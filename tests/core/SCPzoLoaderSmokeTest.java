// SPDX-License-Identifier: MIT
import java.io.File;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/** Runs inside the real Windows game executable; no world or user save is loaded. */
public final class SCPzoLoaderSmokeTest {
    private static boolean flag(Object metadata, String name) throws Exception {
        Field field = metadata.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return Boolean.TRUE.equals(field.get(metadata));
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new AssertionError("Pass canonical and standalone bridge paths");
        Class<?> loader = Class.forName("com.pzoptimizer.JavaModLoader");
        Method metadata = loader.getDeclaredMethod("findModMetadataForJar", File.class);
        metadata.setAccessible(true);
        Object canonical = metadata.invoke(null, new File(args[0]));
        if (!flag(canonical, "isZombieBuddyMod")) {
            throw new AssertionError("Negative control: canonical Workshop metadata must be deferred");
        }
        Object standalone = metadata.invoke(null, new File(args[1]));
        if (flag(standalone, "isZombieBuddyMod") || flag(standalone, "requiresZombieBuddy")) {
            throw new AssertionError("Standalone metadata would make PZO skip the bridge");
        }
        Method entry = loader.getDeclaredMethod("invokeEntrypoint", File.class, String.class, Instrumentation.class);
        entry.setAccessible(true);
        // PZO supplies its Instrumentation after its own bootstrap. The LF
        // entry does not use it; reject any unexpected instrumentation call.
        Instrumentation instrumentation = (Instrumentation) Proxy.newProxyInstance(
                ClassLoader.getSystemClassLoader(), new Class<?>[] { Instrumentation.class },
                (proxy, method, arguments) -> { throw new AssertionError("Unexpected call: " + method); });
        Class<?> bootstrap = Class.forName("livingfellows.bridge.SCBootstrap");
        long before = ((Number) bootstrap.getMethod("getGeneration").invoke(null)).longValue();
        Object invoked = entry.invoke(null, new File(args[1]), "livingfellows.bridge.SCBootstrapAgent", instrumentation);
        long after = ((Number) bootstrap.getMethod("getGeneration").invoke(null)).longValue();
        if (!Boolean.TRUE.equals(invoked) || after != before + 1) {
            throw new AssertionError("PZO did not invoke the real bridge bootstrap");
        }
        System.out.println("SC_PZO_LOADER_SMOKE_PASS metadata=standalone entry=premain bootstrap=started");
    }
}
