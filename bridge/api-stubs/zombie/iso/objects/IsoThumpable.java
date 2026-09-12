// SPDX-License-Identifier: MIT
package zombie.iso.objects;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
import zombie.iso.IsoObject;
public class IsoThumpable extends IsoObject {
    public boolean isBlockAllTheSquare() { return false; }
    public boolean isDoor() { return false; }
    public boolean isCanPassThrough() { return false; }
    public boolean TestCollide(IsoMovingObject actor, IsoGridSquare from, IsoGridSquare to) { return false; }
}
