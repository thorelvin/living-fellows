// SPDX-License-Identifier: MIT
package zombie.Lua;

import java.util.ArrayList;
import java.util.HashMap;

/** Compile-only API surface for the generic character-death event. */
public final class LuaEventManager {
    private LuaEventManager() {}

    public static void getEvents(ArrayList<Event> eventList, HashMap<String, Event> eventMap) {}
    public static void triggerEvent(String event, Object argument) {}
}
