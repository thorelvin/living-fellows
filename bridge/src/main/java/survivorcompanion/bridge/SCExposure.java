// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Map;

/** Exposes the narrow bridge into the game's Kahlua environment after LuaManager initializes. */
final class SCExposure {
    private static final long INIT_STABILITY_NANOS = 250_000_000L;
    private static Object candidateEnvironment;
    private static Object candidateExposer;
    private static long candidateSince;

    private SCExposure() {}

    static boolean exposeNow() throws ReflectiveOperationException {
        ClassLoader loader = SCExposure.class.getClassLoader();
        Class<?> manager = Class.forName("zombie.Lua.LuaManager", false, loader);
        Field environmentField = manager.getField("env");
        Field exposerField = manager.getField("exposer");
        Object environment = environmentField.get(null);
        Object exposer = exposerField.get(null);
        if (environment == null || exposer == null) {
            clearCandidate();
            return false;
        }

        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable", false, loader);
        Method rawget = tableClass.getMethod("rawget", Object.class);
        Field typeMapField = exposer.getClass().getField("typeMap");
        Object typeMapValue = typeMapField.get(exposer);
        boolean initSentinels = typeMapValue instanceof Map<?, ?> typeMap
                && typeMap.containsKey("function") && typeMap.containsKey("table")
                && rawget.invoke(environment, "IsoPlayer") != null;
        if (!initSentinels) {
            clearCandidate();
            return false;
        }

        // LuaManager.init() replaces env/exposer and exposeAll() mutates their
        // maps. Require the completed sentinels and a short stable generation
        // before touching either structure from the bootstrap thread.
        long now = System.nanoTime();
        if (candidateEnvironment != environment || candidateExposer != exposer) {
            candidateEnvironment = environment;
            candidateExposer = exposer;
            candidateSince = now;
            return false;
        }
        if (now - candidateSince < INIT_STABILITY_NANOS) return false;
        if (rawget.invoke(environment, "SCBridge") != null) return true;

        Method setExposed = exposer.getClass().getMethod("setExposed", Class.class);
        Method expose = exposer.getClass().getMethod("exposeLikeJava", Class.class, tableClass);
        for (Class<?> type : new Class<?>[] { SCBridge.class, SCNativeCompanion.class }) {
            setExposed.invoke(exposer, type);
            expose.invoke(exposer, type, environment);
        }
        return rawget.invoke(environment, "SCBridge") != null;
    }

    private static void clearCandidate() {
        candidateEnvironment = null;
        candidateExposer = null;
        candidateSince = 0L;
    }
}
