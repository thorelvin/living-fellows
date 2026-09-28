// SPDX-License-Identifier: MIT
package zombie.characters.BodyDamage;

public class BodyPart {
    public boolean bleeding() { return false; }
    public float getBleedingTime() { return 0.0f; }
    public boolean bitten() { return false; }
    public boolean isInfectedWound() { return false; }
    public boolean bandaged() { return false; }
    public boolean isBandageDirty() { return false; }
    public boolean scratched() { return false; }
    public boolean isCut() { return false; }
    public boolean deepWounded() { return false; }
    public float getBurnTime() { return 0.0f; }
    public float getFractureTime() { return 0.0f; }
    public boolean haveBullet() { return false; }
    public boolean haveGlass() { return false; }
    public BodyPartType getType() { return null; }
}
