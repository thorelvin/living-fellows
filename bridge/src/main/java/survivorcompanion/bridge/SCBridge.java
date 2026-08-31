// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
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

    private enum SpawnState { PENDING, READY, FAILED }

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
        if (!SCBootstrap.isReady()) {
            return SCBootstrap.getStatus();
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
            if (request.state == SpawnState.PENDING) {
                return failBoolean("native spawn request is still pending");
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
            request = SPAWN_REQUESTS.remove(requestId);
        }
        if (request == null) return failBoolean("native spawn request is unknown");
        if (request.actor != null) {
            boolean removed = removeUnchecked(request.actor);
            if (removed) removeOwned(request.actor);
            return removed;
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
        }

        SCNativeCompanion actor = spawnNow(request);
        String failure = actor == null ? lastFailure : "";
        boolean abandoned = false;
        synchronized (SPAWN_REQUESTS) {
            SpawnRequest current = SPAWN_REQUESTS.get(requestId);
            if (current == null) {
                abandoned = true;
            } else if (actor == null) {
                current.failure = failure.isEmpty() ? "native companion spawn failed" : failure;
                current.state = SpawnState.FAILED;
            } else {
                current.actor = actor;
                current.state = SpawnState.READY;
            }
        }
        if (abandoned && actor != null) {
            boolean removed = removeUnchecked(actor);
            if (removed) removeOwned(actor);
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

            String renderFailure = attachRenderModel(actor);
            String actorFailure = checkActorState(actor);
            if (!renderFailure.isEmpty() || !actorFailure.isEmpty()
                    || !actor.isExistInTheWorld()) {
                removeUnchecked(actor);
                if (!renderFailure.isEmpty()) return failNull(renderFailure);
                return failNull(actorFailure.isEmpty()
                        ? "native companion did not enter the world" : actorFailure);
            }
            addOwned(actor);
            return actor;
        } catch (RuntimeException | LinkageError failure) {
            if (actor != null) removeUnchecked(actor);
            return failNull("native companion spawn failed: " + failure.getClass().getSimpleName()
                    + messageSuffix(failure.getMessage()));
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
            actor.addToWorld();
            String renderFailure = attachRenderModel(actor);
            String failure = checkActorState(actor);
            if (!localState.matches()) {
                localState.restore();
                return failBoolean("companion recovery changed local-player state");
            }
            if (!renderFailure.isEmpty()) {
                return failBoolean("companion recovery failed: " + renderFailure);
            }
            if (!failure.isEmpty()) return failBoolean("companion recovery failed: " + failure);
            return true;
        } catch (RuntimeException | LinkageError failure) {
            localState.restore();
            return failBoolean("native companion recovery failed: "
                    + failure.getClass().getSimpleName() + messageSuffix(failure.getMessage()));
        }
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
        boolean removed = removeUnchecked(actor);
        if (removed) removeOwned(actor);
        return removed;
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
        synchronized (SPAWN_REQUESTS) {
            // Removing the requests first makes any already-queued completion a no-op.
            SPAWN_REQUESTS.clear();
        }
        ArrayList<String> failures = new ArrayList<>();
        for (SCNativeCompanion actor : ownedSnapshot()) {
            if (!removeUnchecked(actor)) failures.add(lastFailure);
            // World replacement must never retain a strong reference into the old cell.
            removeOwned(actor);
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
            detachRenderModel(actor);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("model=" + failure.getClass().getSimpleName());
        }
        try {
            if (actor.isExistInTheWorld()) actor.removeFromWorld();
        } catch (RuntimeException | LinkageError failure) {
            failures.add("world=" + failure.getClass().getSimpleName());
        }
        try {
            actor.removeFromSquare();
        } catch (RuntimeException | LinkageError failure) {
            failures.add("square-list=" + failure.getClass().getSimpleName());
        }
        try {
            actor.setMovingSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("moving-square=" + failure.getClass().getSimpleName());
        }
        try {
            actor.setCurrentSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("current-square=" + failure.getClass().getSimpleName());
        }
        try {
            actor.setSquare(null);
        } catch (RuntimeException | LinkageError failure) {
            failures.add("render-square=" + failure.getClass().getSimpleName());
        }
        boolean removed = !actor.isExistInTheWorld() && !actor.isAddedToModelManager()
                && actor.getCurrentSquare() == null && actor.getSquare() == null;
        if (!removed) failures.add("world, model, or square membership remains");
        if (!failures.isEmpty()) {
            return failBoolean("native companion removal failed: " + String.join(", ", failures));
        }
        return true;
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
