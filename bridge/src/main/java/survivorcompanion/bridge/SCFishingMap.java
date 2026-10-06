// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamConstants;
import javax.xml.stream.XMLStreamReader;

import zombie.ZomboidFileSystem;
import zombie.worldMap.WorldMap;
import zombie.worldMap.WorldMapData;

/** Read-only shoreline lookup from the map XML that matches terrain. */
final class SCFishingMap {
    private static final int CELL_SIZE = 300;
    private static final int EDGE_STEP = 10;
    private static final int GROUP_SIZE = 24;
    private static final int MAX_RADIUS = 1000;
    private static final int[][] DIRECTIONS = {
            { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }
    };
    private static final Map<Path, Map<Long, List<WaterPolygon>>> sourceCache =
            new HashMap<>();

    private record Point(int x, int y) {}
    private record Bank(int x, int y, long distanceSq) {}
    private record WaterPolygon(List<List<Point>> rings) {
        boolean contains(double x, double y) {
            boolean inside = false;
            for (List<Point> ring : rings) {
                int size = ring.size();
                for (int i = 0, j = size - 1; i < size; j = i++) {
                    Point a = ring.get(i), b = ring.get(j);
                    if ((a.y() > y) != (b.y() > y)
                            && x < (double) (b.x() - a.x()) * (y - a.y())
                                    / (b.y() - a.y()) + a.x()) inside = !inside;
                }
            }
            return inside;
        }
    }

    private SCFishingMap() {}

    private static long key(int x, int y) {
        return ((long) x << 32) | (y & 0xffffffffL);
    }

    private static String attribute(XMLStreamReader reader, String name) {
        return reader.getAttributeValue(null, name);
    }

    private static Map<Long, List<WaterPolygon>> readWater(Path file) {
        Map<Long, List<WaterPolygon>> cells = new HashMap<>();
        XMLInputFactory factory = XMLInputFactory.newFactory();
        factory.setProperty(XMLInputFactory.SUPPORT_DTD, false);
        factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES,
                false);
        try (InputStream input = Files.newInputStream(file)) {
            XMLStreamReader reader = factory.createXMLStreamReader(input);
            int cx = -1, cy = -1;
            boolean polygon = false, water = false;
            List<List<Point>> rings = null;
            List<Point> ring = null;
            try {
                while (reader.hasNext()) {
                    int event = reader.next();
                    if (event == XMLStreamConstants.START_ELEMENT) {
                        switch (reader.getLocalName()) {
                            case "cell" -> {
                                cx = Integer.parseInt(attribute(reader, "x"));
                                cy = Integer.parseInt(attribute(reader, "y"));
                            }
                            case "feature" -> {
                                polygon = false;
                                water = false;
                                rings = new ArrayList<>();
                            }
                            case "geometry" -> polygon = "Polygon".equals(
                                    attribute(reader, "type"));
                            case "coordinates" -> {
                                if (polygon) ring = new ArrayList<>();
                            }
                            case "point" -> {
                                if (ring != null) ring.add(new Point(
                                        Integer.parseInt(attribute(reader, "x")),
                                        Integer.parseInt(attribute(reader, "y"))));
                            }
                            case "property" -> {
                                if ("water".equals(attribute(reader, "name"))
                                        && attribute(reader, "value") != null) {
                                    water = true;
                                }
                            }
                            default -> { }
                        }
                    } else if (event == XMLStreamConstants.END_ELEMENT) {
                        switch (reader.getLocalName()) {
                            case "coordinates" -> {
                                if (ring != null && ring.size() >= 3) {
                                    rings.add(ring);
                                }
                                ring = null;
                            }
                            case "feature" -> {
                                if (cx >= 0 && cy >= 0 && polygon && water
                                        && rings != null && !rings.isEmpty()) {
                                    cells.computeIfAbsent(key(cx, cy),
                                            ignored -> new ArrayList<>())
                                            .add(new WaterPolygon(rings));
                                }
                                rings = null;
                            }
                            default -> { }
                        }
                    }
                }
            } finally {
                reader.close();
            }
        } catch (Exception failure) {
            throw new IllegalStateException("cannot read fishing map XML: "
                    + file.getFileName(), failure);
        }
        return cells;
    }

    private static List<Map<Long, List<WaterPolygon>>> sources(WorldMap world) {
        if (world == null) throw new IllegalStateException("world map missing");
        List<Map<Long, List<WaterPolygon>>> result = new ArrayList<>();
        for (WorldMapData data : world.data) {
            String name = data.relativeFileName;
            if (name == null || !name.replace('\\', '/').endsWith("/worldmap.xml")) {
                continue;
            }
            String resolved = ZomboidFileSystem.instance.getString(name);
            if (resolved == null || resolved.isBlank()) resolved = name;
            Path file = Path.of(resolved);
            if (!file.isAbsolute()) file = Path.of(System.getProperty("user.dir"),
                    resolved);
            file = file.normalize();
            if (Files.isRegularFile(file)) {
                result.add(sourceCache.computeIfAbsent(file,
                        SCFishingMap::readWater));
            }
        }
        if (result.isEmpty()) throw new IllegalStateException(
                "no readable fishing map XML");
        return result;
    }

    private static boolean waterAt(List<Map<Long, List<WaterPolygon>>> sources,
            int x, int y) {
        if (x < 0 || y < 0) return false;
        int cx = Math.floorDiv(x, CELL_SIZE);
        int cy = Math.floorDiv(y, CELL_SIZE);
        double localX = x - cx * CELL_SIZE + 0.5;
        double localY = y - cy * CELL_SIZE + 0.5;
        for (Map<Long, List<WaterPolygon>> source : sources) {
            List<WaterPolygon> polygons = source.get(key(cx, cy));
            if (polygons == null) continue;
            for (WaterPolygon polygon : polygons) {
                if (polygon.contains(localX, localY)) return true;
            }
        }
        return false;
    }

    private static boolean plausible(List<Map<Long, List<WaterPolygon>>> sources,
            int x, int y) {
        if (x < 0 || y < 0 || x > 30000 || y > 30000
                || waterAt(sources, x, y)) return false;
        for (int[] direction : DIRECTIONS) {
            if (waterAt(sources, x + direction[0] * 6,
                    y + direction[1] * 6)
                    && waterAt(sources, x + direction[0] * 9,
                            y + direction[1] * 9)) return true;
        }
        return false;
    }

    static boolean plausible(WorldMap world, int x, int y) {
        return plausible(sources(world), x, y);
    }

    /** x:y pairs, semicolon separated; Lua owns grouping with loaded banks. */
    static String candidates(WorldMap world, int ox, int oy, int radius) {
        if (radius < 1 || radius > MAX_RADIUS || ox < 0 || oy < 0) return "";
        List<Map<Long, List<WaterPolygon>>> sources = sources(world);
        int minCX = Math.max(0, Math.floorDiv(ox - radius, CELL_SIZE));
        int maxCX = Math.floorDiv(ox + radius, CELL_SIZE);
        int minCY = Math.max(0, Math.floorDiv(oy - radius, CELL_SIZE));
        int maxCY = Math.floorDiv(oy + radius, CELL_SIZE);
        long maxDistanceSq = (long) radius * radius;
        Map<Long, Bank> groups = new HashMap<>();
        for (int cx = minCX; cx <= maxCX; cx++) {
            for (int cy = minCY; cy <= maxCY; cy++) {
                for (Map<Long, List<WaterPolygon>> source : sources) {
                    List<WaterPolygon> polygons = source.get(key(cx, cy));
                    if (polygons == null) continue;
                    for (WaterPolygon polygon : polygons) {
                        for (List<Point> ring : polygon.rings()) {
                            for (int pi = 0; pi < ring.size(); pi++) {
                                Point a = ring.get(pi);
                                Point b = ring.get((pi + 1) % ring.size());
                                double ex = b.x() - a.x(), ey = b.y() - a.y();
                                double length = Math.hypot(ex, ey);
                                if (length <= 0) continue;
                                double nx = -ey / length, ny = ex / length;
                                int steps = (int) Math.ceil(length / EDGE_STEP);
                                for (int step = 0; step < steps; step++) {
                                    double t = (step + 0.5) / steps;
                                    double px = cx * CELL_SIZE + a.x() + ex * t;
                                    double py = cy * CELL_SIZE + a.y() + ey * t;
                                    for (int side = -1; side <= 1; side += 2) {
                                        int x = (int) Math.floor(px + nx * side * 4);
                                        int y = (int) Math.floor(py + ny * side * 4);
                                        long dx = (long) x - ox, dy = (long) y - oy;
                                        long distanceSq = dx * dx + dy * dy;
                                        if (x < 0 || y < 0 || distanceSq < 64
                                                || distanceSq > maxDistanceSq
                                                || !plausible(sources, x, y)) continue;
                                        long group = key(x / GROUP_SIZE,
                                                y / GROUP_SIZE);
                                        Bank old = groups.get(group);
                                        if (old == null
                                                || distanceSq < old.distanceSq()) {
                                            groups.put(group,
                                                    new Bank(x, y, distanceSq));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        ArrayList<Bank> sorted = new ArrayList<>(groups.values());
        sorted.sort(Comparator.comparingLong(Bank::distanceSq)
                .thenComparingInt(Bank::x).thenComparingInt(Bank::y));
        StringBuilder result = new StringBuilder();
        for (Bank bank : sorted) {
            if (!result.isEmpty()) result.append(';');
            result.append(bank.x()).append(':').append(bank.y());
        }
        return result.toString();
    }
}
