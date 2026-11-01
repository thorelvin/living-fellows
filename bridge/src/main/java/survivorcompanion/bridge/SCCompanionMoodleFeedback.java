// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.ref.WeakReference;
import java.lang.reflect.Field;

import zombie.characters.IsoPlayer;
import zombie.ui.MoodlesUI;
import zombie.ui.UIManager;

/** Scope the stock combat manager's singleton-only HUD feedback to its NPC. */
final class SCCompanionMoodleFeedback implements AutoCloseable {
    private static final Field INSTANCE = field("instance");
    private static final Field CHARACTER = field("isoGameCharacter");
    private static MoodlesUI silentFeedback;
    private static WeakReference<IsoPlayer> silentOwner = new WeakReference<>(null);
    private static boolean reportedFailure;

    private final MoodlesUI previous;
    private boolean active;

    private SCCompanionMoodleFeedback(MoodlesUI previous, boolean active) {
        this.previous = previous;
        this.active = active;
    }

    private static Field field(String name) {
        try {
            Field field = MoodlesUI.class.getDeclaredField(name);
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException | RuntimeException failure) {
            return null;
        }
    }

    static SCCompanionMoodleFeedback open(SCNativeCompanion actor) {
        MoodlesUI previous = MoodlesUI.getInstance();
        if (INSTANCE == null || CHARACTER == null) {
            reportFailure();
            return new SCCompanionMoodleFeedback(previous, false);
        }
        try {
            MoodlesUI selected = UIManager.getMoodleUI(actor.getPlayerNum());
            if (selected == null || CHARACTER.get(selected) != actor) {
                IsoPlayer primary = IsoPlayer.players == null || IsoPlayer.players.length == 0
                        ? null : IsoPlayer.players[0];
                if (silentFeedback == null || silentOwner.get() != primary) {
                    // Constructor assigns MoodlesUI.instance itself. Always
                    // restore it even if construction or a later lookup fails.
                    silentFeedback = new MoodlesUI();
                    silentOwner = new WeakReference<>(primary);
                }
                // This HUD is never registered, updated or rendered. Offscreen
                // actors keep real native penalties without shaking player HUDs.
                selected = silentFeedback;
            }
            INSTANCE.set(null, selected);
            return new SCCompanionMoodleFeedback(previous, true);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            restore(previous);
            reportFailure();
            return new SCCompanionMoodleFeedback(previous, false);
        }
    }

    private static void reportFailure() {
        if (reportedFailure) return;
        reportedFailure = true;
        System.err.println("[SurvivorCompanionBridge] companion moodle feedback isolation unavailable");
    }

    private static void restore(MoodlesUI previous) {
        try {
            INSTANCE.set(null, previous);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            reportFailure();
        }
    }

    @Override
    public void close() {
        if (!active) return;
        active = false;
        restore(previous);
    }
}
