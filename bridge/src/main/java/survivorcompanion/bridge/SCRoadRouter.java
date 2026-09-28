// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.TreeMap;
import zombie.worldMap.streets.WorldMapStreet;
import zombie.worldMap.streets.WorldMapStreets;
import zombie.worldMap.streets.WorldMapStreetsV1;

/** A bounded, immutable road graph for one expedition's map region. */
final class SCRoadRouter {
    private static final int MAX_FILES = 128;
    private static final int MAX_STREETS_PER_FILE = 65536;
    private static final int MAX_POINTS_PER_STREET = 4096;
    private static final int MAX_TOTAL_POINTS = 100000;
    private static final int MAX_SEGMENTS = 4096;
    private static final int MAX_NODES = 8192;
    private static final int MAX_RESULT_POINTS = 512;
    private static final double REGION_MARGIN = 160.0;
    private static final double MAX_CONNECTOR = 45.0;
    private static final double MAX_AVOIDANCE_CONNECTOR = 24.0;
    private static final double EPSILON = 0.0001;

    private SCRoadRouter() {}

    record Point(double x, double y) {}
    record StreetLine(String name, List<Point> points) {}
    record Step(double x, double y, String street) {}
    record Result(String status, String reason, List<Step> points,
                  double roadLength, double entryX, double entryY,
                  double exitX, double exitY, int inferredJunctions,
                  int expandedNodes, String fingerprint) {
        static Result failure(String status, String reason) {
            return new Result(status, reason, List.of(), 0, 0, 0, 0, 0, 0, 0, "");
        }
    }
    private record Segment(int id, Point a, Point b, String name) {}
    private record Edge(int id, int from, int to, double length, String name,
                        boolean inferred) {}
    private record Link(int to, int edgeId, double length) {}
    private record Attachment(int edgeId, double t, Point point, double connector) {}
    private record Intersection(double firstT, double secondT, Point point,
                                boolean inferred) {}
    private record QueueEntry(int node, double cost) {}
    private record Avoidance(Point center, double radius) {}

    private static final class Graph {
        final List<Point> nodes = new ArrayList<>();
        final List<Edge> edges = new ArrayList<>();
        final List<List<Link>> links = new ArrayList<>();
        final Map<String, Integer> nodeIds = new HashMap<>();
        final String fingerprint;
        int inferredJunctions;
        int avoidedEdges;
        final Avoidance avoidance;

        Graph(String fingerprint, Avoidance avoidance) {
            this.fingerprint = fingerprint;
            this.avoidance = avoidance;
        }

        int node(Point point) {
            String key = Math.round(point.x * 1000) + ":" + Math.round(point.y * 1000);
            Integer existing = nodeIds.get(key);
            if (existing != null) return existing;
            int id = nodes.size();
            nodes.add(point);
            links.add(new ArrayList<>());
            nodeIds.put(key, id);
            return id;
        }

        void edge(Point a, Point b, String name, boolean inferred) {
            double length = distance(a, b);
            if (length <= EPSILON) return;
            if (avoidance != null && distance(avoidance.center,
                    new Point((a.x + b.x) * 0.5, (a.y + b.y) * 0.5))
                    < avoidance.radius - EPSILON) {
                avoidedEdges++;
                return;
            }
            int from = node(a), to = node(b);
            if (from == to) return;
            int id = edges.size();
            edges.add(new Edge(id, from, to, length, name, inferred));
            links.get(from).add(new Link(to, id, length));
            links.get(to).add(new Link(from, id, length));
        }
    }

    private static double distance(Point a, Point b) {
        return Math.hypot(a.x - b.x, a.y - b.y);
    }

    private static double segmentDistance(Point point, Point a, Point b) {
        double t = project(point, a, b);
        return distance(point, new Point(a.x + (b.x - a.x) * t,
                a.y + (b.y - a.y) * t));
    }

    private static void splitAvoidance(Segment segment, Avoidance avoidance,
                                       TreeMap<Double, Point> splits) {
        if (avoidance == null || segmentDistance(avoidance.center,
                segment.a, segment.b) > avoidance.radius) return;
        double dx = segment.b.x - segment.a.x;
        double dy = segment.b.y - segment.a.y;
        double fx = segment.a.x - avoidance.center.x;
        double fy = segment.a.y - avoidance.center.y;
        double a = dx * dx + dy * dy;
        double b = 2 * (fx * dx + fy * dy);
        double c = fx * fx + fy * fy
                - avoidance.radius * avoidance.radius;
        double discriminant = b * b - 4 * a * c;
        if (a <= EPSILON || discriminant <= EPSILON) return;
        double root = Math.sqrt(discriminant);
        double first = (-b - root) / (2 * a);
        double last = (-b + root) / (2 * a);
        if (first > EPSILON && first < 1 - EPSILON)
            splits.put(first, interpolate(segment, first));
        if (last > EPSILON && last < 1 - EPSILON)
            splits.put(last, interpolate(segment, last));
    }

    private static boolean finite(Point point) {
        return point != null && Double.isFinite(point.x) && Double.isFinite(point.y)
                && point.x >= 0 && point.y >= 0 && point.x <= 30000 && point.y <= 30000;
    }

    private static Point interpolate(Segment segment, double t) {
        return new Point(segment.a.x + (segment.b.x - segment.a.x) * t,
                segment.a.y + (segment.b.y - segment.a.y) * t);
    }

    private static double project(Point point, Point a, Point b) {
        double dx = b.x - a.x, dy = b.y - a.y;
        double lengthSq = dx * dx + dy * dy;
        if (lengthSq <= EPSILON) return 0;
        return Math.max(0, Math.min(1,
                ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSq));
    }

    private static Intersection intersection(Segment first, Segment second) {
        double rx = first.b.x - first.a.x, ry = first.b.y - first.a.y;
        double sx = second.b.x - second.a.x, sy = second.b.y - second.a.y;
        double denominator = rx * sy - ry * sx;
        if (Math.abs(denominator) <= EPSILON) return null;
        double qx = second.a.x - first.a.x, qy = second.a.y - first.a.y;
        double t = (qx * sy - qy * sx) / denominator;
        double u = (qx * ry - qy * rx) / denominator;
        if (t < -EPSILON || t > 1 + EPSILON
                || u < -EPSILON || u > 1 + EPSILON) return null;
        t = Math.max(0, Math.min(1, t));
        u = Math.max(0, Math.min(1, u));
        boolean endpoint = t < EPSILON || t > 1 - EPSILON
                || u < EPSILON || u > 1 - EPSILON;
        return new Intersection(t, u, interpolate(first, t), !endpoint);
    }

    private static List<Segment> segments(List<StreetLine> lines,
                                           Point source, Point target) {
        double minX = Math.min(source.x, target.x) - REGION_MARGIN;
        double minY = Math.min(source.y, target.y) - REGION_MARGIN;
        double maxX = Math.max(source.x, target.x) + REGION_MARGIN;
        double maxY = Math.max(source.y, target.y) + REGION_MARGIN;
        List<Segment> result = new ArrayList<>();
        for (StreetLine line : lines) {
            if (line == null || line.points == null) continue;
            Point previous = null;
            for (Point point : line.points) {
                if (!finite(point)) { previous = null; continue; }
                if (previous != null && distance(previous, point) > EPSILON
                        && Math.min(previous.x, point.x) <= maxX
                        && Math.max(previous.x, point.x) >= minX
                        && Math.min(previous.y, point.y) <= maxY
                        && Math.max(previous.y, point.y) >= minY) {
                    result.add(new Segment(result.size(), previous, point,
                            line.name == null ? "" : line.name));
                    if (result.size() > MAX_SEGMENTS) return null;
                }
                previous = point;
            }
        }
        return result;
    }

    private static Graph graph(List<Segment> segments, String fingerprint,
                               Avoidance avoidance) {
        List<TreeMap<Double, Point>> splits = new ArrayList<>();
        for (Segment segment : segments) {
            TreeMap<Double, Point> points = new TreeMap<>();
            points.put(0.0, segment.a);
            points.put(1.0, segment.b);
            splitAvoidance(segment, avoidance, points);
            splits.add(points);
        }
        Map<Long, List<Integer>> bins = new HashMap<>();
        Set<Long> compared = new HashSet<>();
        Graph graph = new Graph(fingerprint, avoidance);
        for (Segment segment : segments) {
            int minX = (int) Math.floor(Math.min(segment.a.x, segment.b.x) / 32);
            int maxX = (int) Math.floor(Math.max(segment.a.x, segment.b.x) / 32);
            int minY = (int) Math.floor(Math.min(segment.a.y, segment.b.y) / 32);
            int maxY = (int) Math.floor(Math.max(segment.a.y, segment.b.y) / 32);
            if ((long) (maxX - minX + 1) * (maxY - minY + 1) > 4096) return null;
            for (int bx = minX; bx <= maxX; bx++) {
                for (int by = minY; by <= maxY; by++) {
                    long cell = ((long) bx << 32) ^ (by & 0xffffffffL);
                    List<Integer> prior = bins.computeIfAbsent(cell, ignored -> new ArrayList<>());
                    for (int otherId : prior) {
                        long pair = ((long) otherId << 32) | segment.id;
                        if (!compared.add(pair)) continue;
                        Intersection crossing = intersection(segments.get(otherId), segment);
                        if (crossing != null) {
                            splits.get(otherId).put(crossing.firstT, crossing.point);
                            splits.get(segment.id).put(crossing.secondT, crossing.point);
                            if (crossing.inferred) graph.inferredJunctions++;
                        }
                    }
                    prior.add(segment.id);
                }
            }
        }
        for (Segment segment : segments) {
            Point previous = null;
            for (Point point : splits.get(segment.id).values()) {
                if (previous != null) graph.edge(previous, point, segment.name, false);
                previous = point;
            }
        }
        return graph.nodes.size() > MAX_NODES ? null : graph;
    }

    private static List<Attachment> attachments(Graph graph, Point point,
                                                 double maxConnector) {
        List<Attachment> all = new ArrayList<>();
        for (Edge edge : graph.edges) {
            Point a = graph.nodes.get(edge.from), b = graph.nodes.get(edge.to);
            double t = project(point, a, b);
            Point projected = new Point(a.x + (b.x - a.x) * t,
                    a.y + (b.y - a.y) * t);
            double connector = distance(point, projected);
            if (connector <= maxConnector) {
                all.add(new Attachment(edge.id, t, projected, connector));
            }
        }
        all.sort(Comparator.comparingDouble(Attachment::connector));
        return all.size() <= 8 ? all : new ArrayList<>(all.subList(0, 8));
    }

    private static boolean likelyMissingConnector(List<Segment> segments) {
        for (int i = 0; i < segments.size(); i++) {
            Segment first = segments.get(i);
            if (first.name.isBlank()) continue;
            for (int j = i + 1; j < segments.size(); j++) {
                Segment second = segments.get(j);
                if (!first.name.equals(second.name)) continue;
                double gap = Math.min(Math.min(distance(first.a, second.a),
                        distance(first.a, second.b)),
                        Math.min(distance(first.b, second.a),
                                distance(first.b, second.b)));
                if (gap > EPSILON && gap <= 24) return true;
            }
        }
        return false;
    }

    static Result routeLines(List<StreetLine> lines, double sx, double sy,
                             double tx, double ty) {
        return routeLines(lines, sx, sy, tx, ty, null);
    }

    static Result routeLinesAvoiding(List<StreetLine> lines, double sx, double sy,
                                     double tx, double ty, double avoidX,
                                     double avoidY, double avoidRadius) {
        Point center = new Point(avoidX, avoidY);
        if (!finite(center) || !Double.isFinite(avoidRadius)
                || avoidRadius < 4 || avoidRadius > 32)
            return Result.failure("INVALID_REQUEST", "invalid_avoidance");
        return routeLines(lines, sx, sy, tx, ty,
                new Avoidance(center, avoidRadius));
    }

    private static Result routeLines(List<StreetLine> lines, double sx, double sy,
                             double tx, double ty, Avoidance avoidance) {
        Point source = new Point(sx, sy), target = new Point(tx, ty);
        if (!finite(source) || !finite(target))
            return Result.failure("INVALID_REQUEST", "invalid_coordinates");
        List<Segment> raw = segments(lines, source, target);
        if (raw == null) return Result.failure("BUDGET_EXCEEDED", "segment_limit");
        if (raw.isEmpty()) return Result.failure("NO_ROAD_DATA", "no_street_segments");
        long hash = 1469598103934665603L;
        for (Segment segment : raw) {
            hash = (hash ^ Double.doubleToLongBits(segment.a.x)) * 1099511628211L;
            hash = (hash ^ Double.doubleToLongBits(segment.a.y)) * 1099511628211L;
            hash = (hash ^ Double.doubleToLongBits(segment.b.x)) * 1099511628211L;
            hash = (hash ^ Double.doubleToLongBits(segment.b.y)) * 1099511628211L;
        }
        Graph graph = graph(raw, Long.toUnsignedString(hash, 16), avoidance);
        if (graph == null) return Result.failure("BUDGET_EXCEEDED", "graph_limit");
        if (graph.edges.isEmpty() && avoidance != null)
            return Result.failure("NO_SAFE_ROAD_DETOUR", "horde_avoidance_blocked");
        double connectorLimit = avoidance == null
                ? MAX_CONNECTOR : MAX_AVOIDANCE_CONNECTOR;
        List<Attachment> entries = attachments(graph, source, connectorLimit);
        List<Attachment> exits = attachments(graph, target, connectorLimit);
        if (entries.isEmpty()) return Result.failure(avoidance == null
                ? "NO_ENTRY_CANDIDATE" : "NO_SAFE_ROAD_DETOUR", "road_too_far");
        if (exits.isEmpty()) return Result.failure(avoidance == null
                ? "NO_EXIT_CANDIDATE" : "NO_SAFE_ROAD_DETOUR", "road_too_far");

        int count = graph.nodes.size();
        double[] cost = new double[count];
        int[] previous = new int[count], previousEdge = new int[count], entry = new int[count];
        Arrays.fill(cost, Double.POSITIVE_INFINITY);
        Arrays.fill(previous, -1);
        Arrays.fill(previousEdge, -1);
        Arrays.fill(entry, -1);
        PriorityQueue<QueueEntry> queue = new PriorityQueue<>(
                Comparator.comparingDouble(QueueEntry::cost));
        for (int i = 0; i < entries.size(); i++) {
            Attachment candidate = entries.get(i);
            Edge edge = graph.edges.get(candidate.edgeId);
            int[] ends = { edge.from, edge.to };
            double[] lengths = { candidate.t * edge.length,
                    (1 - candidate.t) * edge.length };
            for (int side = 0; side < 2; side++) {
                double next = candidate.connector + lengths[side];
                if (next < cost[ends[side]]) {
                    cost[ends[side]] = next;
                    entry[ends[side]] = i;
                    queue.add(new QueueEntry(ends[side], next));
                }
            }
        }
        int expanded = 0;
        while (!queue.isEmpty()) {
            QueueEntry current = queue.poll();
            if (current.cost > cost[current.node] + EPSILON) continue;
            if (++expanded > MAX_NODES) return Result.failure("BUDGET_EXCEEDED", "search_limit");
            for (Link link : graph.links.get(current.node)) {
                double next = current.cost + link.length;
                if (next + EPSILON < cost[link.to]) {
                    cost[link.to] = next;
                    previous[link.to] = current.node;
                    previousEdge[link.to] = link.edgeId;
                    entry[link.to] = entry[current.node];
                    queue.add(new QueueEntry(link.to, next));
                }
            }
        }
        double best = Double.POSITIVE_INFINITY;
        int bestNode = -1, bestEntry = -1, bestExit = -1;
        boolean direct = false;
        for (int j = 0; j < exits.size(); j++) {
            Attachment exit = exits.get(j);
            Edge edge = graph.edges.get(exit.edgeId);
            int[] ends = { edge.from, edge.to };
            double[] lengths = { exit.t * edge.length,
                    (1 - exit.t) * edge.length };
            for (int side = 0; side < 2; side++) {
                double total = cost[ends[side]] + lengths[side] + exit.connector;
                if (total < best) {
                    best = total; bestNode = ends[side]; bestEntry = entry[bestNode];
                    bestExit = j; direct = false;
                }
            }
            for (int i = 0; i < entries.size(); i++) {
                Attachment start = entries.get(i);
                if (start.edgeId != exit.edgeId) continue;
                double total = start.connector + exit.connector
                        + Math.abs(start.t - exit.t) * edge.length;
                if (total < best) {
                    best = total; bestNode = -1; bestEntry = i;
                    bestExit = j; direct = true;
                }
            }
        }
        if (bestEntry < 0 || bestExit < 0) {
            if (avoidance != null)
                return Result.failure("NO_SAFE_ROAD_DETOUR", "horde_avoidance_blocked");
            if (likelyMissingConnector(raw))
                return Result.failure("INCOMPLETE_MAP_DATA", "unnamed_or_missing_connector");
            return Result.failure("NO_CONNECTED_ROUTE", "disconnected_street_geometry");
        }
        Attachment start = entries.get(bestEntry), finish = exits.get(bestExit);
        List<Step> path = new ArrayList<>();
        path.add(new Step(start.point.x, start.point.y,
                graph.edges.get(start.edgeId).name));
        if (!direct) {
            List<Integer> reversed = new ArrayList<>();
            int cursor = bestNode;
            while (cursor >= 0 && reversed.size() <= MAX_RESULT_POINTS) {
                reversed.add(cursor);
                cursor = previous[cursor];
            }
            for (int index = reversed.size() - 1; index >= 0; index--) {
                int nodeId = reversed.get(index);
                Point point = graph.nodes.get(nodeId);
                int edgeId = previousEdge[nodeId];
                String street = edgeId < 0 ? graph.edges.get(start.edgeId).name
                        : graph.edges.get(edgeId).name;
                path.add(new Step(point.x, point.y, street));
            }
        }
        path.add(new Step(finish.point.x, finish.point.y,
                graph.edges.get(finish.edgeId).name));
        if (path.size() > MAX_RESULT_POINTS)
            return Result.failure("BUDGET_EXCEEDED", "route_payload_limit");
        return new Result("READY", "", List.copyOf(path),
                best - start.connector - finish.connector,
                start.point.x, start.point.y, finish.point.x, finish.point.y,
                graph.inferredJunctions, expanded, graph.fingerprint);
    }

    static Result routeNative(Object api, double sx, double sy, double tx, double ty) {
        return routeNative(api, sx, sy, tx, ty, null);
    }

    static Result routeNativeAvoiding(Object api, double sx, double sy,
                                      double tx, double ty, double avoidX,
                                      double avoidY, double avoidRadius) {
        Point center = new Point(avoidX, avoidY);
        if (!finite(center) || !Double.isFinite(avoidRadius)
                || avoidRadius < 4 || avoidRadius > 32)
            return Result.failure("INVALID_REQUEST", "invalid_avoidance");
        return routeNative(api, sx, sy, tx, ty,
                new Avoidance(center, avoidRadius));
    }

    private static Result routeNative(Object api, double sx, double sy,
                                      double tx, double ty, Avoidance avoidance) {
        if (!(api instanceof WorldMapStreetsV1 streets))
            return Result.failure("DATA_NOT_READY", "street_api_unavailable");
        List<StreetLine> lines = new ArrayList<>();
        int totalPoints = 0;
        try {
            int files = streets.getStreetDataCount();
            if (files <= 0) return Result.failure("DATA_NOT_READY", "street_data_pending");
            if (files > MAX_FILES) return Result.failure("BUDGET_EXCEEDED", "street_file_limit");
            for (int file = 0; file < files; file++) {
                WorldMapStreets data = streets.getStreetDataByIndex(file);
                if (data == null) continue;
                int count = data.getStreetCount();
                if (count > MAX_STREETS_PER_FILE)
                    return Result.failure("BUDGET_EXCEEDED", "street_count_limit");
                for (int index = 0; index < count; index++) {
                    WorldMapStreet street = data.getStreetByIndex(index);
                    if (street == null) continue;
                    int points = street.getNumPoints();
                    if (points > MAX_POINTS_PER_STREET)
                        return Result.failure("BUDGET_EXCEEDED", "street_point_limit");
                    totalPoints += Math.max(0, points);
                    if (totalPoints > MAX_TOTAL_POINTS)
                        return Result.failure("BUDGET_EXCEEDED", "street_data_limit");
                    List<Point> polyline = new ArrayList<>(Math.max(0, points));
                    for (int p = 0; p < points; p++) {
                        polyline.add(new Point(street.getPointX(p), street.getPointY(p)));
                    }
                    lines.add(new StreetLine(street.getUntranslatedText(), polyline));
                }
            }
        } catch (RuntimeException | LinkageError failure) {
            return Result.failure("DATA_NOT_READY", "street_read_failed");
        }
        return routeLines(lines, sx, sy, tx, ty, avoidance);
    }
}
