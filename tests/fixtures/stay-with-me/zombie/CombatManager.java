// SPDX-License-Identifier: MIT
package zombie;

import java.util.ArrayList;

/** Pool contract for the focused native-boundary test, never a game replacement. */
public final class CombatManager {
    private static final CombatManager INSTANCE = new CombatManager();
    public static CombatManager getInstance() { return INSTANCE; }
    public final Pool hitInfoPool = new Pool();
    public static final class Pool {
        public final ArrayList<Object> released = new ArrayList<>();
        public void release(Object value) { released.add(value); }
    }
}
