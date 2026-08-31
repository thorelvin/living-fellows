// SPDX-License-Identifier: MIT

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

/** Version-pinned animation/event contract gate for the native human actor. */
public final class SCAnimationContractTest {
    private SCAnimationContractTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static void requireSource(Path gameRoot, String relative, String... snippets)
            throws Exception {
        Path source = gameRoot.resolve(relative);
        require(Files.isRegularFile(source), "missing vanilla action source: " + relative);
        String text = Files.readString(source);
        for (String snippet : snippets) {
            require(text.contains(snippet), "vanilla animation/event contract changed in "
                    + relative + ": " + snippet);
        }
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 1, "game root argument is required");
        Path gameRoot = Path.of(args[0]);
        Class<?> actionAnims = Class.forName("zombie.characters.CharacterActionAnims");
        Map<String, String> values = new LinkedHashMap<>();
        for (Object constant : actionAnims.getEnumConstants()) {
            Enum<?> enumValue = (Enum<?>) constant;
            values.put(enumValue.name(), enumValue.toString());
        }
        for (String required : new String[] { "Bandage", "Craft", "Read" }) {
            require(values.containsKey(required), "CharacterActionAnims." + required + " is unavailable");
        }

        Path actions = gameRoot.resolve("media/AnimSets/player/actions");
        for (String file : new String[] {
                "Loot.xml", "Bandage.xml", "Craft.xml", "reading.xml", "book.xml",
                "WearClothingDefault.xml", "WashFace.xml", "ScrubClothWithSoap.xml" }) {
            require(Files.isRegularFile(actions.resolve(file)), "missing player animation node: " + file);
        }
        Path emotes = gameRoot.resolve("media/AnimSets/player/emote");
        for (String emote : new String[] {
                "wavehi", "bye", "clap", "thumbsup", "thankyou", "insult", "stop",
                "surrender", "thumbsdown", "followme", "comehere", "yes", "no", "shrug",
                "undecided", "ceasefire", "signalok", "moveout", "freeze", "followbehind",
                "signalfire", "comefront" }) {
            require(Files.isRegularFile(emotes.resolve(emote + ".xml")),
                    "missing player emote node: " + emote);
        }
        require(Files.isRegularFile(emotes.resolve("salutecasual.xml"))
                        || Files.isRegularFile(emotes.resolve("saluteformal.xml")),
                "missing player salute animation node");

        requireSource(gameRoot, "media/lua/shared/TimedActions/ISApplyBandage.lua",
                "setActionAnim(CharacterActionAnims.Bandage)", "EventBandage");
        requireSource(gameRoot, "media/lua/shared/TimedActions/ISCraftAction.lua",
                "setActionAnim(CharacterActionAnims.Craft)");
        requireSource(gameRoot, "media/lua/shared/TimedActions/ISReadABook.lua",
                "setActionAnim(CharacterActionAnims.Read)", "EventRead", "ReadType");
        requireSource(gameRoot, "media/lua/client/TimedActions/ISInventoryTransferAction.lua",
                "setActionAnim(\"Loot\")", "EventLootItem", "LootPosition");
        requireSource(gameRoot, "media/lua/shared/TimedActions/ISWearClothing.lua",
                "setActionAnim(\"WearClothing\")", "EventWearClothing",
                "WearClothingLocation");
        requireSource(gameRoot, "media/lua/shared/TimedActions/ISWashYourself.lua",
                "setActionAnim(\"WashFace\")", "EventWashClothing");
        requireSource(gameRoot, "media/lua/shared/TimedActions/ISWashClothing.lua",
                "setActionAnim(\"ScrubClothWithSoap\")", "EventWashClothing");
        System.out.println("ANIMATION_CONTRACT_PASS " + values);
    }
}
