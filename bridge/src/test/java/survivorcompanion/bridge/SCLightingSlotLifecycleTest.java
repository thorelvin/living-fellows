// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.iso.LightingJNI;
import zombie.MainThread;

/** Original protocol probe; drives the installed native library in its own JVM only. */
public final class SCLightingSlotLifecycleTest {
    private static final int PRIMARY_X = 1500, PRIMARY_Y = 840;
    private static final int SECONDARY_X = 1520, SECONDARY_Y = 850;
    private static int checks;
    private static void require(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }
    private static void geometry(int cx, int cy) {
        LightingJNI.chunkBeginUpdate(cx, cy, 32, 32);
        LightingJNI.chunkLevelBeginUpdate(32);
        for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) {
            LightingJNI.squareBeginUpdate(x, y, 32);
            LightingJNI.squareSet(255, true, false, false, 0, -1L, -1L, 0, true);
            LightingJNI.squareSetLightTransmission(
                    Float.MAX_VALUE, 0, 0, 0, 0,
                    Float.MAX_VALUE, 0, 0, 0, 0,
                    Float.MAX_VALUE, 0, 0, 0, 0,
                    Float.MAX_VALUE, 0, 0, 0, 0);
            LightingJNI.squareEndUpdate();
        }
        LightingJNI.chunkLevelEndUpdate();
        LightingJNI.chunkEndUpdate();
    }
    private static void submit(int slot, boolean first, int position) {
        require(slot == 0 || slot == 1, "probe may submit only its own native states");
        int cx = slot == 0 ? PRIMARY_X : SECONDARY_X;
        int cy = slot == 0 ? PRIMARY_Y : SECONDARY_Y;
        int x = 2 + position % 4, y = 2 + (position / 4) % 4;
        LightingJNI.stateBeginUpdate(slot, cx, cy, 1, 1);
        try {
            LightingJNI.playerSet(cx * 8 + x + .5f, cy * 8 + y + .5f, 32,
                    1, 0, false, false, false, false, 0, 2, 1);
            LightingJNI.stateEndFrame(1, 1, 1, 1, 0, 30, 30, true, 100, 0);
            if (first) geometry(cx, cy);
        } finally {
            LightingJNI.stateEndUpdate();
        }
    }
    // Same barrier as LightingThread.runInner; never compute past WaitingForMain.
    private static boolean pump() throws InterruptedException {
        long until = System.nanoTime() + 2_000_000_000L;
        while (!LightingJNI.WaitingForMain() && System.nanoTime() < until) {
            LightingJNI.DoLightingUpdateNew(System.nanoTime(), true);
            Thread.sleep(1);
        }
        return LightingJNI.WaitingForMain();
    }
    private static void frames(int count, boolean secondary, int offset) throws Exception {
        for (int index = 0; index < count; index++) {
            submit(0, false, index + offset);
            if (secondary) submit(1, false, index + offset);
            require(pump(), "native worker never produced a completed result");
        }
    }
    private static void describe(String stage) {
        System.out.println(stage + " counter0=" + LightingJNI.stateUpdateCounter(0)
                + " counter1=" + LightingJNI.stateUpdateCounter(1)
                + " waiting=" + LightingJNI.WaitingForMain());
    }
    private static void retireSecondary() {
        require(SCLightingSlotRetirement.retire(SECONDARY_X, SECONDARY_Y),
                "production helper skipped initialized native secondary state");
    }
    public static void main(String[] args) throws Exception {
        if (!System.getProperty("os.name", "").startsWith("Windows")
                || !java.nio.file.Files.isRegularFile(java.nio.file.Path.of("Lighting64.dll"))) {
            System.out.println("LIGHTING_SLOT_LIFECYCLE_SKIP native-library-unavailable");
            return;
        }
        Thread previousMain = MainThread.mainThread;
        MainThread.mainThread = Thread.currentThread();
        long deadline = System.nanoTime() + 20_000_000_000L;
        Thread watchdog = new Thread(() -> {
            while (System.nanoTime() < deadline) {
                try { Thread.sleep(50); } catch (InterruptedException ignored) { return; }
            }
            System.err.println("PROBE_TIMEOUT");
            Runtime.getRuntime().halt(124);
        }, "isolated-lighting-probe-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();
        LightingJNI.init();
        try {
            submit(0, true, 0);
            submit(1, true, 0);
            require(pump(), "initial two-slot compute failed");
            frames(20, true, 0);
            describe("joined");
            require(LightingJNI.stateUpdateCounter(0) > 5
                    && LightingJNI.stateUpdateCounter(1) > 5, "both states must genuinely advance");
            frames(6, false, 20);
            int frozen = LightingJNI.stateUpdateCounter(0);
            frames(10, false, 26);
            describe("dropped_secondary_without_retirement");
            require(LightingJNI.stateUpdateCounter(0) == frozen,
                    "negative control must reproduce the stale secondary barrier");
            submit(1, false, 30);
            frames(6, false, 36);
            frozen = LightingJNI.stateUpdateCounter(0);
            frames(10, false, 42);
            describe("one_time_old_size_drain");
            require(LightingJNI.stateUpdateCounter(0) == frozen,
                    "one-time drain should restall when secondary publishes another result");
            retireSecondary();
            describe("retired_zero_size");
            int before = LightingJNI.stateUpdateCounter(0);
            frames(20, false, 50);
            describe("solo_after_retirement");
            require(LightingJNI.stateUpdateCounter(0) > before + 10,
                    "zero-size retirement must keep primary computation advancing");
            for (int trip = 0; trip < 5; trip++) {
                submit(1, true, trip);
                frames(8, true, trip);
                int joined = LightingJNI.stateUpdateCounter(0);
                retireSecondary();
                frames(8, false, trip);
                require(LightingJNI.stateUpdateCounter(0) > joined + 3,
                        "repeat join/close stalled the primary native state");
                describe("repeat_join_close_" + trip);
            }
            for (int position = 0; position < 16; position++) {
                int previous = LightingJNI.stateUpdateCounter(0);
                for (int settle = 0; settle < 4; settle++) {
                    submit(0, false, position);
                    require(pump(), "primary square visibility compute did not finish");
                }
                int x = PRIMARY_X * 8 + 2 + position % 4;
                int y = PRIMARY_Y * 8 + 2 + position / 4;
                require(LightingJNI.stateUpdateCounter(0) > previous,
                        "primary tile movement did not advance native lighting");
                require(LightingJNI.getCanSee(0, x, y, 32)
                                && LightingJNI.getCouldSee(0, x, y, 32),
                        "primary own square lost genuine native sight at " + x + "," + y);
            }
            describe("primary_all_16_positions_visible");
            System.out.println("LIGHTING_SLOT_LIFECYCLE_PASS checks=" + checks);
        } finally {
            LightingJNI.destroy();
            MainThread.mainThread = previousMain;
        }
    }
}
