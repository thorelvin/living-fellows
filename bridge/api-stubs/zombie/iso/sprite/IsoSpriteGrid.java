// SPDX-License-Identifier: MIT
package zombie.iso.sprite;

/** Compile-only Project Zomboid API shape; excluded from the bridge JAR. */
public class IsoSpriteGrid {
    public int getWidth() { return 0; }
    public int getHeight() { return 0; }
    public int getSpriteGridPosX(IsoSprite sprite) { return -1; }
    public int getSpriteGridPosY(IsoSprite sprite) { return -1; }
}
