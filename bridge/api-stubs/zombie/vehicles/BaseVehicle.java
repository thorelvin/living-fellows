// SPDX-License-Identifier: MIT
package zombie.vehicles;

import zombie.characters.IsoGameCharacter;
import zombie.core.physics.CarController;
import zombie.iso.IsoMovingObject;
import zombie.scripting.objects.VehicleScript;

/** Compile-only Build 42 vehicle surface used by health checks and companion driving. */
public class BaseVehicle extends IsoMovingObject {
    public enum engineStateTypes {
        Idle, Starting, RetryingStarting, StartingSuccess, StartingFailed,
        Running, Stalling, ShuttingDown
    }

    public int getSeat(IsoGameCharacter character) { return -1; }
    public IsoGameCharacter getDriver() { return null; }
    public CarController getController() { return null; }
    public VehicleScript getScript() { return null; }
    public float getCurrentSpeedKmHour() { return 0.0f; }
    public org.joml.Vector3f getForwardVector(org.joml.Vector3f out) { return out; }
    public boolean isEngineRunning() { return false; }
    public engineStateTypes getEngineState() { return engineStateTypes.Idle; }
    public void tryStartEngine(boolean haveKey) {}
}
