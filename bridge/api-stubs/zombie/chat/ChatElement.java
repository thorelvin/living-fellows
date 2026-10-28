// SPDX-License-Identifier: MIT
package zombie.chat;

/** Compile-only Build 42 API surface used by the native companion bridge. */
public class ChatElement {
    private final int maxChatLines;
    private final String talkerType;
    public int renderedPlayerForTests, renderedXForTests, renderedYForTests;
    public boolean ignoredRadioForTests;
    public ChatElement(ChatElementOwner owner, int lines, String type) {
        maxChatLines = lines;
        talkerType = type;
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
    public void clear(int playerIndex) {}
    public boolean IsSpeaking() { return false; }
    public boolean getHasChatToDisplay() { return false; }
}
