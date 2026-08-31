// SPDX-License-Identifier: MIT
package zombie.iso;

public class IsoGridSquare {
    public IsoGridSquare(IsoCell cell, SliceY slice, int x, int y, int z) {}
    public boolean TreatAsSolidFloor() { return false; }
    public IsoCell getCell() { return null; }
    public IsoChunk getChunk() { return null; }
    public int getX() { return 0; }
    public int getY() { return 0; }
    public int getZ() { return 0; }
    public boolean isBlockedTo(IsoGridSquare other) { return false; }
    public boolean isFree(boolean ignoreMovingObjects) { return false; }
    public boolean isSafeToSpawn() { return false; }
    public boolean isSolid() { return false; }
    public boolean isSolidTrans() { return false; }
    public boolean testCollideAdjacent(IsoMovingObject actor, int dx, int dy, int dz) { return false; }
}
