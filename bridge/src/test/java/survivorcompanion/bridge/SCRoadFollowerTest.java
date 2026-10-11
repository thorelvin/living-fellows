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
        final Car car;
        final SCRoadFollower follower;
        final SCRoadFollower.Command command = new SCRoadFollower.Command();
        long nowMs;
        boolean collided;
        float maxAbsLateral;
        String trace = "";

        Drive(Road road, Car car, SCRoadFollower follower) {
            this.road = road;
            this.car = car;
            this.follower = follower;
        }

        void run(float seconds, java.util.function.BooleanSupplier until) {
            float dt = 1.0f / 30.0f;
            for (int frame = 0; frame < seconds / dt && !until.getAsBoolean(); frame++) {
                float fx = (float) Math.cos(car.heading);
                float fy = (float) Math.sin(car.heading);
                SCLaneScan.Result front = SCLaneScan.scan(road, car.x, car.y, 0, fx, fy,
                        Car.HALF_WIDTH, Car.HALF_LENGTH + 0.1f,
                        SCCompanionDriver.lookAheadFor(follower.cruiseKmh()));
                SCLaneScan.Result rear = SCLaneScan.scan(road, car.x, car.y, 0, -fx, -fy,
                        Car.HALF_WIDTH, Car.HALF_LENGTH + 0.1f, 4.0f);
                float frontDistance = front.blocked ? front.distance : -1.0f;
                float rearDistance = rear.blocked ? rear.distance : -1.0f;
                follower.update(road, car.x, car.y, 0, fx, fy, car.kmh(), Car.HALF_WIDTH,
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
                if (car.collides(road)) {
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
        road.clear(30, 33, 95, 106);
        drive.run(60.0f, () -> follower.mode() == SCRoadFollower.Mode.ARRIVED);
        require(!drive.collided && follower.mode() == SCRoadFollower.Mode.ARRIVED,
                "once the block is gone the car drives on");
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

    public static void main(String[] args) {
        pathBasics();
        reverseRules();
        clearRoad();
        oneWreck();
        twoWrecks();
        blockedRoad();
        turnRound();
        personInLane();
        tooNarrowToTurn();
        System.out.println("ROAD_FOLLOWER_PASS checks=" + checks);
    }
}
