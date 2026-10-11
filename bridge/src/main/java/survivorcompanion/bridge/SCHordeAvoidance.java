// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/** Counts zombies in the car-width approach to a route obstacle. */
final class SCHordeAvoidance {
    interface World {
        int liveZombiesAt(int x, int y, int z);
    }

    static final int MIN_HORDE = 6;
    private static final float LOOK_AHEAD = 12.0f;
    private static final float SIDE_MARGIN = 1.0f;

    private SCHordeAvoidance() {}

    static boolean ahead(World world, float x, float y, int z, float forwardX,
                         float forwardY, float halfWidth, float halfLength) {
        if (world == null) return false;
        float sideLimit = halfWidth + SIDE_MARGIN;
        int radius = (int) Math.ceil(LOOK_AHEAD + halfLength + sideLimit);
        int count = 0;
        for (int dx = -radius; dx <= radius; dx++) {
            for (int dy = -radius; dy <= radius; dy++) {
                int tileX = (int) Math.floor(x) + dx;
                int tileY = (int) Math.floor(y) + dy;
                float relativeX = tileX + 0.5f - x;
                float relativeY = tileY + 0.5f - y;
                float along = relativeX * forwardX + relativeY * forwardY;
                float side = -relativeX * forwardY + relativeY * forwardX;
                if (along < halfLength || along > halfLength + LOOK_AHEAD
                        || Math.abs(side) > sideLimit) continue;
                count += Math.max(0, world.liveZombiesAt(tileX, tileY, z));
                if (count >= MIN_HORDE) return true;
            }
        }
        return false;
    }
}
