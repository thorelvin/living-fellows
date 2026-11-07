// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.instrument.Instrumentation;

/** Starts the bridge without replacing another supported launcher's main class. */
public final class SCBootstrapAgent {
    private SCBootstrapAgent() {}

    public static void premain(String arguments, Instrumentation instrumentation) {
        if (arguments != null && !arguments.isEmpty()) {
            throw new IllegalArgumentException("Living Fellows bootstrap agent takes no arguments");
        }
        SCBootstrap.start();
    }
}
