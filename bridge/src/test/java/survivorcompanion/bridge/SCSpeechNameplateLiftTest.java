// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;

/**
 * Build 42 draws a character's name where the overhead chat bubble starts, so a
 * speaking companion hid the very label that says who is talking. The bubble
 * grows upward from its anchor and the engine exposes no handle on that anchor,
 * so the lift is part of the line handed to the chat element.
 *
 * Only the rendered bubble is padded. Everything the bridge retains about what
 * was said, and everything Lua sees, stays the words themselves.
 */
public final class SCSpeechNameplateLiftTest {
    private SCSpeechNameplateLiftTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Method lift = SCNativeCompanion.class
                .getDeclaredMethod("liftAboveNameplate", String.class);
        lift.setAccessible(true);

        String spoken = (String) lift.invoke(null, "I still watch the door.");
        require(spoken != null, "a spoken line survives the lift");
        require(spoken.charAt(0) == (char) 10,
                "a spoken line is lifted clear of the nameplate: " + spoken);
        require(spoken.endsWith("I still watch the door."),
                "the words themselves are unchanged: " + spoken);
        require(spoken.length() == "I still watch the door.".length() + 1,
                "exactly one line of lift is added: " + spoken.length());

        // Nothing to lift, and nothing to damage.
        require(lift.invoke(null, (Object) null) == null, "a null line stays null");
        require("".equals(lift.invoke(null, "")), "an empty line is left alone");
        require("   ".equals(lift.invoke(null, "   ")), "a blank line is left alone");

        // The lift is a prefix, so a multi-line quote keeps its own shape.
        String multi = (String) lift.invoke(null, "One." + (char) 10 + "Two.");
        require(multi.equals((char) 10 + "One." + (char) 10 + "Two."),
                "an already multi-line quote keeps its own breaks: " + multi);

        System.out.println("SC_SPEECH_NAMEPLATE_LIFT_PASS");
    }
}
