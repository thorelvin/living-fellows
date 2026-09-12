// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import zombie.MainThread;

/** Proves stopped bootstrap generations retire their worker and queue ticket. */
public final class SCBootstrapLifecycleTest {
    private SCBootstrapLifecycleTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static int bootstrapWorkers() {
        int count = 0;
        for (Thread thread : Thread.getAllStackTraces().keySet()) {
            if (thread.isAlive()
                    && "SurvivorCompanion-bridge-bootstrap".equals(thread.getName())) {
                count++;
            }
        }
        return count;
    }

    private static Object activeRun() throws Exception {
        Field field = SCBootstrap.class.getDeclaredField("activeRun");
        field.setAccessible(true);
        return field.get(null);
    }

    private static void stop(Object run, String reason) throws Exception {
        Method method = SCBootstrap.class.getDeclaredMethod(
                "stopAfterFailure", run.getClass(), String.class);
        method.setAccessible(true);
        method.invoke(null, run, reason);
    }

    private static void waitForQueue() throws Exception {
        long deadline = System.nanoTime() + 2_000_000_000L;
        while (MainThread.queuedForTests() == 0 && System.nanoTime() < deadline) {
            Thread.sleep(2L);
        }
        require(MainThread.queuedForTests() == 1,
                "bootstrap generation did not acquire exactly one queue ticket");
    }

    private static void drainQueue() {
        while (MainThread.queuedForTests() > 0) MainThread.runNextForTests();
    }

    public static void main(String[] args) throws Exception {
        drainQueue();
        SCBootstrap.start();
        waitForQueue();
        Object first = activeRun();
        require(first != null && SCBootstrap.isStarted(),
                "first bootstrap generation did not become active");
        stop(first, "injected first-generation failure");
        drainQueue();
        Thread.sleep(150L);
        require(!SCBootstrap.isStarted() && activeRun() == null
                        && MainThread.queuedForTests() == 0 && bootstrapWorkers() == 0,
                "failed bootstrap generation kept running or queuing callbacks");

        SCBootstrap.start();
        waitForQueue();
        Object second = activeRun();
        require(second != null && second != first && bootstrapWorkers() == 1,
                "bootstrap restart did not own one new worker generation");
        Thread.sleep(150L);
        require(MainThread.queuedForTests() == 1 && bootstrapWorkers() == 1,
                "retired generation interfered with the replacement queue ticket");
        stop(second, "test complete");
        drainQueue();
        Thread.sleep(150L);
        require(bootstrapWorkers() == 0 && MainThread.queuedForTests() == 0,
                "replacement bootstrap worker did not retire cleanly");
        System.out.println("BOOTSTRAP_GENERATION_LIFECYCLE_PASS retired=true replacement=one ticket=isolated");
    }
}
