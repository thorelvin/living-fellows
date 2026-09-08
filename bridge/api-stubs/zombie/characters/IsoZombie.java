// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.iso.IsoMovingObject;
import zombie.iso.Vector2;

/** Compile-only Build 42 zombie surface used by the narrow attack-state bridge. */
public class IsoZombie extends IsoGameCharacter {
    public final Vector2 vectorToTarget = new Vector2();
    public IsoMovingObject getTarget() { return null; }
    public void setTargetSeenTime(float seconds) {}
    public float getTargetSeenTime() { return 0; }
    public boolean isFacingTarget() { return false; }
}
