// SPDX-License-Identifier: MIT
package zombie.inventory.types;
import zombie.inventory.InventoryItem;
public class Food extends InventoryItem {
    public boolean isFrozen() { return false; }
    public float getBaseHunger() { return 0; }
    public float getHungChange() { return 0; }
    public float getThirstChangeUnmodified() { return 0; }
    public float getBoredomChangeUnmodified() { return 0; }
    public float getUnhappyChangeUnmodified() { return 0; }
    public float getCalories() { return 0; }
    public float getCarbohydrates() { return 0; }
    public float getLipids() { return 0; }
    public float getProteins() { return 0; }
    public float getHeat() { return 0; }
    public float getFreezingTime() { return 0; }
    public int getPoisonPower() { return 0; }
    public int getPoisonDetectionLevel() { return 0; }
    public int getUseForPoison() { return 0; }
    public int getLastCookMinute() { return 0; }
    public boolean isCookedInMicrowave() { return false; }
    public boolean isPackaged() { return false; }
    public boolean isbDangerousUncooked() { return false; }
    public boolean isRemoveNegativeEffectOnCooked() { return false; }
}
