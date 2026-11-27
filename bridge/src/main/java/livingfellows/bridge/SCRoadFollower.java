// SPDX-License-Identifier: MIT
package livingfellows.bridge;

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
    static final float SHOULDER = 2.0f;
    static final float OFFSET_STEP = 0.5f;
    static final float AVOID_KMH = 8.0f;
    static final float ARRIVE_TILES = 1.5f;
    /** Stopped this close to the end, with something in the way, also counts as there. */
    static final float NEAR_END_TILES = 5.0f;
    private static final long NEAR_END_STOPPED_MS = 1500L;
    private static final float PURSUIT_GAIN = 2.2f;
    private static final float CURVE_KMH = 6.0f;
    private static final float CURVE_ANGLE = (float) Math.toRadians(25.0);
    private static final float GENTLE_CURVE_KMH = 12.0f;
    private static final float GENTLE_CURVE_ANGLE = (float) Math.toRadians(12.0);
    private static final long SCAN_INTERVAL_MS = 150L;
    private static final long OFFSET_HOLD_MS = 1500L;
    private static final float DEFAULT_WIDTH = 6.0f;
    private static final float TURN_FIRST_ANGLE = (float) Math.toRadians(120.0);
    private static final float TURN_FIRST_KMH = 3.0f;
    private static final float DEPARTURE_ALIGN_ANGLE = (float) Math.toRadians(60.0);
    private static final float DEPARTURE_FRONT_ROOM = 8.0f;
    static final float PARKING_ALIGN_TRAVEL = 6.0f;
    static final long PARKING_ALIGN_LIMIT_MS = 20000L;
    static final int PARKING_ALIGN_MAX_LEGS = 5;
    private static final float PARKING_ALIGN_BRAKE_MARGIN = SCDriveControl.stoppingDistance(6.0f);
    private static final long PARKING_ROOM_INTERVAL_MS = 100L;
    /**
     * Stopped this long while asking to go forward through a clear bumper scan:
     * something the scan cannot see (a wall corner beside the wheel, a kerb)
     * is holding the car. Back off instead of pushing into it until the caller
     * gives up and replans from the same spot.
     */
    static final long WEDGE_MS = 2500L;
    /** Back off this far, or for at most BACKOFF_LIMIT_MS, then follow again. */
    static final float BACKOFF_TILES = 1.5f;
    static final long BACKOFF_LIMIT_MS = 3000L;
    /** Back-offs allowed before the route must make real progress again. */
    static final int MAX_BACKOFFS = 3;
    private static final float BACKOFF_RESET_TILES = 8.0f;
    /** Farther than this from its line, a car stopped against scenery is beside the road. */
    static final float OFF_LINE_TILES = 1.5f;
    /** A rejoin turn faces the lane this far ahead along the route. */
    private static final float REJOIN_AHEAD_TILES = 4.0f;
    private static final float TURN_BACKOUT_TILES = 8.0f;
    private static final long TURN_BACKOUT_LIMIT_MS = 12000L;

    /** One frame of driving: wheel, signed target speed, and which bumper to watch. */
    static final class Command {
        boolean cornerSpeed;
        float steering;
        float targetKmh;
        /** Slow manoeuvre: keep the small gap, and watch the rear when reversing. */
        boolean maneuver;
    }

    private SCDrivePath path;
    private final float cruiseKmh;
    private final float cornerSpeedScale;
    private final float forwardTurnKmh;
    private final boolean keepRight;
    private final boolean preciseArrival;
    private boolean rollingGoal;
    private boolean convoyParking;
    private final SCDrivePath.Projection projection = new SCDrivePath.Projection();
    private final float[] point = new float[5];
    private final float[] scanEnd = new float[5];
    private final HashMap<Long, Integer> scanCache = new HashMap<>();
    private final SCLaneScan.Result stripHit = new SCLaneScan.Result();
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
    private float blockedX;
    private float blockedY;
    private int blockedKind = SCLaneScan.CLEAR;
    private long stoppedSince = -1L;
    private SCTurnAround turn;
    private boolean followBack;
    private boolean resumeAfterTurn;
    /** The current turn only rejoins the lane; failing it falls back to following. */
    private boolean rejoinTurn;
    private boolean initialAlignmentPending = true;
    private boolean turnBackoutTried;
    private boolean turnBackoutSettling;
    private long turnBackoutAt = -1L;
    private long turnBackoutScanAt;
    private float turnBackoutX, turnBackoutY;
    private boolean turnNeighbour;
    private final SCTurnAround.Step turnStep = new SCTurnAround.Step();
    private long wedgedSince = -1L;
    private long backoffStartedAt = -1L;
    private float backoffX;
    private float backoffY;
    private float backoffSteering;
    private float backoffDistance = BACKOFF_TILES;
    private long backoffLimitMs = BACKOFF_LIMIT_MS;
    private float backoffAlong = -1.0f;
    private int backoffs;
    private boolean parkingAlignment;
    private float alignmentX;
    private float alignmentY;
    private float alignmentRoomRadius;
    private long alignmentStartedAt;
    private long alignmentRoomCheckedAt;
    private boolean[] cornerArmed;
    private boolean[] cornerReleased;
    private boolean cornerPathChanged;
    private boolean rebuildingCorner;
    private int cornerFallbacks;
    private float laneError = Float.NaN;
    private float maxLaneError;
    private float motionX, motionY, motionHeading;
    private long motionAt = -1;
    private float velocityAngle;
    private long stripScans;

    SCRoadFollower(SCDrivePath path, float cruiseKmh, boolean keepRight) {
        this(path, cruiseKmh, keepRight, false);
    }

    SCRoadFollower(SCDrivePath path, float cruiseKmh, boolean keepRight,
                   boolean preciseArrival) {
        this(path, cruiseKmh, keepRight, preciseArrival, 1.0f);
    }

    SCRoadFollower(SCDrivePath path, float cruiseKmh, boolean keepRight,
                   boolean preciseArrival, float cornerSpeedScale) {
        this.path = path;
        this.cruiseKmh = SCDriveControl.clampCruise(cruiseKmh);
        this.cornerSpeedScale = Float.isFinite(cornerSpeedScale)
                ? Math.max(1.0f, Math.min(2.0f, cornerSpeedScale)) : 1.0f;
        this.forwardTurnKmh = Math.min(SCTurnAround.FORWARD_KMH * this.cornerSpeedScale,
                Math.max(SCTurnAround.FORWARD_KMH, this.cruiseKmh));
        this.keepRight = keepRight;
        this.preciseArrival = preciseArrival;
        cornerArmed = new boolean[path.corners()];
        cornerReleased = new boolean[path.corners()];
    }

    Mode mode() {
        return mode;
    }

    /** A moving trail ends at a live leader, rather than a destination to brake for. */
    void convoy(boolean parking) {
        rollingGoal = !parking;
        convoyParking = parking;
    }

    SCDrivePath path() {
        return path;
    }

    /** Replace the short rolling trail without discarding steering and obstacle state. */
    void retarget(SCDrivePath next) {
        if (next == null) return;
        if (path.original() != next.original()) {
            cornerArmed = new boolean[next.corners()];
            cornerReleased = new boolean[next.corners()];
            cornerFallbacks = 0;
            maxLaneError = 0;
        }
        path = next;
        segment = -1;
        if (mode == Mode.ARRIVED || mode == Mode.BLOCKED) {
            mode = Mode.FOLLOW;
            blockedAt = -1.0f;
            stoppedSince = -1L;
            initialAlignmentPending = true;
        }
        scanCache.clear();
        nextScanAt = 0L;
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

    int corners() { return path.corners(); }
    int cornersSharp() { return path.cornersSharp(); }
    int cornerFallbacks() { return cornerFallbacks; }
    float laneError() { return laneError; }
    float maxLaneError() { return maxLaneError; }
    long stripScans() { return stripScans; }

    SCDrivePath.Corner activeCorner() {
        for (int i = 0; i < path.corners(); i++) {
            if (cornerArmed[i] && !cornerReleased[i]) return path.corner(i);
        }
        return null;
    }

    int swerves() {
        return swerves;
    }

    /** Back-offs used since the route last made real progress. */
    int backoffs() {
        return backoffs;
    }

    /** True while the car reverses away from something holding it. */
    boolean backingOff() {
        return backoffStartedAt >= 0L || turnBackoutAt >= 0L || turnBackoutSettling;
    }

    float blockedAt() {
        return blockedAt;
    }

    float blockedX() {
        return blockedX;
    }

    float blockedY() {
        return blockedY;
    }

    int blockedKind() {
        return blockedKind;
    }

    SCTurnAround turn() {
        return turn;
    }

    boolean parkingAlignment() { return parkingAlignment; }

    /**
     * Turns round to face back down the route. With followBack the car then
     * drives the same route the other way.
     */
    void beginTurn(float heading, int side, boolean thenFollowBack) {
        parkingAlignment = false;
        turn = new SCTurnAround(SCTurnAround.wrap(heading + (float) Math.PI), side, forwardTurnKmh);
        followBack = thenFollowBack;
        resumeAfterTurn = false;
        initialAlignmentPending = false;
        mode = Mode.TURNING;
    }

    /**
     * A stopped parking correction, under the same driver's owner. The whole
     * possible body envelope is loaded and clear before any pedal is issued;
     * normal bumper scans still brake every forward and reverse leg.
     */
    String beginParkingAlignment(SCLaneScan.World world, float x, float y, int z,
                                 float headingX, float headingY, float speedKmh,
                                 float halfWidth, float halfLength, long nowMs) {
        if (z != 0 || !Float.isFinite(x) || !Float.isFinite(y)
                || !Float.isFinite(speedKmh)
                || Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH
                || !Float.isFinite(halfWidth) || !Float.isFinite(halfLength)
                || halfWidth <= 0.0f || halfLength <= 0.0f) {
            return "parking alignment requires a stopped ground-floor car";
        }
        float headingLength = (float) Math.hypot(headingX, headingY);
        path.pointAt(path.length(), 0.0f, point);
        float distance = (float) Math.hypot(point[0] - x, point[1] - y);
        if (!Float.isFinite(headingLength) || headingLength < 0.9f
                || !Float.isFinite(distance) || distance < 0.5f || distance > 15.0f) {
            return "parking alignment needs a target within 15 tiles";
        }
        float radius = PARKING_ALIGN_TRAVEL + (float) Math.hypot(halfWidth, halfLength)
                + PARKING_ALIGN_BRAKE_MARGIN;
        if (!parkingRoom(world, x, y, z, radius)) {
            return "parking alignment room is blocked or unloaded";
        }
        float heading = (float) Math.atan2(headingY, headingX);
        float targetHeading = (float) Math.atan2(point[1] - y, point[0] - x);
        float error = SCTurnAround.wrap(targetHeading - heading);
        turn = new SCTurnAround(targetHeading, error < 0.0f ? -1 : 1);
        followBack = false;
        resumeAfterTurn = false;
        initialAlignmentPending = false;
        parkingAlignment = true;
        alignmentX = x;
        alignmentY = y;
        alignmentRoomRadius = radius;
        alignmentStartedAt = nowMs;
        alignmentRoomCheckedAt = nowMs;
        mode = Mode.TURNING;
        return "";
    }

    private static boolean parkingRoom(SCLaneScan.World world, float x, float y,
                                       int z, float radius) {
        if (world == null || !Float.isFinite(radius) || radius > 12.0f) return false;
        int checked = 0;
        float radiusSq = radius * radius;
        for (int sx = (int) Math.floor(x - radius); sx <= (int) Math.ceil(x + radius); sx++) {
            for (int sy = (int) Math.floor(y - radius); sy <= (int) Math.ceil(y + radius); sy++) {
                float dx = Math.max(Math.abs(sx + 0.5f - x) - 0.5f, 0.0f);
                float dy = Math.max(Math.abs(sy + 0.5f - y) - 0.5f, 0.0f);
                if (dx * dx + dy * dy > radiusSq) continue;
                if (++checked > 512 || world.squareKind(sx, sy, z) != SCLaneScan.CLEAR
                        || world.edgeBlocked(sx, sy, sx + 1, sy, z)
                        || world.edgeBlocked(sx, sy, sx, sy + 1, z)) return false;
            }
        }
        return true;
    }

    private void failParkingAlignment(String why) {
        turn.abort(why);
        mode = Mode.TURN_FAILED;
    }

    private static boolean vehicleInTurnRoom(SCLaneScan.World world, float x, float y,
                                             int z, float halfWidth, float halfLength) {
        float radius = Math.min(6.0f, (float) Math.hypot(halfWidth, halfLength) + 0.75f);
        for (int sx = (int) Math.floor(x-radius); sx <= (int) Math.ceil(x+radius); sx++) {
            for (int sy = (int) Math.floor(y-radius); sy <= (int) Math.ceil(y+radius); sy++) {
                float dx = Math.max(Math.abs(sx+0.5f-x)-0.5f, 0.0f);
                float dy = Math.max(Math.abs(sy+0.5f-y)-0.5f, 0.0f);
                if (dx*dx+dy*dy <= radius*radius && world.squareKind(sx,sy,z) == SCLaneScan.VEHICLE) return true;
            }
        }
        return false;
    }

    /** Clear a parked neighbour before turning back; never extend the original turn's legs. */
    private boolean backOutForTurn(SCLaneScan.World world, float x, float y, int z,
                                   float speed, float halfWidth, float halfLength,
                                   float rearClear, long nowMs, Command command) {
        if (turnBackoutSettling) {
            if (Math.abs(speed) > SCDriveControl.STOPPED_KMH) return true;
            turnBackoutSettling = false;
        }
        boolean rearClose = rearClear >= 0 && rearClear <= SCTurnAround.LEG_CLEARANCE;
        if (!turnBackoutTried) {
            turnBackoutTried = true;
            if (rearClose || !vehicleInTurnRoom(world,x,y,z,halfWidth,halfLength)) return false;
            turnBackoutAt = nowMs;
            turnBackoutX = x;
            turnBackoutY = y;
            turnNeighbour = true;
            turnBackoutScanAt = nowMs+200;
        }
        if (turnBackoutAt < 0) return false;
        if (nowMs >= turnBackoutScanAt) {
            turnBackoutScanAt = nowMs+200;
            turnNeighbour = vehicleInTurnRoom(world,x,y,z,halfWidth,halfLength);
        }
        if (rearClose || !turnNeighbour || nowMs < turnBackoutAt
                || nowMs-turnBackoutAt >= TURN_BACKOUT_LIMIT_MS
                || Math.hypot(x-turnBackoutX,y-turnBackoutY) >= TURN_BACKOUT_TILES) {
            turnBackoutAt = -1L;
            turnBackoutSettling = Math.abs(speed) > SCDriveControl.STOPPED_KMH;
            return turnBackoutSettling;
        }
        command.steering = 0;
        command.targetKmh = -SCTurnAround.REVERSE_KMH;
        command.maneuver = true;
        return true;
    }

    Command update(SCLaneScan.World world, float x, float y, int z, float headingX,
                   float headingY, float speedKmh, float halfWidth, float halfLength,
                   float frontClear, float rearClear, long nowMs, Command out) {
        return update(world, x, y, z, headingX, headingY, speedKmh, halfWidth,
                halfLength, frontClear, rearClear, SCLaneScan.CLEAR, nowMs, out);
    }

    Command update(SCLaneScan.World world, float x, float y, int z, float headingX,
                   float headingY, float speedKmh, float halfWidth, float halfLength,
                   float frontClear, float rearClear, int frontKind, long nowMs, Command out) {
        Command command = out == null ? new Command() : out;
        command.steering = 0.0f;
        command.targetKmh = 0.0f;
        command.maneuver = false;
        command.cornerSpeed = false;
        laneError = Float.NaN;
        float heading = (float) Math.atan2(headingY, headingX);
        if (path.cornerProfile() != null) observeVelocity(x, y, heading, speedKmh, nowMs);
        if (mode == Mode.TURNING) {
            if (parkingAlignment) {
                if (!Float.isFinite(x) || !Float.isFinite(y) || z != 0
                        || !Float.isFinite(heading) || !Float.isFinite(speedKmh)
                        || Math.abs(speedKmh) > 6.0f) {
                    failParkingAlignment("parking_alignment_pose_or_speed");
                    return command;
                }
                if (Math.hypot(x - alignmentX, y - alignmentY) > PARKING_ALIGN_TRAVEL) {
                    failParkingAlignment("parking_alignment_displacement");
                    return command;
                }
                if (nowMs < alignmentStartedAt
                        || nowMs - alignmentStartedAt >= PARKING_ALIGN_LIMIT_MS
                        || turn.legs() > PARKING_ALIGN_MAX_LEGS) {
                    failParkingAlignment("parking_alignment_limit");
                    return command;
                }
                if (nowMs - alignmentRoomCheckedAt >= PARKING_ROOM_INTERVAL_MS) {
                    alignmentRoomCheckedAt = nowMs;
                    if (!parkingRoom(world, alignmentX, alignmentY, z, alignmentRoomRadius)) {
                        failParkingAlignment("parking_alignment_room_changed");
                        return command;
                    }
                }
            }
            SCTurnAround.Step step = turn.update(heading, speedKmh, frontClear, rearClear,
                    nowMs, turnStep);
            if (parkingAlignment && turn.legs() > PARKING_ALIGN_MAX_LEGS) {
                failParkingAlignment("parking_alignment_limit");
                return command;
            }
            command.steering = step.steering;
            command.targetKmh = step.targetKmh;
            command.cornerSpeed = step.targetKmh > SCTurnAround.FORWARD_KMH;
            command.maneuver = true;
            if (turn.state() == SCTurnAround.State.DONE) {
                if (parkingAlignment) {
                    // The body moved during the turn: the old target heading
                    // cannot establish a safe forward approach from this pose.
                    if (Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH) return command;
                    path.pointAt(path.length(), 0.0f, point);
                    float dx = point[0] - x;
                    float dy = point[1] - y;
                    float distance = (float) Math.hypot(dx, dy);
                    float forwardDot = distance > 0.0f
                            ? (float) (Math.cos(heading) * dx + Math.sin(heading) * dy) / distance
                            : 1.0f;
                    if (distance >= 0.5f && forwardDot < 0.75f) {
                        failParkingAlignment("parking_alignment_target_not_forward");
                    } else {
                        mode = Mode.TURNED;
                    }
                    return command;
                }
                if (followBack || resumeAfterTurn) {
                    if (followBack) {
                        SCDrivePath.CornerProfile profile = path.cornerProfile();
                        path = profile == null ? path.reversed() : path.original().reversed().withCorners(profile);
                        cornerArmed = new boolean[path.corners()];
                        cornerReleased = new boolean[path.corners()];
                    }
                    segment = -1;
                    offsetChosen = false;
                    offsetHoldUntil = 0L;
                    nextScanAt = 0L;
                    stoppedSince = -1L;
                    blockedAt = -1.0f;
                    swerves = 0;
                    rejoinTurn = false;
                    mode = Mode.FOLLOW;
                } else {
                    mode = Mode.TURNED;
                }
            } else if (turn.state() == SCTurnAround.State.FAILED) {
                if (rejoinTurn) {
                    // A rejoin is only a recovery: the route itself has not
                    // failed. Follow again so the normal hold and replan apply.
                    rejoinTurn = false;
                    resumeAfterTurn = false;
                    wedgedSince = -1L;
                    mode = Mode.FOLLOW;
                } else {
                    mode = Mode.TURN_FAILED;
                }
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
        if (initialAlignmentPending) {
            if ((turnBackoutAt >= 0 || turnBackoutSettling)
                    && backOutForTurn(world,x,y,z,speedKmh,halfWidth,halfLength,rearClear,nowMs,command)) return command;
            path.pointAt(along, 0.0f, point);
            float routeHeading = (float) Math.atan2(point[3], point[2]);
            float headingError = Math.abs(SCTurnAround.wrap(routeHeading - heading));
            // A parked roadside car can face almost across its return route.
            // Normal pursuit can drive into the verge or sweep towards a
            // neighbouring parked car before completing that turn. Align
            // while stopped, before spending the available turning space;
            // moving-road steering and precise parking remain unchanged.
            boolean constrainedDeparture = !preciseArrival
                    && Math.abs(speedKmh) < TURN_FIRST_KMH
                    && headingError > DEPARTURE_ALIGN_ANGLE
                    && (frontClear >= 0.0f && frontClear <= DEPARTURE_FRONT_ROOM
                        || vehicleInTurnRoom(world,x,y,z,halfWidth,halfLength));
            if (headingError > TURN_FIRST_ANGLE || constrainedDeparture) {
                if (cruiseKmh <= 0.0f) return command;
                if (constrainedDeparture && !(rearClear < 0.0f
                        || rearClear > SCTurnAround.LEG_CLEARANCE)) return command;
                // A replacement route can lead back from the block. Brake a
                // rolling car before the slow turn, then keep this new path.
                if (Math.abs(speedKmh) < TURN_FIRST_KMH) {
                    if (!preciseArrival && backOutForTurn(world,x,y,z,speedKmh,
                            halfWidth,halfLength,rearClear,nowMs,command)) return command;
                    turn = new SCTurnAround(routeHeading, turnSide(world, x, y, z, heading),
                            forwardTurnKmh);
                    followBack = false;
                    resumeAfterTurn = true;
                    initialAlignmentPending = false;
                    mode = Mode.TURNING;
                    return update(world, x, y, z, headingX, headingY, speedKmh,
                            halfWidth, halfLength, frontClear, rearClear, frontKind, nowMs, command);
                }
                return command;
            }
            initialAlignmentPending = false;
            turnBackoutAt = -1L;
            turnBackoutSettling = false;
        }
        float toEnd = path.length() - along;
        path.pointAt(path.length(), 0.0f, point);
        float physicalEndDistance = (float) Math.hypot(x - point[0], y - point[1]);
        boolean stopped = Math.abs(speedKmh) <= SCDriveControl.STOPPED_KMH;
        if (!stopped) stoppedSince = -1L;
        else if (stoppedSince < 0L) stoppedSince = nowMs;
        boolean arrived = !rollingGoal && (preciseArrival
                ? physicalEndDistance <= (convoyParking ? 0.35f : 1.0f) && stopped
                : toEnd <= ARRIVE_TILES || toEnd <= NEAR_END_TILES && stopped
                    && nowMs - stoppedSince >= NEAR_END_STOPPED_MS);
        if (arrived) {
            mode = Mode.ARRIVED;
            return command;
        }
        if (preciseArrival && physicalEndDistance <= (convoyParking ? 0.25f : 0.9f)) {
            command.targetKmh = 0.0f;
            return command;
        }
        // The real bumper can see beyond a curved lane into the far pavement,
        // even when the route strip is clear. Keep that safety brake intact and
        // give this one corner back to the original pursuit line only when
        // the car has nearly stopped. A moving car can still turn away from
        // a distant side-ray hit outside its clear arc. Keep its safety brake.
        SCDrivePath.Corner bumperArc = path.arcAt(along);
        if (bumperArc != null && frontClear >= 0
                && frontClear <= 0.5f + Math.max(SCDriveControl.HOLD_GAP_TILES,
                        SCDriveControl.stoppingDistance(speedKmh))
                && Math.abs(speedKmh) <= 1.0f
                && !rebuildingCorner && sharpenCorner(bumperArc)) {
            rebuildingCorner = true;
            try {
                return update(world, x, y, z, headingX, headingY, speedKmh, halfWidth,
                        halfLength, frontClear, rearClear, frontKind, nowMs, command);
            } finally { rebuildingCorner = false; }
        }
        path.pointAt(along, 0.0f, point);
        float width = point[4] > 0.0f ? point[4] : DEFAULT_WIDTH;
        float maxOffset = Math.max(0.0f, width * 0.5f + SHOULDER - halfWidth - 0.2f);
        float previousLaneOffset = laneOffset;
        laneOffset = path.cornerProfile() == null
                ? keepRight && width >= 6.0f ? Math.min(width * 0.25f, maxOffset) : 0.0f
                : Math.min(path.laneOffsetAt(along), maxOffset);
        if (offsetChosen && path.arcAt(along) != null) offset += laneOffset - previousLaneOffset;
        if (!offsetChosen) {
            offset = laneOffset;
            offsetChosen = true;
        }
        if (nowMs - nextScanAt >= 0L) {
            nextScanAt = nowMs + SCAN_INTERVAL_MS;
            scanCache.clear();
            chooseOffset(world, z, speedKmh, halfWidth, halfLength, maxOffset, nowMs);
            if (cornerPathChanged) {
                cornerPathChanged = false;
                rebuildingCorner = true;
                try {
                    return update(world, x, y, z, headingX, headingY, speedKmh, halfWidth,
                            halfLength, frontClear, rearClear, frontKind, nowMs, command);
                } finally { rebuildingCorner = false; }
            }
        }
        if (mode == Mode.BLOCKED) {
            wedgedSince = -1L;
            backoffStartedAt = -1L;
            return command;
        }
        if (backoffStartedAt >= 0L) {
            float moved = (float) Math.hypot(x - backoffX, y - backoffY);
            boolean rearClose = rearClear >= 0.0f && rearClear <= SCTurnAround.LEG_CLEARANCE;
            if (moved >= backoffDistance || rearClose
                    || nowMs - backoffStartedAt >= backoffLimitMs) {
                backoffStartedAt = -1L;
                wedgedSince = -1L;
            } else {
                command.steering = backoffSteering;
                command.targetKmh = -SCTurnAround.REVERSE_KMH;
                command.maneuver = true;
                return command;
            }
        }

        float lookAhead = Math.max(4.0f, Math.min(9.0f, 4.0f + 0.3f * Math.abs(speedKmh)));
        float aimLookAhead = lookAhead;
        for (int i = 0; i < path.corners(); i++) {
            SCDrivePath.Corner corner = path.corner(i);
            if (corner.arc() && along >= corner.start() - lookAhead && along <= corner.end() + 3) {
                aimLookAhead = Math.min(aimLookAhead, Math.max(3, corner.radius() * 1.1f));
            }
        }
        float aimAlong = path.cornerProfile() == null ? along + lookAhead
                : path.advanceInLane(along, aimLookAhead, offset - laneOffset);
        float aimOffset = path.cornerProfile() == null ? offset
                : path.laneOffsetAt(aimAlong) + offset - laneOffset;
        path.pointAt(aimAlong, aimOffset, point);
        float aim = SCTurnAround.wrap((float) Math.atan2(point[1] - y, point[0] - x) - heading);
        command.steering = Math.max(-1.0f, Math.min(1.0f, PURSUIT_GAIN * aim));
        float blend = cornerSteeringBlend(lookAhead);
        if (blend > 0) {
            float distance = (float) Math.hypot(point[0] - x, point[1] - y);
            // The route follows the body origin, whose velocity turns ahead of
            // the chassis heading. Phase 0 measured that offset. Observe it from
            // motion rather than hard-coding tyre/profile calibration in gameplay.
            float curvature = distance > 0.1f ? 2 * (float) Math.sin(aim - velocityAngle) / distance : 0;
            float wheel = (float) Math.atan(path.cornerProfile().steeringWheelbase() * curvature);
            command.steering += blend * (Math.max(-1, Math.min(1, wheel)) - command.steering);
        }
        float target = cruiseKmh;
        if (Math.abs(offset - laneOffset) > 0.5f) target = Math.min(target, AVOID_KMH);
        float curveLookAhead = Math.max(9.0f,
                Math.min(64.0f, SCDriveControl.stoppingDistance(speedKmh) + 5.0f));
        path.pointAt(along, 0.0f, point);
        float headingAhead = (float) Math.atan2(point[3], point[2]);
        float vertex = path.nextVertexAlong(along);
        // A fast car needs its braking distance before the first bend. Check
        // each junction in that range so two bends cannot cancel each other.
        for (int bends = 0; bends < 16 && vertex - along <= curveLookAhead; bends++) {
            path.pointAt(vertex + 0.01f, 0.0f, point);
            float nextHeading = (float) Math.atan2(point[3], point[2]);
            float bend = Math.abs(SCTurnAround.wrap(nextHeading - headingAhead));
            if (bend > CURVE_ANGLE) target = Math.min(target, CURVE_KMH * cornerSpeedScale);
            else if (bend > GENTLE_CURVE_ANGLE)
                target = Math.min(target, GENTLE_CURVE_KMH * cornerSpeedScale);
            headingAhead = nextHeading;
            vertex = path.nextVertexAlong(vertex + 0.01f);
        }
        target = cornerSpeed(target, curveLookAhead, heading, speedKmh, command);
        // Ease in to the end of the route.
        if (!rollingGoal) {
            target = Math.min(target, preciseArrival
                    ? Math.max(2.0f, (path.length() - along) * 0.9f)
                    : Math.max(3.0f, (path.length() - along) * 1.5f));
        }
        command.targetKmh = target;
        if (convoyParking) command.maneuver = true;
        noteWedge(x, y, heading, speedKmh, frontClear, rearClear, frontKind, nowMs, command);
        if (path.cornerProfile() != null && mode == Mode.FOLLOW && !backingOff()
                && command.targetKmh >= 0 && Math.abs(offset - laneOffset) <= 0.25f) {
            laneError = lateral - laneOffset;
            maxLaneError = Math.max(maxLaneError, Math.abs(laneError));
        }
        return command;
    }

    private float cornerSteeringBlend(float lookAhead) {
        float blend = 0;
        for (int i = 0; i < path.corners(); i++) {
            SCDrivePath.Corner corner = path.corner(i);
            if (!corner.arc()) continue;
            float enter = Math.max(0, Math.min(1, along - corner.start() + lookAhead));
            float exit = Math.max(0, Math.min(1, corner.end() + 3 - along));
            blend = Math.max(blend, Math.min(enter, exit));
        }
        return blend;
    }

    private void observeVelocity(float x, float y, float heading, float speedKmh, long nowMs) {
        if (motionAt < 0 || nowMs < motionAt || speedKmh <= SCDriveControl.STOPPED_KMH) {
            motionX = x; motionY = y; motionHeading = heading; motionAt = nowMs;
            velocityAngle = 0;
            return;
        }
        if (nowMs - motionAt < 200) return;
        float dx = x - motionX, dy = y - motionY;
        float distance = (float) Math.hypot(dx, dy);
        float measuredSpeed = distance * 1000 / (nowMs - motionAt);
        if (distance >= 0.12f && Math.abs(measuredSpeed - speedKmh / 3.6f) < speedKmh / 3.6f * 0.5f + 0.1f) {
            float middleHeading = motionHeading + SCTurnAround.wrap(heading - motionHeading) / 2;
            float observed = SCTurnAround.wrap((float) Math.atan2(dy, dx) - middleHeading);
            observed = Math.max(-0.6f, Math.min(0.6f, observed));
            velocityAngle += 0.6f * (observed - velocityAngle);
        }
        motionX = x; motionY = y; motionHeading = heading; motionAt = nowMs;
    }

    private float cornerSpeed(float target, float reach, float heading, float speedKmh, Command command) {
        if (path.corners() == 0) return target;
        path.pointAt(along, 0, point);
        float error = Math.abs(SCTurnAround.wrap((float) Math.atan2(point[3], point[2]) - heading));
        float endOfRange = path.advanceInLane(along, reach, 0);
        for (int i = 0; i < path.corners(); i++) {
            SCDrivePath.Corner corner = path.corner(i);
            if (corner.start() <= endOfRange && corner.end() >= along - 0.01f) cornerArmed[i] = true;
            if (!cornerArmed[i] || cornerReleased[i]) continue;
            // Projection passing a vertex cannot release a physical turn.
            if (along > corner.end() && error < Math.toRadians(15)) {
                cornerReleased[i] = true;
                continue;
            }
            // Remember an approaching corner, but do not latch its slow target
            // while still outside this frame's braking range.
            if (along < corner.start() && corner.start() > endOfRange) continue;
            float angle = Math.abs(corner.angle());
            float limit = angle > CURVE_ANGLE ? CURVE_KMH * cornerSpeedScale
                    : angle > GENTLE_CURVE_ANGLE ? GENTLE_CURVE_KMH * cornerSpeedScale : cruiseKmh;
            if (corner.arc() && along < corner.start()) {
                // Enter a checked arc moving at its limit. Keep the conservative
                // 3 m/s², allowing a control update for a corner already known
                // ahead. The physical bumper scan still keeps its full reaction
                // and standstill margins for newly discovered obstacles.
                float speed = Math.abs(speedKmh) / 3.6f;
                float margin = speed * 0.1f;
                float room = Math.max(0, corner.start() - along - margin);
                float permitted = (float) Math.sqrt(limit * limit + 3.6f * 3.6f * 6 * room) - 0.25f;
                limit = Math.max(limit, permitted);
            }
            if (corner.arc()) command.cornerSpeed = true;
            target = Math.min(target, limit);
        }
        return target;
    }

    /**
     * Starts a short reverse when pinned, or when a clear passing strip was
     * selected but the real bumper is too close to turn into it. A fully
     * blocked road still holds. Rear scans and the existing attempt/distance
     * limits govern both recoveries.
     */
    private void noteWedge(float x, float y, float heading, float speedKmh, float frontClear,
                           float rearClear, int frontKind, long nowMs, Command command) {
        if (backoffAlong >= 0.0f && along - backoffAlong >= BACKOFF_RESET_TILES) {
            backoffs = 0;
            backoffAlong = -1.0f;
        }
        boolean scanClear = frontClear < 0.0f
                || frontClear > SCDriveControl.HOLD_GAP_TILES + 0.5f;
        boolean passingBlocked = !scanClear && frontKind == SCLaneScan.VEHICLE
                && Math.abs(offset - laneOffset) > 0.5f;
        // A clear route beside pavement can still leave a crooked bumper
        // stopped before its wheels establish the turn. Use the same bounded
        // reverse near checked corners; raw routes keep their existing policy.
        boolean cornerBlocked = !scanClear && nearCornerBumper()
                && (frontKind == SCLaneScan.SOLID || frontKind == SCLaneScan.WALL
                    || frontKind == SCLaneScan.TREE || frontKind == SCLaneScan.VEHICLE);
        // A cramped turnaround can finish facing along the route but well
        // beside it, the nose over the kerb against a corner (live 0.27.92
        // taxi at a junction mouth). Scenery ahead of a car off its line is
        // not the road closing: back off at the opposite lock and rejoin,
        // as for a corner. In its lane the car still holds.
        boolean offLineBlocked = !scanClear && Math.abs(lateral - offset) > OFF_LINE_TILES
                && (frontKind == SCLaneScan.SOLID || frontKind == SCLaneScan.WALL
                    || frontKind == SCLaneScan.TREE);
        if (preciseArrival || command.targetKmh <= 0.0f
                || !(scanClear || passingBlocked || cornerBlocked || offLineBlocked)
                || Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH) {
            wedgedSince = -1L;
            return;
        }
        if (wedgedSince < 0L) {
            wedgedSince = nowMs;
            return;
        }
        if (nowMs - wedgedSince < WEDGE_MS || backoffs >= MAX_BACKOFFS) return;
        if (rearClear >= 0.0f && rearClear <= SCTurnAround.LEG_CLEARANCE) return;
        backoffs++;
        backoffAlong = along;
        if (offLineBlocked && !passingBlocked && !cornerBlocked) {
            // Beside the road a straight back-off cannot help: the bumper
            // brake holds every forward try along the old heading. Turn on
            // the spot, in bounded slow legs, to face a point on the lane a
            // few tiles ahead, then follow from there.
            path.pointAt(Math.min(path.length(), along + REJOIN_AHEAD_TILES), offset, point);
            float target = (float) Math.atan2(point[1] - y, point[0] - x);
            int side = SCTurnAround.wrap(target - heading) >= 0.0f ? 1 : -1;
            turn = new SCTurnAround(target, side, forwardTurnKmh);
            followBack = false;
            resumeAfterTurn = true;
            rejoinTurn = true;
            initialAlignmentPending = false;
            wedgedSince = -1L;
            mode = Mode.TURNING;
            command.steering = 0.0f;
            command.targetKmh = 0.0f;
            command.maneuver = true;
            return;
        }
        backoffStartedAt = nowMs;
        backoffX = x;
        backoffY = y;
        // A parked car outside a bend can trip both checks. Reversing straight
        // in that case sends the same bumper into the same obstacle again.
        // Make room to change lanes on straights and correct the angle at bends.
        boolean correctCorner = cornerBlocked && Math.abs(command.steering) >= 0.15f;
        boolean makePassingRoom = passingBlocked && !correctCorner;
        backoffDistance = makePassingRoom ? SCDriveControl.HOLD_GAP_TILES + 0.5f : BACKOFF_TILES;
        backoffLimitMs = makePassingRoom ? 6000L : BACKOFF_LIMIT_MS;
        // Reverse at the opposite lock, as a three-point turn does: the car
        // keeps rotating the way it was steering while it backs away, so the
        // next forward try meets the corner at a wider angle.
        backoffSteering = makePassingRoom || Math.abs(command.steering) < 0.15f ? 0.0f : -command.steering;
        command.steering = backoffSteering;
        command.targetKmh = -SCTurnAround.REVERSE_KMH;
        command.maneuver = true;
    }

    private boolean nearCornerBumper() {
        if (path.cornerProfile() == null) return false;
        float reach = 9 + path.cornerProfile().halfLength();
        for (int i = 0; i < path.corners(); i++) {
            SCDrivePath.Corner corner = path.corner(i);
            if (along >= corner.start() - reach && along <= corner.end() + 3) return true;
        }
        return false;
    }

    /**
     * Distance to the first obstacle in a car-wide strip that runs alongside the
     * route at a lateral offset, or -1. The strip follows the route round its
     * corners one straight piece at a time, so a turn ahead is not mistaken for
     * a road that runs on into whatever lies beyond the junction.
     */
    private float stripObstacle(SCLaneScan.World world, int z, float startAlong, float lineOffset,
                                float reach, float halfWidth, float halfLength) {
        stripHit.blocked = false;
        stripHit.kind = SCLaneScan.CLEAR;
        // Nothing past the end of the route matters: the car stops there.
        float toEnd = path.length() + ARRIVE_TILES - startAlong;
        if (path.cornerProfile() != null) {
            reach = path.advanceInLane(startAlong, reach, lineOffset - laneOffset) - startAlong;
        }
        reach = Math.min(reach, toEnd);
        if (reach <= 0.1f) return -1.0f;
        float covered = 0.0f;
        float at = startAlong;
        while (covered < reach - 0.05f) {
            float pieceEnd = Math.min(startAlong + reach, path.nextVertexAlong(at));
            float piece = Math.max(path.cornerProfile() == null ? SCLaneScan.STEP : 0.001f, pieceEnd - at);
            SCDrivePath.Corner arc = path.arcAt(at + 0.001f);
            if (arc != null) {
                float delta = lineOffset - laneOffset;
                path.pointAt(at, path.laneOffsetAt(at) + delta, point);
                float startX = point[0], startY = point[1];
                float startTangent = (float) Math.atan2(point[3], point[2]);
                pieceEnd = Math.min(startAlong + reach, Math.min(arc.end(), path.nextVertexAlong(at)));
                path.pointAt(pieceEnd, path.laneOffsetAt(pieceEnd) + delta, scanEnd);
                float firstHeading = (float) Math.atan2(scanEnd[1] - startY, scanEnd[0] - startX);
                while (pieceEnd < arc.end() - 0.01f && pieceEnd < startAlong + reach - 0.01f) {
                    float previousX = scanEnd[0], previousY = scanEnd[1];
                    float next = Math.min(startAlong + reach, Math.min(arc.end(), path.nextVertexAlong(pieceEnd)));
                    path.pointAt(next, path.laneOffsetAt(next) + delta, scanEnd);
                    float lastHeading = (float) Math.atan2(scanEnd[1] - previousY, scanEnd[0] - previousX);
                    if (Math.abs(SCTurnAround.wrap(lastHeading - firstHeading)) >= Math.toRadians(12)) {
                        path.pointAt(pieceEnd, path.laneOffsetAt(pieceEnd) + delta, scanEnd);
                        break;
                    }
                    pieceEnd = next;
                }
                float dx = scanEnd[0] - startX, dy = scanEnd[1] - startY;
                float chord = (float) Math.hypot(dx, dy);
                // A clipped span can be shorter than the scan's heading
                // threshold at an arc boundary. It is known geometry, rather
                // than an unreadable world direction.
                if (chord <= 0.001f) {
                    covered += pieceEnd - at;
                    at = pieceEnd;
                    continue;
                }
                float angle = Math.abs(SCTurnAround.wrap((float) Math.atan2(scanEnd[3], scanEnd[2]) - startTangent));
                float bow = (arc.radius() + Math.abs(delta)) * (1 - (float) Math.cos(angle / 2));
                // A long body sweeps wider than its centreline while turning.
                // Include its outer corner, beyond the chord's own sagitta.
                float bodyWidth = (float) Math.hypot(arc.radius() + halfWidth, halfLength) - arc.radius();
                stripScans++;
                SCLaneScan.Result hit = SCLaneScan.scanFilled(world, startX, startY, z, dx, dy,
                        bodyWidth + bow, 0, Math.max(chord, 0.001f), scanCache);
                if (hit.blocked) {
                    stripHit.copyFrom(hit);
                    return covered + Math.min(1, hit.distance / Math.max(chord, 0.001f)) * (pieceEnd - at);
                }
                covered += pieceEnd - at;
                at = pieceEnd;
                continue;
            }
            float offset = path.cornerProfile() == null ? lineOffset : path.laneOffsetAt(at) + lineOffset - laneOffset;
            path.pointAt(at, offset, point);
            stripScans++;
            SCLaneScan.Result hit = path.cornerProfile() == null
                    ? SCLaneScan.scan(world, point[0], point[1], z, point[2],
                            point[3], halfWidth, 0.0f, piece, scanCache)
                    : SCLaneScan.scanFilled(world, point[0], point[1], z, point[2],
                            point[3], halfWidth, 0.0f, piece, scanCache);
            if (hit.blocked) {
                stripHit.copyFrom(hit);
                return covered + hit.distance;
            }
            covered += piece;
            at += piece;
        }
        return -1.0f;
    }

    private void chooseOffset(SCLaneScan.World world, int z, float speedKmh,
                              float halfWidth, float halfLength,
                              float maxOffset, long nowMs) {
        float avoidRange = Math.max(AVOID_RANGE,
                Math.min(24.0f, SCDriveControl.stoppingDistance(speedKmh) + 5.0f));
        float behind = path.cornerProfile() == null ? Math.max(0.0f, along - halfLength - 1.0f)
                : path.advanceInLane(along, -halfLength - 1, offset - laneOffset);
        float sideBySide = path.cornerProfile() == null ? along - behind + halfLength : 2 * halfLength + 1;
        if (preciseArrival) {
            float front = along + halfLength;
            float ahead = stripObstacle(world, z, front, 0.0f,
                    avoidRange, halfWidth, halfLength);
            mode = ahead < 0.0f ? Mode.FOLLOW : Mode.BLOCKED;
            blockedAt = ahead;
            if (ahead >= 0.0f) {
                blockedX = stripHit.hitX + 0.5f;
                blockedY = stripHit.hitY + 0.5f;
                blockedKind = stripHit.kind;
            }
            return;
        }
        SCDrivePath.Corner activeArc = path.arcAt(along);
        if (activeArc == null && Math.abs(offset - laneOffset) > 0.25f && nowMs - offsetHoldUntil >= 0L) {
            // Back into the lane once the wreck is behind and the lane ahead is open.
            if (stripObstacle(world, z, behind, laneOffset, sideBySide + RETURN_CLEAR,
                    halfWidth, halfLength) < 0.0f) {
                offset = laneOffset;
                offsetHoldUntil = nowMs + OFFSET_HOLD_MS;
                mode = Mode.FOLLOW;
                blockedAt = -1.0f;
                return;
            }
        }
        float front = path.cornerProfile() == null ? along + halfLength
                : path.advanceInLane(along, halfLength, offset - laneOffset);
        float ahead = stripObstacle(world, z, front, offset, avoidRange, halfWidth, halfLength);
        int hitX = stripHit.hitX, hitY = stripHit.hitY, hitKind = stripHit.kind;
        if (ahead < 0.0f) {
            mode = Mode.FOLLOW;
            blockedAt = -1.0f;
            return;
        }
        SCDrivePath.Corner obstacleArc = path.arcAt(front + ahead);
        SCDrivePath.Corner limitedArc = activeArc == null ? obstacleArc : activeArc;
        if (nowMs - offsetHoldUntil < 0L && mode != Mode.BLOCKED) return;
        // Nearest clear line to the lane; overtake on the left when both sides tie.
        float best = Float.NaN;
        int ranks = (int) Math.ceil(2.0f * maxOffset / OFFSET_STEP) + 1;
        for (int step = 1; activeArc == null && step <= 2 * ranks; step++) {
            int rank = (step + 1) / 2;
            float candidate = laneOffset + (step % 2 == 1 ? -rank : rank) * OFFSET_STEP;
            if (limitedArc != null && Math.abs(candidate - laneOffset)
                    > Math.min(1.5f, limitedArc.radius() - 1.5f) + 0.001f) continue;
            // Leave one pursuit span and the body length to establish a
            // passing line before the arc. A late sideways change would sweep
            // the rear across the obstacle even if that parallel line is clear.
            if (limitedArc != null && limitedArc.start() - along < halfLength + 4
                    && Math.abs(candidate - offset) > 0.25f) continue;
            if (candidate < -maxOffset - 0.01f || candidate > maxOffset + 0.01f) continue;
            if (Math.abs(candidate - offset) < 0.01f) continue;
            if (stripObstacle(world, z, behind, candidate, sideBySide + avoidRange,
                    halfWidth, halfLength) < 0.0f) {
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
            if (limitedArc != null && !rebuildingCorner && sharpenCorner(limitedArc)) {
                cornerPathChanged = true;
                return;
            }
            mode = Mode.BLOCKED;
            blockedAt = ahead;
            blockedX = hitX + 0.5f;
            blockedY = hitY + 0.5f;
            blockedKind = hitKind;
        }
    }

    private boolean sharpenCorner(SCDrivePath.Corner corner) {
        float originalFix = path.originalAlong(along);
        SCDrivePath next = path.sharpCorner(corner.id());
        if (next == path) return false;
        boolean pendingAlignment = initialAlignmentPending;
        retarget(next);
        initialAlignmentPending = pendingAlignment;
        segment = next.segmentAtOriginalAlong(originalFix);
        cornerFallbacks++;
        return true;
    }

    /** Turn towards the more open side; ties go left, across the road. */
    private static int turnSide(SCLaneScan.World world, float x, float y, int z, float heading) {
        float angle = (float) Math.toRadians(70.0);
        float left = room(world, x, y, z, heading - angle);
        float right = room(world, x, y, z, heading + angle);
        return right > left + 0.5f ? 1 : -1;
    }

    private static float room(SCLaneScan.World world, float x, float y, int z, float angle) {
        SCLaneScan.Result scan = SCLaneScan.scan(world, x, y, z,
                (float) Math.cos(angle), (float) Math.sin(angle), 0.5f, 0.0f, 10.0f);
        return scan.blocked ? scan.distance : 11.0f;
    }
}
