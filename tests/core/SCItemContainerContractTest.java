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
        Method add = container.getMethod("AddItem", item);
        Method remove = container.getMethod("Remove", item);
        require(item.isAssignableFrom(add.getReturnType()),
                "ItemContainer.AddItem(InventoryItem) no longer returns the transferred item");
        require(remove.getReturnType() == void.class,
                "ItemContainer.Remove(InventoryItem) return contract changed");
        System.out.println("ITEM_CONTAINER_CONTRACT_PASS add=" + add.getReturnType().getName()
                + " remove=" + remove.getReturnType().getName());
    }
}
