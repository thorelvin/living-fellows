// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;
import java.lang.reflect.Field;

import zombie.chat.ChatElement;
import zombie.ui.TextManager;
import zombie.ui.UIFont;
import zombie.characters.IsoGameCharacter;

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
        Field chatField = IsoGameCharacter.class.getDeclaredField("chatElement");
        chatField.setAccessible(true);
        ChatElement ownChat = new SCNativeCompanion.CompanionChatElement(actor, 5, "character");
        chatField.set(actor, ownChat);
        for (String words : new String[] { "I still watch the door.", "One.\nTwo.", "Nails: 12 (enough)." }) {
            actor.addLineChatElement(words);
            require(words.equals(actor.getSayLine()), "speech acquired padding before display");
            refresh.invoke(actor);
            require(words.equals(actor.getSayLine()), "refresh changed the displayed text");
        }
        int count = ownChat.emissionsForTests;
        require(actor.emitCompanionSpeech("Same words", .7f, .8f, .9f, 8_000), "RGB emission rejected");
        ChatElement.TextRow row = ownChat.newestForTests(0);
        ChatElement.TextRow second = ownChat.newestForTests(1);
        row.clock = second.clock = 3;
        refresh.invoke(actor);
        require(row.clock == 314 && second.clock == 314 && row.r == .7f
                        && row.g == .8f && row.b == .9f && row.font == UIFont.Dialogue,
                "clock refresh must preserve colour/font in both heard viewports");
        require(ownChat.emissionsForTests == count + 1 && ownChat.newestForTests(2) == null,
                "refresh must not duplicate speech or create an unheard viewport row");
        count = ownChat.emissionsForTests;
        actor.addLineChatElement("RGB overload", .8f, .7f, .9f);
        ownChat.newestForTests(0).clock = 1;
        refresh.invoke(actor);
        require(ownChat.emissionsForTests == count + 1 && ownChat.newestForTests(0).clock == 314,
                "the RGB overload must emit once and acquire the common lease");
        row.clock = 7;
        actor.addLineChatElement("Same words", .9f, .7f, .8f, UIFont.Medium, 20f, "custom");
        ChatElement.TextRow repeated = ownChat.newestForTests(0);
        repeated.clock = 2;
        refresh.invoke(actor);
        require(repeated != row && repeated.clock == 314 && row.clock == 7
                        && repeated.r == .9f && repeated.font == UIFont.Medium,
                "repeated words need their own lease; history must fade unchanged");
        actor.addLineChatElement("Extended", .6f, .7f, .8f, UIFont.Small, 12f, "tag",
                true, false, true, true, false, false);
        ChatElement.TextRow extended = ownChat.newestForTests(0);
        require(extended.images && !extended.icons && extended.colors && extended.fonts
                        && !extended.bbcode && !extended.equalize,
                "extended-font emission must retain native formatting settings");
        ownChat.clear(1);
        refresh.invoke(actor);
        require(ownChat.newestForTests(1) == null, "retired viewport was recreated");
        ownChat.addChatLine("Unmanaged", 1, 1, 1, UIFont.Small, 30, "default",
                false, false, false, false, false, true);
        ownChat.newestForTests(0).clock = 4;
        extended.clock = 6;
        refresh.invoke(actor);
        require(ownChat.newestForTests(0).clock == 4 && extended.clock == 6,
                "new foreign rows and the old history must not acquire a lease");
        actor.setAsleep(true);
        count = ownChat.emissionsForTests;
        require(!actor.emitCompanionSpeech("Sleeping", .7f, .8f, .9f, 8_000),
                "atomic RGB speech bypassed sleep");
        actor.addLineChatElement("Sleeping", .7f, .8f, .9f);
        actor.addLineChatElement("Sleeping", .7f, .8f, .9f, UIFont.Small, 12, "tag");
        actor.addLineChatElement("Sleeping");
        require(ownChat.emissionsForTests == count && !actor.hasCompanionSpeech(),
                "an overload bypassed sleep or retained a stale lease");
        actor.setAsleep(false);
        require(actor.emitCompanionSpeech("Awake", .8f, .9f, .7f, 8_000), "wake did not restore speech");
        Field deadline = SCNativeCompanion.class.getDeclaredField("bridgeSpeechRefreshUntilNanos");
        deadline.setAccessible(true);
        deadline.setLong(actor, 1);
        row = ownChat.newestForTests(0);
        row.clock = 5;
        refresh.invoke(actor);
        require(row.clock == 5, "expired lease must let the native fade finish");
        require(!actor.emitCompanionSpeech("Invalid", Float.NaN, 1, 1, 8_000), "invalid RGB accepted");
        actor.emitCompanionSpeech("Recycled", .7f, .8f, .9f, 8_000);
        row = ownChat.newestForTests(0);
        for (int i = 0; i < 5; i++) {
            ownChat.addChatLine("Recycled", 1, 1, 1, UIFont.Small, 30, "default",
                    false, false, false, false, false, true);
        }
        require(ownChat.newestForTests(0) == row, "fixture did not recycle the engine row");
        row.clock = 3;
        refresh.invoke(actor);
        require(row.clock == 3, "a recycled identical row must not inherit an old emission's lease");
        actor.clearCompanionSpeech();
        ownChat.hearingForTests[0] = false;
        ownChat.hearingForTests[1] = true;
        require(actor.emitCompanionSpeech("Only the second view hears", .8f, .9f, .7f, 8_000),
                "secondary-only emission rejected");
        ownChat.newestForTests(1).clock = 1;
        refresh.invoke(actor);
        require(ownChat.newestForTests(0) == null && ownChat.newestForTests(1).clock == 314,
                "a deaf primary viewport must not prevent the heard secondary row's refresh");
        System.out.println("SC_SPEECH_NAMEPLATE_LIFT_PASS render-offset=true text-unchanged=true viewport-isolation=true rgb=true history-isolation=true sleep=true");
    }
}
