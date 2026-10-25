// SPDX-License-Identifier: MIT
package zombie.iso;

/** Compile-only public native signatures; never packaged with the bridge. */
public final class LightingJNI {
    public static boolean init;
    public static void init() {}
    public static native void destroy();
    public static native void stateBeginUpdate(int player, int x, int y, int width, int height);
    public static native void stateEndUpdate();
    public static native void stateEndFrame(float r, float g, float b, float ambient,
            float night, float distance, float maximum, boolean clear, float sources, int sky);
    public static native void playerSet(float x, float y, float z, float dx, float dy,
            boolean flag, boolean dead, boolean ghost, boolean shortSighted,
            float fatigue, float range, float cone);
    public static native boolean WaitingForMain();
    public static native void DoLightingUpdateNew(long time, boolean dirty);
    public static native int stateUpdateCounter(int player);
    public static native boolean getCanSee(int player, int x, int y, int z);
    public static native boolean getCouldSee(int player, int x, int y, int z);
    public static native void chunkBeginUpdate(int x, int y, int minZ, int maxZ);
    public static native void chunkEndUpdate();
    public static native void chunkLevelBeginUpdate(int z);
    public static native void chunkLevelEndUpdate();
    public static native void squareBeginUpdate(int x, int y, int z);
    public static native void squareSet(int vision, boolean up, boolean down, boolean floor,
            int matrix, long building, long room, int level, boolean air);
    public static native void squareSetLightTransmission(float a, float b, float c, float d,
            float e, float f, float g, float h, float i, float j, float k, float l,
            float m, float n, float o, float p, float q, float r, float s, float t);
    public static native void squareEndUpdate();
}
