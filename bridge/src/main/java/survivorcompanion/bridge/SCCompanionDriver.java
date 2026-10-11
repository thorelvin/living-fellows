// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import org.joml.Vector3f;
import zombie.characters.IsoGameCharacter;
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
    private final Vector3f forward = new Vector3f();

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

    SCDriveControl.Input lastInput() {
        return lastInput;
    }

    SCLaneScan.Result lastScan() {
        return lastScan;
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
        nextStartAt = 0L;
        nextScanAt = 0L;
        lastScan.copyFrom(new SCLaneScan.Result());
        return "";
    }

    void set(double steeringValue, double cruise, boolean brakeForObstacles) {
        steering = SCDriveControl.clampSteering(steeringValue);
        cruiseKmh = SCDriveControl.clampCruise(cruise);
        autoBrake = brakeForObstacles;
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
        float halfWidth = DEFAULT_HALF_WIDTH;
        float halfLength = DEFAULT_HALF_LENGTH;
        VehicleScript script = current.getScript();
        Vector3f extents = script == null ? null : script.getExtents();
        if (extents != null && extents.x > 0.5f && extents.z > 1.0f) {
            halfWidth = extents.x * 0.5f;
            halfLength = extents.z * 0.5f;
        }
        // Physics forward is (x, z); world y grows south like physics z.
        return SCLaneScan.scan(new WorldView(current), current.getX(), current.getY(),
                (int) Math.floor(current.getZ()), forward.x, forward.z,
                halfWidth, halfLength + 0.1f, lookAhead);
    }

    /** The loaded world as the lane scan sees it, ignoring the scanning car. */
    private static final class WorldView implements SCLaneScan.World {
        private final BaseVehicle self;
        private final IsoCell cell;

        WorldView(BaseVehicle self) {
            this.self = self;
            this.cell = self.getCell();
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
