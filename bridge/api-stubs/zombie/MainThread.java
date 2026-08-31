// SPDX-License-Identifier: MIT
package zombie;

import java.util.concurrent.ConcurrentLinkedQueue;

/** Compile-only API surface for deferring native creation past a Lua call. */
public final class MainThread {
    private static final ConcurrentLinkedQueue<Runnable> QUEUE = new ConcurrentLinkedQueue<>();
    public static Thread mainThread = Thread.currentThread();

    private MainThread() {}

    public static void queueInvokeOnMainThread(Runnable task) { QUEUE.add(task); }
    public static boolean isRunning() { return true; }
    public static int queuedForTests() { return QUEUE.size(); }
    public static void runNextForTests() {
        Runnable task = QUEUE.poll();
        if (task != null) task.run();
    }
}
