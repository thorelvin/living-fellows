// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public final class SCViewpointCompatibilityTest {
    public static final class Mode { public static boolean enabled; }
    public static final class WrongType { public static int enabled; }
    public static final class InstanceMode { public boolean enabled; }
    public static final class BrokenMode {
        public static boolean enabled = initialize();
        private static boolean initialize() { throw new IllegalStateException("test initializer"); }
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        AtomicLong clock = new AtomicLong(100);
        AtomicInteger lookups = new AtomicInteger();
        var present = new SCViewpointCompatibility.Probe(() -> {
            lookups.incrementAndGet();
            return Mode.class.getField("enabled");
        }, clock::get);
        require(!present.active(), "isometric mode suppressed labels");
        Mode.enabled = true;
        require(present.active(), "3D toggle did not become visible immediately");
        Mode.enabled = false;
        require(!present.active() && lookups.get() == 1, "descriptor caching froze the camera mode");

        AtomicInteger attempts = new AtomicInteger();
        var late = new SCViewpointCompatibility.Probe(() -> {
            if (attempts.incrementAndGet() == 1) throw new ClassNotFoundException("optional mod");
            return Mode.class.getField("enabled");
        }, clock::get);
        for (int index = 0; index < 120; index++) require(!late.active(), "absent mod became active");
        require(attempts.get() == 1, "absent optional mod was probed every frame");
        clock.addAndGet(1_000_000_000L);
        Mode.enabled = true;
        require(late.active() && attempts.get() == 2, "late optional mod never recovered");

        var wrong = new SCViewpointCompatibility.Probe(() -> WrongType.class.getField("enabled"), clock::get);
        var instance = new SCViewpointCompatibility.Probe(() -> InstanceMode.class.getField("enabled"), clock::get);
        var broken = new SCViewpointCompatibility.Probe(() -> BrokenMode.class.getField("enabled"), clock::get);
        require(!wrong.active() && !instance.active() && !broken.active(), "malformed optional state escaped");
        require(!broken.active(), "broken initialization was retried inside cooldown");
        Mode.enabled = false;
        System.out.println("VIEWPOINT_COMPATIBILITY_PASS toggle=true optional=true bounded=true recovery=true");
    }
}
