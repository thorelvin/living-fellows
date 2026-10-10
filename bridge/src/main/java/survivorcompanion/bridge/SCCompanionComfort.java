// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.characters.BodyDamage.BodyDamage;

/** Per-companion controls for ordinary colds and native cough/sneeze timing. */
final class SCCompanionComfort {
    static final long NORMAL_SYMPTOM_GAP_NANOS = 60_000_000_000L;
    static final long RARE_SYMPTOM_GAP_NANOS = 300_000_000_000L;
    private static final float GUARDED_NATIVE_TIMER = 1_000_000_000.0f;

    private static final class Defaults {
        final String symptomMode;
        final boolean ordinaryColdsEnabled;

        Defaults(String symptomMode, boolean ordinaryColdsEnabled) {
            this.symptomMode = symptomMode;
            this.ordinaryColdsEnabled = ordinaryColdsEnabled;
        }
    }

    // Saved Mod Options load before spawn requests. One immutable snapshot makes
    // each new or restored companion inherit both choices before its first tick.
    private static volatile Defaults defaults = new Defaults("normal", true);

    private String symptomMode = "normal";
    private boolean ordinaryColdsEnabled = true;
    private long lastSymptomNanos = Long.MIN_VALUE;
    private int activeBeforeUpdate;
    private float suspendedNativeTimer = Float.NaN;

    static void setDefaults(String mode, boolean ordinaryColdsEnabled) {
        defaults = new Defaults(normalizeSymptomMode(mode), ordinaryColdsEnabled);
    }

    void applyDefaults(BodyDamage body) {
        Defaults current = defaults;
        setSymptomMode(current.symptomMode, body);
        setOrdinaryColdsEnabled(current.ordinaryColdsEnabled, body);
    }

    static String normalizeSymptomMode(String mode) {
        return "rare".equals(mode) || "off".equals(mode) ? mode : "normal";
    }

    static long symptomGapNanos(String mode) {
        return "rare".equals(mode) ? RARE_SYMPTOM_GAP_NANOS : NORMAL_SYMPTOM_GAP_NANOS;
    }

    static boolean symptomAllowed(String mode, long lastNanos, long nowNanos) {
        if ("off".equals(mode)) return false;
        return lastNanos == Long.MIN_VALUE
                || nowNanos - lastNanos >= symptomGapNanos(mode);
    }

    void setSymptomMode(String mode, BodyDamage body) {
        symptomMode = normalizeSymptomMode(mode);
        if ("off".equals(symptomMode)) {
            clearActiveSymptom(body);
            suspendNativeTimer(body);
        }
    }

    void setOrdinaryColdsEnabled(boolean enabled, BodyDamage body) {
        ordinaryColdsEnabled = enabled;
        if (!enabled) clearOrdinaryCold(body);
    }

    boolean canScriptedSymptom() {
        return symptomAllowed(symptomMode, lastSymptomNanos, System.nanoTime());
    }

    boolean noteScriptedSymptom() {
        long now = System.nanoTime();
        if (!symptomAllowed(symptomMode, lastSymptomNanos, now)) return false;
        lastSymptomNanos = now;
        return true;
    }

    void beforeUpdate(BodyDamage body) {
        if (body == null) return;
        long now = System.nanoTime();
        if (!ordinaryColdsEnabled) clearOrdinaryCold(body);
        activeBeforeUpdate = body.getSneezeCoughActive();
        if (activeBeforeUpdate > 0 && lastSymptomNanos == Long.MIN_VALUE) {
            lastSymptomNanos = now;
        }
        if ("off".equals(symptomMode)) {
            clearActiveSymptom(body);
            activeBeforeUpdate = 0;
        }
        if (!symptomAllowed(symptomMode, lastSymptomNanos, now)) {
            // Build 42 decrements once per update for a cold, and by game-world
            // seconds for smokers. Hold the native timer across either rate.
            suspendNativeTimer(body);
        } else {
            resumeNativeTimer(body);
        }
    }

    void afterUpdate(BodyDamage body) {
        if (body == null) return;
        if (!ordinaryColdsEnabled) clearOrdinaryCold(body);
        if ("off".equals(symptomMode)) {
            clearActiveSymptom(body);
            suspendNativeTimer(body);
            return;
        }
        if (activeBeforeUpdate <= 0 && body.getSneezeCoughActive() > 0) {
            lastSymptomNanos = System.nanoTime();
            suspendNativeTimer(body);
        }
    }

    static void clearOrdinaryCold(BodyDamage body) {
        if (body == null) return;
        boolean hadCold = body.isHasACold();
        if (body.getCatchACold() != 0.0f) body.setCatchACold(0.0f);
        if (hadCold) body.setHasACold(false);
        if (body.getColdStrength() != 0.0f) body.setColdStrength(0.0f);
        if (hadCold) clearActiveSymptom(body);
    }

    private static void clearActiveSymptom(BodyDamage body) {
        if (body == null) return;
        body.setSneezeCoughActive(0);
        body.setSneezeCoughTime(0);
    }

    private void suspendNativeTimer(BodyDamage body) {
        if (body == null) return;
        if (Float.isNaN(suspendedNativeTimer)) {
            suspendedNativeTimer = body.getTimeToSneezeOrCough();
        }
        body.setTimeToSneezeOrCough(GUARDED_NATIVE_TIMER);
    }

    private void resumeNativeTimer(BodyDamage body) {
        if (body == null || Float.isNaN(suspendedNativeTimer)) return;
        body.setTimeToSneezeOrCough(suspendedNativeTimer);
        suspendedNativeTimer = Float.NaN;
    }
}
