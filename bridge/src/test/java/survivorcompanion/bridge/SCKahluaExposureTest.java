// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Locale;

/** Exercises the same LuaManager environment and luajava binding used by production Lua. */
public final class SCKahluaExposureTest {
    private SCKahluaExposureTest() {}

    /** A harmless class used to prove that exposure requires an explicit host call. */
    public static final class ProbeBridge {
        private ProbeBridge() {}

        public static String getProtocol() {
            return "42.20.4-sc.1";
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);

        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-kahlua-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);

        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);

        Field environmentField = managerClass.getField("env");
        Field threadField = managerClass.getField("thread");
        Object environment = environmentField.get(null);
        Object thread = threadField.get(null);
        require(environment != null, "LuaManager did not create an environment");
        require(thread != null, "LuaManager did not create a Kahlua thread");

        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> compilerClass = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        Method loadString = compilerClass.getMethod("loadstring", String.class, String.class, tableClass);
        Method call = thread.getClass().getMethod("call", Object.class, Object[].class);
        Method rawget = tableClass.getMethod("rawget", Object.class);
        String baselineSource = "SC_BASELINE_SCBRIDGE = SCBridge ~= nil\n"
                + "SC_BASELINE_PROBE = ProbeBridge ~= nil\n"
                + "SC_BASELINE_ATTACKTYPE = AttackType ~= nil\n"
                + "SC_HAS_LUAJAVA = luajava ~= nil\n"
                + "SC_HAS_CLASS = Class ~= nil\n"
                + "SC_HAS_LUAMANAGER = LuaManager ~= nil\n"
                + "SC_HAS_GETCLASS = getClass ~= nil\n";
        Object baselineClosure = loadString.invoke(null, baselineSource,
                "SCKahluaExposureBaseline.lua", environment);
        call.invoke(thread, baselineClosure, (Object) new Object[0]);
        require(Boolean.FALSE.equals(rawget.invoke(environment, "SC_BASELINE_SCBRIDGE")),
                "custom SCBridge unexpectedly appeared on the stock Kahlua path");
        require(Boolean.FALSE.equals(rawget.invoke(environment, "SC_BASELINE_PROBE")),
                "probe class unexpectedly appeared before explicit exposure");
        require(Boolean.FALSE.equals(rawget.invoke(environment, "SC_BASELINE_ATTACKTYPE")),
                "stock 42.20.4 unexpectedly exposed AttackType to Kahlua");

        Object exposer = managerClass.getField("exposer").get(null);
        require(exposer != null, "LuaManager did not create its Java exposer");
        Class<?> bridgeClass = ProbeBridge.class;
        exposer.getClass().getMethod("setExposed", Class.class).invoke(exposer, bridgeClass);
        exposer.getClass().getMethod("exposeLikeJava", Class.class, tableClass)
                .invoke(exposer, bridgeClass, environment);

        String source = "SC_JAVA_TYPE = type(java)\n"
                + "SC_HAS_JAVA_LANG = java ~= nil and java.lang ~= nil\n"
                + "SC_HAS_JAVA_CLASS = java ~= nil and java.lang ~= nil and java.lang.Class ~= nil\n"
                + "SC_HAS_SC_PACKAGE = survivorcompanion ~= nil\n"
                + "SC_HAS_ACTION_ANIMS = CharacterActionAnims ~= nil"
                + " and CharacterActionAnims.Bandage ~= nil"
                + " and CharacterActionAnims.Craft ~= nil"
                + " and CharacterActionAnims.Read ~= nil\n"
                + "SC_HAS_PROBE = ProbeBridge ~= nil\n"
                + "if ProbeBridge ~= nil then SC_RUNTIME_PROTOCOL = ProbeBridge.getProtocol() end\n";
        Object closure = loadString.invoke(null, source, "SCBridgeExposureTest.lua", environment);
        call.invoke(thread, closure, (Object) new Object[0]);
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_HAS_ACTION_ANIMS")),
                "CharacterActionAnims enum values are not available to production Kahlua");

        System.out.println("baseline-SCBridge=" + rawget.invoke(environment, "SC_BASELINE_SCBRIDGE")
                + " baseline-probe=" + rawget.invoke(environment, "SC_BASELINE_PROBE")
                + " baseline-AttackType=" + rawget.invoke(environment,
                        "SC_BASELINE_ATTACKTYPE"));
        System.out.println("luajava=" + rawget.invoke(environment, "SC_HAS_LUAJAVA")
                + " Class=" + rawget.invoke(environment, "SC_HAS_CLASS")
                + " LuaManager=" + rawget.invoke(environment, "SC_HAS_LUAMANAGER")
                + " getClass=" + rawget.invoke(environment, "SC_HAS_GETCLASS"));
        System.out.println("java-type=" + rawget.invoke(environment, "SC_JAVA_TYPE")
                + " java.lang=" + rawget.invoke(environment, "SC_HAS_JAVA_LANG")
                + " java.lang.Class=" + rawget.invoke(environment, "SC_HAS_JAVA_CLASS")
                + " survivorcompanion-package=" + rawget.invoke(environment, "SC_HAS_SC_PACKAGE"));
        System.out.println("explicitly-exposed-probe=" + rawget.invoke(environment, "SC_HAS_PROBE")
                + " protocol=" + rawget.invoke(environment, "SC_RUNTIME_PROTOCOL"));
        Object iterator = tableClass.getMethod("iterator").invoke(environment);
        Class<?> iteratorClass = Class.forName("se.krka.kahlua.vm.KahluaTableIterator");
        Method advance = iteratorClass.getMethod("advance");
        Method getKey = iteratorClass.getMethod("getKey");
        while ((Boolean) advance.invoke(iterator)) {
            String key = String.valueOf(getKey.invoke(iterator));
            String lower = key.toLowerCase(Locale.ROOT);
            if (lower.contains("class") || lower.contains("java") || lower.contains("reflect")
                    || lower.contains("expos")) {
                System.out.println("candidate-global=" + key);
            }
        }
    }
}
