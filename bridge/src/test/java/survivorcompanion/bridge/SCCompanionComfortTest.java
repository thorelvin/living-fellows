// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.characters.BodyDamage.BodyDamage;

/** Deterministic cold and symptom policy checks against the bridge API stub. */
public final class SCCompanionComfortTest {
    private static final class Body extends BodyDamage {
        float catchCold;
        float strength;
        float timer;
        float knoxLevel = 72.0f;
        boolean hasCold;
        int active;
        int activeTime;

        Body() { super(null); }
        @Override public float getCatchACold() { return catchCold; }
        @Override public void setCatchACold(float value) { catchCold = value; }
        @Override public boolean isHasACold() { return hasCold; }
        @Override public void setHasACold(boolean value) { hasCold = value; }
        @Override public float getColdStrength() { return strength; }
        @Override public void setColdStrength(float value) { strength = value; }
        @Override public float getTimeToSneezeOrCough() { return timer; }
        @Override public void setTimeToSneezeOrCough(float value) { timer = value; }
        @Override public int getSneezeCoughActive() { return active; }
        @Override public void setSneezeCoughActive(int value) { active = value; }
        @Override public int getSneezeCoughTime() { return activeTime; }
        @Override public void setSneezeCoughTime(int value) { activeTime = value; }
        @Override public float getApparentInfectionLevel() { return knoxLevel; }

        void severeColdTick() {
            if (hasCold && --timer <= 0.0f) active = 2;
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        long start = 1_000_000_000L;
        check(SCCompanionComfort.symptomAllowed("normal", start,
                start + 59_000_000_000L) == false, "normal gap is at least 60 real seconds");
        check(SCCompanionComfort.symptomAllowed("normal", start,
                start + 60_000_000_000L), "normal symptom becomes due at 60 seconds");
        check(!SCCompanionComfort.symptomAllowed("rare", start,
                start + 299_000_000_000L), "rare gap is at least five real minutes");
        check(SCCompanionComfort.symptomAllowed("rare", start,
                start + 300_000_000_000L), "rare symptom becomes due at five minutes");
        check(!SCCompanionComfort.symptomAllowed("off", Long.MIN_VALUE, start),
                "off blocks symptoms even without prior symptom history");

        Body firstUpdate = new Body();
        firstUpdate.hasCold = true;
        firstUpdate.catchCold = 12;
        firstUpdate.strength = 30;
        firstUpdate.active = 2;
        firstUpdate.activeTime = 5;
        firstUpdate.knoxLevel = 45;
        SCCompanionComfort.setDefaults("off", false);
        SCCompanionComfort inherited = new SCCompanionComfort();
        inherited.applyDefaults(firstUpdate);
        check(!firstUpdate.hasCold && firstUpdate.catchCold == 0
                && firstUpdate.strength == 0 && firstUpdate.active == 0
                && firstUpdate.activeTime == 0 && firstUpdate.knoxLevel == 45
                && !inherited.canScriptedSymptom(),
                "a new companion inherits both choices before its first update");
        SCCompanionComfort.setDefaults("normal", true);

        Body body = new Body();
        body.hasCold = true;
        body.strength = 90.0f;
        body.catchCold = 48.0f;
        SCCompanionComfort comfort = new SCCompanionComfort();
        comfort.beforeUpdate(body);
        check(body.hasCold && body.strength == 90.0f && body.catchCold == 48.0f,
                "ordinary colds remain on by default");
        body.severeColdTick();
        comfort.afterUpdate(body);
        check(body.active == 2, "the first native severe-cold symptom may fire");
        body.active = 0;
        body.timer = 0;
        comfort.beforeUpdate(body);
        body.severeColdTick();
        comfort.afterUpdate(body);
        check(body.active == 0 && body.timer > 1000,
                "native severe-cold symptoms cannot repeat inside the real-time gap");

        comfort.setSymptomMode("off", body);
        body.active = 2;
        body.activeTime = 8;
        comfort.beforeUpdate(body);
        body.severeColdTick();
        comfort.afterUpdate(body);
        check(body.active == 0 && body.activeTime == 0 && body.hasCold,
                "symptom off clears native symptoms but preserves ordinary colds");

        comfort.setOrdinaryColdsEnabled(false, body);
        check(!body.hasCold && body.catchCold == 0 && body.strength == 0
                && body.knoxLevel == 72.0f,
                "cold off clears only ordinary cold fields, preserving Knox infection");
        body.hasCold = true;
        body.catchCold = 10;
        body.strength = 20;
        comfort.beforeUpdate(body);
        check(!body.hasCold && body.catchCold == 0 && body.strength == 0,
                "cold off prevents a fresh native cold on the next update");
        comfort.setOrdinaryColdsEnabled(true, body);
        body.hasCold = true;
        body.strength = 25;
        comfort.beforeUpdate(body);
        check(body.hasCold && body.strength == 25,
                "turning colds back on restores vanilla cold progression");

        SCCompanionComfort scripted = new SCCompanionComfort();
        check(scripted.canScriptedSymptom() && scripted.noteScriptedSymptom()
                && !scripted.canScriptedSymptom(),
                "a scripted sneeze reserves the same per-companion gap");
        scripted.setSymptomMode("off", null);
        check(!scripted.canScriptedSymptom() && !scripted.noteScriptedSymptom(),
                "symptom off blocks scripted gestures too");
        System.out.println("COMPANION_COMFORT_PASS");
    }
}
