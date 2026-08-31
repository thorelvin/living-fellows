// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/** One-shot, non-transforming bridge bootstrap shared by the wrapper and Java mod loaders. */
public final class SCBootstrap {
    private static volatile boolean started;
    private static volatile boolean ready;
    private static volatile String status = "native bridge has not started";

    private SCBootstrap() {}

    public static synchronized void start() {
        if (started) return;
        started = true;
        status = "waiting for Project Zomboid LuaManager";
        Thread installer = new Thread(() -> {
            long deadline = System.nanoTime() + 180_000_000_000L;
            boolean exposedOnce = false;
            while (!Thread.currentThread().isInterrupted()
                    && (exposedOnce || System.nanoTime() < deadline)) {
                try {
                    if (SCExposure.exposeNow()) {
                        boolean announce = !ready;
                        ready = true;
                        status = "ready";
                        exposedOnce = true;
                        if (announce) {
                            System.out.println("[SurvivorCompanionBridge] ready protocol="
                                    + SCBridge.PROTOCOL);
                        }
                        Thread.sleep(1_000L);
                        continue;
                    }
                    ready = false;
                    status = "waiting for initialized Project Zomboid LuaManager";
                    Thread.sleep(50L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    status = "native bridge exposure interrupted";
                    return;
                } catch (ReflectiveOperationException | LinkageError failure) {
                    status = "native bridge exposure failed: " + failure.getClass().getSimpleName();
                    System.err.println("[SurvivorCompanionBridge] " + status);
                    return;
                }
            }
            if (!exposedOnce) status = "native bridge exposure timed out";
        }, "SurvivorCompanion-bridge-bootstrap");
        installer.setDaemon(true);
        installer.start();
    }

    public static boolean isReady() {
        return ready;
    }

    public static String getStatus() {
        return status;
    }
}
