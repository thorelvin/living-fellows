// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.HashMap;
import java.util.HashSet;

/** Low-speed cruise rules and the lane scan, against a synthetic grid. */
public final class SCCompanionDrivingTest {
    private static int checks;

    private static void require(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }

    /** A flat, loaded grid with chosen obstacles and walls. */
    private static final class Grid implements SCLaneScan.World {
        final HashMap<Long, Integer> kinds = new HashMap<>();
        final HashSet<String> walls = new HashSet<>();
        final HashSet<Long> unloaded = new HashSet<>();
        final HashMap<Long, Integer> queries = new HashMap<>();

        static long key(int x, int y) {
            return ((long) x << 32) ^ (y & 0xffffffffL);
        }

        Grid put(int x, int y, int kind) {
            kinds.put(key(x, y), kind);
            return this;
        }

        Grid wall(int fromX, int fromY, int toX, int toY) {
            walls.add(fromX + "," + fromY + ">" + toX + "," + toY);
            return this;
        }

        @Override
        public int squareKind(int x, int y, int z) {
            queries.merge(key(x, y), 1, Integer::sum);
            if (unloaded.contains(key(x, y))) return SCLaneScan.UNLOADED;
            return kinds.getOrDefault(key(x, y), SCLaneScan.CLEAR);
        }

        @Override
        public boolean edgeBlocked(int fromX, int fromY, int toX, int toY, int z) {
            return walls.contains(fromX + "," + fromY + ">" + toX + "," + toY);
        }
    }

    private static void cruiseRules() {
        require(SCDriveControl.clampCruise(Double.NaN) == 0.0f
                        && SCDriveControl.clampCruise(-5) == 0.0f
                        && SCDriveControl.clampCruise(0) == 0.0f,
                "NaN, negative and zero cruise all mean stop");
        require(SCDriveControl.clampCruise(1) == SCDriveControl.MIN_CRUISE_KMH,
                "a tiny cruise request still moves the car");
        require(SCDriveControl.clampCruise(12) == 12.0f,
                "a low cruise speed is kept as asked");
        require(SCDriveControl.clampCruise(99) == SCDriveControl.MAX_CRUISE_KMH
                        && SCDriveControl.MAX_CRUISE_KMH <= 25.0f,
                "companion cruise never exceeds the low-speed ceiling");
        require(SCDriveControl.clampSteering(Double.NaN) == 0.0f
                        && SCDriveControl.clampSteering(2) == 1.0f
                        && SCDriveControl.clampSteering(-3) == -1.0f
                        && SCDriveControl.clampSteering(0.25) == 0.25f,
                "steering is held to the key range and NaN steers straight");

        SCDriveControl.Input start = SCDriveControl.cruise(0.0f, 10.0f, 0.3f, -1.0f);
        require(start.forward() && !start.brake() && !start.backward()
                        && start.steering() == 0.3f,
                "a stopped car with a cruise speed presses the gas and keeps its steering");
        SCDriveControl.Input band = SCDriveControl.cruise(10.0f, 10.0f, 0.0f, -1.0f);
        require(!band.forward() && !band.brake(),
                "at the cruise speed the car coasts with no pedal");
        SCDriveControl.Input fast = SCDriveControl.cruise(14.5f, 10.0f, 0.0f, -1.0f);
        require(fast.brake() && !fast.forward(),
                "well over the cruise speed the car brakes");
        SCDriveControl.Input stopping = SCDriveControl.cruise(8.0f, 0.0f, 0.0f, -1.0f);
        require(stopping.brake() && !stopping.forward(),
                "a stop request brakes a rolling car");
        SCDriveControl.Input parked = SCDriveControl.cruise(0.2f, 0.0f, 0.0f, -1.0f);
        require(!parked.brake() && !parked.forward() && !parked.backward(),
                "a stopped car holds with no pedal, so game speed is not locked to 1x");
        SCDriveControl.Input rollingBack = SCDriveControl.cruise(-2.0f, 10.0f, 0.0f, -1.0f);
        require(rollingBack.brake() && !rollingBack.forward(),
                "a car rolling backwards brakes before it drives on");
        SCDriveControl.Input unknownSpeed = SCDriveControl.cruise(Float.NaN, 10.0f, 0.0f, -1.0f);
        require(unknownSpeed.brake() && !unknownSpeed.forward(),
                "an unreadable speed brakes");

        require(SCDriveControl.stoppingDistance(0.0f) == 1.5f
                        && SCDriveControl.stoppingDistance(10.0f) > SCDriveControl.stoppingDistance(0.0f)
                        && SCDriveControl.stoppingDistance(25.0f) > SCDriveControl.stoppingDistance(10.0f),
                "stopping distance grows with speed");
        float atTen = SCDriveControl.stoppingDistance(10.0f);
        SCDriveControl.Input close = SCDriveControl.cruise(10.0f, 10.0f, 0.0f, atTen - 0.5f);
        require(close.brake() && !close.forward(),
                "an obstacle inside the stopping distance brakes a rolling car");
        SCDriveControl.Input far = SCDriveControl.cruise(0.0f, 10.0f, 0.0f, atTen + 6.0f);
        require(far.forward(), "an obstacle well ahead does not stop the car");
        SCDriveControl.Input creep = SCDriveControl.cruise(0.0f, 10.0f, 0.0f,
                SCDriveControl.HOLD_GAP_TILES - 0.2f);
        require(!creep.forward() && !creep.brake(),
                "a stopped car does not creep closer than the hold gap");
        require(SCCompanionDriver.lookAheadFor(25.0f) > SCDriveControl.stoppingDistance(25.0f)
                        && SCCompanionDriver.lookAheadFor(0.0f) >= 8.0f,
                "the lane scan always looks further than the car needs to stop");
    }

    private static void laneScan() {
        // A car centred at (100.5, 100.5) facing east, 2 wide and 4.8 long.
        Grid open = new Grid();
        SCLaneScan.Result clear = SCLaneScan.scan(open, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(!clear.blocked && clear.leftDistance < 0 && clear.centerDistance < 0
                        && clear.rightDistance < 0,
                "an open road scans clear on all three rays");
        int distinct = open.queries.size();
        boolean once = open.queries.values().stream().allMatch(count -> count == 1);
        require(once && distinct > 0 && clear.squaresChecked == distinct,
                "each square is read from the world at most once per scan");

        Grid wreck = new Grid().put(108, 100, SCLaneScan.VEHICLE);
        SCLaneScan.Result ahead = SCLaneScan.scan(wreck, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(ahead.blocked && ahead.kind == SCLaneScan.VEHICLE
                        && ahead.hitX == 108 && ahead.hitY == 100
                        && ahead.distance >= 4.6f && ahead.distance <= 5.6f
                        && ahead.centerDistance >= 0,
                "a wreck in the lane is found at its distance from the bumper: " + ahead.distance);

        // Facing east the right hand points south (+y).
        Grid rightOnly = new Grid().put(106, 101, SCLaneScan.TREE);
        SCLaneScan.Result right = SCLaneScan.scan(rightOnly, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(right.blocked && right.kind == SCLaneScan.TREE
                        && right.rightDistance >= 0 && right.leftDistance < 0
                        && right.centerDistance < 0,
                "a tree beside the right fender is caught by the right ray only");

        // Facing north the right hand points east (+x).
        Grid northRight = new Grid().put(51, 46, SCLaneScan.SOLID);
        SCLaneScan.Result north = SCLaneScan.scan(northRight, 50.5f, 50.5f, 0, 0.0f, -1.0f,
                1.0f, 2.4f, 10.0f);
        require(north.blocked && north.rightDistance >= 0 && north.leftDistance < 0,
                "left and right follow the car's heading, not the map");

        Grid fence = new Grid().wall(104, 100, 105, 100);
        SCLaneScan.Result walled = SCLaneScan.scan(fence, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(walled.blocked && walled.kind == SCLaneScan.WALL && walled.hitX == 105,
                "a wall between two clear squares blocks the lane");

        Grid edge = new Grid();
        edge.unloaded.add(Grid.key(107, 100));
        SCLaneScan.Result unloaded = SCLaneScan.scan(edge, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(unloaded.blocked && unloaded.kind == SCLaneScan.UNLOADED,
                "an unloaded square ahead counts as blocked");

        Grid person = new Grid().put(104, 100, SCLaneScan.CHARACTER);
        SCLaneScan.Result walker = SCLaneScan.scan(person, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(walker.blocked && walker.kind == SCLaneScan.CHARACTER,
                "a person or zombie in the lane blocks it");

        Grid nearest = new Grid().put(109, 100, SCLaneScan.VEHICLE).put(105, 101, SCLaneScan.TREE);
        SCLaneScan.Result both = SCLaneScan.scan(nearest, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(both.blocked && both.kind == SCLaneScan.TREE && both.hitX == 105,
                "the nearest hit on any ray wins");

        Grid distant = new Grid().put(140, 100, SCLaneScan.VEHICLE);
        SCLaneScan.Result capped = SCLaneScan.scan(distant, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 100.0f);
        require(!capped.blocked, "the scan never looks past its bounded reach");

        SCLaneScan.Result noHeading = SCLaneScan.scan(open, 100.5f, 100.5f, 0, 0.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(noHeading.blocked && noHeading.distance == 0.0f,
                "without a heading the lane counts as blocked");
        SCLaneScan.Result noWorld = SCLaneScan.scan(null, 100.5f, 100.5f, 0, 1.0f, 0.0f,
                1.0f, 2.4f, 10.0f);
        require(noWorld.blocked, "without a world the lane counts as blocked");
        require("vehicle".equals(SCLaneScan.kindName(SCLaneScan.VEHICLE))
                        && "unknown".equals(SCLaneScan.kindName(99)),
                "obstacle kinds have stable names for Lua");
    }

    public static void main(String[] args) {
        cruiseRules();
        laneScan();
        System.out.println("COMPANION_DRIVING_PASS checks=" + checks);
    }
}
