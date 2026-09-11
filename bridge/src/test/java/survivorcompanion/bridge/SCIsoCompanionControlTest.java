// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.characters.SurvivorDesc;
import zombie.iso.IsoCell;

/** Real-JAR safety control for the custom IsoPlayer-based companion prototype. */
public final class SCIsoCompanionControlTest {
    private SCIsoCompanionControlTest() {}

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        try {
            return target.getClass().getMethod(name).invoke(target);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtime) throw runtime;
            if (cause instanceof Error error) throw error;
            throw failure;
        }
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static void testRetainedMovementAndPathState(SCNativeCompanion actor) throws Exception {
        // Repeat the previously oscillating 0.54-tile alignment pulse at several
        // decision gaps and game multipliers, using production endpoint clamping.
        for (int gap : new int[] { 6, 12, 24 }) {
            for (float multiplier : new float[] { 0.5f, 1.0f, 3.0f }) {
                float y = 0.70f;
                for (int frame = 0; frame < gap * 4; frame++) {
                    float remaining = Math.abs(0.5f - y);
                    float step = SCNativeCompanion.boundedMovementDistance(
                            0.045f, multiplier, remaining, 0.06f) * multiplier;
                    y += Math.signum(0.5f - y) * step;
                    require(y >= 0.5f - 0.00001f, "retained input overshot doorway center");
                }
                require(Math.abs(y - 0.5f) <= 0.06f,
                        "bounded alignment did not converge across delayed decisions");
            }
        }
        require(!SCNativeCompanion.validMovementTarget(Float.NaN, 1, 0, 0, .06f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 1, 0, .06f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 0, 0, -.1f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 0, 0, .06f, 0),
                "invalid/manual cross-floor target was accepted");
        actor.MoveForward(.045f, 1, 0, 0);
        require(actor.setCompanionMovementTarget(actor.getX() + .2f, actor.getY(), actor.getZ(), .06f, 750),
                "native manual endpoint was not retained");
        var targetField = SCNativeCompanion.class.getDeclaredField("bridgeMoveHasTarget");
        var expiryField = SCNativeCompanion.class.getDeclaredField("bridgeMoveExpiresNanos");
        targetField.setAccessible(true);
        expiryField.setAccessible(true);
        require(targetField.getBoolean(actor), "bounded movement lost its endpoint");
        actor.MoveForward(.045f, 0, 1, 0);
        require(!targetField.getBoolean(actor), "unbounded input reused the previous endpoint");
        expiryField.setLong(actor, System.nanoTime() - 1);
        require(!actor.isMoving() && !actor.hasPendingMovement(),
                "expired unbounded input retained movement or ownership");
        actor.setMoving(false);

        float stableX = actor.getX(), stableY = actor.getY();
        actor.setNextX(stableX);
        actor.setNextY(stableY);
        actor.moveUnmodded(Float.NaN, 0);
        actor.moveUnmodded(0, Float.POSITIVE_INFINITY);
        actor.MoveForward(Float.NaN, 1, 0, 0);
        require(actor.getNextX() == stableX && actor.getNextY() == stableY
                        && actor.getX() == stableX && actor.getY() == stableY,
                "invalid movement reached native physics or translated the actor");
        actor.setNextX(Float.NaN);
        actor.setNextY(Float.NaN);
        var guardPhysics = SCNativeCompanion.class.getDeclaredMethod("guardPhysicsMovement");
        guardPhysics.setAccessible(true);
        guardPhysics.invoke(actor);
        require(actor.getNextX() == stableX && actor.getNextY() == stableY
                        && actor.getCompanionCollisionDiagnostic().contains("invalid=4:"),
                "invalid pending physics vector was not discarded and diagnosed");

        var reconcile = SCNativeCompanion.class.getDeclaredMethod("reconcileBridgePathState");
        reconcile.setAccessible(true);
        var behavior = actor.getPathFindBehavior2();
        behavior.pathNextIsSet = true;
        behavior.pathNextX = 999;
        behavior.pathNextY = 999;
        actor.pathToLocationF(actor.getX() + 2, actor.getY(), actor.getZ());
        require(!behavior.pathNextIsSet, "replacement route retained a stale movement waypoint");
        // Real PFB returns isMovingUsingPathFind=true even with no route yet.
        require(behavior.isMovingUsingPathFind() && !behavior.hasStartedMoving(),
                "pending-path native API fixture changed");
        reconcile.invoke(actor);
        require("pending".equals(actor.getCompanionPathStatus()) && !actor.isPlayerMoving(),
                "pending path incorrectly started the walk animation");
        actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.found;
        reconcile.invoke(actor);
        require("ready".equals(actor.getCompanionPathStatus()) && actor.isPlayerMoving()
                        && !behavior.hasStartedMoving(),
                "ready path cannot bootstrap animation before first deferred movement");
        var stopping = behavior.getClass().getDeclaredField("stopping");
        stopping.setAccessible(true);
        stopping.setBoolean(behavior, true);
        reconcile.invoke(actor);
        require("stopping".equals(actor.getCompanionPathStatus()) && !actor.isPlayerMoving()
                        && actor.hasPendingMovement(),
                "stopping path must drain walk animation without losing native completion ownership");
        behavior.pathNextIsSet = true;
        behavior.cancel();
        reconcile.invoke(actor);
        require(!actor.isPlayerMoving() && !actor.hasPendingMovement()
                        && !behavior.pathNextIsSet && "none".equals(actor.getCompanionPathStatus()),
                "cancelled path retained movement or a continuation point");
        require(!SCNativeCompanion.pathRequestTerminal(true, false, false, false)
                        && SCNativeCompanion.pathRequestTerminal(false, false, false, false)
                        && SCNativeCompanion.pathRequestTerminal(true, true, false, false)
                        && SCNativeCompanion.pathRequestTerminal(true, false, true, false)
                        && SCNativeCompanion.pathRequestTerminal(true, false, false, true),
                "native path pending/terminal handshake changed");

        // The guard consumes the engine's own per-swing latch, which can reset
        // for the next swing/automatic-shot entry without a bridge cooldown.
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, false);
        require(SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED)), "first impact rejected");
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, true);
        require(!SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED)), "duplicate impact admitted");
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, false);
        require(SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED))
                        && !SCNativeCompanion.shouldDriveAttackCollision(false, false),
                "new swing reset or stale-event rejection failed");
        require(SCNativeCompanion.collisionTargetAffected(1.0f, .75f, false, false)
                        && SCNativeCompanion.collisionTargetAffected(0.1f, 0.1f, false, true)
                        && !SCNativeCompanion.collisionTargetAffected(1.0f, 1.0f, false, false)
                        && !SCNativeCompanion.collisionTargetAffected(Float.NaN, Float.NaN,
                                false, false),
                "native target-specific collision evidence changed");
        require(SCNativeCompanion.shouldForceStompCollision(true, true)
                        && !SCNativeCompanion.shouldForceStompCollision(true, false)
                        && !SCNativeCompanion.shouldForceStompCollision(false, true),
                "native stomp flag was not restricted to an armed stomp swing");

        // Build 42 stores attack ownership in several independent flags. A dead
        // target can leave the animation latch active after the ordinary hand-
        // to-hand clear, which makes applyBridgeMovement reject every follow
        // pulse. The bounded stale-release contract must clear all of them.
        actor.setAttackStarted(true);
        actor.setInitiateAttack(true);
        actor.setPerformingAttackAnimation(true);
        actor.setPerformingShoveAnimation(true);
        actor.setPerformingStompAnimation(true);
        actor.setShoveStompAnim(true);
        require(actor.releaseCompanionStaleAttack()
                        && !actor.isAttackStarted()
                        && !actor.isPerformingAttackAnimation()
                        && !actor.isPerformingShoveAnimation()
                        && !actor.isPerformingStompAnimation(),
                "stale dead-target release retained a native attack owner");

        var collision = SCNativeCompanion.class.getDeclaredMethod("driveCompanionAttackCollision", String.class);
        collision.setAccessible(true);
        int serial = actor.getCompanionAttackCollisionSerial();
        require(Boolean.FALSE.equals(collision.invoke(actor, "MeleeSwing"))
                        && actor.getCompanionAttackCollisionSerial() == serial,
                "outgoing attack event advanced impact evidence outside a swing");
        require(actor.getCompanionAttackCollisionHitCount() == 0
                        && actor.getCompanionAttackCollisionTarget() == null
                        && !actor.didCompanionAttackCollisionHitTarget(),
                "rejected attack event fabricated native target-hit evidence");
        actor.getActionContext().reportEvent("EventClimbFence");
        actor.getActionContext().reportEvent("EventHitReaction");
        require(actor.cancelCompanionStuckClimb()
                        && !actor.getActionContext().hasEventOccurred("EventClimbFence")
                        && actor.getActionContext().hasEventOccurred("EventHitReaction"),
                "pending climb cancellation failed or cleared an unrelated native event");
        actor.getActionContext().clearEvent("EventHitReaction");
    }

    @SuppressWarnings("unchecked")
    private static void testNativeTraversalOwnership(SCNativeCompanion actor) throws Exception {
        var machine = actor.getStateMachine();
        var currentField = machine.getClass().getDeclaredField("currentState");
        var subStatesField = machine.getClass().getDeclaredField("subStates");
        currentField.setAccessible(true);
        subStatesField.setAccessible(true);
        Object originalRoot = currentField.get(machine);
        List<Object> slots = (List<Object>) subStatesField.get(machine);
        List<Object> originalSlots = new ArrayList<>(slots);
        Class<?> stateClass = Class.forName("zombie.ai.State");
        var slotConstructor = Class.forName("zombie.ai.StateMachine$SubstateSlot")
                .getDeclaredConstructor(stateClass);
        slotConstructor.setAccessible(true);
        var applyMovement = SCNativeCompanion.class.getDeclaredMethod("applyBridgeMovement");
        applyMovement.setAccessible(true);
        var advancePath = SCNativeCompanion.class.getDeclaredMethod("advanceBridgePath");
        advancePath.setAccessible(true);
        var pathActiveField = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActiveField.setAccessible(true);
        require(!actor.isClimbing(), "native traversal regression requires a false legacy climbing field");
        try {
            slots.clear();
            currentField.set(machine, null);
            require(!actor.isCompanionTraversalActive(), "idle actor falsely owns native traversal");
            for (String stateName : new String[] { "ClimbOverFenceState", "ClimbOverWallState",
                    "ClimbThroughWindowState", "ClimbSheetRopeState", "ClimbDownSheetRopeState",
                    "OpenWindowState", "SmashWindowState" }) {
                Object nativeState = Class.forName("zombie.ai.states." + stateName)
                        .getMethod("instance").invoke(null);
                // Use real runtime state instances and native state-machine
                // slots without invoking world-dependent animation enter hooks.
                currentField.set(machine, nativeState);
                require(actor.isCompanionTraversalActive() && !actor.isClimbing(),
                        stateName + " root ownership was hidden by the legacy climbing field");
                actor.MoveForward(.045f, 1, 0, 0);
                float x = actor.getX(), y = actor.getY();
                applyMovement.invoke(actor);
                require(!actor.hasPendingMovement() && actor.getX() == x && actor.getY() == y,
                        stateName + " allowed retained manual input to compete with native traversal");
                pathActiveField.setBoolean(actor, true);
                actor.setVariable("bPathfind", true);
                actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.failed;
                advancePath.invoke(actor);
                require(actor.getVariableBoolean("bPathfind"),
                        stateName + " allowed native path update to compete with traversal");
                pathActiveField.setBoolean(actor, false);
                actor.setVariable("bPathfind", false);
                currentField.set(machine, null);
                slots.add(slotConstructor.newInstance(nativeState));
                require(actor.isCompanionTraversalActive(), stateName + " child ownership was missed");
                slots.clear();
                require(!actor.isCompanionTraversalActive(), stateName + " ownership survived state exit");
            }
            Object fence = Class.forName("zombie.ai.states.ClimbOverFenceState")
                    .getMethod("instance").invoke(null);
            slots.add(slotConstructor.newInstance(fence));
            actor.setVariable("ClimbingFence", true);
            actor.getActionContext().reportEvent("EventClimbFence");
            require(actor.cancelCompanionTraversal() && !actor.isCompanionTraversalActive()
                            && !actor.getVariableBoolean("ClimbingFence")
                            && !actor.getActionContext().hasEventOccurred("EventClimbFence"),
                    "native child traversal cancellation did not run its exit hook or clear its event");
        } finally {
            currentField.set(machine, originalRoot);
            slots.clear();
            slots.addAll(originalSlots);
            actor.setMoving(false);
        }
        require(actor.getCompanionCollisionDiagnostic().startsWith("move{")
                        && actor.getCompanionCollisionDiagnostic().contains("};collision{"),
                "native physics evidence is not exposed as a read-only diagnostic");
    }

    private static void testZeroDeferredDuplicatePathNode(SCNativeCompanion actor) throws Exception {
        float x = actor.getX(), y = actor.getY(), z = actor.getZ();
        actor.pathToLocationF(x + .3f, y, z);
        var behavior = actor.getPathFindBehavior2();
        var pathField = behavior.getClass().getDeclaredField("path");
        pathField.setAccessible(true);
        var path = (zombie.pathfind.Path) pathField.get(behavior);
        path.getClass().getMethod("clear").invoke(path);
        var add = path.getClass().getMethod("addNode", float.class, float.class, float.class);
        for (float point : new float[] { x - .3f, x, x, x + .3f }) add.invoke(path, point, y, z);
        actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.found;
        actor.setPath2(path);
        var startedMoving = behavior.getClass().getDeclaredField("startedMoving");
        startedMoving.setAccessible(true);
        startedMoving.setBoolean(behavior, true);
        var deferred = actor.getDeferredMovement(new zombie.iso.Vector2());
        require(deferred.x == 0 && deferred.y == 0, "duplicate-node fixture requires zero deferred motion");
        var invalid = SCNativeCompanion.class.getDeclaredField("bridgeInvalidMovementCount");
        invalid.setAccessible(true);
        long before = invalid.getLong(actor);
        behavior.getClass().getMethod("update").invoke(behavior);
        require(invalid.getLong(actor) == before + 1,
                "real native duplicate-node fixture did not reach the zero-deferred invalid vector");
        require(Float.isFinite(actor.getNextX()) && Float.isFinite(actor.getNextY())
                        && actor.getX() == x && actor.getY() == y,
                "native zero-deferred duplicate waypoint corrupted the actor's physical position");
        behavior.cancel();
        actor.setMoving(false);
    }

    private static void testDeferredAccumulatorConsumption(SCNativeCompanion actor) throws Exception {
        Class<?> animationClass = Class.forName("zombie.core.skinnedmodel.animation.AnimationPlayer");
        var constructor = animationClass.getDeclaredConstructor();
        constructor.setAccessible(true);
        Object animation = constructor.newInstance();
        var ownerAnimation = Class.forName("zombie.characters.IsoGameCharacter").getDeclaredField("animPlayer");
        ownerAnimation.setAccessible(true);
        Object original = ownerAnimation.get(actor);
        var accumulatorField = animationClass.getDeclaredField("deferredMovementAccum");
        var snapshotField = animationClass.getDeclaredField("deferredMovement");
        accumulatorField.setAccessible(true);
        snapshotField.setAccessible(true);
        var accumulator = (zombie.iso.Vector2) accumulatorField.get(animation);
        var snapshot = (zombie.iso.Vector2) snapshotField.get(animation);
        var consume = SCNativeCompanion.class.getDeclaredMethod("consumeBridgeDeferredMovement");
        consume.setAccessible(true);
        try {
            ownerAnimation.set(actor, animation);
            snapshot.x = .025f; snapshot.y = -.01f;
            for (int frame = 0; frame < 50; frame++) {
                accumulator.x += .025f; accumulator.y -= .01f;
                consume.invoke(actor);
                require(accumulator.x == 0 && accumulator.y == 0,
                        "unconsumed animation motion accumulated across companion simulation frames");
                require(snapshot.x == .025f && snapshot.y == -.01f,
                        "consuming the accumulator erased the native path's current motion snapshot");
            }
        } finally {
            ownerAnimation.set(actor, original);
        }
    }

    private static void testFloorAttackInputLease(SCNativeCompanion actor, Object localPlayer,
            SCNativeCompanion otherActor) throws Exception {
        Object localFloor = invoke(localPlayer, "isManualFloorAtkButtonDown");
        Object localMelee = invoke(localPlayer, "isMeleeButtonDown");
        require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "companion acquired unrequested local-player attack input");
        require(actor.setCompanionFloorAttackInput(true, false)
                        && actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "floor weapon attack did not retain manual-floor without stomp input");
        require(actor.setCompanionFloorAttackInput(false, false)
                        && !actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "failed floor preflight did not clear owned input");
        require(actor.setCompanionFloorAttackInput(true, true)
                        && actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                "stomp did not retain both manual-floor and melee input");
        Class<?> coreClass = Class.forName("zombie.core.Core");
        Object core = coreClass.getMethod("getInstance").invoke(null);
        boolean autoProne = (Boolean) coreClass.getMethod("isOptionAutoProneAtk").invoke(core);
        var setAutoProne = coreClass.getMethod("setOptionAutoProneAtk", boolean.class);
        var stompDisabled = Class.forName("zombie.ai.states.SwipeStatePlayer")
                .getMethod("isStompingDisabled", Class.forName("zombie.characters.IsoGameCharacter"), boolean.class);
        try {
            setAutoProne.invoke(core, false);
            require(Boolean.FALSE.equals(stompDisabled.invoke(null, actor, true)),
                    "native Swipe entry ignored the actor-owned floor input when player auto-prone was disabled");
            actor.setCompanionFloorAttackInput(false, false);
            require(Boolean.TRUE.equals(stompDisabled.invoke(null, actor, true)),
                    "native Swipe entry retained released floor input");
            actor.setCompanionFloorAttackInput(true, true);
        } finally {
            setAutoProne.invoke(core, autoProne);
        }
        var startDeadline = SCNativeCompanion.class.getDeclaredField("bridgeFloorInputStartDeadline");
        var hardDeadline = SCNativeCompanion.class.getDeclaredField("bridgeFloorInputHardDeadline");
        startDeadline.setAccessible(true);
        hardDeadline.setAccessible(true);
        startDeadline.setLong(actor, System.nanoTime() - 1);
        require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "floor input remained pressed after the bounded start window");

        var machine = actor.getStateMachine();
        var stateField = machine.getClass().getDeclaredField("currentState");
        stateField.setAccessible(true);
        Object originalState = stateField.get(machine);
        try {
            require(actor.setCompanionFloorAttackInput(true, true), "stomp lease failed to rearm");
            stateField.set(machine, zombie.ai.states.SwipeStatePlayer.instance());
            require(actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                    "native swing did not inherit the explicit floor input");
            startDeadline.setLong(actor, System.nanoTime() - 1);
            require(actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                    "pending deadline released input during an accepted native swing");
            require(!actor.setCompanionFloorAttackInput(true, false) && actor.isMeleeButtonDown(),
                    "a later input request changed the stance of an in-flight stomp");
            stateField.set(machine, originalState);
            require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "floor input was not released at native swing exit");
            require(actor.setCompanionFloorAttackInput(true, false), "floor weapon lease failed to rearm");
            stateField.set(machine, zombie.ai.states.SwipeStatePlayer.instance());
            require(actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "floor weapon lease changed into a stomp during native swing");
            hardDeadline.setLong(actor, System.nanoTime() - 1);
            require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "stuck native swing retained manual-floor input past its safety bound");
        } finally {
            stateField.set(machine, originalState);
            actor.setCompanionFloorAttackInput(false, false);
        }
        require(localFloor.equals(invoke(localPlayer, "isManualFloorAtkButtonDown"))
                        && localMelee.equals(invoke(localPlayer, "isMeleeButtonDown"))
                        && !otherActor.isManualFloorAtkButtonDown() && !otherActor.isMeleeButtonDown(),
                "one companion's floor intent changed player or other-companion input");
    }

    @SuppressWarnings({ "rawtypes", "unchecked" })
    private static Object companionDescriptor(boolean female, String forename) throws Exception {
        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Class<?> factoryClass = Class.forName("zombie.characters.SurvivorFactory");
        Class<?> typeClass = Class.forName("zombie.characters.SurvivorFactory$SurvivorType");
        List<String> forenames = (List<String>) factoryClass
                .getField(female ? "FemaleForenames" : "MaleForenames").get(null);
        List<String> surnames = (List<String>) factoryClass.getField("Surnames").get(null);
        if (forenames.isEmpty()) forenames.add(forename);
        if (surnames.isEmpty()) surnames.add("Companion");
        Object neutral = Enum.valueOf((Class<? extends Enum>) typeClass, "Neutral");
        Object descriptor = factoryClass.getMethod("CreateSurvivor", typeClass, boolean.class)
                .invoke(null, neutral, female);
        descriptorClass.getMethod("setForename", String.class).invoke(descriptor, forename);
        descriptorClass.getMethod("setSurname", String.class).invoke(descriptor, "Companion");
        return descriptor;
    }

    public static void main(String[] args) throws Exception {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-isocompanion-control");
        fileSystemClass.getMethod("init").invoke(fileSystem);
        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        managerClass.getMethod("RunLua", String.class).invoke(null,
                "media/lua/shared/Definitions/HairOutfitDefinitions.lua");
        Class.forName("zombie.core.skinnedmodel.population.HairStyles").getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.BeardStyles").getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.OutfitManager").getMethod("init").invoke(null);
        Object hairDefinitions = Class.forName("zombie.characters.HairOutfitDefinitions")
                .getField("instance").get(null);
        hairDefinitions.getClass().getMethod("checkDirty").invoke(hairDefinitions);
        Class<?> colorClass = Class.forName("zombie.core.ImmutableColor");
        Object color = colorClass.getConstructor(float.class, float.class, float.class)
                .newInstance(0.3f, 0.2f, 0.1f);
        List<Object> commonHairColors = (List<Object>) Class.forName("zombie.characters.SurvivorDesc")
                .getField("HairCommonColors").get(null);
        if (commonHairColors.isEmpty()) commonHairColors.add(color);
        Object populationTemplates = Class.forName("zombie.core.skinnedmodel.population.PopTemplateManager")
                .getField("instance").get(null);
        for (String[] fixture : new String[][] {
                { "maleSkins", "MaleBody01" }, { "femaleSkins", "FemaleBody01" }
        }) {
            List<String> skins = (List<String>) populationTemplates.getClass()
                    .getField(fixture[0]).get(populationTemplates);
            if (skins.isEmpty()) skins.add(fixture[1]);
        }
        Class<?> soundManagerClass = Class.forName("zombie.SoundManager");
        soundManagerClass.getField("instance").set(null,
                Class.forName("zombie.DummySoundManager").getConstructor().newInstance());

        Class<?> cellClass = Class.forName("zombie.iso.IsoCell");
        Object cell = cellClass.getConstructor(int.class, int.class).newInstance(64, 64);
        Class<?> sliceClass = Class.forName("zombie.iso.SliceY");
        Class<?> squareClass = Class.forName("zombie.iso.IsoGridSquare");
        Object square = squareClass.getConstructor(cellClass, sliceClass, int.class, int.class, int.class)
                .newInstance(cell, sliceClass.getConstructor().newInstance(), 0, 0, 0);
        squareClass.getField("solidFloor").setBoolean(square, true);
        Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
        Object world = worldClass.getConstructor().newInstance();
        worldClass.getField("instance").set(null, world);
        worldClass.getField("currentCell").set(world, cell);

        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Object localDescriptor = descriptorClass.getConstructor().newInstance();
        descriptorClass.getMethod("setForename", String.class).invoke(localDescriptor, "Control");
        descriptorClass.getMethod("setSurname", String.class).invoke(localDescriptor, "Player");
        descriptorClass.getMethod("setFemale", boolean.class).invoke(localDescriptor, false);
        Object visual = descriptorClass.getMethod("getHumanVisual").invoke(localDescriptor);
        visual.getClass().getMethod("setHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setHairModel", String.class).invoke(visual, "Bald");
        visual.getClass().getMethod("setBeardModel", String.class).invoke(visual, "");
        visual.getClass().getMethod("setSkinTextureName", String.class).invoke(visual, "MaleBody01");

        Class<?> playerClass = Class.forName("zombie.characters.IsoPlayer");
        boolean coopPvpBefore = (Boolean) playerClass.getMethod("getCoopPVP").invoke(null);
        playerClass.getMethod("setCoopPVP", boolean.class).invoke(null, false);
        Object localPlayer = playerClass.getConstructor(cellClass, descriptorClass,
                        int.class, int.class, int.class, boolean.class)
                .newInstance(cell, localDescriptor, 0, 0, 0, false);
        localPlayer.getClass().getMethod("setCurrentSquare", squareClass).invoke(localPlayer, square);
        playerClass.getMethod("setLocalPlayer", int.class, playerClass)
                .invoke(null, 0, localPlayer);
        playerClass.getMethod("setInstance", playerClass).invoke(null, localPlayer);
        Class<?> cameraClass = Class.forName("zombie.iso.IsoCamera");
        Class<?> gameCharacterClass = Class.forName("zombie.characters.IsoGameCharacter");
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, localPlayer);
        Object[] slotsBefore = ((Object[]) playerClass.getField("players").get(null)).clone();
        int countBefore = playerClass.getField("numPlayers").getInt(null);
        Object singletonBefore = playerClass.getMethod("getInstance").invoke(null);
        Object cameraBefore = cameraClass.getMethod("getCameraCharacter").invoke(null);
        Class<?> companionClass = Class.forName("survivorcompanion.bridge.SCNativeCompanion");
        Object firstDescriptor = companionDescriptor(false, "First");
        ArrayList<Event> eventList = new ArrayList<>();
        HashMap<String, Event> eventMap = new HashMap<>();
        LuaEventManager.getEvents(eventList, eventMap);
        Event createLiving = eventMap.get("OnCreateLivingCharacter");
        require(createLiving != null, "OnCreateLivingCharacter event is unavailable");
        int callbacksBefore = createLiving.callbacks.size();
        createLiving.callbacks.add(null);
        Object actor;
        try {
            actor = SCBridge.constructCompanion((SurvivorDesc) firstDescriptor,
                    (IsoCell) cell, 0, 0, 0);
            require(createLiving.callbacks.size() == callbacksBefore + 1
                            && createLiving.callbacks.get(callbacksBefore) == null,
                    "constructor guard did not restore the exact callback sequence");
        } finally {
            createLiving.callbacks.remove(callbacksBefore);
        }
        actor.getClass().getMethod("setCurrentSquare", squareClass).invoke(actor, square);
        Object secondDescriptor = companionDescriptor(true, "Second");
        Object secondActor = SCBridge.constructCompanion((SurvivorDesc) secondDescriptor,
                (IsoCell) cell, 0, 0, 0);
        secondActor.getClass().getMethod("setCurrentSquare", squareClass).invoke(secondActor, square);

        // A dedicated probe covers the complete live spawn registration. The
        // headless fixture has no initialized GameEntityManager unregister
        // path, so detach its square references directly after the assertion
        // instead of mixing that fixture limitation into the teardown test.
        Object membershipDescriptor = companionDescriptor(false, "Membership");
        Object membershipActor = SCBridge.constructCompanion((SurvivorDesc) membershipDescriptor,
                (IsoCell) cell, 0, 0, 0);
        membershipActor.getClass().getMethod("setCurrentSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("setSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("setMovingSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("addToWorld").invoke(membershipActor);
        require((Boolean) invoke(membershipActor, "isExistInTheWorld"),
                "native companion was not registered in its square moving-object list");
        membershipActor.getClass().getMethod("removeFromSquare").invoke(membershipActor);
        membershipActor.getClass().getMethod("setMovingSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });
        membershipActor.getClass().getMethod("setCurrentSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });
        membershipActor.getClass().getMethod("setSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });

        require(playerClass.isInstance(actor), "companion is not an IsoPlayer subtype");
        require((Boolean) invoke(actor, "isNpc"), "companion is not in NPC mode");
        require(!(Boolean) invoke(actor, "isLocalPlayer"), "companion became local");
        require("player".equals(invoke(actor, "getCompanionActionGroupName"))
                        && !String.valueOf(invoke(actor,
                                "getCompanionActionStateName")).isBlank(),
                "companion did not expose its player ActionContext safely");
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, true);
        actor.getClass().getMethod("MoveForward", float.class, float.class, float.class, float.class)
                .invoke(actor, 0.045f, 1.0f, 0.0f, 1.0f);
        require((Boolean) invoke(actor, "isMoving"),
                "companion lost its generic NPC movement state to IsoPlayer input semantics");
        require((Boolean) invoke(actor, "isPlayerMoving"),
                "player animation graph did not receive companion movement state");
        require(((SCNativeCompanion) actor).hasPendingMovement(),
                "companion did not retain movement for the native physics window");
        ((SCNativeCompanion) actor).synchronizePlayerLocomotion();
        Method variableFloat = actor.getClass().getMethod("getVariableFloat",
                String.class, float.class);
        require(((Number) variableFloat.invoke(actor, "WalkSpeed", -1.0f)).floatValue() > 0.0f
                        && ((Number) variableFloat.invoke(actor, "RunSpeed", -1.0f)).floatValue() > 0.0f
                        && ((Number) variableFloat.invoke(actor, "IdleSpeed", -1.0f)).floatValue() > 0.0f,
                "player locomotion speed scalars remained frozen at zero");
        require(((SCNativeCompanion) actor).setCompanionTacticalMovement(true, 0.55f, -0.55f),
                "NPC aiming control did not retain tactical movement");
        require((Boolean) invoke(actor, "isAiming")
                        && ((SCNativeCompanion) actor).isCompanionTacticalMovement()
                        && Math.abs(((Number) variableFloat.invoke(actor,
                                "DeltaX", 0.0f)).floatValue() - 0.55f) < 0.001f
                        && Math.abs(((Number) variableFloat.invoke(actor,
                                "DeltaY", 0.0f)).floatValue() + 0.55f) < 0.001f,
                "stock IsoPlayer diagonal backward animation inputs were not retained");
        require(((SCNativeCompanion) actor).setCompanionTacticalMovement(false, 0.0f, 0.0f)
                        && !(Boolean) invoke(actor, "isAiming")
                        && !((SCNativeCompanion) actor).isCompanionTacticalMovement(),
                "tactical movement state did not clear cleanly");
        actor.getClass().getMethod("setIsAiming", boolean.class).invoke(actor, true);
        ((SCNativeCompanion) actor).synchronizePlayerLocomotion();
        require((Boolean) invoke(actor, "isAiming")
                        && !((SCNativeCompanion) actor).isCompanionTacticalMovement(),
                "locomotion synchronization cancelled an ordinary combat aiming state");
        actor.getClass().getMethod("setIsAiming", boolean.class).invoke(actor, false);
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, false);
        require(!(Boolean) invoke(actor, "isMoving"),
                "companion movement state did not stop cleanly");
        require(!(Boolean) invoke(actor, "isPlayerMoving"),
                "player animation graph retained movement after stop");
        require(!((SCNativeCompanion) actor).hasPendingMovement(),
                "stopping the companion left a stale native movement request");
        // A clear-line vanilla path normally selects input-owned player movement.
        // The companion has no local input, so its override must retain the native
        // path state instead of walking in place with only animation flags set.
        actor.getClass().getMethod("pathToLocationF", float.class, float.class, float.class)
                .invoke(actor, 2.5f, 0.5f, 0.0f);
        var pathMoveRequested = SCNativeCompanion.class.getDeclaredField("bridgeMoveRequested");
        pathMoveRequested.setAccessible(true);
        require((Boolean) actor.getClass().getMethod("getVariableBoolean", String.class)
                        .invoke(actor, "bPathfind")
                        && !(Boolean) invoke(actor, "isPlayerMoving")
                        && ((SCNativeCompanion) actor).hasPendingMovement()
                        && !pathMoveRequested.getBoolean(actor),
                "a pathfinder-owned search animated forward before movement began");
        invoke(invoke(actor, "getPathFindBehavior2"), "cancel");
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, false);
        require(!(Boolean) actor.getClass().getMethod("getVariableBoolean", String.class)
                        .invoke(actor, "bPathfind"),
                "external path stop retained vanilla's bPathfind animation state");
        var pathActive = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActive.setAccessible(true);
        var pathStarted = SCNativeCompanion.class.getDeclaredField("bridgePathStartedThisRun");
        pathStarted.setAccessible(true);
        pathActive.setBoolean(actor, true);
        require(!(Boolean) invoke(actor, "isPlayerMoving"),
                "pending native path search reported player locomotion");
        pathStarted.setBoolean(actor, true);
        require((Boolean) invoke(actor, "isPlayerMoving"),
                "started native path state recursed through IsoPlayer movement callbacks");
        pathStarted.setBoolean(actor, false);
        pathActive.setBoolean(actor, false);
        require(!SCNativeCompanion.shouldApplyCompanionAim(true, false, false),
                "ordinary forward locomotion can be reversed by a stale combat aim target");
        require(SCNativeCompanion.shouldApplyCompanionAim(true, true, false),
                "tactical strafe lost its target-facing ownership");
        require(SCNativeCompanion.shouldApplyCompanionAim(true, false, true),
                "an active attack lost the target angle required by its hit arc");
        require(SCNativeCompanion.shouldApplyCompanionAim(false, false, false),
                "a stationary companion no longer tracks its combat target");
        require(SCNativeCompanion.shouldBridgeMovementOwnFacing(true, false, false),
                "ordinary manual movement did not own its forward direction");
        require(!SCNativeCompanion.shouldBridgeMovementOwnFacing(true, true, false),
                "manual movement stole facing from tactical strafe");
        require(!SCNativeCompanion.shouldBridgeMovementOwnFacing(true, false, true),
                "manual movement stole facing from an active attack");
        testRetainedMovementAndPathState((SCNativeCompanion) actor);
        testNativeTraversalOwnership((SCNativeCompanion) actor);
        testZeroDeferredDuplicatePathNode((SCNativeCompanion) actor);
        testDeferredAccumulatorConsumption((SCNativeCompanion) actor);
        testFloorAttackInputLease((SCNativeCompanion) actor, localPlayer, (SCNativeCompanion) secondActor);
        require(((Number) invoke(actor, "getPlayerNum")).intValue() == 3,
                "companion did not retain reserved non-local index");
        require(((Number) invoke(secondActor, "getPlayerNum")).intValue() == 3
                        && (Boolean) invoke(secondActor, "isNpc")
                        && !(Boolean) invoke(secondActor, "isLocalPlayer"),
                "second companion did not retain isolated NPC state");
        require(SCNativeCompanion.hasGenericCharacterUpdate(),
                "version-pinned generic IsoGameCharacter update is unavailable");
        for (String component : new String[] {
                "getBodyDamage", "getMoodles", "getXp", "getEmitter", "getVisual",
                "getInventory", "getPathFindBehavior2", "getModData" }) {
            require(invoke(actor, component) != null, "component is null: " + component);
        }
        SCNativeCompanion.LocalPlayerState rollback = SCNativeCompanion.LocalPlayerState.capture();
        require(rollback != null && rollback.matches(), "local-player rollback snapshot failed");
        Object[] mutableSlots = (Object[]) playerClass.getField("players").get(null);
        mutableSlots[1] = actor;
        playerClass.getField("numPlayers").setInt(null, 2);
        playerClass.getMethod("setInstance", playerClass).invoke(null, actor);
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, actor);
        require(!rollback.matches() && rollback.restore() && rollback.matches(),
                "local-player state mutation was not repaired transactionally");

        SCNativeCompanion.LocalPlayerState ownershipGuard =
                SCNativeCompanion.LocalPlayerState.capture();
        playerClass.getMethod("setInstance", playerClass).invoke(null, actor);
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, actor);
        require(ownershipGuard.slotsMatch() && !ownershipGuard.ownersMatch()
                        && ownershipGuard.restore() && ownershipGuard.matches(),
                "companion ownership contamination was not rejected and repaired");

        Class.forName("zombie.iso.areas.isoregion.IsoRegions").getMethod("init").invoke(null);
        boolean updateReachedRenderBoundary = false;
        for (Object candidate : new Object[] { actor, secondActor }) {
            try {
                invoke(candidate, "update");
                String bridgeFailure = String.valueOf(invoke(candidate, "getBridgeFailure"));
                if (!bridgeFailure.isEmpty()) {
                    boolean renderContextBoundary = bridgeFailure.contains("RenderContextQueueException")
                            && bridgeFailure.contains("No GLCapabilities");
                    boolean headlessAnimationBoundary = bridgeFailure.contains("NullPointerException")
                            && bridgeFailure.contains("AnimationPlayer.setModel");
                    require(renderContextBoundary || headlessAnimationBoundary,
                            "companion contained an unexpected native update failure: " + bridgeFailure);
                    updateReachedRenderBoundary = true;
                } else {
                    require(!(Boolean) invoke(candidate, "isDead"),
                            "companion died during native update");
                }
            } catch (RuntimeException failure) {
                if (failure.getClass().getName().equals("zombie.core.opengl.RenderContextQueueException")
                        && String.valueOf(failure.getMessage()).contains("No GLCapabilities")) {
                    updateReachedRenderBoundary = true;
                } else {
                    throw failure;
                }
            }
        }

        Object[] slotsAfter = (Object[]) playerClass.getField("players").get(null);
        require(countBefore == playerClass.getField("numPlayers").getInt(null),
                "companion changed IsoPlayer.numPlayers");
        require(Arrays.equals(slotsBefore, slotsAfter), "companion changed IsoPlayer.players");
        require(singletonBefore == playerClass.getMethod("getInstance").invoke(null),
                "companion changed the IsoPlayer singleton");
        require(cameraBefore == cameraClass.getMethod("getCameraCharacter").invoke(null),
                "companion changed the IsoCamera character");
        require(Arrays.stream(slotsAfter).noneMatch(value -> value == actor),
                "companion occupied a local-player slot");
        require(Arrays.stream(slotsAfter).noneMatch(value -> value == secondActor),
                "second companion occupied a local-player slot");
        require(slotsAfter[0] == localPlayer, "companion displaced local player 0");
        Method addOwned = SCBridge.class.getDeclaredMethod("addOwned", SCNativeCompanion.class);
        addOwned.setAccessible(true);
        addOwned.invoke(null, actor);
        addOwned.invoke(null, secondActor);
        require(SCBridge.getOwnedCount() == 2
                        && SCBridge.isCompanion(actor) && SCBridge.isCompanion(secondActor),
                "bridge identity ownership did not retain two companions");
        require((Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "owned NPCs did not enable the vanilla IsoPlayer hit gate");
        Class<?> movingObjectClass = Class.forName("zombie.iso.IsoMovingObject");
        boolean playerMayHitCompanion = (Boolean) Class.forName("zombie.CombatManager")
                .getMethod("checkPVP", movingObjectClass, movingObjectClass, boolean.class)
                .invoke(null, localPlayer, actor, true);
        require(playerMayHitCompanion,
                "CombatManager still rejected player weapon hits against an owned companion");
        Object deathSquare = invoke(actor, "getCurrentSquare");
        actor.getClass().getMethod("setHealth", float.class).invoke(actor, 0.0f);
        actor.getClass().getMethod("setOnDeathDone", boolean.class).invoke(actor, true);
        var corpseReady = SCNativeCompanion.class.getDeclaredField("corpseReady");
        corpseReady.setAccessible(true);
        corpseReady.setBoolean(actor, true);
        require(SCBridge.retireDead((SCNativeCompanion) actor)
                        && SCBridge.getOwnedCount() == 1 && !SCBridge.isCompanion(actor)
                        && invoke(actor, "getCurrentSquare") == deathSquare,
                "finalized death retirement removed the corpse actor from its world square");
        require((Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "retiring one NPC disabled player damage while another remained owned");
        Object cleanupDescriptor = companionDescriptor(false, "Cleanup");
        SCNativeCompanion cleanupActor = SCBridge.constructCompanion(
                (SurvivorDesc) cleanupDescriptor, (IsoCell) cell, 0, 0, 0);
        cleanupActor.setCurrentSquare((zombie.iso.IsoGridSquare) square);
        cleanupActor.setSquare((zombie.iso.IsoGridSquare) square);
        cleanupActor.setMovingSquare((zombie.iso.IsoGridSquare) square);
        addOwned.invoke(null, cleanupActor);
        SCBridge.failNextCleanupStepForTests("current-square");
        require(!SCBridge.remove(cleanupActor)
                        && SCBridge.isCompanion(cleanupActor)
                        && SCBridge.getOwnedCount() == 2
                        && SCBridge.getCleanupPendingCount() == 1
                        && !SCBridge.getCleanupFailure(cleanupActor).isEmpty(),
                "failed teardown lost native ownership or cleanup evidence");
        require(SCBridge.retryCleanup(cleanupActor)
                        && !SCBridge.isCompanion(cleanupActor)
                        && SCBridge.getCleanupPendingCount() == 0
                        && SCBridge.getOwnedCount() == 1,
                "native cleanup retry did not commit ownership removal");
        require(SCBridge.removeAll() && SCBridge.getOwnedCount() == 0
                        && !SCBridge.isCompanion(secondActor),
                "bridge teardown did not clear all owned companion references: "
                        + SCBridge.getLastFailure());
        require(!(Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "last NPC teardown did not restore the previous vanilla hit-gate state");
        playerClass.getMethod("setCoopPVP", boolean.class).invoke(null, coopPvpBefore);
        System.out.println("ISO_COMPANION_CONTROL_PASS actors=2 index=3 components=true local-state=unchanged"
                + " movement=true animation-scalars=true rollback=true transient-ownership=true ownership=true pvp-hit-gate=true permadeath=true teardown=true"
                + " cleanup-retry=true update="
                + (updateReachedRenderBoundary ? "contained-render-boundary" : "complete"));
    }
}
