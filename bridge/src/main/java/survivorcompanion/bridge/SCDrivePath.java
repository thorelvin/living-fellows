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
    /** Points closer than this to the previous one are dropped. */
    private static final float MIN_SPACING = 0.5f;
    private static final float MAX_COORDINATE = 30000.0f;
    private static final float MAX_WIDTH = 64.0f;

    private final float[] xs;
    private final float[] ys;
    private final float[] widths;
    private final float[] cumulative;
    private final float length;

    private SCDrivePath(float[] xs, float[] ys, float[] widths) {
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
        return new SCDrivePath(x, y, w);
    }

    float length() {
        return length;
    }

    int points() {
        return xs.length;
    }

    /** The distance of the next corner after along, or MAX_VALUE past the last one. */
    float nextVertexAlong(float along) {
        for (int index = 1; index < cumulative.length - 1; index++) {
            if (cumulative[index] > along + 0.001f) return cumulative[index];
        }
        return Float.MAX_VALUE;
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
        int segment = 0;
        // At a corner itself the outgoing segment applies, so a scan starting there
        // runs down the new street rather than on past the junction.
        while (segment < xs.length - 2 && cumulative[segment + 1] <= distance) segment++;
        float ax = xs[segment];
        float ay = ys[segment];
        float dx = xs[segment + 1] - ax;
        float dy = ys[segment + 1] - ay;
        float segmentLength = (float) Math.sqrt(dx * dx + dy * dy);
        float t = segmentLength > 0.0f ? (distance - cumulative[segment]) / segmentLength : 0.0f;
        float tx = segmentLength > 0.0f ? dx / segmentLength : 1.0f;
        float ty = segmentLength > 0.0f ? dy / segmentLength : 0.0f;
        out[0] = ax + dx * t - ty * offset;
        out[1] = ay + dy * t + tx * offset;
        out[2] = tx;
        out[3] = ty;
        out[4] = Math.max(widths[segment], widths[segment + 1]);
    }
}
