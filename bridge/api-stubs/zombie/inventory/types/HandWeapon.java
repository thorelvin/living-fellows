// SPDX-License-Identifier: MIT
package zombie.inventory.types;
import zombie.inventory.InventoryItem;
public class HandWeapon extends InventoryItem {
    public HandWeapon(String module, String name, String type, String icon) {}
    public boolean isContainsClip() { return false; }
    public boolean isRoundChambered() { return false; }
    public boolean isJammed() { return false; }
    public String getFireMode() { return null; }
}
