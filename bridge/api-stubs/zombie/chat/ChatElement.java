// SPDX-License-Identifier: MIT
package zombie.chat;

/** Compile-only Build 42 API surface used by the native companion bridge. */
public class ChatElement {
    public void clear(int playerIndex) {}
    public boolean IsSpeaking() { return false; }
    public boolean getHasChatToDisplay() { return false; }
}
