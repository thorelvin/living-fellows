// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicLong;

import org.joml.Vector3f;

import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.LuaClosure;
import zombie.MainThread;
import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.ai.states.AttackState;
import zombie.characters.IsoGameCharacter;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.BodyDamage.BodyPart;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.SurvivorDesc;
import zombie.characters.WornItems.WornItem;
import zombie.characters.WornItems.WornItems;
import zombie.characters.action.ActionContext;
import zombie.characters.action.ActionGroup;
import zombie.characters.action.ActionState;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.SurvivorFactory;
import zombie.core.Core;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.core.skinnedmodel.ModelManager;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Clothing;
import zombie.inventory.types.DrainableComboItem;
import zombie.inventory.types.Food;
import zombie.inventory.types.HandWeapon;
import zombie.inventory.types.Key;
import zombie.iso.IsoCell;
import zombie.iso.IsoCamera;
import zombie.iso.IsoDirections;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.PlayerCamera;
import zombie.iso.areas.IsoRoom;
import zombie.pathfind.VehiclePoly;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.GridSquareEdge;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.objects.IsoWindow;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteGrid;
import zombie.seating.SeatingManager;
import zombie.util.list.PZArrayList;
import zombie.vehicles.BaseVehicle;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.worldMap.UIWorldMap;
import zombie.worldMap.WorldMap;

/** Narrow Lua-facing authority for creating and owning native companions. */
public final class SCBridge {
    public static final String PROTOCOL = "42.21-isocompanion-24";
    public static final int ITEM_FACT_FOOD = 1;
    public static final int ITEM_FACT_DRAINABLE = 1 << 1;
    public static final int ITEM_FACT_HAND_WEAPON = 1 << 2;
    public static final int ITEM_FACT_MAGAZINE = 1 << 3;
    public static final int ITEM_FACT_KEY = 1 << 4;
    public static final int BODY_BLEEDING = 1;
    public static final int BODY_BITTEN = 1 << 1;
    public static final int BODY_INFECTED_WOUND = 1 << 2;
    public static final int BODY_BANDAGED = 1 << 3;
    public static final int BODY_BANDAGE_DIRTY = 1 << 4;
    public static final int BODY_SCRATCHED = 1 << 5;
    public static final int BODY_CUT = 1 << 6;
    public static final int BODY_DEEP = 1 << 7;
    public static final int BODY_BURNED = 1 << 8;
    public static final int BODY_FRACTURED = 1 << 9;
    public static final int BODY_BULLET = 1 << 10;
    public static final int BODY_GLASS = 1 << 11;
    /**
     * Core.getVersionNumber() reports the public release family (42.21) in a
     * live game, even though this bridge is compiled and signature-tested
     * against the installed 42.21.0 runtime. Keep both spellings explicit so
     * the live display label cannot incorrectly disable an otherwise verified
     * bridge, while unrelated game families still fail closed.
     */
    public static final String SUPPORTED_GAME_VERSION = "42.21";
    public static final String COMPILED_GAME_VERSION = "42.21.0";

    private static final int MAX_NAME_LENGTH = 48;
    private static final int MAX_OUTFIT_LENGTH = 96;
    private static final int MAX_SPAWN_REQUESTS = 8;
    private static final float MAX_VIEW_OFFSET = 16.0f;
    private static final int EXPEDITION_ZOOM_STEPS = 10;
    private static final long INVALID_SPAWN_REQUEST = -1L;
    private static final Set<SCNativeCompanion> OWNED = Collections.newSetFromMap(
            new IdentityHashMap<>());
    private static final Map<SCNativeCompanion, String> CLEANUP_FAILURES =
            new IdentityHashMap<>();
    private static final Map<Long, SpawnRequest> SPAWN_REQUESTS = new LinkedHashMap<>();
    private static final AtomicLong NEXT_SPAWN_REQUEST = new AtomicLong(1L);
    /**
     * Build 42's zombie action graph gates both entry to and continuation of
     * the stock attack state on this private visibility bit. The normal player
     * visibility pass maintains it only for entries in IsoPlayer.players[];
     * owned companions deliberately never occupy those local-player slots.
     * Resolve the exact 42.20.4 field once and fail closed if the installed
     * runtime no longer matches the signature test.
     */
    private static final Field ZOMBIE_CAN_SEE_TARGET = resolveZombieCanSeeTarget();
    // CombatManager.checkPVP treats every IsoPlayer subclass as a co-op player,
    // including our non-local NPCs. In single-player it rejects that target when
    // IsoPlayer.coopPvp is false, before melee and firearm hit-info is created.
    // The bridge already rejects split-screen/multiple local players, so retain
    // and enable the vanilla flag only while at least one owned NPC exists.
    private static boolean coopPvpOverrideActive;
    private static boolean coopPvpBeforeOwnership;
    // The game-wide co-op PvP switch must remain enabled for hostile or
    // unrecruited NPCs. The user's ally-protection choice is a separate target
    // gate in SCNativeCompanion.Hit, applied only to the primary local player.
    private static volatile boolean protectRecruitedCompanions;
    /**
     * MainThread.queueInvokeOnMainThread executes inline when called by the game
     * thread. Lua also runs on that thread, so calling it directly from the
     * exposed request method would still construct IsoPlayer inside a
     * LuaJavaInvoker frame. This daemon only performs the queue hand-off; all
     * game object work remains on Project Zomboid's main thread.
     */
    private static final ExecutorService SPAWN_HANDOFF = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "SurvivorCompanion-spawn-handoff");
        thread.setDaemon(true);
        return thread;
    });
    private static volatile String lastFailure = "";
    // Only the second local view is changed. Its previous auto-zoom setting is
    // kept until the view closes, including a return, death or world exit.
    private static Core expeditionZoomCore;
    private static boolean expeditionAutoZoomBefore;
    /**
     * Package-private fault controls are intentionally unreachable through the
     * public/Kahlua bridge. They let the real-game-JAR control prove that every
     * destructive transaction retains ownership until native cleanup has been
     * verified, including failures that the headless engine cannot naturally
     * produce on demand.
     */
    private static final Set<String> FAILURE_STEPS_FOR_TESTS = new HashSet<>();
    private static volatile CountDownLatch SPAWN_PAUSED_FOR_TESTS;
    private static volatile CountDownLatch SPAWN_RESUME_FOR_TESTS;

    /**
     * IsoPlayer's constructor fires the local/mod-facing
     * OnCreateLivingCharacter event before the subclass constructor body can
     * run. Third-party callbacks can re-enter Kahlua during native companion
     * construction and corrupt the global ReturnValues pool. Temporarily mute
     * only this event and restore its exact callback sequence immediately.
     */
    private static final class MutedLivingCharacterEvent implements AutoCloseable {
        private final ArrayList<LuaClosure> callbacks;
        private final ArrayList<LuaClosure> saved;

        private MutedLivingCharacterEvent(ArrayList<LuaClosure> callbacks) {
            this.callbacks = callbacks;
            this.saved = new ArrayList<>(callbacks);
            callbacks.clear();
        }

        static MutedLivingCharacterEvent open() {
            ArrayList<Event> events = new ArrayList<>();
            HashMap<String, Event> byName = new HashMap<>();
            LuaEventManager.getEvents(events, byName);
            Event event = byName.get("OnCreateLivingCharacter");
            if (event == null || event.callbacks == null) {
                throw new IllegalStateException("OnCreateLivingCharacter event is unavailable");
            }
            return new MutedLivingCharacterEvent(event.callbacks);
        }

        @Override
        public void close() {
            callbacks.clear();
            callbacks.addAll(saved);
            if (callbacks.size() != saved.size()) {
                throw new IllegalStateException("OnCreateLivingCharacter callbacks were not restored");
            }
            for (int index = 0; index < saved.size(); index++) {
                if (callbacks.get(index) != saved.get(index)) {
                    throw new IllegalStateException("OnCreateLivingCharacter callback order changed");
                }
            }
        }
    }

    private enum SpawnState { PENDING, READY, FAILED, CLEANUP_PENDING }

    private static final class SpawnRequest {
        private final long id;
        private final IsoGridSquare square;
        private final String forename;
        private final String surname;
        private final boolean female;
        private final String outfit;
        private final boolean bare;
        private SpawnState state = SpawnState.PENDING;
        private SCNativeCompanion actor;
        private String failure = "";
        private boolean cancelRequested;

        private SpawnRequest(long id, IsoGridSquare square, String forename,
                String surname, boolean female, String outfit, boolean bare) {
            this.id = id;
            this.square = square;
            this.forename = forename;
            this.surname = surname;
            this.female = female;
            this.outfit = outfit;
            this.bare = bare;
        }
    }

    private SCBridge() {}

    private static Field resolveZombieCanSeeTarget() {
        try {
            Field field = IsoZombie.class.getDeclaredField("canSeeTarget");
            if (field.getType() != boolean.class) return null;
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            return null;
        }
    }

    public static String getProtocol() {
        return PROTOCOL;
    }

    public static String getDetectedGameVersion() {
        try {
            String value = Core.getInstance().getVersionNumber();
            return value == null ? "unavailable" : value.trim();
        } catch (RuntimeException | LinkageError failure) {
            return "unavailable";
        }
    }

    public static String checkReady() {
        if (!SCBootstrap.isStarted()) SCBootstrap.start();
        if (!SCBootstrap.isReady()) {
            return SCBootstrap.getStatus();
        }
        String contractFailure = SCNativeCompanion.runtimeContractFailure();
        if (!contractFailure.isEmpty()) {
            return "native bridge runtime contract failed: " + contractFailure;
        }
        String version = getDetectedGameVersion();
        if (!isSupportedGameVersion(version)) {
            return "requires Project Zomboid " + SUPPORTED_GAME_VERSION
                    + " (bridge build " + COMPILED_GAME_VERSION + "); detected " + version;
        }
        if (GameClient.client || GameServer.server) {
            return "SurvivorCompanion native actors are single-player only";
        }
        if (!MainThread.isRunning()) {
            return "Project Zomboid main-thread queue is not running";
        }
        return localPlayerIsolationFailure();
    }

    static boolean isSupportedGameVersion(String version) {
        if (version == null) return false;
        String clean = version.trim();
        return clean.equals(SUPPORTED_GAME_VERSION) || clean.equals(COMPILED_GAME_VERSION);
    }

    public static String getLastFailure() {
        return lastFailure;
    }

    public static long getBootstrapGeneration() {
        return SCBootstrap.getGeneration();
    }

    /** Monotonic duration clock; its origin must never be used for saved timestamps. */
    public static double nowMsPrecise() {
        return System.nanoTime() / 1_000_000.0;
    }

    /**
     * Moves only the local view centre in world-tile coordinates. This does not
     * replace the camera character, publish a companion in a local-player slot,
     * or touch PlayerCamera's independent right-click aim offset.
     */
    public static boolean setViewOffset(float dx, float dy) {
        lastFailure = "";
        if (!onGameThread()) {
            return failBoolean("setViewOffset requires the game thread");
        }
        if (!Float.isFinite(dx) || !Float.isFinite(dy)) {
            return failBoolean("view offset must be finite");
        }
        try {
            PlayerCamera camera = IsoCamera.cameras[0];
            if (camera == null) return failBoolean("player camera is unavailable");
            double length = Math.hypot(dx, dy);
            if (length > MAX_VIEW_OFFSET) {
                float scale = (float) (MAX_VIEW_OFFSET / length);
                dx *= scale;
                dy *= scale;
            }
            camera.deferedX = dx;
            camera.deferedY = dy;
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("view offset failed" + messageSuffix(failure.getMessage()));
        }
    }

    /** Restores the ordinary player-centred view without touching aim lean. */
    public static boolean clearViewOffset() {
        lastFailure = "";
        if (!onGameThread()) {
            return failBoolean("clearViewOffset requires the game thread");
        }
        try {
            PlayerCamera camera = IsoCamera.cameras[0];
            if (camera == null) return failBoolean("player camera is unavailable");
            camera.deferedX = 0.0f;
            camera.deferedY = 0.0f;
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("view offset clear failed" + messageSuffix(failure.getMessage()));
        }
    }

    /** Read the joined Living Fellows view's target and enabled zoom range. */
    public static boolean readExpeditionZoom(KahluaTable out) {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("expedition zoom requires the game thread");
        if (out == null) return failBoolean("expedition zoom output is unavailable");
        if (!hasJoinedExpeditionView()) {
            return failBoolean("Living Fellows second view has not joined");
        }
        try {
            Core core = Core.getInstance();
            if (core == null || !core.isZoomEnabled()) {
                return failBoolean("expedition zoom is disabled");
            }
            Object buffer = expeditionZoomBuffer(core);
            float target = expeditionTargetZoom(buffer);
            float min = expeditionZoomBound(buffer, "getMinZoom");
            float max = expeditionZoomBound(buffer, "getMaxZoom");
            if (!validExpeditionZoomRange(target, min, max)) {
                return failBoolean("expedition zoom range is unavailable");
            }
            put(out, "target", target);
            put(out, "min", min);
            put(out, "max", max);
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            return failBoolean("expedition zoom read failed" + messageSuffix(failure.getMessage()));
        }
    }

    /** Ten evenly spaced positions across the player's enabled zoom range. */
    public static boolean setExpeditionZoomStep(int step) {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("expedition zoom requires the game thread");
        if (step < 1 || step > EXPEDITION_ZOOM_STEPS) {
            return failBoolean("expedition zoom step must be from 1 to 10");
        }
        if (!hasJoinedExpeditionView()) {
            return failBoolean("Living Fellows second view has not joined");
        }
        try {
            Core core = Core.getInstance();
            if (core == null || !core.isZoomEnabled()) {
                return failBoolean("expedition zoom is disabled");
            }
            if (expeditionZoomCore != null && expeditionZoomCore != core) {
                return failBoolean("expedition zoom belongs to a previous game session");
            }
            Object buffer = expeditionZoomBuffer(core);
            float current = expeditionTargetZoom(buffer);
            float min = expeditionZoomBound(buffer, "getMinZoom");
            float max = expeditionZoomBound(buffer, "getMaxZoom");
            if (!validExpeditionZoomRange(current, min, max)) {
                return failBoolean("expedition zoom range is unavailable");
            }
            float target = min + (max - min) * (step - 1) / (EXPEDITION_ZOOM_STEPS - 1);
            boolean firstChange = expeditionZoomCore == null;
            if (firstChange) {
                expeditionAutoZoomBefore = core.getAutoZoom(1);
                core.setAutoZoom(1, false);
                expeditionZoomCore = core;
            }
            try {
                buffer.getClass().getMethod("setTargetZoom", int.class, float.class)
                        .invoke(buffer, 1, target);
            } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
                if (firstChange) restoreExpeditionZoom();
                throw failure;
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            return failBoolean("expedition zoom update failed" + messageSuffix(failure.getMessage()));
        }
    }

    /** Idempotent even after slot 1 has been released or the world has exited. */
    public static boolean restoreExpeditionZoom() {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("expedition zoom restore requires the game thread");
        Core core = expeditionZoomCore;
        if (core == null) return true;
        try {
            core.setAutoZoom(1, expeditionAutoZoomBefore);
            expeditionZoomCore = null;
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("expedition zoom restore failed" + messageSuffix(failure.getMessage()));
        }
    }

    private static boolean hasJoinedExpeditionView() {
        IsoPlayer[] slots = IsoPlayer.players;
        return SCSplitScreenProbe.acceptsCurrentLayout(slots)
                && slots[1] != null && SCSplitScreenProbe.isLeader(slots[1]);
    }

    private static Object expeditionZoomBuffer(Core core) throws ReflectiveOperationException {
        Field field = Core.class.getDeclaredField("offscreenBuffer");
        field.setAccessible(true);
        Object buffer = field.get(core);
        if (buffer == null
                || !buffer.getClass().getName().equals("zombie.core.textures.MultiTextureFBO2")) {
            throw new IllegalStateException("Build 42 zoom framebuffer is unavailable");
        }
        return buffer;
    }

    private static float expeditionTargetZoom(Object buffer) throws ReflectiveOperationException {
        Method read = buffer.getClass().getMethod("getTargetZoom", int.class);
        return ((Number) read.invoke(buffer, 1)).floatValue();
    }

    private static float expeditionZoomBound(Object buffer, String methodName)
            throws ReflectiveOperationException {
        // Core.getMinZoom/getMaxZoom return display-scale values multiplied by
        // Core.tileScale / 2. MultiTextureFBO2.setTargetZoom takes raw zoom
        // factors, so read the matching raw bounds from that same FBO.
        Method read = buffer.getClass().getMethod(methodName);
        return ((Number) read.invoke(buffer)).floatValue();
    }

    private static boolean validExpeditionZoomRange(float target, float min, float max) {
        return Float.isFinite(target) && Float.isFinite(min) && Float.isFinite(max)
                && min > 0.0f && max > min && target > 0.0f;
    }

    private static boolean onGameThread() {
        return Thread.currentThread() == MainThread.mainThread;
    }

    /**
     * Temporarily raises only this companion's 3D model while the settled
     * pillow-tile bed pose is rendered. The actor's physical Z and bed action
     * stay under native engine control. Pass zero to clear the visual lift.
     */
    public static boolean setOnBedRenderLift(SCNativeCompanion actor,
            int milliTiles) {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("bed render lift requires the game thread");
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        if (milliTiles < 0 || milliTiles > 250) {
            return failBoolean("bed render lift must be 0 to 250 milli-tiles");
        }
        if (milliTiles == 0) {
            actor.clearBridgeOnBedRenderLift();
            return actor.getBridgeOnBedRenderLift() == 0.0f
                    || failBoolean("bed render lift did not clear");
        }
        try {
            if (actor.isDead() || !actor.isOnBed()
                    || !actor.getVariableBoolean("OnBedStarted")) {
                return failBoolean("native companion has not settled into the bed action");
            }
            float x = actor.getX(), y = actor.getY(), z = actor.getZ();
            if (!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)
                    || actor.getCell() == null) {
                return failBoolean("bed render lift has invalid world coordinates");
            }
            int tileX = (int) Math.floor(x);
            int tileY = (int) Math.floor(y);
            int tileZ = (int) Math.floor(z);
            IsoGridSquare pillow = actor.getCell().getGridSquare(tileX, tileY, tileZ);
            if (pillow == null || pillow.getChunk() == null
                    || actor.getCurrentSquare() != pillow || actor.square != pillow
                    || actor.getMovingSquare() != pillow || actor.getSquare() != pillow
                    || !actor.isExistInTheWorld()
                    || countIdentity(pillow.getMovingObjects(), actor) != 1) {
                return failBoolean("bed render lift requires pillow-square membership");
            }
            IsoGridSquare foot = actor.getCell().getGridSquare(tileX, tileY + 1,
                    tileZ);
            IsoRoom room = pillow.getRoom();
            if (room == null || foot == null || foot.getChunk() == null
                    || foot.getRoom() != room
                    || !completeSouthBedFootprint(actor.getCell(), foot,
                            pillow, room)) {
                return failBoolean("bed render lift requires the same complete south-facing bed grid");
            }
            actor.setBridgeOnBedRenderLift(milliTiles / 1000.0f, pillow);
            if (Float.compare(actor.getZ(), z) != 0
                    || actor.getCurrentSquare() != pillow
                    || actor.getMovingSquare() != pillow || actor.square != pillow
                    || !actor.isOnBed()
                    || !actor.getVariableBoolean("OnBedStarted")) {
                actor.clearBridgeOnBedRenderLift();
                return failBoolean("bed render lift changed native physical state");
            }
            return true;
        } catch (RuntimeException | LinkageError failure) {
            actor.clearBridgeOnBedRenderLift();
            return failBoolean("bed render lift failed: "
                    + failure.getClass().getSimpleName()
                    + messageSuffix(failure.getMessage()));
        }
    }

    /**
     * Adjusts a settled stock bed pose from the south foot tile onto the pillow
     * tile of the same two-by-two bed. The stock timed action remains in charge
     * of OnBed/OnBedStarted; the half-tile Y correction places the model at
     * the midpoint between the observed foot and head poses. A half-tile X
     * correction places it in the center of the same pillow lane.
     * All of IsoMovingObject's square references and interpolation coordinates
     * are changed in the same game-thread turn, without a world detach.
     */
    public static boolean shiftOnBedPoseTowardPillow(SCNativeCompanion actor,
            int targetX, int targetY, int targetZ) {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("bed pose shift requires the game thread");
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");

        BedPoseBefore before = null;
        IsoGridSquare target = null;
        boolean changed = false;
        try {
            if (actor.isDead() || !actor.isOnBed()
                    || !actor.getVariableBoolean("OnBedStarted")) {
                return failBoolean("native companion has not settled into the bed action");
            }
            before = new BedPoseBefore(actor);
            if (!before.finite()) return failBoolean("bed pose coordinates are not finite");
            int currentX = (int) Math.floor(before.x);
            int currentY = (int) Math.floor(before.y);
            int currentZ = (int) Math.floor(before.z);
            if (targetX != currentX || targetY != currentY - 1
                    || targetZ != currentZ) {
                return failBoolean("bed pose shift must be exactly one tile north");
            }
            if (actor.getCell() == null || before.current == null
                    || before.render != before.current
                    || before.moving != before.current
                    || before.current != actor.getCell().getGridSquare(
                            currentX, currentY, currentZ)
                    || before.current.getChunk() == null
                    || !actor.isExistInTheWorld()
                    || countIdentity(before.current.getMovingObjects(), actor) != 1) {
                return failBoolean("native companion has inconsistent source-square membership");
            }

            target = actor.getCell().getGridSquare(targetX, targetY, targetZ);
            if (target == null || target.getChunk() == null
                    || target.getCell() != before.current.getCell()
                    || countIdentity(target.getMovingObjects(), actor) != 0) {
                return failBoolean("pillow square is unloaded or has inconsistent membership");
            }
            IsoRoom room = before.current.getRoom();
            if (room == null || target.getRoom() != room) {
                return failBoolean("bed foot and pillow are not in the same room");
            }
            if (!completeSouthBedFootprint(actor.getCell(), before.current,
                    target, room)) {
                return failBoolean("foot and pillow do not share a complete south-facing two-by-two bed grid");
            }

            float newX = before.x + 0.5f;
            float newY = before.y - 0.5f;
            if ((int) Math.floor(newX) != targetX
                    || (int) Math.floor(newY) != targetY) {
                return failBoolean("shifted coordinates do not fall inside pillow square");
            }
            changed = true;
            // setMovingSquare is the native list transfer. The current and
            // render pointers are separate fields and must follow it.
            actor.setMovingSquare(target);
            actor.setCurrentSquare(target);
            actor.setSquare(target);
            actor.setX(newX);
            actor.setY(newY);
            actor.setNextX(newX);
            actor.setNextY(newY);
            actor.setLastX(newX);
            actor.setLastY(newY);
            if (!bedPoseShiftMatches(actor, before, target, newX, newY)) {
                return failBedPoseShiftWithRollback(actor, before, target,
                        "native bed pose shift did not retain its target state");
            }
            return true;
        } catch (RuntimeException | LinkageError failure) {
            String reason = "native bed pose shift failed: "
                    + failure.getClass().getSimpleName()
                    + messageSuffix(failure.getMessage());
            return changed && before != null
                    ? failBedPoseShiftWithRollback(actor, before, target, reason)
                    : failBoolean(reason);
        }
    }

    private static final class BedPoseBefore {
        final float x, y, z, nextX, nextY, lastX, lastY;
        final IsoGridSquare current, render, moving;

        BedPoseBefore(SCNativeCompanion actor) {
            x = actor.getX();
            y = actor.getY();
            z = actor.getZ();
            nextX = actor.getNextX();
            nextY = actor.getNextY();
            lastX = actor.getLastX();
            lastY = actor.getLastY();
            current = actor.getCurrentSquare();
            // IsoMovingObject.getSquare() prefers current over IsoObject.square.
            // Read the public render field directly so a stale render pointer
            // cannot pass the source membership check.
            render = actor.square;
            moving = actor.getMovingSquare();
        }

        boolean finite() {
            return Float.isFinite(x) && Float.isFinite(y) && Float.isFinite(z)
                    && Float.isFinite(nextX) && Float.isFinite(nextY)
                    && Float.isFinite(lastX) && Float.isFinite(lastY);
        }
    }

    private static int countIdentity(ArrayList<?> objects, Object target) {
        if (objects == null) return -1;
        int count = 0;
        for (Object object : objects) if (object == target) count++;
        return count;
    }

    private static boolean completeSouthBedFootprint(IsoCell cell,
            IsoGridSquare foot, IsoGridSquare pillow, IsoRoom room) {
        SeatingManager seating = SeatingManager.getInstance();
        PZArrayList<IsoObject> objects = foot.getObjects();
        if (seating == null || objects == null) return false;
        // PZArrayList deliberately does not implement iterator(): its
        // iterator() throws UnsupportedOperationException in Build 42.21.
        for (int index = 0; index < objects.size(); index++) {
            IsoObject object = objects.get(index);
            if (object == null || object.getSquare() != foot
                    || object.getProperties() == null
                    || !object.getProperties().has(IsoFlagType.bed)) continue;
            IsoSprite sprite = object.getSprite();
            if (sprite == null) continue;
            IsoSpriteGrid grid = sprite.getSpriteGrid();
            if (grid == null || grid.getWidth() != 2 || grid.getHeight() != 2
                    || grid.getSpriteGridPosY(sprite) != 1
                    || !"S".equals(object.getProperties().get("Facing"))
                    || !"S".equals(seating.getFacingDirection(object))) continue;
            int column = grid.getSpriteGridPosX(sprite);
            if (column != 0 && column != 1) continue;
            int otherX = foot.getX() + (column == 0 ? 1 : -1);
            IsoGridSquare otherFoot = cell.getGridSquare(otherX,
                    foot.getY(), foot.getZ());
            IsoGridSquare otherPillow = cell.getGridSquare(otherX,
                    pillow.getY(), pillow.getZ());
            if (hasBedGridTile(pillow, room, grid, column, 0)
                    && hasBedGridTile(otherFoot, room, grid, 1 - column, 1)
                    && hasBedGridTile(otherPillow, room, grid, 1 - column, 0)) {
                return true;
            }
        }
        return false;
    }

    private static boolean hasBedGridTile(IsoGridSquare square, IsoRoom room,
            IsoSpriteGrid grid, int column, int row) {
        if (square == null || square.getChunk() == null || square.getRoom() != room) {
            return false;
        }
        PZArrayList<IsoObject> objects = square.getObjects();
        if (objects == null) return false;
        for (int index = 0; index < objects.size(); index++) {
            IsoObject object = objects.get(index);
            if (object == null || object.getSquare() != square
                    || object.getProperties() == null
                    || !object.getProperties().has(IsoFlagType.bed)) continue;
            IsoSprite sprite = object.getSprite();
            if (sprite != null && sprite.getSpriteGrid() == grid
                    && grid.getSpriteGridPosX(sprite) == column
                    && grid.getSpriteGridPosY(sprite) == row
                    && "S".equals(object.getProperties().get("Facing"))) return true;
        }
        return false;
    }

    private static boolean bedPoseShiftMatches(SCNativeCompanion actor,
            BedPoseBefore before, IsoGridSquare target, float newX, float newY) {
        return actor.getCurrentSquare() == target && actor.square == target
                && actor.getMovingSquare() == target && actor.getSquare() == target
                && actor.isExistInTheWorld()
                && countIdentity(before.current.getMovingObjects(), actor) == 0
                && countIdentity(target.getMovingObjects(), actor) == 1
                && Float.compare(actor.getX(), newX) == 0
                && Float.compare(actor.getY(), newY) == 0
                && Float.compare(actor.getZ(), before.z) == 0
                && Float.compare(actor.getNextX(), newX) == 0
                && Float.compare(actor.getLastX(), newX) == 0
                && Float.compare(actor.getNextY(), newY) == 0
                && Float.compare(actor.getLastY(), newY) == 0
                && actor.isOnBed() && actor.getVariableBoolean("OnBedStarted");
    }

    private static boolean failBedPoseShiftWithRollback(SCNativeCompanion actor,
            BedPoseBefore before, IsoGridSquare target, String reason) {
        try {
            actor.setMovingSquare(before.moving);
            actor.setCurrentSquare(before.current);
            actor.setSquare(before.render);
            actor.setX(before.x);
            actor.setY(before.y);
            actor.setZ(before.z);
            actor.setNextX(before.nextX);
            actor.setNextY(before.nextY);
            actor.setLastX(before.lastX);
            actor.setLastY(before.lastY);
            if (actor.getCurrentSquare() == before.current
                    && actor.square == before.render
                    && actor.getMovingSquare() == before.moving
                    && countIdentity(before.current.getMovingObjects(), actor) == 1
                    && (target == null || countIdentity(target.getMovingObjects(), actor) == 0)
                    && actor.isExistInTheWorld()
                    && Float.compare(actor.getX(), before.x) == 0
                    && Float.compare(actor.getY(), before.y) == 0
                    && Float.compare(actor.getZ(), before.z) == 0
                    && Float.compare(actor.getNextX(), before.nextX) == 0
                    && Float.compare(actor.getNextY(), before.nextY) == 0
                    && Float.compare(actor.getLastX(), before.lastX) == 0
                    && Float.compare(actor.getLastY(), before.lastY) == 0
                    && actor.isOnBed() && actor.getVariableBoolean("OnBedStarted")) {
                return failBoolean(reason + "; previous bed pose restored");
            }
            return failBoolean(reason + "; previous bed pose could not be verified");
        } catch (RuntimeException | LinkageError rollbackFailure) {
            return failBoolean(reason + "; bed pose rollback failed: "
                    + rollbackFailure.getClass().getSimpleName()
                    + messageSuffix(rollbackFailure.getMessage()));
        }
    }

    private static Object luaValue(Object value) {
        // Kahlua stores raw table values exactly as supplied. Reflected Java
        // returns are converted by the call boundary, but rawset(Integer/Float)
        // would otherwise leave boxed userdata where Lua requires a number.
        return value instanceof Number number
                ? Double.valueOf(number.doubleValue())
                : value;
    }

    private static void put(KahluaTable table, String key, Object value) {
        table.rawset(key, luaValue(value));
    }

    private static void put(KahluaTable table, int key, Object value) {
        table.rawset(key, luaValue(value));
    }

    /**
     * Captures the hot, scalar portion of an item snapshot without crossing the
     * Lua/Java boundary once per field. Complex graph-shaped state deliberately
     * stays in Lua, where its existing validation and cycle limits remain the
     * authority. The caller owns and may reuse {@code out}.
     */
    public static int captureItemFacts(InventoryItem item, KahluaTable out) {
        lastFailure = "";
        if (!onGameThread() || item == null || out == null) {
            lastFailure = "captureItemFacts requires the game thread, an item, and an output table";
            return -1;
        }
        try {
            out.wipe();
            int mask = 0;
            put(out, "type", item.getFullType());
            put(out, "condition", item.getCondition());
            put(out, "favorite", item.isFavorite());
            put(out, "scalar_uses", item.getUses());
            put(out, "scalar_age", item.getAge());
            put(out, "scalar_offAge", item.getOffAge());
            put(out, "scalar_offAgeMax", item.getOffAgeMax());
            put(out, "scalar_bloodLevel", item.getBloodLevel());
            put(out, "scalar_repairs", item.getHaveBeenRepaired());
            put(out, "scalar_cooked", item.isCooked());
            put(out, "scalar_burnt", item.isBurnt());
            put(out, "scalar_activated", item.isActivated());

            if (item instanceof Clothing clothing) {
                put(out, "scalar_dirtiness", clothing.getDirtiness());
                put(out, "scalar_wetness", clothing.getWetness());
            }
            if (item instanceof DrainableComboItem drainable) {
                mask |= ITEM_FACT_DRAINABLE;
                put(out, "drainable_currentUses", drainable.getCurrentUsesFloat());
            }
            if (item instanceof Food food) {
                mask |= ITEM_FACT_FOOD;
                put(out, "scalar_frozen", food.isFrozen());
                put(out, "food_baseHunger", food.getBaseHunger());
                put(out, "food_hungChange", food.getHungChange());
                put(out, "food_thirstChange", food.getThirstChangeUnmodified());
                put(out, "food_boredomChange", food.getBoredomChangeUnmodified());
                put(out, "food_unhappyChange", food.getUnhappyChangeUnmodified());
                put(out, "food_calories", food.getCalories());
                put(out, "food_carbohydrates", food.getCarbohydrates());
                put(out, "food_lipids", food.getLipids());
                put(out, "food_proteins", food.getProteins());
                put(out, "food_heat", food.getHeat());
                put(out, "food_freezingTime", food.getFreezingTime());
                put(out, "food_poisonPower", food.getPoisonPower());
                put(out, "food_poisonDetection", food.getPoisonDetectionLevel());
                put(out, "food_useForPoison", food.getUseForPoison());
                put(out, "food_lastCookMinute", food.getLastCookMinute());
                put(out, "food_microwaved", food.isCookedInMicrowave());
                put(out, "food_packaged", food.isPackaged());
                put(out, "food_dangerousUncooked", food.isbDangerousUncooked());
                put(out, "food_removeNegativeWhenCooked", food.isRemoveNegativeEffectOnCooked());
            }

            int keyId = item.getKeyId();
            if (item instanceof Key && keyId >= 0) {
                mask |= ITEM_FACT_KEY;
                put(out, "key_id", keyId);
            }
            if (item instanceof HandWeapon weapon) {
                mask |= ITEM_FACT_HAND_WEAPON;
                put(out, "firearm_currentAmmo", weapon.getCurrentAmmoCount());
                put(out, "firearm_containsClip", weapon.isContainsClip());
                put(out, "firearm_roundChambered", weapon.isRoundChambered());
                put(out, "firearm_jammed", weapon.isJammed());
                put(out, "firearm_fireMode", weapon.getFireMode());
            } else {
                // Build 42 represents detachable magazines as InventoryItem;
                // maxAmmo is the reliable distinction from ordinary items.
                int maxAmmo = item.getMaxAmmo();
                if (maxAmmo > 0) {
                    mask |= ITEM_FACT_MAGAZINE;
                    put(out, "magazine_currentAmmo", item.getCurrentAmmoCount());
                }
            }
            return mask;
        } catch (RuntimeException | LinkageError failure) {
            try { out.wipe(); } catch (RuntimeException ignored) {}
            lastFailure = cleanFailure("item fact capture failed: "
                    + failure.getClass().getSimpleName());
            return -1;
        }
    }

    /** Fresh body assessment in one Lua/Java crossing. The caller reuses out. */
    public static int fillBodyFacts(IsoGameCharacter character, KahluaTable out) {
        lastFailure = "";
        if (!onGameThread() || character == null || out == null) {
            lastFailure = "fillBodyFacts requires the game thread, a character, and an output table";
            return -1;
        }
        try {
            out.wipe();
            BodyDamage body = character.getBodyDamage();
            if (body == null) {
                lastFailure = "character has no body damage";
                return -1;
            }
            put(out, "health", body.getHealth());
            put(out, "infected", body.IsInfected());
            put(out, "apparentInfection", body.getApparentInfectionLevel());
            put(out, "infectionTime", body.getInfectionTime());
            put(out, "infectionDuration", body.getInfectionMortalityDuration());
            ArrayList<BodyPart> parts = body.getBodyParts();
            if (parts == null) {
                lastFailure = "character has no body parts";
                out.wipe();
                return -1;
            }
            int output = 1;
            int flagged = 0;
            for (int index = 0; index < parts.size(); index++) {
                BodyPart part = parts.get(index);
                if (part == null) continue;
                int flags = 0;
                if (part.bleeding() || part.getBleedingTime() > 0) flags |= BODY_BLEEDING;
                if (part.bitten()) flags |= BODY_BITTEN;
                if (part.isInfectedWound()) flags |= BODY_INFECTED_WOUND;
                boolean bandaged = part.bandaged();
                if (bandaged) flags |= BODY_BANDAGED;
                if (bandaged && part.isBandageDirty()) flags |= BODY_BANDAGE_DIRTY;
                if (part.scratched()) flags |= BODY_SCRATCHED;
                if (part.isCut()) flags |= BODY_CUT;
                if (part.deepWounded()) flags |= BODY_DEEP;
                if (part.getBurnTime() > 0) flags |= BODY_BURNED;
                if (part.getFractureTime() > 0) flags |= BODY_FRACTURED;
                if (part.haveBullet()) flags |= BODY_BULLET;
                if (part.haveGlass()) flags |= BODY_GLASS;
                if (flags == 0) continue;
                put(out, output++, part);
                put(out, output++, index);
                put(out, output++, flags);
                put(out, output++, String.valueOf(part.getType()));
                flagged++;
            }
            put(out, "count", flagged);
            return flagged;
        } catch (RuntimeException | LinkageError failure) {
            try { out.wipe(); } catch (RuntimeException ignored) {}
            lastFailure = cleanFailure("body fact capture failed: "
                    + failure.getClass().getSimpleName());
            return -1;
        }
    }

    /**
     * Publishes a coherent flat zombie roster in one main-thread call. Numeric
     * keys contain actor,x,y,z quadruples. Overflow never publishes a prefix,
     * so Lua cannot mistake an incomplete sample for negative evidence.
     */
    public static int fillZombieSnapshot(KahluaTable out, int maximum) {
        lastFailure = "";
        if (!onGameThread() || out == null || maximum < 0) {
            lastFailure = "fillZombieSnapshot requires the game thread and a valid output table";
            return -1;
        }
        try {
            out.wipe();
            IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.getCell();
            ArrayList<IsoZombie> zombies = cell == null ? null : cell.getZombieList();
            if (zombies == null) return 0;
            int count = zombies.size();
            if (count > maximum) {
                put(out, "requiredCount", count);
                return -2;
            }
            int output = 1;
            for (int index = 0; index < count; index++) {
                IsoZombie zombie = zombies.get(index);
                if (zombie == null) continue;
                put(out, output++, zombie);
                put(out, output++, zombie.getX());
                put(out, output++, zombie.getY());
                put(out, output++, zombie.getZ());
            }
            int published = (output - 1) / 4;
            put(out, "count", published);
            return published;
        } catch (RuntimeException | LinkageError failure) {
            try { out.wipe(); } catch (RuntimeException ignored) {}
            lastFailure = cleanFailure("zombie snapshot failed: "
                    + failure.getClass().getSimpleName());
            return -1;
        }
    }

    /**
     * Reads edge geometry into a caller-reused table. This helper publishes
     * facts only; Lua remains authoritative for keys, hazards, safehouses,
     * costs, reservations and companion capability.
     */
    public static boolean fillEdgeFacts(IsoGameCharacter actor, IsoGridSquare from,
            IsoGridSquare to, KahluaTable out) {
        lastFailure = "";
        if (!onGameThread() || from == null || to == null || out == null) {
            return failBoolean("fillEdgeFacts requires the game thread and loaded squares");
        }
        try {
            out.wipe();
            int fx = from.getX(), fy = from.getY(), fz = from.getZ();
            int tx = to.getX(), ty = to.getY(), tz = to.getZ();
            int dx = tx - fx, dy = ty - fy, dz = tz - fz;
            put(out, "fromX", fx); put(out, "fromY", fy); put(out, "fromZ", fz);
            put(out, "toX", tx); put(out, "toY", ty); put(out, "toZ", tz);
            put(out, "water", to.hasWater());
            put(out, "tree", to.HasTree() || to.getTree() != null);
            put(out, "fire", to.haveFire());
            put(out, "brokenGlass", to.getBrokenGlass() != null);
            put(out, "vehicle", to.getVehicleContainer());
            put(out, "squareFree", to.isFree(true) && !to.isSolid()
                    && !to.isSolidTrans() && to.TreatAsSolidFloor());
            put(out, "stairsFrom", from.HasStairs());
            put(out, "stairsTo", to.HasStairs());
            put(out, "slopeFrom", from.hasSlopedSurface());
            put(out, "slopeTo", to.hasSlopedSurface());

            if (fz != tz) {
                put(out, "barrierKind", Math.abs(dx) + Math.abs(dy) > 1 ? "invalid" : "stairs");
                return true;
            }
            if (Math.abs(dx) + Math.abs(dy) != 1) {
                put(out, "barrierKind", dx == 0 && dy == 0 ? "same" : "diagonal");
                return true;
            }

            IsoGridSquare owner = from;
            boolean north;
            if (ty < fy) north = true;
            else if (ty > fy) { owner = to; north = true; }
            else if (tx < fx) north = false;
            else { owner = to; north = false; }
            GridSquareEdge edge = north ? GridSquareEdge.NORTH : GridSquareEdge.WEST;

            IsoObject barrier = from.getWindowTo(to);
            String kind = barrier == null ? null : "window";
            if (barrier == null) { barrier = from.getWindowThumpableTo(to); kind = barrier == null ? null : "window"; }
            if (barrier == null) { barrier = from.getWindowFrameTo(to); kind = barrier == null ? null : "window_frame"; }
            if (barrier == null) { barrier = from.getDoorTo(to); kind = barrier == null ? null : "door"; }
            if (barrier == null) { barrier = owner.getGarageDoor(north); kind = barrier == null ? null : "door"; }
            if (barrier == null) {
                IsoObject contextual = owner.getDoorOrWindow(north);
                if (contextual instanceof IsoWindow || contextual != null && contextual.isWindow()) {
                    barrier = contextual; kind = "window";
                } else if (contextual instanceof IsoDoor
                        || contextual instanceof IsoThumpable thumpable && thumpable.isDoor()) {
                    barrier = contextual; kind = "door";
                }
            }
            if (barrier == null && from.isDoorTo(to)) {
                barrier = owner.getDoor(edge); kind = "door";
            }
            if (barrier == null && from.isWindowTo(to)) {
                barrier = owner.getWindow(edge);
                if (barrier == null) barrier = owner.getThumpableWindow(edge);
                if (barrier == null) {
                    barrier = owner.getWindowFrame(edge);
                    kind = barrier == null ? "window" : "window_frame";
                } else kind = "window";
            }
            if (barrier == null) { barrier = from.getHoppableThumpableTo(to); kind = barrier == null ? null : "fence"; }
            if (barrier == null) { barrier = from.getHoppableTo(to); kind = barrier == null ? null : "fence"; }
            if (barrier == null) { barrier = from.getWallHoppableTo(to); kind = barrier == null ? null : "fence"; }
            if (barrier == null && from.isHoppableTo(to)) kind = "fence";

            boolean ordinaryBlocked = from.isBlockedTo(to);
            if (kind == null && ordinaryBlocked) {
                IsoDirections direction = dy < 0 ? IsoDirections.N : dy > 0
                        ? IsoDirections.S : dx < 0 ? IsoDirections.W : IsoDirections.E;
                kind = from.isPlayerAbleToHopWallTo(direction, to) ? "fence" : "blocked";
            }
            if (kind == null) kind = "open";
            put(out, "barrierObject", barrier);
            put(out, "barrierKind", kind);
            put(out, "nativeBlocked", kind.equals("open")
                    && from.testPathFindAdjacent(actor, dx, dy, dz));

            writeThumpableBlocker(actor, from, to, out);
            return true;
        } catch (RuntimeException | LinkageError failure) {
            try { out.wipe(); } catch (RuntimeException ignored) {}
            return failBoolean("edge fact capture failed: "
                    + failure.getClass().getSimpleName());
        }
    }

    private static void writeThumpableBlocker(IsoGameCharacter actor,
            IsoGridSquare from, IsoGridSquare to, KahluaTable out) {
        for (IsoGridSquare square : new IsoGridSquare[] { from, to }) {
            List<IsoObject> objects = square.getSpecialObjects();
            if (objects == null) continue;
            int maximum = Math.min(objects.size(), 48);
            for (int index = 0; index < maximum; index++) {
                IsoObject object = objects.get(index);
                if (object == null) continue;
                if (square == to && object.isMovedThumpable()) {
                    put(out, "thumpableObject", object);
                    put(out, "thumpableKind", "moved_object");
                    return;
                }
                if (!(object instanceof IsoThumpable thumpable)) continue;
                if (square == to && thumpable.isBlockAllTheSquare()) {
                    put(out, "thumpableObject", object);
                    put(out, "thumpableKind", "full_square_thumpable");
                    return;
                }
                if (!thumpable.isDoor() && !thumpable.isWindow()
                        && !thumpable.isCanPassThrough()
                        && thumpable.TestCollide(actor, from, to)) {
                    put(out, "thumpableObject", object);
                    put(out, "thumpableKind", "wall_thumpable");
                    return;
                }
            }
        }
    }

    /**
     * Swing collision capability (review 4.3). The bridge can be ready while the
     * combat collision reflection is missing, which silently leaves a combat
     * companion swinging without landing hits; surface it so the Lua combat gate
     * and the support report can report a degraded state instead of guessing.
     */
    public static boolean isCombatCollisionReady() {
        return SCNativeCompanion.combatCollisionReady();
    }

    /** Downed-target stomp capability; when false only the stomp is disabled. */
    public static boolean isFloorAttackReady() {
        return SCNativeCompanion.floorAttackReady();
    }

    /** "" when the swing collision path is fully wired, else the missing handle. */
    public static String getCombatCapabilityFailure() {
        return SCNativeCompanion.combatCollisionFailure();
    }

    /** Return loaded map metadata without an unexposed UIWorldMap Lua method. */
    public static Object loadedWorldMap(Object mapObject) {
        if (!(mapObject instanceof UIWorldMap map)) return null;
        WorldMap world = map.getWorldMap();
        return world != null && world.isDataLoaded() ? world : null;
    }

    /** Bank coordinates from the source map XML, which matches game terrain. */
    public static String mappedFishingBanks(Object mapObject, double x,
            double y, double radius) {
        lastFailure = "";
        if (!onGameThread() || !(mapObject instanceof WorldMap world)
                || !world.isDataLoaded() || !Double.isFinite(x)
                || !Double.isFinite(y) || !Double.isFinite(radius)
                || radius < 1 || radius > 1000) return null;
        try {
            return SCFishingMap.candidates(world, (int) Math.floor(x),
                    (int) Math.floor(y), (int) radius);
        } catch (RuntimeException | LinkageError failure) {
            lastFailure = "mapped fishing bank lookup failed"
                    + messageSuffix(failure.getMessage());
            return null;
        }
    }

    /** Recheck a remote map bank just before departure. */
    public static boolean mappedFishingBankPlausible(Object mapObject,
            double x, double y) {
        if (!onGameThread() || !(mapObject instanceof WorldMap world)
                || !world.isDataLoaded() || !Double.isFinite(x)
                || !Double.isFinite(y)) return false;
        try {
            return SCFishingMap.plausible(world,
                    (int) Math.floor(x), (int) Math.floor(y));
        } catch (RuntimeException | LinkageError failure) {
            lastFailure = "mapped fishing bank check failed"
                    + messageSuffix(failure.getMessage());
            return false;
        }
    }

    /**
     * Nearest named street to a world point as "name\tdistance\tx\ty", or null.
     * Lua passes the map's WorldMapStreetsV1; the street files behind it are not
     * exposed to Kahlua, so the bounded walk runs here (see SCStreetLookup).
     */
    public static String nearestStreet(Object streetsApi, double worldX, double worldY,
            double maxDistance) {
        return SCStreetLookup.nearest(streetsApi, worldX, worldY, maxDistance);
    }

    /** One bounded road-region calculation; the Lua caller owns the output table. */
    public static boolean planRoadRoute(Object streetsApi, double startX, double startY,
            double targetX, double targetY, KahluaTable out) {
        if (!onGameThread() || out == null) return false;
        out.wipe();
        long started = System.nanoTime();
        SCRoadRouter.Result result = SCRoadRouter.routeNative(
                streetsApi, startX, startY, targetX, targetY);
        putRoadResult(out, result, started);
        return true;
    }

    /** Replan around a currently observed horde without altering shared streets. */
    public static boolean planRoadRouteAvoiding(Object streetsApi,
            double startX, double startY, double targetX, double targetY,
            double avoidX, double avoidY, double avoidRadius, KahluaTable out) {
        return planRoadRouteAvoidingAll(streetsApi, startX, startY, targetX, targetY,
                avoidX + "," + avoidY + "," + avoidRadius, out);
    }

    /** Up to eight temporary blocked areas, encoded as "x,y,r;...". */
    public static boolean planRoadRouteAvoidingAll(Object streetsApi,
            double startX, double startY, double targetX, double targetY,
            String circles, KahluaTable out) {
        if (!onGameThread() || out == null) return false;
        out.wipe();
        long started = System.nanoTime();
        SCRoadRouter.Result result = SCRoadRouter.routeNativeAvoidingAll(
                streetsApi, startX, startY, targetX, targetY, circles);
        putRoadResult(out, result, started);
        return true;
    }

    private static void putRoadResult(KahluaTable out,
            SCRoadRouter.Result result, long started) {
        put(out, "status", result.status());
        put(out, "reason", result.reason());
        put(out, "fingerprint", result.fingerprint());
        put(out, "roadLength", result.roadLength());
        put(out, "entryX", result.entryX());
        put(out, "entryY", result.entryY());
        put(out, "exitX", result.exitX());
        put(out, "exitY", result.exitY());
        put(out, "inferredJunctions", result.inferredJunctions());
        put(out, "expandedNodes", result.expandedNodes());
        put(out, "elapsedMs", (System.nanoTime() - started) / 1_000_000.0);
        if ("READY".equals(result.status())) {
            StringBuilder geometry = new StringBuilder();
            for (SCRoadRouter.Step point : result.points()) {
                if (!geometry.isEmpty()) geometry.append(';');
                String label = point.street() == null ? "" : point.street()
                        .replaceAll("[\\t\\r\\n;,]", " ").trim();
                if (label.length() > 128) label = label.substring(0, 128);
                geometry.append(point.x()).append(',').append(point.y())
                        .append(',').append(point.width()).append(',')
                        .append(point.junction() ? '1' : '0')
                        .append(',').append(label);
            }
            put(out, "geometry", geometry.toString());
        }
    }

    public static boolean isCompanion(Object candidate) {
        return candidate instanceof SCNativeCompanion actor && isOwned(actor);
    }

    /** Apply the local player's live option without changing vanilla co-op PvP. */
    public static boolean setProtectRecruitedCompanions(boolean enabled) {
        protectRecruitedCompanions = enabled;
        return true;
    }

    public static boolean isProtectRecruitedCompanions() {
        return protectRecruitedCompanions;
    }

    /** Snapshot live comfort options for every newly constructed companion. */
    public static boolean setCompanionComfortOptions(String symptomMode,
            boolean ordinaryColdsEnabled) {
        SCCompanionComfort.setDefaults(symptomMode, ordinaryColdsEnabled);
        return true;
    }

    /**
     * Temporary, actor-local shelter for a scripted companion in a sealed car.
     * Lua decides when the doors and windows still justify that shelter. Build
     * 42's normal cheat setter ignores a non-local actor, so only the bridge's
     * owned native actor may receive this flag; no player or other NPC changes.
     */
    public static boolean setStoryZombieIgnored(SCNativeCompanion actor, boolean enabled) {
        lastFailure = "";
        if (!onGameThread()) {
            return failBoolean("story zombie shelter requires the game thread");
        }
        if (GameClient.client || GameServer.server) {
            return failBoolean("story zombie shelter is single-player only");
        }
        if (!isOwned(actor)) {
            return failBoolean("native companion is not owned by SCBridge");
        }
        if (enabled && actor.isDead()) {
            return failBoolean("dead companion cannot enter story zombie shelter");
        }
        actor.setStoryZombieIgnored(enabled);
        return true;
    }

    /**
     * Puts an owned companion that already sits in seat 0 under bridge control.
     * Lua's SCVehicle owns boarding; this only takes the wheel. The car starts
     * held still, and the engine is started (with a few bounded retries) only
     * once {@link #driveSet} asks for speed. Never while a player is aboard.
     */
    public static boolean driveStart(SCNativeCompanion actor, boolean haveKey) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        try {
            BaseVehicle vehicle = actor.getVehicle();
            if (vehicle == null) return failBoolean("companion is not in a vehicle");
            if (playerAboard(vehicle)) return failBoolean("a player is in this vehicle");
            String failure = actor.companionDriver().start(actor, vehicle, haveKey);
            return failure.isEmpty() || failBoolean(failure);
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("drive start failed: " + failure.getClass().getSimpleName());
        }
    }


    /** Starts a service journey for exactly one real player already in a passenger seat. */
    public static boolean driveStartWithPassenger(SCNativeCompanion actor,
                                                   IsoPlayer passenger, boolean haveKey) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        try {
            BaseVehicle vehicle = actor.getVehicle();
            if (vehicle == null || vehicle.getDriver() != actor) {
                return failBoolean("companion is not in the driver's seat");
            }
            if (!isAuthorizedDrivePassenger(vehicle, passenger)) {
                return failBoolean("booked player is not in a passenger seat");
            }
            String failure = actor.companionDriver().startWithPassenger(actor, vehicle,
                    passenger, haveKey);
            return failure.isEmpty() || failBoolean(failure);
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("passenger drive start failed: " + failure.getClass().getSimpleName());
        }
    }

    /**
     * Steering in [-1, 1] (-1 is the left key) and a cruise speed in km/h. Zero
     * stops and holds; anything else is held to SCDriveControl's speed ceiling.
     * With brakeForObstacles the car stops for anything the lane scan finds.
     */
    public static boolean driveSet(SCNativeCompanion actor, double steering, double cruiseKmh,
                                   boolean brakeForObstacles) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        SCCompanionDriver driver = actor.companionDriver();
        if (!driver.isActive()) return failBoolean("companion is not driving");
        driver.set(steering, cruiseKmh, brakeForObstacles);
        return true;
    }

    /**
     * Follows a road route, "x,y,width;..." as the expedition planner gives it:
     * keeps to the right-hand lane, slides round wrecks the lane scan finds,
     * stops when the road is blocked edge to edge, and stops at the end.
     */
    public static boolean driveFollow(SCNativeCompanion actor, String route, double cruiseKmh) {
        return driveFollowTuned(actor, route, cruiseKmh, 1.0);
    }

    /** Route follower with a bounded corner-speed multiplier for Markus's cab. */
    public static boolean driveFollowTuned(SCNativeCompanion actor, String route,
                                           double cruiseKmh, double cornerSpeedScale) {
        lastFailure = "";
        if (!Double.isFinite(cornerSpeedScale)
                || cornerSpeedScale < 1.0 || cornerSpeedScale > 2.0) {
            return failBoolean("corner speed scale must be between 1 and 2");
        }
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        SCCompanionDriver driver = actor.companionDriver();
        if (!driver.isActive()) return failBoolean("companion is not driving");
        SCDrivePath path = SCDrivePath.parse(route);
        if (path == null) {
            return failBoolean("route must be 2 to " + SCDrivePath.MAX_POINTS
                    + " points of x,y,width inside the map");
        }
        driver.follow(path, cruiseKmh, cornerSpeedScale);
        return true;
    }

    /** Follow a player's rolling vehicle trail, retaining the current wheel owner. */
    public static boolean driveFollowVehicle(SCNativeCompanion actor, BaseVehicle lead,
                                             String route, double cruiseKmh) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        if (lead == null || lead == actor.getVehicle() || lead.getDriver() == null)
            return failBoolean("lead vehicle has no player driver");
        if (!(lead.getDriver() instanceof IsoPlayer))
            return failBoolean("lead vehicle has no player driver");
        if (!Double.isFinite(cruiseKmh) || cruiseKmh <= 0.0 || cruiseKmh > 50.0)
            return failBoolean("convoy speed must be 1 to 50 km/h");
        SCCompanionDriver driver = actor.companionDriver();
        if (!driver.isActive()) return failBoolean("companion is not driving");
        SCDrivePath path = SCDrivePath.parse(route);
        if (path == null) return failBoolean("invalid convoy trail");
        driver.followVehicle(lead, path, cruiseKmh);
        return true;
    }

    /** Bounded slow final parking leg, never a general route substitute. */
    public static boolean driveApproach(SCNativeCompanion actor, String route,
                                        double cruiseKmh) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        SCCompanionDriver driver = actor.companionDriver();
        if (!driver.isActive()) return failBoolean("companion is not driving");
        SCDrivePath path = SCDrivePath.parse(route);
        if (path == null || path.points() != 2 || path.length() > 15.0f
                || path.length() < 0.5f || !Double.isFinite(cruiseKmh)
                || cruiseKmh <= 0.0 || cruiseKmh > 5.0) {
            return failBoolean("parking approach requires a clear two-point route within 15 tiles");
        }
        BaseVehicle vehicle = actor.getVehicle();
        if (vehicle == null) return failBoolean("parking car is missing");
        Vector3f forward = vehicle.getForwardVector(new Vector3f());
        float length = (float) Math.hypot(forward.x, forward.z);
        SCDrivePath.Projection origin = path.project(vehicle.getX(), vehicle.getY(),
                -1, null);
        float[] target = new float[5];
        path.pointAt(path.length(), 0.0f, target);
        float dx = target[0] - vehicle.getX();
        float dy = target[1] - vehicle.getY();
        float distance = (float) Math.hypot(dx, dy);
        if (length < 0.9f || distance < 0.5f
                || Math.abs(origin.lateral) > 1.0f
                || (forward.x * dx + forward.z * dy) / (length * distance) < 0.75f) {
            return failBoolean("parking bay requires a clear forward approach");
        }
        driver.approach(path, cruiseKmh);
        return true;
    }

    /** Copy the engine's actual world-space vehicle polygon into a Lua table. */
    public static boolean vehicleFootprint(BaseVehicle vehicle, KahluaTable out) {
        lastFailure = "";
        if (!onGameThread() || vehicle == null || out == null) {
            return failBoolean("vehicle footprint needs a loaded car and game thread");
        }
        VehiclePoly poly = vehicle.getPoly();
        if (poly == null) return failBoolean("vehicle polygon is unavailable");
        out.wipe();
        put(out, "x1", poly.x1); put(out, "y1", poly.y1);
        put(out, "x2", poly.x2); put(out, "y2", poly.y2);
        put(out, "x3", poly.x3); put(out, "y3", poly.y3);
        put(out, "x4", poly.x4); put(out, "y4", poly.y4);
        return true;
    }

    /**
     * Turns the car round with a bounded three-point turn. With followBack the
     * companion then drives the same route back.
     */
    public static boolean driveTurnAround(SCNativeCompanion actor, boolean followBack) {
        lastFailure = "";
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        SCCompanionDriver driver = actor.companionDriver();
        if (!driver.isActive()) return failBoolean("companion is not driving");
        String failure = driver.turnAround(followBack);
        return failure.isEmpty() || failBoolean(failure);
    }

    /** Lets go of the wheel and parks the car. Safe to call when not driving. */
    public static boolean driveStop(SCNativeCompanion actor) {
        lastFailure = "";
        if (!onGameThread()) return failBoolean("companion driving requires the game thread");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        try {
            actor.companionDriver().stop(actor, "released");
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("drive stop failed: " + failure.getClass().getSimpleName());
        }
    }

    /** Fills out with the driver's state, the last inputs and the last lane scan. */
    public static boolean driveStatus(SCNativeCompanion actor, KahluaTable out) {
        lastFailure = "";
        if (out == null) return failBoolean("driveStatus requires an output table");
        if (!onGameThread()) return failBoolean("companion driving requires the game thread");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        SCCompanionDriver driver = actor.companionDriver();
        out.wipe();
        put(out, "active", driver.isActive());
        put(out, "state", driver.state());
        put(out, "reason", driver.reason());
        put(out, "speedKmh", driver.speedKmh());
        put(out, "cruiseKmh", driver.cruiseKmh());
        put(out, "maxCruiseKmh", SCDriveControl.MAX_CRUISE_KMH);
        put(out, "steering", driver.steering());
        put(out, "autoBrake", driver.autoBrake());
        put(out, "engineRunning", driver.engineRunning());
        put(out, "engineState", driver.engineState());
        put(out, "startAttempts", driver.startAttempts());
        put(out, "engineStartCalls", driver.startCalls());
        put(out, "zombiesKilled", driver.zombiesKilled());
        SCDriveControl.Input input = driver.lastInput();
        put(out, "forward", input.forward());
        put(out, "brake", input.brake());
        put(out, "backward", input.backward());
        putLane(out, driver.lastScan());
        SCRoadFollower follower = driver.follower();
        put(out, "following", follower != null);
        if (follower != null) {
            put(out, "mode", follower.mode().name().toLowerCase(java.util.Locale.ROOT));
            put(out, "routeLength", follower.path().length());
            put(out, "routePoints", follower.path().points());
            put(out, "along", follower.along());
            put(out, "remaining", follower.remaining());
            put(out, "lateral", follower.lateral());
            put(out, "offset", follower.offset());
            put(out, "laneOffset", follower.laneOffset());
            put(out, "swerves", follower.swerves());
            put(out, "blockedAt", follower.blockedAt());
            if (follower.mode() == SCRoadFollower.Mode.BLOCKED) {
                put(out, "blockedX", follower.blockedX());
                put(out, "blockedY", follower.blockedY());
            } else if ("safety_blocked".equals(driver.state())) {
                put(out, "blockedX", driver.safetyBlockedX());
                put(out, "blockedY", driver.safetyBlockedY());
            }
            SCLaneScan.Result rear = driver.lastRearScan();
            put(out, "rearBlocked", rear.blocked);
            put(out, "rearDistance", rear.distance);
            put(out, "rearKind", SCLaneScan.kindName(rear.kind));
            SCTurnAround turn = follower.turn();
            if (turn != null) {
                put(out, "turnState", turn.state().name().toLowerCase(java.util.Locale.ROOT));
                put(out, "turnLegs", turn.legs());
                put(out, "turnSide", turn.side());
                put(out, "turnReverseSign", turn.reverseSign());
                put(out, "turnReason", turn.reason());
            }
        }
        return true;
    }

    /**
     * Runs the lane scan once for the car the companion sits in, in any seat,
     * lookAhead tiles past the front bumper. Never moves anything.
     */
    public static boolean scanLane(SCNativeCompanion actor, double lookAhead, KahluaTable out) {
        lastFailure = "";
        if (out == null) return failBoolean("scanLane requires an output table");
        String refused = driveRefusal(actor);
        if (!refused.isEmpty()) return failBoolean(refused);
        try {
            BaseVehicle vehicle = actor.getVehicle();
            if (vehicle == null) return failBoolean("companion is not in a vehicle");
            float reach = lookAhead > 0.0 && lookAhead == lookAhead
                    ? (float) Math.min(lookAhead, SCLaneScan.MAX_LOOK_AHEAD)
                    : SCCompanionDriver.lookAheadFor(0.0f);
            SCLaneScan.Result result = actor.companionDriver().scan(vehicle, reach);
            out.wipe();
            put(out, "lookAhead", reach);
            putLane(out, result);
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("lane scan failed: " + failure.getClass().getSimpleName());
        }
    }

    private static void putLane(KahluaTable out, SCLaneScan.Result result) {
        put(out, "blocked", result.blocked);
        put(out, "obstacleDistance", result.distance);
        put(out, "obstacleKind", SCLaneScan.kindName(result.kind));
        put(out, "obstacleX", result.hitX);
        put(out, "obstacleY", result.hitY);
        put(out, "leftDistance", result.leftDistance);
        put(out, "centerDistance", result.centerDistance);
        put(out, "rightDistance", result.rightDistance);
        put(out, "squaresChecked", result.squaresChecked);
    }

    private static String driveRefusal(SCNativeCompanion actor) {
        if (!onGameThread()) return "companion driving requires the game thread";
        if (GameClient.client || GameServer.server) return "companion driving is single-player only";
        if (!isOwned(actor)) return "native companion is not owned by SCBridge";
        if (actor.isDead()) return "a dead companion cannot drive";
        return "";
    }

    /** A real player in the car. A promoted companion in a player slot does not count. */
    static boolean playerAboard(BaseVehicle vehicle) {
        if (vehicle == null) return false;
        IsoPlayer[] players = IsoPlayer.players;
        if (players == null) return false;
        for (IsoPlayer player : players) {
            if (player != null && !isCompanion(player)
                    && player.getVehicle() == vehicle) {
                return true;
            }
        }
        return false;
    }

    /** Reject unknown occupants; a booked passenger never grants another player a ride. */
    static boolean isAuthorizedDrivePassenger(BaseVehicle vehicle, IsoPlayer passenger) {
        if (vehicle == null || passenger == null || isCompanion(passenger)
                || passenger.getVehicle() != vehicle) return false;
        IsoPlayer[] players = IsoPlayer.players;
        boolean local = false;
        if (players != null) {
            for (IsoPlayer player : players) {
                if (player == passenger) local = true;
                else if (player != null && !isCompanion(player)
                        && player.getVehicle() == vehicle) return false;
            }
        }
        if (!local) return false;
        int seat = vehicle.getSeat(passenger);
        int count = vehicle.getMaxPassengers();
        if (seat <= 0 || count < 2 || count > 32 || seat >= count
                || vehicle.getCharacter(seat) != passenger) return false;
        for (int index = 0; index < count; index++) {
            IsoGameCharacter occupant = vehicle.getCharacter(index);
            if (occupant != null && occupant != passenger && !isCompanion(occupant)) {
                return false;
            }
        }
        return true;
    }

    public static String checkActor(SCNativeCompanion actor) {
        if (!isOwned(actor)) return "native companion is not owned by SCBridge";
        return checkActorState(actor);
    }

    /**
     * Starts Build 42's real zombie attack action against an owned companion.
     *
     * A detached non-local IsoPlayer is not present in the stock players[] vision
     * loop. The zombie can consequently keep it as target and even face it while
     * the action graph repeatedly falls back to idle instead of selecting its
     * `attack` state. Lua calls this only after the ordinary target-seen warning
     * interval. This method revalidates the dangerous boundary natively and then
     * selects the existing zombie action state: the stock AttackState, animation
     * clips, AttackCollisionCheck, victim reaction, sound and BodyDamage code do
     * all subsequent work.
     */
    /**
     * CB-01. Refresh an already-live attacker/victim pair's eligibility without
     * ever requesting attack entry.
     *
     * <p>{@code IsoZombie.postUpdateInternal()} ends with
     * {@code canSeeTarget = isTargetVisible()} and zeroes {@code targetSeenTime}
     * with it. {@code isTargetVisible()} cannot find a deliberately detached
     * companion, so both are cleared <em>every frame</em>. Restoring them was
     * previously fused into {@link #startZombieAttack}, which also selects the
     * attack state -- so the only way to keep an attack alive was to keep asking
     * the graph to start one. This method is the maintenance half on its own: it
     * revalidates the pair and writes the two fields, and touches neither the
     * ActionContext nor the state machine.
     *
     * <p>Returns {@code "sustained"} when the pair is still eligible, or the
     * reason it is not, so the caller can drop a pair that has gone stale.
     */
    public static String sustainZombieAttack(IsoZombie zombie, SCNativeCompanion actor) {
        String eligibility = checkZombieAttackEligibility(zombie, actor);
        if (eligibility != null) return eligibility;
        if (ZOMBIE_CAN_SEE_TARGET == null) return "visibility_adapter_unavailable";
        try {
            ZOMBIE_CAN_SEE_TARGET.setBoolean(zombie, true);
        } catch (IllegalAccessException | IllegalArgumentException failure) {
            return "visibility_adapter_failed";
        }
        // postUpdateInternal also zeroes targetSeenTime whenever it clears
        // canSeeTarget, and getShouldAttack() reads it. Restoring one without
        // the other leaves the pair half-eligible.
        zombie.setTargetSeenTime(Math.max(0.51f, zombie.getTargetSeenTime()));
        return "sustained";
    }

    /**
     * The shared precondition check for both halves of a companion-directed
     * zombie attack. Returns null when the pair is eligible, otherwise the
     * reason it is not. Also refreshes {@code vectorToTarget}, which
     * {@code getShouldAttack()} reads instead of recomputing the distance.
     */
    private static String checkZombieAttackEligibility(IsoZombie zombie,
            SCNativeCompanion actor) {
        if (zombie == null) return "invalid_zombie";
        if (!isOwned(actor)) return "unowned_companion";
        if (zombie.isDead() || actor.isDead() || actor.isOnFloor()) return "invalid_life_state";
        if (actor.getVehicle() != null) return "companion_in_vehicle";
        if (actor.isZombiesDontAttack()) return "companion_attack_immunity";
        if (zombie.getTarget() != actor) return "different_target";

        float dx = actor.getX() - zombie.getX();
        float dy = actor.getY() - zombie.getY();
        float dz = Math.abs(actor.getZ() - zombie.getZ());
        // The local-player vision pass normally refreshes this cached vector; a
        // detached companion never participates in that pass, which is the
        // actual reason an otherwise-valid action state fell straight to idle.
        zombie.vectorToTarget.x = dx;
        zombie.vectorToTarget.y = dy;
        if (dz >= 0.2f || dx * dx + dy * dy > 0.72f * 0.72f) {
            return "outside_attack_range";
        }
        IsoGridSquare zombieSquare = zombie.getCurrentSquare();
        IsoGridSquare actorSquare = actor.getCurrentSquare();
        if (zombieSquare == null || actorSquare == null) return "missing_square";
        if (zombieSquare != actorSquare && zombieSquare.isSomethingTo(actorSquare)) {
            return "attack_obstructed";
        }
        return null;
    }

    /**
     * Request attack <em>entry</em> for a pair. Maintenance of an already-live
     * attack is {@link #sustainZombieAttack}: keeping the two separate is what
     * stops a per-frame visibility refresh from repeatedly re-entering the
     * attack state (CB-01).
     */
    public static String startZombieAttack(IsoZombie zombie, SCNativeCompanion actor) {
        String sustained = sustainZombieAttack(zombie, actor);
        if (!"sustained".equals(sustained)) return sustained;
        if (!zombie.isFacingTarget()) return "not_facing_target";

        ActionContext context = zombie.getActionContext();
        if (context == null) return "missing_action_context";
        String current = context.getCurrentStateName();
        if ("attack".equalsIgnoreCase(current)
                && zombie.getStateMachine().getCurrent() == AttackState.instance()) {
            return "attack_active";
        }
        if (!("idle".equalsIgnoreCase(current)
                || "face-target".equalsIgnoreCase(current)
                || "walktoward".equalsIgnoreCase(current)
                || "lunge".equalsIgnoreCase(current)
                || "pathfind".equalsIgnoreCase(current))) {
            return "busy_" + (current == null ? "unknown" : current);
        }
        ActionGroup group = context.getGroup();
        if (group == null || group.getName() == null
                || !group.getName().startsWith("zombie")) {
            return "wrong_action_group";
        }
        ActionState attack = group.findState("attack");
        if (attack == null) return "attack_state_unavailable";
        context.setCurrentState(attack);
        // Build 42 keeps the ActionContext animation state and legacy AI state
        // as separate layers. Selecting only the former is overwritten before
        // AttackState.enter() clears ZombieBiteDone and initializes the outcome.
        zombie.changeState(AttackState.instance());
        return "attack".equalsIgnoreCase(context.getCurrentStateName())
                && zombie.getStateMachine().getCurrent() == AttackState.instance()
                ? "attack_started" : "attack_state_rejected";
    }

    private static String checkActorState(SCNativeCompanion actor) {
        if (actor == null) return "native companion is null";
        if (!actor.isBridgeHealthy()) return actor.getBridgeFailure();
        if (!actor.isNpc() || actor.isLocalPlayer()) return "native companion lost NPC isolation";
        if (actor.getPlayerNum() != actor.bridgeExpectedPlayerIndex()) {
            return "native companion player index changed";
        }
        if (actor.getBodyDamage() == null || actor.getMoodles() == null || actor.getXp() == null
                || actor.getEmitter() == null || actor.getVisual() == null) {
            return "native companion components are invalid";
        }
        BaseVehicle vehicle = actor.getVehicle();
        if (!actor.isDead() && vehicle != null) {
            if (vehicle.getSeat(actor) < 0) {
                return "living native companion has an invalid vehicle seat";
            }
        } else if (!actor.isDead()) {
            if (actor.getCurrentSquare() == null) {
                return "living native companion has no current world square";
            }
            if (!actor.isExistInTheWorld()) {
                return "living native companion is absent from its square moving-object list";
            }
        }
        String isolationFailure = localPlayerIsolationFailure();
        if (!isolationFailure.isEmpty()) return isolationFailure;
        IsoPlayer[] slots = IsoPlayer.players;
        for (int index = 0; index < slots.length; index++) {
            if (slots[index] == actor
                    && !(index == 1 && SCSplitScreenProbe.isLeader(actor))) {
                return "native companion occupied an unexpected local-player slot";
            }
        }
        return "";
    }

    /**
     * Enqueues native actor construction after the current Lua call has fully
     * unwound. IsoPlayer's constructor synchronously fires
     * OnCreateLivingCharacter; constructing it inside Lua -> Java re-enters
     * Kahlua while LuaJavaInvoker still owns pooled ReturnValues and can corrupt
     * that pool for every later timed action in the session.
     */
    public static long requestSpawn(
            IsoGridSquare square,
            String forename,
            String surname,
            boolean female,
            String outfit) {
        return requestSpawn(square, forename, surname, female, outfit, false);
    }

    /**
     * As above, but `bare` says the caller will dress this companion itself.
     *
     * <p>SurvivorFactory only makes fully clothed survivors, and IsoPlayer's
     * constructor puts those clothes on before anything else can run. A
     * companion being restored from a save has its own clothes applied by Lua
     * a frame or more later, so the player watched the group load in wearing
     * strangers' outfits and then change. A bare spawn is undressed the
     * instant it is built, before it is ever drawn, so the only change the
     * player sees is the right clothes going on.
     */
    public static long requestSpawn(
            IsoGridSquare square,
            String forename,
            String surname,
            boolean female,
            String outfit,
            boolean bare) {
        lastFailure = "";
        String ready = checkReady();
        if (!ready.isEmpty()) return failRequest(ready);
        if (!validSpawnSquare(square)) {
            return failRequest("spawn square is unsafe, obstructed, or unloaded");
        }

        final SpawnRequest request;
        synchronized (SPAWN_REQUESTS) {
            if (SPAWN_REQUESTS.size() >= MAX_SPAWN_REQUESTS) {
                return failRequest("too many native companion spawn requests are pending");
            }
            long id = nextSpawnRequestId();
            request = new SpawnRequest(id, square,
                    cleanText(forename, MAX_NAME_LENGTH, "Fellow"),
                    cleanText(surname, MAX_NAME_LENGTH, "Survivor"), female,
                    cleanText(outfit, MAX_OUTFIT_LENGTH, ""), bare);
            SPAWN_REQUESTS.put(id, request);
        }

        try {
            queueSpawnAfterLua(request.id);
        } catch (RejectedExecutionException failure) {
            synchronized (SPAWN_REQUESTS) {
                SPAWN_REQUESTS.remove(request.id);
            }
            return failRequest("native spawn hand-off is unavailable");
        }
        return request.id;
    }

    private static void queueAfterLua(Runnable task) throws RejectedExecutionException {
        SPAWN_HANDOFF.execute(() -> MainThread.queueInvokeOnMainThread(task));
    }

    /**
     * Hand a companion timed-action start to the main loop after the exposing
     * LuaJavaInvoker has returned. IsoGameCharacter.StartAction synchronously
     * enters Lua callbacks; doing that inside the original Lua -> Java call
     * corrupts Kahlua's pooled ReturnValues frame for a non-local companion.
     */
    static void queueCompanionActionStart(SCNativeCompanion actor, BaseAction action)
            throws RejectedExecutionException {
        SPAWN_HANDOFF.execute(() -> {
            try {
                MainThread.queueInvokeOnMainThread(
                        () -> actor.completeDeferredActionStart(action));
            } catch (RuntimeException | LinkageError failure) {
                // Without this the action would stay "pending" forever: Lua
                // keeps waiting and a retry of the same action is ignored.
                actor.failDeferredActionStart(action, "native action start queue failed: "
                        + failure.getClass().getSimpleName()
                        + messageSuffix(failure.getMessage()));
            }
        });
    }

    private static void queueSpawnAfterLua(long requestId) throws RejectedExecutionException {
        SPAWN_HANDOFF.execute(() -> {
            try {
                MainThread.queueInvokeOnMainThread(() -> completeSpawn(requestId));
            } catch (RuntimeException | LinkageError failure) {
                failSpawnRequest(requestId, "native spawn queue failed: "
                        + failure.getClass().getSimpleName()
                        + messageSuffix(failure.getMessage()));
            }
        });
    }

    /** Compatibility trap for stale callers; synchronous construction is unsafe. */
    @Deprecated
    public static SCNativeCompanion spawn(
            IsoGridSquare square,
            String forename,
            String surname,
            boolean female,
            String outfit) {
        return failNull("synchronous native spawn is disabled; use requestSpawn");
    }

    public static String getSpawnState(long requestId) {
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest request = SPAWN_REQUESTS.get(requestId);
            return request == null ? "unknown" : request.state.name().toLowerCase();
        }
    }

    public static SCNativeCompanion getSpawnResult(long requestId) {
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest request = SPAWN_REQUESTS.get(requestId);
            return request != null && request.state == SpawnState.READY ? request.actor : null;
        }
    }

    public static String getSpawnFailure(long requestId) {
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest request = SPAWN_REQUESTS.get(requestId);
            return request == null ? "native spawn request is unknown" : request.failure;
        }
    }

    /** Releases a terminal request after Lua has safely claimed its result. */
    public static boolean forgetSpawnRequest(long requestId) {
        lastFailure = "";
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest request = SPAWN_REQUESTS.get(requestId);
            if (request == null) return failBoolean("native spawn request is unknown");
            if (request.state == SpawnState.PENDING
                    || request.state == SpawnState.CLEANUP_PENDING) {
                return failBoolean("native spawn request is not terminal: "
                        + request.state.name().toLowerCase());
            }
            SPAWN_REQUESTS.remove(requestId);
            return true;
        }
    }

    /** Cancels an unclaimed request and tears down a completed actor if needed. */
    public static boolean cancelSpawnRequest(long requestId) {
        lastFailure = "";
        final SpawnRequest request;
        synchronized (SPAWN_REQUESTS) {
            request = SPAWN_REQUESTS.get(requestId);
            if (request != null) request.cancelRequested = true;
        }
        if (request == null) return failBoolean("native spawn request is unknown");
        if (request.actor != null) {
            boolean removed = cleanupActor(request.actor, "cancelled spawn request");
            synchronized (SPAWN_REQUESTS) {
                if (removed) {
                    SPAWN_REQUESTS.remove(requestId);
                } else {
                    request.state = SpawnState.CLEANUP_PENDING;
                    request.failure = cleanupFailure(request.actor);
                }
            }
            return removed;
        }
        // Keep a pending request queryable until completeSpawn observes the
        // cancellation. It may already have passed its first map lookup and be
        // constructing an actor; removing the request here would leave a failed
        // abandoned-actor cleanup with no request-level retry handle.
        synchronized (SPAWN_REQUESTS) {
            if (request.state != SpawnState.PENDING) {
                SPAWN_REQUESTS.remove(requestId);
            }
        }
        return true;
    }

    public static int getSpawnRequestCount() {
        synchronized (SPAWN_REQUESTS) {
            return SPAWN_REQUESTS.size();
        }
    }

    private static void completeSpawn(long requestId) {
        if (Thread.currentThread() != MainThread.mainThread) {
            failSpawnRequest(requestId, "native spawn left Project Zomboid's main thread");
            return;
        }
        final SpawnRequest request;
        synchronized (SPAWN_REQUESTS) {
            request = SPAWN_REQUESTS.get(requestId);
            if (request == null || request.state != SpawnState.PENDING) return;
            if (request.cancelRequested) {
                SPAWN_REQUESTS.remove(requestId);
                return;
            }
        }

        awaitSpawnCompletionPauseForTests();

        SCNativeCompanion actor = spawnNow(request);
        String failure = actor == null ? lastFailure : "";
        boolean cleanupAbandonedActor = false;
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest current = SPAWN_REQUESTS.get(requestId);
            if (current == null) {
                cleanupAbandonedActor = actor != null;
            } else if (actor == null) {
                if (current.actor != null && isCleanupPending(current.actor)) {
                    String cleanup = cleanupFailure(current.actor);
                    current.failure = failure.isEmpty() ? cleanup
                            : cleanFailure(failure + "; " + cleanup);
                    current.state = SpawnState.CLEANUP_PENDING;
                } else {
                    current.actor = null;
                    current.failure = failure.isEmpty()
                            ? "native companion spawn failed" : failure;
                    current.state = SpawnState.FAILED;
                }
            } else if (current.cancelRequested) {
                cleanupAbandonedActor = true;
            } else {
                current.actor = actor;
                current.state = SpawnState.READY;
            }
        }
        if (cleanupAbandonedActor && actor != null) {
            boolean removed = cleanupActor(actor, "abandoned spawn result");
            synchronized (SPAWN_REQUESTS) {
                SpawnRequest current = SPAWN_REQUESTS.get(requestId);
                if (current != null && current.cancelRequested) {
                    if (removed) {
                        SPAWN_REQUESTS.remove(requestId);
                    } else {
                        current.actor = actor;
                        current.state = SpawnState.CLEANUP_PENDING;
                        current.failure = cleanupFailure(actor);
                    }
                }
            }
        }
    }

    static void pauseSpawnCompletionForTests(CountDownLatch paused,
            CountDownLatch resume) {
        SPAWN_PAUSED_FOR_TESTS = paused;
        SPAWN_RESUME_FOR_TESTS = resume;
    }

    private static void awaitSpawnCompletionPauseForTests() {
        CountDownLatch paused = SPAWN_PAUSED_FOR_TESTS;
        CountDownLatch resume = SPAWN_RESUME_FOR_TESTS;
        if (paused == null || resume == null) return;
        SPAWN_PAUSED_FOR_TESTS = null;
        SPAWN_RESUME_FOR_TESTS = null;
        paused.countDown();
        try {
            resume.await();
        } catch (InterruptedException failure) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("spawn completion test pause interrupted", failure);
        }
    }

    private static SCNativeCompanion spawnNow(SpawnRequest request) {
        String ready = checkReady();
        if (!ready.isEmpty()) return failNull(ready);
        IsoGridSquare square = request.square;
        if (!validSpawnSquare(square)) {
            return failNull("spawn square became unsafe, obstructed, or unloaded");
        }

        SCNativeCompanion actor = null;
        try {
            SurvivorDesc descriptor = SurvivorFactory.CreateSurvivor(
                    SurvivorFactory.SurvivorType.Neutral, request.female);
            if (descriptor == null) return failNull("SurvivorFactory returned no descriptor");
            descriptor.setVoicePrefix(request.female ? "VoiceFemale" : "VoiceMale");
            descriptor.setForename(request.forename);
            descriptor.setSurname(request.surname);
            if (!request.outfit.isEmpty()) descriptor.dressInNamedOutfit(request.outfit);

            IsoCell cell = square.getCell();
            actor = constructCompanion(descriptor, cell,
                    square.getX(), square.getY(), square.getZ());
            // Ownership begins immediately after construction. Every later
            // operation can throw, and teardown itself can fail; retaining the
            // reference is the only safe way to make cleanup retryable.
            addOwned(actor);
            request.actor = actor;
            actor.setX(square.getX() + 0.5f);
            actor.setY(square.getY() + 0.5f);
            actor.setZ(square.getZ());
            // IsoMovingObject tracks three related square references. The
            // constructor/current-square setter alone does not populate the
            // render square or its moving-object list, while
            // isExistInTheWorld() explicitly requires both.
            // Nobody watches a companion get dressed.
            //
            // SurvivorFactory hands us a randomly outfitted descriptor and
            // IsoPlayer's constructor puts those clothes on. A companion being
            // restored from a save has its real clothes applied by Lua a frame
            // or more later, so the group loaded in wearing strangers' outfits
            // and then changed into their own in front of the player. Take the
            // factory's clothes off now, before the actor has been drawn once.
            if (request.bare) {
                String undressed = undress(actor);
                if (!undressed.isEmpty()) {
                    boolean removed = cleanupActor(actor, "failed spawn");
                    if (removed) request.actor = null;
                    return failNull(undressed + (removed ? "" : "; cleanup is pending"));
                }
            }
            actor.setCurrentSquare(square);
            actor.setSquare(square);
            actor.setMovingSquare(square);
            actor.addToWorld();
            // A restored stay/base-duty companion may never take a movement
            // step. Register its update slot now: square membership alone
            // leaves it on the minimap while its model alpha stays at zero.
            boolean scheduled = actor.ensureScheduled();

            String renderFailure = consumeFailureForTests("spawn:render-validation")
                    ? "injected native companion render validation failure"
                    : attachRenderModel(actor);
            if (renderFailure.isEmpty() && request.bare) {
                // Second layer, and best-effort: scene culling is what
                // attachRenderModel clears to make a companion draw, so
                // setting it is the engine's own "not yet". It costs nothing
                // if the renderer recomputes it, and the undress above is what
                // actually guarantees the player never sees the wrong clothes.
                actor.setSceneCulled(true);
                actor.hiddenUntilReadyAt = System.currentTimeMillis();
            }
            String actorFailure = checkActorState(actor);
            if (!scheduled || !renderFailure.isEmpty() || !actorFailure.isEmpty()
                    || !actor.isExistInTheWorld()) {
                String reason = !scheduled
                        ? "native companion did not enter the update scheduler"
                        : !renderFailure.isEmpty() ? renderFailure
                        : actorFailure.isEmpty() ? "native companion did not enter the world"
                        : actorFailure;
                boolean removed = cleanupActor(actor, "failed spawn");
                if (removed) request.actor = null;
                return failNull(reason + (removed ? "" : "; cleanup is pending"));
            }
            return actor;
        } catch (RuntimeException | LinkageError failure) {
            String reason = "native companion spawn failed: "
                    + failure.getClass().getSimpleName() + messageSuffix(failure.getMessage());
            if (actor != null) {
                boolean removed = cleanupActor(actor, "failed spawn exception");
                if (removed) request.actor = null;
                if (!removed) reason += "; cleanup is pending";
            }
            return failNull(reason);
        }
    }

    /** Package-private so the real-JAR control covers the production guard. */
    static SCNativeCompanion constructCompanion(
            SurvivorDesc descriptor, IsoCell cell, int x, int y, int z) {
        try (MutedLivingCharacterEvent ignored = MutedLivingCharacterEvent.open()) {
            return new SCNativeCompanion(descriptor, cell, x, y, z);
        }
    }

    /**
     * Shows a companion that was hidden for construction. Called once the mod
     * has finished restoring its clothes, inventory and appearance.
     *
     * <p>Idempotent, and never the only thing standing between a companion and
     * being seen: {@link SCNativeCompanion#update()} reveals itself anyway
     * once the hide has outlived its welcome, so a failed or skipped reveal
     * costs a moment of invisibility rather than a permanent ghost.
     */
    public static boolean reveal(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        actor.revealNow();
        if (actor.isInvisible()) return failBoolean("native companion stayed invisible");
        return true;
    }

    /**
     * Reattaches a persistent companion after Build 42 unloads its former
     * square. Lua selects a currently loaded, safe square near the player.
     */
    public static boolean recover(SCNativeCompanion actor, IsoGridSquare square) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        if (actor.isDead()) return failBoolean("dead native companion cannot be recovered");
        if (!validSpawnSquare(square)) return failBoolean("recovery square is unsafe or unloaded");
        SCNativeCompanion.LocalPlayerState localState = SCNativeCompanion.LocalPlayerState.capture();
        if (localState == null || !localState.matches()) {
            return failBoolean("local-player state is unavailable for companion recovery");
        }
        float oldX = actor.getX();
        float oldY = actor.getY();
        float oldZ = actor.getZ();
        IsoGridSquare oldCurrentSquare = actor.getCurrentSquare();
        IsoGridSquare oldSquare = actor.getSquare();
        IsoGridSquare oldMovingSquare = actor.getMovingSquare();
        boolean oldWorldMembership = actor.isExistInTheWorld();
        boolean oldModelMembership = actor.isAddedToModelManager();
        try {
            actor.StopAllActionQueue();
            if (actor.getPathFindBehavior2() != null) actor.getPathFindBehavior2().cancel();
            actor.setMoving(false);
            actor.setRunning(false);
            actor.setSprinting(false);
            actor.setSneaking(false);
            // World/square membership can be rebuilt without destroying the
            // render slot. Keeping ModelManager ownership across this brief
            // relocation avoids an unnecessary remove/add race on the same
            // main-thread frame.
            if (actor.isExistInTheWorld()) actor.removeFromWorld();
            actor.removeFromSquare();
            actor.setMovingSquare(null);
            actor.setCurrentSquare(null);
            actor.setSquare(null);
            actor.setX(square.getX() + 0.5f);
            actor.setY(square.getY() + 0.5f);
            actor.setZ(square.getZ());
            actor.setCurrentSquare(square);
            actor.setSquare(square);
            actor.setMovingSquare(square);
            boolean injectedFinalCheck = consumeFailureForTests("recovery:final-check");
            // A real live actor always performs the native world commit. The
            // injected branch stops at the immediately preceding transaction
            // boundary so the real-JAR headless control can exercise rollback
            // without IsoGameCharacter's unavailable render/ragdoll runtime.
            if (!injectedFinalCheck) actor.addToWorld();
            String renderFailure;
            String failure;
            if (injectedFinalCheck) {
                // Exercise the rollback from the same final validation point
                // without requiring a live world renderer in the real-JAR
                // headless control. Normal production calls cannot select it.
                renderFailure = "";
                failure = "injected recovery final-check failure";
            } else {
                renderFailure = attachRenderModel(actor);
                failure = checkActorState(actor);
            }
            if (!localState.matches()) {
                localState.restore();
                return failRecoveryWithRollback(actor, "companion recovery changed local-player state",
                        oldX, oldY, oldZ, oldCurrentSquare, oldSquare, oldMovingSquare,
                        oldWorldMembership, oldModelMembership);
            }
            if (!renderFailure.isEmpty()) {
                return failRecoveryWithRollback(actor,
                        "companion recovery failed: " + renderFailure,
                        oldX, oldY, oldZ, oldCurrentSquare, oldSquare, oldMovingSquare,
                        oldWorldMembership, oldModelMembership);
            }
            if (!failure.isEmpty()) {
                return failRecoveryWithRollback(actor,
                        "companion recovery failed: " + failure,
                        oldX, oldY, oldZ, oldCurrentSquare, oldSquare, oldMovingSquare,
                        oldWorldMembership, oldModelMembership);
            }
            // addToWorld() restores square membership but not the cell object
            // list the MovingObjectUpdateScheduler iterates. Without this the
            // recovered actor is never ticked: it stops moving and its render
            // alpha fades to invisible (while its valid square keeps it on the
            // minimap, lootable, and a target for zombies) -- exactly the
            // "teleported companion disappears but does not move" symptom.
            actor.ensureScheduled();
            return true;
        } catch (RuntimeException | LinkageError failure) {
            localState.restore();
            return failRecoveryWithRollback(actor, "native companion recovery failed: "
                    + failure.getClass().getSimpleName() + messageSuffix(failure.getMessage()),
                    oldX, oldY, oldZ, oldCurrentSquare, oldSquare, oldMovingSquare,
                    oldWorldMembership, oldModelMembership);
        }
    }

    private static boolean failRecoveryWithRollback(SCNativeCompanion actor, String reason,
            float oldX, float oldY, float oldZ, IsoGridSquare oldCurrentSquare,
            IsoGridSquare oldSquare, IsoGridSquare oldMovingSquare,
            boolean oldWorldMembership, boolean oldModelMembership) {
        ArrayList<String> rollbackFailures = new ArrayList<>();
        try {
            if (actor.isExistInTheWorld()) {
                if (consumeFailureForTests("recovery:headless-square-detach")) {
                    // The injected final-check branch never entered the game
                    // entity manager, so only its square-list registration
                    // exists in the real-JAR headless control.
                    actor.removeFromSquare();
                } else {
                    actor.removeFromWorld();
                }
            }
        } catch (RuntimeException | LinkageError failure) {
            rollbackFailures.add("world-detach=" + failure.getClass().getSimpleName());
        }
        try { actor.removeFromSquare(); }
        catch (RuntimeException | LinkageError failure) {
            rollbackFailures.add("square-detach=" + failure.getClass().getSimpleName());
        }
        try {
            actor.setMovingSquare(null);
            actor.setCurrentSquare(null);
            actor.setSquare(null);
            actor.setX(oldX);
            actor.setY(oldY);
            actor.setZ(oldZ);
            actor.setCurrentSquare(oldCurrentSquare);
            actor.setSquare(oldSquare);
            actor.setMovingSquare(oldMovingSquare);
            if (oldWorldMembership) actor.addToWorld();
            if (oldModelMembership) {
                String renderFailure = attachRenderModel(actor);
                if (!renderFailure.isEmpty()) rollbackFailures.add(renderFailure);
            } else if (actor.isAddedToModelManager()) {
                detachRenderModel(actor);
            }
        } catch (RuntimeException | LinkageError failure) {
            rollbackFailures.add("restore=" + failure.getClass().getSimpleName()
                    + messageSuffix(failure.getMessage()));
        }
        boolean matches = Float.compare(actor.getX(), oldX) == 0
                && Float.compare(actor.getY(), oldY) == 0
                && Float.compare(actor.getZ(), oldZ) == 0
                && actor.getCurrentSquare() == oldCurrentSquare
                && actor.getSquare() == oldSquare
                && actor.getMovingSquare() == oldMovingSquare
                && actor.isExistInTheWorld() == oldWorldMembership
                && actor.isAddedToModelManager() == oldModelMembership;
        if (!matches) rollbackFailures.add("prior placement was not restored");
        if (rollbackFailures.isEmpty()) return failBoolean(reason + "; prior state restored");

        boolean removed = cleanupActor(actor, "failed recovery rollback");
        return failBoolean(reason + "; rollback failed: "
                + String.join(", ", rollbackFailures)
                + (removed ? "; actor removed" : "; cleanup is pending"));
    }

    private static void failSpawnRequest(long requestId, String reason) {
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest request = SPAWN_REQUESTS.get(requestId);
            if (request == null || request.state != SpawnState.PENDING) return;
            request.failure = cleanFailure(reason);
            request.state = SpawnState.FAILED;
        }
    }

    public static boolean remove(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        return cleanupActor(actor, "explicit removal");
    }

    /** Retries a previously unverified native teardown without dropping ownership. */
    public static boolean retryCleanup(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null || !isOwned(actor)) {
            return failBoolean("native companion is not owned by SCBridge");
        }
        if (!isCleanupPending(actor)) {
            return failBoolean("native companion has no pending cleanup");
        }
        return cleanupActor(actor, "cleanup retry");
    }

    public static boolean retryCleanupAll() {
        lastFailure = "";
        ArrayList<String> failures = new ArrayList<>();
        for (SCNativeCompanion actor : cleanupSnapshot()) {
            if (!cleanupActor(actor, "cleanup retry")) failures.add(cleanupFailure(actor));
        }
        if (!failures.isEmpty()) {
            return failBoolean("native cleanup remains pending: " + String.join("; ", failures));
        }
        return true;
    }

    public static boolean stop(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        try {
            if (actor.getPathFindBehavior2() != null) actor.getPathFindBehavior2().cancel();
            actor.setMoving(false);
            actor.setRunning(false);
            actor.setSprinting(false);
            actor.setSneaking(false);
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("native companion stop failed: " + failure.getClass().getSimpleName());
        }
    }

    /**
     * Applies an authorized fatal injury through vanilla BodyDamage. The actor
     * remains in the world so Project Zomboid performs its normal death,
     * corpse and reanimation lifecycle; retireDead() later releases ownership.
     */
    public static boolean endLife(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        if (actor.isDead()) return true;
        try {
            float health = actor.getBodyDamage().getOverallBodyHealth();
            actor.getBodyDamage().ReduceGeneralHealth(Math.max(health + 1.0f, 101.0f));
            // Build 42 applies the fatal health change on the following
            // update. A successful native damage call is the result here;
            // callers observe isDead separately on later frames.
            return true;
        } catch (RuntimeException | LinkageError failure) {
            return failBoolean("native fatal injury failed: "
                    + failure.getClass().getSimpleName());
        }
    }

    /**
     * Releases bridge ownership after vanilla has produced the corpse. Unlike
     * remove(), this must not delete the actor from the world before death is
     * finalized or the corpse/reanimation contract would be interrupted.
     */
    public static boolean retireDead(SCNativeCompanion actor) {
        lastFailure = "";
        if (actor == null) return failBoolean("native companion is null");
        if (!isOwned(actor)) return failBoolean("native companion is not owned by SCBridge");
        if (!actor.isDead()) return failBoolean("native companion is still alive");
        if (!actor.isOnDeathDone() || !actor.isCorpseReady()) {
            return failBoolean("native companion death is not finalized");
        }
        actor.disableBridge("death finalized");
        removeOwned(actor);
        return true;
    }

    /** Best-effort world teardown used before registry reset or world replacement. */
    public static boolean removeAll() {
        lastFailure = "";
        Set<SCNativeCompanion> requestActors = Collections.newSetFromMap(
                new IdentityHashMap<>());
        ArrayList<Long> requestIds;
        synchronized (SPAWN_REQUESTS) {
            requestIds = new ArrayList<>(SPAWN_REQUESTS.keySet());
            for (SpawnRequest request : SPAWN_REQUESTS.values()) {
                if (request.actor != null) requestActors.add(request.actor);
            }
        }
        ArrayList<String> failures = new ArrayList<>();
        for (long requestId : requestIds) {
            if (!cancelSpawnRequest(requestId)) failures.add(lastFailure);
        }
        for (SCNativeCompanion actor : ownedSnapshot()) {
            if (!requestActors.contains(actor)
                    && !cleanupActor(actor, "world teardown")) failures.add(lastFailure);
        }
        if (!failures.isEmpty()) {
            return failBoolean("one or more native companions failed teardown: "
                    + String.join("; ", failures));
        }
        return true;
    }

    public static int getOwnedCount() {
        synchronized (OWNED) {
            return OWNED.size();
        }
    }

    public static int getCleanupPendingCount() {
        synchronized (CLEANUP_FAILURES) {
            return CLEANUP_FAILURES.size();
        }
    }

    public static String getCleanupFailure(SCNativeCompanion actor) {
        return cleanupFailure(actor);
    }

    /**
     * addToWorld() registers square membership, but it does not add a manually
     * constructed IsoGameCharacter to ModelManager. Build 42 does that from
     * setSceneCulled(false); without this explicit transition the actor moves
     * and casts a shadow while its human model is never rendered.
     */
    /**
     * Takes off everything the survivor factory dressed this companion in.
     *
     * <p>Only ever used for a spawn the mod is about to dress itself, and run
     * before the actor joins the world, so nothing is lost: Lua clears the
     * inventory and applies the saved items immediately afterwards.
     */
    private static String undress(SCNativeCompanion actor) {
        WornItems worn = actor.getWornItems();
        if (worn == null) return "native companion exposes no worn-item list";
        for (int index = worn.size() - 1; index >= 0; index--) {
            WornItem entry = worn.get(index);
            InventoryItem item = entry == null ? null : entry.getItem();
            if (item != null) actor.removeWornItem(item);
        }
        if (worn.size() != 0) {
            worn.clear();
            if (worn.size() != 0) return "native companion could not be undressed";
        }
        actor.resetModelNextFrame();
        return "";
    }

    private static String attachRenderModel(SCNativeCompanion actor) {
        actor.setSceneCulled(false);
        // removeFromWorld() can detach ModelManager ownership without changing
        // the scene-culling value. Repeating setSceneCulled(false) is then a
        // no-op. ModelManager.Add() is the engine's idempotent recovery path:
        // it cancels a queued removal and reactivates the actor's existing
        // model slot before rebuilding one when needed.
        if (!actor.isAddedToModelManager()) {
            ModelManager.instance.Add(actor);
        }
        // Build 42.20.4's Add() cancellation branch clears a pending removal
        // and preserves the active slot, but returns before restoring the
        // character's isAddedToModelManager flag. Complete that native state
        // transition only when the existing model proves the slot survived.
        if (!actor.isAddedToModelManager() && actor.hasActiveModel()) {
            actor.setAddedToModelManager(ModelManager.instance, true);
        }
        if (!actor.isAddedToModelManager()) {
            return "native companion was not added to the model renderer";
        }
        if (!actor.hasActiveModel()) {
            return "native companion model renderer is inactive";
        }
        return "";
    }

    /** ModelManager ownership is separate from world/square membership. */
    private static void detachRenderModel(SCNativeCompanion actor) {
        if (actor.isAddedToModelManager()) ModelManager.instance.Remove(actor);
    }

    private static boolean removeUnchecked(SCNativeCompanion actor) {
        ArrayList<String> failures = new ArrayList<>();
        actor.disableBridge("removed");
        try {
            actor.StopAllActionQueue();
        } catch (RuntimeException | LinkageError failure) {
            failures.add("stop=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("speech");
            if (!actor.clearCompanionSpeech()) {
                failures.add("speech=visible chat state remains");
            }
        } catch (RuntimeException | LinkageError failure) {
            failures.add("speech=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("scheduler");
            if (!actor.ensureUnscheduled()) {
                failures.add("scheduler=cell update membership remains");
            }
        } catch (RuntimeException | LinkageError failure) {
            failures.add("scheduler=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("model");
            detachRenderModel(actor);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("model=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("world");
            if (actor.isExistInTheWorld()) actor.removeFromWorld();
        } catch (RuntimeException | LinkageError failure) {
            failures.add("world=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("square-list");
            actor.removeFromSquare();
        } catch (RuntimeException | LinkageError failure) {
            failures.add("square-list=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("moving-square");
            actor.setMovingSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("moving-square=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("current-square");
            actor.setCurrentSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("current-square=" + failure.getClass().getSimpleName());
        }
        try {
            failCleanupStepForTests("render-square");
            actor.setSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("render-square=" + failure.getClass().getSimpleName());
        }
        boolean removed = !actor.isExistInTheWorld() && !actor.isAddedToModelManager()
                && actor.getCurrentSquare() == null && actor.getSquare() == null
                && actor.getMovingSquare() == null && !actor.isScheduled()
                && !actor.hasCompanionSpeech();
        if (!removed) {
            failures.add("world, model, scheduler, speech, or square membership remains");
        }
        if (!failures.isEmpty()) {
            return failBoolean("native companion removal failed: " + String.join(", ", failures));
        }
        return true;
    }

    /**
     * The ownership transaction commits only after native world, model and
     * square membership are all verified absent. A failed teardown remains a
     * strongly managed object and is surfaced through the retry API.
     */
    private static boolean cleanupActor(SCNativeCompanion actor, String operation) {
        if (actor == null) return failBoolean("native companion is null");
        // A removed driver must not leave its last pedal pressed in the car.
        try {
            actor.companionDriver().stop(actor, "removed");
        } catch (RuntimeException | LinkageError ignored) {
            // A failed park must not block removing the actor itself.
        }
        addOwned(actor);
        if (removeUnchecked(actor)) {
            synchronized (CLEANUP_FAILURES) {
                CLEANUP_FAILURES.remove(actor);
            }
            removeOwned(actor);
            return true;
        }
        String failure = cleanFailure(operation + ": " + lastFailure);
        synchronized (CLEANUP_FAILURES) {
            CLEANUP_FAILURES.put(actor, failure);
        }
        lastFailure = failure;
        return false;
    }

    /** Disposable co-op bootstrap only; retains failed cleanup for retry. */
    static boolean disposeColdProbeActor(SCNativeCompanion actor) {
        if (actor == null || isOwned(actor) || IsoPlayer.players == null) return false;
        for (IsoPlayer slot : IsoPlayer.players) {
            if (slot == actor) return false;
        }
        return cleanupActor(actor, "cold co-op bootstrap removal");
    }

    private static boolean isCleanupPending(SCNativeCompanion actor) {
        synchronized (CLEANUP_FAILURES) {
            return CLEANUP_FAILURES.containsKey(actor);
        }
    }

    private static String cleanupFailure(SCNativeCompanion actor) {
        synchronized (CLEANUP_FAILURES) {
            String failure = CLEANUP_FAILURES.get(actor);
            return failure == null ? "" : failure;
        }
    }

    private static ArrayList<SCNativeCompanion> cleanupSnapshot() {
        synchronized (CLEANUP_FAILURES) {
            return new ArrayList<>(CLEANUP_FAILURES.keySet());
        }
    }

    /** Package-private, one-shot fault seam used only by the real-JAR control. */
    static void failNextCleanupStepForTests(String step) {
        failNextBridgeStepsForTests(step == null ? null : "cleanup:" + step);
    }

    /** Package-private multi-point variant for compound rollback controls. */
    static void failNextBridgeStepsForTests(String... steps) {
        synchronized (FAILURE_STEPS_FOR_TESTS) {
            FAILURE_STEPS_FOR_TESTS.clear();
            if (steps == null) return;
            for (String step : steps) {
                if (step != null && !step.isBlank()) FAILURE_STEPS_FOR_TESTS.add(step);
            }
        }
    }

    private static boolean consumeFailureForTests(String step) {
        synchronized (FAILURE_STEPS_FOR_TESTS) {
            return FAILURE_STEPS_FOR_TESTS.remove(step);
        }
    }

    private static void failCleanupStepForTests(String step) {
        if (consumeFailureForTests("cleanup:" + step)) {
            throw new IllegalStateException("injected cleanup failure");
        }
    }

    private static String localPlayerIsolationFailure() {
        IsoPlayer[] slots = IsoPlayer.players;
        if (slots == null || slots.length != 4) return "unexpected local-player slot layout";
        if (IsoPlayer.numPlayers != 1 && !SCSplitScreenProbe.acceptsCurrentLayout(slots)) {
            return "split-screen or multiple local players are unsupported";
        }
        if (slots[0] == null || slots[0].getPlayerNum() != 0
                || !slots[0].isLocalPlayer()
                || (IsoPlayer.getInstance() != slots[0]
                    && !SCSplitScreenProbe.isLeader(IsoPlayer.getInstance()))) {
            return "primary local-player singleton or slot is not ready";
        }
        if ((slots[1] != null && !SCSplitScreenProbe.isLeader(slots[1]))
                || slots[2] != null || slots[3] != null) {
            return "local player slots 1-3 have an unsupported occupant";
        }
        return "";
    }

    private static boolean isOwned(SCNativeCompanion actor) {
        if (actor == null) return false;
        synchronized (OWNED) {
            return OWNED.contains(actor);
        }
    }

    private static void addOwned(SCNativeCompanion actor) {
        synchronized (OWNED) {
            if (OWNED.isEmpty() && !coopPvpOverrideActive) {
                coopPvpBeforeOwnership = IsoPlayer.getCoopPVP();
                IsoPlayer.setCoopPVP(true);
                coopPvpOverrideActive = true;
            }
            OWNED.add(actor);
        }
    }

    private static void removeOwned(SCNativeCompanion actor) {
        synchronized (OWNED) {
            actor.setStoryZombieIgnored(false);
            OWNED.remove(actor);
            if (OWNED.isEmpty() && coopPvpOverrideActive) {
                IsoPlayer.setCoopPVP(coopPvpBeforeOwnership);
                coopPvpOverrideActive = false;
            }
        }
    }

    private static ArrayList<SCNativeCompanion> ownedSnapshot() {
        synchronized (OWNED) {
            return new ArrayList<>(OWNED);
        }
    }

    private static boolean validSpawnSquare(IsoGridSquare square) {
        return square != null && square.getCell() != null && square.getChunk() != null
                && !square.isSolid() && !square.isSolidTrans() && square.TreatAsSolidFloor()
                && square.isFree(true) && square.isSafeToSpawn();
    }

    private static String cleanText(String value, int maximumLength, String fallback) {
        String clean = value == null ? "" : value.trim().replaceAll("[\\p{Cntrl}]", "");
        if (clean.length() > maximumLength) clean = clean.substring(0, maximumLength);
        return clean.isEmpty() ? fallback : clean;
    }

    private static String messageSuffix(String message) {
        if (message == null || message.isBlank()) return "";
        String clean = message.replaceAll("[\\r\\n\\t]+", " ").trim();
        if (clean.length() > 160) clean = clean.substring(0, 160);
        return ": " + clean;
    }

    private static long nextSpawnRequestId() {
        long id = NEXT_SPAWN_REQUEST.getAndIncrement();
        if (id <= 0L) {
            NEXT_SPAWN_REQUEST.compareAndSet(id + 1L, 1L);
            id = NEXT_SPAWN_REQUEST.getAndIncrement();
        }
        return id;
    }

    private static String cleanFailure(String reason) {
        String clean = reason == null ? "native companion spawn failed"
                : reason.replaceAll("[\\r\\n\\t]+", " ").trim();
        if (clean.isEmpty()) clean = "native companion spawn failed";
        return clean.length() > 240 ? clean.substring(0, 240) : clean;
    }

    private static SCNativeCompanion failNull(String reason) {
        lastFailure = cleanFailure(reason);
        return null;
    }

    private static long failRequest(String reason) {
        lastFailure = cleanFailure(reason);
        return INVALID_SPAWN_REQUEST;
    }

    private static boolean failBoolean(String reason) {
        lastFailure = cleanFailure(reason);
        return false;
    }
}
