// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.concurrent.atomic.AtomicBoolean;
import zombie.MainThread;

/** One-shot, non-transforming bridge bootstrap shared by the wrapper and Java mod loaders. */
public final class SCBootstrap {
    private static volatile boolean started;
    private static volatile boolean ready;
    private static volatile String status = "native bridge has not started";
    private static final AtomicBoolean exposureQueued = new AtomicBoolean();
    private static volatile long generation;

    private SCBootstrap() {}

    public static synchronized void start() {
        if (started) return;
        started = true;
        long runGeneration = ++generation;
        status = "waiting for Project Zomboid LuaManager";
        Thread installer = new Thread(() -> {
            long deadline = System.nanoTime() + 180_000_000_000L;
            boolean exposedOnce = false;
            while (!Thread.currentThread().isInterrupted()
                    && (exposedOnce || System.nanoTime() < deadline)) {
                try {
                    if (MainThread.isRunning()
                            && exposureQueued.compareAndSet(false, true)) {
                        MainThread.queueInvokeOnMainThread(
                                () -> exposeOnMainThread(runGeneration));
                    }
                    exposedOnce = exposedOnce || ready;
                    Thread.sleep(ready ? 1_000L : 50L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    stopAfterFailure(runGeneration, "native bridge exposure interrupted");
                    return;
                } catch (RuntimeException | LinkageError failure) {
                    exposureQueued.set(false);
                    stopAfterFailure(runGeneration, "native bridge queue failed: "
                            + failure.getClass().getSimpleName());
                    System.err.println("[SurvivorCompanionBridge] " + status);
                    return;
                }
            }
            if (!exposedOnce) stopAfterFailure(runGeneration,
                    "native bridge exposure timed out");
        }, "SurvivorCompanion-bridge-bootstrap");
        installer.setDaemon(true);
        installer.start();
    }

    public static boolean isReady() {
        return ready;
    }

    public static boolean isStarted() {
        return started;
    }

    public static String getStatus() {
        return status;
    }

    private static void exposeOnMainThread(long runGeneration) {
        try {
            if (!started || generation != runGeneration) return;
            if (SCExposure.exposeNow()) {
                boolean announce = !ready;
                ready = true;
                status = "ready";
                if (announce) {
                    System.out.println("[SurvivorCompanionBridge] ready protocol="
                            + SCBridge.PROTOCOL);
                }
            } else {
                ready = false;
                status = "waiting for initialized Project Zomboid LuaManager";
            }
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            stopAfterFailure(runGeneration, "native bridge exposure failed: "
                    + failure.getClass().getSimpleName());
            System.err.println("[SurvivorCompanionBridge] " + status);
        } finally {
            exposureQueued.set(false);
        }
    }

    private static synchronized void stopAfterFailure(long runGeneration, String reason) {
        if (generation != runGeneration) return;
        ready = false;
        started = false;
        status = reason;
    }
}
