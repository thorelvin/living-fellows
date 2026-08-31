// SPDX-License-Identifier: MIT
package zombie.pathfind;

import se.krka.kahlua.vm.KahluaTable;

/** Compile-only API surface for the version-pinned locomotion bridge. */
public class PathFindBehavior2 {
    public void cancel() {}
    public boolean shouldBeMoving() { return false; }
    public boolean hasStartedMoving() { return false; }
    public boolean allowTurnAnimation() { return false; }
    public boolean isTurningToObstacle() { return false; }
    public boolean isStrafing() { return false; }
    public boolean isMovingUsingPathFind() { return false; }
    public void pathToNearestTable(KahluaTable locations) {}
}
