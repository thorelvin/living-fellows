// SPDX-License-Identifier: MIT
package zombie.Lua;

import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import se.krka.kahlua.vm.KahluaTable;

/** Native-boundary fixture; never packaged in the bridge. */
public final class LuaManager {
    public static KahluaTable env;
    public static Object thread = new Object();
    public static final Caller caller = new Caller();
    public static final class Caller {
        public final Set<Object> owned = Collections.newSetFromMap(new IdentityHashMap<>());
        public boolean fail;
        public int calls;
        public Object[] pcall(Object thread, Object function, Object actor) {
            calls++;
            return fail ? new Object[] { false, "identity callback failed" }
                    : new Object[] { true, owned.contains(actor) };
        }
    }
}
