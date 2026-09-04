// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicLong;

import zombie.MainThread;
import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.SurvivorFactory;
import zombie.core.Core;
import zombie.core.skinnedmodel.ModelManager;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.vehicles.BaseVehicle;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Narrow Lua-facing authority for creating and owning native companions. */
public final class SCBridge {
    public static final String PROTOCOL = "42.20-isocompanion-5";
    /**
     * Core.getVersionNumber() reports the public release family (42.20) in a
     * live game, even though this bridge is compiled and signature-tested
     * against the installed 42.20.4 runtime. Keep both spellings explicit so
     * the live display label cannot incorrectly disable an otherwise verified
     * bridge, while unrelated game families still fail closed.
     */
    public static final String SUPPORTED_GAME_VERSION = "42.20";
    public static final String COMPILED_GAME_VERSION = "42.20.4";

    private static final int MAX_NAME_LENGTH = 48;
    private static final int MAX_OUTFIT_LENGTH = 96;
    private static final int MAX_SPAWN_REQUESTS = 8;
    private static final long INVALID_SPAWN_REQUEST = -1L;
    private static final Set<SCNativeCompanion> OWNED = Collections.newSetFromMap(
            new IdentityHashMap<>());
    private static final Map<SCNativeCompanion, String> CLEANUP_FAILURES =
            new IdentityHashMap<>();
    private static final Map<Long, SpawnRequest> SPAWN_REQUESTS = new LinkedHashMap<>();
    private static final AtomicLong NEXT_SPAWN_REQUEST = new AtomicLong(1L);
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
        private final ArrayList<Object> callbacks;
        private final ArrayList<Object> saved;

        private MutedLivingCharacterEvent(ArrayList<Object> callbacks) {
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
        private SpawnState state = SpawnState.PENDING;
        private SCNativeCompanion actor;
        private String failure = "";
        private boolean cancelRequested;

        private SpawnRequest(long id, IsoGridSquare square, String forename,
                String surname, boolean female, String outfit) {
            this.id = id;
            this.square = square;
            this.forename = forename;
            this.surname = surname;
            this.female = female;
            this.outfit = outfit;
        }
    }

    private SCBridge() {}

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

    public static boolean isCompanion(Object candidate) {
        return candidate instanceof SCNativeCompanion actor && isOwned(actor);
    }

    public static String checkActor(SCNativeCompanion actor) {
        if (!isOwned(actor)) return "native companion is not owned by SCBridge";
        return checkActorState(actor);
    }

    private static String checkActorState(SCNativeCompanion actor) {
        if (actor == null) return "native companion is null";
        if (!actor.isBridgeHealthy()) return actor.getBridgeFailure();
        if (!actor.isNpc() || actor.isLocalPlayer()) return "native companion lost NPC isolation";
        if (actor.getPlayerNum() != SCNativeCompanion.RESERVED_NON_LOCAL_PLAYER_INDEX) {
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
        for (IsoPlayer slot : slots) {
            if (slot == actor) return "native companion occupied a local-player slot";
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
                    cleanText(outfit, MAX_OUTFIT_LENGTH, ""));
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
            actor.setCurrentSquare(square);
            actor.setSquare(square);
            actor.setMovingSquare(square);
            actor.addToWorld();

            String renderFailure = consumeFailureForTests("spawn:render-validation")
                    ? "injected native companion render validation failure"
                    : attachRenderModel(actor);
            String actorFailure = checkActorState(actor);
            if (!renderFailure.isEmpty() || !actorFailure.isEmpty()
                    || !actor.isExistInTheWorld()) {
                String reason = !renderFailure.isEmpty() ? renderFailure
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
            return actor.isDead() || actor.getBodyDamage().getOverallBodyHealth() <= 0.0f;
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
                && actor.getMovingSquare() == null;
        if (!removed) failures.add("world, model, or square membership remains");
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
        if (IsoPlayer.numPlayers != 1) return "split-screen or multiple local players are unsupported";
        if (slots[0] == null || IsoPlayer.getInstance() != slots[0]
                || slots[0].getPlayerNum() != 0 || !slots[0].isLocalPlayer()) {
            return "primary local-player singleton or slot is not ready";
        }
        if (slots[1] != null || slots[2] != null || slots[3] != null) {
            return "local player slots 1-3 must be unused";
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
            OWNED.add(actor);
        }
    }

    private static void removeOwned(SCNativeCompanion actor) {
        synchronized (OWNED) {
            OWNED.remove(actor);
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
