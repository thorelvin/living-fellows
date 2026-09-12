// SPDX-License-Identifier: MIT
package zombie.inventory.types;
import zombie.inventory.InventoryItem;
public class HandWeapon extends InventoryItem {
    public boolean isContainsClip() { return false; }
    public boolean isRoundChambered() { return false; }
    public boolean isJammed() { return false; }
    public String getFireMode() { return null; }
}
