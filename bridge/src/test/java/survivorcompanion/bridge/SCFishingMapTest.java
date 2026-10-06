// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.nio.file.Files;
import java.nio.file.Path;

import zombie.worldMap.WorldMap;
import zombie.worldMap.WorldMapCell;
import zombie.worldMap.WorldMapData;
import zombie.worldMap.WorldMapFeature;
import zombie.worldMap.WorldMapProperties;

/** The compiled map can claim a dry Riverside field is river water. */
public final class SCFishingMapTest {
    private SCFishingMapTest() {}

    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("sc-fishing-map-");
        Path xml = directory.resolve("worldmap.xml");
        try {
            Files.writeString(xml, """
                    <world>
                      <cell x="25" y="20"><feature>
                        <geometry type="Polygon"><coordinates>
                          <point x="8" y="0"/><point x="288" y="0"/>
                          <point x="288" y="300"/><point x="8" y="300"/>
                        </coordinates></geometry>
                        <properties><property name="water" value="river"/></properties>
                      </feature></cell>
                    </world>
                    """);
            WorldMapData data = new WorldMapData();
            data.relativeFileName = xml.toString();
            WorldMapCell misleading = new WorldMapCell();
            WorldMapFeature falseRiver = new WorldMapFeature();
            falseRiver.properties = new WorldMapProperties();
            falseRiver.properties.put("water", "river");
            misleading.features.add(falseRiver);
            WorldMap world = new WorldMap() {
                @Override public WorldMapCell getCell(int x, int y) {
                    return x == 24 && y == 20 ? misleading : null;
                }
            };
            world.data.add(data);
            String banks = SCFishingMap.candidates(world, 7343, 6040, 1000);
            if (banks.isEmpty()) throw new AssertionError("real river missing");
            if (banks.contains("7330:6069") ||
                    SCFishingMap.plausible(world, 7330, 6069)) {
                throw new AssertionError("compiled-map false river survived");
            }
            String[] first = banks.split(";")[0].split(":");
            int x = Integer.parseInt(first[0]);
            int y = Integer.parseInt(first[1]);
            if (x < 7500 || !SCFishingMap.plausible(world, x, y)
                    || SCFishingMap.plausible(world, 7510, 6045)
                    || !SCFishingMap.candidates(world, 7343, 6040, 50)
                            .isEmpty()) {
                throw new AssertionError("XML bank mismatch: " + banks);
            }
            System.out.println("SC_FISHING_MAP_PASS bank=" + x + ":" + y);
        } finally {
            Files.deleteIfExists(xml);
            Files.deleteIfExists(directory);
        }
    }
}
