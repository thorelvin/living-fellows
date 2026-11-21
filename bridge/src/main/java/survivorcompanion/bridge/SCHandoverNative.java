// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.nio.BufferOverflowException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.sql.DriverManager;
import java.util.Base64;
import zombie.MainThread;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoGameCharacter;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.savefile.PlayerDB;
import zombie.world.moddata.GlobalModData;
import se.krka.kahlua.vm.KahluaTable;

/** Native player serialization/admission. Never drives NPCs or zombie navigation. */
final class SCHandoverNative {
    private static final int MAX_BYTES = 2 * 1024 * 1024;
    private SCHandoverNative() {}

    private static void mainThread() {
        if (Thread.currentThread() != MainThread.mainThread || GameClient.client || GameServer.server)
            throw new IllegalStateException("Handover requires the single-player main thread");
    }

    static boolean finalizeDeath(IsoPlayer player) throws Exception {
        mainThread();
        if (player == null || player != IsoPlayer.players[0] || !player.isDead()
                || player instanceof SCNativeCompanion)
            throw new IllegalStateException("only the dead primary player can finalize Handover");
        // die() is the game's idempotent finalizer: it transfers the exact
        // inventory and creates the native corpse/reanimation lifecycle once.
        IsoPlayer.class.getMethod("die").invoke(player);
        var field = IsoGameCharacter.class.getDeclaredField("diedBody");
        field.setAccessible(true);
        IsoDeadBody corpse = (IsoDeadBody) field.get(player);
        SCSplitScreenProbe.retainPrimaryCorpse(corpse);
        return SCSplitScreenProbe.saveRetainedCorpseChunksNow();
    }

    static String capture(IsoPlayer actor) throws Exception {
        mainThread();
        if (actor == null || actor.isDead()) throw new IllegalStateException("successor is not alive");
        for (int capacity = 32768; capacity <= MAX_BYTES; capacity *= 2) {
            ByteBuffer buffer = ByteBuffer.allocate(capacity);
            try {
                IsoPlayer.class.getMethod("save", ByteBuffer.class).invoke(actor, buffer);
                byte[] bytes = new byte[buffer.position()]; buffer.flip(); buffer.get(bytes);
                int version = ((Number) IsoWorld.class.getMethod("getWorldVersion").invoke(null)).intValue();
                return version + ":" + Base64.getEncoder().encodeToString(bytes);
            } catch (InvocationTargetException failure) {
                if (!(failure.getCause() instanceof BufferOverflowException)) throw failure;
            }
        }
        throw new IllegalStateException("successor exceeds the native player save limit");
    }

    static IsoPlayer prepare(String snapshot, String token) throws Exception {
        mainThread();
        if (snapshot == null || snapshot.length() > MAX_BYTES * 2
                || token == null || !token.matches("lf-handover-[A-Za-z0-9-]{16,96}"))
            throw new IllegalArgumentException("invalid Handover snapshot or token");
        int split = snapshot.indexOf(':');
        if (split < 1 || split > 5) throw new IllegalArgumentException("invalid native snapshot header");
        int version = Integer.parseInt(snapshot.substring(0, split));
        int current = ((Number) IsoWorld.class.getMethod("getWorldVersion").invoke(null)).intValue();
        if (version != current) throw new IllegalStateException("native character save version changed");
        byte[] bytes = Base64.getDecoder().decode(snapshot.substring(split + 1));
        if (bytes.length < 16 || bytes.length > MAX_BYTES) throw new IllegalArgumentException("invalid native snapshot size");
        SCNativeCompanion.LocalPlayerState ownership = SCNativeCompanion.LocalPlayerState.capture();
        if (ownership == null) throw new IllegalStateException("local player ownership unavailable");
        IsoPlayer player = null;
        boolean prepared = false;
        try {
            player = IsoPlayer.class.getConstructor(IsoCell.class).newInstance(IsoWorld.instance.getCell());
            IsoPlayer.class.getMethod("load", ByteBuffer.class, int.class).invoke(player, ByteBuffer.wrap(bytes), version);
            player.setNpc(false);
            player.playerIndex = 0;
            player.serverPlayerIndex = -1;
            player.sqlId = 1;
            Object companionId = player.getModData().rawget("SC_Id");
            // The durable receipt is prepared again for native admission.
            // Its first preparation has already retired SC_Id; retain the
            // survivor identity used by persistent per-person learning.
            if (companionId == null)
                companionId = player.getModData().rawget("LF_HandoverCompanionId");
            player.getModData().rawset("LF_HandoverCompanionId", companionId);
            player.getModData().rawset("SC_Id", null);
            player.getModData().rawset("SC_Recruited", null);
            player.getModData().rawset("LF_HandoverToken", token);
            // A constructor/load is preparation, not publication into the cell.
            prepared = true;
            return player;
        } finally {
            if (player != null) {
                IsoWorld.instance.getCell().getAddList().remove(player);
                IsoWorld.instance.getCell().getObjectList().remove(player);
                if (!prepared) {
                    player.removeFromWorld();
                    player.removeFromSquare();
                }
            }
            if (!ownership.restore()) throw new IllegalStateException("native player preparation changed local ownership");
        }
    }

    static boolean admit(IsoPlayer player) throws Exception {
        return admit(player, false);
    }

    static boolean recover(IsoPlayer player, String token) throws Exception {
        mainThread();
        KahluaTable store = GlobalModData.instance == null ? null : GlobalModData.instance.get("LF_HandoverV1");
        Object raw = store == null ? null : store.rawget("pending");
        if (!(raw instanceof KahluaTable receipt) || !token.equals(receipt.rawget("token"))
                || !"committing".equals(receipt.rawget("phase")))
            throw new IllegalStateException("no durable Handover owns this recovery");
        return admit(player, true);
    }

    private static boolean admit(IsoPlayer player, boolean recovery) throws Exception {
        mainThread();
        IsoPlayer old = IsoPlayer.players[0];
        if (player == null || player.isDead() || player instanceof SCNativeCompanion
                || old == null || (!old.isDead() && !recovery)) throw new IllegalStateException("primary player must be dead before Handover");
        // After interruption the last committed player row can precede the
        // recorded death. Retire that stale loaded representation without a
        // second death/corpse event. Only the durable receipt grants this path.
        if (recovery && !old.isDead()) {
            old.removeFromWorld();
            old.removeFromSquare();
        }
        Class<?> globals = Class.forName("zombie.Lua.LuaManager$GlobalObject");
        Class<?> joypads=Class.forName("zombie.input.JoypadManager");
        Object manager=joypads.getField("instance").get(null);
        Object binding=joypads.getMethod("getFromPlayer",int.class).invoke(manager,0);
        int joypad=binding==null ? -1 : ((Number)binding.getClass().getMethod("getID").invoke(binding)).intValue();
        if (joypad>=0) globals.getMethod("setPlayerJoypad",int.class,int.class,IsoPlayer.class,String.class,boolean.class)
                .invoke(null,0,joypad,player,null,false);
        else globals.getMethod("setPlayerMouse", IsoPlayer.class).invoke(null, player);
        return true;
    }

    /** IsoWorld normally advances this queue only while simulation runs. */
    static boolean ownsLoader(IsoPlayer player,int index) {
        if (index==0) return player!=null && !(player instanceof SCNativeCompanion);
        return index==1 && player instanceof SCNativeCompanion companion
                && SCSplitScreenProbe.isLeader(companion)
                && (SCBridge.isCompanion(companion) || SCSplitScreenProbe.isColdProbe(companion));
    }
    static IsoPlayer pollAdmission() throws Exception {
        mainThread();
        IsoWorld world = IsoWorld.instance;
        if (world == null) return null;
        boolean primaryLoading = false;
        for (Object loader : new java.util.ArrayList<>(world.addCoopPlayers)) {
            Class<?> type = loader.getClass();
            IsoPlayer player = (IsoPlayer) type.getMethod("getPlayer").invoke(loader);
            int index = ((Number) type.getMethod("getPlayerIndex").invoke(loader)).intValue();
            if (index==0 && player instanceof SCNativeCompanion) throw new IllegalStateException("successor must use the stock player runtime");
            if (!ownsLoader(player,index)) continue;
            type.getMethod("update").invoke(loader);
            boolean finished=Boolean.TRUE.equals(type.getMethod("isFinished").invoke(loader));
            if (finished) world.addCoopPlayers.remove(loader);
            else if (index==0) primaryLoading=true;
        }
        if (primaryLoading) return null;
        IsoPlayer secondary=IsoPlayer.players[1];
        if (ownsLoader(secondary,1) && secondary.getCurrentSquare()==null) warmSquare(world,secondary,1);
        IsoPlayer primary = IsoPlayer.players[0];
        if (primary == null || primary.isDead()) return null;
        // AddCoopPlayer can finish before asynchronous chunks arrive. The
        // ordinary world update would warm this map, but succession is paused.
        // Advance streaming only, and publish readiness after its real square
        // exists. This never advances characters, world time or navigation.
        if (primary.getCurrentSquare()==null) {
            warmSquare(world,primary,0);
            if (primary.getCurrentSquare()==null) return null;
        }
        return primary;
    }
    private static void warmSquare(IsoWorld world,IsoPlayer player,int index) throws Exception {
        Object map=world.getCell().getChunkMap(index);
        map.getClass().getMethod("update").invoke(map);
        map.getClass().getMethod("calculateZExtentsForChunkMap").invoke(map);
        IsoPlayer.class.getMethod("setCurrentSquareFromPosition").invoke(player);
    }

    static boolean saved(String token) throws Exception {
        mainThread();
        if (token == null || !token.matches("lf-handover-[A-Za-z0-9-]{16,96}")) return false;
        Class<?> fs = Class.forName("zombie.ZomboidFileSystem");
        Object system = fs.getField("instance").get(null);
        Path database = Path.of((String) fs.getMethod("getCurrentSaveDir").invoke(system), "players.db");
        if (!java.nio.file.Files.isRegularFile(database)) return false;
        byte[] needle = token.getBytes(StandardCharsets.UTF_8);
        // A separate read-only connection sees committed rows, never the queued save.
        try (var conn = DriverManager.getConnection("jdbc:sqlite:" + database.toUri() + "?mode=ro");
             var query = conn.prepareStatement("SELECT data,isDead FROM localPlayers WHERE id=1")) {
            query.setQueryTimeout(1);
            try (var rows = query.executeQuery()) {
                if (!rows.next() || rows.getBoolean(2)) return false;
                byte[] bytes = rows.getBytes(1);
                if (bytes == null) return false;
                outer: for (int i=0; i <= bytes.length - needle.length; i++) {
                    for (int j=0; j < needle.length; j++) if (bytes[i+j] != needle[j]) continue outer;
                    return true;
                }
                return false;
            }
        }
    }

    /** Recover before MainScreen routes a dead primary row to character creation. */
    static boolean resumeBeforeLoad() throws Exception {
        mainThread();
        // Loading an isolated table store is read-only and does not install
        // another world's tables or fire OnInitGlobalModData in this VM.
        GlobalModData shadow=GlobalModData.class.getConstructor().newInstance();
        GlobalModData.class.getMethod("load").invoke(shadow);
        KahluaTable journal=shadow.get("LF_HandoverV1");
        if (journal==null) return false;
        if (!(journal.rawget("schema") instanceof Number schema) || schema.intValue()!=1)
            throw new IllegalStateException("unsupported Handover journal; save preserved");
        Object raw=journal.rawget("pending");
        if (!(raw instanceof KahluaTable receipt) || !"committing".equals(receipt.rawget("phase"))) return false;
        String token=receipt.rawget("token") instanceof String value ? value : null;
        String snapshot=receipt.rawget("snapshot") instanceof String value ? value : null;
        if (token==null || !token.matches("lf-handover-[A-Za-z0-9-]{16,96}")
                || snapshot==null || snapshot.length()>MAX_BYTES*2)
            throw new IllegalStateException("invalid saved successor receipt; save preserved");
        if (saved(token)) return true;
        int split=snapshot.indexOf(':');
        if (split<1 || split>5) throw new IllegalStateException("invalid successor snapshot header");
        int version=Integer.parseInt(snapshot.substring(0,split));
        int current=((Number)IsoWorld.class.getMethod("getWorldVersion").invoke(null)).intValue();
        byte[] bytes=Base64.getDecoder().decode(snapshot.substring(split+1));
        if (version!=current || bytes.length<16 || bytes.length>MAX_BYTES || !containsToken(bytes,token))
            throw new IllegalStateException("successor snapshot does not match its receipt; save preserved");
        float x=coordinate(receipt,"x"),y=coordinate(receipt,"y"),z=coordinate(receipt,"z");
        if (!(receipt.rawget("name") instanceof String name) || name.isBlank() || name.length()>128)
            throw new IllegalStateException("successor name is missing; save preserved");
        Class<?> recordType=Class.forName("zombie.savefile.PlayerDB$PlayerData");
        var constructor=recordType.getDeclaredConstructor();constructor.setAccessible(true);
        Object record=constructor.newInstance();
        field(record,"sqlId",1);field(record,"x",x);field(record,"y",y);field(record,"z",z);
        field(record,"worldVersion",version);field(record,"isDead",false);field(record,"name",name);
        var setBytes=recordType.getDeclaredMethod("setBytes",byte[].class);setBytes.setAccessible(true);setBytes.invoke(record,(Object)bytes);
        // Use the game's own player-store transaction and format. A temporary
        // store avoids changing PlayerDB.instance/allow during menu loading.
        Class<?> storeType=Class.forName("zombie.savefile.PlayerDB$SQLPlayerStore");
        var storeConstructor=storeType.getDeclaredConstructor();storeConstructor.setAccessible(true);
        Object store=storeConstructor.newInstance();
        Class<?> setType=Class.forName("gnu.trove.set.hash.TIntHashSet");
        var init=storeType.getDeclaredMethod("init",setType);init.setAccessible(true);
        var save=storeType.getDeclaredMethod("save",recordType);save.setAccessible(true);
        var close=storeType.getDeclaredMethod("Reset");close.setAccessible(true);
        try { init.invoke(store,setType.getConstructor().newInstance());save.invoke(store,record); }
        finally { close.invoke(store); }
        if (!saved(token)) throw new IllegalStateException("native successor row was not committed; receipt retained");
        return true;
    }

    private static float coordinate(KahluaTable receipt,String key) {
        if (!(receipt.rawget(key) instanceof Number value) || !Float.isFinite(value.floatValue()))
            throw new IllegalStateException("invalid successor position; save preserved");
        return value.floatValue();
    }
    private static void field(Object object,String key,Object value) throws Exception {
        var field=object.getClass().getDeclaredField(key);field.setAccessible(true);field.set(object,value);
    }
    private static boolean containsToken(byte[] bytes,String token) {
        byte[] needle=token.getBytes(StandardCharsets.UTF_8);
        outer: for (int i=0;i<=bytes.length-needle.length;i++) {
            for (int j=0;j<needle.length;j++) if(bytes[i+j]!=needle[j]) continue outer;
            return true;
        }
        return false;
    }

    static boolean requestSave() {
        mainThread();
        PlayerDB db = PlayerDB.getInstance();
        if (db == null) throw new IllegalStateException("native player database unavailable");
        db.saveLocalPlayersForce();
        return true;
    }
}
