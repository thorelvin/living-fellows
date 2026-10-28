// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;
import java.lang.reflect.Field;

import zombie.chat.ChatElement;
import zombie.ui.TextManager;

/**
 * The native bubble clears names without changing text or adding a backdrop
 * row. Run against repository stubs to observe the arguments sent to rendering;
 * the real-JAR cleanup and live screenshot checks exercise the actual engine.
 */
public final class SCSpeechNameplateLiftTest {
    private SCSpeechNameplateLiftTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        ChatElement chat = new SCNativeCompanion.CompanionChatElement(null, 5, "character");
        TextManager.instance.fontHeightForTests = 14;
        chat.renderBatched(0, 320, 240);
        require(chat.renderedPlayerForTests == 0 && chat.renderedXForTests == 320
                        && chat.renderedYForTests == 218 && !chat.ignoredRadioForTests,
                "the three-argument render path must lift the bubble once and retain its viewport");
        chat.renderBatched(1, 960, 480, true);
        require(chat.renderedPlayerForTests == 1 && chat.renderedXForTests == 960
                        && chat.renderedYForTests == 458 && chat.ignoredRadioForTests,
                "secondary-view anchor and radio filtering must pass through unchanged");
        TextManager.instance.fontHeightForTests = 24;
        chat.renderBatched(0, 320, 240);
        require(chat.renderedYForTests == 208,
                "large UI fonts require their own screen-space clearance");
        TextManager.instance.fontHeightForTests = 0;
        chat.renderBatched(0, 320, 240);
        require(chat.renderedYForTests == 218, "missing font metrics need bounded default clearance");
        TextManager.instance.fontHeightForTests = 14;
        ChatElement ordinary = new ChatElement(null, 5, "character");
        ordinary.renderBatched(1, 960, 480, true);
        require(ordinary.renderedYForTests == 480,
                "the companion renderer must not change player or other-mod chat anchors");

        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        SCNativeCompanion actor = (SCNativeCompanion) unsafeClass
                .getMethod("allocateInstance", Class.class)
                .invoke(singleton.get(null), SCNativeCompanion.class);
        Method refresh = SCNativeCompanion.class.getDeclaredMethod("refreshCompanionSpeech");
        refresh.setAccessible(true);
        for (String words : new String[] { "I still watch the door.", "One.\nTwo.", "Nails: 12 (enough)." }) {
            actor.addLineChatElement(words);
            require(words.equals(actor.getSayLine()), "speech acquired padding before display");
            refresh.invoke(actor);
            require(words.equals(actor.getSayLine()), "refresh changed the displayed text");
        }
        System.out.println("SC_SPEECH_NAMEPLATE_LIFT_PASS render-offset=true text-unchanged=true viewport-isolation=true");
    }
}
