// SPDX-License-Identifier: MIT
package livingfellows.harness;

import java.lang.instrument.Instrumentation;

/** Test-only PZO-loaded helper: advances the disposable world's start gate. */
public final class SCPzoLoadingGateAgent {
    private SCPzoLoadingGateAgent() {}

    public static void premain(String ignored, Instrumentation instrumentation) {
        String marker = System.getProperty("sc.pzo.loadingGateMarker");
        if (marker == null || marker.isBlank()) {
            throw new IllegalStateException("An owned fixture loading-gate marker is required");
        }
        SCLoadingGateAgent.premain(marker, instrumentation);
    }
}
