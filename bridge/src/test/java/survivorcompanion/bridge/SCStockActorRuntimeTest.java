// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Constructs the bridge IsoSurvivor through the real production Kahlua exposure path. */
public final class SCStockActorRuntimeTest {
    private SCStockActorRuntimeTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static Object invoke(Object target, String name, Class<?>[] types, Object... args)
            throws ReflectiveOperationException {
        try {
            return target.getClass().getMethod(name, types).invoke(target, args);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtime) {
                throw runtime;
            }
            if (cause instanceof Error error) {
                throw error;
            }
            throw failure;
        }
    }

    private static Object initializeLua() throws ReflectiveOperationException {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);

        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-stock-actor-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);

        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        managerClass.getMethod("RunLua", String.class).invoke(null,
                "media/lua/shared/Definitions/HairOutfitDefinitions.lua");
        Class.forName("zombie.core.skinnedmodel.population.HairStyles")
                .getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.BeardStyles")
                .getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.OutfitManager")
                .getMethod("init").invoke(null);
        Object hairDefinitions = Class.forName("zombie.characters.HairOutfitDefinitions")
                .getField("instance").get(null);
        hairDefinitions.getClass().getMethod("checkDirty").invoke(hairDefinitions);
        Class<?> soundManagerClass = Class.forName("zombie.SoundManager");
        soundManagerClass.getField("instance").set(null,
                Class.forName("zombie.DummySoundManager").getConstructor().newInstance());
        return managerClass;
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        Class<?> managerClass = (Class<?>) initializeLua();
        Object environment = managerClass.getField("env").get(null);
        Object thread = managerClass.getField("thread").get(null);
        require(environment != null && thread != null, "LuaManager initialization failed");

        Class<?> cellClass = Class.forName("zombie.iso.IsoCell");
        Object cell = cellClass.getConstructor(int.class, int.class).newInstance(64, 64);
        Class<?> squareClass = Class.forName("zombie.iso.IsoGridSquare");
        Class<?> sliceClass = Class.forName("zombie.iso.SliceY");
        Object slice = sliceClass.getConstructor().newInstance();
        Object square = squareClass.getConstructor(cellClass, sliceClass, int.class, int.class, int.class)
                .newInstance(cell, slice, 0, 0, 0);
        Class<?> chunkClass = Class.forName("zombie.iso.IsoChunk");
        Object chunk = chunkClass.getConstructor(cellClass).newInstance(cell);
        squareClass.getField("chunk").set(square, chunk);
        squareClass.getField("solidFloor").setBoolean(square, true);
        squareClass.getField("solidFloorCached").setBoolean(square, true);
        squareClass.getField("isSolidFloorCache").setBoolean(square, true);
        chunkClass.getField("wx").setInt(chunk, 0);
        chunkClass.getField("wy").setInt(chunk, 0);
        chunkClass.getField("loaded").setBoolean(chunk, true);
        chunkClass.getMethod("setSquare", int.class, int.class, int.class, squareClass)
                .invoke(chunk, 0, 0, 0, square);
        Object[] chunkMaps = (Object[]) cellClass.getField("chunkMap").get(cell);
        require(chunkMaps.length > 0 && chunkMaps[0] != null, "fixture cell has no chunk map");
        Class<?> chunkMapClass = Class.forName("zombie.iso.IsoChunkMap");
        chunkMapClass.getField("worldX").setInt(chunkMaps[0], 0);
        chunkMapClass.getField("worldY").setInt(chunkMaps[0], 0);
        chunkMapClass.getField("ignore").setBoolean(chunkMaps[0], false);
        chunkMapClass.getMethod("setChunkDirect", chunkClass, boolean.class)
                .invoke(chunkMaps[0], chunk, true);
        chunkMapClass.getMethod("setGridSquare", squareClass, int.class, int.class, int.class)
                .invoke(chunkMaps[0], square, 0, 0, 0);

        Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
        Object world = worldClass.getConstructor().newInstance();
        worldClass.getField("instance").set(null, world);
        worldClass.getField("currentCell").set(world, cell);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        tableClass.getMethod("rawset", Object.class, Object.class)
                .invoke(environment, "SC_TEST_SQUARE", square);

        Class<?> exposureClass = Class.forName("survivorcompanion.bridge.SCExposure");
        require((Boolean) exposureClass.getMethod("exposeNow").invoke(null),
                "bridge was not exposed into LuaManager");
        Class<?> bridgeClass = Class.forName("survivorcompanion.bridge.SCBridge");
        Class<?> survivorFactoryClass = Class.forName("zombie.characters.SurvivorFactory");
        survivorFactoryClass.getMethod("addMaleForename", String.class).invoke(null, "Direct");
        survivorFactoryClass.getMethod("addFemaleForename", String.class).invoke(null, "Direct");
        survivorFactoryClass.getMethod("addSurname", String.class).invoke(null, "Control");
        try {
            Object directActor = bridgeClass.getMethod("spawn", squareClass, String.class,
                            String.class, boolean.class, String.class)
                    .invoke(null, square, "Direct", "Control", false, "");
            require(directActor != null, "direct bridge spawn returned null");
            boolean directCleanup = (Boolean) bridgeClass
                    .getMethod("remove", Class.forName("zombie.characters.IsoSurvivor"))
                    .invoke(null, directActor);
            System.out.println("DIRECT_BRIDGE_SPAWN passed cleanup=" + directCleanup);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            System.out.println("DIRECT_BRIDGE_SPAWN failed: " + cause);
            cause.printStackTrace(System.out);
            throw failure;
        }

        String source = "assert(SCBridge ~= nil, 'SCBridge is not exposed')\n"
                + "assert(SurvivorFactory ~= nil, 'SurvivorFactory is not exposed')\n"
                + "SC_TEST_READY = SCBridge.checkReady()\n"
                + "SurvivorFactory.addMaleForename('Runtime')\n"
                + "SurvivorFactory.addFemaleForename('Runtime')\n"
                + "SurvivorFactory.addSurname('Fellow')\n"
                + "SC_TEST_ACTOR = SCBridge.spawn(SC_TEST_SQUARE, 'Runtime', 'Fellow', false, '')\n";
        Class<?> compilerClass = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        Object closure = compilerClass.getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCStockActorRuntimeTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);

        Object actor = tableClass.getMethod("rawget", Object.class).invoke(environment, "SC_TEST_ACTOR");
        Object readiness = tableClass.getMethod("rawget", Object.class).invoke(environment, "SC_TEST_READY");
        System.out.println("BRIDGE_READINESS " + readiness);
        require(actor != null, "Lua did not return an actor");
        require(Class.forName("zombie.characters.IsoSurvivor").isInstance(actor),
                "Lua returned a non-IsoSurvivor actor");
        require(invoke(actor, "getBodyDamage", new Class<?>[0]) != null, "BodyDamage is null");
        require(invoke(actor, "getMoodles", new Class<?>[0]) != null, "Moodles is null");
        require(invoke(actor, "getXp", new Class<?>[0]) != null, "XP is null");
        require(invoke(actor, "getEmitter", new Class<?>[0]) != null, "emitter is null");
        Object descriptor = invoke(actor, "getDescriptor", new Class<?>[0]);
        require(descriptor != null, "descriptor is null");
        require(invoke(descriptor, "getHumanVisual", new Class<?>[0]) != null,
                "descriptor HumanVisual is null");
        require(invoke(actor, "getVisual", new Class<?>[0]) != null, "actor visual is null");

        invoke(actor, "update", new Class<?>[0]);
        require(!(Boolean) invoke(actor, "isDead", new Class<?>[0]), "actor died during one update");
        System.out.println("Bridge Kahlua IsoSurvivor test passed with native state and update");
    }
}
