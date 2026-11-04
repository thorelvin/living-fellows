// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import se.krka.kahlua.vm.KahluaTable;
import zombie.MainThread;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.savefile.PlayerDB;
import zombie.world.moddata.GlobalModData;

/**
 * The save barrier for a remote arrival. Lua owns the companion snapshots and
 * registry cleanup; this lease owns the exact native actors and view being
 * retired. It neither constructs actors nor changes their position.
 */
final class SCRemoteArrival {
    private SCRemoteArrival() {}

    static final class Member {
        final SCNativeCompanion actor;
        final String id;
        final IsoGridSquare square;
        final float x, y, z;
        final boolean originalGodMode;
        private boolean protectionFailureLogged;
        private boolean restorationFailureLogged;

        Member(SCNativeCompanion actor) {
            this.actor = actor;
            KahluaTable data = actor.getModData();
            Object value = data == null ? null : data.rawget("SC_Id");
            if (!(value instanceof String identity) || !identity.startsWith("sc-")
                    || identity.length() < 4 || identity.length() > 80) {
                throw new IllegalStateException("remote arrival member has no stable companion identity");
            }
            id = identity;
            square = actor.getCurrentSquare();
            x = actor.getX();
            y = actor.getY();
            z = actor.getZ();
            originalGodMode = actor.isGodMod();
        }
    }

    static final class Lease {
        final long token;
        final IsoWorld world;
        final IsoCell cell;
        final IsoPlayer[] slots;
        final IsoPlayer primary;
        final int primarySqlId;
        final SCNativeCompanion leader;
        final IsoChunkMap primaryMap, companionMap;
        final int slotSqlId;
        final ArrayList<Member> members;
        private KahluaTable acknowledgedDocument;
        private String acknowledgedStoreKey;
        private SCVehicleSaveBarrier.Ticket vehicleSave;
        private boolean deadTeardownStarted;
        private int deadLightingX, deadLightingY;

        Lease(long token, IsoWorld world, IsoCell cell, IsoPlayer[] slots,
                SCNativeCompanion leader, IsoChunkMap primaryMap,
                IsoChunkMap companionMap, int slotSqlId, ArrayList<Member> members) {
            this.token = token;
            this.world = world;
            this.cell = cell;
            this.slots = slots;
            primary = slots[0];
            primarySqlId = primary.sqlId;
            this.leader = leader;
            this.primaryMap = primaryMap;
            this.companionMap = companionMap;
            this.slotSqlId = slotSqlId;
            this.members = members;
        }

        void requireContext(SCNativeCompanion currentLeader) {
            requireContext(currentLeader, false);
            if (acknowledged()) retireAcknowledgedMembers();
        }

        private void requireContext(SCNativeCompanion currentLeader, boolean allowClosingMap) {
            requireGameThread();
            if (IsoWorld.instance != world || world.getCell() != cell
                    || IsoPlayer.players != slots || slots.length != 4
                    || slots[0] != primary || slots[1] != leader
                    || slots[2] != null || slots[3] != null
                    || IsoPlayer.numPlayers != 2 || currentLeader != leader
                    || primary.getPlayerNum() != 0 || leader.getPlayerNum() != 1
                    || primary.sqlId != primarySqlId || leader.sqlId != slotSqlId
                    || primary.isDead() || primary.getCurrentSquare() == null
                    || world.addCoopPlayers == null || !world.addCoopPlayers.isEmpty()
                    || cell.getChunkMap(0) != primaryMap || cell.getChunkMap(1) != companionMap
                    || primaryMap.ignore || companionMap.ignore && !allowClosingMap
                    || primaryMap.playerId != 0 || companionMap.playerId != 1) {
                throw new IllegalStateException("remote arrival view ownership changed");
            }
        }

        /** A pre-save death outcome can replace only this exact still-owned lease. */
        void requireDeadTeardown(SCNativeCompanion currentLeader,
                                 Iterable<SCNativeCompanion> retainedCorpses) {
            if (acknowledged()) {
                throw new IllegalStateException("acknowledged remote arrival cannot become an all-dead cancellation");
            }
            requireContext(currentLeader, deadTeardownStarted);
            for (Member member : members) {
                SCNativeCompanion actor = member.actor;
                boolean retained = false;
                for (SCNativeCompanion corpse : retainedCorpses) {
                    if (corpse == actor) { retained = true; break; }
                }
                if (!actor.isDead() || !actor.isCorpseReady() || !retained
                        || actor.isRemoteArrivalRetired()) {
                    throw new IllegalStateException("remote arrival all-dead corpse is not retained: " + member.id);
                }
            }
        }

        boolean deadTeardownStarted() { return deadTeardownStarted; }
        int deadLightingX() { return deadLightingX; }
        int deadLightingY() { return deadLightingY; }

        void beginDeadTeardown(int lightingX, int lightingY) {
            if (!deadTeardownStarted) {
                deadLightingX = lightingX;
                deadLightingY = lightingY;
                deadTeardownStarted = true;
            }
        }

        void finishDeadTeardown() {
            if (acknowledged()) {
                throw new IllegalStateException("acknowledged remote arrival still owns its durable cleanup");
            }
            SCVehicleSaveBarrier.detach(vehicleSave, token);
        }

        void requireLiveMembers() {
            for (Member member : members) {
                SCNativeCompanion actor = member.actor;
                if (!SCBridge.isCompanion(actor) || !actor.isBridgeHealthy() || actor.isDead()
                        || actor.getCurrentSquare() != member.square || actor.getVehicle() != null
                        || Float.compare(actor.getX(), member.x) != 0
                        || Float.compare(actor.getY(), member.y) != 0
                        || Float.compare(actor.getZ(), member.z) != 0) {
                    throw new IllegalStateException("remote arrival member changed before snapshot acknowledgement: "
                            + member.id);
                }
            }
        }

        void acknowledge(String storeKey, KahluaTable document) throws IOException {
            requireLiveMembers();
            GlobalModData store = GlobalModData.instance;
            if (store == null || storeKey == null || storeKey.isBlank()
                    || storeKey.length() > 128 || document == null
                    || Core.getInstance().isNoSave()) {
                throw new IllegalStateException("remote arrival save acknowledgement is unavailable");
            }
            KahluaTable envelope = store.get(storeKey);
            if (envelope == null || envelope.rawget("document") != document) {
                throw new IllegalStateException("remote arrival acknowledgement is not the installed save document");
            }
            verifyDocument(document, members, slotSqlId);
            SCVehicleSaveBarrier.verifyDocument(vehicleSave, token, document);
            // Set the acknowledgement only after the native write completes.
            // PlayerDB.saveLocalPlayersForce() queues asynchronously and is not
            // a substitute for this full-roster LF save barrier.
            store.save();
            acknowledgedStoreKey = storeKey;
            acknowledgedDocument = document;
            retireAcknowledgedMembers();
        }

        boolean acknowledged() { return acknowledgedDocument != null; }

        void attachVehicleSave(long ticket) {
            if (acknowledged()) throw new IllegalStateException("vehicle proof must attach before arrival acknowledgement");
            if (vehicleSave != null && vehicleSave.id != ticket)
                throw new IllegalStateException("arrival already owns a different vehicle proof");
            SCVehicleSaveBarrier.Ticket attached = SCVehicleSaveBarrier.attach(ticket, token);
            vehicleSave = attached;
        }

        void retireAcknowledgedMembers() {
            retireAcknowledgedMembers(SCNativeCompanion::protectRemoteArrivalRetirement);
        }

        /** Package-only operation seam for the real-JAR exception control. */
        void retireAcknowledgedMembers(Consumer<SCNativeCompanion> protect) {
            if (!acknowledged()) {
                throw new IllegalStateException("unacknowledged remote arrival cannot retire live companions");
            }
            // Mark the WHOLE exact crew before its first fallible cleanup or
            // native cheat operation. Read-only god/invulnerable overrides and
            // Hit guards already protect every old object at this boundary.
            for (Member member : members) member.actor.markRemoteArrivalRetired();
            for (Member member : members) {
                try {
                    protect.accept(member.actor);
                } catch (RuntimeException | LinkageError failure) {
                    // The disk commit and direct retirement bits are already
                    // authoritative. A native flag callback cannot turn that
                    // success into a reported failed/abortable acknowledgement.
                    if (!member.protectionFailureLogged) {
                        member.protectionFailureLogged = true;
                        System.err.println("[Living Fellows] remote arrival native protection pending id="
                                + member.id + " cause=" + failure.getClass().getSimpleName());
                    }
                }
            }
        }

        void finishRetirement() {
            finishRetirement(SCNativeCompanion::finishRemoteArrivalRetirement);
            SCVehicleSaveBarrier.detach(vehicleSave, token);
        }

        /** Package-only operation seam; callers have already detached this crew. */
        void finishRetirement(BiConsumer<SCNativeCompanion, Boolean> restore) {
            for (Member member : members) {
                if (member.actor.isRemoteArrivalRetired()) {
                    try {
                        restore.accept(member.actor, member.originalGodMode);
                    } catch (RuntimeException | LinkageError failure) {
                        // These exact old objects are now detached/discarded.
                        // Keep a failed one inert; never throw after map/slot
                        // teardown committed or reactivate a stale actor.
                        member.actor.markRemoteArrivalRetired();
                        if (!member.restorationFailureLogged) {
                            member.restorationFailureLogged = true;
                            System.err.println("[Living Fellows] detached remote arrival flag restore pending id="
                                    + member.id + " cause=" + failure.getClass().getSimpleName());
                        }
                    }
                }
            }
        }

        void requireDetachedMembers() {
            if (acknowledgedDocument == null) {
                throw new IllegalStateException("remote arrival snapshots have not been durably acknowledged");
            }
            GlobalModData store = GlobalModData.instance;
            KahluaTable envelope = store == null ? null : store.get(acknowledgedStoreKey);
            if (envelope == null || envelope.rawget("document") != acknowledgedDocument) {
                throw new IllegalStateException("remote arrival acknowledged save document changed");
            }
            verifyDocument(acknowledgedDocument, members, slotSqlId);
            SCVehicleSaveBarrier.verifyDocument(vehicleSave, token, acknowledgedDocument);
            for (Member member : members) {
                SCNativeCompanion actor = member.actor;
                if (SCBridge.isCompanion(actor) || actor.isExistInTheWorld()
                        || actor.isAddedToModelManager() || actor.isScheduled()
                        || actor.getCurrentSquare() != null || actor.getSquare() != null
                        || actor.getMovingSquare() != null || actor.getVehicle() != null
                        || actor.hasCompanionSpeech()) {
                    throw new IllegalStateException("remote arrival native cleanup is incomplete: " + member.id);
                }
            }
        }

        void requireCancelable() {
            if (acknowledgedDocument != null) {
                throw new IllegalStateException("durably acknowledged remote arrival must finish cleanup");
            }
            // A failed capture/write may take several ticks. Living actors can
            // move meanwhile; their old coordinates must not trap a pre-save
            // lease forever. Cancellation changes no actor or placement and is
            // safe only while every exact crew object is still fully owned and
            // attached. A partially retired crew must finish its transaction.
            for (Member member : members) {
                SCNativeCompanion actor = member.actor;
                if (!SCBridge.isCompanion(actor) || !actor.isBridgeHealthy() || actor.isDead()
                        || actor.getCurrentSquare() == null || actor.getVehicle() != null
                        || !actor.isExistInTheWorld() || !actor.isScheduled()) {
                    throw new IllegalStateException("remote arrival cannot cancel a detached member: " + member.id);
                }
            }
            SCVehicleSaveBarrier.detach(vehicleSave, token);
        }
    }

    static Lease prepare(long token, SCNativeCompanion leader, KahluaTable roster,
            int minX, int minY, int maxX, int maxY, int z) {
        requireGameThread();
        if (minX > maxX || minY > maxY || z < -32 || z > 31
                || (long) maxX - minX > 1024 || (long) maxY - minY > 1024) {
            throw new IllegalStateException("remote arrival camp bounds are invalid");
        }
        IsoPlayer[] slots = IsoPlayer.players;
        IsoWorld world = IsoWorld.instance;
        IsoCell cell = world == null ? null : world.getCell();
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        if (leader == null || primary == null || primary.isDead()
                || primary.getCurrentSquare() == null || slots[1] != leader
                || primary.getPlayerNum() != 0 || leader.getPlayerNum() != 1
                || slots[2] != null || slots[3] != null || IsoPlayer.numPlayers != 2
                || world == null || cell == null || world.addCoopPlayers == null
                || !world.addCoopPlayers.isEmpty() || roster == null) {
            throw new IllegalStateException("local companion view is not ready for remote arrival");
        }
        IsoChunkMap primaryMap = cell.getChunkMap(0), companionMap = cell.getChunkMap(1);
        if (primaryMap == null || companionMap == null || primaryMap == companionMap
                || primaryMap.ignore || companionMap.ignore
                || primaryMap.playerId != 0 || companionMap.playerId != 1) {
            throw new IllegalStateException("remote arrival chunk-map ownership is unavailable");
        }
        ArrayList<Member> members = new ArrayList<>();
        IdentityHashMap<SCNativeCompanion, Boolean> actors = new IdentityHashMap<>();
        HashSet<String> ids = new HashSet<>();
        for (int index = 1; index <= 4; index++) {
            Object value = roster.rawget((double) index);
            if (value == null) break;
            if (!(value instanceof SCNativeCompanion actor) || !SCBridge.isCompanion(actor)
                    || !actor.isBridgeHealthy() || actor.isDead() || actor.getVehicle() != null
                    || actor.getCurrentSquare() == null || !actor.isExistInTheWorld()
                    || !actor.isScheduled()) {
                throw new IllegalStateException("remote arrival requires living unseated loaded companions");
            }
            Member member = new Member(actor);
            if (!Float.isFinite(member.x) || !Float.isFinite(member.y) || !Float.isFinite(member.z)
                    || member.square.getCell() != cell || member.square.getChunk() == null
                    || member.x < minX || member.x >= (double) maxX + 1
                    || member.y < minY || member.y >= (double) maxY + 1 || member.z != z
                    || member.square.getX() < companionMap.getWorldXMinTiles()
                    || member.square.getX() > companionMap.getWorldXMaxTiles()
                    || member.square.getY() < companionMap.getWorldYMinTiles()
                    || member.square.getY() > companionMap.getWorldYMaxTiles()) {
                throw new IllegalStateException("remote arrival member is outside the loaded camp: " + member.id);
            }
            if (actors.put(actor, Boolean.TRUE) != null || !ids.add(member.id)) {
                throw new IllegalStateException("remote arrival roster contains a duplicate identity");
            }
            members.add(member);
        }
        if (members.isEmpty() || roster.rawget(5.0) != null || !actors.containsKey(leader)) {
            throw new IllegalStateException("remote arrival needs its exact leader and one to four companions");
        }
        for (int index = members.size() + 1; index <= 4; index++) {
            if (roster.rawget((double) index) != null) {
                throw new IllegalStateException("remote arrival roster must be a dense list");
            }
        }
        if (leader.sqlId == primary.sqlId) {
            throw new IllegalStateException("remote arrival companion identity overlaps the primary player");
        }
        if (leader.sqlId < 2) {
            PlayerDB db = PlayerDB.getInstance();
            if (db == null) throw new IllegalStateException("native local-player database is unavailable");
            db.saveLocalPlayersForce();
        }
        if (leader.sqlId < 2 || leader.sqlId == primary.sqlId) {
            throw new IllegalStateException("native save did not reserve a companion slot identity");
        }
        return new Lease(token, world, cell, slots, leader, primaryMap,
                companionMap, leader.sqlId, members);
    }

    static void verifyDocument(KahluaTable document, ArrayList<Member> members, int slotSqlId) {
        if (!(document.rawget("viewSlot") instanceof KahluaTable viewSlot)
                || !numberEquals(viewSlot.rawget("schema"), 1)
                || !numberEquals(viewSlot.rawget("slotSqlId"), slotSqlId)
                || !(document.rawget("expedition") instanceof KahluaTable expedition)
                || !numberEquals(expedition.rawget("schema"), 2)
                || !"idle".equals(expedition.rawget("state"))
                || !numberEquals(expedition.rawget("slotSqlId"), slotSqlId)
                || expedition.rawget("roster") != null || expedition.rawget("survivors") != null
                || expedition.rawget("leaderId") != null || expedition.rawget("scout") != null) {
            throw new IllegalStateException("remote arrival save has not finalized the mission and companion slot");
        }
        Object companions = document.rawget("companions");
        if (!(companions instanceof KahluaTable records)) {
            throw new IllegalStateException("remote arrival save has no companion snapshots");
        }
        for (Member member : members) {
            Object value = records.rawget(member.id);
            if (!(value instanceof KahluaTable record)
                    || !member.id.equals(record.rawget("id"))
                    || !Boolean.TRUE.equals(record.rawget("restorePrimaryOnly"))
                    || !(record.rawget("position") instanceof KahluaTable position)
                    || !numberEquals(position.rawget("x"), member.square.getX())
                    || !numberEquals(position.rawget("y"), member.square.getY())
                    || !numberEquals(position.rawget("z"), member.square.getZ())
                    || !(record.rawget("inventory") instanceof KahluaTable)
                    || !(record.rawget("vitals") instanceof KahluaTable)) {
                throw new IllegalStateException("remote arrival save does not preserve the captured member: "
                        + member.id);
            }
        }
    }

    private static boolean numberEquals(Object value, int expected) {
        return value instanceof Number number && number.doubleValue() == expected;
    }

    private static void requireGameThread() {
        if (Thread.currentThread() != MainThread.mainThread) {
            throw new IllegalStateException("remote arrival requires the game thread");
        }
    }
}
