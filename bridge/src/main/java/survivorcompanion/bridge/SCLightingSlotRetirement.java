// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.MainThread;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunkMap;
import zombie.iso.LightingJNI;

/** Retires only LF's released second lighting state without resetting live lights. */
final class SCLightingSlotRetirement {
    interface Api {
        boolean initialized();
        void begin(int slot, int x, int y, int width, int height);
        void end();
    }
    interface Worker { SCLightingWorkerPause.Lease pause(); }
    private static final Worker WORKER = SCLightingWorkerPause::pause;

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
        return resize(originX, originY, 0, api, WORKER);
    }

    static boolean prepare(int originX, int originY, int width) {
        return resize(originX, originY, width, NATIVE, WORKER);
    }

    static boolean prepare(IsoCell cell) {
        if (!NATIVE.initialized()) return false;
        IsoChunkMap primaryMap = cell == null ? null : cell.getChunkMap(0);
        if (primaryMap == null) throw new IllegalStateException("primary lighting map is unavailable");
        return prepare(primaryMap.getWorldXMin(), primaryMap.getWorldYMin(), IsoChunkMap.chunkGridWidth);
    }

    static boolean resize(int originX, int originY, int width, Api api, Worker worker) {
        if (!api.initialized()) return false;
        if (Thread.currentThread() != MainThread.mainThread) {
            throw new IllegalStateException("lighting retirement requires the main thread");
        }
        if (width < 0 || width > 128) throw new IllegalArgumentException("invalid lighting grid width");
        // An allocated result-ready secondary state otherwise keeps the native
        // worker waiting forever after Java's player count drops to one. A
        // dimension change replaces just that state; an empty update leaves the
        // replacement inactive. Sending a player, frame or chunk would reactivate it.
        // Resizing while DoLightingUpdateNew uses the previous state can crash
        // Lighting64.dll. Pause on both retirement AND reallocation before the
        // next co-op join. Keep primary lights, rooms and world caches intact.
        try (SCLightingWorkerPause.Lease ignored = worker.pause()) {
            boolean begun = false;
            try {
                api.begin(1, originX, originY, width, width);
                begun = true;
            } finally {
                if (begun) api.end();
            }
        }
        return true;
    }
}
