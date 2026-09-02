// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import se.krka.kahlua.vm.KahluaTable;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import zombie.Lua.LuaEventManager;
import zombie.ai.AIBrainPlayerControlVars;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.component.AIComponent;
import zombie.characters.action.ActionState;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.pathfind.PathFindBehavior2;
import zombie.pathfind.PolygonalMap2;
import zombie.core.skinnedmodel.advancedanimation.AnimEvent;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.animation.AnimationTrack;

/** A non-local human actor backed by Build 42's complete player character runtime. */
public final class SCNativeCompanion extends IsoPlayer {
    public static final int RESERVED_NON_LOCAL_PLAYER_INDEX = 3;
    private static final Method GENERIC_CHARACTER_UPDATE = resolveGenericCharacterUpdate();
    private static final Method PLAYER_VEHICLE_UPDATE = resolvePlayerVehicleUpdate();
    private static final Method PLAYER_ACTION_GROUP_CHECK = resolvePlayerActionGroupCheck();
    private static final Method COMBAT_MANAGER_INSTANCE = resolveStatic("zombie.CombatManager", "getInstance");
    private static final Method SWIPE_STATE_INSTANCE = resolveStatic("zombie.ai.states.SwipeStatePlayer", "instance");
    private static final Method ATTACK_COLLISION_CHECK = resolveAttackCollisionCheck();
    private static final Method GET_USE_HAND_WEAPON = resolveNoArg(IsoGameCharacter.class, "getUseHandWeapon");
    private static final Method GET_ATTACK_TYPE = resolveNoArg(IsoPlayer.class, "getAttackType");
    private static volatile String RUNTIME_CONTRACT_FAILURE_FOR_TESTS = "";
    private static final int MIN_SPEECH_DISPLAY_MILLIS = 4_000;
    private static final int MAX_SPEECH_DISPLAY_MILLIS = 30_000;

    private volatile boolean bridgeDisabled;
    private volatile String bridgeFailure = "";
    private volatile boolean bridgeDeathStarted;
    private volatile boolean corpseReady;
    private volatile boolean bridgeMoving;
    private volatile boolean bridgeMoveRequested;
    private volatile boolean bridgePathActive;
    private volatile float bridgeMoveDistance;
    private volatile float bridgeMoveX;
    private volatile float bridgeMoveY;
    private volatile float bridgeMoveSoundDelta;
    private volatile boolean bridgeTacticalMovement;
    private volatile float bridgeStrafeX;
    private volatile float bridgeStrafeY;
    private volatile int bridgeNextSpeechDisplayMillis;
    private volatile String bridgeSpeechLine;
    private volatile long bridgeSpeechRefreshUntilNanos;
    private volatile long bridgePostUpdateCount;
    private volatile String bridgePostUpdateDiagnostic = "not_run";
    private volatile zombie.iso.IsoMovingObject bridgeAimTarget;
    private boolean genericUpdateActive;

    public SCNativeCompanion(SurvivorDesc descriptor, IsoCell cell, int x, int y, int z) {
        super(cell, descriptor, x, y, z, false);
        playerIndex = RESERVED_NON_LOCAL_PLAYER_INDEX;
        serverPlayerIndex = -1;
        setNpc(true);
        descriptor.setInstance(this);
        addOnDiedListener((character, body) -> corpseReady = body != null, false);
    }

    @Override
    public boolean isLocalPlayer() {
        return false;
    }

    /** Kahlua-safe diagnostic view of the otherwise unexposed ActionContext. */
    public String getCompanionActionGroupName() {
        if (getActionContext() == null || getActionContext().getGroup() == null) return "";
        String name = getActionContext().getGroup().getName();
        return name == null ? "" : name;
    }

    /** Kahlua-safe diagnostic view of the active root player-action state. */
    public String getCompanionActionStateName() {
        if (getActionContext() == null) return "";
        String name = getActionContext().getCurrentStateName();
        return name == null ? "" : name;
    }

    /** The transition the stock player graph would select on its next update. */
    public String getCompanionNextActionStateName() {
        if (getActionContext() == null) return "";
        ActionState state = getActionContext().peekNextState();
        return state == null || state.getName() == null ? "" : state.getName();
    }

    /** Whether all Build 42 transition conditions currently permit melee. */
    public boolean canCompanionTransitionToMelee() {
        return getActionContext() != null
                && getActionContext().canTransitionToState("melee");
    }

    /**
     * Compact live diagnostic proving whether the engine-owned postupdate pass
     * consumed a companion attack request through the ordinary player action
     * graph. This is intentionally read-only and safe to expose to Kahlua.
     */
    /**
     * addToWorld()/setCurrentSquare() only reliably register a manually
     * constructed non-local actor into the cell's deferred add list, so the
     * MovingObjectUpdateScheduler (which iterates IsoCell.getObjectList()) never
     * ticks it while it is stationary. Force live object-list membership so the
     * companion is simulated every frame like a normal character.
     */
    public boolean ensureScheduled() {
        if (bridgeDisabled) return false;
        try {
            zombie.iso.IsoCell cell = getCell();
            if (cell == null) return false;
            java.util.Set<zombie.iso.IsoMovingObject> list = cell.getObjectList();
            if (list == null) return false;
            if (!list.contains(this)) list.add(this);
            return list.contains(this);
        } catch (RuntimeException | LinkageError failure) {
            return false;
        }
    }

    public String getCompanionPostUpdateDiagnostic() {
        return bridgePostUpdateDiagnostic + ",count=" + bridgePostUpdateCount;
    }

    @Override
    public void postupdate() {
        String beforeState = getCompanionActionStateName();
        String beforeNext = getCompanionNextActionStateName();
        boolean beforeMelee = canCompanionTransitionToMelee();
        boolean beforeInitiate = isInitiateAttack();
        boolean beforeVariable = getVariableBoolean("initiateAttack");
        // Re-point at the aim target immediately before the engine advances the
        // swing animation and fires its AttackCollisionCheck, so the hit arc sees
        // the companion facing the target.
        applyCompanionAim();
        super.postupdate();
        bridgePostUpdateCount++;
        bridgePostUpdateDiagnostic = "before=" + beforeState
                + ",next=" + beforeNext
                + ",canMelee=" + beforeMelee
                + ",initiate=" + beforeInitiate
                + ",variable=" + beforeVariable
                + ",after=" + getCompanionActionStateName()
                + ",afterInitiate=" + isInitiateAttack()
                + ",performing=" + isPerformingAttackAnimation();
    }

    /**
     * Build 42's SwipeStatePlayer.OnAnimEvent_AttackCollisionCheck resolves a
     * melee/ranged hit only for a local player (in multiplayer the server does
     * it for everyone else). A non-local companion therefore swings, finds valid
     * targets and animates, but never applies damage in single player. Detect the
     * same swing event and drive the collision check ourselves. CombatManager's
     * hit application is gated on isLocalPlayer()||isNpc(), and this actor is an
     * NPC, so the hit lands. This is the sole place the companion applies a swing.
     */
    @Override
    public void OnAnimEvent(AnimLayer layer, AnimationTrack track, AnimEvent event) {
        super.OnAnimEvent(layer, track, event);
        if (event != null && "AttackCollisionCheck".equals(event.eventName)) {
            driveCompanionAttackCollision(event.parameterValue);
        }
    }

    private void driveCompanionAttackCollision(String attackTypeName) {
        if (bridgeDisabled || getVehicle() != null) return;
        if (COMBAT_MANAGER_INSTANCE == null || ATTACK_COLLISION_CHECK == null
                || SWIPE_STATE_INSTANCE == null || GET_USE_HAND_WEAPON == null
                || GET_ATTACK_TYPE == null) {
            return;
        }
        try {
            Object weapon = GET_USE_HAND_WEAPON.invoke(this);
            if (weapon == null) return;
            // The AttackType that gates CombatManager's stance filter is carried
            // by the swing's AttackCollisionCheck anim event (its parameter is the
            // enum id, e.g. "MeleeSwing"), not by the actor's getAttackType()
            // (which is DEFAULT/MISS off the collision path). With the wrong type
            // the hit loop skips the target. Resolve it from the event parameter;
            // only fall back to the actor's value if the event carries no name.
            Object attackType = resolveAttackType(attackTypeName);
            if (attackType == null) {
                attackType = GET_ATTACK_TYPE.invoke(this);
            }
            Object combatManager = COMBAT_MANAGER_INSTANCE.invoke(null);
            Object swipeState = SWIPE_STATE_INSTANCE.invoke(null);
            if (combatManager == null || swipeState == null) return;
            // Re-point at the current target: the swing animation may have turned
            // the actor, and attackCollisionCheck rebuilds the hit-info list
            // against the actor's facing before applying the hit.
            applyCompanionAim();
            ATTACK_COLLISION_CHECK.invoke(combatManager, this, weapon, swipeState, attackType);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError ignored) {
            // Fail closed: no swing damage rather than an update-breaking throw.
        }
    }

    /**
     * IsoGameCharacter.isMoving() deliberately reports false for an IsoPlayer
     * outside a narrow local attack-animation case. That is correct for a
     * keyboard-controlled player, but it cancels every generic NPC movement
     * request made by this non-local subtype. Own the movement flag here while
     * still mirroring it into the base character for physics and animation.
     */
    @Override
    public boolean isMoving() {
        return isBridgeLocomotionActive();
    }

    /**
     * The player action group does not read IsoGameCharacter's {@code bMoving}
     * callback. It reads IsoPlayer's separate {@code isMoving} callback, which
     * delegates to isPlayerMoving(). The local-player controller normally owns
     * that field; this non-local actor must expose the bridge/path state instead.
     */
    @Override
    public boolean isPlayerMoving() {
        return isBridgeLocomotionActive();
    }

    @Override
    public void setMoving(boolean moving) {
        if (!genericUpdateActive) {
            bridgeMoving = moving && getVehicle() == null;
            if (!bridgeMoving) {
                bridgeMoveRequested = false;
                bridgePathActive = false;
            }
        }
        super.setMoving(moving && getVehicle() == null);
    }

    @Override
    public void pathToLocationF(float x, float y, float z) {
        super.pathToLocationF(x, y, z);
        bridgePathActive = getVehicle() == null && !bridgeDisabled;
    }

    @Override
    public void pathToLocation(int x, int y, int z) {
        super.pathToLocation(x, y, z);
        bridgePathActive = getVehicle() == null && !bridgeDisabled;
    }

    @Override
    public void pathToCharacter(IsoGameCharacter target) {
        super.pathToCharacter(target);
        bridgePathActive = target != null && getVehicle() == null && !bridgeDisabled;
    }

    @Override
    public void pathToSound(int x, int y, int z) {
        super.pathToSound(x, y, z);
        bridgePathActive = getVehicle() == null && !bridgeDisabled;
    }

    /**
     * Lua decisions run after moving-object postupdate. Calling the vanilla
     * implementation there only changes nextX/nextY until the next preupdate
     * resets them. Retain the validated vector and apply it from update(),
     * which is inside the engine's preupdate/update/postupdate physics window.
     */
    @Override
    public void MoveForward(float distance, float x, float y, float soundDelta) {
        if (genericUpdateActive) {
            super.MoveForward(distance, x, y, soundDelta);
            return;
        }
        if (getVehicle() != null) {
            suspendBridgeLocomotion();
            return;
        }
        bridgeMoveDistance = distance;
        bridgeMoveX = x;
        bridgeMoveY = y;
        bridgeMoveSoundDelta = soundDelta;
        bridgeMoveRequested = true;
        bridgeMoving = true;
        super.setMoving(true);
    }

    /**
     * Build 42 stores NPC aiming in AIComponent rather than the ordinary
     * IsoGameCharacter field. Mirror every weapon-ready request into that
     * authoritative control record so the player strafe state can activate.
     */
    @Override
    public void setIsAiming(boolean aiming) {
        super.setIsAiming(aiming);
        try {
            AIBrainPlayerControlVars controls = getECSComponent(AIComponent.class)
                    .getHumanControlVars();
            controls.aiming = aiming;
        } catch (RuntimeException | LinkageError ignored) {
            // The superclass constructor runs before setNpc(true) installs the
            // AI component. The ordinary character field is sufficient there.
        }
    }

    /**
     * Select the stock IsoPlayer backward/diagonal/side-step animations while
     * translation remains owned by the bridge. Values are local to the facing
     * direction: X is lateral and Y is forward (negative Y walks backward).
     */
    public boolean setCompanionTacticalMovement(boolean enabled, float strafeX, float strafeY) {
        bridgeTacticalMovement = enabled;
        bridgeStrafeX = enabled ? clampUnit(strafeX) : 0.0f;
        bridgeStrafeY = enabled ? clampUnit(strafeY) : 0.0f;
        if (enabled) {
            applyCompanionTacticalMovement();
        } else {
            setIsAiming(false);
            setVariable("DeltaX", 0.0f);
            setVariable("DeltaY", 0.0f);
        }
        return isAiming() == enabled;
    }

    public boolean isCompanionTacticalMovement() {
        return bridgeTacticalMovement;
    }

    /**
     * Test a short manual movement against the same continuous polygon map used
     * by Build 42 for players and vehicles. IsoGameCharacter.canStandAt() uses
     * the ignore-doors flag, so it is not sufficient for a companion step.
     */
    public boolean isCompanionMovementClear(float toX, float toY, float toZ) {
        if (getVehicle() != null) return false;
        int level = (int)Math.floor(toZ);
        if ((int)Math.floor(getZ()) != level) return false;
        return !PolygonalMap2.instance.lineClearCollide(
                getX(), getY(), toX, toY, level, this, false, true);
    }

    /**
     * Supplies a one-shot real-time display target for the next actor-owned
     * overhead line. Lua derives it from line length. Bounds prevent a broken
     * mod call from creating a permanent bubble.
     */
    public boolean setCompanionSpeechDisplayMillis(int milliseconds) {
        bridgeNextSpeechDisplayMillis = Math.max(MIN_SPEECH_DISPLAY_MILLIS,
                Math.min(MAX_SPEECH_DISPLAY_MILLIS, milliseconds));
        return true;
    }

    @Override
    public void addLineChatElement(String line) {
        super.addLineChatElement(line);
        if (line == null || line.isBlank()) {
            bridgeSpeechLine = null;
            bridgeSpeechRefreshUntilNanos = 0L;
            bridgeNextSpeechDisplayMillis = 0;
            return;
        }
        int requested = bridgeNextSpeechDisplayMillis > 0
                ? bridgeNextSpeechDisplayMillis : 9_000;
        bridgeNextSpeechDisplayMillis = 0;
        bridgeSpeechLine = line;
        // Keep the line fully readable for the requested real-time interval.
        // The stock fade begins only after this deadline, so a high game-time
        // multiplier cannot shorten the configured reading window.
        bridgeSpeechRefreshUntilNanos = System.nanoTime() + requested * 1_000_000L;
    }

    private void refreshCompanionSpeech() {
        String line = bridgeSpeechLine;
        if (line == null) return;
        long current = System.nanoTime();
        if (current >= bridgeSpeechRefreshUntilNanos) {
            bridgeSpeechLine = null;
            bridgeSpeechRefreshUntilNanos = 0L;
            return;
        }
        String active = getSayLine();
        if (active != null && !active.equals(line)) {
            bridgeSpeechLine = null;
            bridgeSpeechRefreshUntilNanos = 0L;
            return;
        }
        // SayDebug detects the identical newest line and only refreshes its
        // internal clock; it neither adds duplicate rows nor changes its font.
        super.SayDebug(0, line);
    }

    /**
     * Continuously point the companion straight at its combat target, like a
     * player's mouse aim. Build 42's CombatManager hit arc reads
     * getDirectionAngle (the angle of forwardDirection), and the ordinary
     * per-frame update resets that vector, so a swing set up from Lua misses a
     * target the companion appears to face. Lua sets the target while engaging
     * and clears it when combat ends; a target that leaves the world is dropped.
     */
    public void setCompanionAimTarget(zombie.iso.IsoMovingObject target) {
        bridgeAimTarget = target;
    }

    public boolean hasCompanionAimTarget() {
        return bridgeAimTarget != null;
    }

    private void applyCompanionAim() {
        zombie.iso.IsoMovingObject target = bridgeAimTarget;
        if (target == null || getVehicle() != null) return;
        if (!target.isExistInTheWorld()) {
            bridgeAimTarget = null;
            return;
        }
        float dx = target.getX() - getX();
        float dy = target.getY() - getY();
        float length = (float) Math.sqrt(dx * dx + dy * dy);
        if (length > 0.0001f) {
            setForwardDirection(dx / length, dy / length);
        }
    }

    private void applyCompanionTacticalMovement() {
        if (bridgeTacticalMovement) {
            setIsAiming(true);
            setVariable("DeltaX", bridgeStrafeX);
            setVariable("DeltaY", bridgeStrafeY);
            setRunning(false);
            setSprinting(false);
        }
    }

    /**
     * Preserve the generic character-death contract without running IsoPlayer's
     * local-player UI, music, drag-slot, or save-file deletion side effects.
     */
    @Override
    public void OnDeath() {
        if (bridgeDeathStarted) return;
        bridgeDeathStarted = true;
        StopAllActionQueue();
        if (isAsleep()) setAsleep(false);
        dropHandItems();
        if (shouldBecomeZombieAfterDeath()) forceAwake();
        if (getMoodles() != null) getMoodles().Update();
        LuaEventManager.triggerEvent("OnCharacterDeath", this);
    }

    @Override
    public void update() {
        if (bridgeDisabled) {
            return;
        }
        LocalPlayerState localState = LocalPlayerState.capture();
        if (localState == null) {
            disableBridge("unexpected local-player slot layout");
            return;
        }
        try {
            boolean seated = getVehicle() != null;
            if (seated) suspendBridgeLocomotion();
            synchronizePlayerLocomotion();
            genericUpdateActive = true;
            if (seated) {
                updatePlayerVehicleState();
            } else {
                // Keep the on-foot player action group active every frame, not
                // only on the vehicle-exit frame. checkActionGroup() only
                // selects the ActionGroup (no local input), and ActionContext
                // .update() already runs through this actor's postupdate chain
                // (IsoPlayer.postupdate -> ... -> IsoGameCharacter
                // .postUpdateInternal -> postUpdateAnimating). Without the
                // combat-capable group set, that context can never transition
                // into ai.states.SwipeStatePlayer, so a DoAttack-initiated
                // swing plays its animation (driven by the initiateAttack
                // variable) but SwipeStatePlayer.OnAnimEvent_AttackCollisionCheck
                // never fires and the melee hit is never resolved.
                updatePlayerActionGroup();
            }
            updateGenericCharacter();
            genericUpdateActive = false;
            // The vanilla visibility fade never raises this non-local actor's
            // render alpha, so it stays 0: the companion is invisible even while
            // present on the map (seen only on the minimap), and the
            // MovingObjectUpdateScheduler treats a <0.25-alpha actor as barely
            // visible and collapses its simulation level until it effectively
            // stops ticking. Force full opacity after the generic update so the
            // companion is both visible and fully simulated.
            setAlphaAndTarget(1.0f);
            applyCompanionAim();
            refreshCompanionSpeech();
            if (getVehicle() == null) applyBridgeMovement();
        } catch (RuntimeException | LinkageError failure) {
            genericUpdateActive = false;
            boolean repaired = localState.restore();
            playerIndex = RESERVED_NON_LOCAL_PLAYER_INDEX;
            serverPlayerIndex = -1;
            disableBridge("native update failed: " + failure.getClass().getSimpleName()
                    + cleanMessage(failure.getMessage()) + cleanLocation(failure)
                    + (repaired ? "" : "; local-player rollback failed"));
            return;
        }

        // A generic character update must never borrow local-player ownership.
        boolean actorStateIntact = playerIndex == RESERVED_NON_LOCAL_PLAYER_INDEX
                && serverPlayerIndex == -1 && isNpc();
        boolean slotsIntact = localState.slotsMatch();
        boolean ownersIntact = localState.ownersMatch();
        boolean repaired = localState.restore();
        if (!actorStateIntact || !slotsIntact || !ownersIntact || !repaired) {
            playerIndex = RESERVED_NON_LOCAL_PLAYER_INDEX;
            serverPlayerIndex = -1;
            setNpc(true);
            disableBridge("native update isolation failure: actor=" + actorStateIntact
                    + ", slots=" + slotsIntact + ", owners=" + ownersIntact
                    + ", rollback=" + repaired);
        }
    }

    private void applyBridgeMovement() {
        if (getVehicle() != null || !bridgeMoveRequested || !bridgeMoving) return;
        super.setMoving(true);
        super.MoveForward(bridgeMoveDistance, bridgeMoveX, bridgeMoveY, bridgeMoveSoundDelta);
    }

    /**
     * Mirror the part of IsoPlayer.updateInternal2() that owns the player
     * locomotion animation variables. WalkSpeed, RunSpeed and IdleSpeed all
     * default to zero, so omitting this call enters the right state but freezes
     * the animation while the physics body keeps moving (the moonwalk bug).
     */
    void synchronizePlayerLocomotion() {
        boolean moving = isBridgeLocomotionActive();
        isPlayerMoving = moving;
        super.setMoving(moving);
        applyCompanionTacticalMovement();
        updateMovementRates();
    }

    private boolean isBridgeLocomotionActive() {
        if (getVehicle() != null) return false;
        // PathFindBehavior2.shouldBeMoving() calls actor.shouldBeTurning(),
        // which reaches IsoPlayer.isPlayerMoving() and therefore this method
        // again. Own path activity explicitly instead of querying either the
        // behavior or its callback-backed animation variable here.
        return bridgeMoving || bridgeMoveRequested || bridgePathActive;
    }

    /**
     * Start a native nearest-of-many request without exposing PolygonalMap2 or
     * Kahlua internals to gameplay Lua.  A nearest request cannot safely use
     * pathToAux()'s single-target direct-line shortcut, so it always enters the
     * ordinary player pathfinding animation state.
     */
    public boolean bridgePathToNearest(KahluaTable locations,
            float hintX, float hintY, float hintZ) {
        if (locations == null || getVehicle() != null || bridgeDisabled) return false;
        try {
            PathFindBehavior2 behavior = getPathFindBehavior2();
            if (behavior == null) return false;
            behavior.pathToNearestTable(locations);
            setVariable("bPathfind", true);
            super.setMoving(false);
            bridgePathActive = true;
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return false;
        }
    }

    private void suspendBridgeLocomotion() {
        bridgeMoveRequested = false;
        bridgeMoving = false;
        bridgePathActive = false;
        bridgeTacticalMovement = false;
        bridgeStrafeX = 0.0f;
        bridgeStrafeY = 0.0f;
        try {
            PathFindBehavior2 behavior = getPathFindBehavior2();
            if (behavior != null) behavior.cancel();
        } catch (RuntimeException | LinkageError ignored) {}
        super.setMoving(false);
        setRunning(false);
        setSprinting(false);
        setSneaking(false);
        setIsAiming(false);
        setVariable("DeltaX", 0.0f);
        setVariable("DeltaY", 0.0f);
    }

    private void updatePlayerVehicleState() {
        if (PLAYER_VEHICLE_UPDATE == null) return;
        try {
            PLAYER_VEHICLE_UPDATE.invoke(this);
        } catch (IllegalAccessException failure) {
            throw new IllegalStateException("player vehicle update is inaccessible", failure);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtimeFailure) throw runtimeFailure;
            if (cause instanceof Error error) throw error;
            throw new IllegalStateException("player vehicle update failed", cause);
        }
    }

    private void updatePlayerActionGroup() {
        if (PLAYER_ACTION_GROUP_CHECK == null) return;
        try {
            PLAYER_ACTION_GROUP_CHECK.invoke(this);
        } catch (IllegalAccessException failure) {
            throw new IllegalStateException("player action-group check is inaccessible", failure);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtimeFailure) throw runtimeFailure;
            if (cause instanceof Error error) throw error;
            throw new IllegalStateException("player action-group check failed", cause);
        }
    }

    /**
     * IsoPlayer.update() is a local-player controller: in Build 42.20.4 it
     * assigns the global player/camera owners, fires OnPlayerUpdate and reads
     * player input even for an NPC.  Invoke IsoGameCharacter's private,
     * non-virtual update body instead.  This retains character physics, state
     * machines, wounds, timed actions and animation without entering the
     * local-player controller or re-entering Lua through OnPlayerUpdate.
     */
    private void updateGenericCharacter() {
        if (GENERIC_CHARACTER_UPDATE == null) {
            throw new IllegalStateException("generic IsoGameCharacter update is unavailable");
        }
        try {
            GENERIC_CHARACTER_UPDATE.invoke(this);
        } catch (IllegalAccessException failure) {
            throw new IllegalStateException("generic IsoGameCharacter update is inaccessible", failure);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtimeFailure) throw runtimeFailure;
            if (cause instanceof Error error) throw error;
            throw new IllegalStateException("generic IsoGameCharacter update failed", cause);
        }
    }

    private static Method resolveGenericCharacterUpdate() {
        try {
            Method method = IsoGameCharacter.class.getDeclaredMethod("updateInternal");
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    private static Method resolvePlayerVehicleUpdate() {
        try {
            Method method = IsoPlayer.class.getDeclaredMethod("updateWhileInVehicle");
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    private static Method resolvePlayerActionGroupCheck() {
        try {
            Method method = IsoPlayer.class.getDeclaredMethod("checkActionGroup");
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    private static Method resolveStatic(String className, String methodName) {
        try {
            Method method = Class.forName(className).getMethod(methodName);
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    private static Method resolveNoArg(Class<?> owner, String methodName) {
        try {
            Method method = owner.getMethod(methodName);
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private static Object resolveAttackType(String name) {
        if (name == null || name.isEmpty()) return null;
        try {
            Class<?> attackType = Class.forName("zombie.AttackType");
            if (!attackType.isEnum()) return null;
            // The anim-event parameter (e.g. "MeleeSwing") corresponds to the
            // enum's id, which toString() returns lowercased ("meleeswing") --
            // not the constant name ("MELEE_SWING"). Try the constant name first,
            // then a case-insensitive match on the id.
            try {
                return Enum.valueOf((Class<? extends Enum>) attackType, name);
            } catch (IllegalArgumentException notAConstantName) {
                for (Object value : attackType.getEnumConstants()) {
                    if (name.equalsIgnoreCase(String.valueOf(value))) return value;
                }
                return null;
            }
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    private static Method resolveAttackCollisionCheck() {
        try {
            Class<?> combatManager = Class.forName("zombie.CombatManager");
            Class<?> handWeapon = Class.forName("zombie.inventory.types.HandWeapon");
            Class<?> swipeState = Class.forName("zombie.ai.states.SwipeStatePlayer");
            Class<?> attackType = Class.forName("zombie.AttackType");
            Method method = combatManager.getMethod("attackCollisionCheck",
                    IsoGameCharacter.class, handWeapon, swipeState, attackType);
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    /**
     * Fail-closed contract for every private Build 42 method used by the
     * native actor.  Checking only the generic update method allowed a bridge
     * to report ready and then silently skip vehicle or animation work after
     * a game update renamed one of the other methods.
     */
    static String runtimeContractFailure() {
        String injected = RUNTIME_CONTRACT_FAILURE_FOR_TESTS;
        if (!injected.isEmpty()) return injected;
        String failure = reflectedMethodFailure(GENERIC_CHARACTER_UPDATE,
                IsoGameCharacter.class, "updateInternal");
        if (!failure.isEmpty()) return failure;
        failure = reflectedMethodFailure(PLAYER_VEHICLE_UPDATE,
                IsoPlayer.class, "updateWhileInVehicle");
        if (!failure.isEmpty()) return failure;
        return reflectedMethodFailure(PLAYER_ACTION_GROUP_CHECK,
                IsoPlayer.class, "checkActionGroup");
    }

    private static String reflectedMethodFailure(Method method, Class<?> owner, String name) {
        if (method == null) return owner.getSimpleName() + "." + name + " is unavailable";
        if (method.getDeclaringClass() != owner || !method.getName().equals(name)
                || method.getParameterCount() != 0 || method.getReturnType() != void.class) {
            return owner.getSimpleName() + "." + name + " has an incompatible signature";
        }
        try {
            if (!method.trySetAccessible()) {
                return owner.getSimpleName() + "." + name + " is inaccessible";
            }
        } catch (RuntimeException failure) {
            return owner.getSimpleName() + "." + name + " access failed: "
                    + failure.getClass().getSimpleName();
        }
        return "";
    }

    /** Package-private real-JAR test seam for the version-pinned update path. */
    static boolean hasGenericCharacterUpdate() {
        return runtimeContractFailure().isEmpty();
    }

    /** Package-private negative readiness seam; never exposed through Kahlua. */
    static void failRuntimeContractForTests(String failure) {
        RUNTIME_CONTRACT_FAILURE_FOR_TESTS = failure == null ? "" : failure.trim();
    }

    /** Package-private real-JAR test seam for the deferred physics request. */
    boolean hasPendingMovement() {
        return bridgeMoveRequested || bridgePathActive;
    }

    public boolean isBridgeHealthy() {
        return !bridgeDisabled && bridgeFailure.isEmpty();
    }

    public String getBridgeFailure() {
        return bridgeFailure;
    }

    public boolean isCorpseReady() {
        return corpseReady;
    }

    public void disableBridge(String reason) {
        bridgeFailure = cleanReason(reason);
        bridgeDisabled = true;
        try { setCompanionTacticalMovement(false, 0.0f, 0.0f); }
        catch (RuntimeException | LinkageError ignored) {}
        try { setMoving(false); } catch (RuntimeException | LinkageError ignored) {}
        try { setRunning(false); } catch (RuntimeException | LinkageError ignored) {}
        try { setSprinting(false); } catch (RuntimeException | LinkageError ignored) {}
        try { setSneaking(false); } catch (RuntimeException | LinkageError ignored) {}
    }

    /** Package-private so the real-JAR control can prove rollback independently. */
    static final class LocalPlayerState {
        private final IsoPlayer[] slots;
        private final IsoPlayer[] values;
        private final int playerCount;
        private final IsoPlayer singleton;
        private final IsoGameCharacter cameraCharacter;

        private LocalPlayerState(IsoPlayer[] slots, IsoPlayer[] values,
                int playerCount, IsoPlayer singleton, IsoGameCharacter cameraCharacter) {
            this.slots = slots;
            this.values = values;
            this.playerCount = playerCount;
            this.singleton = singleton;
            this.cameraCharacter = cameraCharacter;
        }

        static LocalPlayerState capture() {
            IsoPlayer[] current = IsoPlayer.players;
            if (current == null || current.length != 4) return null;
            return new LocalPlayerState(current, current.clone(),
                    IsoPlayer.numPlayers, IsoPlayer.getInstance(), IsoCamera.getCameraCharacter());
        }

        boolean slotsMatch() {
            if (IsoPlayer.players != slots || slots.length != values.length
                    || IsoPlayer.numPlayers != playerCount) return false;
            for (int index = 0; index < values.length; index++) {
                if (slots[index] != values[index]) return false;
            }
            return true;
        }

        boolean ownersMatch() {
            return IsoPlayer.getInstance() == singleton
                    && IsoCamera.getCameraCharacter() == cameraCharacter;
        }

        boolean matches() {
            return slotsMatch() && ownersMatch();
        }

        boolean restore() {
            try {
                if (IsoPlayer.players != slots || slots.length != values.length) return false;
                System.arraycopy(values, 0, slots, 0, values.length);
                IsoPlayer.numPlayers = playerCount;
                IsoPlayer.setInstance(singleton);
                IsoCamera.setCameraCharacter(cameraCharacter);
                return matches();
            } catch (RuntimeException | LinkageError failure) {
                return false;
            }
        }
    }

    private static String cleanReason(String reason) {
        String clean = reason == null ? "unknown native companion failure" : reason.trim();
        if (clean.isEmpty()) clean = "unknown native companion failure";
        return clean.length() > 240 ? clean.substring(0, 240) : clean;
    }

    private static String cleanMessage(String message) {
        if (message == null || message.isBlank()) return "";
        String clean = message.replaceAll("[\\r\\n\\t]+", " ").trim();
        if (clean.length() > 160) clean = clean.substring(0, 160);
        return ": " + clean;
    }

    private static String cleanLocation(Throwable failure) {
        StackTraceElement[] trace = failure == null ? null : failure.getStackTrace();
        if (trace == null || trace.length == 0) return "";
        StringBuilder location = new StringBuilder(" at ");
        int included = 0;
        for (StackTraceElement element : trace) {
            String className = element.getClassName();
            if (included == 0 || className.startsWith("zombie.")) {
                if (included > 0) location.append(" <- ");
                location.append(className).append('.').append(element.getMethodName())
                        .append(':').append(element.getLineNumber());
                included++;
                if (included == 4) break;
            }
        }
        return location.toString();
    }

    private static float clampUnit(float value) {
        if (!Float.isFinite(value)) return 0.0f;
        return Math.max(-1.0f, Math.min(1.0f, value));
    }
}
