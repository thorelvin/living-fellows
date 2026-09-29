// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.List;

/** Deterministic road-geometry and attachment checks, without a game world. */
public final class SCRoadRouterTest {
    private static int checks;

    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }

    private static SCRoadRouter.StreetLine line(String name, double... coordinates) {
        return wide(name, 0, coordinates);
    }

    private static SCRoadRouter.StreetLine wide(String name, double width,
                                                double... coordinates) {
        java.util.ArrayList<SCRoadRouter.Point> points = new java.util.ArrayList<>();
        for (int i = 0; i < coordinates.length; i += 2) {
            points.add(new SCRoadRouter.Point(coordinates[i], coordinates[i + 1]));
        }
        return new SCRoadRouter.StreetLine(name, points, width);
    }

    public static void main(String[] args) {
        var straight = SCRoadRouter.routeLines(
                List.of(line("Oak St", 0, 0, 100, 0)), 20, 0, 80, 0);
        check("READY".equals(straight.status())
                && Math.abs(straight.roadLength() - 60) < 0.001
                && straight.points().size() == 2,
                "same-edge attachments must use the partial edge, not its endpoints");

        var bend = SCRoadRouter.routeLines(List.of(
                line("Bent", 10, 10, 60, 10, 60, 60),
                line("Cross", 60, 40, 110, 40)), 10, 10, 110, 40);
        check("READY".equals(bend.status()) && bend.points().size() >= 4,
                "route preserves bend and T-junction geometry");
        check(bend.roadLength() > 100 && bend.roadLength() < 150,
                "distance follows road arcs rather than an endpoint chord");

        var disconnected = SCRoadRouter.routeLines(List.of(
                line("Same", 10, 10, 10, 100),
                line("Same", 200, 10, 200, 100)), 10, 40, 200, 40);
        check("NO_CONNECTED_ROUTE".equals(disconnected.status()),
                "matching names do not connect separate road islands");

        // Each piece lies beyond off-road reach of the other end.
        var missing = SCRoadRouter.routeLines(List.of(
                line("Gap", 10, 10, 160, 10, Double.NaN, 10, 160, 20, 310, 20)),
                10, 10, 310, 20);
        check("INCOMPLETE_MAP_DATA".equals(missing.status()),
                "invalid points break a polyline instead of inventing a span");

        var absent = SCRoadRouter.routeLines(List.of(), 10, 10, 100, 100);
        check("NO_ROAD_DATA".equals(absent.status()),
                "missing street metadata is not a traversable direct route");

        var network = List.of(
                line("Main", 10, 10, 60, 10, 110, 10),
                line("West", 10, 10, 10, 40),
                line("Bypass", 10, 40, 110, 40),
                line("East", 110, 40, 110, 10));
        var clear = SCRoadRouter.routeLines(network, 20, 10, 100, 10);
        var detour = SCRoadRouter.routeLinesAvoiding(network,
                20, 10, 100, 10, 60, 10, 8);
        check("READY".equals(clear.status()) && clear.roadLength() < 100,
                "unthreatened road uses the short main street");
        check("READY".equals(detour.status()) && detour.roadLength() > 100
                && detour.points().stream().anyMatch(point -> point.y() == 40),
                "a seen horde excludes local road edges and selects the connected bypass");
        check("READY".equals(SCRoadRouter.routeLines(network,
                20, 10, 100, 10).status()),
                "temporary avoidance never mutates the base street geometry");
        var noBypass = SCRoadRouter.routeLinesAvoiding(
                List.of(line("Only road", 10, 10, 60, 10, 110, 10)),
                20, 10, 100, 10, 60, 10, 8);
        check("NO_SAFE_ROAD_DETOUR".equals(noBypass.status()),
                "no alternate road must be reported rather than crossing the horde");
        var safeSide = SCRoadRouter.routeLinesAvoiding(
                List.of(line("Only road", 10, 10, 110, 10)),
                20, 10, 40, 10, 60, 10, 8);
        check("READY".equals(safeSide.status())
                && Math.abs(safeSide.roadLength() - 20) < 0.001,
                "a horde blocks only its edge interval, not the whole long street");

        // Riverside's Harbor St ends at y=5288, five tiles short of the centre
        // of the ten-wide W Main St at y=5283: map streets stop at the road edge.
        // Both ends lie beyond off-road reach of the other street, so only the
        // junction can connect them.
        var tee = SCRoadRouter.routeLines(List.of(
                wide("Main", 10, 0, 0, 400, 0),
                wide("Side", 8, 300, 5, 300, 300)), 20, 0, 300, 250);
        check("READY".equals(tee.status())
                && Math.abs(tee.roadLength() - 530) < 0.001,
                "a street ending at the joined road's edge connects to that road");
        check(tee.points().stream().anyMatch(point -> point.junction()
                    && Math.abs(point.x() - 300) < 0.001
                    && Math.abs(point.y()) < 0.001)
                && tee.points().stream().anyMatch(point -> point.width() == 8),
                "road output carries actual street width and traversed junctions");
        var apart = SCRoadRouter.routeLines(List.of(
                wide("Main", 10, 0, 0, 400, 0),
                wide("Side", 8, 300, 8, 300, 300)), 20, 0, 300, 250);
        check("NO_CONNECTED_ROUTE".equals(apart.status()),
                "a gap wider than the joined road's half-width stays disconnected");

        var farTarget = SCRoadRouter.routeLines(List.of(
                wide("Only road", 8, 0, 0, 200, 0)), 20, 0, 150, 80);
        check("READY".equals(farTarget.status())
                && Math.abs(farTarget.exitX() - 150) < 0.001
                && Math.abs(farTarget.exitY()) < 0.001
                && Math.abs(farTarget.roadLength() - 130) < 0.001,
                "a building 80 tiles off the road is reached by leaving the road beside it");
        var farSource = SCRoadRouter.routeLines(List.of(
                wide("Only road", 8, 0, 0, 200, 0)), 150, 80, 20, 0);
        check("READY".equals(farSource.status())
                && Math.abs(farSource.entryX() - 150) < 0.001,
                "the return from a building far off the road starts with the same off-road walk");
        check("NO_EXIT_CANDIDATE".equals(SCRoadRouter.routeLines(List.of(
                wide("Only road", 8, 0, 0, 200, 0)), 20, 0, 150, 120).status()),
                "off-road access stays bounded at 100 tiles");

        var preferRoad = SCRoadRouter.routeLines(List.of(
                wide("Main", 8, 0, 0, 100, 0),
                wide("Cross", 8, 100, 0, 100, 100)), 10, 0, 80, 70);
        check("READY".equals(preferRoad.status())
                && Math.abs(preferRoad.exitX() - 100) < 0.001
                && Math.abs(preferRoad.exitY() - 70) < 0.001,
                "the squad keeps to roads rather than leaving early for a longer walk");

        var roadNetwork = List.of(wide("Only road", 8, 0, 0, 200, 0));
        check("NO_SAFE_ROAD_DETOUR".equals(SCRoadRouter.routeLinesAvoiding(
                roadNetwork, 20, 0, 100, 60, 100, 30, 8).status()),
                "an off-road walk never crosses an observed horde");
        var clearWalk = SCRoadRouter.routeLinesAvoiding(
                roadNetwork, 20, 0, 160, 60, 100, 30, 8);
        check("READY".equals(clearWalk.status())
                && Math.abs(clearWalk.exitX() - 160) < 0.001,
                "a long off-road walk clear of the horde remains available");

        System.out.println("SC_ROAD_ROUTER_PASS checks=" + checks);
    }
}
