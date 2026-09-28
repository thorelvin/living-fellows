// SPDX-License-Identifier: MIT
package zombie.Lua;

import java.util.ArrayList;
import se.krka.kahlua.vm.LuaClosure;

public final class Event {
    public final ArrayList<LuaClosure> callbacks = new ArrayList<>();
}
