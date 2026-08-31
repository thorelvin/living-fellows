// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;

/** Reversible normal-launch wrapper configured through ProjectZomboid64.json. */
public final class SCLauncher {
    private SCLauncher() {}

    public static void main(String[] arguments) throws Throwable {
        if (Arrays.asList(arguments).contains("--sc-bridge-smoke-test")) {
            System.out.println("SC_BRIDGE_LAUNCHER_SMOKE_PASS protocol=" + SCBridge.PROTOCOL);
            return;
        }
        SCBootstrap.start();
        Class<?> mainScreen = Class.forName("zombie.gameStates.MainScreenState");
        Method main = mainScreen.getMethod("main", String[].class);
        try {
            main.invoke(null, (Object) arguments);
        } catch (InvocationTargetException failure) {
            throw failure.getCause();
        }
    }
}
