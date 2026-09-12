// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.MainThread;

/** One-shot, non-transforming bridge bootstrap shared by the wrapper and Java mod loaders. */
public final class SCBootstrap {
    private static volatile boolean started;
    private static volatile boolean ready;
    private static volatile String status = "native bridge has not started";
    private static volatile long generation;
    private static volatile BootstrapRun activeRun;

    private static final class BootstrapRun {
        private final long generation;
        private final java.util.concurrent.atomic.AtomicBoolean exposureQueued =
                new java.util.concurrent.atomic.AtomicBoolean();
        private volatile boolean cancelled;

        private BootstrapRun(long generation) {
            this.generation = generation;
        }
    }

    private SCBootstrap() {}

    public static synchronized void start() {
        if (started) return;
        started = true;
        BootstrapRun run = new BootstrapRun(++generation);
        activeRun = run;
        status = "waiting for Project Zomboid LuaManager";
        Thread installer = new Thread(() -> {
            long deadline = System.nanoTime() + 180_000_000_000L;
            boolean exposedOnce = false;
            while (isCurrent(run) && !Thread.currentThread().isInterrupted()
                    && (exposedOnce || System.nanoTime() < deadline)) {
                try {
                    if (MainThread.isRunning()
                            && run.exposureQueued.compareAndSet(false, true)) {
                        MainThread.queueInvokeOnMainThread(
                                () -> exposeOnMainThread(run));
                    }
                    exposedOnce = exposedOnce || ready;
                    Thread.sleep(ready ? 1_000L : 50L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    stopAfterFailure(run, "native bridge exposure interrupted");
                    return;
                } catch (RuntimeException | LinkageError failure) {
                    run.exposureQueued.set(false);
                    stopAfterFailure(run, "native bridge queue failed: "
                            + failure.getClass().getSimpleName());
                    System.err.println("[SurvivorCompanionBridge] " + status);
                    return;
                }
            }
            if (isCurrent(run) && !exposedOnce) stopAfterFailure(run,
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

    private static boolean isCurrent(BootstrapRun run) {
        return run != null && !run.cancelled && started && activeRun == run
                && generation == run.generation;
    }

    private static void exposeOnMainThread(BootstrapRun run) {
        try {
            if (!isCurrent(run)) return;
            boolean exposed = SCExposure.exposeNow();
            if (publishExposure(run, exposed)) {
                System.out.println("[SurvivorCompanionBridge] ready protocol="
                        + SCBridge.PROTOCOL);
            }
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            stopAfterFailure(run, "native bridge exposure failed: "
                    + failure.getClass().getSimpleName());
            System.err.println("[SurvivorCompanionBridge] " + status);
        } finally {
            run.exposureQueued.set(false);
        }
    }

    /** Publishes an exposure result only while its generation still owns bootstrap state. */
    private static synchronized boolean publishExposure(BootstrapRun run, boolean exposed) {
        if (!isCurrent(run)) return false;
        if (exposed) {
            boolean announce = !ready;
            ready = true;
            status = "ready";
            return announce;
        }
        ready = false;
        status = "waiting for initialized Project Zomboid LuaManager";
        return false;
    }

    private static synchronized void stopAfterFailure(BootstrapRun run, String reason) {
        if (run == null || activeRun != run || generation != run.generation) return;
        run.cancelled = true;
        activeRun = null;
        ready = false;
        started = false;
        status = reason;
    }
}
