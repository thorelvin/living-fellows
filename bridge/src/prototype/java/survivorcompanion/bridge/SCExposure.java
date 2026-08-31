// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Installs the bridge into the actual LuaManager exposer without modifying the game JAR. */
public final class SCExposure {
    private static volatile String status = "waiting for LuaManager";
    private static volatile boolean ready;

    private SCExposure() {}

    public static void installAsync() {
        Thread installer = new Thread(() -> {
            long deadline = System.nanoTime() + 120_000_000_000L;
            while (System.nanoTime() < deadline && !ready) {
                try {
                    if (exposeNow()) {
                        return;
                    }
                    Thread.sleep(10L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    status = "bridge exposure interrupted";
                    return;
                } catch (Throwable failure) {
                    status = "bridge exposure failed: " + failure.getClass().getSimpleName();
                    return;
                }
            }
            if (!ready) {
                status = "LuaManager exposure timed out";
            }
        }, "SurvivorCompanion-bridge-exposure");
        installer.setDaemon(true);
        installer.start();
    }

    public static synchronized boolean exposeNow() throws ReflectiveOperationException {
        if (ready) {
            return true;
        }
        ClassLoader loader = SCExposure.class.getClassLoader();
        Class<?> manager = Class.forName("zombie.Lua.LuaManager", false, loader);
        Field environmentField = manager.getField("env");
        Field exposerField = manager.getField("exposer");
        Object environment = environmentField.get(null);
        Object exposer = exposerField.get(null);
        if (environment == null || exposer == null) {
            return false;
        }

        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable", false, loader);
        Method setExposed = exposer.getClass().getMethod("setExposed", Class.class);
        Method expose = exposer.getClass().getMethod("exposeLikeJava", Class.class, tableClass);
        setExposed.invoke(exposer, SCBridge.class);
        expose.invoke(exposer, SCBridge.class, environment);
        ready = true;
        status = "ready";
        return true;
    }

    public static boolean isReady() {
        return ready;
    }

    public static String getStatus() {
        return status;
    }
}
