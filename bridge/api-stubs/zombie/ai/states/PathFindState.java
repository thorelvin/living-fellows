// SPDX-License-Identifier: MIT
package zombie.ai.states;

import zombie.ai.State;

public final class PathFindState extends State {
    private static final PathFindState INSTANCE = new PathFindState();

    public static PathFindState instance() { return INSTANCE; }
}
