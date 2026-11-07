// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;
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

    private static long exposureDeadline(Object run) throws Exception {
        Field field = run.getClass().getDeclaredField("exposureDeadlineNanos");
        field.setAccessible(true);
        return field.getLong(run);
    }

    private static void stop(Object run, String reason) throws Exception {
        Method method = SCBootstrap.class.getDeclaredMethod(
                "stopAfterFailure", run.getClass(), String.class);
        method.setAccessible(true);
        method.invoke(null, run, reason);
    }

    private static boolean publish(Object run, boolean exposed) throws Exception {
        Method method = SCBootstrap.class.getDeclaredMethod(
                "publishExposure", run.getClass(), boolean.class);
        method.setAccessible(true);
        return (Boolean) method.invoke(null, run, exposed);
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

    private static Path sourceOf(Class<?> type) throws Exception {
        return Path.of(type.getProtectionDomain().getCodeSource().getLocation().toURI())
                .toRealPath();
    }

    private static void verifyPremainChild(String[] args) throws Exception {
        require(args.length == 3 && "host-argument".equals(args[2]),
                "agent consumed or changed host main arguments");
        Path agentJar = Path.of(args[1]).toRealPath();
        require(SCBootstrap.isStarted() && SCBootstrap.getGeneration() == 1,
                "bootstrap was not started before the host main");
        require(sourceOf(SCBootstrapAgent.class).equals(agentJar)
                        && sourceOf(SCBootstrap.class).equals(agentJar),
                "premain did not use the actual packaged bridge classes");
        waitForQueue();
        Object run = activeRun();
        SCBootstrapAgent.premain(null, null);
        SCBootstrapAgent.premain("", null);
        SCBootstrap.start();
        require(activeRun() == run && SCBootstrap.getGeneration() == 1
                        && bootstrapWorkers() == 1 && MainThread.queuedForTests() == 1,
                "agent and ordinary bootstrap created duplicate workers or queue tickets");
        boolean rejected = false;
        try { SCBootstrapAgent.premain("unexpected", null); }
        catch (IllegalArgumentException expected) { rejected = true; }
        require(rejected && activeRun() == run && SCBootstrap.getGeneration() == 1,
                "unexpected agent options were accepted or changed active ownership");
        stop(run, "premain child complete");
        drainQueue();
        Thread.sleep(150L);
        require(bootstrapWorkers() == 0, "premain test left a bootstrap worker alive");
        System.out.println("BOOTSTRAP_AGENT_PREMAIN_PASS before_main=true workers=one args=preserved");
    }

    private static void verifyRealAgent(Path agentJar) throws Exception {
        require(Files.isRegularFile(agentJar), "actual bridge agent JAR is missing");
        String separator = System.getProperty("path.separator");
        String classpath = sourceOf(SCBootstrapLifecycleTest.class) + separator
                + agentJar.toRealPath() + separator + sourceOf(MainThread.class);
        Path java = Path.of(System.getProperty("java.home"), "bin",
                System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java");
        Process child = new ProcessBuilder(java.toString(), "-Xmx128m",
                "-XX:ActiveProcessorCount=2", "-XX:+UseSerialGC",
                "-javaagent:" + agentJar.toRealPath(), "-cp", classpath,
                SCBootstrapLifecycleTest.class.getName(), "--premain-child",
                agentJar.toRealPath().toString(), "host-argument")
                .redirectErrorStream(true).start();
        if (!child.waitFor(10, TimeUnit.SECONDS)) {
            child.destroyForcibly();
            throw new AssertionError("bootstrap agent child exceeded ten seconds");
        }
        String output = new String(child.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        require(child.exitValue() == 0 && output.contains("BOOTSTRAP_AGENT_PREMAIN_PASS"),
                "real -javaagent launch failed: " + output);
        System.out.print(output);
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && "--premain-child".equals(args[0])) {
            verifyPremainChild(args);
            return;
        }
        if (args.length == 2 && "--agent-jar".equals(args[0])) {
            verifyRealAgent(Path.of(args[1]));
        }
        drainQueue();
        MainThread.setRunningForTests(false);
        SCBootstrap.start();
        Thread.sleep(150L);
        Object waiting = activeRun();
        require(waiting != null && SCBootstrap.isStarted() && bootstrapWorkers() == 1
                        && MainThread.queuedForTests() == 0 && exposureDeadline(waiting) == 0L,
                "pre-game host setup armed the exposure timeout or queued game work");
        MainThread.setRunningForTests(true);
        waitForQueue();
        Object first = activeRun();
        require(first == waiting && SCBootstrap.isStarted() && exposureDeadline(first) != 0L,
                "game startup did not arm and queue the same bootstrap generation");
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
        String replacementStatus = SCBootstrap.getStatus();
        require(!publish(first, true) && !SCBootstrap.isReady()
                        && replacementStatus.equals(SCBootstrap.getStatus()),
                "retired in-flight exposure published readiness into its replacement");
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
