// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;

/** Verifies the production bootstrap against the real Project Zomboid Kahlua runtime. */
public final class SCNativeBridgeExposureTest {
    private SCNativeBridgeExposureTest() {}

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-native-exposure-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);

        Class<?> bootstrapClass = Class.forName("survivorcompanion.bridge.SCBootstrap");
        bootstrapClass.getMethod("start").invoke(null);
        Thread.sleep(150L);
        require(!(Boolean) bootstrapClass.getMethod("isReady").invoke(null),
                "bootstrap exposed into LuaManager before the game initialized Kahlua");

        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (!(Boolean) bootstrapClass.getMethod("isReady").invoke(null)
                && System.nanoTime() < deadline) {
            Thread.sleep(10L);
        }
        require((Boolean) bootstrapClass.getMethod("isReady").invoke(null),
                "production bootstrap did not expose the bridge: "
                        + bootstrapClass.getMethod("getStatus").invoke(null));

        Object environment = managerClass.getField("env").get(null);
        Object thread = managerClass.getField("thread").get(null);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        String source = "assert(SCBridge ~= nil, 'SCBridge is not exposed')\n"
                + "SC_TEST_PROTOCOL = SCBridge.getProtocol()\n"
                + "SC_TEST_READY = SCBridge.checkReady()\n";
        Object closure = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCNativeBridgeExposureTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);
        Method rawget = tableClass.getMethod("rawget", Object.class);
        require("42.20-isocompanion-5".equals(rawget.invoke(environment, "SC_TEST_PROTOCOL")),
                "Lua received the wrong native bridge protocol");
        String readiness = String.valueOf(rawget.invoke(environment, "SC_TEST_READY"));
        require(SCBridge.isSupportedGameVersion("42.20")
                        && SCBridge.isSupportedGameVersion("42.20.4")
                        && !SCBridge.isSupportedGameVersion("42.19")
                        && !SCBridge.isSupportedGameVersion("42.21"),
                "native bridge release-family gate is too broad or rejects a valid live label");
        require(!readiness.contains("requires Project Zomboid"),
                "live 42.20 label was incorrectly rejected by the version gate: " + readiness);
        require(!readiness.isEmpty(),
                "headless readiness unexpectedly bypassed the local-player isolation gate");
        System.out.println("NATIVE_BRIDGE_EXPOSURE_PASS protocol=true kahlua=true version-family-gate=true local-player-gate=true");
    }
}
