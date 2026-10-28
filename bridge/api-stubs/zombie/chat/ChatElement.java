// SPDX-License-Identifier: MIT
package zombie.chat;

/** Compile-only Build 42 API surface used by the native companion bridge. */
public class ChatElement {
    protected final PlayerLines[] playerLines = new PlayerLines[4];
    public int emissionsForTests;
    public boolean[] hearingForTests = { true, true, false, false };
    public static class TextRow {
        public String original;
        public float clock, r, g, b;
        public zombie.ui.UIFont font;
        public boolean images, icons, colors, fonts, bbcode, equalize;
        public String getOriginal() { return original; }
        public void setInternalTickClock(float value) { clock = value; }
    }
    static class PlayerLines {
        protected int lineDisplayTime = 314;
        protected TextRow[] chatLines = new TextRow[5];
    }
    private final int maxChatLines;
    private final String talkerType;
    public int renderedPlayerForTests, renderedXForTests, renderedYForTests;
    public boolean ignoredRadioForTests;
    public ChatElement(ChatElementOwner owner, int lines, String type) {
        maxChatLines = lines;
        talkerType = type;
        for (int i = 0; i < 4; i++) playerLines[i] = new PlayerLines();
    }
    public int getMaxChatLines() { return maxChatLines; }
    public String getTalkerType() { return talkerType; }
    public void renderBatched(int playerIndex, int x, int y) {
        renderBatched(playerIndex, x, y, false);
    }
    public void renderBatched(int playerIndex, int x, int y, boolean ignoreRadioLines) {
        renderedPlayerForTests = playerIndex;
        renderedXForTests = x;
        renderedYForTests = y;
        ignoredRadioForTests = ignoreRadioLines;
    }
    public TextRow newestForTests(int index) { return playerLines[index].chatLines[0]; }
    public TextRow historyForTests(int index) { return playerLines[index].chatLines[1]; }
    public void addChatLine(String text, float r, float g, float b, zombie.ui.UIFont font,
            float range, String tag, boolean images, boolean icons, boolean colors,
            boolean fonts, boolean bbcode, boolean equalize) {
        emissionsForTests++;
        for (int i = 0; i < 4; i++) {
            if (!hearingForTests[i]) continue;
            TextRow[] lines = playerLines[i].chatLines;
            TextRow recycled = lines[lines.length - 1];
            System.arraycopy(lines, 0, lines, 1, lines.length - 1);
            TextRow row = recycled == null ? new TextRow() : recycled;
            row.original = text; row.r = r; row.g = g; row.b = b; row.font = font;
            row.images = images; row.icons = icons; row.colors = colors;
            row.fonts = fonts; row.bbcode = bbcode; row.equalize = equalize;
            row.clock = 314; lines[0] = row;
        }
    }
    public void clear(int playerIndex) { playerLines[playerIndex].chatLines = new TextRow[5]; }
    public boolean IsSpeaking() { return false; }
    public boolean getHasChatToDisplay() { return false; }
}
