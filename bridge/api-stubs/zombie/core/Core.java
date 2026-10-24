// SPDX-License-Identifier: MIT
package zombie.core;

public class Core {
    public static boolean debug;
    public static int width;
    public static int height;
    public static Core getInstance() { return null; }
    public String getVersionNumber() { return null; }
    public boolean isZoomEnabled() { return false; }
    public int getOffscreenWidth(int playerIndex) { return 0; }
    public int getOffscreenHeight(int playerIndex) { return 0; }
    public float getZoom(int playerIndex) { return 1.0f; }
    public boolean getAutoZoom(int playerIndex) { return false; }
    public void setAutoZoom(int playerIndex, boolean enabled) {}
}
