// SPDX-License-Identifier: MIT
package zombie.worldMap;

/** Compile-only Build 42 map data readiness. */
public class WorldMap {
    public final java.util.ArrayList<WorldMapData> data = new java.util.ArrayList<>();
    public boolean isDataLoaded() { return false; }
    public WorldMapCell getCell(int x, int y) { return null; }
}
