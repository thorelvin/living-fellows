// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.IOException;
import java.io.InputStream;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.CodeSource;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import survivorcompanion.optimizerpatch.SCOptimizerSubmitPatch;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoZombie;
import zombie.characters.action.ActionContext;

/** Recognizes specific PZ_Optimization releases before installing LF's optional submit advice. */
public final class SCPZOptimizerCompatibility {
    private static final String LEGACY_RELEASE = "b42.21-20261102-2253-154126d0";
    private static final String SIGNED_RELEASE = "b42.22.2-20261120-2110-20f89d32 (official Java agent)";
    private static final String EVALUATOR = "pzopt.ActionEval";
    private static final String PATCH_PACKAGE = "survivorcompanion.optimizerpatch";
    private static final String GAME_JAR = "projectzomboid.jar";
    private static final String STOCK_GAME_SHA = "3c4a7c5f149d784758c6fb5f8fa85f3a21d572e38bc081400e89035f8120d287";
    private static final String AGENT = "pzopt/agent/pzopt-agent.jar";
    private static final String AGENT_OPTION = "-javaagent:";
    private static final String OVERRIDE_DIRECTORY = "pzopt/overrides/";
    private static final String ACTION_CONTEXT = "zombie/characters/action/ActionContext.class";
    private static final String ZOMBIE = "zombie/characters/IsoZombie.class";
    private static final String CHARACTER = "zombie/characters/IsoGameCharacter.class";
    private static final Pin ACTION_EVAL = new Pin("pzopt/ActionEval.class",
            "3a0f78587aaee1ee238360a361e30cb7ec629d5890331b647bd076240eb8d15d");
    private static final Pin LEGACY_CONTEXT = new Pin(ACTION_CONTEXT,
            "38e082c0c7721c1b2bb2dfad75e675c97df52cb5f7eed56325e6558c9d2d2e39");
    private static final Pin LEGACY_ZOMBIE = new Pin(ZOMBIE,
            "9d37dfa616438b9b6eaf7cec763976047fd3552939e61be86b5f297d35bbff8b");
    private static final List<Pin> SIGNED_PINS = List.of(
            ACTION_EVAL,
            new Pin(AGENT, "16eb7ab37c166463b838d0a79fe90fab6664f9af3f6b72c8e0f7ccb91ea325fb"),
            new Pin("pzopt/build-info.properties", "81df1598c96bca20596e7db6539178f2a6303209f440a2bed7bea4e788353586"),
            new Pin("pzopt/BuildInfo.class", "b1fdab4b2f77ce8e58da466e5bc40cb663b1cd62ac2faf55bb00054168924e94"),
            new Pin("pzopt/Overrides.class", "357ec19cf41a96d852cc4fb4d251ee3ea6d351a26a56452be6875bb509228ca0"),
            new Pin(OVERRIDE_DIRECTORY + ACTION_CONTEXT, "cf4176d727f10ed4a5737d574feb43150d9a7d6c9e7623755becc07c3e32b8bd"),
            new Pin(OVERRIDE_DIRECTORY + ZOMBIE, "007d52b99f0285861c68b9f33b588bae82b9fb5ef0815b9bf5bf193771b0be33"),
            new Pin(OVERRIDE_DIRECTORY + CHARACTER, "98a03292584e24215688dff78c7aa282042be9660fea68e9942c8e1f400dc114"));

    private static boolean checked;
    private static boolean present;
    private static String release;
    private static String failure;
    private static String absentReason = "PZ_Optimization is not loaded";
    private static String state = "absent";
    private static String reason = absentReason;
    private static volatile boolean enabled;
    private static volatile Thread probeThread;
    private static boolean hookSeen;
    private static long inlineCalls;

    private record Pin(String resource, String sha256) {}

    private SCPZOptimizerCompatibility() {}

    public static synchronized boolean configure(boolean requested) {
        enabled = false;
        if (!requested) {
            state = "disabled";
            reason = "PZ_Optimization compatibility is off";
            return false;
        }
        if (!checked) {
            checked = true;
            checkAndInstall();
        }
        if (!present) {
            state = "absent";
            reason = absentReason;
        } else if (release == null) {
            state = "unsupported";
            reason = "PZ_Optimization adapter unavailable. " + failure;
        } else {
            enabled = true;
            state = "active";
            reason = "LF-target attacks run inline with PZ_Optimization " + release;
        }
        return enabled;
    }

    private static void checkAndInstall() {
        ClassLoader bridgeLoader = SCPZOptimizerCompatibility.class.getClassLoader();
        ClassLoader gameLoader = IsoGameCharacter.class.getClassLoader();
        try {
            present = bridgeLoader.getResource(ACTION_EVAL.resource()) != null
                    || gameLoader.getResource(ACTION_EVAL.resource()) != null
                    || gameLoader.getResource(OVERRIDE_DIRECTORY + ACTION_CONTEXT) != null;
            if (!present) {
                if (gameLoader.getResource("com/pzoptimizer/PZOEntrypoint.class") != null
                        || bridgeLoader.getResource("com/pzoptimizer/PZOEntrypoint.class") != null) {
                    absentReason = "PZ_Optimization is not loaded (prop11 PZO Launcher detected)";
                }
                return;
            }

            verifyResource(gameLoader, ACTION_EVAL);
            Class<?> evaluator = Class.forName(EVALUATOR, false, gameLoader);
            require(Class.forName(EVALUATOR, false, bridgeLoader) == evaluator,
                    "Bridge and game resolve different PZ_Optimization evaluators");
            String profile = verifiedProfile(gameLoader, evaluator);
            installAdvice(bridgeLoader, evaluator);
            release = profile;
        } catch (ReflectiveOperationException | IOException | NoSuchAlgorithmException
                | URISyntaxException | RuntimeException | LinkageError problem) {
            Throwable cause = problem.getCause() == null ? problem : problem.getCause();
            // A failed installation remains inert even if the host applied part of the advice.
            present = true;
            failure = cause.getMessage() == null ? cause.getClass().getSimpleName() : cause.getMessage();
        }
    }

    private static String verifiedProfile(ClassLoader gameLoader, Class<?> evaluator)
            throws ReflectiveOperationException, IOException, NoSuchAlgorithmException, URISyntaxException {
        if (gameLoader.getResource(OVERRIDE_DIRECTORY + ACTION_CONTEXT) != null
                || gameLoader.getResource(AGENT) != null) {
            verifySignedAgent(gameLoader, evaluator);
            return SIGNED_RELEASE;
        }
        verifyResource(gameLoader, LEGACY_CONTEXT);
        verifyResource(gameLoader, LEGACY_ZOMBIE);
        return LEGACY_RELEASE;
    }

    private static void verifySignedAgent(ClassLoader gameLoader, Class<?> evaluator)
            throws ReflectiveOperationException, IOException, NoSuchAlgorithmException, URISyntaxException {
        // The official agent transforms definitions from the signed game JAR. The
        // original class resource still points at stock bytes in this mode.
        require(gameLoader == ClassLoader.getSystemClassLoader()
                        && evaluator.getClassLoader() == gameLoader
                        && ActionContext.class.getClassLoader() == gameLoader
                        && IsoZombie.class.getClassLoader() == gameLoader,
                "The signed PZ_Optimization profile requires the system game class loader");

        Path gameJar = sourcePath(IsoGameCharacter.class);
        require(GAME_JAR.equalsIgnoreCase(gameJar.getFileName().toString())
                        && gameJar.equals(sourcePath(ActionContext.class))
                        && gameJar.equals(sourcePath(IsoZombie.class))
                        && isSigned(IsoGameCharacter.class)
                        && isSigned(ActionContext.class)
                        && isSigned(IsoZombie.class),
                "Game classes lack the signed projectzomboid.jar origin");
        Path gameRoot = gameJar.getParent();
        require(gameRoot.equals(sourcePath(evaluator)),
                "PZ_Optimization evaluator is outside the verified loose-class installation");
        Path agentJar = installedFile(gameRoot, AGENT);
        require(hasOfficialAgentOption(ManagementFactory.getRuntimeMXBean().getInputArguments(), agentJar),
                "The official PZ_Optimization Java agent is not a JVM startup agent");
        require(STOCK_GAME_SHA.equals(fileFingerprint(gameJar)), "Untested signed game JAR");
        for (Pin pin : SIGNED_PINS) {
            verifyFingerprint(pin, fileFingerprint(installedFile(gameRoot, pin.resource())));
        }
        Class<?> agent = Class.forName("pzoptagent.Agent", false, gameLoader);
        require(agent.getClassLoader() == gameLoader && agentJar.equals(sourcePath(agent)),
                "PZ_Optimization Java agent has an unexpected class origin");

        // On-disk optimizer files alone do not prove that premain transformed
        // these loaded classes. Verify their added members without invoking them.
        try {
            requireField(ActionContext.class, "pzoptTaskClaim", int.class, Modifier.PUBLIC | Modifier.VOLATILE);
            requireMethod(ActionContext.class, "pzoptSnapshot", void.class, Modifier.PUBLIC);
            requireField(IsoZombie.class, "pzoptStreamGen", int.class, Modifier.PUBLIC);
            requireMethod(IsoZombie.class, "pzoptCleanPostupdate", byte.class, Modifier.PUBLIC);
            requireMethod(IsoGameCharacter.class, "pzoptEvalTask", void.class, Modifier.PUBLIC);
            requireMethod(IsoGameCharacter.class, "pzoptPostUpdateAnimatingRest", void.class, Modifier.PUBLIC);
        } catch (NoSuchFieldException | NoSuchMethodException missing) {
            throw new IllegalStateException("Loaded game classes lack the PZ_Optimization agent ABI ("
                    + missing.getMessage() + ")");
        }
    }

    private static void installAdvice(ClassLoader bridgeLoader, Class<?> evaluator)
            throws ReflectiveOperationException {
        Method submit = requireMethod(evaluator, "submit", boolean.class,
                Modifier.PUBLIC | Modifier.STATIC, IsoGameCharacter.class);
        Method inner = requireMethod(evaluator, "submit", boolean.class,
                Modifier.PRIVATE | Modifier.STATIC, IsoGameCharacter.class, boolean.class);
        inner.setAccessible(true);

        Class<?> engine;
        try {
            engine = Class.forName("me.zed_0xff.zombie_buddy.PatchEngine", false, bridgeLoader);
        } catch (ClassNotFoundException problem) {
            throw new IllegalStateException("ZombieBuddy patch host is unavailable");
        }
        Method collect = engine.getMethod("collectPatches", String.class, ClassLoader.class);
        Method apply = engine.getMethod("applyPatches", String.class, ClassLoader.class);
        ClassLoader discoveryLoader = bridgeLoader;
        Object patches = collect.invoke(null, PATCH_PACKAGE, discoveryLoader);
        if (patches instanceof List<?> found && found.isEmpty()) {
            // ZombieBuddy's mod loader appends approved JARs through
            // Instrumentation. Its null-loader scan includes those JARs.
            discoveryLoader = null;
            patches = collect.invoke(null, PATCH_PACKAGE, discoveryLoader);
        }
        require(List.of(SCOptimizerSubmitPatch.class).equals(patches),
                "ZombieBuddy did not discover exactly the Living Fellows optimizer advice");
        apply.invoke(null, PATCH_PACKAGE, discoveryLoader);

        // Probe the public route and the direct private route used by the head
        // submission. An exact ActionEval treats a null submission as a no-op.
        probeThread = Thread.currentThread();
        try {
            probe(submit, "submit", new Object[] { null });
            probe(inner, "head-submit", null, true);
        } finally {
            probeThread = null;
        }
    }

    private static void probe(Method method, String route, Object... arguments)
            throws ReflectiveOperationException {
        hookSeen = false;
        Object result = method.invoke(null, arguments);
        require(Boolean.FALSE.equals(result) && hookSeen,
                "ZombieBuddy did not verify the PZ_Optimization " + route + " hook");
    }

    /** Called only by the optional submit advice; never adds or replays damage. */
    public static boolean beforeSubmit(IsoGameCharacter character) {
        if (character == null) {
            if (Thread.currentThread() == probeThread) hookSeen = true;
            return false;
        }
        if (!enabled || !(character instanceof IsoZombie zombie)
                || !SCBridge.isCompanion(zombie.getTarget())) return false;
        inlineCalls++;
        return true;
    }

    public static synchronized String state() { return state; }
    public static synchronized String reason() { return reason; }
    public static long inlineCalls() { return inlineCalls; }

    private static Path sourcePath(Class<?> type) throws URISyntaxException, IOException {
        CodeSource source = type.getProtectionDomain().getCodeSource();
        require(source != null && source.getLocation() != null && "file".equals(source.getLocation().getProtocol()),
                "No local code source for " + type.getName());
        return Path.of(source.getLocation().toURI()).toRealPath();
    }

    private static boolean isSigned(Class<?> type) {
        CodeSource source = type.getProtectionDomain().getCodeSource();
        return source != null && source.getCodeSigners() != null && source.getCodeSigners().length != 0;
    }

    private static Path installedFile(Path gameRoot, String relative) throws IOException {
        Path file = gameRoot.resolve(relative);
        require(Files.isRegularFile(file), "Missing PZ_Optimization file " + relative);
        Path actual = file.toRealPath();
        require(actual.startsWith(gameRoot), "PZ_Optimization file outside game directory " + relative);
        return actual;
    }

    private static boolean hasOfficialAgentOption(List<String> options, Path agentJar) {
        for (String option : options) {
            if (!option.startsWith(AGENT_OPTION)) continue;
            String value = option.substring(AGENT_OPTION.length());
            int arguments = value.indexOf('=');
            if (arguments >= 0) value = value.substring(0, arguments);
            if (value.length() > 1 && value.startsWith("\"") && value.endsWith("\"")) {
                value = value.substring(1, value.length() - 1);
            }
            try {
                if (!value.isBlank() && agentJar.equals(Path.of(value).toRealPath())) return true;
            } catch (IOException | IllegalArgumentException missing) {
                // Unrelated JVM agents need not use a filesystem path that resolves here.
            }
        }
        return false;
    }

    private static Method requireMethod(Class<?> owner, String name, Class<?> result, int modifiers,
            Class<?>... parameters) throws NoSuchMethodException {
        Method method = owner.getDeclaredMethod(name, parameters);
        require(method.getReturnType() == result && method.getModifiers() == modifiers,
                "Unexpected runtime method " + owner.getName() + "." + name);
        return method;
    }

    private static void requireField(Class<?> owner, String name, Class<?> type, int modifiers)
            throws NoSuchFieldException {
        var field = owner.getDeclaredField(name);
        require(field.getType() == type && field.getModifiers() == modifiers,
                "Unexpected runtime field " + owner.getName() + "." + name);
    }

    private static void verifyResource(ClassLoader loader, Pin pin) throws IOException, NoSuchAlgorithmException {
        verifyFingerprint(pin, resourceFingerprint(loader, pin.resource()));
    }

    private static void verifyFingerprint(Pin pin, String actual) {
        require(pin.sha256().equals(actual),
                "Untested PZ_Optimization file " + pin.resource() + " (SHA-256 " + actual + ")");
    }

    private static String resourceFingerprint(ClassLoader loader, String resource)
            throws IOException, NoSuchAlgorithmException {
        try (InputStream input = loader.getResourceAsStream(resource)) {
            return input == null ? "missing" : fingerprint(input);
        }
    }

    private static String fileFingerprint(Path file) throws IOException, NoSuchAlgorithmException {
        try (InputStream input = Files.newInputStream(file)) {
            return fingerprint(input);
        }
    }

    private static String fingerprint(InputStream input) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[8192];
        int length;
        while ((length = input.read(buffer)) != -1) digest.update(buffer, 0, length);
        return HexFormat.of().formatHex(digest.digest());
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
