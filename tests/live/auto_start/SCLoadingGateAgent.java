// SPDX-License-Identifier: MIT
// Test-only agent. The live harness loads this into its disposable game process.
// Build 42 polls its own mouse state at the click-to-start gate, so posting a
// desktop/window click from the runner cannot reliably advance an unattended run.
package survivorcompanion.harness;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

public final class SCLoadingGateAgent {
    private SCLoadingGateAgent() {}

    public static void premain(String markerPath, Instrumentation instrumentation) {
        final Path marker = Path.of(markerPath);
        record(marker, "agent_started");
        Thread worker = new Thread(() -> advanceLoadingGate(marker), "SC live loading gate");
        worker.setDaemon(true);
        worker.start();
    }

    private static void advanceLoadingGate(Path marker) {
        try {
            // Let the game create its own main thread and initialize GameWindow.
            Thread.sleep(15_000);
            ClassLoader loader = ClassLoader.getSystemClassLoader();
            Class<?> windowClass = Class.forName("zombie.GameWindow", false, loader);
            Class<?> loadingClass = Class.forName("zombie.gameStates.GameLoadingState", false, loader);
            Field statesField = windowClass.getField("states");
            Field currentField = Class.forName("zombie.gameStates.GameStateMachine", false, loader)
                    .getField("current");
            Field doneField = loadingClass.getDeclaredField("done");
            Field showedField = loadingClass.getDeclaredField("showedClickToSkip");
            Field forceDoneField = loadingClass.getDeclaredField("forceDone");
            doneField.setAccessible(true);
            showedField.setAccessible(true);
            forceDoneField.setAccessible(true);
            long deadline = System.nanoTime() + 600_000_000_000L;
            boolean advanced = false;
            while (System.nanoTime() < deadline) {
                Object states = statesField.get(null);
                Object current = states == null ? null : currentField.get(states);
                if (current != null && loadingClass.isInstance(current)
                        && doneField.getBoolean(null) && showedField.getBoolean(null)) {
                    forceDoneField.setBoolean(current, true);
                    if (!advanced) {
                        record(marker, "gate_advanced");
                        advanced = true;
                    }
                } else if (advanced && current != null && !loadingClass.isInstance(current)) {
                    record(marker, "game_started");
                    return;
                }
                Thread.sleep(50);
            }
            record(marker, advanced ? "gate_did_not_exit" : "gate_not_seen");
        } catch (Throwable failure) {
            record(marker, "agent_failed:" + failure.getClass().getName() + ":" + failure.getMessage());
        }
    }

    private static void record(Path marker, String message) {
        try {
            Files.writeString(marker, message + System.lineSeparator(),
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (Exception ignored) {
            // The game launch and its console remain available for diagnosis.
        }
    }
}
