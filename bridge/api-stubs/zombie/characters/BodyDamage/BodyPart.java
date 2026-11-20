// SPDX-License-Identifier: MIT
package zombie.characters.BodyDamage;

public class BodyPart {
    public boolean bleeding() { return false; }
    public float getBleedingTime() { return 0.0f; }
    public boolean bitten() { return false; }
    public float getBiteTime() { return 0.0f; }
    public boolean isInfectedWound() { return false; }
    public boolean bandaged() { return false; }
    public boolean isBandageDirty() { return false; }
    public boolean scratched() { return false; }
    public float getScratchTime() { return 0.0f; }
    public boolean isCut() { return false; }
    public float getCutTime() { return 0.0f; }
    public boolean deepWounded() { return false; }
    public float getDeepWoundTime() { return 0.0f; }
    public float getBurnTime() { return 0.0f; }
    public float getFractureTime() { return 0.0f; }
    public boolean haveBullet() { return false; }
    public boolean haveGlass() { return false; }
    public boolean stitched() { return false; }
    public float getStitchTime() { return 0.0f; }
    public boolean isSplint() { return false; }
    public float getSplintFactor() { return 0.0f; }
    public BodyPartType getType() { return null; }
}
