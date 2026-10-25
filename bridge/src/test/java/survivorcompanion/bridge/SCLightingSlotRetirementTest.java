// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import zombie.MainThread;

public final class SCLightingSlotRetirementTest {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class FakeApi implements SCLightingSlotRetirement.Api {
        final ArrayList<String> calls = new ArrayList<>();
        boolean online = true, failBegin, failEnd;
        public boolean initialized() { return online; }
        public void begin(int slot, int x, int y, int width, int height) {
            calls.add("begin:" + slot + ":" + x + ":" + y + ":" + width + ":" + height);
            if (failBegin) throw new IllegalStateException("begin failed");
        }
        public void end() {
            calls.add("end");
            if (failEnd) throw new IllegalStateException("end failed");
        }
    }

    public static void main(String[] args) throws Exception {
        Thread previous = MainThread.mainThread;
        try {
            FakeApi api = new FakeApi();
            api.online = false;
            MainThread.mainThread = null;
            require(!SCLightingSlotRetirement.retire(1500, 840, api) && api.calls.isEmpty(),
                    "offline cleanup called native lighting or required a game thread");
            api.online = true;
            boolean refused = false;
            try { SCLightingSlotRetirement.retire(1500, 840, api); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.isEmpty(), "wrong thread opened native lighting context");
            MainThread.mainThread = Thread.currentThread();
            require(SCLightingSlotRetirement.retire(1500, 840, api)
                            && api.calls.equals(java.util.List.of("begin:1:1500:840:0:0", "end")),
                    "retirement changed another slot, origin, dimensions or submitted reactivating work");
            api = new FakeApi();
            api.failBegin = true;
            refused = false;
            try { SCLightingSlotRetirement.retire(-8, 15, api); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.equals(java.util.List.of("begin:1:-8:15:0:0")),
                    "failed begin closed an unowned or unopened context");
            api = new FakeApi();
            api.failEnd = true;
            refused = false;
            try { SCLightingSlotRetirement.retire(0, 0, api); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.equals(java.util.List.of("begin:1:0:0:0:0", "end")),
                    "failed end repeated a native transaction or swallowed its failure");
            Class<?> lighting = Class.forName("zombie.iso.LightingJNI");
            require(lighting.getField("init").getType() == boolean.class,
                    "native initialized flag signature changed");
            lighting.getMethod("stateBeginUpdate", int.class, int.class, int.class, int.class, int.class);
            lighting.getMethod("stateEndUpdate");
            Class<?> map = Class.forName("zombie.iso.IsoChunkMap");
            map.getMethod("getWorldXMin");
            map.getMethod("getWorldYMin");
            System.out.println("LIGHTING_SLOT_RETIREMENT_PASS offline=true thread=true owned-slot=1 balanced=true failure=true native-api=true");
        } finally {
            MainThread.mainThread = previous;
        }
    }
}
