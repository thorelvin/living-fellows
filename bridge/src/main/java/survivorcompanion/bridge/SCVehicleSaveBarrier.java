// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.ConcurrentLinkedQueue;

import se.krka.kahlua.vm.KahluaTable;
import zombie.MainThread;
import zombie.core.Core;
import zombie.iso.IsoWorld;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.vehicles.BaseVehicle;

/** Native vehicle writer plus an independent, read-only committed-row barrier. */
final class SCVehicleSaveBarrier {
    static final String TAG_KEY = "SC_HomeVehicleSaveTag";
    static final int MAX_BYTES = 2 * 1024 * 1024;
    private static final long TIMEOUT = 30_000_000_000L;
    private static final long POLL_INTERVAL = 250_000_000L;
    private static final LinkedHashMap<Long, Ticket> tickets = new LinkedHashMap<>();
    private static Environment environment = new NativeEnvironment();
    private static long sequence;
    private static String lastFailure = "";

    record Context(Object world, Object cell, Path saveDir, int worldVersion) {
        Context {
            if (world == null || cell == null || saveDir == null || worldVersion < 1)
                throw new IllegalStateException("vehicle save world is unavailable");
            saveDir = saveDir.toAbsolutePath().normalize();
        }
        boolean same(Context other) {
            return other != null && world == other.world && cell == other.cell
                    && saveDir.equals(other.saveDir) && worldVersion == other.worldVersion;
        }
    }
    record State(int id, float x, float y, float z, float speed,
            boolean running, boolean starting, boolean empty, String tag) {}
    record Snapshot(int id, int wx, int wy, float x, float y, int worldVersion, byte[] bytes) {
        Snapshot { bytes = bytes.clone(); }
    }
    record Row(int id, int wx, int wy, float x, float y, int worldVersion, byte[] bytes) {}

    /** Package-only seam: tests still use the production read-only SQLite reader. */
    interface Environment {
        boolean capable();
        Context context();
        State state(BaseVehicle car);
        default State physicalState(BaseVehicle car) { return state(car); }
        BaseVehicle loaded(int sqlId);
        default boolean loadedObject(BaseVehicle car) { return false; }
        boolean primaryOwned(BaseVehicle car);
        Snapshot enqueue(BaseVehicle car, String tag) throws Exception;
        default long now() { return System.nanoTime(); }
    }

    static final class Ticket {
        final long id;
        final Context context;
        final int sqlId;
        final String tag;
        final float x, y, z;
        final int worldVersion, byteLength;
        final String sha256;
        final BaseVehicle car;
        final Snapshot snapshot;
        final long created;
        boolean committed;
        long nextPoll, attachedLease;
        String failure = "";

        Ticket(long id, Context context, BaseVehicle car, State state,
                String tag, Snapshot snapshot, KahluaTable receipt) {
            this.id = id; this.context = context; this.car = car; this.tag = tag;
            this.sqlId = state.id; this.x = state.x; this.y = state.y; this.z = state.z;
            this.snapshot = snapshot;
            worldVersion = snapshot == null ? integer(receipt, "worldVersion", 1, 10000000) : snapshot.worldVersion;
            byteLength = snapshot == null ? integer(receipt, "byteLength", 1, MAX_BYTES) : snapshot.bytes.length;
            sha256 = snapshot == null ? string(receipt, "sha256", 64) : digest(snapshot.bytes);
            created = environment.now();
        }
    }

    private SCVehicleSaveBarrier() {}

    static boolean capable() {
        try { return environment.capable(); }
        catch (RuntimeException | LinkageError failure) { lastFailure = clean(failure); return false; }
    }

    /** Near-recall assertion only; never grants remote unload or cancels a ticket. */
    static boolean primaryRetains(BaseVehicle car, int expectedSqlId) {
        try {
            requireThread();
            if (car == null || expectedSqlId < 1) return false;
            for (Ticket ticket : tickets.values()) {
                if (ticket.attachedLease != 0 && (ticket.sqlId == expectedSqlId || ticket.car == car)) return false;
            }
            State state=environment.physicalState(car);
            return state.id==expectedSqlId && environment.loaded(expectedSqlId)==car && stoppedState(state)
                    && environment.primaryOwned(car);
        } catch (RuntimeException | LinkageError failure) { return false; }
    }

    static long request(BaseVehicle car) {
        try {
            requireThread();
            if (!capable()) throw new IllegalStateException("native vehicle save capability unavailable");
            Context context = environment.context();
            prune(context);
            State state = stopped(car, context, null);
            String tag = "lf-home-" + UUID.randomUUID();
            Snapshot snapshot = environment.enqueue(car, tag);
            if (snapshot.id != state.id || snapshot.worldVersion != context.worldVersion
                    || Float.compare(snapshot.x, state.x) != 0 || Float.compare(snapshot.y, state.y) != 0
                    || snapshot.bytes.length < 1 || snapshot.bytes.length > MAX_BYTES
                    || !containsTag(snapshot.bytes, tag)) {
                throw new IllegalStateException("native queued vehicle snapshot does not match stopped car");
            }
            Ticket ticket = new Ticket(++sequence, context, car, state, tag, snapshot, null);
            tickets.put(ticket.id, ticket);
            lastFailure = "";
            return ticket.id;
        } catch (Exception | LinkageError failure) { lastFailure = clean(failure); return 0; }
    }

    static long restore(KahluaTable receipt) {
        try {
            requireThread();
            if (!capable()) throw new IllegalStateException("native vehicle save capability unavailable");
            Context context = environment.context();
            prune(context);
            int sqlId = integer(receipt, "sqlId", 1, Integer.MAX_VALUE);
            if (integer(receipt, "version", 1, 1) != 1) throw new IllegalStateException("vehicle receipt version invalid");
            String tag = string(receipt, "tagUUID", 44);
            validateTag(tag);
            String hash = string(receipt, "sha256", 64);
            if (!hash.matches("[0-9a-fA-F]{64}")) throw new IllegalStateException("vehicle receipt hash invalid");
            int version = integer(receipt, "worldVersion", 1, 10000000);
            integer(receipt, "byteLength", 1, MAX_BYTES);
            if (version != context.worldVersion) throw new IllegalStateException("vehicle receipt world version changed");
            float x = coordinate(receipt, "x", 0, 30000), y = coordinate(receipt, "y", 0, 30000);
            float z = coordinate(receipt, "z", -32, 31);
            Row row = readCommitted(context.saveDir.resolve("vehicles.db"), sqlId);
            if (row == null || !containsTag(row.bytes, tag) || row.worldVersion != version)
                throw new IllegalStateException("committed vehicle receipt tag is absent");
            BaseVehicle loaded = environment.loaded(sqlId);
            if (loaded != null) {
                State current = environment.state(loaded);
                if (current.id != sqlId || !tag.equals(current.tag)) throw new IllegalStateException("loaded vehicle receipt identity changed");
                // A car in the retiring view needs a new current native stop
                // snapshot. Never restore a virtual car from receipt bytes.
                if (!environment.primaryOwned(loaded)) return request(loaded);
            }
            State state = new State(sqlId, x, y, z, 0, false, false, true, tag);
            Ticket ticket = new Ticket(++sequence, context, loaded, state, tag, null, receipt);
            ticket.committed = true;
            tickets.put(ticket.id, ticket);
            lastFailure = "";
            return ticket.id;
        } catch (Exception | LinkageError failure) { lastFailure = clean(failure); return 0; }
    }

    static String poll(long id) {
        Ticket ticket = tickets.get(id);
        if (ticket == null) return "failed";
        if (!ticket.failure.isEmpty()) return "failed";
        try {
            requireThread();
            if (!ticket.context.same(environment.context())) throw new IllegalStateException("vehicle save world changed");
            BaseVehicle loaded = environment.loaded(ticket.sqlId);
            boolean primary = loaded != null && environment.primaryOwned(loaded);
            if (loaded != null) {
                if (ticket.car != null && loaded != ticket.car) throw new IllegalStateException("native vehicle object changed");
                State state = environment.state(loaded);
                if (state.id != ticket.sqlId || !ticket.tag.equals(state.tag)) throw new IllegalStateException("vehicle save tag changed");
                if (!primary || !ticket.committed) stopped(loaded, ticket.context, ticket);
                if (ticket.snapshot == null && !primary) throw new IllegalStateException("loaded secondary vehicle needs a fresh stopped snapshot");
            } else if (!ticket.committed) {
                throw new IllegalStateException("vehicle unloaded before its stop snapshot committed");
            } else if (ticket.car != null && environment.loadedObject(ticket.car)) {
                throw new IllegalStateException("native vehicle SQL identity changed");
            }
            long now = environment.now();
            if (now < ticket.nextPoll) return ticket.committed ? "ready" : "pending";
            ticket.nextPoll = now + POLL_INTERVAL;
            Row row = readCommitted(ticket.context.saveDir.resolve("vehicles.db"), ticket.sqlId);
            if (row != null && row.worldVersion == ticket.worldVersion && containsTag(row.bytes, ticket.tag)) {
                boolean exact = ticket.snapshot != null && rowMatches(ticket.snapshot, row);
                if (!ticket.committed && exact) ticket.committed = true;
                if (ticket.committed) return "ready";
            }
            if (ticket.committed) throw new IllegalStateException("committed vehicle row or native tag changed");
            if (now - ticket.created >= TIMEOUT) throw new IllegalStateException("native vehicle write did not commit the queued snapshot");
            return "pending";
        } catch (SQLException failure) {
            if (failure.getErrorCode() == 5 || failure.getErrorCode() == 6) {
                if (environment.now() - ticket.created < TIMEOUT) return "pending";
            }
            ticket.failure = clean(failure); return "failed";
        } catch (Exception | LinkageError failure) { ticket.failure = clean(failure); return "failed"; }
    }

    static String failure(long id) {
        Ticket ticket = tickets.get(id);
        return ticket == null ? lastFailure.isEmpty() ? "vehicle save ticket unavailable" : lastFailure : ticket.failure;
    }

    static KahluaTable receipt(long id) {
        Ticket ticket = requireReady(id);
        try {
            KahluaTable result = NativeAccess.TABLE.newInstance(new HashMap<>());
            result.rawset("version", 1.0); result.rawset("sqlId", (double) ticket.sqlId);
            result.rawset("tagUUID", ticket.tag);
            result.rawset("x", (double) ticket.x); result.rawset("y", (double) ticket.y); result.rawset("z", (double) ticket.z);
            result.rawset("worldVersion", (double) ticket.worldVersion);
            result.rawset("byteLength", (double) ticket.byteLength); result.rawset("sha256", ticket.sha256);
            return result;
        } catch (ReflectiveOperationException failure) { throw new IllegalStateException("vehicle receipt allocation unavailable", failure); }
    }

    static Ticket attach(long id, long lease) {
        Ticket ticket = requireReady(id);
        if (lease <= 0 || ticket.attachedLease != 0 && ticket.attachedLease != lease)
            throw new IllegalStateException("vehicle save ticket already belongs to another arrival lease");
        ticket.attachedLease = lease;
        return ticket;
    }

    static void detach(Ticket ticket, long lease) {
        if (ticket != null && ticket.attachedLease == lease) ticket.attachedLease = 0;
    }

    static boolean cancel(long id) {
        requireThread();
        Ticket ticket = tickets.get(id);
        if (ticket == null) return true;
        if (ticket.attachedLease != 0) return false;
        tickets.remove(id);
        return true;
    }

    /** Cache only: queued native writes and persistent car UUIDs remain owned by the game. */
    static void clearAfterWorldExit() {
        requireThread();
        for (Ticket ticket : tickets.values()) if (ticket.attachedLease != 0)
            throw new IllegalStateException("vehicle save still belongs to an active arrival lease");
        tickets.clear();
        lastFailure = "";
    }

    static void verifyDocument(Ticket ticket, long lease, KahluaTable document) {
        Object expedition = document.rawget("expedition");
        Object debrief = expedition instanceof KahluaTable table ? table.rawget("debrief") : null;
        Object value = debrief instanceof KahluaTable table ? table.rawget("integration") : null;
        Object carId = value instanceof KahluaTable integration ? integration.rawget("carId") : null;
        if (carId == null && ticket == null) return; // Existing walking lease.
        if (!(value instanceof KahluaTable integration) || !(carId instanceof Number number)
                || ticket == null || number.doubleValue() != ticket.sqlId || ticket.attachedLease != lease
                || !(integration.rawget("carSaveReceipt") instanceof KahluaTable saved)
                || integer(saved, "version", 1, 1) != 1 || integer(saved, "sqlId", 1, Integer.MAX_VALUE) != ticket.sqlId
                || !ticket.tag.equals(saved.rawget("tagUUID")) || !ticket.sha256.equals(saved.rawget("sha256"))
                || integer(saved, "byteLength", 1, MAX_BYTES) != ticket.byteLength
                || integer(saved, "worldVersion", 1, 10000000) != ticket.worldVersion
                || coordinate(saved,"x",0,30000) != ticket.x || coordinate(saved,"y",0,30000) != ticket.y
                || coordinate(saved,"z",-32,31) != ticket.z) {
            throw new IllegalStateException("remote arrival lacks its exact committed vehicle receipt");
        }
        requireReady(ticket.id);
    }

    private static Ticket requireReady(long id) {
        if (!"ready".equals(poll(id))) throw new IllegalStateException("vehicle save is not committed: " + failure(id));
        return tickets.get(id);
    }

    private static State stopped(BaseVehicle car, Context context, Ticket expected) {
        if (car == null) throw new IllegalStateException("native vehicle is unavailable");
        State state = environment.state(car);
        if (state.id < 1 || environment.loaded(state.id) != car || !stoppedState(state))
            throw new IllegalStateException("vehicle must be stopped, empty and engine-off");
        if (expected != null && (state.id != expected.sqlId || !expected.tag.equals(state.tag)
                || Math.abs(state.x - expected.x) > .1f || Math.abs(state.y - expected.y) > .1f
                || Math.abs(state.z - expected.z) > .1f)) throw new IllegalStateException("vehicle changed after its stop snapshot");
        return state;
    }

    private static boolean stoppedState(State state) {
        return Float.isFinite(state.x) && Float.isFinite(state.y) && Float.isFinite(state.z)
                && state.x>=0 && state.y>=0 && state.x<=30000 && state.y<=30000 && Math.abs(state.z)<=.1f
                && Float.isFinite(state.speed) && Math.abs(state.speed)<=.1f
                && !state.running && !state.starting && state.empty;
    }

    static boolean rowMatches(Snapshot snapshot, Row row) {
        return row != null && snapshot.id == row.id && snapshot.wx == row.wx && snapshot.wy == row.wy
                && Float.compare(snapshot.x, row.x) == 0 && Float.compare(snapshot.y, row.y) == 0
                && snapshot.worldVersion == row.worldVersion && Arrays.equals(snapshot.bytes, row.bytes);
    }

    static Collection<?> vehicleCollection(Object values) {
        if (!(values instanceof Collection<?> collection) || collection.size() > 512)
            throw new IllegalStateException("native loaded vehicle collection unavailable");
        return collection;
    }

    static boolean containsIdentity(Collection<?> values, Object target) {
        for (Object value : values) if (value == target) return true;
        return false;
    }

    /** SELECT only; SQLite's separate read-only connection cannot see uncommitted native writes. */
    static Row readCommitted(Path database, int sqlId) throws SQLException {
        if (!Files.isRegularFile(database)) return null;
        try { Class.forName("org.sqlite.JDBC"); }
        catch (ClassNotFoundException failure) { throw new SQLException("SQLite read-only driver unavailable", failure); }
        Properties properties = new Properties();
        properties.setProperty("open_mode", "1");
        properties.setProperty("busy_timeout", "25");
        try (Connection connection = DriverManager.getConnection("jdbc:sqlite:" + database.toAbsolutePath().normalize(), properties)) {
            if (!connection.isReadOnly()) throw new SQLException("vehicle proof connection is not read-only");
            try (PreparedStatement query = connection.prepareStatement(
                    "SELECT id,wx,wy,x,y,worldversion,data FROM vehicles WHERE id=? AND length(data) BETWEEN 1 AND ?")) {
                query.setInt(1, sqlId); query.setInt(2, MAX_BYTES);
                try (ResultSet result = query.executeQuery()) {
                    if (!result.next()) return null;
                    return new Row(result.getInt(1), result.getInt(2), result.getInt(3), result.getFloat(4),
                            result.getFloat(5), result.getInt(6), result.getBytes(7));
                }
            }
        }
    }

    static boolean containsTag(byte[] bytes, String tag) {
        for (var charset : List.of(StandardCharsets.UTF_8, StandardCharsets.UTF_16LE, StandardCharsets.UTF_16BE)) {
            byte[] needle = tag.getBytes(charset);
            outer: for (int i = 0; i <= bytes.length - needle.length; i++) {
                for (int j = 0; j < needle.length; j++) if (bytes[i+j] != needle[j]) continue outer;
                return true;
            }
        }
        return false;
    }

    private static String digest(byte[] bytes) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder result = new StringBuilder(64);
            for (byte value : hash) result.append(String.format("%02x", value & 255));
            return result.toString();
        } catch (java.security.NoSuchAlgorithmException failure) { throw new IllegalStateException(failure); }
    }
    private static String string(KahluaTable table, String key, int maximum) {
        Object value = table == null ? null : table.rawget(key);
        if (!(value instanceof String text) || text.isEmpty() || text.length() > maximum) throw new IllegalStateException("vehicle receipt " + key + " invalid");
        return text;
    }
    private static int integer(KahluaTable table, String key, int min, int max) {
        Object value = table == null ? null : table.rawget(key);
        if (!(value instanceof Number number) || !Double.isFinite(number.doubleValue()) || number.doubleValue() != Math.rint(number.doubleValue())
                || number.doubleValue() < min || number.doubleValue() > max) throw new IllegalStateException("vehicle receipt " + key + " invalid");
        return number.intValue();
    }
    private static float coordinate(KahluaTable table, String key, int min, int max) {
        Object value = table == null ? null : table.rawget(key);
        if (!(value instanceof Number number) || !Double.isFinite(number.doubleValue()) || number.doubleValue() < min || number.doubleValue() > max)
            throw new IllegalStateException("vehicle receipt " + key + " invalid");
        return number.floatValue();
    }
    private static void validateTag(String tag) {
        if (!tag.startsWith("lf-home-") || !UUID.fromString(tag.substring(8)).toString().equals(tag.substring(8)))
            throw new IllegalStateException("vehicle receipt native UUID invalid");
    }
    private static void prune(Context context) {
        tickets.values().removeIf(ticket -> !ticket.context.same(context));
        if (tickets.size() >= 32) tickets.values().removeIf(ticket -> ticket.attachedLease == 0 && !ticket.failure.isEmpty());
        if (tickets.size() >= 32) throw new IllegalStateException("vehicle save ticket limit reached");
    }
    private static void requireThread() {
        if (Thread.currentThread() != MainThread.mainThread) throw new IllegalStateException("vehicle save requires the game thread");
    }
    private static String clean(Throwable failure) {
        Throwable cause = failure instanceof java.lang.reflect.InvocationTargetException invocation && invocation.getCause() != null
                ? invocation.getCause() : failure;
        String text = cause.getClass().getSimpleName() + ": " + String.valueOf(cause.getMessage());
        return text.substring(0, Math.min(256, text.length()));
    }
    static Environment replaceEnvironmentForTests(Environment value) {
        Environment old = environment; environment = value; tickets.clear(); lastFailure = ""; return old;
    }

    private static final class NativeEnvironment implements Environment {
        public boolean capable() { return NativeAccess.READY; }
        public Context context() {
            try {
                IsoWorld world = IsoWorld.instance;
                if (world == null || world.getCell() == null || Core.getInstance().isNoSave()) throw new IllegalStateException("native world saving unavailable");
                Object fileSystem = NativeAccess.FILESYSTEM.get(null);
                return new Context(world, world.getCell(), Path.of((String) NativeAccess.SAVE_DIR.invoke(fileSystem)),
                        ((Number) NativeAccess.WORLD_VERSION.invoke(null)).intValue());
            } catch (ReflectiveOperationException failure) { throw new IllegalStateException("native save directory unavailable", failure); }
        }
        public BaseVehicle loaded(int sqlId) {
            try {
                Object values = NativeAccess.VEHICLES.invoke(IsoWorld.instance.getCell());
                Collection<?> list = vehicleCollection(values);
                BaseVehicle found = null;
                for (Object value : list) if (value instanceof BaseVehicle car && NativeAccess.SQL_ID.getInt(car) == sqlId) {
                    if (found != null) throw new IllegalStateException("duplicate native vehicle SQL identity");
                    found = car;
                }
                return found;
            } catch (ReflectiveOperationException failure) { throw new IllegalStateException("native vehicle lookup unavailable", failure); }
        }
        public boolean primaryOwned(BaseVehicle car) {
            try {
                IsoWorld world=IsoWorld.instance;
                IsoCell cell=world==null?null:world.getCell();
                float x=car.getX(),y=car.getY(),z=car.getZ();
                if (cell==null || car.getCell()!=cell || !Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)) return false;
                IsoChunkMap primary=cell.getChunkMap(0);
                Object chunk=NativeAccess.CAR_CHUNK.get(car);
                return primary!=null && chunk!=null
                        && primary.getChunkForGridSquare((int)Math.floor(x),(int)Math.floor(y))==chunk
                        && SCSplitScreenProbe.primaryAreaContains((int)Math.floor(x),(int)Math.floor(y),(int)Math.floor(z));
            } catch (ReflectiveOperationException failure) { throw new IllegalStateException("native primary vehicle ownership unavailable",failure); }
        }
        public boolean loadedObject(BaseVehicle car) {
            try {
                Object values=NativeAccess.VEHICLES.invoke(IsoWorld.instance.getCell());
                return containsIdentity(vehicleCollection(values),car);
            } catch (ReflectiveOperationException failure) { throw new IllegalStateException("native vehicle lookup unavailable",failure); }
        }
        public State state(BaseVehicle car) {
            return state(car,true);
        }
        public State physicalState(BaseVehicle car) {
            return state(car,false);
        }
        private State state(BaseVehicle car,boolean readTag) {
            try {
                int count = car.getMaxPassengers();
                if (count < 1 || count > 32) throw new IllegalStateException("native vehicle seat bound unavailable");
                boolean empty = true;
                for (int seat = 0; seat < count; seat++) if (car.getCharacter(seat) != null) empty = false;
                Object tag = readTag ? car.getModData().rawget(TAG_KEY) : null;
                return new State(NativeAccess.SQL_ID.getInt(car), car.getX(), car.getY(), car.getZ(), car.getCurrentSpeedKmHour(),
                        car.isEngineRunning(), (Boolean) NativeAccess.STARTED.invoke(car), empty, tag instanceof String text ? text : "");
            } catch (ReflectiveOperationException failure) { throw new IllegalStateException("native vehicle stop state unavailable", failure); }
        }
        public Snapshot enqueue(BaseVehicle car, String tag) throws Exception {
            Object request = null;
            boolean queued = false;
            KahluaTable data = car.getModData();
            Object previous = data.rawget(TAG_KEY);
            try {
                Object database = NativeAccess.DB_INSTANCE.get(null);
                Object streamer = NativeAccess.STREAMER.get(database);
                Object queueObject = NativeAccess.QUEUE.get(streamer);
                if (!(queueObject instanceof ConcurrentLinkedQueue<?>)) throw new IllegalStateException("native vehicle writer queue unavailable");
                Object pool = NativeAccess.POOL.get(null);
                request = NativeAccess.ALLOC.invoke(pool);
                if (!NativeAccess.REQUEST.isInstance(request)) throw new IllegalStateException("native vehicle pool returned incompatible request");
                data.rawset(TAG_KEY, tag);
                NativeAccess.INIT.invoke(request, car);
                Object buffer = NativeAccess.BUFFER.get(request);
                ByteBuffer nativeBytes = (ByteBuffer) NativeAccess.BYTES.get(buffer);
                ByteBuffer copy = nativeBytes.asReadOnlyBuffer(); copy.position(0);
                if (copy.remaining() < 1 || copy.remaining() > MAX_BYTES) throw new IllegalStateException("native vehicle snapshot byte bound exceeded");
                byte[] bytes = new byte[copy.remaining()]; copy.get(bytes);
                Snapshot snapshot = new Snapshot(NativeAccess.ID.getInt(buffer), NativeAccess.WX.getInt(buffer), NativeAccess.WY.getInt(buffer),
                        NativeAccess.X.getFloat(buffer), NativeAccess.Y.getFloat(buffer), NativeAccess.VERSION.getInt(buffer), bytes);
                if (!containsTag(bytes, tag)) throw new IllegalStateException("native vehicle serializer omitted save UUID");
                @SuppressWarnings("unchecked") ConcurrentLinkedQueue<Object> queue = (ConcurrentLinkedQueue<Object>) queueObject;
                queued = queue.add(request);
                if (!queued) throw new IllegalStateException("native vehicle writer rejected request");
                return snapshot;
            } finally {
                if (!queued) {
                    data.rawset(TAG_KEY, previous);
                    if (request != null) NativeAccess.RELEASE.invoke(request);
                }
            }
        }
    }

    /** Version-pinned native structure; unavailable fields disable Drive only. */
    private static final class NativeAccess {
        static boolean READY;
        static Class<?> REQUEST;
        static Field FILESYSTEM, DB_INSTANCE, STREAMER, QUEUE, POOL, BUFFER, BYTES, SQL_ID, CAR_CHUNK, ID, WX, WY, X, Y, VERSION;
        static Method SAVE_DIR, WORLD_VERSION, VEHICLES, STARTED, ALLOC, INIT, RELEASE;
        static Constructor<? extends KahluaTable> TABLE;
        static {
            try {
                ClassLoader loader = SCVehicleSaveBarrier.class.getClassLoader();
                Class<?> db = Class.forName("zombie.vehicles.VehiclesDB2", false, loader);
                REQUEST = Class.forName("zombie.vehicles.VehiclesDB2$QueueUpdateVehicle", false, loader);
                Class<?> buffer = Class.forName("zombie.vehicles.VehiclesDB2$VehicleBuffer", false, loader);
                Class<?> pool = Class.forName("zombie.util.Pool", false, loader);
                Class<?> fs = Class.forName("zombie.ZomboidFileSystem", false, loader);
                Class<?> cell = Class.forName("zombie.iso.IsoCell", false, loader);
                Class.forName("org.sqlite.JDBC", false, loader);
                FILESYSTEM = field(fs,"instance",fs); SAVE_DIR = fs.getMethod("getCurrentSaveDir");
                WORLD_VERSION = IsoWorld.class.getMethod("getWorldVersion"); VEHICLES = cell.getMethod("getVehicles");
                STARTED = BaseVehicle.class.getMethod("isEngineStarted"); SQL_ID = field(BaseVehicle.class,"sqlId",int.class);
                CAR_CHUNK=field(BaseVehicle.class,"chunk",IsoChunk.class);
                DB_INSTANCE = field(db,"instance",db); STREAMER = field(db,"worldStreamer",null);
                QUEUE = field(STREAMER.getType(),"queue",ConcurrentLinkedQueue.class);
                POOL = field(REQUEST,"s_pool",pool); ALLOC = pool.getMethod("alloc");
                INIT = REQUEST.getDeclaredMethod("init",BaseVehicle.class); INIT.setAccessible(true);
                RELEASE = REQUEST.getMethod("release"); RELEASE.setAccessible(true);
                BUFFER = field(REQUEST,"vehicleBuffer",buffer); BYTES = field(buffer,"bb",ByteBuffer.class);
                ID = field(buffer,"id",int.class); WX = field(buffer,"wx",int.class); WY = field(buffer,"wy",int.class);
                X = field(buffer,"x",float.class); Y = field(buffer,"y",float.class); VERSION = field(buffer,"worldVersion",int.class);
                @SuppressWarnings("unchecked") Constructor<? extends KahluaTable> table = (Constructor<? extends KahluaTable>)
                        Class.forName("se.krka.kahlua.j2se.KahluaTableImpl", false, loader).getConstructor(Map.class);
                TABLE = table;
                if (SAVE_DIR.getReturnType()!=String.class || WORLD_VERSION.getReturnType()!=int.class || STARTED.getReturnType()!=boolean.class
                        || !Collection.class.isAssignableFrom(VEHICLES.getReturnType())
                        || !Modifier.isStatic(WORLD_VERSION.getModifiers()) || INIT.getReturnType()!=void.class) throw new NoSuchMethodException("native vehicle save signature changed");
                READY = true;
            } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
                READY = false; lastFailure = "native vehicle save contract unavailable: " + clean(failure);
            }
        }
        private static Field field(Class<?> owner,String name,Class<?> type) throws NoSuchFieldException {
            Field value = owner.getDeclaredField(name); value.setAccessible(true);
            if (type != null && value.getType()!=type) throw new NoSuchFieldException(owner.getName()+"."+name+" type changed");
            return value;
        }
    }
}
