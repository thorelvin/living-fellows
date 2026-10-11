// SPDX-License-Identifier: MIT
package zombie.iso;

import zombie.core.properties.PropertyContainer;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteGrid;

public class IsoObject {
    public IsoGridSquare square;
    public se.krka.kahlua.vm.KahluaTable getModData() { return null; }
    public IsoGridSquare getSquare() { return null; }
    public IsoSprite getSprite() { return null; }
    public IsoSpriteGrid getSpriteGrid() { return null; }
    public PropertyContainer getProperties() { return null; }
    public void setAlphaAndTarget(float alpha) {}
    public float getTargetAlpha(int playerIndex) { return 1.0f; }
    public IsoCell getCell() { return null; }
    public boolean isMovedThumpable() { return false; }
    public boolean isWindow() { return false; }
}
