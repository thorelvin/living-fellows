// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.HashMap;

/**
 * A fast, bounded check of the lane in front of a car. Three rays run forward
 * from the front bumper: one down the middle and one just outside each side of
 * the body. Each ray samples the squares it crosses and the edges between them,
 * so walls and fences between two clear squares count too. The nearest hit on
 * any ray is the obstacle the car must stop for; the per-ray results tell a
 * later steering layer which side is open.
 *
 * <p>The world is reached only through {@link World}, so the core gate runs
 * this against a synthetic grid without the game.
 */
final class SCLaneScan {
    static final int CLEAR = 0;
    static final int VEHICLE = 1;
    static final int SOLID = 2;
    static final int TREE = 3;
    static final int WALL = 4;
    static final int CHARACTER = 5;
    static final int UNLOADED = 6;
    private static final String[] KIND_NAMES = {
        "clear", "vehicle", "solid", "tree", "wall", "character", "unloaded",
    };
    /** Sampling step along a ray, in tiles. Below 1 so no square is skipped. */
    static final float STEP = 0.4f;
    static final float MAX_LOOK_AHEAD = 32.0f;
    /** Clearance outside the body for the side rays, in tiles. */
    static final float SIDE_MARGIN = 0.2f;
    private static final int MAX_SQUARES = 512;

    private SCLaneScan() {}

    /** The world as the scan sees it. */
    interface World {
        /** CLEAR, or the obstacle kind occupying the square. */
        int squareKind(int x, int y, int z);

        /** True when a wall, fence, window or door blocks travel between two neighbours. */
        boolean edgeBlocked(int fromX, int fromY, int toX, int toY, int z);
    }

    static String kindName(int kind) {
        return kind >= 0 && kind < KIND_NAMES.length ? KIND_NAMES[kind] : "unknown";
    }

    /** Scan outcome. Distances are tiles from the front bumper. */
    static final class Result {
        boolean blocked;
        float distance = -1.0f;
        int kind = CLEAR;
        int hitX;
        int hitY;
        float leftDistance = -1.0f;
        float centerDistance = -1.0f;
        float rightDistance = -1.0f;
        /** Squares this scan read from the world (not from a shared cache). */
        int squaresChecked;

        void copyFrom(Result other) {
            blocked = other.blocked;
            distance = other.distance;
            kind = other.kind;
            hitX = other.hitX;
            hitY = other.hitY;
            leftDistance = other.leftDistance;
            centerDistance = other.centerDistance;
            rightDistance = other.rightDistance;
            squaresChecked = other.squaresChecked;
        }
    }

    /**
     * Scans the lane ahead of a car.
     *
     * @param x car centre
     * @param y car centre
     * @param forwardX world direction the car faces (x grows east)
     * @param forwardY world direction the car faces (y grows south)
     * @param halfWidth half the body width
     * @param frontOffset distance from the centre to the front bumper
     * @param lookAhead how far past the bumper to look
     */
    static Result scan(World world, float x, float y, int z, float forwardX, float forwardY,
                       float halfWidth, float frontOffset, float lookAhead) {
        return scan(world, x, y, z, forwardX, forwardY, halfWidth, frontOffset, lookAhead,
                new HashMap<>());
    }

    /**
     * The same scan sharing a square cache with other scans of the same moment,
     * so trying several lateral offsets reads each square once.
     */
    static Result scan(World world, float x, float y, int z, float forwardX, float forwardY,
                       float halfWidth, float frontOffset, float lookAhead,
                       HashMap<Long, Integer> kinds) {
        Result result = new Result();
        float length = (float) Math.sqrt(forwardX * forwardX + forwardY * forwardY);
        if (world == null || !(length > 0.001f) || !(x == x) || !(y == y)
                || !(halfWidth >= 0.0f) || !(frontOffset >= 0.0f) || !(lookAhead > 0.0f)) {
            // Without a heading the car cannot know what is ahead of it.
            result.blocked = true;
            result.distance = 0.0f;
            result.kind = UNLOADED;
            return result;
        }
        float fx = forwardX / length;
        float fy = forwardY / length;
        // Facing north (0,-1) the right hand points east (1,0).
        float rightX = -fy;
        float rightY = fx;
        float reach = Math.min(lookAhead, MAX_LOOK_AHEAD);
        float side = halfWidth + SIDE_MARGIN;
        result.leftDistance = ray(world, kinds, result, x, y, z, fx, fy,
                -rightX * side, -rightY * side, frontOffset, reach);
        result.centerDistance = ray(world, kinds, result, x, y, z, fx, fy,
                0.0f, 0.0f, frontOffset, reach);
        result.rightDistance = ray(world, kinds, result, x, y, z, fx, fy,
                rightX * side, rightY * side, frontOffset, reach);
        return result;
    }

    private static float ray(World world, HashMap<Long, Integer> kinds, Result result,
                             float x, float y, int z, float fx, float fy,
                             float offsetX, float offsetY, float frontOffset, float reach) {
        int previousX = Integer.MIN_VALUE;
        int previousY = Integer.MIN_VALUE;
        int steps = (int) Math.ceil(reach / STEP);
        for (int step = 0; step <= steps; step++) {
            float travelled = Math.min(step * STEP, reach);
            float along = frontOffset + travelled;
            int squareX = (int) Math.floor(x + offsetX + fx * along);
            int squareY = (int) Math.floor(y + offsetY + fy * along);
            if (squareX == previousX && squareY == previousY) continue;
            int kind = CLEAR;
            if (previousX != Integer.MIN_VALUE
                    && world.edgeBlocked(previousX, previousY, squareX, squareY, z)) {
                kind = WALL;
            } else {
                long key = ((long) squareX << 32) ^ (squareY & 0xffffffffL);
                Integer cached = kinds.get(key);
                if (cached != null) {
                    kind = cached;
                } else if (result.squaresChecked < MAX_SQUARES) {
                    kind = world.squareKind(squareX, squareY, z);
                    kinds.put(key, kind);
                    result.squaresChecked++;
                } else {
                    // Out of budget: an unchecked square is not a clear square.
                    kind = UNLOADED;
                }
            }
            if (kind != CLEAR) {
                if (!result.blocked || travelled < result.distance) {
                    result.blocked = true;
                    result.distance = travelled;
                    result.kind = kind;
                    result.hitX = squareX;
                    result.hitY = squareY;
                }
                return travelled;
            }
            previousX = squareX;
            previousY = squareY;
        }
        return -1.0f;
    }
}
