// SPDX-License-Identifier: MIT
package zombie.ui;

/** Compile-only Build 42 font metrics. */
public class TextManager {
    public static final TextManager instance = new TextManager();
    public int fontHeightForTests = 14;
    public int getFontHeight(UIFont font) { return fontHeightForTests; }
}
