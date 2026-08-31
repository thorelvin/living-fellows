// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

/** Evaluates the non-IsoSurvivor alternative without a Java agent. */
public final class SCNativeCharacterPrototypeTest {
    private SCNativeCharacterPrototypeTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        try {
            return target.getClass().getMethod(name).invoke(target);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtime) throw runtime;
            if (cause instanceof Error error) throw error;
            throw failure;
        }
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-native-prototype-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);
        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        Object environment = managerClass.getField("env").get(null);
        Object thread = managerClass.getField("thread").get(null);

        Class<?> soundManagerClass = Class.forName("zombie.SoundManager");
        Object dummySoundManager = Class.forName("zombie.DummySoundManager").getConstructor().newInstance();
        soundManagerClass.getField("instance").set(null, dummySoundManager);

        Class<?> cellClass = Class.forName("zombie.iso.IsoCell");
        Object cell = cellClass.getConstructor(int.class, int.class).newInstance(64, 64);
        Class<?> sliceClass = Class.forName("zombie.iso.SliceY");
        Class<?> squareClass = Class.forName("zombie.iso.IsoGridSquare");
        Object square = squareClass.getConstructor(cellClass, sliceClass, int.class, int.class, int.class)
                .newInstance(cell, sliceClass.getConstructor().newInstance(), 0, 0, 0);
        squareClass.getField("solidFloor").setBoolean(square, true);
        squareClass.getField("solidFloorCached").setBoolean(square, true);
        squareClass.getField("isSolidFloorCache").setBoolean(square, true);

        Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
        Object world = worldClass.getConstructor().newInstance();
        worldClass.getField("instance").set(null, world);
        worldClass.getField("currentCell").set(world, cell);

        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Object descriptor = descriptorClass.getConstructor().newInstance();
        descriptorClass.getMethod("setForename", String.class).invoke(descriptor, "Prototype");
        descriptorClass.getMethod("setSurname", String.class).invoke(descriptor, "Fellow");

        Object exposer = managerClass.getField("exposer").get(null);
        Class<?> prototype = Class.forName("survivorcompanion.bridge.SCNativeCharacterPrototype");
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        exposer.getClass().getMethod("setExposed", Class.class).invoke(exposer, prototype);
        exposer.getClass().getMethod("exposeLikeJava", Class.class, tableClass)
                .invoke(exposer, prototype, environment);
        tableClass.getMethod("rawset", Object.class, Object.class).invoke(environment, "SC_TEST_DESC", descriptor);
        tableClass.getMethod("rawset", Object.class, Object.class).invoke(environment, "SC_TEST_SQUARE", square);

        Class<?> compilerClass = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        String source = "assert(SCNativeCharacterPrototype ~= nil)\n"
                + "SC_TEST_ACTOR = SCNativeCharacterPrototype.new(SC_TEST_DESC, SC_TEST_SQUARE)\n";
        Object closure = compilerClass.getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCNativeCharacterPrototypeTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);
        Object actor = tableClass.getMethod("rawget", Object.class).invoke(environment, "SC_TEST_ACTOR");

        require(actor != null, "Kahlua did not construct the prototype");
        require(invoke(actor, "getBodyDamage") != null, "BodyDamage is null");
        require(invoke(actor, "getMoodles") != null, "Moodles is null");
        require(invoke(actor, "getXp") != null, "XP is null");
        require(invoke(actor, "getEmitter") != null, "emitter is null");
        require(invoke(actor, "getVisual") != null, "HumanVisual is null");
        invoke(actor, "update");
        require(!(Boolean) invoke(actor, "isDead"), "prototype died during update");
        require(!Class.forName("zombie.characters.IsoSurvivor").isInstance(actor),
                "prototype unexpectedly satisfies the required actor type");
        System.out.println("Native IsoLivingCharacter prototype passed components/update but is not IsoSurvivor");
    }
}
