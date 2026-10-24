// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.GameTime;
import zombie.SystemDisabler;
import zombie.ZomboidGlobals;
import zombie.characters.CharacterStat;
import zombie.characters.IsoGameCharacter;
import zombie.characters.Stats;
import zombie.characters.traits.CharacterTraits;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.objects.CharacterTrait;

/** Formula and lifecycle checks; the live observation verifies real engine growth. */
public final class SCCompanionFatigueTest {
    private static int checks;
    private static void check(boolean okay, String reason) {
        checks++;
        if (!okay) throw new AssertionError(reason);
    }
    private static void close(float actual, float expected, String reason) {
        check(Math.abs(actual - expected) < 0.00001f, reason + ": " + actual + " != " + expected);
    }
    private static final class Values extends Stats {
        float fatigue = 0.2f, endurance = 1;
        int additions;
        @Override public float get(CharacterStat stat) {
            return stat == CharacterStat.FATIGUE ? fatigue : endurance;
        }
        @Override public boolean add(CharacterStat stat, float value) {
            check(stat == CharacterStat.FATIGUE, "only fatigue may change");
            additions++;
            fatigue = Math.min(1, Math.max(0, fatigue + value));
            return true;
        }
    }
    private static final class Traits extends CharacterTraits {
        boolean less, more;
        @Override public boolean get(CharacterTrait trait) {
            return trait == CharacterTrait.NEEDS_LESS_SLEEP ? less : more;
        }
    }
    private static final class Actor extends IsoGameCharacter {
        final Values values = new Values();
        final Traits traits = new Traits();
        boolean asleep, dead, god, sitting, resting;
        @Override public Stats getStats() { return values; }
        @Override public CharacterTraits getCharacterTraits() { return traits; }
        @Override public boolean isAsleep() { return asleep; }
        @Override public boolean isDead() { return dead; }
        @Override public boolean isGodMod() { return god; }
        @Override public boolean isSitting() { return sitting; }
        @Override public boolean isResting() { return resting; }
    }
    public static void main(String[] args) {
        close(SCCompanionFatigue.gain(.01, 1, 1, 1, 1, false, false, 1, false),
                .003f, "rested endurance uses the native 0.3 floor");
        close(SCCompanionFatigue.gain(.01, 2, .2f, 3, .5f, false, false, 2, false),
                .048f, "sandbox, speed, day length and fatigue modifier compose");
        close(SCCompanionFatigue.gain(.01, 1, 0, 1, 1, true, false, 1, false),
                .007f, "less sleep trait matches native 0.7 rate");
        close(SCCompanionFatigue.gain(.01, 1, 0, 1, 1, true, true, 1, false),
                .013f, "more sleep matches native precedence and 1.3 rate");
        close(SCCompanionFatigue.gain(.01, 1, 0, 1, 1, false, false, 1, true),
                .01f / 1.5f, "sitting or resting reduces gain");
        check(SCCompanionFatigue.gain(Double.NaN, 1, 0, 1, 1, false, false, 1, false) == 0,
                "an invalid native value cannot poison stats");
        check(SCCompanionFatigue.gain(.01, 1, 0, 0, 1, false, false, 1, false) == 0,
                "paused world time adds no fatigue");
        GameTime.instance = new GameTime();
        ZomboidGlobals.fatigueIncrease = .01;
        Actor actor = new Actor();
        SCCompanionFatigue.update(actor);
        close(actor.values.fatigue, .203f, "awake non-local character grows naturally");
        check(actor.values.additions == 1, "one update produces one addition");
        actor.values.fatigue = .05f; // A native caffeine reduction remains effective.
        SCCompanionFatigue.update(actor);
        close(actor.values.fatigue, .053f, "a native reduction is not overwritten");
        int before = actor.values.additions;
        actor.asleep = true; SCCompanionFatigue.update(actor); actor.asleep = false;
        actor.dead = true; SCCompanionFatigue.update(actor); actor.dead = false;
        actor.god = true; SCCompanionFatigue.update(actor); actor.god = false;
        SystemDisabler.doCharacterStats = false; SCCompanionFatigue.update(actor);
        SystemDisabler.doCharacterStats = true;
        GameClient.client = true; SCCompanionFatigue.update(actor); GameClient.client = false;
        GameServer.server = true; SCCompanionFatigue.update(actor); GameServer.server = false;
        check(actor.values.additions == before, "sleep, death, cheats, disabled stats and network paths add nothing");
        actor.sitting = true;
        SCCompanionFatigue.update(actor);
        close(actor.values.fatigue, .055f, "a real resting flag selects the resting rate");
        System.out.println("COMPANION_FATIGUE_PASS checks=" + checks);
    }
}
