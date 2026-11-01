// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;

/** Read-only evidence of a round spent by the native collision callback. */
final class SCFirearmShot {
    private static final Method AMMO = weaponMethod("getCurrentAmmoCount");
    private static final Method CHAMBER = weaponMethod("haveChamber");
    private static final Method LOADED = weaponMethod("isRoundChambered");
    private static final Method MANUAL = weaponMethod("isManuallyRemoveSpentRounds");
    private static final Method SPENT = weaponMethod("getSpentRoundCount");
    private static final Method JAMMED = weaponMethod("isJammed");
    private static final Method AIMED = weaponMethod("isAimedFirearm");

    record Snapshot(Object weapon, long liveRounds, boolean jammed) {}

    private SCFirearmShot() {}

    static Snapshot capture(Object weapon) throws ReflectiveOperationException {
        if (weapon == null || !Boolean.TRUE.equals(AIMED.invoke(weapon))) return null;
        long rounds = Math.max(0, ((Number) AMMO.invoke(weapon)).longValue());
        // Revolvers retain spent cartridges; pump guns consume their chamber
        // before the magazine changes. Counting the magazine alone misses both.
        if (Boolean.TRUE.equals(MANUAL.invoke(weapon))) {
            rounds = Math.max(0, rounds - ((Number) SPENT.invoke(weapon)).longValue());
        }
        if (Boolean.TRUE.equals(CHAMBER.invoke(weapon))
                && Boolean.TRUE.equals(LOADED.invoke(weapon))) rounds++;
        return new Snapshot(weapon, rounds, Boolean.TRUE.equals(JAMMED.invoke(weapon)));
    }

    static boolean fired(Snapshot before, Snapshot after, boolean completed, boolean unlimited) {
        return completed && before != null && after != null && before.weapon == after.weapon
                && !before.jammed && (before.liveRounds > 0 || unlimited)
                && (after.liveRounds < before.liveRounds || unlimited);
    }

    private static Method weaponMethod(String name) {
        try {
            return Class.forName("zombie.inventory.types.HandWeapon").getMethod(name);
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }
}
