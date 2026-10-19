// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicBoolean;

import zombie.MainThread;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.SurvivorDesc;
import zombie.iso.IsoCell;

/** Proves the bridge hand-off returns before native main-thread work executes. */
public final class SCDeferredMainThreadQueueTest {
    private SCDeferredMainThreadQueueTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        AtomicBoolean ran = new AtomicBoolean(false);
        Method handoff = SCBridge.class.getDeclaredMethod("queueAfterLua", Runnable.class);
        handoff.setAccessible(true);
        handoff.invoke(null, (Runnable) () -> ran.set(true));

        long deadline = System.nanoTime() + 2_000_000_000L;
        while (MainThread.queuedForTests() == 0 && System.nanoTime() < deadline) {
            Thread.sleep(1L);
        }
        require(MainThread.queuedForTests() == 1,
                "spawn hand-off did not reach the main-thread queue");
        require(!ran.get(), "spawn work executed before the originating call returned");
        MainThread.runNextForTests();
        require(ran.get() && MainThread.queuedForTests() == 0,
                "deferred spawn work did not execute exactly once on queue drain");

        // A hand-off that cannot reach the main-thread queue must release the
        // pending start and report why; otherwise Lua waits on it forever.
        SCNativeCompanion actor = new SCNativeCompanion(new SurvivorDesc(),
                new IsoCell(1, 1), 0, 0, 0);
        BaseAction action = new BaseAction();
        MainThread.failNextQueueForTests(new IllegalStateException("queue closed"));
        actor.StartAction(action);
        deadline = System.nanoTime() + 2_000_000_000L;
        while (actor.isCompanionActionStartPending(action) && System.nanoTime() < deadline) {
            Thread.sleep(1L);
        }
        require(!actor.isCompanionActionStartPending(action),
                "failed action-start hand-off left the start pending");
        require(actor.getCompanionActionStartFailure()
                        .startsWith("native action start queue failed: IllegalStateException"),
                "failed action-start hand-off did not report its cause: "
                        + actor.getCompanionActionStartFailure());
        require(MainThread.queuedForTests() == 0,
                "failed action-start hand-off queued main-thread work");
        System.out.println("DEFERRED_MAIN_THREAD_QUEUE_PASS queued=true inline=false once=true"
                + " failedStartReleased=true");
    }
}
