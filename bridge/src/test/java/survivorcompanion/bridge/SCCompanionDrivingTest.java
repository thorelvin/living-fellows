// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.core.physics.CarController;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

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
        require(SCDriveControl.clampCruise(50) == 50.0f
                        && SCDriveControl.clampCruise(99) == 50.0f,
                "the native controller accepts a 50 km/h taxi request but no more");
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
                        && SCCompanionDriver.lookAheadFor(0.0f) >= 8.0f
                        && SCLaneScan.MAX_LOOK_AHEAD
                            >= SCCompanionDriver.lookAheadFor(50.0f),
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

        Grid stoppingRange = new Grid().put(150, 100, SCLaneScan.VEHICLE);
        SCLaneScan.Result visible = SCLaneScan.scan(stoppingRange,
                100.5f, 100.5f, 0, 1.0f, 0.0f, 1.0f, 2.4f, 100.0f);
        require(visible.blocked && visible.kind == SCLaneScan.VEHICLE,
                "a taxi at 50 km/h can see a vehicle inside its braking range");
        Grid distant = new Grid().put(170, 100, SCLaneScan.VEHICLE);
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

    private static void ramContact() {
        float[] body = {1.0f, 2.4f};
        // A car at (10, 10) facing east.
        require(SCCompanionDriver.touches(10.0f, 10.0f, 1.0f, 0.0f, body, 12.8f, 10.0f),
                "a zombie just past the front bumper is in contact");
        require(SCCompanionDriver.touches(10.0f, 10.0f, 1.0f, 0.0f, body, 10.0f, 11.4f),
                "a zombie against the side is in contact");
        require(!SCCompanionDriver.touches(10.0f, 10.0f, 1.0f, 0.0f, body, 13.2f, 10.0f)
                        && !SCCompanionDriver.touches(10.0f, 10.0f, 1.0f, 0.0f, body, 10.0f, 11.7f),
                "a zombie a little way off is not");
        require(SCCompanionDriver.touches(10.0f, 10.0f, 0.0f, -1.0f, body, 10.0f, 7.2f)
                        && !SCCompanionDriver.touches(10.0f, 10.0f, 0.0f, -1.0f, body, 12.8f, 10.0f),
                "contact follows the car's heading: facing north, the front is up the map");
        require(SCCompanionDriver.touches(100.0f, 100.9f, 1.0f, 0.0f,
                        body, 100.0f, 102.2f),
                "expanded side contact reaches the wall-separated zombie geometrically");
        SCCompanionDriver.ClearEdge wall = (fx, fy, tx, ty, z) ->
                !((fy == 101 && ty == 102) || (fy == 102 && ty == 101));
        require(!SCCompanionDriver.topologyClear(100.0f, 100.9f,
                        100.0f, 102.2f, 0, wall),
                "a wall between car and zombie vetoes the expanded contact");
        require(SCCompanionDriver.topologyClear(100.0f, 100.9f,
                        100.0f, 102.2f, 0, (fx, fy, tx, ty, z) -> true),
                "the same side contact remains valid with clear edges");
    }

    private static void hordeAvoidance() {
        HashMap<Long, Integer> zombies = new HashMap<>();
        SCHordeAvoidance.World world = (x, y, z) -> zombies.getOrDefault(Grid.key(x, y), 0);
        for (int x = 104; x <= 108; x++) zombies.put(Grid.key(x, 100), 1);
        require(!SCHordeAvoidance.ahead(world, 100.5f, 100.5f, 0, 1, 0, 1, 2.4f),
                "five zombies ahead remain driveable");
        zombies.put(Grid.key(109, 100), 1);
        require(SCHordeAvoidance.ahead(world, 100.5f, 100.5f, 0, 1, 0, 1, 2.4f),
                "six zombies in the approach trigger the route's obstacle avoidance");
        zombies.clear();
        zombies.put(Grid.key(95, 100), 12);
        zombies.put(Grid.key(106, 106), 12);
        require(!SCHordeAvoidance.ahead(world, 100.5f, 100.5f, 0, 1, 0, 1, 2.4f),
                "zombies behind or beside the route do not force a turn");
    }

    private static final class Vehicle extends BaseVehicle {
        final CarController controller = new CarController();
        IsoGameCharacter driver;
        IsoCell cell;

        @Override public IsoGameCharacter getDriver() { return driver; }
        @Override public IsoCell getCell() { return cell; }
        @Override public CarController getController() { return controller; }
        @Override public boolean isEngineRunning() { return true; }
        @Override public engineStateTypes getEngineState() { return engineStateTypes.Running; }
    }

    private static final class FloorSquare extends IsoGridSquare {
        boolean floor;
        boolean stopCar;
        String physicsShape;
        final zombie.core.properties.PropertyContainer properties = new zombie.core.properties.PropertyContainer() {
            @Override public boolean has(String name) { return "StopCar".equals(name) && stopCar; }
            @Override public String get(String name) { return "PhysicsShape".equals(name) ? physicsShape : null; }
        };
        FloorSquare(boolean floor) { super(null, null, 0, 0, 0); this.floor = floor; }
        @Override public boolean TreatAsSolidFloor() { return floor; }
        @Override public zombie.core.properties.PropertyContainer getProperties() { return properties; }
    }

    private static final class ParkingCell extends IsoCell {
        final FloorSquare ground = new FloorSquare(true);
        final FloorSquare selected = new FloorSquare(false);
        boolean missing;
        ParkingCell() { super(20, 20); }
        @Override public IsoGridSquare getGridSquare(int x, int y, int z) {
            return x == 55 && y == 100 ? missing ? null : selected : ground;
        }
    }

    private static void parkingGround() throws Exception {
        Vehicle vehicle = new Vehicle();
        ParkingCell cell = new ParkingCell();
        vehicle.cell = cell;
        var constructor = Class.forName(SCCompanionDriver.class.getName() + "$WorldView")
                .getDeclaredConstructor(BaseVehicle.class, boolean.class);
        constructor.setAccessible(true);
        SCLaneScan.World ordinary = (SCLaneScan.World) constructor.newInstance(vehicle, false);
        SCLaneScan.World parking = (SCLaneScan.World) constructor.newInstance(vehicle, true);
        require(ordinary.squareKind(55, 100, 0) == SCLaneScan.CLEAR
                        && parking.squareKind(55, 100, 0) == SCLaneScan.SOLID,
                "loaded floorless ground blocks only the new parking envelope, preserving ordinary road semantics");
        SCRoadFollower refused = new SCRoadFollower(SCDrivePath.parse("50,100,5;50,85,5"),
                4, false, true);
        require(!refused.beginParkingAlignment(parking, 50, 100, 0, 1, 0, 0,
                        0.95f, 2.4f, 0).isEmpty() && refused.turn() == null,
                "a loaded void in possible parking room refuses before any physical manoeuvre");
        cell.selected.floor = true;
        SCRoadFollower changed = new SCRoadFollower(SCDrivePath.parse("50,100,5;50,85,5"),
                4, false, true);
        require(changed.beginParkingAlignment(parking, 50, 100, 0, 1, 0, 0,
                        0.95f, 2.4f, 0).isEmpty(),
                "actual loaded ground admits the same parking room");
        cell.selected.floor = false;
        SCRoadFollower.Command command = changed.update(parking, 50, 100, 0, 1, 0, 0,
                0.95f, 2.4f, -1, -1, 100, null);
        require(changed.mode() == SCRoadFollower.Mode.TURN_FAILED && command.targetKmh == 0
                        && "parking_alignment_room_changed".equals(changed.turn().reason()),
                "ground disappearing during alignment brakes through the native dynamic room check");
        cell.missing = true;
        require(parking.squareKind(55, 100, 0) == SCLaneScan.UNLOADED,
                "an absent square remains an unloaded refusal rather than manufactured ground");
        cell.missing = false;
        cell.selected.floor = true;
        cell.selected.stopCar = true;
        require(ordinary.squareKind(55,100,0) == SCLaneScan.SOLID,
                "vehicle-only StopCar fixtures block a road scan without solid or tree flags");
        cell.selected.stopCar = false;
        cell.selected.physicsShape = "Tree";
        require(ordinary.squareKind(55,100,0) == SCLaneScan.SOLID,
                "tree-shaped pole physics also blocks before the bumper reaches it");
        cell.selected.physicsShape = null;
        require(ordinary.squareKind(55,100,0) == SCLaneScan.CLEAR,
                "removing the fixture restores ordinary drivable ground");
    }

    private static final class Table implements KahluaTable {
        final HashMap<Object, Object> values = new HashMap<>();
        @Override public Object rawget(Object key) { return values.get(key); }
        @Override public void rawset(Object key, Object value) { values.put(key, value); }
        @Override public void rawset(int key, Object value) { values.put(key, value); }
        @Override public void wipe() { values.clear(); }
    }

    @SuppressWarnings("unchecked")
    private static void playerBoardingAndStatus() throws Exception {
        IsoPlayer[] savedPlayers = IsoPlayer.players;
        boolean savedClient = GameClient.client;
        boolean savedServer = GameServer.server;
        var ownedField = SCBridge.class.getDeclaredField("OWNED");
        ownedField.setAccessible(true);
        Set<SCNativeCompanion> owned = (Set<SCNativeCompanion>) ownedField.get(null);
        SCNativeCompanion actor = new SCNativeCompanion(new SurvivorDesc(), null, 0, 0, 0);
        Vehicle vehicle = new Vehicle();
        vehicle.driver = actor;
        actor.setVehicleForTests(vehicle);
        owned.add(actor);
        try {
            IsoPlayer player = new IsoPlayer(null, new SurvivorDesc(), 0, 0, 0, false);
            IsoPlayer.players = new IsoPlayer[] {player, actor, null, null};
            require(!SCBridge.playerAboard(vehicle) && !SCBridge.playerAboard(null),
                    "an owned companion promoted to a player slot does not count as a passenger");
            player.setVehicleForTests(new Vehicle());
            require(!SCBridge.playerAboard(vehicle), "a real player in another car does not stop this one");
            GameClient.client = true;
            require(!SCBridge.driveStart(actor, true), "client multiplayer cannot take the wheel");
            GameClient.client = false;
            GameServer.server = true;
            require(!SCBridge.driveStart(actor, true), "server multiplayer cannot take the wheel");
            GameServer.server = false;
            require(SCBridge.driveStart(actor, true) && SCBridge.driveSet(actor, 0.4, 10, false),
                    "a seated owned companion can start an ordinary single-player drive");
            SCCompanionDriver driver = actor.companionDriver();
            require(!SCBridge.driveAlign(actor, Double.NaN, 10)
                            && !SCBridge.driveAlign(actor, 10, Double.POSITIVE_INFINITY)
                            && !SCBridge.driveAlign(actor, 30001, 10)
                            && !SCBridge.driveAlign(actor, 100, 100)
                            && driver.isActive() && driver.follower() == null,
                    "invalid and distant parking targets preserve the existing native owner without a turn");
            vehicle.driver = player;
            require(!SCBridge.driveAlign(actor, 0, 10) && driver.isActive(),
                    "parking alignment requires the exact current driver rather than a retained owner reference");
            vehicle.driver = actor;
            driver.beforeVehicleUpdate(actor, vehicle);
            require(driver.isActive() && vehicle.controller.clientControls.forward,
                    "the driving frame still runs with only the promoted owned companion aboard");

            player.setVehicleForTests(vehicle);
            require(SCBridge.playerAboard(vehicle), "a real player in any passenger seat is aboard");
            require(!SCBridge.driveAlign(actor, 0, 10) && driver.isActive(),
                    "a parking correction never grants the companion control with the main player aboard");
            driver.beforeVehicleUpdate(actor, vehicle);
            require(!driver.isActive() && "player_aboard".equals(driver.reason())
                            && "idle".equals(driver.state()) && driver.vehicle() == null
                            && vehicle.controller.parkCallsForTests == 1,
                    "the next driving frame releases and parks when a real player boards");
            CarController.ClientControls controls = vehicle.controller.clientControls;
            require(!controls.forward && !controls.backward && !controls.brake
                            && controls.steering == 0 && !controls.shift,
                    "player boarding clears all companion pedal and steering inputs");
            require(!SCBridge.driveStart(actor, true),
                    "the shared boarding rule also refuses a fresh drive with the player aboard");
            player.setVehicleForTests(null);
            owned.remove(actor);
            require(SCBridge.playerAboard(vehicle),
                    "an unowned companion instance in a player slot is not silently ignored");
            owned.add(actor);

            require(SCBridge.driveStart(actor, true)
                            && SCBridge.driveFollow(actor, "2,101,8;90,101,8", 10),
                    "the driver may take another route after the player leaves");
            Grid grid = new Grid();
            for (int y = 95; y <= 106; y++) grid.put(30, y, SCLaneScan.VEHICLE);
            SCRoadFollower follower = driver.follower();
            follower.update(grid, 18, 103, 0, 1, 0, 0, 0.95f, 2.4f,
                    -1, -1, 0, null);
            Table status = new Table();
            require(follower.mode() == SCRoadFollower.Mode.BLOCKED
                            && SCBridge.driveStatus(actor, status)
                            && status.rawget("blockedX") instanceof Double
                            && Math.abs((Double) status.rawget("blockedX") - 30) < 0.6
                            && (Double) status.rawget("blockedY") >= 95
                            && (Double) status.rawget("blockedY") < 107
                            && SCLaneScan.kindName(SCLaneScan.VEHICLE).equals(status.rawget("obstacleKind")),
                    "the Kahlua driver status carries the actual blocked cell and matching obstacle kind");
            require(SCBridge.driveStop(actor) && SCBridge.driveStatus(actor, status)
                            && status.rawget("blockedX") == null && status.rawget("blockedY") == null
                            && Boolean.FALSE.equals(status.rawget("active")),
                    "release clears route coordinates so the next job cannot reuse a stale block");
            require(!SCBridge.driveAlign(actor, 0, 10),
                    "an inactive native driver cannot start a parking alignment without its Lua owner reacquiring control");
        } finally {
            actor.companionDriver().stop(actor, "test_cleanup");
            owned.remove(actor);
            IsoPlayer.players = savedPlayers;
            GameClient.client = savedClient;
            GameServer.server = savedServer;
        }
    }

    public static void main(String[] args) throws Exception {
        cruiseRules();
        laneScan();
        ramContact();
        hordeAvoidance();
        parkingGround();
        playerBoardingAndStatus();
        System.out.println("COMPANION_DRIVING_PASS checks=" + checks);
    }
}
