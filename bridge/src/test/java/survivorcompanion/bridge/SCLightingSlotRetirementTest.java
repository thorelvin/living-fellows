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

    private static final class FakeWorker implements SCLightingSlotRetirement.Worker {
        final ArrayList<String> calls;
        boolean fail;
        FakeWorker(ArrayList<String> calls) { this.calls = calls; }
        public SCLightingWorkerPause.Lease pause() {
            calls.add("pause");
            if (fail) throw new IllegalStateException("worker busy");
            return () -> calls.add("resume");
        }
    }

    private static void workerLifecycle() throws Exception {
        java.util.concurrent.atomic.AtomicBoolean stop = new java.util.concurrent.atomic.AtomicBoolean();
        java.util.concurrent.atomic.AtomicBoolean exit = new java.util.concurrent.atomic.AtomicBoolean();
        Thread worker = new Thread(() -> {
            while (!stop.get() && !exit.get()) Thread.onSpinWait();
        }, "lighting-pause-test");
        int[] restarted = { 0 };
        SCLightingWorkerPause.Api api = new SCLightingWorkerPause.Api() {
            public Thread worker() { return worker; }
            public boolean stopping() { return stop.get(); }
            public void stopping(boolean value) { stop.set(value); }
            public void restart(Thread previous) {
                require(previous == worker && !worker.isAlive(), "restart must own the stopped worker");
                restarted[0]++;
                stop.set(false);
            }
        };
        worker.start();
        try {
            SCLightingWorkerPause.Lease lease = SCLightingWorkerPause.pause(api, 1000);
            require(!worker.isAlive() && restarted[0] == 0, "mutation began before worker termination");
            lease.close(); lease.close();
            require(restarted[0] == 1 && !stop.get(), "worker lease did not restart exactly once");
        } finally { exit.set(true); worker.join(1000); }

        stop.set(false); exit.set(false);
        Thread blocked = new Thread(() -> { while (!exit.get()) Thread.onSpinWait(); }, "lighting-busy-test");
        SCLightingWorkerPause.Api busy = new SCLightingWorkerPause.Api() {
            public Thread worker() { return blocked; }
            public boolean stopping() { return stop.get(); }
            public void stopping(boolean value) { stop.set(value); }
            public void restart(Thread previous) { throw new AssertionError("live worker was replaced"); }
        };
        blocked.start();
        try {
            boolean refused = false;
            try { SCLightingWorkerPause.pause(busy, 10); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && blocked.isAlive() && !stop.get(), "busy worker was mutated or left stopping");
            Thread.currentThread().interrupt();
            refused = false;
            try { SCLightingWorkerPause.pause(busy, 10); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && Thread.interrupted() && !stop.get(), "interruption did not preserve caller/worker state");
        } finally { exit.set(true); blocked.join(1000); }
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
            api = new FakeApi();
            FakeWorker worker = new FakeWorker(api.calls);
            require(SCLightingSlotRetirement.resize(1500, 840, 19, api, worker)
                    && api.calls.equals(java.util.List.of("pause", "begin:1:1500:840:19:19", "end", "resume")),
                    "rejoining must allocate only the secondary state while its worker is paused");
            api = new FakeApi(); api.failBegin = true; worker = new FakeWorker(api.calls);
            refused = false;
            try { SCLightingSlotRetirement.resize(0, 0, 0, api, worker); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.equals(java.util.List.of("pause", "begin:1:0:0:0:0", "resume")),
                    "failed allocation did not resume worker or ended an unopened context");
            api = new FakeApi(); api.failEnd = true; worker = new FakeWorker(api.calls);
            refused = false;
            try { SCLightingSlotRetirement.resize(0, 0, 0, api, worker); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.equals(java.util.List.of("pause", "begin:1:0:0:0:0", "end", "resume")),
                    "failed submission did not resume worker exactly once");
            api = new FakeApi(); worker = new FakeWorker(api.calls); worker.fail = true;
            refused = false;
            try { SCLightingSlotRetirement.resize(0, 0, 0, api, worker); }
            catch (IllegalStateException expected) { refused = true; }
            require(refused && api.calls.equals(java.util.List.of("pause")), "busy worker allowed native mutation");
            workerLifecycle();
            Class<?> lighting = Class.forName("zombie.iso.LightingJNI");
            require(lighting.getField("init").getType() == boolean.class,
                    "native initialized flag signature changed");
            lighting.getMethod("stateBeginUpdate", int.class, int.class, int.class, int.class, int.class);
            lighting.getMethod("stateEndUpdate");
            Class<?> map = Class.forName("zombie.iso.IsoChunkMap");
            map.getMethod("getWorldXMin");
            map.getMethod("getWorldYMin");
            map.getField("chunkGridWidth");
            Class<?> lightingThread = Class.forName("zombie.iso.LightingThread");
            lightingThread.getField("instance"); lightingThread.getField("lightingThread");
            lightingThread.getField("finished"); lightingThread.getMethod("create");
            System.out.println("LIGHTING_SLOT_RETIREMENT_PASS offline=true thread=true owned-slot=1 balanced=true failure=true worker-quiescent=true timeout=true interrupted=true native-api=true");
        } finally {
            MainThread.mainThread = previous;
        }
    }
}
