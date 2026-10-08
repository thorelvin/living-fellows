// SPDX-License-Identifier: MIT
package zombie.iso;

/** Compile-only Build 42 isometric depth calculations. */
public final class IsoDepthHelper {
    public static final class Results {
        public float depthStart;
    }
    public static float calculateDepth(float x, float y, float z) { return 0.0f; }
    public static Results getChunkDepthData(int cameraChunkX, int cameraChunkY,
            int worldChunkX, int worldChunkY, int z) { return new Results(); }
}
