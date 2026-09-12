// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
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

import se.krka.kahlua.vm.KahluaTable;
import zombie.MainThread;
import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.ai.states.AttackState;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.SurvivorDesc;
import zombie.characters.action.ActionContext;
import zombie.characters.action.ActionGroup;
import zombie.characters.action.ActionState;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.SurvivorFactory;
import zombie.core.Core;
import zombie.core.skinnedmodel.ModelManager;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.Clothing;
import zombie.inventory.types.DrainableComboItem;
import zombie.inventory.types.Food;
import zombie.inventory.types.HandWeapon;
import zombie.inventory.types.Key;
import zombie.iso.IsoCell;
import zombie.iso.IsoDirections;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.objects.IsoWindow;
import zombie.vehicles.BaseVehicle;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Narrow Lua-facing authority for creating and owning native companions. */
public final class SCBridge {
    public static final String PROTOCOL = "42.20-isocompanion-8";
    public static final int ITEM_FACT_FOOD = 1;
    public static final int ITEM_FACT_DRAINABLE = 1 << 1;
    public static final int ITEM_FACT_HAND_WEAPON = 1 << 2;
    public static final int ITEM_FACT_MAGAZINE = 1 << 3;
    public static final int ITEM_FACT_KEY = 1 << 4;
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

    private static boolean onGameThread() {
        return Thread.currentThread() == MainThread.mainThread;
    }

    private static void put(KahluaTable table, String key, Object value) {
        table.rawset(key, value);
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
                out.rawset(output++, (Object) zombie);
                out.rawset(output++, Float.valueOf(zombie.getX()));
                out.rawset(output++, Float.valueOf(zombie.getY()));
                out.rawset(output++, Float.valueOf(zombie.getZ()));
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
                barrier = owner.getDoor(north); kind = "door";
            }
            if (barrier == null && from.isWindowTo(to)) {
                barrier = owner.getWindow(north);
                if (barrier == null) barrier = owner.getThumpableWindow(north);
                if (barrier == null) {
                    barrier = owner.getWindowFrame(north);
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
            ArrayList<IsoObject> objects = square.getSpecialObjects();
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

    public static boolean isCompanion(Object candidate) {
        return candidate instanceof SCNativeCompanion actor && isOwned(actor);
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
    public static String startZombieAttack(IsoZombie zombie, SCNativeCompanion actor) {
        if (zombie == null) return "invalid_zombie";
        if (!isOwned(actor)) return "unowned_companion";
        if (zombie.isDead() || actor.isDead() || actor.isOnFloor()) return "invalid_life_state";
        if (actor.getVehicle() != null) return "companion_in_vehicle";
        if (actor.isZombiesDontAttack()) return "companion_attack_immunity";
        if (zombie.getTarget() != actor) return "different_target";

        float dx = actor.getX() - zombie.getX();
        float dy = actor.getY() - zombie.getY();
        float dz = Math.abs(actor.getZ() - zombie.getZ());
        // getShouldAttack() reads this cached vector rather than recomputing the
        // distance. The local-player vision pass normally refreshes it; a detached
        // companion never participates in that pass, which is the actual reason
        // the otherwise-valid action state fell straight back to idle.
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

        // IsoZombie.postupdate() recalculates this from isTargetVisible(), which
        // cannot find a deliberately detached companion, after the animation
        // graph has updated. Lua invokes this adapter after postupdate on every
        // close-range resolver tick, keeping the bit valid for the next graph
        // update. The target/range/z-level/obstruction checks above make this a
        // narrow replacement for the missing local-player visibility slot, not
        // a way for zombies to attack through walls or at a distance.
        if (ZOMBIE_CAN_SEE_TARGET == null) return "visibility_adapter_unavailable";
        try {
            ZOMBIE_CAN_SEE_TARGET.setBoolean(zombie, true);
        } catch (IllegalAccessException | IllegalArgumentException failure) {
            return "visibility_adapter_failed";
        }
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
        zombie.setTargetSeenTime(Math.max(0.51f, zombie.getTargetSeenTime()));
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

    /**
     * Hand a companion timed-action start to the main loop after the exposing
     * LuaJavaInvoker has returned. IsoGameCharacter.StartAction synchronously
     * enters Lua callbacks; doing that inside the original Lua -> Java call
     * corrupts Kahlua's pooled ReturnValues frame for a non-local companion.
     */
    static void queueCompanionActionStart(SCNativeCompanion actor, BaseAction action)
            throws RejectedExecutionException {
        queueAfterLua(() -> actor.completeDeferredActionStart(action));
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
