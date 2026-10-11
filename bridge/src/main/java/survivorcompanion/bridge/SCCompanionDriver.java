// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import org.joml.Vector3f;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoZombie;
import zombie.core.physics.CarController;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
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
    private boolean haveKey;
    private float steering;
    private float cruiseKmh;
    private boolean autoBrake = true;
    private String state = "idle";
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

    BaseVehicle vehicle() {
        return vehicle;
    }

    String state() {
        return state;
    }

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
        follower = null;
        turnRequested = false;
        return "";
    }

    /** Hand driving: a set wheel and speed. Ends any route being followed. */
    void set(double steeringValue, double cruise, boolean brakeForObstacles) {
        follower = null;
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
        follower = new SCRoadFollower(path, (float) cruise, true);
        cruiseKmh = follower.cruiseKmh();
        steering = 0.0f;
        autoBrake = true;
        turnRequested = false;
    }

    /** Short, centreline-only final approach. Precise stop is still verified
     * against the complete vehicle footprint by the Lua mission owner. */
    void approach(SCDrivePath path, double cruise) {
        follower = new SCRoadFollower(path, (float) Math.min(5.0, cruise),
                false, true);
        cruiseKmh = follower.cruiseKmh();
        steering = 0.0f;
        autoBrake = true;
        turnRequested = false;
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
        if (actor == null || actor.isDead()) {
            stop(actor, "driver_dead");
            return;
        }
        if (current == null || current != vehicle || current.getDriver() != actor) {
            stop(actor, "left_driver_seat");
            return;
        }
        if (SCBridge.playerAboard(current)) {
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
        float headingX = length > 0.001f ? forward.x / length : 1.0f;
        float headingY = length > 0.001f ? forward.z / length : 0.0f;
        float[] body = bodySize(current);
        float x = current.getX();
        float y = current.getY();
        int z = (int) Math.floor(current.getZ());
        WorldView world = new WorldView(current);
        if (now - nextScanAt >= 0L) {
            nextScanAt = now + SCAN_INTERVAL_NANOS;
            if (SCHordeAvoidance.ahead(world, x, y, z, headingX, headingY,
                    body[0], body[1])) {
                hordeAvoidUntil = now + HORDE_AVOID_HOLD_NANOS;
            }
            world.avoidZombies = now - hordeAvoidUntil < 0L;
            lastScan.copyFrom(SCLaneScan.scan(world, x, y, z, headingX, headingY, body[0],
                    body[1] + 0.1f, lookAheadFor(follower.cruiseKmh())));
            lastRearScan.copyFrom(SCLaneScan.scan(world, x, y, z, -headingX, -headingY, body[0],
                    body[1] + 0.1f, REAR_LOOK));
        }
        world.avoidZombies = now - hordeAvoidUntil < 0L;
        if (turnRequested) {
            turnRequested = false;
            follower.beginTurn((float) Math.atan2(headingY, headingX),
                    turnSide(world, x, y, z, headingX, headingY), turnFollowBack);
        }
        float front = lastScan.blocked ? lastScan.distance : -1.0f;
        float rear = lastRearScan.blocked ? lastRearScan.distance : -1.0f;
        follower.update(world, x, y, z, headingX, headingY, speedKmh, body[0], body[1],
                front, rear, now / 1_000_000L, command);
        steering = command.steering;
        SCDriveControl.Input input = command.targetKmh < 0.0f
                ? SCDriveControl.reverse(speedKmh, -command.targetKmh, command.steering, rear)
                : SCDriveControl.cruise(speedKmh, command.targetKmh, command.steering, front,
                        command.maneuver ? SCDriveControl.MANEUVER_GAP_TILES
                                : SCDriveControl.HOLD_GAP_TILES);
        write(controls, input);
        SCRoadFollower.Mode mode = follower.mode();
        if (mode == SCRoadFollower.Mode.FOLLOW) {
            state = Math.abs(follower.offset() - follower.laneOffset()) > 0.5f
                    ? "avoiding" : "following";
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
        private boolean avoidZombies;

        WorldView(BaseVehicle self) {
            this.self = self;
            this.cell = self.getCell();
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
            BaseVehicle other = square.getVehicleContainer();
            if (other != null && other != self) return SCLaneScan.VEHICLE;
            if (square.HasTree()) return SCLaneScan.TREE;
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
