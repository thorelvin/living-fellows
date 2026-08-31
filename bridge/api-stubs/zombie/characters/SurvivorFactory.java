// SPDX-License-Identifier: MIT
package zombie.characters;

public class SurvivorFactory {
    public enum SurvivorType { Friendly, Neutral, Aggressive }

    public static SurvivorDesc CreateSurvivor() { return null; }
    public static SurvivorDesc CreateSurvivor(SurvivorType type, boolean female) { return null; }
}
