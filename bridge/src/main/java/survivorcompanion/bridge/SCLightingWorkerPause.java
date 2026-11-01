// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Quiesces the worker without destroying any native lighting/world state. */
final class SCLightingWorkerPause {
    interface Lease extends AutoCloseable { @Override void close(); }
    interface Api {
        Thread worker();
        boolean stopping();
        void stopping(boolean value);
        void restart(Thread previous);
    }
    private static final Lease NOOP = () -> {};

    private SCLightingWorkerPause() {}

    static Lease pause() { return pause(new EngineApi(), 1000); }

    static Lease pause(Api api, long timeoutMillis) {
        if (timeoutMillis < 1 || timeoutMillis > 1000) {
            throw new IllegalArgumentException("lighting pause needs a bounded positive timeout");
        }
        Thread worker = api.worker();
        if (worker == null || !worker.isAlive()) return NOOP;
        if (worker == Thread.currentThread() || api.stopping()) {
            throw new IllegalStateException("lighting worker is already stopping or owns this call");
        }
        api.stopping(true);
        try {
            worker.join(timeoutMillis);
        } catch (InterruptedException failure) {
            if (worker.isAlive()) api.stopping(false);
            else api.restart(worker);
            Thread.currentThread().interrupt();
            throw new IllegalStateException("lighting worker pause interrupted", failure);
        }
        if (worker.isAlive()) {
            api.stopping(false);
            throw new IllegalStateException("lighting worker did not quiesce before resize");
        }
        return new Lease() {
            private boolean closed;
            public void close() {
                if (closed) return;
                closed = true;
                api.restart(worker);
            }
        };
    }

    private static final class EngineApi implements Api {
        final Object owner;
        final Field thread, finished;
        final Method create;
        EngineApi() {
            try {
                Class<?> type = Class.forName("zombie.iso.LightingThread");
                owner = type.getField("instance").get(null);
                thread = type.getField("lightingThread");
                finished = type.getField("finished");
                create = type.getMethod("create");
            } catch (ReflectiveOperationException failure) {
                throw new IllegalStateException("lighting worker lifecycle unavailable", failure);
            }
        }
        public Thread worker() {
            try { return (Thread) thread.get(owner); }
            catch (IllegalAccessException failure) { throw unavailable(failure); }
        }
        public boolean stopping() {
            try { return finished.getBoolean(owner); }
            catch (IllegalAccessException failure) { throw unavailable(failure); }
        }
        public void stopping(boolean value) {
            try { finished.setBoolean(owner, value); }
            catch (IllegalAccessException failure) { throw unavailable(failure); }
        }
        public void restart(Thread previous) {
            if (worker() != previous || previous.isAlive() || !stopping()) {
                throw new IllegalStateException("lighting worker ownership changed during resize");
            }
            try { create.invoke(owner); }
            catch (ReflectiveOperationException failure) { throw unavailable(failure); }
        }
        private IllegalStateException unavailable(Exception failure) {
            return new IllegalStateException("lighting worker lifecycle failed", failure);
        }
    }
}
