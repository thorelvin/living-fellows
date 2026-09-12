// SPDX-License-Identifier: MIT
package zombie.iso;

import java.util.ArrayList;
import zombie.iso.objects.IsoBrokenGlass;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.objects.IsoTree;
import zombie.iso.objects.IsoWindow;
import zombie.iso.objects.IsoWindowFrame;
import zombie.vehicles.BaseVehicle;

public class IsoGridSquare {
    public IsoGridSquare(IsoCell cell, SliceY slice, int x, int y, int z) {}
    public boolean TreatAsSolidFloor() { return false; }
    public IsoCell getCell() { return null; }
    public IsoChunk getChunk() { return null; }
    public int getX() { return 0; }
    public int getY() { return 0; }
    public int getZ() { return 0; }
    public ArrayList<IsoMovingObject> getMovingObjects() { return null; }
    public ArrayList<IsoObject> getSpecialObjects() { return null; }
    public boolean isBlockedTo(IsoGridSquare other) { return false; }
    public boolean isSomethingTo(IsoGridSquare other) { return false; }
    public boolean isFree(boolean ignoreMovingObjects) { return false; }
    public boolean isSafeToSpawn() { return false; }
    public boolean isSolid() { return false; }
    public boolean isSolidTrans() { return false; }
    public boolean testCollideAdjacent(IsoMovingObject actor, int dx, int dy, int dz) { return false; }
    public boolean testPathFindAdjacent(IsoMovingObject actor, int dx, int dy, int dz) { return false; }
    public boolean HasStairs() { return false; }
    public boolean HasTree() { return false; }
    public IsoTree getTree() { return null; }
    public boolean hasWater() { return false; }
    public boolean haveFire() { return false; }
    public boolean hasSlopedSurface() { return false; }
    public IsoBrokenGlass getBrokenGlass() { return null; }
    public BaseVehicle getVehicleContainer() { return null; }
    public IsoWindow getWindowTo(IsoGridSquare other) { return null; }
    public IsoThumpable getWindowThumpableTo(IsoGridSquare other) { return null; }
    public IsoWindowFrame getWindowFrameTo(IsoGridSquare other) { return null; }
    public IsoObject getDoorTo(IsoGridSquare other) { return null; }
    public IsoObject getGarageDoor(boolean north) { return null; }
    public IsoObject getDoorOrWindow(boolean north) { return null; }
    public boolean isDoorTo(IsoGridSquare other) { return false; }
    public boolean isWindowTo(IsoGridSquare other) { return false; }
    public IsoObject getDoor(boolean north) { return null; }
    public IsoWindow getWindow(boolean north) { return null; }
    public IsoThumpable getThumpableWindow(boolean north) { return null; }
    public IsoWindowFrame getWindowFrame(boolean north) { return null; }
    public IsoThumpable getHoppableThumpableTo(IsoGridSquare other) { return null; }
    public IsoObject getHoppableTo(IsoGridSquare other) { return null; }
    public IsoObject getWallHoppableTo(IsoGridSquare other) { return null; }
    public boolean isHoppableTo(IsoGridSquare other) { return false; }
    public boolean isPlayerAbleToHopWallTo(IsoDirections direction, IsoGridSquare other) { return false; }
}
