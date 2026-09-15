// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.List;

/** Deterministic coverage for the Java-side nearest-street lookup. */
public final class SCStreetLookupTest {
    private SCStreetLookupTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static SCStreetLookup.Street street(String name, float... points) {
        float minX = Float.MAX_VALUE, minY = Float.MAX_VALUE;
        float maxX = -Float.MAX_VALUE, maxY = -Float.MAX_VALUE;
        for (int index = 0; index + 1 < points.length; index += 2) {
            minX = Math.min(minX, points[index]);
            maxX = Math.max(maxX, points[index]);
            minY = Math.min(minY, points[index + 1]);
            maxY = Math.max(maxY, points[index + 1]);
        }
        final float left = minX, top = minY, right = maxX, bottom = maxY;
        return new SCStreetLookup.Street() {
            public String name() { return name; }
            public float minX() { return left; }
            public float minY() { return top; }
            public float maxX() { return right; }
            public float maxY() { return bottom; }
            public int pointCount() { return points.length / 2; }
            public float pointX(int index) { return points[index * 2]; }
            public float pointY(int index) { return points[index * 2 + 1]; }
        };
    }

    public static void main(String[] arguments) {
        SCStreetLookup.Street far = street("Far Road", 50f, 50f, 100f, 50f);
        SCStreetLookup.Street knox = street("Knox Avenue", 0f, 5f, 10f, 5f);
        SCStreetLookup.Street unnamed = street("  ", 2f, 3f, 2f, 4f);

        String found = SCStreetLookup.nearestIn(List.of(far, knox, unnamed), 2.0, 2.0, 300.0);
        require("Knox Avenue\t3.0\t2.0\t5.0".equals(found),
                "nearest named street is chosen by polyline distance: " + found);
        require(SCStreetLookup.nearestIn(List.of(far), 2.0, 2.0, 10.0) == null,
                "streets beyond the distance cap are ignored");
        String single = SCStreetLookup.nearestIn(List.of(street("Tab\tRoad", 0f, 0f)),
                0.0, 1.0, 300.0);
        require(single != null && single.startsWith("Tab Road\t1.0\t"),
                "a one-point street is measured to its point and tabs are escaped: " + single);
        require(SCStreetLookup.nearestIn(List.of(knox), Double.NaN, 2.0, 300.0) == null,
                "a non-finite position finds nothing");
        require(SCStreetLookup.nearest(null, 1.0, 1.0, 300.0) == null
                        && SCStreetLookup.nearest("not a map", 1.0, 1.0, 300.0) == null,
                "only the map's streets API is accepted");
        System.out.println("NATIVE_STREET_LOOKUP_PASS");
    }
}
