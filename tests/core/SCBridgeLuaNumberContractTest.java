// SPDX-License-Identifier: MIT

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.LinkedHashMap;
import java.util.Map;

import se.krka.kahlua.vm.KahluaTable;
import survivorcompanion.bridge.SCBridge;

/** Verifies that direct Kahlua raw writes never publish boxed Java numbers. */
public final class SCBridgeLuaNumberContractTest {
    private SCBridgeLuaNumberContractTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static KahluaTable recordingTable(Map<Object, Object> values) {
        InvocationHandler handler = (proxy, method, arguments) -> {
            if (method.getName().equals("rawset")) {
                values.put(arguments[0], arguments[1]);
                return null;
            }
            if (method.getName().equals("wipe")) {
                values.clear();
                return null;
            }
            if (method.getName().equals("toString")) return "recording-kahlua-table";
            if (method.getName().equals("hashCode")) return System.identityHashCode(proxy);
            if (method.getName().equals("equals")) return proxy == arguments[0];
            Class<?> result = method.getReturnType();
            if (!result.isPrimitive()) return null;
            if (result == boolean.class) return false;
            if (result == char.class) return '\0';
            return 0;
        };
        return (KahluaTable) Proxy.newProxyInstance(
                KahluaTable.class.getClassLoader(), new Class<?>[] { KahluaTable.class }, handler);
    }

    public static void main(String[] args) throws Exception {
        Map<Object, Object> values = new LinkedHashMap<>();
        KahluaTable table = recordingTable(values);
        Method stringPut = SCBridge.class.getDeclaredMethod(
                "put", KahluaTable.class, String.class, Object.class);
        Method integerPut = SCBridge.class.getDeclaredMethod(
                "put", KahluaTable.class, int.class, Object.class);
        stringPut.setAccessible(true);
        integerPut.setAccessible(true);

        stringPut.invoke(null, table, "condition", Integer.valueOf(7));
        stringPut.invoke(null, table, "wetness", Float.valueOf(1.25f));
        integerPut.invoke(null, table, 2, Long.valueOf(19L));
        integerPut.invoke(null, table, 3, Float.valueOf(4.5f));
        stringPut.invoke(null, table, "favorite", Boolean.TRUE);
        stringPut.invoke(null, table, "type", "Base.Axe");

        require(values.get("condition") instanceof Double
                        && ((Double) values.get("condition")).doubleValue() == 7.0,
                "integer item fact was not normalized to a Lua Double");
        require(values.get("wetness") instanceof Double
                        && ((Double) values.get("wetness")).doubleValue() == 1.25,
                "float item fact was not normalized to a Lua Double");
        require(values.get(Integer.valueOf(2)) instanceof Double
                        && ((Double) values.get(Integer.valueOf(2))).doubleValue() == 19.0,
                "integer-key snapshot number was not normalized to a Lua Double");
        require(values.get(Integer.valueOf(3)) instanceof Double
                        && ((Double) values.get(Integer.valueOf(3))).doubleValue() == 4.5,
                "zombie coordinate was not normalized to a Lua Double");
        require(Boolean.TRUE.equals(values.get("favorite"))
                        && "Base.Axe".equals(values.get("type")),
                "non-numeric Kahlua values changed during normalization");

        System.out.println("SCBridgeLuaNumberContractTest: PASS");
    }
}
