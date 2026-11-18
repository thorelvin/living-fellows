// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import org.joml.Vector3f;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.core.physics.CarController;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
import zombie.pathfind.VehiclePoly;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;

/**
 * One companion's hands on a steering wheel.
 *
 * <p>Build 42 drives a car from {@code CarController.clientControls}: steering,
 * forward, backward and brake. The keyboard and gamepad only write those fields
 * for player 0 or a bound gamepad, and a seated driver's own update runs
 * {@code IsoPlayer.updateWhileInVehicle}, which feeds them to the controller
 * ({@code BaseVehicle.updatePhysics}). The companion runs that update every
 * frame while seated, so writing the fields just before it is all driving
 * takes. Everything else -- engine, gears, brakes, physics, crash damage -- is
 * the game's own code.
 *
 * <p>Only the main thread touches this object.
 */
final class SCCompanionDriver {
    private static final long SCAN_INTERVAL_NANOS = 100_000_000L;
    private static final long START_RETRY_NANOS = 3_000_000_000L;
    static final int MAX_START_ATTEMPTS = 3;
    private static final float DEFAULT_HALF_WIDTH = 1.0f;
    private static final float DEFAULT_HALF_LENGTH = 2.4f;
    private static final float MIN_LOOK_AHEAD = 8.0f;

    private boolean active;
    private BaseVehicle vehicle;
    private BaseVehicle convoyLead;
    private boolean convoyParking;
    private boolean convoyParked;
    private float convoyGap = Float.NaN;
    private float convoyLateral = Float.NaN;
    private final Vector3f leadForward = new Vector3f();
    static final float CONVOY_PARK_GAP = 2.0f;
    private IsoPlayer authorizedPassenger;
    private boolean haveKey;
    private float steering;
    private float cruiseKmh;
    private boolean autoBrake = true;
    private String state = "idle";
    private float safetyBlockedX;
    private float safetyBlockedY;
    private String reason = "";
    private int startAttempts;
    private int startCalls;
    private long nextStartAt;
    private long nextScanAt;
    private float speedKmh;
    private boolean engineRunning;
    private String engineState = "";
    private SCDriveControl.Input lastInput = new SCDriveControl.Input(0.0f, false, false, false);
    private final SCLaneScan.Result lastScan = new SCLaneScan.Result();
    private final SCLaneScan.Result lastRearScan = new SCLaneScan.Result();
    private BaseVehicle lastScanVehicle;
    private final Vector3f forward = new Vector3f();
    private SCRoadFollower follower;
    private final SCRoadFollower.Command command = new SCRoadFollower.Command();
    private boolean turnRequested;
    private boolean turnFollowBack;
    /** Rear clearance checked during a manoeuvre, in tiles behind the bumper. */
    private static final float REAR_LOOK = 4.0f;
    /** How far to look to each side when choosing which way to turn round. */
    private static final float TURN_ROOM_LOOK = 10.0f;
    private static final float TURN_ROOM_ANGLE = (float) Math.toRadians(70.0);
    private static final long HORDE_AVOID_HOLD_NANOS = 3_000_000_000L;
    /** A companion's car kills any zombie it touches while moving at least this fast. */
    static final float RAM_MIN_KMH = 1.5f;
    /** Squares around the car's centre checked for zombies in contact. */
    private static final int RAM_RADIUS = 4;
    /**
     * Contact reach beyond the body, in tiles. Build 42's own collision pushes
     * a zombie out of the car's box the moment it touches it, so a test of the
     * box alone ({@code isCollided}) only rarely sees the touch.
     */
    static final float RAM_MARGIN = 0.5f;
    private int zombiesKilled;
    private long hordeAvoidUntil;

    boolean isActive() {
        return active;
    }

    boolean followsVehicle(BaseVehicle lead) { return active && convoyLead == lead; }
    boolean convoyParking() { return convoyLead != null && convoyParking; }
    boolean convoyParked() { return convoyLead != null && convoyParked; }
    float convoyGap() { return convoyGap; }
    float convoyLateral() { return convoyLateral; }

    BaseVehicle vehicle() {
        return vehicle;
    }

    String state() {
        return state;
    }

    float safetyBlockedX() { return safetyBlockedX; }
    float safetyBlockedY() { return safetyBlockedY; }

    String reason() {
        return reason;
    }

    float steering() {
        return steering;
    }

    float cruiseKmh() {
        return cruiseKmh;
    }

    boolean autoBrake() {
        return autoBrake;
    }

    float speedKmh() {
        return speedKmh;
    }

    boolean engineRunning() {
        return engineRunning;
    }

    String engineState() {
        return engineState;
    }

    int startAttempts() {
        return startAttempts;
    }

    /** Engine start calls since the wheel was taken, kept after the engine runs. */
    int startCalls() {
        return startCalls;
    }

    /** Zombies this driver has run down since taking the wheel. */
    int zombiesKilled() {
        return zombiesKilled;
    }

    SCDriveControl.Input lastInput() {
        return lastInput;
    }

    SCLaneScan.Result lastScan() {
        return lastScan;
    }

    SCLaneScan.Result lastRearScan() {
        return lastRearScan;
    }

    /** The route being followed, or null while driven by hand (driveSet). */
    SCRoadFollower follower() {
        return follower;
    }

    /** Takes the wheel of the car the actor is driving. Starts stopped. */
    String start(IsoGameCharacter actor, BaseVehicle current, boolean actorHasKey) {
        if (actor == null || current == null) return "companion is not in a vehicle";
        if (current.getDriver() != actor) return "companion is not in the driver's seat";
        if (current.getController() == null) return "vehicle has no controller";
        active = true;
        vehicle = current;
        authorizedPassenger = null;
        haveKey = actorHasKey;
        steering = 0.0f;
        cruiseKmh = 0.0f;
        autoBrake = true;
        state = "holding";
        reason = "";
        startAttempts = 0;
        startCalls = 0;
        zombiesKilled = 0;
        nextStartAt = 0L;
        nextScanAt = 0L;
        hordeAvoidUntil = 0L;
        lastScan.copyFrom(new SCLaneScan.Result());
        lastScanVehicle = null;
        follower = null;
        convoyLead = null;
        convoyParking = convoyParked = false;
        convoyGap = convoyLateral = Float.NaN;
        turnRequested = false;
        return "";
    }

    /** The taxi exception is tied to one seated local player and this car. */
    String startWithPassenger(IsoGameCharacter actor, BaseVehicle current,
                              IsoPlayer passenger, boolean actorHasKey) {
        if (!SCBridge.isAuthorizedDrivePassenger(current, passenger)) {
            return "booked player is not in a passenger seat";
        }
        String failure = start(actor, current, actorHasKey);
        if (failure.isEmpty()) authorizedPassenger = passenger;
        return failure;
    }

    /** Hand driving: a set wheel and speed. Ends any route being followed. */
    void set(double steeringValue, double cruise, boolean brakeForObstacles) {
        follower = null;
        // A braking hold pauses the current owner; it does not authorize a
        // different lead or forget the one needed for a driverless retry.
        boolean holding = steeringValue == 0.0 && cruise == 0.0 && brakeForObstacles;
        if (!holding) convoyLead = null;
        convoyParking = convoyParked = false;
        convoyGap = convoyLateral = Float.NaN;
        lastScanVehicle = null;
        turnRequested = false;
        steering = SCDriveControl.clampSteering(steeringValue);
        cruiseKmh = SCDriveControl.clampCruise(cruise);
        autoBrake = brakeForObstacles;
    }

    /**
     * Follows a route: keeps right, slides round what blocks the lane, and
     * brakes for anything the lane scan finds. Obstacle braking stays on.
     */
    void follow(SCDrivePath path, double cruise) {
        follow(path, cruise, 1.0);
    }

    void follow(SCDrivePath path, double cruise, double cornerSpeedScale) {
        convoyLead = null;
        SCDrivePath.CornerProfile profile = cornerProfile(vehicle, (float) cornerSpeedScale);
        follower = new SCRoadFollower(path.withCorners(profile), (float) cruise, true,
                false, (float) cornerSpeedScale);
        cruiseKmh = follower.cruiseKmh();
        steering = 0.0f;
        autoBrake = true;
        turnRequested = false;
    }

    String followVehicle(BaseVehicle lead, SCDrivePath path, double cruise) {
        boolean parking = lead.getDriver() == null;
        if (follower == null || convoyLead != lead || convoyParking != parking) nextScanAt = 0L;
        if (parking) {
            lead.getForwardVector(leadForward);
            float span = (float) Math.hypot(leadForward.x, leadForward.z);
            if (!(span > 0.9f) || lead.getSquare() == null)
                return "parked lead vehicle is not reachable";
            float hx = leadForward.x / span, hy = leadForward.z / span;
            vehicle.getForwardVector(forward);
            float ownSpan = (float) Math.hypot(forward.x, forward.z);
            if (!(ownSpan > 0.9f)) return "follow car heading is unavailable";
            float standOff = extent(lead, -hx, -hy)
                    + extent(vehicle, forward.x / ownSpan, forward.z / ownSpan) + CONVOY_PARK_GAP;
            path = path.stopBeforeEnd(standOff,
                    lead.getX() - hx * standOff, lead.getY() - hy * standOff);
            cruise = Math.min(cruise, 5.0);
        }
        if (follower == null || convoyLead != lead
                || convoyParking != parking
                || follower.mode() == SCRoadFollower.Mode.TURN_FAILED) {
            follower = new SCRoadFollower(path, (float) cruise, false, parking);
            follower.convoy(parking);
        } else {
            follower.retarget(path);
        }
        convoyLead = lead;
        convoyParking = parking;
        convoyParked = false;
        cruiseKmh = follower.cruiseKmh();
        autoBrake = true;
        turnRequested = false;
        return "";
    }

    /** Actual polygon reach from the body origin in a chosen world direction. */
    private static float extent(BaseVehicle car, float hx, float hy) {
        VehiclePoly poly = car.getPoly();
        if (poly == null) return bodySize(car)[1];
        float x = car.getX(), y = car.getY();
        float reach = Math.max(Math.max((poly.x1 - x) * hx + (poly.y1 - y) * hy,
                (poly.x2 - x) * hx + (poly.y2 - y) * hy),
                Math.max((poly.x3 - x) * hx + (poly.y3 - y) * hy,
                        (poly.x4 - x) * hx + (poly.y4 - y) * hy));
        return Float.isFinite(reach) && reach > 0.1f ? reach : bodySize(car)[1];
    }

    /** Close the gap smoothly; a rolling trail must not apply destination braking. */
    static float convoySpeed(float routeKmh, float speed, float leadKmh, float gap) {
        if (!Float.isFinite(gap) || !Float.isFinite(speed) || !Float.isFinite(leadKmh)) return 0;
        float leader = Math.max(0, leadKmh);
        float desiredGap = 4.0f + leader / 3.6f * 0.2f;
        float target = Math.min(routeKmh, Math.max(0, leader + (gap - desiredGap) * 2.0f));
        float closing = Math.max(0, speed - leader);
        if (gap <= 2.5f) return 0;
        if (gap <= 2.0f + SCDriveControl.stoppingDistance(closing)) target = Math.min(target, leader);
        return target;
    }

    /** Short, centreline-only final approach. Precise stop is still verified
     * against the complete vehicle footprint by the Lua mission owner. */
    void approach(SCDrivePath path, double cruise) {
        convoyLead = null;
        follower = new SCRoadFollower(path, (float) Math.min(5.0, cruise),
                false, true);
        cruiseKmh = follower.cruiseKmh();
        steering = 0.0f;
        autoBrake = true;
        turnRequested = false;
    }

    /** A bounded physical correction before the unchanged forward parking leg. */
    String alignParking(IsoGameCharacter actor, double targetX, double targetY) {
        BaseVehicle current = vehicle;
        if (!active || current == null || actor == null
                || actor.getVehicle() != current || current.getDriver() != actor) {
            return "parking alignment requires the exact active driver";
        }
        if (SCBridge.playerAboard(current)) return "parking alignment refuses a player aboard";
        if (!Double.isFinite(targetX) || !Double.isFinite(targetY)
                || targetX < 0.0 || targetX > 30000.0
                || targetY < 0.0 || targetY > 30000.0
                || !Float.isFinite(current.getZ()) || Math.floor(current.getZ()) != 0.0) {
            return "parking alignment needs a finite ground-floor target";
        }
        float x = current.getX();
        float y = current.getY();
        float currentSpeed = current.getCurrentSpeedKmHour();
        SCDrivePath path = SCDrivePath.parse(x + "," + y + ",5;"
                + targetX + "," + targetY + ",5");
        if (path == null) return "parking alignment has no bounded target route";
        current.getForwardVector(forward);
        float[] body = bodySize(current);
        WorldView world = new WorldView(current, true);
        world.avoidZombies = true;
        SCRoadFollower next = new SCRoadFollower(path, SCTurnAround.FORWARD_KMH, false, true);
        String refused = next.beginParkingAlignment(world, x, y, 0, forward.x, forward.z,
                currentSpeed, body[0], body[1], System.nanoTime() / 1_000_000L);
        if (!refused.isEmpty()) return refused;
        follower = next;
        convoyLead = null;
        cruiseKmh = SCTurnAround.FORWARD_KMH;
        steering = 0.0f;
        autoBrake = true;
        turnRequested = false;
        nextScanAt = 0L;
        return "";
    }

    /** Turns round on the next frame; with followBack, drives the route back. */
    String turnAround(boolean followBack) {
        if (follower == null) return "companion is not following a route";
        turnRequested = true;
        turnFollowBack = followBack;
        return "";
    }

    /**
     * Lets go of the wheel: clears every input and parks the car. A car this
     * companion no longer drives is left alone, so the player's own controls
     * are never touched.
     */
    void stop(IsoGameCharacter actor, String why) {
        BaseVehicle current = vehicle;
        boolean wasActive = active;
        active = false;
        vehicle = null;
        convoyLead = null;
        authorizedPassenger = null;
        follower = null;
        turnRequested = false;
        hordeAvoidUntil = 0L;
        cruiseKmh = 0.0f;
        steering = 0.0f;
        lastInput = new SCDriveControl.Input(0.0f, false, false, false);
        state = "idle";
        reason = why == null ? "" : why;
        if (!wasActive || current == null) return;
        IsoGameCharacter driver = current.getDriver();
        if (driver != null && driver != actor) return;
        CarController controller = current.getController();
        if (controller == null) return;
        controller.getClientControls().reset();
        controller.park();
    }

    /** Called by the seated companion just before the vanilla in-vehicle update. */
    void beforeVehicleUpdate(IsoGameCharacter actor, BaseVehicle current) {
        if (!active) return;
        convoyParked = false;
        if (actor == null || actor.isDead()) {
            stop(actor, "driver_dead");
            return;
        }
        if (current == null || current != vehicle || current.getDriver() != actor) {
            stop(actor, "left_driver_seat");
            return;
        }
        if (authorizedPassenger != null
                && !SCBridge.isAuthorizedDrivePassenger(current, authorizedPassenger)) {
            stop(actor, "booked_passenger_left");
            return;
        }
        if (authorizedPassenger == null && SCBridge.playerAboard(current)) {
            stop(actor, "player_aboard");
            return;
        }
        CarController controller = current.getController();
        if (controller == null) {
            stop(actor, "no_controller");
            return;
        }
        long now = System.nanoTime();
        speedKmh = current.getCurrentSpeedKmHour();
        engineRunning = current.isEngineRunning();
        BaseVehicle.engineStateTypes engine = current.getEngineState();
        engineState = engine == null ? "" : engine.name();
        CarController.ClientControls controls = controller.getClientControls();
        ramZombies(actor, current);
        if (!engineRunning) {
            // No pedal while the engine is off: the controller would try its own
            // key start once and never retry. Start it here, a bounded few times.
            write(controls, new SCDriveControl.Input(steering, false, false,
                    Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH));
            boolean idle = engine == BaseVehicle.engineStateTypes.Idle;
            if (cruiseKmh <= 0.0f) {
                state = "holding";
            } else if (idle && startAttempts >= MAX_START_ATTEMPTS) {
                state = "engine_failed";
            } else if (idle && now - nextStartAt >= 0L) {
                startAttempts++;
                startCalls++;
                nextStartAt = now + START_RETRY_NANOS;
                current.tryStartEngine(haveKey);
                state = "starting";
            } else {
                state = "starting";
            }
            return;
        }
        startAttempts = 0;
        if (follower != null) {
            driveRoute(current, controls, now);
            return;
        }
        if (autoBrake && now - nextScanAt >= 0L) {
            nextScanAt = now + SCAN_INTERVAL_NANOS;
            lastScan.copyFrom(scan(current, lookAheadFor(cruiseKmh)));
        } else if (!autoBrake) {
            lastScan.copyFrom(new SCLaneScan.Result());
        }
        float obstacle = autoBrake && lastScan.blocked ? lastScan.distance : -1.0f;
        SCDriveControl.Input input = SCDriveControl.cruise(speedKmh, cruiseKmh, steering, obstacle);
        write(controls, input);
        if (cruiseKmh <= 0.0f) {
            state = Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH ? "stopping" : "holding";
        } else if (SCDriveControl.mustStop(speedKmh, obstacle)) {
            state = "blocked";
        } else {
            state = "cruising";
        }
    }

    /** One frame of route following: the follower steers, the safety scans brake. */
    private void driveRoute(BaseVehicle current, CarController.ClientControls controls, long now) {
        current.getForwardVector(forward);
        float length = (float) Math.hypot(forward.x, forward.z);
        boolean lostAlignmentHeading = follower.parkingAlignment()
                && (!Float.isFinite(length) || length < 0.9f);
        float headingX = lostAlignmentHeading ? Float.NaN
                : length > 0.001f ? forward.x / length : 1.0f;
        float headingY = lostAlignmentHeading ? Float.NaN
                : length > 0.001f ? forward.z / length : 0.0f;
        float[] body = bodySize(current);
        float x = current.getX();
        float y = current.getY();
        int z = follower.parkingAlignment() && !Float.isFinite(current.getZ())
                ? -1 : (int) Math.floor(current.getZ());
        WorldView world = new WorldView(current, follower.parkingAlignment() || convoyParking);
        if (now - nextScanAt >= 0L) {
            nextScanAt = now + SCAN_INTERVAL_NANOS;
            if (SCHordeAvoidance.ahead(world, x, y, z, headingX, headingY,
                    body[0], body[1])) {
                hordeAvoidUntil = now + HORDE_AVOID_HOLD_NANOS;
            }
            world.avoidZombies = convoyParking || follower.parkingAlignment() || now - hordeAvoidUntil < 0L;
            lastScan.copyFrom(SCLaneScan.scan(world, x, y, z, headingX, headingY, body[0],
                    body[1] + 0.1f, lookAheadFor(follower.cruiseKmh())));
            IsoGridSquare hit = world.cell == null ? null
                    : world.cell.getGridSquare(lastScan.hitX, lastScan.hitY, z);
            lastScanVehicle = lastScan.blocked && lastScan.kind == SCLaneScan.VEHICLE && hit != null
                    ? hit.getVehicleContainer() : null;
            lastRearScan.copyFrom(SCLaneScan.scan(world, x, y, z, -headingX, -headingY, body[0],
                    body[1] + 0.1f, REAR_LOOK));
        }
        world.avoidZombies = convoyParking || follower.parkingAlignment() || now - hordeAvoidUntil < 0L;
        if (turnRequested) {
            turnRequested = false;
            follower.beginTurn((float) Math.atan2(headingY, headingX),
                    turnSide(world, x, y, z, headingX, headingY), turnFollowBack);
        }
        float front = lastScan.blocked ? lastScan.distance : -1.0f;
        float rear = lastRearScan.blocked ? lastRearScan.distance : -1.0f;
        // Exempt the live lead from overtaking decisions, retaining it in the
        // physical bumper scan above. Every other obstacle keeps both checks.
        if (convoyLead != null && !convoyParking) world.ignoredVehicle = convoyLead;
        follower.update(world, x, y, z, headingX, headingY, speedKmh, body[0], body[1],
                front, rear, lastScan.kind, now / 1_000_000L, command);
        if (convoyLead != null) {
            convoyParked = false;
            if (convoyLead == current || convoyLead.getSquare() == null
                    || (convoyLead.getDriver() != null
                    && !(convoyLead.getDriver() instanceof IsoPlayer))
                    || convoyLead.getZ() != current.getZ()) {
                command.targetKmh = 0.0f;
            } else {
                convoyLead.getForwardVector(leadForward);
                float span = (float) Math.hypot(leadForward.x, leadForward.z);
                float hx = span > 0.9f ? leadForward.x / span : Float.NaN;
                float hy = span > 0.9f ? leadForward.z / span : Float.NaN;
                float dx = convoyLead.getX() - x, dy = convoyLead.getY() - y;
                convoyGap = dx * hx + dy * hy - extent(convoyLead, -hx, -hy)
                        - extent(current, hx, hy);
                convoyLateral = -dx * hy + dy * hx;
                if (convoyParking) {
                    command.maneuver = true;
                    float leadSpeed = convoyLead.getCurrentSpeedKmHour();
                    boolean leadStopped = Float.isFinite(leadSpeed)
                            && Math.abs(leadSpeed) <= SCDriveControl.STOPPED_KMH;
                    convoyParked = Float.isFinite(convoyGap) && convoyGap >= 1.5f
                            && convoyGap <= 2.8f && Math.abs(convoyLateral) <= 0.7f
                            && headingX * hx + headingY * hy >= 0.96f
                            && Math.abs(speedKmh) <= SCDriveControl.STOPPED_KMH && leadStopped;
                    if (convoyParked || !Float.isFinite(convoyGap) || convoyGap < 1.5f
                            || !leadStopped)
                        command.targetKmh = 0;
                } else {
                    float separation = (float) Math.hypot(dx, dy);
                    float nx = separation > 0.001f ? dx / separation : Float.NaN;
                    float ny = separation > 0.001f ? dy / separation : Float.NaN;
                    float clearGap = separation - extent(current, nx, ny) - extent(convoyLead, -nx, -ny);
                    command.targetKmh = convoySpeed(command.targetKmh, speedKmh,
                            convoyLead.getCurrentSpeedKmHour(), clearGap);
                    // Only the exact, aligned moving lead uses closing speed.
                    // Other vehicles and all stationary hits keep the normal
                    // absolute-speed bumper brake.
                    float leadSpeed = convoyLead.getCurrentSpeedKmHour();
                    if (lastScan.blocked && lastScan.kind == SCLaneScan.VEHICLE
                            && lastScanVehicle == convoyLead
                            && leadSpeed > SCDriveControl.STOPPED_KMH
                            && headingX * hx + headingY * hy >= 0.96f
                            && Math.abs(convoyLateral) <= 1.5f) {
                        float closing = Math.max(0, speedKmh - leadSpeed);
                        if (closing > SCDriveControl.STOPPED_KMH
                                && front <= 2.0f + SCDriveControl.stoppingDistance(closing))
                            command.targetKmh = Math.min(command.targetKmh, Math.max(0, speedKmh - 4));
                        front = -1;
                    }
                }
            }
        }
        steering = command.steering;
        SCDriveControl.Input input = command.targetKmh < 0.0f
                ? SCDriveControl.reverse(speedKmh, -command.targetKmh, command.steering, rear)
                : SCDriveControl.cruise(speedKmh, command.targetKmh, command.steering, front,
                        command.maneuver ? SCDriveControl.MANEUVER_GAP_TILES
                                : SCDriveControl.HOLD_GAP_TILES);
        write(controls, input);
        SCRoadFollower.Mode mode = follower.mode();
        if (convoyParked()) {
            state = "convoy_parked";
        } else if (mode == SCRoadFollower.Mode.FOLLOW) {
            float gap = command.maneuver ? SCDriveControl.MANEUVER_GAP_TILES
                    : SCDriveControl.HOLD_GAP_TILES;
            if (command.targetKmh > 0.0f && SCDriveControl.mustStop(speedKmh, front, gap)) {
                // The route strip may be clear while the real bumper is not.
                // Report this brake as a block even though the follower is in FOLLOW.
                state = "safety_blocked";
                safetyBlockedX = lastScan.hitX + 0.5f;
                safetyBlockedY = lastScan.hitY + 0.5f;
            } else if (follower.backingOff()) {
                state = "backing_off";
            } else {
                state = Math.abs(follower.offset() - follower.laneOffset()) > 0.5f
                        ? "avoiding" : "following";
            }
        } else {
            state = mode.name().toLowerCase(java.util.Locale.ROOT);
        }
    }

    /**
     * Which way to turn round: towards the side with more open ground ahead of
     * it. -1 turns left, +1 right; a tie turns left, across the road.
     */
    private static int turnSide(WorldView world, float x, float y, int z, float headingX,
                                float headingY) {
        float heading = (float) Math.atan2(headingY, headingX);
        float left = room(world, x, y, z, heading - TURN_ROOM_ANGLE);
        float right = room(world, x, y, z, heading + TURN_ROOM_ANGLE);
        return right > left + 0.5f ? 1 : -1;
    }

    private static float room(WorldView world, float x, float y, int z, float angle) {
        SCLaneScan.Result result = SCLaneScan.scan(world, x, y, z, (float) Math.cos(angle),
                (float) Math.sin(angle), 0.5f, 0.0f, TURN_ROOM_LOOK);
        return result.blocked ? result.distance : TURN_ROOM_LOOK + 1.0f;
    }

    /** Half the body width and half its length, from the vehicle script. */
    private static float[] bodySize(BaseVehicle current) {
        float halfWidth = DEFAULT_HALF_WIDTH;
        float halfLength = DEFAULT_HALF_LENGTH;
        VehicleScript script = current.getScript();
        Vector3f extents = script == null ? null : script.getExtents();
        if (extents != null && extents.x > 0.5f && extents.z > 1.0f) {
            halfWidth = extents.x * 0.5f;
            halfLength = extents.z * 0.5f;
        }
        return new float[] {halfWidth, halfLength};
    }

    /** Only normal route following opts in; convoy, approach and parking stay raw. */
    private static SCDrivePath.CornerProfile cornerProfile(BaseVehicle current, float scale) {
        float[] body = current == null ? new float[] {DEFAULT_HALF_WIDTH, DEFAULT_HALF_LENGTH} : bodySize(current);
        VehicleScript script = current == null ? null : current.getScript();
        float front = 0, rear = 0;
        int fronts = 0, rears = 0;
        if (script != null) {
            for (int i = 0; i < script.getWheelCount(); i++) {
                VehicleScript.Wheel wheel = script.getWheel(i);
                Vector3f offset = wheel == null ? null : wheel.getOffset();
                if (offset == null || !Float.isFinite(offset.z)) continue;
                if (wheel.front) { front += offset.z; fronts++; }
                else { rear += offset.z; rears++; }
            }
        }
        float wheelbase = fronts > 0 && rears > 0 ? Math.abs(front / fronts - rear / rears) : Float.NaN;
        float maxSpeed = script == null ? Float.NaN : script.maxSpeed;
        float clamp = script == null ? Float.NaN : script.getSteeringClamp(maxSpeed);
        float speedScale = Float.isFinite(scale) ? Math.max(1, Math.min(2, scale)) : 1;
        return new SCDrivePath.CornerProfile(true, body[0], body[1], wheelbase, maxSpeed, clamp, 6 * speedScale);
    }

    /**
     * A zombie the moving car touches dies on the spot, killed by the driver.
     * Contact is the car's body box grown by {@link #RAM_MARGIN}. The margin
     * compensates for native collision displacement, but cannot cross a wall.
     * The kill is the game's own {@code Kill}, so corpse and credit are native.
     */
    private void ramZombies(IsoGameCharacter driver, BaseVehicle current) {
        if (Math.abs(speedKmh) < RAM_MIN_KMH) return;
        IsoCell cell = current.getCell();
        if (cell == null) return;
        current.getForwardVector(forward);
        float length = (float) Math.hypot(forward.x, forward.z);
        if (!(length > 0.001f)) return;
        float headingX = forward.x / length;
        float headingY = forward.z / length;
        float[] body = bodySize(current);
        float carX = current.getX();
        float carY = current.getY();
        int centerX = (int) Math.floor(carX);
        int centerY = (int) Math.floor(carY);
        int z = (int) Math.floor(current.getZ());
        ClearEdge clearEdge = (fromX, fromY, toX, toY, floor) -> {
            IsoGridSquare from = cell.getGridSquare(fromX, fromY, floor);
            IsoGridSquare to = cell.getGridSquare(toX, toY, floor);
            return from != null && to != null && !from.isBlockedTo(to)
                    && !to.isSolid() && !to.isSolidTrans();
        };
        for (int dx = -RAM_RADIUS; dx <= RAM_RADIUS; dx++) {
            for (int dy = -RAM_RADIUS; dy <= RAM_RADIUS; dy++) {
                IsoGridSquare square = cell.getGridSquare(centerX + dx, centerY + dy, z);
                ArrayList<IsoMovingObject> movers = square == null ? null : square.getMovingObjects();
                if (movers == null) continue;
                for (int index = movers.size() - 1; index >= 0; index--) {
                    IsoMovingObject mover = movers.get(index);
                    if (mover instanceof IsoZombie zombie && !zombie.isDead()
                            && !zombie.isOnKillDone()
                            && touches(carX, carY, headingX, headingY, body,
                                    zombie.getX(), zombie.getY())
                            && topologyClear(carX, carY, zombie.getX(), zombie.getY(), z,
                                    clearEdge)) {
                        zombie.Kill(driver);
                        zombiesKilled++;
                    }
                }
            }
        }
    }

    /** A point inside the car's body box grown by the ram margin. */
    static boolean touches(float carX, float carY, float headingX, float headingY, float[] body,
                           float x, float y) {
        float dx = x - carX;
        float dy = y - carY;
        float along = dx * headingX + dy * headingY;
        float side = -dx * headingY + dy * headingX;
        return Math.abs(along) <= body[1] + RAM_MARGIN && Math.abs(side) <= body[0] + RAM_MARGIN;
    }

    @FunctionalInterface
    interface ClearEdge {
        boolean clear(int fromX, int fromY, int toX, int toY, int z);
    }

    /** Conservative loaded-square trace from the car to a prospective hit. */
    static boolean topologyClear(float carX, float carY, float x, float y,
                                 int z, ClearEdge edge) {
        int lastX = (int) Math.floor(carX);
        int lastY = (int) Math.floor(carY);
        int steps = Math.max(1, (int) Math.ceil(Math.hypot(x - carX, y - carY) * 5.0));
        for (int i = 1; i <= steps; i++) {
            float fraction = (float) i / steps;
            int nextX = (int) Math.floor(carX + (x - carX) * fraction);
            int nextY = (int) Math.floor(carY + (y - carY) * fraction);
            if (nextX != lastX && nextY != lastY) {
                // A diagonal can graze either side of a corner. Both routes
                // must be clear before treating the enlarged box as contact.
                if (!edge.clear(lastX, lastY, nextX, lastY, z)
                        || !edge.clear(lastX, lastY, lastX, nextY, z)
                        || !edge.clear(nextX, lastY, nextX, nextY, z)
                        || !edge.clear(lastX, nextY, nextX, nextY, z)) return false;
            } else if ((nextX != lastX || nextY != lastY)
                    && !edge.clear(lastX, lastY, nextX, nextY, z)) {
                return false;
            }
            lastX = nextX;
            lastY = nextY;
        }
        return true;
    }

    private void write(CarController.ClientControls controls, SCDriveControl.Input input) {
        controls.steering = input.steering();
        controls.forward = input.forward();
        controls.backward = input.backward();
        controls.brake = input.brake();
        controls.shift = false;
        lastInput = input;
    }

    /** Far enough to stop from a little over the cruise speed, with room to spare. */
    static float lookAheadFor(float cruise) {
        return Math.max(MIN_LOOK_AHEAD, SCDriveControl.stoppingDistance(cruise + 5.0f) + 4.0f);
    }

    /** Runs the lane scan for this car now. */
    SCLaneScan.Result scan(BaseVehicle current, float lookAhead) {
        if (current == null) return SCLaneScan.scan(null, 0, 0, 0, 0, 0, 0, 0, 0);
        current.getForwardVector(forward);
        float[] body = bodySize(current);
        // Physics forward is (x, z); world y grows south like physics z.
        return SCLaneScan.scan(new WorldView(current), current.getX(), current.getY(),
                (int) Math.floor(current.getZ()), forward.x, forward.z,
                body[0], body[1] + 0.1f, lookAhead);
    }

    /** The loaded world as the lane scan sees it, ignoring the scanning car. */
    private static final class WorldView implements SCLaneScan.World, SCHordeAvoidance.World {
        private final BaseVehicle self;
        private final IsoCell cell;
        private BaseVehicle ignoredVehicle;
        private final boolean requireGround;
        private boolean avoidZombies;

        WorldView(BaseVehicle self) {
            this(self, false);
        }

        WorldView(BaseVehicle self, boolean requireGround) {
            this.self = self;
            this.cell = self.getCell();
            this.requireGround = requireGround;
        }

        @Override
        public int liveZombiesAt(int x, int y, int z) {
            IsoGridSquare square = cell == null ? null : cell.getGridSquare(x, y, z);
            ArrayList<IsoMovingObject> movers = square == null ? null : square.getMovingObjects();
            if (movers == null) return 0;
            int count = 0;
            for (IsoMovingObject mover : movers) {
                if (mover instanceof IsoZombie zombie && !zombie.isDead()) count++;
            }
            return count;
        }

        @Override
        public int squareKind(int x, int y, int z) {
            IsoGridSquare square = cell == null ? null : cell.getGridSquare(x, y, z);
            if (square == null) return SCLaneScan.UNLOADED;
            if (requireGround && !square.TreatAsSolidFloor()) return SCLaneScan.SOLID;
            BaseVehicle other = square.getVehicleContainer();
            if (other != null && other != self && other != ignoredVehicle) return SCLaneScan.VEHICLE;
            if (square.HasTree()) return SCLaneScan.TREE;
            zombie.core.properties.PropertyContainer properties = square.getProperties();
            if (properties != null && (properties.has("StopCar")
                    || "Tree".equals(properties.get("PhysicsShape")))) return SCLaneScan.SOLID;
            if (square.isSolid() || square.isSolidTrans()) return SCLaneScan.SOLID;
            ArrayList<IsoMovingObject> movers = square.getMovingObjects();
            if (movers != null) {
                for (int index = 0; index < movers.size(); index++) {
                    IsoMovingObject mover = movers.get(index);
                    // Small groups remain driveable. A dense group ahead makes
                    // the existing car-width route scan steer around or stop.
                    if (mover instanceof IsoZombie zombie && !zombie.isDead()) {
                        if (avoidZombies) return SCLaneScan.CHARACTER;
                        continue;
                    }
                    if (mover instanceof IsoGameCharacter character
                            && !character.isDead() && character.getVehicle() == null) {
                        return SCLaneScan.CHARACTER;
                    }
                }
            }
            return SCLaneScan.CLEAR;
        }

        @Override
        public boolean edgeBlocked(int fromX, int fromY, int toX, int toY, int z) {
            if (cell == null) return false;
            IsoGridSquare from = cell.getGridSquare(fromX, fromY, z);
            IsoGridSquare to = cell.getGridSquare(toX, toY, z);
            // An unloaded square is reported by squareKind, not as an edge.
            return from != null && to != null && from.isBlockedTo(to);
        }
    }
}
