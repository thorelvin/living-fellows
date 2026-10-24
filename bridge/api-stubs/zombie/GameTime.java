// SPDX-License-Identifier: MIT
package zombie;
public class GameTime {
    public static GameTime instance;
    public static GameTime getInstance() { return instance; }
    public float getMultiplier() { return 1.0f; }
    public float getDeltaMinutesPerDay() { return 1.0f; }
}
