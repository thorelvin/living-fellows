// SPDX-License-Identifier: MIT
package zombie.pathfind;

import zombie.iso.IsoMovingObject;

public final class PolygonalMap2 {
    public static final PolygonalMap2 instance = new PolygonalMap2();

    public boolean lineClearCollide(float fromX, float fromY, float toX, float toY,
            int z, IsoMovingObject ignoreVehicle, boolean ignoreDoors,
            boolean closeToWalls) {
        return false;
    }
}
