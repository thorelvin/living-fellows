// SPDX-License-Identifier: MIT

import java.lang.reflect.Method;

/** Version-pinned inventory transfer contract used by companion scavenging. */
public final class SCItemContainerContractTest {
    private SCItemContainerContractTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Class<?> container = Class.forName("zombie.inventory.ItemContainer");
        Class<?> item = Class.forName("zombie.inventory.InventoryItem");
        Class<?> factory = Class.forName("zombie.inventory.InventoryItemFactory");
        Class<?> character = Class.forName("zombie.characters.IsoGameCharacter");
        Method create = factory.getMethod("CreateItem", String.class);
        require(item.isAssignableFrom(create.getReturnType()),
                "InventoryItemFactory.CreateItem(String) no longer returns an inventory item");
        Method add = container.getMethod("AddItem", item);
        Method remove = container.getMethod("Remove", item);
        require(item.isAssignableFrom(add.getReturnType()),
                "ItemContainer.AddItem(InventoryItem) no longer returns the transferred item");
        require(remove.getReturnType() == void.class,
                "ItemContainer.Remove(InventoryItem) return contract changed");
        Method hasRoomFor = container.getMethod("hasRoomFor", character, item);
        require(hasRoomFor.getReturnType() == boolean.class,
                "ItemContainer.hasRoomFor(IsoGameCharacter, InventoryItem) return contract changed");
        System.out.println("ITEM_CONTAINER_CONTRACT_PASS create="
                + create.getReturnType().getName()
                + " add=" + add.getReturnType().getName()
                + " remove=" + remove.getReturnType().getName()
                + " hasRoomFor=" + hasRoomFor.getReturnType().getName());
    }
}
