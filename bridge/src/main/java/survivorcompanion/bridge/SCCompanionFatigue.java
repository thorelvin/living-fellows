// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.GameTime;
import zombie.SandboxOptions;
import zombie.SystemDisabler;
import zombie.ZomboidGlobals;
import zombie.characters.CharacterStat;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.Stats;
import zombie.characters.traits.CharacterTraits;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.scripting.objects.CharacterTrait;

/** The fatigue-only part of Build 42.21's local-player awake stats update. */
final class SCCompanionFatigue {
    private SCCompanionFatigue() {}

    static float gain(double base, double sandbox, float endurance, float multiplier,
            float dayScale, boolean lessSleep, boolean moreSleep,
            double fatigueMultiplier, boolean resting) {
        double sleepTrait = moreSleep ? 1.3f : lessSleep ? 0.7f : 1.0f;
        double amount = base * sandbox * Math.max(0.3f, 1.0f - endurance)
                * multiplier * dayScale * sleepTrait * fatigueMultiplier
                / (resting ? 1.5f : 1.0f);
        return Double.isFinite(amount) && amount > 0 && amount <= Float.MAX_VALUE
                ? (float) amount : 0.0f;
    }

    static void update(IsoGameCharacter actor) {
        // The engine owns the singleton's gain. Multiplayer is unsupported;
        // its server-side stats path must never be advanced a second time.
        if (actor == null || !SystemDisabler.doCharacterStats || GameServer.server
                || GameClient.client || actor == IsoPlayer.getInstance()
                || actor.isDead() || actor.isAsleep() || actor.isGodMod()) return;
        Stats stats = actor.getStats();
        GameTime time = GameTime.getInstance();
        SandboxOptions sandbox = SandboxOptions.instance;
        if (stats == null || time == null || sandbox == null) return;
        CharacterTraits traits = actor.getCharacterTraits();
        float amount = gain(ZomboidGlobals.fatigueIncrease,
                sandbox.getStatsDecreaseMultiplier(), stats.get(CharacterStat.ENDURANCE),
                time.getMultiplier(), time.getDeltaMinutesPerDay(),
                traits != null && traits.get(CharacterTrait.NEEDS_LESS_SLEEP),
                traits != null && traits.get(CharacterTrait.NEEDS_MORE_SLEEP),
                actor.getFatiqueMultiplier(), actor.isSitting() || actor.isResting());
        // Add just this frame's natural gain. Food, caffeine and sleep reductions
        // retain their native effect; no wall-clock/offline catch-up is applied.
        if (amount > 0) stats.add(CharacterStat.FATIGUE, amount);
    }
}
