// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import zombie.chat.ChatElement;

/** Extends only rows actually created by an emission. Never reparses or replays. */
final class SCCompanionSpeechRows {
    private static final Field PLAYERS, LINES, DISPLAY_TIME;
    private static final Method ORIGINAL, CLOCK;
    private static boolean reported;
    static {
        Field players = null, lines = null, time = null;
        Method original = null, clock = null;
        try {
            players = ChatElement.class.getDeclaredField("playerLines");
            Class<?> playerLines = players.getType().getComponentType();
            lines = playerLines.getDeclaredField("chatLines");
            time = playerLines.getDeclaredField("lineDisplayTime");
            Class<?> text = lines.getType().getComponentType();
            original = text.getMethod("getOriginal");
            clock = text.getMethod("setInternalTickClock", float.class);
            players.setAccessible(true);
            lines.setAccessible(true);
            time.setAccessible(true);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            report(failure);
            players = null;
        }
        PLAYERS = players; LINES = lines; DISPLAY_TIME = time;
        ORIGINAL = original; CLOCK = clock;
    }

    private final Object[] rows = new Object[4];
    private final String[] text = new String[4];
    private long generation;

    private static synchronized void report(Throwable failure) {
        if (reported) return;
        reported = true;
        System.err.println("[Living Fellows] Speech clock refresh unavailable; native fade retained: "
                + failure.getClass().getSimpleName());
    }

    static Object[] newest(ChatElement chat) {
        if (PLAYERS == null || chat == null) return null;
        try {
            Object[] result = new Object[4];
            Object[] players = (Object[]) PLAYERS.get(chat);
            for (int i = 0; i < Math.min(4, players.length); i++) {
                if (players[i] == null) continue;
                Object[] lines = (Object[]) LINES.get(players[i]);
                if (lines != null && lines.length > 0) result[i] = lines[0];
            }
            return result;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            report(failure);
            return null;
        }
    }

    static SCCompanionSpeechRows capture(ChatElement chat, Object[] before) {
        if (before == null) return null;
        Object[] after = newest(chat);
        if (after == null) return null;
        SCCompanionSpeechRows lease = new SCCompanionSpeechRows();
        if (chat instanceof SCNativeCompanion.CompanionChatElement companionChat) {
            lease.generation = companionChat.emissionGeneration;
        }
        try {
            for (int i = 0; i < 4; i++) {
                // An unheard/deaf/missing viewport has no newly inserted row.
                // Remember its actual rendered text, including native scrambling.
                if (after[i] != null && after[i] != before[i]) {
                    lease.rows[i] = after[i];
                    lease.text[i] = (String) ORIGINAL.invoke(after[i]);
                }
            }
            return lease;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            report(failure);
            return null;
        }
    }

    boolean refresh(ChatElement chat) {
        try {
            if (PLAYERS == null || chat == null) return false;
            if (chat instanceof SCNativeCompanion.CompanionChatElement companionChat
                    && companionChat.emissionGeneration != generation) return false;
            Object[] players = (Object[]) PLAYERS.get(chat);
            for (int i = 0; i < 4; i++) {
                if (rows[i] == null) continue;
                Object[] lines = i < players.length && players[i] != null
                        ? (Object[]) LINES.get(players[i]) : null;
                if (lines == null || lines.length == 0 || lines[0] != rows[i]
                        || text[i] == null || !text[i].equals(ORIGINAL.invoke(rows[i]))) {
                    rows[i] = null;
                    continue;
                }
                CLOCK.invoke(rows[i], (float) DISPLAY_TIME.getInt(players[i]));
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            report(failure);
            return false;
        }
    }
}
