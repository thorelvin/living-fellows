// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/** Runtime linkage test. It intentionally uses reflection and no compile-time game dependency. */
public final class SCBridgeLoadTest {
    private SCBridgeLoadTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        Class<?> bridge = Class.forName("survivorcompanion.bridge.SCBridge", true,
                SCBridgeLoadTest.class.getClassLoader());
        String protocol = (String) bridge.getMethod("getProtocol").invoke(null);
        String required = (String) bridge.getMethod("getRequiredGameVersion").invoke(null);
        String detected = (String) bridge.getMethod("getDetectedGameVersion").invoke(null);

        require("42.20.4-sc.1".equals(protocol), "bridge protocol mismatch");
        require("42.20.4".equals(required), "required game version mismatch");
        require("42.20.4".equals(detected), "installed game version mismatch: " + detected);

        var compatibility = bridge.getMethod("checkCompatibility", String.class, boolean.class);
        require("".equals(compatibility.invoke(null, "42.20.4", false)),
                "supported single-player runtime was rejected");
        require(((String) compatibility.invoke(null, "42.20.3", false)).contains("requires Project Zomboid"),
                "version mismatch did not fail closed");
        require(((String) compatibility.invoke(null, "42.20.4", true)).contains("single-player only"),
                "multiplayer did not fail closed");

        require(bridge.getMethod("spawn", Class.forName("zombie.iso.IsoGridSquare"), String.class,
                String.class, boolean.class, String.class).getReturnType().getName()
                        .equals("zombie.characters.IsoSurvivor"),
                "spawn return type is not IsoSurvivor");
        System.out.println("SCBridge load test passed: " + detected + " / " + protocol);
    }
}
