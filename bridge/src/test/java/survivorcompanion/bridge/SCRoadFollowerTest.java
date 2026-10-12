// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.HashMap;

/**
 * Route following, wreck avoidance and turning round, driven through the same
 * stack the bridge uses (SCRoadFollower, SCDriveControl, SCLaneScan) with a
 * simple bicycle-model car on a synthetic road. Real Build 42 physics differs;
 * the live -DrivingProbe -DrivingRoute run checks the real thing.
 */
public final class SCRoadFollowerTest {
    private static int checks;

    private static void require(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }

    /** Road y 97..104 (8 wide), grass shoulders, solid beyond, unloaded past the ends. */
    private static final class Road implements SCLaneScan.World {
        final HashMap<Long, Integer> kinds = new HashMap<>();
        /** First and last open row: the verges by default, the road alone when walled. */
        int firstOpen = 95;
        int lastOpen = 106;

        static long key(int x, int y) {
            return ((long) x << 32) ^ (y & 0xffffffffL);
        }

        Road block(int x0, int x1, int y0, int y1, int kind) {
            for (int x = x0; x <= x1; x++) {
                for (int y = y0; y <= y1; y++) kinds.put(key(x, y), kind);
            }
            return this;
        }

        Road clear(int x0, int x1, int y0, int y1) {
            for (int x = x0; x <= x1; x++) {
                for (int y = y0; y <= y1; y++) kinds.remove(key(x, y));
            }
            return this;
        }

        @Override
        public int squareKind(int x, int y, int z) {
            if (x < 0 || x >= 120) return SCLaneScan.UNLOADED;
            if (y < firstOpen || y > lastOpen) return SCLaneScan.SOLID;
            return kinds.getOrDefault(key(x, y), SCLaneScan.CLEAR);
        }

        @Override
        public boolean edgeBlocked(int fromX, int fromY, int toX, int toY, int z) {
            return false;
        }
    }

    /** Bicycle model: positive steering turns right, and reversing turns the other way. */
    private static final class Car {
        static final float WHEELBASE = 2.7f;
        static final float MAX_STEER = (float) Math.toRadians(32.0);
        static final float STEER_RATE = (float) Math.toRadians(90.0);
        static final float HALF_WIDTH = 0.95f;
        static final float HALF_LENGTH = 2.4f;
        float x;
        float y;
        float heading;
        float speed;
        float wheel;

        Car(float x, float y, float heading) {
            this.x = x;
            this.y = y;
            this.heading = heading;
        }

        float kmh() {
            return speed * 3.6f;
        }

        void step(SCDriveControl.Input input, float dt) {
            float wanted = input.steering() * MAX_STEER;
            float change = Math.max(-STEER_RATE * dt, Math.min(STEER_RATE * dt, wanted - wheel));
            wheel += change;
            if (input.brake()) {
                speed = approachZero(speed, 6.0f * dt);
            } else if (input.forward()) {
                speed = speed < -0.1f ? approachZero(speed, 6.0f * dt) : speed + 2.5f * dt;
            } else if (input.backward()) {
                speed = speed > 0.1f ? approachZero(speed, 6.0f * dt) : speed - 2.0f * dt;
            } else {
                speed = approachZero(speed, 1.0f * dt);
            }
            speed = Math.max(-6.0f / 3.6f, Math.min(25.0f / 3.6f, speed));
            heading += speed / WHEELBASE * (float) Math.tan(wheel) * dt;
            x += speed * (float) Math.cos(heading) * dt;
            y += speed * (float) Math.sin(heading) * dt;
        }

        static float approachZero(float value, float amount) {
            if (value > 0.0f) return Math.max(0.0f, value - amount);
            return Math.min(0.0f, value + amount);
        }

        boolean peopleCount;

        /** Any part of the body inside a blocking square. */
        boolean collides(SCLaneScan.World world) {
            float fx = (float) Math.cos(heading);
            float fy = (float) Math.sin(heading);
            for (int along = -2; along <= 2; along++) {
                for (int side = -1; side <= 1; side++) {
                    float px = x + fx * HALF_LENGTH * along / 2.0f - fy * HALF_WIDTH * side;
                    float py = y + fy * HALF_LENGTH * along / 2.0f + fx * HALF_WIDTH * side;
                    int kind = world.squareKind((int) Math.floor(px), (int) Math.floor(py), 0);
                    if (kind != SCLaneScan.CLEAR
                            && (kind != SCLaneScan.CHARACTER || peopleCount)) return true;
                }
            }
            return false;
        }
    }

    /** The bridge's per-frame loop, as SCCompanionDriver runs it. */
    private static final class Drive {
        final Road road;
        SCLaneScan.World world;
        final Car car;
        final SCRoadFollower follower;
        final SCRoadFollower.Command command = new SCRoadFollower.Command();
        long nowMs;
        boolean collided;
        float maxAbsLateral;
        String trace = "";

        Drive(Road road, Car car, SCRoadFollower follower) {
            this.road = road;
            this.world = road;
            this.car = car;
            this.follower = follower;
        }

        void run(float seconds, java.util.function.BooleanSupplier until) {
            float dt = 1.0f / 30.0f;
            for (int frame = 0; frame < seconds / dt && !until.getAsBoolean(); frame++) {
                float fx = (float) Math.cos(car.heading);
                float fy = (float) Math.sin(car.heading);
                SCLaneScan.Result front = SCLaneScan.scan(world, car.x, car.y, 0, fx, fy,
                        Car.HALF_WIDTH, Car.HALF_LENGTH + 0.1f,
                        SCCompanionDriver.lookAheadFor(follower.cruiseKmh()));
                SCLaneScan.Result rear = SCLaneScan.scan(world, car.x, car.y, 0, -fx, -fy,
                        Car.HALF_WIDTH, Car.HALF_LENGTH + 0.1f, 4.0f);
                float frontDistance = front.blocked ? front.distance : -1.0f;
                float rearDistance = rear.blocked ? rear.distance : -1.0f;
                follower.update(world, car.x, car.y, 0, fx, fy, car.kmh(), Car.HALF_WIDTH,
                        Car.HALF_LENGTH, frontDistance, rearDistance, nowMs, command);
                SCDriveControl.Input input = command.targetKmh < 0.0f
                        ? SCDriveControl.reverse(car.kmh(), -command.targetKmh, command.steering,
                                rearDistance)
                        : SCDriveControl.cruise(car.kmh(), command.targetKmh, command.steering,
                                frontDistance, command.maneuver
                                        ? SCDriveControl.MANEUVER_GAP_TILES
                                        : SCDriveControl.HOLD_GAP_TILES);
                car.step(input, dt);
                nowMs += (long) (dt * 1000.0f);
                if (car.collides(world)) {
                    collided = true;
                    trace = "collision at " + car.x + "," + car.y + " mode=" + follower.mode();
                    return;
                }
                if (follower.mode() == SCRoadFollower.Mode.FOLLOW) {
                    maxAbsLateral = Math.max(maxAbsLateral, Math.abs(follower.lateral()));
                }
            }
        }
    }

    private static final String ROUTE = "2,101,8;90,101,8";

    private static void pathBasics() {
        SCDrivePath path = SCDrivePath.parse("10,20,6;10.2,20,6;30,20,8;30,40,8");
        require(path != null && path.points() == 3 && Math.abs(path.length() - 40.0f) < 0.01f,
                "close points merge and the route length adds up");
        require(SCDrivePath.parse("10,20,6") == null && SCDrivePath.parse("a,b,c;1,2,3") == null
                        && SCDrivePath.parse("1,2;3,4") == null
                        && SCDrivePath.parse("-1,2,3;4,5,6") == null && SCDrivePath.parse(null) == null,
                "malformed or one-point routes are refused");
        SCDrivePath.Projection at = path.project(20.0f, 22.0f, -1, null);
        require(at.segment == 0 && Math.abs(at.along - 10.0f) < 0.01f
                        && Math.abs(at.lateral - 2.0f) < 0.01f,
                "facing east, a point to the south is on the right");
        float[] point = new float[5];
        path.pointAt(5.0f, 2.0f, point);
        require(Math.abs(point[0] - 15.0f) < 0.01f && Math.abs(point[1] - 22.0f) < 0.01f
                        && point[2] == 1.0f && point[4] == 8.0f,
                "a positive offset shifts the line to the right of travel");
        SCDrivePath back = path.reversed();
        SCDrivePath.Projection backAt = back.project(20.0f, 22.0f, -1, null);
        require(Math.abs(back.length() - path.length()) < 0.01f
                        && Math.abs(backAt.along - 30.0f) < 0.01f
                        && Math.abs(backAt.lateral + 2.0f) < 0.01f,
                "the reversed route runs the other way, so the same point is on the left");
    }

    private static Drive outbound(Road road) {
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(ROUTE), 10.0f, true);
        Drive drive = new Drive(road, new Car(6.0f, 103.0f, 0.0f), follower);
        drive.run(90.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        return drive;
    }

    private static void clearRoad() {
        Drive drive = outbound(new Road());
        require(!drive.collided && drive.follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && drive.follower.swerves() == 0
                        && Math.abs(drive.follower.lateral() - 2.0f) < 0.6f,
                "an open road is driven to the end in the right-hand lane: " + drive.trace
                        + " lateral=" + drive.follower.lateral());
    }

    private static void oneWreck() {
        Road road = new Road().block(24, 28, 102, 103, SCLaneScan.VEHICLE);
        Drive drive = outbound(road);
        require(!drive.collided && drive.follower.mode() == SCRoadFollower.Mode.ARRIVED,
                "a wreck in the lane is driven round without touching it: " + drive.trace);
        require(drive.follower.swerves() == 1 && Math.abs(drive.follower.lateral() - 2.0f) < 0.6f,
                "one wreck is one swerve, and the car is back in its lane at the end: swerves="
                        + drive.follower.swerves() + " lateral=" + drive.follower.lateral());
        require(drive.maxAbsLateral <= 5.0f,
                "the swerve stays on the road and its verge: " + drive.maxAbsLateral);
    }

    private static void twoWrecks() {
        Road road = new Road().block(24, 28, 102, 103, SCLaneScan.VEHICLE)
                .block(52, 56, 102, 103, SCLaneScan.VEHICLE);
        Drive drive = outbound(road);
        require(!drive.collided && drive.follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && drive.follower.swerves() == 2,
                "two wrecks far apart are two separate swerves with a return between: "
                        + drive.trace + " swerves=" + drive.follower.swerves());
    }

    private static void blockedRoad() {
        Road road = new Road().block(30, 33, 95, 106, SCLaneScan.VEHICLE);
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(ROUTE), 10.0f, true);
        Drive drive = new Drive(road, new Car(6.0f, 103.0f, 0.0f), follower);
        drive.run(30.0f, () -> false);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.BLOCKED
                        && Math.abs(drive.car.kmh()) < 0.6f && drive.car.x < 30.0f - 2.4f,
                "a road blocked edge to edge stops the car short of the block: " + drive.trace
                        + " mode=" + follower.mode() + " x=" + drive.car.x);
        require(follower.blockedX() >= 29.5f && follower.blockedX() <= 30.5f
                        && Math.abs(follower.blockedY() - 103.0f) < 0.01f,
                "a blocked route exposes the obstruction in world coordinates, not its distance: "
                        + follower.blockedX() + "," + follower.blockedY());
        road.clear(30, 33, 95, 106);
        drive.run(60.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED,
                "once the block is gone the car drives on");
    }

    private static void newRouteBehind() {
        String route = "90,101,8;2,101,8";
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(route), 10.0f, true);
        SCDrivePath newPath = follower.path();
        Drive drive = new Drive(new Road(), new Car(86.0f, 103.0f, 0.0f), follower);
        drive.run(0.1f, () -> false);
        require(follower.mode() == SCRoadFollower.Mode.TURNING && follower.turn() != null,
                "a new route behind a stopped car begins a bounded turn before pursuit");
        drive.run(120.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && drive.car.x < 6.0f && follower.path() == newPath,
                "the car turns onto the new route, keeps that route, and arrives untouched: "
                        + drive.trace + " mode=" + follower.mode() + " x=" + drive.car.x);

        SCRoadFollower rolling = new SCRoadFollower(SCDrivePath.parse(route), 10.0f, true);
        SCRoadFollower.Command command = rolling.update(new Road(), 70, 103, 0, 1, 0,
                5.0f, Car.HALF_WIDTH, Car.HALF_LENGTH, -1, -1, 0, null);
        require(rolling.turn() == null && command.targetKmh == 0.0f,
                "a rolling car brakes before a new backward route starts its turn");
        rolling.update(new Road(), 70, 103, 0, 1, 0, 2.9f,
                Car.HALF_WIDTH, Car.HALF_LENGTH, -1, -1, 1000, command);
        require(rolling.mode() == SCRoadFollower.Mode.TURNING,
                "the initial route alignment turn begins below three km/h");
        SCRoadFollower holding = new SCRoadFollower(SCDrivePath.parse(route), 0.0f, true);
        command = holding.update(new Road(), 70, 103, 0, 1, 0, 0,
                Car.HALF_WIDTH, Car.HALF_LENGTH, -1, -1, 0, null);
        require(holding.turn() == null && command.targetKmh == 0.0f,
                "a zero-cruise route holds even when it points behind the car");

        // A diagonal route needs its own direction, rather than a 180-degree flip.
        SCRoadFollower diagonal = new SCRoadFollower(
                SCDrivePath.parse("80,100,8;40,140,8"), 10.0f, true);
        diagonal.update(new Road(), 80, 100, 0, 1, 0, 0,
                Car.HALF_WIDTH, Car.HALF_LENGTH, -1, -1, 0, null);
        require(diagonal.turn() != null && Math.abs(SCTurnAround.wrap(
                        diagonal.turn().targetHeading() - (float) (3 * Math.PI / 4))) < 0.001f,
                "the initial turn targets the projected route's actual diagonal heading");

        SCRoadFollower ahead = new SCRoadFollower(SCDrivePath.parse(ROUTE), 10.0f, true);
        ahead.update(new Road(), 6, 103, 0, 1, 0, 0,
                Car.HALF_WIDTH, Car.HALF_LENGTH, -1, -1, 0, null);
        require(ahead.mode() == SCRoadFollower.Mode.FOLLOW && ahead.turn() == null,
                "a route already facing forward starts ordinary pursuit");
    }

    private static Drive turnAndReturn(boolean reverseWheelWrong) {
        Road road = new Road().block(24, 28, 102, 103, SCLaneScan.VEHICLE);
        Drive drive = outbound(road);
        SCRoadFollower follower = drive.follower;
        follower.beginTurn(drive.car.heading, -1, true);
        if (reverseWheelWrong) follower.turn().startWithReverseSign(-1.0f);
        // The outbound wreck is gone; two more sit in the lane for the way back.
        road.clear(24, 28, 102, 103).block(60, 64, 98, 99, SCLaneScan.VEHICLE)
                .block(30, 34, 98, 99, SCLaneScan.VEHICLE);
        drive.run(60.0f, () -> follower.mode() != SCRoadFollower.Mode.TURNING);
        return drive;
    }

    private static void turnRound() {
        Drive drive = turnAndReturn(false);
        SCRoadFollower follower = drive.follower;
        SCTurnAround turn = follower.turn();
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.FOLLOW
                        && turn.legs() <= SCTurnAround.MAX_LEGS && turn.legs() >= 2,
                "a three-point turn fits on the road and verge: " + drive.trace + " mode="
                        + follower.mode() + " legs=" + turn.legs() + " reason=" + turn.reason());
        require(Math.abs(SCTurnAround.wrap(drive.car.heading - (float) Math.PI))
                        <= SCTurnAround.DONE_ERROR + 0.02f,
                "after the turn the car faces back down the road: " + drive.car.heading);
        drive.run(120.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && drive.car.x < 6.0f && follower.swerves() == 2,
                "the car drives the route back, round two wrecks in its new lane: "
                        + drive.trace + " x=" + drive.car.x + " swerves=" + follower.swerves());
        Drive wrongWheel = turnAndReturn(true);
        require(!wrongWheel.collided
                        && wrongWheel.follower.mode() == SCRoadFollower.Mode.FOLLOW
                        && wrongWheel.follower.turn().reverseSign() > 0.0f,
                "a reverse wheel that turns the wrong way is noticed and flipped: "
                        + wrongWheel.trace + " mode=" + wrongWheel.follower.mode());
    }

    private static void reverseRules() {
        SCDriveControl.Input back = SCDriveControl.reverse(0.0f, 3.0f, 0.5f, -1.0f);
        require(back.backward() && !back.forward() && !back.brake() && back.steering() == 0.5f,
                "a stopped car reverses when asked");
        SCDriveControl.Input rollingOn = SCDriveControl.reverse(4.0f, 3.0f, 0.0f, -1.0f);
        require(rollingOn.brake() && !rollingOn.backward(),
                "a car still rolling forward brakes before it reverses");
        SCDriveControl.Input wall = SCDriveControl.reverse(-3.0f, 3.0f, 0.0f, 0.8f);
        require(wall.brake() && !wall.backward(),
                "reversing stops for something close behind");
        require(SCDriveControl.reverse(0.0f, 50.0f, 0.0f, -1.0f).backward()
                        && SCDriveControl.MAX_REVERSE_KMH <= 6.0f,
                "reversing stays slow whatever speed is asked");
    }

    /**
     * A junction: the main road (y 97..104, verges 95..106) meets a side
     * street (x 56..63, verges 54..65) that runs north or south from it.
     * Everything else is solid, so cutting a corner hits something.
     */
    private static final class Junction implements SCLaneScan.World {
        final boolean north;

        Junction(boolean north) {
            this.north = north;
        }

        @Override
        public int squareKind(int x, int y, int z) {
            if (x < 0 || x >= 120 || y < 0 || y >= 200) return SCLaneScan.UNLOADED;
            boolean main = y >= 95 && y <= 106 && x <= 65;
            boolean side = x >= 54 && x <= 65 && (north ? y <= 106 : y >= 95);
            return main || side ? SCLaneScan.CLEAR : SCLaneScan.SOLID;
        }

        @Override
        public boolean edgeBlocked(int fromX, int fromY, int toX, int toY, int z) {
            return false;
        }
    }

    private static void streetToStreet(boolean north) {
        Junction world = new Junction(north);
        String route = north ? "2,101,8;60,101,8;60,40,8" : "2,101,8;60,101,8;60,160,8";
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(route), 10.0f, true);
        Car car = new Car(6.0f, 103.0f, 0.0f);
        Drive drive = new Drive(null, car, follower);
        drive.world = world;
        drive.run(120.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        float wanted = north ? (float) (-Math.PI / 2.0) : (float) (Math.PI / 2.0);
        float endY = north ? 41.5f : 158.5f;
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && Math.abs(car.y - endY) < 3.0f
                        && Math.abs(SCTurnAround.wrap(car.heading - wanted)) < 0.35f,
                "the car turns " + (north ? "left" : "right") + " from one street into the next "
                        + "without touching the corner: " + drive.trace + " mode=" + follower.mode()
                        + " at " + car.x + "," + car.y + " heading=" + car.heading);
        require(Math.abs(follower.lateral() - 2.0f) < 0.8f,
                "after the turn it keeps to the right-hand lane of the new street: "
                        + follower.lateral());
    }

    private static void personInLane() {
        // Stopped with someone 2.5 tiles ahead: inside the cruise hold gap.
        Road road = new Road().block(30, 30, 102, 103, SCLaneScan.CHARACTER);
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(ROUTE), 10.0f, true);
        Car car = new Car(30.0f - Car.HALF_LENGTH - 2.5f, 103.0f, 0.0f);
        car.peopleCount = true;
        Drive drive = new Drive(road, car, follower);
        float startX = car.x;
        drive.run(10.0f, () -> false);
        require(!drive.collided && Math.abs(car.kmh()) < 0.6f && car.x - startX < 1.0f,
                "a car stopped close behind someone in the lane waits and never touches them: "
                        + drive.trace + " moved=" + (car.x - startX));
        road.clear(30, 30, 102, 103);
        drive.run(90.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED,
                "once they step aside the car drives on: " + drive.trace + " mode=" + follower.mode());
    }

    private static void tooNarrowToTurn() {
        Road road = new Road();
        road.firstOpen = 97;
        road.lastOpen = 104;
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(ROUTE), 10.0f, true);
        Drive drive = new Drive(road, new Car(6.0f, 103.0f, 0.0f), follower);
        drive.run(90.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        follower.beginTurn(drive.car.heading, -1, true);
        drive.run(120.0f, () -> follower.mode() != SCRoadFollower.Mode.TURNING);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.TURN_FAILED
                        && follower.turn().legs() > SCTurnAround.MAX_LEGS,
                "a road walled too tight to turn in fails the turn within its leg limit, untouched: "
                        + drive.trace + " mode=" + follower.mode() + " legs=" + follower.turn().legs());
    }

    private static void preciseParking() {
        String route = "12,101,5;25,101,5";
        SCRoadFollower edge = new SCRoadFollower(SCDrivePath.parse(route),
                5.0f, false, true);
        edge.update(new Road(), 24.15f, 101.70f, 0, 1.0f, 0.0f,
                0.0f, 1.0f, 2.4f, -1.0f, -1.0f, 1000L,
                new SCRoadFollower.Command());
        require(edge.mode() != SCRoadFollower.Mode.ARRIVED,
                "a stopped car outside the one-tile physical circle cannot report precise arrival");
        SCRoadFollower overshoot = new SCRoadFollower(SCDrivePath.parse(route),
                5.0f, false, true);
        overshoot.update(new Road(), 26.5f, 101.0f, 0, 1.0f, 0.0f,
                0.0f, 1.0f, 2.4f, -1.0f, -1.0f, 1000L,
                new SCRoadFollower.Command());
        require(overshoot.mode() != SCRoadFollower.Mode.ARRIVED,
                "projection clamping cannot hide a precise-arrival overshoot");
        SCRoadFollower follower = new SCRoadFollower(SCDrivePath.parse(route),
                5.0f, false, true);
        Drive drive = new Drive(new Road(), new Car(12.0f, 101.0f, 0.0f), follower);
        drive.run(90.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED
                        && Math.abs(drive.car.x - 25.0f) <= 0.9f
                        && Math.abs(drive.car.y - 101.0f) <= 0.75f,
                "precise parking reaches the bay without early road arrival: x="
                        + drive.car.x + " y=" + drive.car.y + " mode=" + follower.mode());
        Road obstructed = new Road().block(21, 25, 100, 102, SCLaneScan.VEHICLE);
        SCRoadFollower blocked = new SCRoadFollower(SCDrivePath.parse(route),
                5.0f, false, true);
        Drive stopped = new Drive(obstructed, new Car(12.0f, 101.0f, 0.0f), blocked);
        stopped.run(30.0f, () -> blocked.mode() == SCRoadFollower.Mode.BLOCKED);
        require(!stopped.collided && blocked.mode() == SCRoadFollower.Mode.BLOCKED
                        && blocked.swerves() == 0,
                "a blocked parking bay stops without swerving into another bay");
    }

    public static void main(String[] args) {
        pathBasics();
        reverseRules();
        clearRoad();
        oneWreck();
        twoWrecks();
        blockedRoad();
        newRouteBehind();
        turnRound();
        personInLane();
        tooNarrowToTurn();
        preciseParking();
        streetToStreet(true);
        streetToStreet(false);
        System.out.println("ROAD_FOLLOWER_PASS checks=" + checks);
    }
}
