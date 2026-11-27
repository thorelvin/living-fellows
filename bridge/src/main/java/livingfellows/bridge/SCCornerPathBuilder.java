// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.util.ArrayList;
import java.util.List;

/** One bounded, game-independent construction. A rejected corner retains its source points. */
final class SCCornerPathBuilder {
    private static final double LEG_BEND = Math.toRadians(3);
    private static final double MIN_BEND = Math.toRadians(12);
    private static final double MAX_BEND = Math.toRadians(150);
    private static final double STEP_ANGLE = Math.toRadians(10);
    private static final double EPS = 0.005;

    private record V(double x, double y) {
        V add(V b) { return new V(x + b.x, y + b.y); }
        V sub(V b) { return new V(x - b.x, y - b.y); }
        V mul(double s) { return new V(x * s, y * s); }
        V right() { return new V(-y, x); }
        double dot(V b) { return x * b.x + y * b.y; }
        double cross(V b) { return x * b.y - y * b.x; }
        double length() { return Math.hypot(x, y); }
        V unit() { return mul(1 / length()); }
    }

    private record Node(V point, float width, float lane, V tangent, int corner, float rootAlong) { }

    private static final class Bend {
        int id, first, last, inLimit, outLimit;
        V a, b, centerPoint;
        double angle, inWidth, outWidth, inOffset, outOffset;
        double radius, rootStart, rootEnd;
        String reason = "";
        List<Node> arc;
        int startNode, endNode;
    }

    private static V point(SCDrivePath path, int index) { return new V(path.x(index), path.y(index)); }
    private static V direction(SCDrivePath path, int segment) {
        return point(path, segment + 1).sub(point(path, segment)).unit();
    }
    private static double width(SCDrivePath path, int segment) {
        double w = Math.max(path.width(segment), path.width(segment + 1));
        return w > 0 ? w : 6;
    }

    /**
     * The width of the leg from point {@code segment} to the next one. Route
     * points carry the width of the street they were reached on, so a point
     * where the route turns describes the street before it, never the one
     * after it (a reversed route flips that). Every other leg keeps the
     * follower's wider-end rule, which the narrow Lua driveway and road-exit
     * points rely on. Arc ends then meet the straight beside them.
     */
    static double legWidth(SCDrivePath root, int segment, boolean[] turning) {
        boolean leaves = root.widthsLeaveNode();
        int carrier = leaves ? segment : segment + 1;
        int other = leaves ? segment + 1 : segment;
        if (turning[other]) return root.width(carrier) > 0 ? root.width(carrier) : 6;
        return width(root, segment);
    }

    private static double offset(double width, SCDrivePath.CornerProfile p) {
        return p.keepRight() && width >= 6 ? width / 4 : 0;
    }
    private static double angle(V a, V b) { return Math.atan2(a.cross(b), a.dot(b)); }
    private static V intersection(V p, V a, V q, V b) {
        double cross = a.cross(b);
        return Math.abs(cross) < 1e-8 ? null : p.add(a.mul(q.sub(p).cross(b) / cross));
    }
    private static double segmentDistance(V p, V a, V b) {
        V d = b.sub(a);
        double t = Math.max(0, Math.min(1, p.sub(a).dot(d) / d.dot(d)));
        return p.sub(a.add(d.mul(t))).length();
    }
    private static double sourceDistance(SCDrivePath root, V p, int first, int last) {
        double best = Double.POSITIVE_INFINITY;
        for (int i = first; i < last; i++) {
            best = Math.min(best, segmentDistance(p, point(root, i), point(root, i + 1)));
        }
        return best;
    }

    /** Points where the route changes direction by at least {@link #LEG_BEND}. */
    private static boolean[] turningPoints(SCDrivePath root) {
        boolean[] turning = new boolean[root.points()];
        for (int i = 1; i < root.points() - 1; i++) {
            turning[i] = Math.abs(angle(direction(root, i - 1), direction(root, i))) >= LEG_BEND;
        }
        return turning;
    }

    private static List<Bend> bends(SCDrivePath root, SCDrivePath.CornerProfile profile, boolean[] turning) {
        List<Integer> vertices = new ArrayList<>();
        for (int i = 1; i < root.points() - 1; i++) {
            if (turning[i]) vertices.add(i);
        }
        List<Bend> result = new ArrayList<>();
        for (int cursor = 0; cursor < vertices.size(); cursor++) {
            int first = vertices.get(cursor), last = first, lastCursor = cursor;
            V a = direction(root, first - 1), b = direction(root, first);
            double total = angle(a, b), maxWidth = Math.max(width(root, first - 1), width(root, first));
            for (int next = cursor + 1; next < vertices.size(); next++) {
                int vertex = vertices.get(next);
                double nextAngle = angle(direction(root, vertex - 1), direction(root, vertex));
                double nextWidth = Math.max(maxWidth, Math.max(width(root, vertex - 1), width(root, vertex)));
                if (Math.signum(nextAngle) != Math.signum(total)
                        || point(root, vertex).sub(point(root, first)).length() > nextWidth / 2 + 2) break;
                V outgoing = direction(root, vertex);
                V joined = intersection(point(root, first), a, point(root, vertex), outgoing);
                if (joined == null || sourceDistance(root, joined, first - 1, vertex + 1) > nextWidth / 2) break;
                for (int k = last + 1; k <= vertex; k++) total += angle(direction(root, k - 1), direction(root, k));
                maxWidth = nextWidth; last = vertex; b = outgoing; lastCursor = next;
            }
            if (Math.abs(total) >= MIN_BEND && Math.abs(total) <= MAX_BEND) {
                Bend bend = new Bend();
                bend.id = result.size(); bend.first = first; bend.last = last;
                bend.inLimit = cursor == 0 ? 0 : vertices.get(cursor - 1);
                bend.outLimit = lastCursor + 1 == vertices.size() ? root.points() - 1 : vertices.get(lastCursor + 1);
                bend.a = a; bend.b = b; bend.angle = total;
                // Read each leg from the point that describes it. The point
                // before a junction is often the previous junction (another
                // street) or a narrow driveway point, never this street.
                bend.inWidth = legWidth(root, first - 1, turning);
                bend.outWidth = legWidth(root, last, turning);
                bend.inOffset = offset(bend.inWidth, profile); bend.outOffset = offset(bend.outWidth, profile);
                bend.centerPoint = intersection(point(root, first), a, point(root, last), b);
                result.add(bend);
            }
            cursor = lastCursor;
        }
        return result;
    }

    /** Largest radius satisfying |C-K| <= R-clearance; the quadratic avoids a bad bisection bracket. */
    private static double kerbRadius(Bend bend, V laneCorner, double clearance) {
        V kerb = intersection(bend.centerPoint.add(bend.a.right().mul(bend.inWidth / 2)), bend.a,
                bend.centerPoint.add(bend.b.right().mul(bend.outWidth / 2)), bend.b);
        if (kerb == null) return 0;
        V d = laneCorner.sub(kerb);
        V v = bend.a.right().sub(bend.a.mul(Math.tan(Math.abs(bend.angle) / 2)));
        double aa = v.dot(v) - 1;
        double bb = 2 * (d.dot(v) + clearance);
        double cc = d.dot(d) - clearance * clearance;
        double discriminant = bb * bb - 4 * aa * cc;
        if (discriminant < 0 || aa < 1e-8) return 0;
        double radius = (-bb + Math.sqrt(discriminant)) / (2 * aa);
        return radius >= clearance ? Math.min(20, radius) : 0;
    }

    /** Independent side invariant, also exercised with deliberately off-side test points. */
    static boolean sideSafe(float x, float y, float originX, float originY,
                            float ax, float ay, float bx, float by,
                            float angle, float inWidth, float outWidth, boolean end) {
        V q = new V(x - originX, y - originY);
        double in = new V(-ay, ax).dot(q), out = new V(-by, bx).dot(q);
        if (angle > 0) return (inWidth < 6 || in >= -EPS) && (outWidth < 6 || out >= -EPS);
        // Past the crossing, the legal exit lane is naturally left of the
        // extended incoming line. Do not mistake that for oncoming traffic.
        boolean onExit = Math.abs(out) <= outWidth / 2 + 2 + EPS && q.dot(new V(bx, by)) >= -EPS;
        return !(inWidth >= 6 && in < -EPS && q.length() > Math.max(inWidth, outWidth) / 2 + 2 + EPS && !onExit)
                && (!end || outWidth < 6 || out >= -EPS);
    }

    private static void shape(SCDrivePath root, SCDrivePath.CornerProfile profile, Bend bend) {
        double minRadius = profile.minimumRadius();
        V laneCorner = intersection(point(root, bend.first).add(bend.a.right().mul(bend.inOffset)), bend.a,
                point(root, bend.last).add(bend.b.right().mul(bend.outOffset)), bend.b);
        if (laneCorner == null || bend.centerPoint == null) { bend.reason = "parallel"; return; }
        double tangent = Math.tan(Math.abs(bend.angle) / 2);
        double radius = bend.angle > 0 ? Math.max(minRadius,
                Math.min(Math.min(bend.inWidth, bend.outWidth) / 2,
                        kerbRadius(bend, laneCorner, profile.halfWidth() + 0.3)))
                : Math.max(minRadius, bend.outWidth / 2 + bend.inOffset);
        double shiftIn = laneCorner.sub(bend.a.right().mul(bend.inOffset)).sub(point(root, bend.first)).dot(bend.a);
        double shiftOut = laneCorner.sub(bend.b.right().mul(bend.outOffset)).sub(point(root, bend.last)).dot(bend.b);
        // Different lane widths can put their intersection beyond the source
        // vertex. The circle must still begin/end on the real incoming/outgoing
        // legs; increasing its radius avoids an artificial extra jog.
        radius = Math.max(radius, Math.max(shiftIn, -shiftOut) / tangent);
        double before = bend.inLimit == 0 ? 1
                : (root.distance(bend.inLimit) + root.distance(bend.first)) / 2;
        double after = bend.outLimit == root.points() - 1 ? root.length() - 2 - profile.halfLength()
                : (root.distance(bend.last) + root.distance(bend.outLimit)) / 2;
        radius = Math.min(radius, Math.min(root.distance(bend.first) + shiftIn - before,
                after - root.distance(bend.last) - shiftOut) / tangent);
        if (!(radius >= minRadius / 2)) { bend.reason = "short_leg"; return; }
        bend.radius = radius;
        bend.rootStart = root.distance(bend.first) + shiftIn - radius * tangent;
        bend.rootEnd = root.distance(bend.last) + shiftOut + radius * tangent;
        if (bend.rootStart > root.distance(bend.first) + EPS
                || bend.rootEnd < root.distance(bend.last) - EPS
                || bend.rootEnd <= bend.rootStart + 0.001) { bend.reason = "order"; return; }
        V start = laneCorner.sub(bend.a.mul(radius * tangent));
        double sign = Math.signum(bend.angle);
        V center = start.add(bend.a.right().mul(sign * radius));
        V radial = start.sub(center);
        int steps = Math.max(2, (int) Math.ceil(Math.abs(bend.angle) / STEP_ANGLE));
        List<Node> arc = new ArrayList<>();
        double maxWidth = Math.max(bend.inWidth, bend.outWidth);
        for (int i = 0; i <= steps; i++) {
            double t = (double) i / steps, rotation = bend.angle * t;
            double cos = Math.cos(rotation), sin = Math.sin(rotation);
            V q = center.add(new V(radial.x * cos - radial.y * sin, radial.x * sin + radial.y * cos));
            V direction = new V(bend.a.x * cos - bend.a.y * sin, bend.a.x * sin + bend.a.y * cos);
            double lane = bend.inOffset + (bend.outOffset - bend.inOffset) * t;
            V encoded = q.sub(direction.right().mul(lane));
            if (!(Double.isFinite(encoded.x) && Double.isFinite(encoded.y)
                    && encoded.x >= 0 && encoded.y >= 0 && encoded.x <= 30000 && encoded.y <= 30000)) {
                bend.reason = "numbers"; return;
            }
            if (sourceDistance(root, q, bend.inLimit, bend.outLimit) > maxWidth / 2 + 1 + EPS) {
                bend.reason = "corridor"; return;
            }
            if (!sideSafe((float) q.x, (float) q.y, (float) bend.centerPoint.x, (float) bend.centerPoint.y,
                    (float) bend.a.x, (float) bend.a.y, (float) bend.b.x, (float) bend.b.y,
                    (float) bend.angle, (float) bend.inWidth, (float) bend.outWidth, i == steps)) {
                bend.reason = "sides"; return;
            }
            if (!arc.isEmpty() && encoded.sub(arc.get(arc.size() - 1).point).length() < 0.25) {
                bend.reason = "spacing"; return;
            }
            arc.add(new Node(encoded, (float) (bend.inWidth + (bend.outWidth - bend.inWidth) * t),
                    (float) lane, direction, bend.id,
                    (float) (bend.rootStart + (bend.rootEnd - bend.rootStart) * t)));
        }
        double turn = angle(arc.get(0).tangent, arc.get(arc.size() - 1).tangent);
        if (Math.signum(turn) != sign || Math.abs(turn - bend.angle) > Math.toRadians(1)) {
            bend.reason = "turn"; return;
        }
        bend.arc = arc;
    }

    static SCDrivePath build(SCDrivePath root, SCDrivePath.CornerProfile profile, boolean[] marked) {
        if (profile == null) return root;
        boolean[] turning = turningPoints(root);
        List<Bend> bends = bends(root, profile, turning);
        if (bends.isEmpty()) return root;
        boolean[] forced = marked == null ? new boolean[bends.size()] : marked.clone();
        List<Node> nodes = new ArrayList<>();
        int cursor = 0;
        double usedUntil = -1;
        for (Bend bend : bends) {
            if (forced[bend.id]) bend.reason = "obstacle"; else shape(root, profile, bend);
            if (bend.arc != null) {
                int after = cursor;
                while (after < root.points() && root.distance(after) <= bend.rootEnd + EPS) after++;
                int before = cursor;
                while (before < root.points() && root.distance(before) < bend.rootStart - EPS) before++;
                double prevDistance = before > 0 ? root.distance(before - 1) : -1;
                double nextDistance = after < root.points() ? root.distance(after) : root.length() + 1;
                boolean spacing = bend.rootStart - prevDistance < 0.25
                        || nextDistance - bend.rootEnd < 0.25
                        || before > 0 && bend.arc.get(0).point.sub(point(root, before - 1)).length() < 0.25
                        || after < root.points() && bend.arc.get(bend.arc.size() - 1).point.sub(point(root, after)).length() < 0.25;
                if (bend.rootStart <= usedUntil || spacing
                        || nodes.size() + (before - cursor) + bend.arc.size() + root.points() - after
                                > SCDrivePath.MAX_CORNER_POINTS) {
                    bend.reason = spacing ? "join_spacing" : bend.rootStart <= usedUntil ? "order" : "budget";
                    bend.arc = null;
                } else {
                    while (cursor < before) { nodes.add(originalNode(root, cursor)); cursor++; }
                    bend.startNode = nodes.size();
                    nodes.addAll(bend.arc); bend.endNode = nodes.size() - 1;
                    cursor = after; usedUntil = bend.rootEnd;
                }
            }
        }
        while (cursor < root.points()) { nodes.add(originalNode(root, cursor)); cursor++; }
        int count = nodes.size();
        float[] x = new float[count], y = new float[count], width = new float[count], lane = new float[count];
        float[] tx = new float[count], ty = new float[count], originalAlong = new float[count], distance = new float[count];
        int[] ids = new int[count];
        for (int i = 0; i < count; i++) {
            Node node = nodes.get(i);
            x[i] = (float) node.point.x; y[i] = (float) node.point.y; width[i] = node.width;
            lane[i] = node.lane; ids[i] = node.corner; originalAlong[i] = node.rootAlong;
            tx[i] = node.tangent == null ? Float.NaN : (float) node.tangent.x;
            ty[i] = node.tangent == null ? Float.NaN : (float) node.tangent.y;
            if (i > 0) distance[i] = distance[i - 1] + (float) Math.hypot(x[i] - x[i - 1], y[i] - y[i - 1]);
        }
        SCDrivePath.Corner[] corners = new SCDrivePath.Corner[bends.size()];
        for (Bend bend : bends) {
            boolean arc = bend.arc != null;
            float start = arc ? distance[bend.startNode] : mapped(root.distance(bend.first), originalAlong, distance);
            float end = arc ? distance[bend.endNode] : mapped(root.distance(bend.last), originalAlong, distance);
            corners[bend.id] = new SCDrivePath.Corner(bend.id, start, end,
                    (float) bend.angle, (float) bend.radius, arc, bend.reason);
        }
        // Each straight segment takes the lane of the leg it lies on, by the
        // same rule as the arcs, so every arc meets the straight beside it,
        // including one that starts at a corner left sharp.
        float[] straight = new float[count - 1];
        for (int i = 0; i + 1 < count; i++) {
            if (ids[i] >= 0 && ids[i] == ids[i + 1]) { straight[i] = Float.NaN; continue; }
            int leg = root.segmentAtOriginalAlong((originalAlong[i] + originalAlong[i + 1]) / 2);
            straight[i] = (float) offset(legWidth(root, leg, turning), profile);
        }
        return new SCDrivePath(x, y, width, root, profile, corners, lane, tx, ty, ids, originalAlong, forced,
                straight);
    }

    private static Node originalNode(SCDrivePath root, int index) {
        return new Node(point(root, index), root.width(index), Float.NaN, null, -1, root.distance(index));
    }

    private static float mapped(float original, float[] originals, float[] distances) {
        for (int i = 1; i < originals.length; i++) {
            if (originals[i] >= original) {
                float t = (original - originals[i - 1]) / (originals[i] - originals[i - 1]);
                return distances[i - 1] + t * (distances[i] - distances[i - 1]);
            }
        }
        return distances[distances.length - 1];
    }
}
