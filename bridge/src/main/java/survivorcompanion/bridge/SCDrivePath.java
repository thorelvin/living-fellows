// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/**
 * A road route as a polyline a car can follow: the expedition planner's points
 * with each road's width. Distances run along the line from its first point.
 * Lateral offsets are measured to the right of the direction of travel, so a
 * positive offset is the right-hand lane. Uses no game types.
 */
final class SCDrivePath {
    static final int MAX_POINTS = 512;
    static final int MAX_TEXT = 65536;
    static final int MAX_CORNER_POINTS = 1024;

    /** Native script dimensions are already scaled; no modelScale is applied. */
    record CornerProfile(boolean keepRight, float halfWidth, float halfLength,
                         float wheelbase, float maxSpeed, float steeringClamp, float cornerKmh) {
        float minimumRadius() {
            if (!(Float.isFinite(wheelbase) && wheelbase >= halfLength * 0.8f
                    && wheelbase <= halfLength * 1.5f && maxSpeed >= 20 && maxSpeed <= 300
                    && steeringClamp >= 0.05f && steeringClamp <= 0.9f
                    && Float.isFinite(cornerKmh) && cornerKmh > 0)) return 4;
            float clamp = steeringClamp + (0.9f - steeringClamp)
                    * (1 - Math.min(1, cornerKmh / maxSpeed));
            return 1.25f * wheelbase / (float) Math.tan(clamp);
        }

        float steeringWheelbase() {
            return Float.isFinite(wheelbase) && wheelbase > 0.5f && wheelbase < 8 ? wheelbase : 2.6f;
        }
    }

    record Corner(int id, float start, float end, float angle, float radius,
                  boolean arc, String sharpReason) { }
    /** Points closer than this to the previous one are dropped. */
    private static final float MIN_SPACING = 0.5f;
    private static final float MAX_COORDINATE = 30000.0f;
    private static final float MAX_WIDTH = 64.0f;

    private final float[] xs;
    private final float[] ys;
    private final float[] widths;
    private final float[] cumulative;
    private final float length;
    private final SCDrivePath original;
    private final CornerProfile profile;
    private final Corner[] corners;
    private final float[] laneOffsets;
    private final float[] tangentX;
    private final float[] tangentY;
    private final int[] cornerIds;
    private final float[] originalAlong;
    private final boolean[] forcedSharp;
    private final float[] laneSegmentLengths;
    /**
     * Route points carry the width of the street they were reached on (the
     * road router and the Lua planner both write them that way). A reversed
     * route keeps its point widths, so each width then describes the leg that
     * leaves the point instead.
     */
    private final boolean widthsLeaveNode;
    /** Corner routes only: the lane of each straight segment, from the leg it lies on. */
    private final float[] straightLanes;

    private SCDrivePath(float[] xs, float[] ys, float[] widths) {
        this(xs, ys, widths, false);
    }

    private SCDrivePath(float[] xs, float[] ys, float[] widths, boolean widthsLeaveNode) {
        this(xs, ys, widths, null, null, new Corner[0], null, null, null, null, null, null,
                null, widthsLeaveNode);
    }

    SCDrivePath(float[] xs, float[] ys, float[] widths, SCDrivePath original,
                CornerProfile profile, Corner[] corners, float[] laneOffsets,
                float[] tangentX, float[] tangentY, int[] cornerIds,
                float[] originalAlong, boolean[] forcedSharp, float[] straightLanes) {
        this(xs, ys, widths, original, profile, corners, laneOffsets, tangentX, tangentY,
                cornerIds, originalAlong, forcedSharp, straightLanes,
                original != null && original.widthsLeaveNode);
    }

    private SCDrivePath(float[] xs, float[] ys, float[] widths, SCDrivePath original,
                        CornerProfile profile, Corner[] corners, float[] laneOffsets,
                        float[] tangentX, float[] tangentY, int[] cornerIds,
                        float[] originalAlong, boolean[] forcedSharp, float[] straightLanes,
                        boolean widthsLeaveNode) {
        this.widthsLeaveNode = widthsLeaveNode;
        this.straightLanes = straightLanes;
        this.xs = xs;
        this.ys = ys;
        this.widths = widths;
        this.cumulative = new float[xs.length];
        float total = 0.0f;
        for (int index = 1; index < xs.length; index++) {
            total += (float) Math.hypot(xs[index] - xs[index - 1], ys[index] - ys[index - 1]);
            cumulative[index] = total;
        }
        this.length = total;
        this.original = original;
        this.profile = profile;
        this.corners = corners;
        this.laneOffsets = laneOffsets;
        this.tangentX = tangentX;
        this.tangentY = tangentY;
        this.cornerIds = cornerIds;
        this.originalAlong = originalAlong;
        this.forcedSharp = forcedSharp;
        laneSegmentLengths = profile == null ? null : new float[xs.length - 1];
        if (laneSegmentLengths != null) {
            for (int i = 0; i < laneSegmentLengths.length; i++) {
                if (arcSegment(i)) {
                    float ax = xs[i] - tangentY[i] * laneOffsets[i];
                    float ay = ys[i] + tangentX[i] * laneOffsets[i];
                    float bx = xs[i + 1] - tangentY[i + 1] * laneOffsets[i + 1];
                    float by = ys[i + 1] + tangentX[i + 1] * laneOffsets[i + 1];
                    laneSegmentLengths[i] = (float) Math.hypot(bx - ax, by - ay);
                } else laneSegmentLengths[i] = cumulative[i + 1] - cumulative[i];
            }
        }
    }

    SCDrivePath withCorners(CornerProfile nextProfile) {
        return SCCornerPathBuilder.build(original(), nextProfile, null);
    }

    SCDrivePath sharpCorner(int id) {
        if (profile == null || id < 0 || id >= corners.length || forcedSharp[id]) return this;
        boolean[] sharp = forcedSharp.clone();
        sharp[id] = true;
        return SCCornerPathBuilder.build(original(), profile, sharp);
    }

    SCDrivePath original() { return original == null ? this : original; }
    boolean widthsLeaveNode() { return widthsLeaveNode; }
    CornerProfile cornerProfile() { return profile; }
    int corners() { return corners.length; }
    Corner corner(int id) { return corners[id]; }
    int cornersSharp() {
        int count = 0;
        for (Corner corner : corners) if (!corner.arc) count++;
        return count;
    }
    float x(int index) { return xs[index]; }
    float y(int index) { return ys[index]; }
    float width(int index) { return widths[index]; }
    float distance(int index) { return cumulative[index]; }

    float originalAlong(float along) {
        if (originalAlong == null) return along;
        return interpolate(originalAlong, along);
    }

    int segmentAtOriginalAlong(float value) {
        if (originalAlong == null) return segmentAt(value);
        return segmentAt(originalAlong, value);
    }

    float laneOffsetAt(float along) {
        int segment = segmentAt(along);
        if (arcSegment(segment)) return interpolate(laneOffsets, along);
        if (straightLanes != null) return straightLanes[segment];
        float width = Math.max(widths[segment], widths[segment + 1]);
        if (width <= 0) width = 6;
        return profile != null && profile.keepRight && width >= 6 ? width / 4 : 0;
    }

    /** Distances used for steering/braking are physical lane distances, not
     * the shorter/longer encoded centreline on left/right arcs. */
    float advanceInLane(float along, float distance, float deviation) {
        if (laneSegmentLengths == null) return Math.max(0, Math.min(length, along + distance));
        boolean forward = distance >= 0;
        float remaining = Math.abs(distance), at = Math.max(0, Math.min(length, along));
        int segment = segmentAt(at);
        while (remaining > 0.0001f && segment >= 0 && segment < xs.length - 1) {
            float span = cumulative[segment + 1] - cumulative[segment];
            float ratio = laneSegmentLengths[segment] / span;
            if (arcSegment(segment)) {
                Corner arc = corners[cornerIds[segment]];
                ratio *= Math.max(0.05f, 1 - Math.signum(arc.angle) * deviation / arc.radius);
            }
            float edge = forward ? cumulative[segment + 1] : cumulative[segment];
            float room = Math.abs(edge - at) * ratio;
            if (room >= remaining) return at + (forward ? 1 : -1) * remaining / ratio;
            remaining -= room; at = edge; segment += forward ? 1 : -1;
        }
        return at;
    }

    Corner arcAt(float along) {
        int first = 0, last = corners.length;
        while (first < last) {
            int mid = (first + last) >>> 1;
            if (corners[mid].start <= along) first = mid + 1; else last = mid;
        }
        if (first == 0) return null;
        Corner corner = corners[first - 1];
        return corner.arc && along <= corner.end ? corner : null;
    }

    private boolean arcSegment(int segment) {
        return cornerIds != null && cornerIds[segment] >= 0
                && cornerIds[segment] == cornerIds[segment + 1];
    }

    private static int segmentAt(float[] distances, float along) {
        int first = 1, last = distances.length - 1;
        while (first < last) {
            int mid = (first + last) >>> 1;
            if (distances[mid] <= along) first = mid + 1; else last = mid;
        }
        return first - 1;
    }

    private int segmentAt(float along) { return segmentAt(cumulative, along); }

    private float interpolate(float[] values, float along) {
        int segment = segmentAt(along);
        float span = cumulative[segment + 1] - cumulative[segment];
        float t = Math.max(0, Math.min(1, (along - cumulative[segment]) / span));
        return values[segment] + (values[segment + 1] - values[segment]) * t;
    }

    /**
     * Parses {@code "x,y,width;x,y,width;..."}. Width may be 0 when the map does
     * not know it. Returns null for anything malformed, out of range or shorter
     * than two distinct points.
     */
    static SCDrivePath parse(String text) {
        if (text == null || text.isEmpty() || text.length() > MAX_TEXT) return null;
        String[] items = text.split(";");
        if (items.length < 2 || items.length > MAX_POINTS) return null;
        float[] x = new float[items.length];
        float[] y = new float[items.length];
        float[] w = new float[items.length];
        int count = 0;
        for (String item : items) {
            String[] parts = item.split(",");
            if (parts.length != 3) return null;
            float px;
            float py;
            float pw;
            try {
                px = Float.parseFloat(parts[0].trim());
                py = Float.parseFloat(parts[1].trim());
                pw = Float.parseFloat(parts[2].trim());
            } catch (NumberFormatException invalid) {
                return null;
            }
            if (!(px >= 0.0f && px <= MAX_COORDINATE && py >= 0.0f && py <= MAX_COORDINATE
                    && pw >= 0.0f && pw <= MAX_WIDTH)) {
                return null;
            }
            if (count > 0 && Math.hypot(px - x[count - 1], py - y[count - 1]) < MIN_SPACING) {
                w[count - 1] = Math.max(w[count - 1], pw);
                continue;
            }
            x[count] = px;
            y[count] = py;
            w[count] = pw;
            count++;
        }
        if (count < 2) return null;
        return new SCDrivePath(java.util.Arrays.copyOf(x, count),
                java.util.Arrays.copyOf(y, count), java.util.Arrays.copyOf(w, count));
    }

    /** The same road driven the other way. */
    SCDrivePath reversed() {
        int count = xs.length;
        float[] x = new float[count];
        float[] y = new float[count];
        float[] w = new float[count];
        for (int index = 0; index < count; index++) {
            x[index] = xs[count - 1 - index];
            y[index] = ys[count - 1 - index];
            w[index] = widths[count - 1 - index];
        }
        return new SCDrivePath(x, y, w, !widthsLeaveNode);
    }

    float length() {
        return length;
    }

    /** Retain the driven trail, replacing its last body-length with a parking goal. */
    SCDrivePath stopBeforeEnd(float trim, float targetX, float targetY) {
        float end = Math.max(0.0f, length - trim);
        float[] x = new float[xs.length + 1];
        float[] y = new float[xs.length + 1];
        float[] w = new float[xs.length + 1];
        int count = 0;
        for (int index = 0; index < xs.length && cumulative[index] < end; index++) {
            x[count] = xs[index]; y[count] = ys[index]; w[count] = widths[index];
            count++;
        }
        if (count == 0) {
            x[0] = xs[0]; y[0] = ys[0]; w[0] = widths[0]; count = 1;
        }
        // A car already at the goal still needs a non-degenerate path. This
        // point is behind its current pose; no actor or vehicle is relocated.
        if (count == 1 && Math.hypot(x[0] - targetX, y[0] - targetY) < MIN_SPACING) {
            float dx = xs[xs.length - 1] - xs[xs.length - 2];
            float dy = ys[ys.length - 1] - ys[ys.length - 2];
            float span = (float) Math.hypot(dx, dy);
            x[0] = targetX - dx / span; y[0] = targetY - dy / span;
        }
        x[count] = targetX; y[count] = targetY; w[count] = widths[widths.length - 1];
        return new SCDrivePath(java.util.Arrays.copyOf(x, count + 1),
                java.util.Arrays.copyOf(y, count + 1), java.util.Arrays.copyOf(w, count + 1));
    }

    int points() {
        return xs.length;
    }

    /** The distance of the next corner after along, or MAX_VALUE past the last one. */
    float nextVertexAlong(float along) {
        int first = 1, last = cumulative.length - 1;
        while (first < last) {
            int mid = (first + last) >>> 1;
            if (cumulative[mid] <= along + 0.001f) first = mid + 1; else last = mid;
        }
        return first < cumulative.length - 1 ? cumulative[first] : Float.MAX_VALUE;
    }

    /** Where a point sits relative to the line: along it, and to the right of it. */
    static final class Projection {
        int segment;
        float along;
        float lateral;
    }

    /**
     * Projects a point onto the line, searching only a few segments around the
     * hint so a route that doubles back on itself is followed in order. A
     * negative hint searches every segment, for the first fix.
     */
    Projection project(float x, float y, int hintSegment, Projection out) {
        Projection result = out == null ? new Projection() : out;
        int segments = xs.length - 1;
        int first = hintSegment < 0 ? 0 : Math.max(0, Math.min(segments - 1, hintSegment) - 2);
        int last = hintSegment < 0 ? segments - 1
                : Math.min(segments - 1, Math.max(0, hintSegment) + 6);
        float bestDistance = Float.MAX_VALUE;
        for (int segment = first; segment <= last; segment++) {
            float ax = xs[segment];
            float ay = ys[segment];
            float dx = xs[segment + 1] - ax;
            float dy = ys[segment + 1] - ay;
            float span = dx * dx + dy * dy;
            float t = span > 0.0f ? ((x - ax) * dx + (y - ay) * dy) / span : 0.0f;
            float clamped = Math.max(0.0f, Math.min(1.0f, t));
            float px = ax + dx * clamped;
            float py = ay + dy * clamped;
            float distance = (x - px) * (x - px) + (y - py) * (y - py);
            if (distance < bestDistance) {
                bestDistance = distance;
                float segmentLength = (float) Math.sqrt(span);
                result.segment = segment;
                result.along = cumulative[segment] + clamped * segmentLength;
                if (segmentLength > 0.0f) {
                    // Right of travel: facing east (1,0) the right hand points south (0,1).
                    float rightX = -dy / segmentLength;
                    float rightY = dx / segmentLength;
                    result.lateral = (x - px) * rightX + (y - py) * rightY;
                } else {
                    result.lateral = 0.0f;
                }
            }
        }
        return result;
    }

    /**
     * The point at a distance along the line, shifted sideways by offset.
     * out receives x, y, the unit tangent (tx, ty) and the road width there.
     */
    void pointAt(float along, float offset, float[] out) {
        float distance = Math.max(0.0f, Math.min(length, along));
        int segment = segmentAt(distance);
        // At a corner itself the outgoing segment applies, so a scan starting there
        // runs down the new street rather than on past the junction.
        float ax = xs[segment];
        float ay = ys[segment];
        float dx = xs[segment + 1] - ax;
        float dy = ys[segment + 1] - ay;
        float segmentLength = (float) Math.sqrt(dx * dx + dy * dy);
        float t = segmentLength > 0.0f ? (distance - cumulative[segment]) / segmentLength : 0.0f;
        float tx = segmentLength > 0.0f ? dx / segmentLength : 1.0f;
        float ty = segmentLength > 0.0f ? dy / segmentLength : 0.0f;
        if (arcSegment(segment)) {
            tx = tangentX[segment] + (tangentX[segment + 1] - tangentX[segment]) * t;
            ty = tangentY[segment] + (tangentY[segment + 1] - tangentY[segment]) * t;
            float norm = (float) Math.hypot(tx, ty);
            tx /= norm; ty /= norm;
        }
        out[0] = ax + dx * t - ty * offset;
        out[1] = ay + dy * t + tx * offset;
        out[2] = tx;
        out[3] = ty;
        out[4] = arcSegment(segment) ? widths[segment] + (widths[segment + 1] - widths[segment]) * t
                : Math.max(widths[segment], widths[segment + 1]);
    }
}
