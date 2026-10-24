// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.function.LongSupplier;

/** Optional read-only mode flag. Viewpoint is never a compile-time dependency. */
final class SCViewpointCompatibility {
    private static final long RETRY_NANOS = 1_000_000_000L;
    private static final Probe PROBE = new Probe(SCViewpointCompatibility::resolve, System::nanoTime);

    @FunctionalInterface
    interface Resolver {
        Field resolve() throws ReflectiveOperationException;
    }

    static final class Probe {
        private final Resolver resolver;
        private final LongSupplier clock;
        private Field enabled;
        private long retryAt;
        private boolean waiting;

        Probe(Resolver resolver, LongSupplier clock) {
            this.resolver = resolver;
            this.clock = clock;
        }

        synchronized boolean active() {
            long now = clock.getAsLong();
            if (enabled == null && waiting && now - retryAt < 0) return false;
            try {
                if (enabled == null) {
                    Field field = resolver.resolve();
                    if (field.getType() != boolean.class || !Modifier.isStatic(field.getModifiers())
                            || !Modifier.isPublic(field.getModifiers())) {
                        waiting = true;
                        retryAt = now + RETRY_NANOS;
                        return false;
                    }
                    enabled = field;
                    waiting = false;
                }
                // Cache only the descriptor; camera-mode toggles must be live.
                return enabled.getBoolean(null);
            } catch (ReflectiveOperationException | LinkageError | RuntimeException unavailable) {
                enabled = null;
                waiting = true;
                retryAt = now + RETRY_NANOS;
                return false;
            }
        }
    }

    private SCViewpointCompatibility() {}

    static boolean active() { return PROBE.active(); }

    private static Field resolve() throws ReflectiveOperationException {
        ClassLoader primary = SCBridge.class.getClassLoader();
        try {
            return Class.forName("viewpoint.core.View", false, primary).getField("enabled");
        } catch (ClassNotFoundException missing) {
            ClassLoader context = Thread.currentThread().getContextClassLoader();
            if (context == null || context == primary) throw missing;
            return Class.forName("viewpoint.core.View", false, context).getField("enabled");
        }
    }
}
