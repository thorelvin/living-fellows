// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.HexFormat;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoZombie;

/** Optional PZOptimizer boundary. No foreign classes, settings or files are replaced. */
public final class SCPZOptimizerCompatibility {
    public static final String TESTED_RELEASE = "b42.21-20261102-2253-154126d0";
    private static final String[][] FINGERPRINTS = {
        { "pzopt/ActionEval.class", "3a0f78587aaee1ee238360a361e30cb7ec629d5890331b647bd076240eb8d15d" },
        { "zombie/characters/action/ActionContext.class", "38e082c0c7721c1b2bb2dfad75e675c97df52cb5f7eed56325e6558c9d2d2e39" },
        { "zombie/characters/IsoZombie.class", "9d37dfa616438b9b6eaf7cec763976047fd3552939e61be86b5f297d35bbff8b" }
    };
    private static boolean checked;
    private static boolean present;
    private static boolean installed;
    private static volatile boolean hookSeen;
    private static volatile boolean enabled;
    private static String state = "absent";
    private static String reason = "PZOptimizer is not loaded";
    private static String failure;
    private static long inlineCalls;

    private SCPZOptimizerCompatibility() {}

    public static synchronized boolean configure(boolean requested) {
        enabled = false;
        if (!requested) {
            state = "disabled";
            reason = "PZOptimizer compatibility is off";
            return false;
        }
        if (!checked) {
            checked = true;
            ClassLoader loader = SCPZOptimizerCompatibility.class.getClassLoader();
            present = loader.getResource(FINGERPRINTS[0][0]) != null;
            if (present) {
                try {
                    for (String[] entry : FINGERPRINTS) {
                        String actual = fingerprint(loader, entry[0]);
                        if (!entry[1].equals(actual)) {
                            throw new IllegalStateException("Untested PZOptimizer class "
                                    + entry[0] + " (SHA-256 " + actual + "); tested " + TESTED_RELEASE);
                        }
                    }
                    Class<?> engine = Class.forName("me.zed_0xff.zombie_buddy.PatchEngine", false, loader);
                    Method apply = engine.getMethod("applyPatches", String.class, ClassLoader.class);
                    apply.invoke(null, "survivorcompanion.optimizerpatch", loader);
                    // Do not trust a successful loader call alone. Both overloads
                    // must reach our advice; null submissions are harmless native no-ops.
                    Class<?> evaluator = Class.forName("pzopt.ActionEval", false, loader);
                    hookSeen = false;
                    evaluator.getMethod("submit", IsoGameCharacter.class).invoke(null, new Object[] { null });
                    if (!hookSeen) throw new IllegalStateException("ZombieBuddy did not install the submit hook");
                    Method inner = evaluator.getDeclaredMethod("submit", IsoGameCharacter.class, boolean.class);
                    inner.setAccessible(true);
                    hookSeen = false;
                    inner.invoke(null, null, true);
                    if (!hookSeen) throw new IllegalStateException("ZombieBuddy did not install the head-submit hook");
                    installed = true;
                } catch (ClassNotFoundException problem) {
                    failure = "ZombieBuddy patch host is unavailable (" + problem.getMessage() + ")";
                } catch (ReflectiveOperationException | RuntimeException | LinkageError problem) {
                    Throwable cause = problem.getCause() == null ? problem : problem.getCause();
                    failure = cause.getClass().getSimpleName() + ": " + cause.getMessage();
                } catch (java.io.IOException | java.security.NoSuchAlgorithmException problem) {
                    failure = problem.getClass().getSimpleName() + ": " + problem.getMessage();
                }
            }
        }
        if (!present) {
            state = "absent";
            reason = "PZOptimizer is not loaded";
        } else if (!installed) {
            state = "unsupported";
            reason = "PZOptimizer adapter unavailable: " + failure;
        } else {
            enabled = true;
            state = "active";
            reason = "LF-target attacks run inline; PZOptimizer " + TESTED_RELEASE;
        }
        return enabled;
    }

    /** Called only by the optional submit advice; never adds or replays damage. */
    public static boolean beforeSubmit(IsoGameCharacter character) {
        if (character == null) {
            hookSeen = true;
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

    private static String fingerprint(ClassLoader loader, String path)
            throws java.io.IOException, java.security.NoSuchAlgorithmException {
        try (InputStream input = loader.getResourceAsStream(path)) {
            if (input == null) return "missing";
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[8192];
            int length;
            while ((length = input.read(buffer)) != -1) digest.update(buffer, 0, length);
            return HexFormat.of().formatHex(digest.digest());
        }
    }
}
