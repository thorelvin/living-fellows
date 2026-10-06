// SPDX-License-Identifier: MIT
package zombie.worldMap;

/** Compile-only Build 42 map polygon. */
public class WorldMapFeature {
    public WorldMapGeometry geometry;
    public WorldMapProperties properties;
    public boolean hasPolygon() { return false; }
    public boolean containsPoint(float x, float y) { return false; }
}
