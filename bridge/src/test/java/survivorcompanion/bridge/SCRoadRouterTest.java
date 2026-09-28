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
        java.util.ArrayList<SCRoadRouter.Point> points = new java.util.ArrayList<>();
        for (int i = 0; i < coordinates.length; i += 2) {
            points.add(new SCRoadRouter.Point(coordinates[i], coordinates[i + 1]));
        }
        return new SCRoadRouter.StreetLine(name, points);
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

        var missing = SCRoadRouter.routeLines(List.of(
                line("Gap", 10, 10, 60, 10, Double.NaN, 10, 60, 20, 110, 20)),
                10, 10, 110, 20);
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

        System.out.println("SC_ROAD_ROUTER_PASS checks=" + checks);
    }
}
