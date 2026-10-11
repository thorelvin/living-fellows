// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.HashMap;

/**
 * Steers a car along a road route and around what blocks it.
 *
 * <p>Following is pure pursuit: aim the wheel at the point a few tiles ahead on
 * the route, shifted sideways into the right-hand lane. To get past a wreck the
 * follower slides that line sideways: it checks car-wide strips parallel to the
 * road with the lane scan and takes the nearest clear offset, then slides back
 * into its lane once the strip alongside and ahead of the car is clear again.
 * When no offset is clear it reports {@link Mode#BLOCKED} and asks to stop.
 *
 * <p>Turning round hands the wheel to {@link SCTurnAround}; afterwards the car
 * can follow the same route back. Uses no game types: the world arrives through
 * {@link SCLaneScan.World}, so the core gate drives it in a simulation.
 */
final class SCRoadFollower {
    enum Mode { FOLLOW, BLOCKED, ARRIVED, TURNING, TURNED, TURN_FAILED }

    /** Start sliding sideways this far before an obstacle in the current line. */
    static final float AVOID_RANGE = 12.0f;
    /** Slide back into the lane only when this much of it is clear ahead. */
    static final float RETURN_CLEAR = 16.0f;
    /** How far off the road edge a car may put its outer side to get past. */
    static final float SHOULDER = 1.0f;
    static final float OFFSET_STEP = 0.5f;
    static final float AVOID_KMH = 8.0f;
    static final float ARRIVE_TILES = 1.5f;
    /** Stopped this close to the end, with something in the way, also counts as there. */
    static final float NEAR_END_TILES = 5.0f;
    private static final long NEAR_END_STOPPED_MS = 1500L;
    private static final float PURSUIT_GAIN = 2.2f;
    private static final float CURVE_KMH = 6.0f;
    private static final float CURVE_ANGLE = (float) Math.toRadians(25.0);
    private static final long SCAN_INTERVAL_MS = 150L;
    private static final long OFFSET_HOLD_MS = 1500L;
    private static final float DEFAULT_WIDTH = 6.0f;

    /** One frame of driving: wheel, signed target speed, and which bumper to watch. */
    static final class Command {
        float steering;
        float targetKmh;
        /** Slow manoeuvre: keep the small gap, and watch the rear when reversing. */
        boolean maneuver;
    }

    private SCDrivePath path;
    private final float cruiseKmh;
    private final boolean keepRight;
    private final SCDrivePath.Projection projection = new SCDrivePath.Projection();
    private final float[] point = new float[5];
    private final HashMap<Long, Integer> scanCache = new HashMap<>();
    private Mode mode = Mode.FOLLOW;
    private int segment = -1;
    private float along;
    private float lateral;
    private float laneOffset;
    private float offset;
    private boolean offsetChosen;
    private long offsetHoldUntil;
    private long nextScanAt;
    private int swerves;
    private float blockedAt = -1.0f;
    private long stoppedSince = -1L;
    private SCTurnAround turn;
    private boolean followBack;
    private final SCTurnAround.Step turnStep = new SCTurnAround.Step();

    SCRoadFollower(SCDrivePath path, float cruiseKmh, boolean keepRight) {
        this.path = path;
        this.cruiseKmh = SCDriveControl.clampCruise(cruiseKmh);
        this.keepRight = keepRight;
    }

    Mode mode() {
        return mode;
    }

    SCDrivePath path() {
        return path;
    }

    float cruiseKmh() {
        return cruiseKmh;
    }

    float along() {
        return along;
    }

    float remaining() {
        return path.length() - along;
    }

    float lateral() {
        return lateral;
    }

    float offset() {
        return offset;
    }

    float laneOffset() {
        return laneOffset;
    }

    int swerves() {
        return swerves;
    }

    float blockedAt() {
        return blockedAt;
    }

    SCTurnAround turn() {
        return turn;
    }

    /**
     * Turns round to face back down the route. With followBack the car then
     * drives the same route the other way.
     */
    void beginTurn(float heading, int side, boolean thenFollowBack) {
        turn = new SCTurnAround(SCTurnAround.wrap(heading + (float) Math.PI), side);
        followBack = thenFollowBack;
        mode = Mode.TURNING;
    }

    Command update(SCLaneScan.World world, float x, float y, int z, float headingX,
                   float headingY, float speedKmh, float halfWidth, float halfLength,
                   float frontClear, float rearClear, long nowMs, Command out) {
        Command command = out == null ? new Command() : out;
        command.steering = 0.0f;
        command.targetKmh = 0.0f;
        command.maneuver = false;
        float heading = (float) Math.atan2(headingY, headingX);
        if (mode == Mode.TURNING) {
            SCTurnAround.Step step = turn.update(heading, speedKmh, frontClear, rearClear,
                    nowMs, turnStep);
            command.steering = step.steering;
            command.targetKmh = step.targetKmh;
            command.maneuver = true;
            if (turn.state() == SCTurnAround.State.DONE) {
                if (followBack) {
                    path = path.reversed();
                    segment = -1;
                    offsetChosen = false;
                    swerves = 0;
                    mode = Mode.FOLLOW;
                } else {
                    mode = Mode.TURNED;
                }
            } else if (turn.state() == SCTurnAround.State.FAILED) {
                mode = Mode.TURN_FAILED;
            }
            return command;
        }
        if (mode == Mode.ARRIVED || mode == Mode.TURNED || mode == Mode.TURN_FAILED) {
            return command;
        }
        path.project(x, y, segment, projection);
        segment = projection.segment;
        along = projection.along;
        lateral = projection.lateral;
        float toEnd = path.length() - along;
        boolean stopped = Math.abs(speedKmh) <= SCDriveControl.STOPPED_KMH;
        if (!stopped) stoppedSince = -1L;
        else if (stoppedSince < 0L) stoppedSince = nowMs;
        if (toEnd <= ARRIVE_TILES || toEnd <= NEAR_END_TILES && stopped
                && nowMs - stoppedSince >= NEAR_END_STOPPED_MS) {
            mode = Mode.ARRIVED;
            return command;
        }
        path.pointAt(along, 0.0f, point);
        float width = point[4] > 0.0f ? point[4] : DEFAULT_WIDTH;
        float maxOffset = Math.max(0.0f, width * 0.5f + SHOULDER - halfWidth - 0.2f);
        laneOffset = keepRight && width >= 6.0f ? Math.min(width * 0.25f, maxOffset) : 0.0f;
        if (!offsetChosen) {
            offset = laneOffset;
            offsetChosen = true;
        }
        if (nowMs - nextScanAt >= 0L) {
            nextScanAt = nowMs + SCAN_INTERVAL_MS;
            scanCache.clear();
            chooseOffset(world, z, halfWidth, halfLength, maxOffset, nowMs);
        }
        if (mode == Mode.BLOCKED) return command;

        float lookAhead = Math.max(4.0f, Math.min(9.0f, 4.0f + 0.3f * Math.abs(speedKmh)));
        path.pointAt(along + lookAhead, offset, point);
        float aim = SCTurnAround.wrap((float) Math.atan2(point[1] - y, point[0] - x) - heading);
        command.steering = Math.max(-1.0f, Math.min(1.0f, PURSUIT_GAIN * aim));
        float target = cruiseKmh;
        if (Math.abs(offset - laneOffset) > 0.5f) target = Math.min(target, AVOID_KMH);
        float tangentAheadX = point[2];
        float tangentAheadY = point[3];
        path.pointAt(along, 0.0f, point);
        float bend = Math.abs(SCTurnAround.wrap((float) (Math.atan2(tangentAheadY, tangentAheadX)
                - Math.atan2(point[3], point[2]))));
        if (bend > CURVE_ANGLE) target = Math.min(target, CURVE_KMH);
        // Ease in to the end of the route.
        target = Math.min(target, Math.max(3.0f, (path.length() - along) * 1.5f));
        command.targetKmh = target;
        return command;
    }

    /** Distance to the first obstacle in a car-wide strip parallel to the road, or -1. */
    private float stripObstacle(SCLaneScan.World world, int z, float startAlong, float lineOffset,
                                float reach, float halfWidth) {
        // Nothing past the end of the route matters: the car stops there.
        float toEnd = path.length() + ARRIVE_TILES - startAlong;
        reach = Math.min(reach, toEnd);
        if (reach <= 0.1f) return -1.0f;
        path.pointAt(startAlong, lineOffset, point);
        SCLaneScan.Result hit = SCLaneScan.scan(world, point[0], point[1], z, point[2], point[3],
                halfWidth, 0.0f, reach, scanCache);
        return hit.blocked ? hit.distance : -1.0f;
    }

    private void chooseOffset(SCLaneScan.World world, int z, float halfWidth, float halfLength,
                              float maxOffset, long nowMs) {
        float behind = Math.max(0.0f, along - halfLength - 1.0f);
        float sideBySide = along - behind + halfLength;
        if (Math.abs(offset - laneOffset) > 0.25f && nowMs - offsetHoldUntil >= 0L) {
            // Back into the lane once the wreck is behind and the lane ahead is open.
            if (stripObstacle(world, z, behind, laneOffset, sideBySide + RETURN_CLEAR,
                    halfWidth) < 0.0f) {
                offset = laneOffset;
                offsetHoldUntil = nowMs + OFFSET_HOLD_MS;
                mode = Mode.FOLLOW;
                blockedAt = -1.0f;
                return;
            }
        }
        float front = along + halfLength;
        float ahead = stripObstacle(world, z, front, offset, AVOID_RANGE, halfWidth);
        if (ahead < 0.0f) {
            mode = Mode.FOLLOW;
            blockedAt = -1.0f;
            return;
        }
        if (nowMs - offsetHoldUntil < 0L && mode != Mode.BLOCKED) return;
        // Nearest clear line to the lane; overtake on the left when both sides tie.
        float best = Float.NaN;
        int ranks = (int) Math.ceil(2.0f * maxOffset / OFFSET_STEP) + 1;
        for (int step = 1; step <= 2 * ranks; step++) {
            int rank = (step + 1) / 2;
            float candidate = laneOffset + (step % 2 == 1 ? -rank : rank) * OFFSET_STEP;
            if (candidate < -maxOffset - 0.01f || candidate > maxOffset + 0.01f) continue;
            if (Math.abs(candidate - offset) < 0.01f) continue;
            if (stripObstacle(world, z, behind, candidate, sideBySide + AVOID_RANGE,
                    halfWidth) < 0.0f) {
                best = candidate;
                break;
            }
        }
        if (best == best) {
            boolean leavingLane = Math.abs(offset - laneOffset) <= 0.25f;
            if (leavingLane && Math.abs(best - laneOffset) > 0.25f) swerves++;
            offset = best;
            offsetHoldUntil = nowMs + OFFSET_HOLD_MS;
            mode = Mode.FOLLOW;
            blockedAt = -1.0f;
        } else {
            mode = Mode.BLOCKED;
            blockedAt = ahead;
        }
    }
}
