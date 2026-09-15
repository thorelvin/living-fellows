// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.worldMap.streets.WorldMapStreet;
import zombie.worldMap.streets.WorldMapStreets;
import zombie.worldMap.streets.WorldMapStreetsV1;

/**
 * Nearest named map street to a world point.
 *
 * Build 42 exposes the Lua street API (WorldMapStreetsV1) but not the
 * WorldMapStreets data files behind it, so every Lua call on a street file
 * fails. This walks them on the Java side and returns plain values. The walk is
 * bounded by the loaded street files, per-file and per-street caps, and a
 * distance cap that also prunes streets by their bounding box.
 */
public final class SCStreetLookup {
    static final int MAX_DATA_FILES = 128;
    static final int MAX_STREETS_PER_FILE = 65536;
    static final int MAX_POINTS_PER_STREET = 4096;
    static final double DEFAULT_MAX_DISTANCE = 300.0;

    private SCStreetLookup() {}

    /** One street polyline, as read from the game or supplied by a test. */
    interface Street {
        String name();
        float minX();
        float minY();
        float maxX();
        float maxY();
        int pointCount();
        float pointX(int index);
        float pointY(int index);
    }

    private static final class Match {
        String name;
        double distanceSq;
        double x;
        double y;
    }

    private static final class NativeStreet implements Street {
        private final WorldMapStreet street;

        NativeStreet(WorldMapStreet street) { this.street = street; }

        public String name() { return street.getTranslatedText(); }
        public float minX() { return street.getMinX(); }
        public float minY() { return street.getMinY(); }
        public float maxX() { return street.getMaxX(); }
        public float maxY() { return street.getMaxY(); }
        public int pointCount() { return street.getNumPoints(); }
        public float pointX(int index) { return street.getPointX(index); }
        public float pointY(int index) { return street.getPointY(index); }
    }

    /** "name\tdistance\tx\ty" for the nearest street in the map's data, or null. */
    static String nearest(Object streetsApi, double worldX, double worldY, double maxDistance) {
        if (!(streetsApi instanceof WorldMapStreetsV1 api)) return null;
        if (!Double.isFinite(worldX) || !Double.isFinite(worldY)) return null;
        Match best = new Match();
        best.distanceSq = limitSq(maxDistance);
        try {
            int files = Math.min(MAX_DATA_FILES, Math.max(0, api.getStreetDataCount()));
            for (int file = 0; file < files; file++) {
                WorldMapStreets data = api.getStreetDataByIndex(file);
                if (data == null) continue;
                int streets = Math.min(MAX_STREETS_PER_FILE, Math.max(0, data.getStreetCount()));
                for (int index = 0; index < streets; index++) {
                    WorldMapStreet street = data.getStreetByIndex(index);
                    if (street != null) consider(new NativeStreet(street), worldX, worldY, best);
                }
            }
        } catch (RuntimeException | LinkageError failure) {
            return null;
        }
        return format(best);
    }

    /** The same search over supplied streets; used by the deterministic test. */
    static String nearestIn(Iterable<? extends Street> streets, double worldX, double worldY,
            double maxDistance) {
        if (streets == null || !Double.isFinite(worldX) || !Double.isFinite(worldY)) return null;
        Match best = new Match();
        best.distanceSq = limitSq(maxDistance);
        for (Street street : streets) {
            if (street != null) consider(street, worldX, worldY, best);
        }
        return format(best);
    }

    private static double limitSq(double maxDistance) {
        double limit = Double.isFinite(maxDistance) && maxDistance > 0.0
                ? maxDistance : DEFAULT_MAX_DISTANCE;
        return limit * limit;
    }

    private static void consider(Street street, double x, double y, Match best) {
        String name = street.name();
        if (name == null || name.isBlank()) return;
        double minX = street.minX(), minY = street.minY();
        double maxX = street.maxX(), maxY = street.maxY();
        double dx = x < minX ? minX - x : x > maxX ? x - maxX : 0.0;
        double dy = y < minY ? minY - y : y > maxY ? y - maxY : 0.0;
        if (dx * dx + dy * dy > best.distanceSq) return;
        int points = Math.min(MAX_POINTS_PER_STREET, Math.max(0, street.pointCount()));
        boolean hasPrevious = false;
        double previousX = 0.0, previousY = 0.0;
        for (int index = 0; index < points; index++) {
            double pointX = street.pointX(index), pointY = street.pointY(index);
            if (!Double.isFinite(pointX) || !Double.isFinite(pointY)) continue;
            double closestX = pointX, closestY = pointY;
            if (hasPrevious) {
                double segmentX = pointX - previousX, segmentY = pointY - previousY;
                double lengthSq = segmentX * segmentX + segmentY * segmentY;
                double factor = lengthSq > 0.0
                        ? ((x - previousX) * segmentX + (y - previousY) * segmentY) / lengthSq
                        : 0.0;
                factor = Math.max(0.0, Math.min(1.0, factor));
                closestX = previousX + factor * segmentX;
                closestY = previousY + factor * segmentY;
            }
            double offsetX = x - closestX, offsetY = y - closestY;
            double distanceSq = offsetX * offsetX + offsetY * offsetY;
            if (distanceSq < best.distanceSq) {
                best.distanceSq = distanceSq;
                best.name = name.trim();
                best.x = closestX;
                best.y = closestY;
            }
            previousX = pointX;
            previousY = pointY;
            hasPrevious = true;
        }
    }

    private static String format(Match best) {
        if (best.name == null) return null;
        return best.name.replace('\t', ' ') + "\t" + Math.sqrt(best.distanceSq)
                + "\t" + best.x + "\t" + best.y;
    }
}
