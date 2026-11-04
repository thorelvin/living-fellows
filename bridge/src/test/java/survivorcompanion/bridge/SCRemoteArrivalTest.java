// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import se.krka.kahlua.vm.KahluaTable;
import zombie.MainThread;
import zombie.characters.IsoPlayer;
import zombie.chat.ChatElement;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.vehicles.BaseVehicle;
import zombie.world.moddata.GlobalModData;

/** Real-JAR, no-render controls for the remote-arrival save/detachment barrier. */
public final class SCRemoteArrivalTest {
    private static Object unsafe;
    private static Method allocate;
    private static int checks;

    private static void require(boolean value, String reason) {
        checks++;
        if (!value) throw new AssertionError(reason);
    }

    private static Field field(Class<?> type, String name) throws Exception {
        for (Class<?> current = type; current != null; current = current.getSuperclass()) {
            try {
                Field result = current.getDeclaredField(name);
                result.setAccessible(true);
                return result;
            } catch (NoSuchFieldException ignored) {}
        }
        throw new NoSuchFieldException(type.getName() + "." + name);
    }

    private static void set(Object object, String name, Object value) throws Exception {
        field(object.getClass(), name).set(object, value);
    }

    private static <T> T empty(Class<T> type) throws Exception {
        return type.cast(allocate.invoke(unsafe, type));
    }

    private static void slots(IsoPlayer[] value) throws Exception {
        Field players = field(IsoPlayer.class, "players");
        Class<?> type = unsafe.getClass();
        Object base = type.getMethod("staticFieldBase", Field.class).invoke(unsafe, players);
        long offset = ((Number) type.getMethod("staticFieldOffset", Field.class)
                .invoke(unsafe, players)).longValue();
        type.getMethod("putObject", Object.class, long.class, Object.class)
                .invoke(unsafe, base, offset, value);
    }

    private static KahluaTable table() throws Exception {
        return (KahluaTable) Class.forName("se.krka.kahlua.j2se.KahluaTableImpl")
                .getConstructor(java.util.Map.class).newInstance(new HashMap<>());
    }

    private static void refuses(Runnable operation, String reason) {
        boolean refused = false;
        try { operation.run(); }
        catch (IllegalStateException expected) { refused = true; }
        require(refused, reason);
    }

    @SuppressWarnings("unchecked")
    private static Set<SCNativeCompanion> owned() throws Exception {
        return (Set<SCNativeCompanion>) field(SCBridge.class, "OWNED").get(null);
    }

    private static IsoGridSquare square(int x, int y) throws Exception {
        IsoGridSquare result = empty(IsoGridSquare.class);
        set(result, "x", x); set(result, "y", y); set(result, "z", 0);
        set(result, "chunk", empty(IsoChunk.class));
        set(result, "movingObjects", new ArrayList<>());
        return result;
    }

    private static void place(IsoPlayer actor, IsoGridSquare square) throws Exception {
        Field cheats = field(actor.getClass(), "cheats");
        cheats.set(actor, cheats.getType().getConstructor().newInstance());
        set(actor, "health", 75.0f);
        set(actor, "x", square.getX() + .5f);
        set(actor, "y", square.getY() + .5f);
        set(actor, "z", 0.0f);
        set(actor, "current", square);
        set(actor, "square", square);
        set(actor, "movingSq", square);
        square.getMovingObjects().add(actor);
    }

    private static SCNativeCompanion actor(String id, IsoCell cell, int x, int y)
            throws Exception {
        SCNativeCompanion actor = empty(SCNativeCompanion.class);
        place(actor, square(x, y));
        set(actor, "bridgeFailure", "");
        set(actor, "chatElement", empty(ChatElement.class));
        set(actor, "bridgeCell", cell);
        set(actor, "playerIndex", SCNativeCompanion.RESERVED_NON_LOCAL_PLAYER_INDEX);
        KahluaTable data = table(); data.rawset("SC_Id", id);
        actor.getClass().getMethod("setModData", KahluaTable.class).invoke(actor, data);
        cell.getObjectList().add(actor);
        owned().add(actor);
        return actor;
    }

    private static KahluaTable document(ArrayList<SCRemoteArrival.Member> members)
            throws Exception {
        KahluaTable result = table(), records = table();
        result.rawset("companions", records);
        KahluaTable viewSlot = table(), expedition = table();
        viewSlot.rawset("schema", 1.0); viewSlot.rawset("slotSqlId", 2.0);
        expedition.rawset("schema", 2.0); expedition.rawset("state", "idle");
        expedition.rawset("slotSqlId", 2.0);
        result.rawset("viewSlot", viewSlot); result.rawset("expedition", expedition);
        for (SCRemoteArrival.Member member : members) {
            KahluaTable record = table(), position = table();
            record.rawset("id", member.id);
            record.rawset("restorePrimaryOnly", true);
            position.rawset("x", (double) member.square.getX());
            position.rawset("y", (double) member.square.getY());
            position.rawset("z", (double) member.square.getZ());
            record.rawset("position", position);
            record.rawset("inventory", table()); record.rawset("vitals", table());
            records.rawset(member.id, record);
        }
        return result;
    }

    private static IsoChunkMap map(int slot, int min, int max) throws Exception {
        IsoChunkMap map = empty(IsoChunkMap.class);
        map.playerId = slot;
        set(map, "chunksSwapA", new IsoChunk[9]);
        set(map, "chunksSwapB", new IsoChunk[9]);
        set(map, "xMinTiles", min); set(map, "xMaxTiles", max);
        set(map, "yMinTiles", min); set(map, "yMaxTiles", max);
        return map;
    }

    @SuppressWarnings("unchecked")
    private static void preAckDeadTeardown(SCNativeCompanion leader, SCNativeCompanion follower,
                                          KahluaTable roster, IsoChunkMap companionMap) throws Exception {
        Field leaseField = field(SCSplitScreenProbe.class, "remoteArrival");
        Object priorLease = leaseField.get(null);
        ArrayList<SCNativeCompanion> retained = (ArrayList<SCNativeCompanion>) field(
                SCSplitScreenProbe.class, "retainedCorpseActors").get(null);
        ArrayList<SCNativeCompanion> priorRetained = new ArrayList<>(retained);
        Map<Long, SCVehicleSaveBarrier.Ticket> tickets = (Map<Long, SCVehicleSaveBarrier.Ticket>) field(
                SCVehicleSaveBarrier.class, "tickets").get(null);
        Map<Long, SCVehicleSaveBarrier.Ticket> priorTickets = new HashMap<>(tickets);
        boolean priorIgnore = companionMap.ignore;
        float leaderHealth = leader.getHealth(), followerHealth = follower.getHealth();
        boolean leaderReady = leader.isCorpseReady(), followerReady = follower.isCorpseReady();
        try {
            SCRemoteArrival.Lease lease = SCRemoteArrival.prepare(9, leader, roster, 498, 498, 504, 504, 0);
            leaseField.set(null, lease);
            SCVehicleSaveBarrier.Context context = new SCVehicleSaveBarrier.Context(
                    lease.world, lease.cell, Path.of("."), 123);
            SCVehicleSaveBarrier.State carState = new SCVehicleSaveBarrier.State(
                    17, 100.5f, 100.5f, 0, 0, false, false, true, "proof");
            SCVehicleSaveBarrier.Ticket ticket = new SCVehicleSaveBarrier.Ticket(1000009, context,
                    empty(BaseVehicle.class), carState, "proof",
                    new SCVehicleSaveBarrier.Snapshot(17, 12, 12, 100.5f, 100.5f, 123, new byte[] {1}), null);
            ticket.attachedLease = lease.token;
            tickets.put(ticket.id, ticket);
            set(lease, "vehicleSave", ticket);
            int[] calls = { 0, 0 };
            Runnable saved = () -> calls[0]++;
            java.util.function.Consumer<SCRemoteArrival.Lease> unloaded = value -> calls[1]++;
            set(leader, "health", 0.0f); set(leader, "corpseReady", true);
            retained.clear(); retained.add(leader); retained.add(follower);
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, unloaded),
                    "a still-living exact follower permitted all-dead lease cancellation");
            set(follower, "health", 0.0f); set(follower, "corpseReady", true);
            set(leader, "corpseReady", false);
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, unloaded),
                    "a pending native corpse permitted all-dead lease cancellation");
            set(leader, "corpseReady", true);
            retained.remove(follower);
            retained.add(empty(SCNativeCompanion.class));
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, unloaded),
                    "a different retained actor replaced the captured follower's corpse authority");
            retained.clear(); retained.add(leader); retained.add(follower);
            set(lease, "acknowledgedDocument", table());
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, unloaded),
                    "an acknowledged lease was discarded as a pre-ack all-dead outcome");
            require(calls[0] == 0 && calls[1] == 0 && ticket.attachedLease == lease.token,
                    "failed dead preflight crossed its corpse/native boundary or detached the car proof");
            set(lease, "acknowledgedDocument", null);
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader,
                    () -> { calls[0]++; throw new IllegalStateException("injected corpse save failure"); }, unloaded),
                    "a failed corpse save was reported as a successful all-dead teardown");
            require(leaseField.get(null) == lease && calls[1] == 0 && !companionMap.ignore
                            && ticket.attachedLease == lease.token && !SCVehicleSaveBarrier.cancel(ticket.id),
                    "corpse save failure discarded the prepared lease, car proof or live map");
            refuses(() -> SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, value -> {
                value.beginDeadTeardown(450, 450);
                companionMap.ignore = true;
                calls[1]++;
                throw new IllegalStateException("injected native unload failure");
            }), "a failed native teardown discarded its prepared lease");
            require(leaseField.get(null) == lease && lease.deadTeardownStarted()
                            && ticket.attachedLease == lease.token,
                    "failed native teardown lost its retry authority or attached vehicle proof");
            refuses(() -> lease.requireContext(leader),
                    "ordinary live/ack context admitted an already-closing secondary map");
            SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, value -> {
                require(value == lease && value.deadTeardownStarted()
                                && value.deadLightingX() == 450 && value.deadLightingY() == 450,
                        "an exact already-closing dead lease could not retain its first lighting witness");
                calls[1]++;
            });
            require(leaseField.get(null) == null && ticket.attachedLease == 0
                            && SCVehicleSaveBarrier.cancel(ticket.id) && calls[0] == 3 && calls[1] == 2,
                    "successful corpse/native teardown retained its orphan lease or uncancellable car proof");
            int beforeSave = calls[0];
            SCSplitScreenProbe.runDeadArrivalTeardown(leader, saved, value -> {
                require(value == null, "generic all-dead teardown acquired an unrelated arrival lease");
                calls[1]++;
            });
            require(calls[0] == beforeSave,
                    "generic all-dead teardown gained the scoped remote-arrival corpse barrier");
        } finally {
            set(leader, "health", leaderHealth); set(follower, "health", followerHealth);
            set(leader, "corpseReady", leaderReady); set(follower, "corpseReady", followerReady);
            companionMap.ignore = priorIgnore;
            leaseField.set(null, priorLease);
            retained.clear(); retained.addAll(priorRetained);
            tickets.clear(); tickets.putAll(priorTickets);
        }
    }

    public static void main(String[] args) throws Exception {
        // PlayerCheats resolves the real single-player capability path, whose
        // GameClient/ServerOptions initialization uses the game's RNG.
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> type = Class.forName("sun.misc.Unsafe");
        Field singleton = field(type, "theUnsafe");
        unsafe = singleton.get(null);
        allocate = type.getMethod("allocateInstance", Class.class);
        IsoPlayer[] priorSlots = IsoPlayer.players;
        int priorCount = IsoPlayer.numPlayers;
        int priorWidth = IsoChunkMap.chunkGridWidth;
        IsoWorld priorWorld = IsoWorld.instance;
        GlobalModData priorStore = GlobalModData.instance;
        Thread priorThread = MainThread.mainThread;
        Field leaderField = field(SCSplitScreenProbe.class, "leader");
        Object priorLeader = leaderField.get(null);
        Field leaseField = field(SCSplitScreenProbe.class, "remoteArrival");
        Object priorLease = leaseField.get(null);
        Set<SCNativeCompanion> priorOwned = new HashSet<>(owned());
        HashMap<Integer, IsoChunk> priorChunks = new HashMap<>(IsoChunkMap.SharedChunks);
        try {
            MainThread.mainThread = Thread.currentThread();
            IsoChunkMap.chunkGridWidth = 3;
            IsoCell cell = empty(IsoCell.class);
            set(cell, "objectList", new HashSet<>());
            IsoChunkMap primaryMap = map(0, 250, 350), companionMap = map(1, 450, 550);
            set(cell, "chunkMap", new IsoChunkMap[] { primaryMap, companionMap, null, null });
            IsoWorld world = empty(IsoWorld.class);
            set(world, "currentCell", cell); world.addCoopPlayers = new ArrayList<>();
            IsoWorld.instance = world;
            IsoPlayer primary = empty(IsoPlayer.class); place(primary, square(300, 300));
            primary.sqlId = 1;
            SCNativeCompanion leader = actor("sc-leader", cell, 500, 500);
            set(leader, "playerIndex", 1);
            leader.sqlId = 2;
            SCNativeCompanion follower = actor("sc-follower", cell, 501, 500);
            follower.setGodMod(true, true);
            slots(new IsoPlayer[] { primary, leader, null, null });
            IsoPlayer.numPlayers = 2;
            leaderField.set(null, leader);
            // Vanilla may refuse a god-mode request for a non-local NPC even
            // with the forced setter. Assert the real observed flags rather
            // than assuming that a fixture request bypassed that permission.
            boolean primaryGodBefore = primary.isGodMod();
            boolean leaderGodBefore = leader.isGodMod();
            boolean followerGodBefore = follower.isGodMod();
            KahluaTable roster = table(); roster.rawset(1, leader); roster.rawset(2, follower);
            refuses(() -> SCRemoteArrival.prepare(1, leader, roster, 100, 100, 110, 110, 0),
                    "a crew outside camp was accepted");
            refuses(() -> SCRemoteArrival.prepare(1, leader, roster, 498, 498, 504, 504, 1),
                    "a crew on the wrong camp floor was accepted");
            roster.rawset(2, leader);
            refuses(() -> SCRemoteArrival.prepare(1, leader, roster, 498, 498, 504, 504, 0),
                    "a duplicate native actor was accepted as a second crew member");
            roster.rawset(1, follower); roster.rawset(2, null);
            refuses(() -> SCRemoteArrival.prepare(1, leader, roster, 498, 498, 504, 504, 0),
                    "a roster without the exact view leader was accepted");
            roster.rawset(1, leader); roster.rawset(2, follower); roster.rawset(5, follower);
            refuses(() -> SCRemoteArrival.prepare(1, leader, roster, 498, 498, 504, 504, 0),
                    "an oversized crew was accepted");
            roster.rawset(5, null);
            SCRemoteArrival.Lease movingLease = SCRemoteArrival.prepare(6, leader, roster, 498, 498, 504, 504, 0);
            leaseField.set(null, movingLease);
            set(leader, "x", 500.75f);
            refuses(movingLease::requireLiveMembers,
                    "an old preparation accepted a moved actor for snapshot acknowledgement");
            owned().remove(follower);
            refuses(movingLease::requireCancelable,
                    "an unacknowledged but partially detached crew was allowed to cancel");
            owned().add(follower);
            require(SCSplitScreenProbe.cancelRemoteArrival(6)
                            && leader.getX() == 500.75f && IsoPlayer.players[1] == leader
                            && !companionMap.ignore,
                    "pre-ack movement trapped the lease or cancellation changed native placement/view");
            set(leader, "x", 500.5f);
            preAckDeadTeardown(leader, follower, roster, companionMap);
            SCRemoteArrival.Lease lease = SCRemoteArrival.prepare(7, leader, roster, 498, 498, 504, 504, 0);
            leaseField.set(null, lease);
            require(lease.members.size() == 2 && lease.slotSqlId == 2,
                    "remote preparation lost a crew member or the reserved slot row");
            require(!leader.isRemoteArrivalRetired() && leader.isGodMod() == leaderGodBefore
                            && primary.isGodMod() == primaryGodBefore && follower.isGodMod() == followerGodBefore
                            && lease.members.get(0).originalGodMode == leaderGodBefore
                            && lease.members.get(1).originalGodMode == followerGodBefore,
                    "unacknowledged preparation changed a protection flag or affected the primary");
            refuses(lease::retireAcknowledgedMembers,
                    "a preparation without a disk acknowledgement retired live actors");
            require(!SCSplitScreenProbe.canReleaseJoinedLeader(),
                    "existing joined release admitted a distant camp");
            require(!SCSplitScreenProbe.primaryAreaContains(500, 500, 0),
                    "a secondary-only loaded camp was admitted for primary restoration");
            set(primary, "x", 495.0f); set(primary, "y", 500.5f);
            require(!SCSplitScreenProbe.canReleaseJoinedLeader(),
                    "joined release ignored primary map ownership when the player was close");
            set(primaryMap, "xMinTiles", 488); set(primaryMap, "xMaxTiles", 511);
            set(primaryMap, "yMinTiles", 488); set(primaryMap, "yMaxTiles", 511);
            set(primaryMap, "worldX", 62); set(primaryMap, "worldY", 62);
            IsoGridSquare querySquare = leader.getCurrentSquare();
            IsoChunk queryChunk = querySquare.getChunk();
            queryChunk.wx = 62; queryChunk.wy = 62;
            set(queryChunk, "loaded", true);
            IsoGridSquare[][] squares = new IsoGridSquare[][] { new IsoGridSquare[64] };
            squares[0][4 * 8 + 4] = querySquare;
            set(queryChunk, "squares", squares);
            set(queryChunk, "minLevel", 0); set(queryChunk, "maxLevel", 0);
            IsoChunk[] chunksA = (IsoChunk[]) field(IsoChunkMap.class, "chunksSwapA").get(primaryMap);
            IsoChunk[] chunksB = (IsoChunk[]) field(IsoChunkMap.class, "chunksSwapB").get(primaryMap);
            chunksA[4] = queryChunk; chunksB[4] = queryChunk;
            set(queryChunk, "refs", new ArrayList<>(java.util.List.of(companionMap)));
            IsoChunkMap.SharedChunks.put((62 << 16) + 62, queryChunk);
            require(!SCSplitScreenProbe.primaryAreaContains(500, 500, 0),
                    "primary bounds alone admitted a chunk owned only by the secondary map");
            queryChunk.refs.add(primaryMap);
            require(SCSplitScreenProbe.primaryAreaContains(500, 500, 0),
                    "a real square owned by the primary map was not admitted");
            IsoChunk actualChunk = queryChunk;
            set(querySquare, "chunk", empty(IsoChunk.class));
            require(!SCSplitScreenProbe.primaryAreaContains(500, 500, 0),
                    "a stale square/chunk identity was admitted for restoration");
            set(querySquare, "chunk", actualChunk);
            require(SCSplitScreenProbe.canReleaseJoinedLeader(), "ordinary nearby joined release regressed");
            set(primary, "x", 483.5f);
            require(!SCSplitScreenProbe.canReleaseJoinedLeader(), "joined release lost its sixteen-tile guard");
            set(primary, "x", 300.5f); set(primary, "y", 300.5f);
            require(!SCSplitScreenProbe.canReleaseRemoteArrival(7),
                    "remote map release skipped the durable snapshot acknowledgement");
            refuses(() -> SCSplitScreenProbe.releaseRemoteArrival(7),
                    "remote release unloaded without snapshots");
            require(!companionMap.ignore && IsoPlayer.players[1] == leader,
                    "refused remote release changed the secondary view");
            KahluaTable saved = document(lease.members);
            SCRemoteArrival.verifyDocument(saved, lease.members, lease.slotSqlId);
            KahluaTable finalized = (KahluaTable) saved.rawget("expedition");
            finalized.rawset("state", "inbound");
            refuses(() -> SCRemoteArrival.verifyDocument(saved, lease.members, lease.slotSqlId),
                    "a crash save that would restart the completed mission was accepted");
            finalized.rawset("state", "idle");
            KahluaTable viewSlot = (KahluaTable) saved.rawget("viewSlot");
            viewSlot.rawset("slotSqlId", 1.0);
            refuses(() -> SCRemoteArrival.verifyDocument(saved, lease.members, lease.slotSqlId),
                    "the primary player's save row was accepted as the reusable companion slot");
            viewSlot.rawset("slotSqlId", 2.0);
            KahluaTable records = (KahluaTable) saved.rawget("companions");
            Object snapshot = records.rawget("sc-follower");
            records.rawset("sc-follower", null);
            refuses(() -> SCRemoteArrival.verifyDocument(saved, lease.members, lease.slotSqlId),
                    "save barrier admitted a missing follower snapshot");
            records.rawset("sc-follower", snapshot);
            KahluaTable position = (KahluaTable) ((KahluaTable) snapshot).rawget("position");
            position.rawset("x", 300.0);
            refuses(() -> SCRemoteArrival.verifyDocument(saved, lease.members, lease.slotSqlId),
                    "save barrier admitted a stale or relocated camp position");
            position.rawset("x", 501.0);
            GlobalModData store = empty(GlobalModData.class);
            KahluaTable envelope = table(); envelope.rawset("document", saved);
            set(store, "modData", new HashMap<>(java.util.Map.of("SC_WorldV1", envelope)));
            GlobalModData.instance = store;
            @SuppressWarnings("unchecked")
            ArrayList<IsoChunk> corpseChunks = (ArrayList<IsoChunk>) field(
                    SCSplitScreenProbe.class, "retainedCorpseChunks").get(null);
            ArrayList<IsoChunk> priorCorpseChunks = new ArrayList<>(corpseChunks);
            try {
                IsoChunk invalidCorpseChunk = empty(IsoChunk.class);
                set(invalidCorpseChunk, "refs", new ArrayList<>());
                corpseChunks.clear(); corpseChunks.add(invalidCorpseChunk);
                refuses(() -> SCSplitScreenProbe.acknowledgeRemoteArrival(7, "SC_WorldV1", saved),
                        "a failed physical corpse chunk save permitted the LF acknowledgement");
                require(field(SCRemoteArrival.Lease.class, "acknowledgedDocument").get(lease) == null
                                && !companionMap.ignore && IsoPlayer.players[1] == leader,
                        "corpse save failure crossed the acknowledgement or view-unload boundary");
                require(!leader.isRemoteArrivalRetired() && !follower.isRemoteArrivalRetired()
                                && leader.isGodMod() == leaderGodBefore
                                && follower.isGodMod() == followerGodBefore && primary.isGodMod() == primaryGodBefore,
                        "failed disk acknowledgement activated retirement protection");
                require(SCSplitScreenProbe.releaseDiagnostics().contains("retainedCorpseChunks=1"),
                        "release diagnostics omitted retained corpse ownership");
            } finally {
                corpseChunks.clear(); corpseChunks.addAll(priorCorpseChunks);
            }
            // Post-write fixture: exercise the production postcondition without
            // writing a player's global store from this no-render test.
            set(lease, "acknowledgedStoreKey", "SC_WorldV1");
            set(lease, "acknowledgedDocument", saved);
            int[] protectionCalls = { 0 };
            lease.retireAcknowledgedMembers(actor -> {
                require(leader.isRemoteArrivalRetired() && follower.isRemoteArrivalRetired(),
                        "a fallible protection call ran before the whole crew's direct retirement bits");
                protectionCalls[0]++;
                if (actor == leader) throw new IllegalStateException("injected native protection notification");
                actor.protectRemoteArrivalRetirement();
            });
            require(protectionCalls[0] == 2 && lease.acknowledged(),
                    "native protection exception reversed durable acknowledgement or skipped another crew member");
            require(leader.isRemoteArrivalRetired() && follower.isRemoteArrivalRetired()
                            && leader.isGodMod() && follower.isGodMod()
                            && leader.isInvulnerable() && primary.isGodMod() == primaryGodBefore,
                    "acknowledgement did not quiesce the whole exact crew before the first removal");
            float healthBefore = leader.getHealth();
            leader.update(); leader.postupdate(); follower.update(); follower.postupdate();
            require(leader.Hit(null, primary, 25.0f, false, 1.0f, false) == 0.0f
                            && leader.getHealth() == healthBefore
                            && leader.isBridgeHealthy() && follower.isBridgeHealthy(),
                    "a logical retirement ran a native update/healing pass or accepted incoming Hit damage");
            refuses(() -> SCSplitScreenProbe.cancelRemoteArrival(7),
                    "a durable completed-mission save was cancelled back into active memory");
            require(!SCSplitScreenProbe.canReleaseRemoteArrival(7),
                    "acknowledged snapshots alone permitted live native actors to unload");
            require(primary.getX() == 300.5f && leader.getX() == 500.5f
                            && follower.getX() == 501.5f && primary.sqlId == 1,
                    "remote preflight or refusal changed a physical position or primary save identity");
            for (SCRemoteArrival.Member member : lease.members) {
                owned().remove(member.actor);
                cell.getObjectList().remove(member.actor);
                member.square.getMovingObjects().remove(member.actor);
                set(member.actor, "current", null);
                set(member.actor, "square", null);
                set(member.actor, "movingSq", null);
            }
            require(SCSplitScreenProbe.canReleaseRemoteArrival(7),
                    "durable fully detached remote crew could not reach the unload boundary: "
                            + SCSplitScreenProbe.remoteArrivalFailure());
            require(!companionMap.ignore && IsoPlayer.players[1] == leader,
                    "read-only remote readiness changed view ownership");
            set(follower, "current", lease.members.get(1).square);
            require(!SCSplitScreenProbe.canReleaseRemoteArrival(7),
                    "a follower's lingering square membership escaped the cleanup barrier");
            set(follower, "current", null);
            envelope.rawset("document", table());
            require(!SCSplitScreenProbe.canReleaseRemoteArrival(7),
                    "remote release accepted a replaced acknowledged save document");
            require(!SCSplitScreenProbe.canReleaseRemoteArrival(8), "stale transaction token was accepted");
            int[] restorationCalls = { 0 };
            lease.finishRetirement((actor, original) -> {
                restorationCalls[0]++;
                if (actor == leader) throw new IllegalStateException("injected native flag restore notification");
                actor.finishRemoteArrivalRetirement(original);
            });
            require(restorationCalls[0] == 2 && leader.isRemoteArrivalRetired()
                            && !follower.isRemoteArrivalRetired() && primary.isGodMod() == primaryGodBefore,
                    "disposal exception escaped, skipped another actor, or reactivated a stale old object");
            lease.finishRetirement();
            require(!leader.isRemoteArrivalRetired() && !follower.isRemoteArrivalRetired()
                            && leader.isGodMod() == leaderGodBefore && follower.isGodMod() == followerGodBefore
                            && primary.isGodMod() == primaryGodBefore,
                    "disposal did not restore each original native protection flag or changed the primary");
            System.out.println("REMOTE_ARRIVAL_PASS checks=" + checks
                    + " joined-guard=true snapshots=true detach-barrier=true no-relocation=true");
        } finally {
            owned().clear(); owned().addAll(priorOwned);
            slots(priorSlots); IsoPlayer.numPlayers = priorCount;
            IsoChunkMap.chunkGridWidth = priorWidth;
            IsoWorld.instance = priorWorld; GlobalModData.instance = priorStore;
            MainThread.mainThread = priorThread;
            IsoChunkMap.SharedChunks.clear(); IsoChunkMap.SharedChunks.putAll(priorChunks);
            leaderField.set(null, priorLeader); leaseField.set(null, priorLease);
        }
    }
}
