// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.MainThread;
import zombie.iso.LightingJNI;

/** Retires only LF's released second lighting state without resetting live lights. */
final class SCLightingSlotRetirement {
    interface Api {
        boolean initialized();
        void begin(int slot, int x, int y, int width, int height);
        void end();
    }

    private static final Api NATIVE = new Api() {
        public boolean initialized() { return LightingJNI.init; }
        public void begin(int slot, int x, int y, int width, int height) {
            LightingJNI.stateBeginUpdate(slot, x, y, width, height);
        }
        public void end() { LightingJNI.stateEndUpdate(); }
    };

    private SCLightingSlotRetirement() {}

    static boolean retire(int originX, int originY) {
        return retire(originX, originY, NATIVE);
    }

    static boolean retire(int originX, int originY, Api api) {
        if (!api.initialized()) return false;
        if (Thread.currentThread() != MainThread.mainThread) {
            throw new IllegalStateException("lighting retirement requires the main thread");
        }
        // An allocated result-ready secondary state otherwise keeps the native
        // worker waiting forever after Java's player count drops to one. A
        // dimension change replaces just that state; an empty update leaves the
        // replacement inactive. Sending a player, frame or chunk would reactivate it.
        boolean begun = false;
        try {
            api.begin(1, originX, originY, 0, 0);
            begun = true;
        } finally {
            if (begun) api.end();
        }
        return true;
    }
}
