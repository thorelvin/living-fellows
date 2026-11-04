// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.ref.WeakReference;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HashMap;

import se.krka.kahlua.vm.KahluaTable;
import zombie.MainThread;
import zombie.vehicles.BaseVehicle;

/** Real SQLite commit controls; no game, writer thread or vehicle is started. */
public final class SCVehicleSaveBarrierTest {
    private static int checks;
    private static Object unsafe;
    private static Method allocate;

    private static void require(boolean value, String reason) {
        checks++;
        if (!value) throw new AssertionError(reason);
    }
    private static BaseVehicle car() throws Exception {
        return (BaseVehicle) allocate.invoke(unsafe, BaseVehicle.class);
    }
    private static KahluaTable table() throws Exception {
        return (KahluaTable) Class.forName("se.krka.kahlua.j2se.KahluaTableImpl")
                .getConstructor(java.util.Map.class).newInstance(new HashMap<>());
    }
    private static void refuses(Runnable action, String reason) {
        boolean rejected = false;
        try { action.run(); } catch (IllegalStateException expected) { rejected = true; }
        require(rejected, reason);
    }

    private static final class Fake implements SCVehicleSaveBarrier.Environment {
        Object world = new Object(), cell = new Object();
        final Path directory;
        BaseVehicle car;
        int sqlId = 17, captures;
        float x = 100.5f, y = 65.5f, z, speed;
        boolean loaded = true, primary, running, starting, empty = true, captureFails, contextFails;
        String tag = "";
        long now = 1;
        SCVehicleSaveBarrier.Snapshot snapshot;
        Fake(Path directory) throws Exception { this.directory = directory; car = car(); }
        public boolean capable() { return true; }
        public SCVehicleSaveBarrier.Context context() {
            if (contextFails) throw new IllegalStateException("native saving unavailable");
            return new SCVehicleSaveBarrier.Context(world, cell, directory, 123);
        }
        public SCVehicleSaveBarrier.State state(BaseVehicle value) {
            if (value != car) throw new IllegalStateException("wrong native object");
            return new SCVehicleSaveBarrier.State(sqlId, x, y, z, speed, running, starting, empty, tag);
        }
        public BaseVehicle loaded(int id) { return loaded && id == sqlId ? car : null; }
        public boolean loadedObject(BaseVehicle value) { return loaded && value == car; }
        public boolean primaryOwned(BaseVehicle value) { return primary && loaded && value == car; }
        public long now() { return now; }
        public SCVehicleSaveBarrier.Snapshot enqueue(BaseVehicle value, String generatedTag) throws Exception {
            captures++;
            if (captureFails) throw new java.io.IOException("injected native snapshot failure");
            tag = generatedTag;
            byte[] bytes = ("native-car|" + tag + "|same-real-items").getBytes(StandardCharsets.UTF_8);
            snapshot = new SCVehicleSaveBarrier.Snapshot(sqlId, 12, 8, x, y, 123, bytes);
            return snapshot;
        }
        void tick() { now += 300_000_000L; }
    }

    private static void write(Connection writer, SCVehicleSaveBarrier.Snapshot snapshot, byte[] bytes) throws SQLException {
        try (PreparedStatement update = writer.prepareStatement(
                "INSERT OR REPLACE INTO vehicles(id,wx,wy,x,y,worldversion,data) VALUES(?,?,?,?,?,?,?)")) {
            update.setInt(1, snapshot.id()); update.setInt(2, snapshot.wx()); update.setInt(3, snapshot.wy());
            update.setFloat(4, snapshot.x()); update.setFloat(5, snapshot.y());
            update.setInt(6, snapshot.worldVersion()); update.setBytes(7, bytes);
            update.executeUpdate();
        }
    }
    private static KahluaTable document(KahluaTable receipt, int sqlId) throws Exception {
        KahluaTable integration = table(); integration.rawset("kind", "home");
        integration.rawset("carId", (double) sqlId); integration.rawset("carSaveReceipt", receipt);
        KahluaTable debrief = table(); debrief.rawset("integration", integration);
        KahluaTable expedition = table(); expedition.rawset("debrief", debrief);
        KahluaTable document = table(); document.rawset("expedition", expedition);
        return document;
    }

    private record OldReferences(long ticket, WeakReference<Object> world,
            WeakReference<Object> cell, WeakReference<Object> car,
            WeakReference<Object> context, WeakReference<Object> bytes) {
        boolean collected() {
            return world.get()==null && cell.get()==null && car.get()==null
                    && context.get()==null && bytes.get()==null;
        }
    }

    /** Return only weak references; none of the old world/car locals escape this frame. */
    private static OldReferences unfinishedWorld(Fake fake) throws Exception {
        fake.world=new Object(); fake.cell=new Object(); fake.car=car();
        fake.captureFails=false; fake.loaded=true; fake.primary=false;
        fake.running=false; fake.starting=false; fake.empty=true; fake.speed=0;
        long id=SCSplitScreenProbe.requestHomeVehicleSave(fake.car);
        require(id>0,"unfinished world-exit control could not capture its ticket");
        Field field=SCVehicleSaveBarrier.class.getDeclaredField("tickets"); field.setAccessible(true);
        Object value=((java.util.Map<?,?>)field.get(null)).get(id);
        SCVehicleSaveBarrier.Ticket ticket=(SCVehicleSaveBarrier.Ticket)value;
        OldReferences references=new OldReferences(id,new WeakReference<>(ticket.context.world()),
                new WeakReference<>(ticket.context.cell()),new WeakReference<>(ticket.car),
                new WeakReference<>(ticket.context),new WeakReference<>(ticket.snapshot.bytes()));
        // Simulate the game replacing its current world references. Do not make
        // another request: that would prune the map and hide the exit leak.
        fake.world=new Object(); fake.cell=new Object(); fake.car=car(); fake.snapshot=null;
        return references;
    }

    public static void main(String[] args) throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe"); singleton.setAccessible(true);
        unsafe = singleton.get(null); allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        Object random = Class.forName("zombie.core.random.RandStandard").getField("INSTANCE").get(null);
        random.getClass().getMethod("init").invoke(random);
        Thread previousThread = MainThread.mainThread;
        MainThread.mainThread = Thread.currentThread();
        require(SCSplitScreenProbe.homeVehicleSaveCapability(),
                "real-JAR reflected native queue/SQLite contract unavailable: " + SCSplitScreenProbe.homeVehicleSaveFailure(0));
        Class<?> nativeVehiclesType = Class.forName("zombie.iso.IsoCell").getMethod("getVehicles").getReturnType();
        require(nativeVehiclesType == java.util.Set.class
                        && java.util.Collection.class.isAssignableFrom(nativeVehiclesType),
                "installed native getVehicles descriptor changed: " + nativeVehiclesType.getTypeName());
        java.util.Set<Object> nativeSet = new java.util.LinkedHashSet<>();
        Object exactVehicle = new Object(); nativeSet.add(exactVehicle);
        require(SCVehicleSaveBarrier.vehicleCollection(nativeSet) == nativeSet
                        && SCVehicleSaveBarrier.containsIdentity(nativeSet, exactVehicle),
                "native Set vehicle collection was rejected or copied/mutated");
        Object equalButDifferent = new Object() {
            @Override public boolean equals(Object value) { return true; }
            @Override public int hashCode() { return 0; }
        };
        require(!SCVehicleSaveBarrier.containsIdentity(nativeSet, equalButDifferent),
                "native loaded-object authority used equals instead of exact identity");
        refuses(() -> SCVehicleSaveBarrier.vehicleCollection(new java.util.ArrayList<>(
                java.util.Collections.nCopies(513, new Object()))), "unbounded native vehicle collection was admitted");
        refuses(() -> SCVehicleSaveBarrier.vehicleCollection(new Object()), "unsupported native vehicle collection was admitted");
        Path directory = Files.createTempDirectory("lf-vehicle-save-proof-");
        Path database = directory.resolve("vehicles.db");
        Fake fake = new Fake(directory);
        SCVehicleSaveBarrier.Environment original = SCVehicleSaveBarrier.replaceEnvironmentForTests(fake);
        try {
            require(!SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"secondary-only vehicle granted the near-recall exception");
            fake.primary=true;
            require(SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"actual primary-retained stopped empty car was refused");
            fake.contextFails=true;
            require(SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"read-only primary retention depended on failed database saving");
            fake.contextFails=false;
            require(fake.captures==0 && fake.tag.isEmpty(),"read-only primary retention queued a save or changed car metadata");
            require(!SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,18)
                            && !SCSplitScreenProbe.primaryRetainsHomeVehicle(null,17)
                            && !SCSplitScreenProbe.primaryRetainsHomeVehicle(car(),17),
                    "wrong SQL/native vehicle identity granted primary retention");
            for (String defect:new String[]{"moving","engine","starting","passenger","unloaded","pose"}) {
                if (defect.equals("moving")) fake.speed=.2f;
                if (defect.equals("engine")) fake.running=true;
                if (defect.equals("starting")) fake.starting=true;
                if (defect.equals("passenger")) fake.empty=false;
                if (defect.equals("unloaded")) fake.loaded=false;
                if (defect.equals("pose")) fake.x=Float.NaN;
                require(!SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"unsafe near-recall car was retained: "+defect);
                fake.speed=0;fake.running=false;fake.starting=false;fake.empty=true;fake.loaded=true;fake.x=100.5f;
            }
            Field activeLease=SCSplitScreenProbe.class.getDeclaredField("remoteArrival");activeLease.setAccessible(true);
            Object previousLease=activeLease.get(null);
            try {
                activeLease.set(null,allocate.invoke(unsafe,SCRemoteArrival.Lease.class));
                require(!SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"active remote-arrival lease granted a near-recall bypass");
            } finally { activeLease.set(null,previousLease); }
            fake.primary=false;
            require(SCVehicleSaveBarrier.readCommitted(database, 17) == null && !Files.exists(database),
                    "read-only proof created an absent game database");
            Class.forName("org.sqlite.JDBC");
            try (Connection writer = DriverManager.getConnection("jdbc:sqlite:" + database)) {
                try (Statement schema = writer.createStatement()) {
                    schema.executeUpdate("CREATE TABLE vehicles(id INTEGER PRIMARY KEY,wx INTEGER,wy INTEGER,x REAL,y REAL,worldversion INTEGER,data BLOB)");
                }
                writer.setAutoCommit(false);
                long ticket = SCSplitScreenProbe.requestHomeVehicleSave(fake.car);
                require(ticket > 0 && fake.captures == 1 && fake.tag.startsWith("lf-home-"), "request did not capture one native-tagged stop snapshot");
                require("pending".equals(SCSplitScreenProbe.pollHomeVehicleSave(ticket)), "queue submission was accepted as a durable save");
                write(writer, fake.snapshot, fake.snapshot.bytes());
                fake.tick();
                require("pending".equals(SCSplitScreenProbe.pollHomeVehicleSave(ticket)), "uncommitted SQL vehicle row passed the barrier");
                writer.commit(); fake.tick();
                require("ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(ticket)), "the exact committed queued blob was not admitted");
                KahluaTable receipt = SCSplitScreenProbe.homeVehicleSaveReceipt(ticket);
                require(((Number) receipt.rawget("version")).intValue() == 1
                        && ((Number) receipt.rawget("sqlId")).intValue() == 17
                        && ((String) receipt.rawget("sha256")).length() == 64
                        && fake.tag.equals(receipt.rawget("tagUUID")), "receipt omitted its stable bounded native proof fields");

                SCVehicleSaveBarrier.Row row = SCVehicleSaveBarrier.readCommitted(database, 17);
                require(SCVehicleSaveBarrier.rowMatches(fake.snapshot, row), "committed native SQL columns/bytes mismatch");
                require(!SCVehicleSaveBarrier.rowMatches(fake.snapshot, new SCVehicleSaveBarrier.Row(18, row.wx(), row.wy(), row.x(), row.y(), row.worldVersion(), row.bytes())), "wrong SQL id passed");
                require(!SCVehicleSaveBarrier.rowMatches(fake.snapshot, new SCVehicleSaveBarrier.Row(17, row.wx()+1, row.wy(), row.x(), row.y(), row.worldVersion(), row.bytes())), "wrong native chunk passed");
                require(!SCVehicleSaveBarrier.rowMatches(fake.snapshot, new SCVehicleSaveBarrier.Row(17, row.wx(), row.wy(), row.x()+1, row.y(), row.worldVersion(), row.bytes())), "wrong stopped pose passed");
                require(!SCVehicleSaveBarrier.rowMatches(fake.snapshot, new SCVehicleSaveBarrier.Row(17, row.wx(), row.wy(), row.x(), row.y(), row.worldVersion()+1, row.bytes())), "wrong world version passed");
                require(!SCVehicleSaveBarrier.rowMatches(fake.snapshot, new SCVehicleSaveBarrier.Row(17, row.wx(), row.wy(), row.x(), row.y(), row.worldVersion(), new byte[]{1})), "different SQL blob passed");

                SCVehicleSaveBarrier.Ticket attached = SCVehicleSaveBarrier.attach(ticket, 700);
                SCVehicleSaveBarrier.verifyDocument(attached, 700, document(receipt, 17));
                fake.primary=true;
                require(!SCSplitScreenProbe.primaryRetainsHomeVehicle(fake.car,17),"attached vehicle receipt granted a near-recall bypass");
                fake.primary=false;
                require(!SCSplitScreenProbe.cancelHomeVehicleSave(ticket), "attached vehicle proof was cancelled before its crew lease finished");
                refuses(() -> SCVehicleSaveBarrier.attach(ticket, 701), "one ticket was attached to two arrival leases");
                KahluaTable wrongId = document(receipt, 18);
                refuses(() -> SCVehicleSaveBarrier.verifyDocument(attached, 700, wrongId), "finalized integration substituted another car SQL id");
                refuses(() -> SCVehicleSaveBarrier.verifyDocument(null, 700, wrongId), "driving arrival omitted its required native vehicle proof");
                refuses(SCSplitScreenProbe::finalizeCorpseChunksAfterWorldExit,
                        "world-exit cache cleanup discarded an attached active vehicle proof");
                require("ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(ticket)),
                        "failed world-exit cleanup dropped the active arrival ticket");
                SCVehicleSaveBarrier.verifyDocument(null, 700, table());
                require(true, "walking arrival unexpectedly depended on vehicle capability");
                SCVehicleSaveBarrier.detach(attached, 700);
                require(SCSplitScreenProbe.cancelHomeVehicleSave(ticket), "completed crew lease could not retire its ticket cache");

                byte[] naturallyResaved = ("updated-native-age|" + fake.tag + "|same-real-items").getBytes(StandardCharsets.UTF_8);
                write(writer, fake.snapshot, naturallyResaved); writer.commit();
                fake.loaded = false;
                int captures = fake.captures;
                long restored = SCSplitScreenProbe.restoreHomeVehicleSave(receipt);
                require(restored > 0 && "ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(restored)) && fake.captures == captures,
                        "unloaded committed UUID receipt required identical passive bytes or created a virtual car");
                Object oldWorld = fake.world; fake.world = new Object(); fake.tick();
                require("failed".equals(SCSplitScreenProbe.pollHomeVehicleSave(restored)), "old in-process ticket crossed world ownership");
                long cold = SCSplitScreenProbe.restoreHomeVehicleSave(receipt);
                require(cold > 0 && "ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(cold)), "cold-world receipt did not rebind to the current committed native database");
                fake.world = oldWorld;

                Object savedTag = receipt.rawget("tagUUID");
                receipt.rawset("tagUUID", "lf-home-00000000-0000-4000-8000-000000000000");
                require(SCSplitScreenProbe.restoreHomeVehicleSave(receipt) == 0, "absent native UUID resurrected a receipt car");
                receipt.rawset("tagUUID", savedTag);
                receipt.rawset("worldVersion", 124.0);
                require(SCSplitScreenProbe.restoreHomeVehicleSave(receipt) == 0, "wrong receipt world version passed");
                receipt.rawset("worldVersion", 123.0);

                fake.loaded = true; fake.car = car();
                long fresh = SCSplitScreenProbe.restoreHomeVehicleSave(receipt);
                require(fresh > 0 && fake.captures == captures+1 && "pending".equals(SCSplitScreenProbe.pollHomeVehicleSave(fresh)),
                        "loaded secondary car reused old receipt without a new native stopped snapshot");
                write(writer, fake.snapshot, fake.snapshot.bytes()); writer.commit(); fake.tick();
                require("ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(fresh)), "fresh loaded secondary snapshot did not commit");
                KahluaTable latest = SCSplitScreenProbe.homeVehicleSaveReceipt(fresh);
                fake.primary = true; fake.running = true; fake.empty = false; fake.speed = 12;
                long retained = SCSplitScreenProbe.restoreHomeVehicleSave(latest);
                require(retained > 0 && "ready".equals(SCSplitScreenProbe.pollHomeVehicleSave(retained)),
                        "primary-owned retained car was frozen or refused while its real player used it");
                fake.primary = false; fake.tick();
                require("failed".equals(SCSplitScreenProbe.pollHomeVehicleSave(retained)), "running occupied car in retiring view passed");
                fake.running = false; fake.empty = true; fake.speed = 0;

                for (String defect : new String[]{"pose", "engine", "starting", "passenger", "tag", "sql", "unloaded"}) {
                    long pending = SCSplitScreenProbe.requestHomeVehicleSave(fake.car);
                    require(pending > 0, "fresh defect control could not prepare: " + defect);
                    write(writer, fake.snapshot, fake.snapshot.bytes()); writer.commit();
                    if (defect.equals("pose")) fake.x += .2f;
                    if (defect.equals("engine")) fake.running = true;
                    if (defect.equals("starting")) fake.starting = true;
                    if (defect.equals("passenger")) fake.empty = false;
                    if (defect.equals("tag")) fake.tag = "changed";
                    if (defect.equals("sql")) fake.sqlId++;
                    if (defect.equals("unloaded")) fake.loaded = false;
                    fake.tick();
                    require("failed".equals(SCSplitScreenProbe.pollHomeVehicleSave(pending)), "late car state drift passed: " + defect);
                    fake.x = 100.5f; fake.running = false; fake.starting = false; fake.empty = true; fake.sqlId = 17; fake.loaded = true;
                }
                long failedWrite = SCSplitScreenProbe.requestHomeVehicleSave(fake.car);
                try (Statement broken = writer.createStatement()) {
                    boolean writeFailed = false;
                    try { broken.executeUpdate("INSERT INTO nonexistent_native_vehicle_table VALUES(1)"); }
                    catch (SQLException expected) { writeFailed = true; writer.rollback(); }
                    require(writeFailed, "SQL write failure negative control did not fail");
                }
                fake.now += 31_000_000_000L;
                require("failed".equals(SCSplitScreenProbe.pollHomeVehicleSave(failedWrite)), "failed native write was accepted without exact committed bytes");
                fake.captureFails = true;
                require(SCSplitScreenProbe.requestHomeVehicleSave(fake.car) == 0
                        && SCSplitScreenProbe.homeVehicleSaveFailure(0).contains("injected native snapshot failure"), "native capture failure was reported as a save ticket");
                writer.rollback();
            }
            OldReferences old=unfinishedWorld(fake);
            require(!old.collected(),"unfinished ticket did not retain the old context control");
            require(SCSplitScreenProbe.finalizeCorpseChunksAfterWorldExit(),
                    "verified successful world-exit hook did not finish cache cleanup");
            require("failed".equals(SCSplitScreenProbe.pollHomeVehicleSave(old.ticket())),
                    "unfinished vehicle-save ticket survived native world exit");
            for (int attempt=0;attempt<30 && !old.collected();attempt++) {
                System.gc(); Thread.sleep(10L);
            }
            require(old.collected(),"native world-exit ticket cache retained old world/cell/car/snapshot references");
            System.out.println("SCVehicleSaveBarrierTest PASS checks=" + checks);
        } finally {
            SCVehicleSaveBarrier.replaceEnvironmentForTests(original);
            MainThread.mainThread = previousThread;
            Files.deleteIfExists(database.resolveSibling("vehicles.db-journal"));
            Files.deleteIfExists(database); Files.deleteIfExists(directory);
        }
    }
}
