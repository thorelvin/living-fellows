// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.zip.CRC32;

import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.SurvivorFactory;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.ChunkSaveWorker;
import zombie.iso.objects.IsoDeadBody;
import zombie.radio.ZomboidRadio;
import zombie.savefile.PlayerDB;
import zombie.util.AddCoopPlayer;
import zombie.world.moddata.GlobalModData;

/** Disposable native co-op loader probe. Never include in a release build. */
public final class SCSplitScreenProbe {
    private static volatile SCNativeCompanion leader;
    private static volatile SCNativeCompanion coldProbe;
    private static final ArrayList<IsoChunk> retainedCorpseChunks = new ArrayList<>();
    private static final ArrayList<SCNativeCompanion> retainedCorpseActors = new ArrayList<>();
    private static IsoChunkMap retainedCorpseOwner;

    private static final class CorpseChunkSnapshot {
        final IsoChunk chunk;
        final int wx;
        final int wy;
        final byte[] bytes;

        CorpseChunkSnapshot(IsoChunk chunk, byte[] bytes) {
            this.chunk = chunk;
            this.wx = chunk.wx;
            this.wy = chunk.wy;
            this.bytes = bytes;
        }
    }

    private SCSplitScreenProbe() {}

    /** Read-only counters for the disposable W09 cost probe. */
    public static long monotonicNanos() { return System.nanoTime(); }

    public static long heapUsedBytes() {
        Runtime runtime = Runtime.getRuntime();
        return runtime.totalMemory() - runtime.freeMemory();
    }

    public static int loadedChunkCount(int slot) {
        IsoWorld world = IsoWorld.instance;
        IsoCell cell = world == null ? null : world.getCell();
        IsoChunkMap map = cell == null || slot < 0 || slot > 1
                ? null : cell.getChunkMap(slot);
        if (map == null || map.getChunks() == null) return -1;
        int count = 0;
        for (Object chunk : map.getChunks()) if (chunk != null) count++;
        return count;
    }

    public static int pendingCoopCount() {
        IsoWorld world = IsoWorld.instance;
        return world == null || world.addCoopPlayers == null
                ? -1 : world.addCoopPlayers.size();
    }

    public static int nativeZombieCount() {
        IsoWorld world = IsoWorld.instance;
        IsoCell cell = world == null ? null : world.getCell();
        return cell == null || cell.getZombieList() == null
                ? -1 : cell.getZombieList().size();
    }

    public static boolean isLeader(IsoPlayer candidate) {
        return candidate != null && candidate == leader;
    }

    /** Distinguish the hidden map loader from a registered expedition member. */
    public static boolean isColdProbe(IsoPlayer candidate) {
        return candidate != null && candidate == coldProbe && candidate == leader;
    }

    /** Persist the temporary row at the exact pre-handoff crash boundary. */
    public static int saveColdProbeSlotForTest() {
        SCNativeCompanion temporary = coldProbe;
        IsoPlayer[] slots = IsoPlayer.players;
        if (temporary == null || leader != temporary || slots == null
                || slots.length != 4 || slots[0] == null
                || slots[1] != temporary || IsoPlayer.numPlayers != 2
                || temporary.getCurrentSquare() == null
                || temporary.sqlId < 2 || temporary.sqlId == slots[0].sqlId) {
            throw new IllegalStateException("cold loader is not ready for the save boundary");
        }
        PlayerDB db = PlayerDB.getInstance();
        if (db == null) {
            throw new IllegalStateException("native local-player database is unavailable");
        }
        db.saveLocalPlayersForce();
        return temporary.sqlId;
    }

    /** Flush LF's global ModData without also saving the native player row. */
    public static boolean saveGlobalModDataAfterHandoffForTest() {
        SCNativeCompanion current = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        if (current == null || current == coldProbe || coldProbe != null
                || slots == null || slots.length != 4
                || slots[0] == null || slots[1] != current
                || IsoPlayer.numPlayers != 2 || current.sqlId < 2) {
            throw new IllegalStateException("restored leader is not ready for LF-first save");
        }
        GlobalModData store = GlobalModData.instance;
        if (store == null) {
            throw new IllegalStateException("native global ModData store is unavailable");
        }
        try {
            store.save();
        } catch (IOException failure) {
            throw new IllegalStateException("native global ModData save failed", failure);
        }
        return true;
    }

    /** Lua-visible read of the native slot identity; Kahlua hides Java fields. */
    public static int leaderSqlId() {
        SCNativeCompanion current = leader;
        return current != null && SCBridge.isCompanion(current)
                && IsoPlayer.players != null && IsoPlayer.players[1] == current
                ? current.sqlId : -1;
    }

    public static boolean isLeaderRadioTextContextActive() {
        return leader != null && leader.isCompanionRadioTextContextActive()
                && IsoPlayer.players != null && IsoPlayer.players[1] == leader;
    }

    /** Private proof: pass one transmission through native radio text dispatch. */
    public static void sendTestRadioWithLeaderText(int x, int y, int channel,
            String text, String guid, String codes, float red, float green,
            float blue, int range, boolean television) {
        SCNativeCompanion current = leader;
        if (!acceptsCurrentLayout(IsoPlayer.players)
                || current.isDead() || current.getCurrentSquare() == null
                || text == null || text.isEmpty() || range <= 0) {
            throw new IllegalStateException("native companion radio text probe is unavailable");
        }
        current.beginCompanionRadioTextContext();
        try {
            ZomboidRadio.getInstance().SendTransmission(x, y, channel,
                    text, guid, codes, red, green, blue, range, television);
        } finally {
            current.endCompanionRadioTextContext();
        }
    }

    static boolean acceptsCurrentLayout(IsoPlayer[] slots) {
        SCNativeCompanion current = leader;
        return current != null && slots != null && slots.length == 4
                && IsoPlayer.numPlayers == 2 && slots[0] != null
                && (slots[1] == null || slots[1] == current)
                && slots[2] == null && slots[3] == null
                && current.getPlayerNum() == 1
                && (IsoPlayer.getInstance() == slots[0]
                    || IsoPlayer.getInstance() == current);
    }

    public static SCNativeCompanion promote(SCNativeCompanion actor) {
        return promote(actor, -1);
    }

    /** Reuse only a slot identity retained from a prior LF-owned view. */
    public static SCNativeCompanion promote(SCNativeCompanion actor, int savedSlotSqlId) {
        IsoPlayer original = IsoPlayer.players == null ? null : IsoPlayer.players[0];
        if (actor == null || !SCBridge.isCompanion(actor) || !actor.isBridgeHealthy()) {
            throw new IllegalStateException("leader must be a healthy owned native companion");
        }
        if (leader != null || original == null || IsoPlayer.players.length != 4
                || IsoPlayer.players[1] != null || IsoPlayer.numPlayers != 1
                || actor.getPlayerNum() != SCNativeCompanion.RESERVED_NON_LOCAL_PLAYER_INDEX
                || (savedSlotSqlId != -1 && savedSlotSqlId < 2)
                || savedSlotSqlId == original.sqlId
                || (savedSlotSqlId >= 2 && actor.sqlId != -1
                    && actor.sqlId != savedSlotSqlId)
                || actor.sqlId == original.sqlId) {
            throw new IllegalStateException("local-player slots are not ready for leader promotion");
        }
        IsoWorld world = IsoWorld.instance;
        if (world == null || world.addCoopPlayers == null || actor.getCurrentSquare() == null) {
            throw new IllegalStateException("leader or co-op world loader is unavailable");
        }
        int previousSqlId = actor.sqlId;
        try {
            if (savedSlotSqlId >= 2 && actor.sqlId == -1) {
                actor.sqlId = savedSlotSqlId;
            }
            leader = actor;
            actor.markCoopLeaderForProbe();
            IsoPlayer.numPlayers = 2;
            world.addCoopPlayers.add(new AddCoopPlayer(actor, false));
            IsoPlayer.setInstance(original);
            return actor;
        } catch (RuntimeException | LinkageError failure) {
            IsoPlayer.numPlayers = 1;
            actor.sqlId = previousSqlId;
            actor.unmarkCoopLeaderForProbe();
            leader = null;
            IsoPlayer.setInstance(original);
            throw failure;
        }
    }

    /** Finish a joined trip with a durable identity for the next expedition. */
    public static int persistJoinedLeaderSlotForReuse() {
        String issue = joinedReleaseIssue();
        if (issue != null) throw new IllegalStateException(issue);
        SCNativeCompanion current = leader;
        IsoPlayer primary = IsoPlayer.players[0];
        if (current.sqlId == primary.sqlId) {
            throw new IllegalStateException("companion save identity overlaps the primary player");
        }
        PlayerDB db = PlayerDB.getInstance();
        if (db == null) {
            throw new IllegalStateException("native local-player database is unavailable");
        }
        db.saveLocalPlayersForce();
        if (current.sqlId < 2 || current.sqlId == primary.sqlId) {
            throw new IllegalStateException("native save did not retain a companion slot ID");
        }
        return current.sqlId;
    }

    /** Save the terminal slot while it still belongs to the dead actor. */
    public static int persistDeadLeaderSlotForReuse() {
        SCNativeCompanion current = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        if (current == null || !current.isDead() || primary == null
                || slots[1] != current || IsoPlayer.numPlayers != 2
                || slots[2] != null || slots[3] != null
                || current.sqlId == primary.sqlId) {
            throw new IllegalStateException("dead companion slot is not ready for save");
        }
        PlayerDB db = PlayerDB.getInstance();
        if (db == null) {
            throw new IllegalStateException("native local-player database is unavailable");
        }
        db.saveLocalPlayersForce();
        if (current.sqlId < 2 || current.sqlId == primary.sqlId) {
            throw new IllegalStateException("dead companion save did not retain a slot ID");
        }
        return current.sqlId;
    }

    /** Repoint the already loaded second local view at a surviving team member. */
    public static SCNativeCompanion handoff(SCNativeCompanion successor) {
        SCNativeCompanion previous = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        if (previous == null || !previous.isDead() || successor == null
                || successor == previous || !SCBridge.isCompanion(successor)
                || !successor.isBridgeHealthy() || successor.isDead()
                || successor.getCurrentSquare() == null || primary == null
                || IsoPlayer.numPlayers != 2
                || (slots[1] != previous && slots[1] != null)
                || slots[2] != null || slots[3] != null) {
            throw new IllegalStateException("local companion view is not ready for handoff");
        }
        // PlayerDB saves every occupied local slot. A fresh companion normally
        // has sqlId -1, so handing slot 1 to it would allocate one more local
        // player row at the next save. Reuse the existing slot-1 row when the
        // successor has no row of its own. Never let either actor inherit the
        // primary player's save identity.
        if ((previous.sqlId != -1 && previous.sqlId == primary.sqlId)
                || (successor.sqlId != -1 && successor.sqlId == primary.sqlId)) {
            throw new IllegalStateException("companion save identity overlaps the primary player");
        }
        if (successor.sqlId == -1 && previous.sqlId >= 2) {
            successor.sqlId = previous.sqlId;
        }
        previous.unmarkCoopLeaderForProbe();
        successor.markCoopLeaderForProbe();
        leader = successor;
        slots[1] = successor;
        IsoPlayer.setInstance(primary);
        return successor;
    }

    /** Keep the watched area loaded when a living base leader must retreat. */
    public static SCNativeCompanion handoffLiving(SCNativeCompanion successor) {
        SCNativeCompanion previous = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        if (previous == null || previous.isDead() || successor == null
                || successor == previous || !SCBridge.isCompanion(successor)
                || !successor.isBridgeHealthy() || successor.isDead()
                || successor.getCurrentSquare() == null || primary == null
                || IsoPlayer.numPlayers != 2 || slots[1] != previous
                || slots[2] != null || slots[3] != null
                || previous.getZ() != successor.getZ()
                || Math.abs(previous.getX() - successor.getX()) > 16.0f
                || Math.abs(previous.getY() - successor.getY()) > 16.0f
                || (previous.sqlId != -1 && previous.sqlId == primary.sqlId)
                || (successor.sqlId != -1 && successor.sqlId == primary.sqlId)
                || (successor.sqlId >= 2 && successor.sqlId != previous.sqlId)) {
            throw new IllegalStateException("living companion view handoff is unavailable");
        }
        // LF persists the former leader as a companion. Only slot 1 may retain
        // the game's local-player row; otherwise a later native save can grow
        // duplicate local rows when this view changes hands repeatedly.
        int slotSqlId = previous.sqlId;
        previous.unmarkCoopLeaderForProbe();
        previous.sqlId = -1;
        successor.sqlId = slotSqlId;
        successor.markCoopLeaderForProbe();
        leader = successor;
        slots[1] = successor;
        IsoPlayer.setInstance(primary);
        return successor;
    }

    /** Replace the temporary remote loader with the exact restored LF actor. */
    public static boolean replaceColdProbeWithRestoredLeader(
            SCNativeCompanion restored, int savedSlotSqlId) {
        SCNativeCompanion temporary = coldProbe;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        if (temporary == null || leader != temporary || restored == null
                || restored == temporary || !SCBridge.isCompanion(restored)
                || !restored.isBridgeHealthy() || restored.isDead()
                || restored.getCurrentSquare() == null || primary == null
                || IsoPlayer.numPlayers != 2 || slots[1] != temporary
                || slots[2] != null || slots[3] != null
                || Math.abs(restored.getX() - temporary.getX()) > 16.0f
                || Math.abs(restored.getY() - temporary.getY()) > 16.0f
                || restored.getZ() != temporary.getZ()
                || savedSlotSqlId < -1
                || savedSlotSqlId == primary.sqlId
                || (savedSlotSqlId >= 2 && restored.sqlId != -1
                    && restored.sqlId != savedSlotSqlId)
                || restored.sqlId == primary.sqlId
                || temporary.sqlId == primary.sqlId) {
            throw new IllegalStateException("restored leader cannot take the cold co-op view");
        }
        if (restored.sqlId == -1) {
            if (savedSlotSqlId >= 2) restored.sqlId = savedSlotSqlId;
            else if (temporary.sqlId >= 2) restored.sqlId = temporary.sqlId;
        }
        temporary.unmarkCoopLeaderForProbe();
        restored.markCoopLeaderForProbe();
        slots[1] = restored;
        leader = restored;
        IsoPlayer.setInstance(primary);
        if (!SCBridge.disposeColdProbeActor(temporary)) {
            throw new IllegalStateException("cold co-op actor cleanup is pending: "
                    + SCBridge.getLastFailure());
        }
        coldProbe = null;
        if (restored.sqlId == -1) {
            PlayerDB db = PlayerDB.getInstance();
            if (db == null) {
                throw new IllegalStateException("native local-player database is unavailable");
            }
            db.saveLocalPlayersForce();
            if (restored.sqlId < 2) {
                throw new IllegalStateException("native save did not assign the restored leader an SQL ID");
            }
        }
        return true;
    }

    /** Keep a bounded native corpse chunk alive through ordinary map shifts. */
    public static boolean stageDeadCorpseChunk(SCNativeCompanion actor) {
        if (actor == null || !actor.isDead() || !actor.isCorpseReady()
                || leader == null || IsoPlayer.numPlayers != 2) {
            throw new IllegalStateException("dead companion corpse is not ready for chunk save");
        }
        // The engine may reanimate and detach this exact corpse after the
        // chunk is retained. Its native outcome is still owned by that chunk.
        if (retainedCorpseActors.contains(actor)) return true;
        IsoDeadBody body = actor.getCompanionCorpse();
        IsoGridSquare square = body == null ? null : body.getSquare();
        IsoChunk chunk = square == null ? null : square.getChunk();
        if (chunk == null || !square.getStaticMovingObjects().contains(body)) {
            throw new IllegalStateException("native corpse is not on a loaded square");
        }
        if (retainedCorpseChunks.contains(chunk)) {
            retainedCorpseActors.add(actor);
            return true;
        }
        if (retainedCorpseChunks.size() >= 8) {
            throw new IllegalStateException("corpse chunk retention limit reached");
        }
        IsoWorld world = IsoWorld.instance;
        IsoCell cell = world == null ? null : world.getCell();
        if (cell == null || IsoChunkMap.SharedChunks.get((chunk.wx << 16) + chunk.wy) != chunk) {
            throw new IllegalStateException("corpse chunk is not shared by the live world");
        }
        if (retainedCorpseOwner == null) retainedCorpseOwner = new IsoChunkMap(cell);
        chunk.refs.add(retainedCorpseOwner);
        retainedCorpseChunks.add(chunk);
        retainedCorpseActors.add(actor);
        return true;
    }

    public static int retainedCorpseChunkCount() { return retainedCorpseChunks.size(); }

    /** Write the latest native chunk at the game's save boundary. */
    public static boolean saveRetainedCorpseChunksNow() {
        ArrayList<IsoChunk> chunks = new ArrayList<>();
        ArrayList<CorpseChunkSnapshot> snapshots = new ArrayList<>();
        try {
            for (IsoChunk chunk : retainedCorpseChunks) {
                int key = (chunk.wx << 16) + chunk.wy;
                if (!chunk.refs.contains(retainedCorpseOwner)
                        || IsoChunkMap.SharedChunks.get(key) != chunk) {
                    throw new IllegalStateException("retained corpse chunk changed identity");
                }
                ByteBuffer buffer = chunk.Save(ByteBuffer.allocate(65536),
                        new CRC32(), false);
                snapshots.add(new CorpseChunkSnapshot(chunk,
                        Arrays.copyOf(buffer.array(), buffer.position())));
                chunks.add(chunk);
            }
            if (!chunks.isEmpty()) ChunkSaveWorker.instance.SaveNow(chunks);
            for (CorpseChunkSnapshot snapshot : snapshots) {
                ByteBuffer buffer = ByteBuffer.wrap(snapshot.bytes);
                buffer.position(snapshot.bytes.length);
                IsoChunk.SafeWrite(snapshot.wx, snapshot.wy, buffer);
            }
            return true;
        } catch (IOException failure) {
            throw new IllegalStateException("native corpse chunk save failed", failure);
        }
    }

    /** Save chunks whose final real view has gone; defer chunks still viewed. */
    private static void releaseRetainedCorpseChunks(boolean deferShared) throws IOException {
        ArrayList<IsoChunk> queued = new ArrayList<>();
        ArrayList<CorpseChunkSnapshot> snapshots = new ArrayList<>();
        ArrayList<IsoChunk> deferred = new ArrayList<>();
        for (IsoChunk chunk : retainedCorpseChunks) {
            if (!chunk.refs.contains(retainedCorpseOwner)) {
                throw new IllegalStateException("retained corpse chunk lost its owner");
            }
            if (chunk.refs.size() != 1) {
                if (deferShared) {
                    deferred.add(chunk);
                    continue;
                }
                throw new IllegalStateException("native player map still owns corpse chunk");
            }
            ByteBuffer buffer = chunk.Save(ByteBuffer.allocate(65536), new CRC32(), false);
            snapshots.add(new CorpseChunkSnapshot(chunk,
                    Arrays.copyOf(buffer.array(), buffer.position())));
        }
        for (IsoChunk chunk : retainedCorpseChunks) {
            if (deferred.contains(chunk)) continue;
            chunk.refs.remove(retainedCorpseOwner);
            if (!chunk.refs.isEmpty()) {
                throw new IllegalStateException("retained corpse chunk gained a view during release");
            }
            int key = (chunk.wx << 16) + chunk.wy;
            if (IsoChunkMap.SharedChunks.get(key) != chunk) {
                throw new IllegalStateException("retained corpse chunk changed identity");
            }
            IsoChunkMap.SharedChunks.remove(key);
            chunk.removeFromWorld();
            ChunkSaveWorker.instance.Add(chunk);
            queued.add(chunk);
        }
        if (!queued.isEmpty()) ChunkSaveWorker.instance.SaveNow(queued);
        for (CorpseChunkSnapshot snapshot : snapshots) {
            ByteBuffer buffer = ByteBuffer.wrap(snapshot.bytes);
            buffer.position(snapshot.bytes.length);
            IsoChunk.SafeWrite(snapshot.wx, snapshot.wy, buffer);
        }
        retainedCorpseChunks.clear();
        retainedCorpseChunks.addAll(deferred);
        if (retainedCorpseChunks.isEmpty()) {
            retainedCorpseActors.clear();
            retainedCorpseOwner = null;
        }
    }

    /** Called after ordinary slot-0 world teardown has released its map. */
    public static boolean finalizeCorpseChunksAfterWorldExit() {
        try {
            releaseRetainedCorpseChunks(false);
            return true;
        } catch (IOException failure) {
            throw new IllegalStateException("native corpse chunk restore failed", failure);
        }
    }

    /** Close only the owned second view after every mission member has died. */
    public static boolean releaseDeadLeader() {
        SCNativeCompanion current = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        IsoWorld world = IsoWorld.instance;
        if (current == null || !current.isDead() || primary == null
                || IsoPlayer.numPlayers != 2 || slots[1] != current
                || slots[2] != null || slots[3] != null
                || world == null || world.getCell() == null
                || world.addCoopPlayers == null || !world.addCoopPlayers.isEmpty()) {
            throw new IllegalStateException("dead companion view is not ready for release");
        }
        IsoChunkMap map = world.getCell().getChunkMap(1);
        if (map == null || map.playerId != 1 || retainedCorpseChunks.isEmpty()) {
            throw new IllegalStateException("owned second chunk map is unavailable");
        }
        // Native Unload releases only this map's chunk references, queues
        // unshared chunks for save and clears pending loads and physics state.
        // Ignore late worker completions before invoking it.
        map.ignore = true;
        map.Unload();
        try {
            releaseRetainedCorpseChunks(true);
        } catch (IOException failure) {
            throw new IllegalStateException("native corpse chunk restore failed", failure);
        }
        current.unmarkCoopLeaderForProbe();
        slots[1] = null;
        IsoPlayer.numPlayers = 1;
        IsoPlayer.setInstance(primary);
        leader = null;
        return true;
    }

    /** Main-menu teardown: unload only LF's second map before actor disposal. */
    public static boolean releaseForWorldExit() {
        SCNativeCompanion current = leader;
        if (current == null) {
            if (coldProbe != null) {
                if (!SCBridge.disposeColdProbeActor(coldProbe)) {
                    throw new IllegalStateException("cold co-op actor cleanup is pending: "
                            + SCBridge.getLastFailure());
                }
                coldProbe = null;
            }
            return true;
        }
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        IsoWorld world = IsoWorld.instance;
        if (primary == null || IsoPlayer.numPlayers != 2
                || slots[1] != current || slots[2] != null || slots[3] != null
                || current.sqlId == primary.sqlId || world == null
                || world.getCell() == null || world.addCoopPlayers == null
                || !world.addCoopPlayers.isEmpty()) {
            throw new IllegalStateException("companion view is not ready for world exit");
        }
        IsoChunkMap map = world.getCell().getChunkMap(1);
        if (map == null || map.playerId != 1 || map.ignore) {
            throw new IllegalStateException("owned second chunk map is unavailable");
        }
        // A cold loader must not overwrite the real saved leader's row.
        if (current != coldProbe) {
            PlayerDB db = PlayerDB.getInstance();
            if (db == null) {
                throw new IllegalStateException("native local-player database is unavailable");
            }
            db.saveLocalPlayersForce();
            if (current.sqlId < 2 || current.sqlId == primary.sqlId) {
                throw new IllegalStateException("companion save did not retain a slot ID");
            }
        }
        map.ignore = true;
        map.Unload();
        try {
            releaseRetainedCorpseChunks(true);
        } catch (IOException failure) {
            throw new IllegalStateException("native corpse chunk restore failed", failure);
        }
        current.unmarkCoopLeaderForProbe();
        slots[1] = null;
        IsoPlayer.numPlayers = 1;
        IsoPlayer.setInstance(primary);
        leader = null;
        if (current == coldProbe) {
            if (!SCBridge.disposeColdProbeActor(current)) {
                throw new IllegalStateException("cold co-op actor cleanup is pending: "
                        + SCBridge.getLastFailure());
            }
            coldProbe = null;
        }
        return true;
    }

    /** Flush an active or idle LF descriptor before menu teardown. */
    public static boolean flushGlobalModDataForWorldExit() {
        GlobalModData store = GlobalModData.instance;
        if (store == null) {
            throw new IllegalStateException("native global ModData store is unavailable");
        }
        try {
            store.save();
        } catch (IOException failure) {
            throw new IllegalStateException("native global ModData save failed", failure);
        }
        return true;
    }

    /** Return handoff: the primary player's own map already owns this area. */
    public static boolean canReleaseJoinedLeader() {
        return joinedReleaseIssue() == null;
    }

    private static String joinedReleaseIssue() {
        SCNativeCompanion current = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots == null || slots.length != 4 ? null : slots[0];
        IsoWorld world = IsoWorld.instance;
        if (current == null || current.isDead() || current.getCurrentSquare() == null
                || primary == null || primary.isDead() || primary.getCurrentSquare() == null
                || IsoPlayer.numPlayers != 2 || slots[1] != current
                || slots[2] != null || slots[3] != null
                || world == null || world.getCell() == null
                || world.addCoopPlayers == null || !world.addCoopPlayers.isEmpty()) {
            return "local companion view is not ready for joined release";
        }
        IsoChunkMap primaryMap = world.getCell().getChunkMap(0);
        IsoChunkMap companionMap = world.getCell().getChunkMap(1);
        int x = (int) Math.floor(current.getX());
        int y = (int) Math.floor(current.getY());
        if (primaryMap == null || companionMap == null
                || primaryMap == companionMap || primaryMap.ignore
                || companionMap.ignore || primaryMap.playerId != 0
                || companionMap.playerId != 1
                || x < primaryMap.getWorldXMinTiles()
                || x > primaryMap.getWorldXMaxTiles()
                || y < primaryMap.getWorldYMinTiles()
                || y > primaryMap.getWorldYMaxTiles()
                || Math.abs(primary.getX() - current.getX()) > 16.0f
                || Math.abs(primary.getY() - current.getY()) > 16.0f) {
            return "primary player does not own the companion's loaded area";
        }
        return null;
    }

    public static boolean releaseJoinedLeader() {
        String issue = joinedReleaseIssue();
        if (issue != null) throw new IllegalStateException(issue);
        SCNativeCompanion current = leader;
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer primary = slots[0];
        IsoChunkMap map = IsoWorld.instance.getCell().getChunkMap(1);
        map.ignore = true;
        map.Unload();
        try {
            releaseRetainedCorpseChunks(true);
        } catch (IOException failure) {
            throw new IllegalStateException("native corpse chunk restore failed", failure);
        }
        current.unmarkCoopLeaderForProbe();
        slots[1] = null;
        IsoPlayer.numPlayers = 1;
        IsoPlayer.setInstance(primary);
        leader = null;
        return true;
    }

    public static boolean isReleased() {
        IsoPlayer[] slots = IsoPlayer.players;
        IsoWorld world = IsoWorld.instance;
        IsoChunkMap map = world == null || world.getCell() == null
                ? null : world.getCell().getChunkMap(1);
        return leader == null && slots != null && slots.length == 4
                && slots[0] != null && slots[1] == null
                && slots[2] == null && slots[3] == null
                && IsoPlayer.numPlayers == 1
                && IsoPlayer.getInstance() == slots[0]
                && map != null && map.ignore
                && chunksReleased(map);
    }

    private static boolean chunksReleased(IsoChunkMap map) {
        if (map == null || map.getChunks() == null) return false;
        for (Object chunk : map.getChunks()) {
            if (chunk != null) return false;
        }
        return true;
    }

    public static String releaseDiagnostics() {
        IsoPlayer[] slots = IsoPlayer.players;
        IsoWorld world = IsoWorld.instance;
        IsoChunkMap map = world == null || world.getCell() == null
                ? null : world.getCell().getChunkMap(1);
        return "leader=" + (leader == null ? "nil" : "present")
                + " numPlayers=" + IsoPlayer.numPlayers
                + " slot0=" + (slots == null ? "no-array" : slots[0])
                + " slot1=" + (slots == null ? "no-array" : slots[1])
                + " instanceIsPrimary=" + (slots != null && IsoPlayer.getInstance() == slots[0])
                + " map=" + (map == null ? "nil" : "present")
                + " mapIgnore=" + (map != null && map.ignore)
                + " mapPlayerId=" + (map == null ? "nil" : map.playerId)
                + " chunksReleased=" + chunksReleased(map);
    }

    public static IsoPlayer start(int x, int y, int z) {
        IsoPlayer original = IsoPlayer.getInstance();
        if (original == null || IsoPlayer.players == null || IsoPlayer.players.length != 4
                || IsoPlayer.players[0] != original || IsoPlayer.players[1] != null
                || IsoPlayer.numPlayers != 1) {
            throw new IllegalStateException("expected one original local player in slot 0");
        }
        IsoWorld world = IsoWorld.instance;
        if (world == null || world.getCell() == null || world.addCoopPlayers == null) {
            throw new IllegalStateException("co-op world loader is unavailable");
        }
        IsoCell cell = world.getCell();
        SurvivorDesc descriptor = SurvivorFactory.CreateSurvivor();
        if (descriptor == null) throw new IllegalStateException("survivor factory returned null");

        // This mirrors the stock addPlayerToWorld preparation without assigning
        // a nonexistent physical joypad. AddCoopPlayer initializes the second
        // native chunk map and publishes slot 1 after its distant square loads.
        IsoPlayer observer = new IsoPlayer(cell, descriptor, x, y, z, false);
        IsoPlayer.setInstance(original);
        cell.getAddList().remove(observer);
        cell.getObjectList().remove(observer);
        observer.playerIndex = 1;
        IsoPlayer.numPlayers = 2;
        world.addCoopPlayers.add(new AddCoopPlayer(observer, false));
        IsoPlayer.setInstance(original);
        return observer;
    }

    /**
     * Disposable feasibility probe: can the stock co-op loader stream a remote
     * area around an SCNativeCompanion constructed before its square exists?
     * This actor is deliberately not registered as an LF survivor. It must
     * never be used as proof that a saved mission has restored its leader.
     */
    public static SCNativeCompanion startColdCompanionProbe(
            int x, int y, int z, int savedSlotSqlId) {
        IsoPlayer original = IsoPlayer.getInstance();
        if (original == null || IsoPlayer.players == null
                || IsoPlayer.players.length != 4 || IsoPlayer.players[0] != original
                || IsoPlayer.players[1] != null || IsoPlayer.players[2] != null
                || IsoPlayer.players[3] != null || IsoPlayer.numPlayers != 1
                || leader != null || savedSlotSqlId < -1
                || (savedSlotSqlId >= 2 && savedSlotSqlId == original.sqlId)) {
            throw new IllegalStateException("expected one original local player in slot 0");
        }
        IsoWorld world = IsoWorld.instance;
        if (world == null || world.getCell() == null || world.addCoopPlayers == null) {
            throw new IllegalStateException("co-op world loader is unavailable");
        }
        IsoCell cell = world.getCell();
        if (cell.getGridSquare(x, y, z) != null) {
            throw new IllegalStateException("cold companion probe requires an unloaded square");
        }
        SurvivorDesc descriptor = SurvivorFactory.CreateSurvivor();
        if (descriptor == null) throw new IllegalStateException("survivor factory returned null");
        SCNativeCompanion actor = null;
        try {
            // The constructor can fire OnCreateLivingCharacter. Use the same
            // event mute as the production provider to avoid re-entering Lua
            // while this Lua-to-Java probe call owns Kahlua's return frame.
            actor = SCBridge.constructCompanion(descriptor, cell, x, y, z);
            IsoPlayer.setInstance(original);
            cell.getAddList().remove(actor);
            cell.getObjectList().remove(actor);
            if (actor.getCurrentSquare() != null) {
                throw new IllegalStateException("cold companion already has a square");
            }
            actor.setX(x + 0.5f);
            actor.setY(y + 0.5f);
            actor.setZ(z);
            if (savedSlotSqlId >= 2) actor.sqlId = savedSlotSqlId;
            // The loader is a disposable placeholder, not a saved teammate.
            // Keep its factory underwear out of the second viewport until the
            // exact restored leader takes this slot.
            actor.hideColdBootstrapForProbe();
            actor.markCoopLeaderForProbe();
            leader = actor;
            coldProbe = actor;
            IsoPlayer.numPlayers = 2;
            world.addCoopPlayers.add(new AddCoopPlayer(actor, false));
            IsoPlayer.setInstance(original);
            return actor;
        } catch (RuntimeException | LinkageError failure) {
            if (actor != null) {
                cell.getAddList().remove(actor);
                cell.getObjectList().remove(actor);
                actor.unmarkCoopLeaderForProbe();
            }
            leader = null;
            coldProbe = null;
            IsoPlayer.numPlayers = 1;
            IsoPlayer.setInstance(original);
            throw failure;
        }
    }
}
