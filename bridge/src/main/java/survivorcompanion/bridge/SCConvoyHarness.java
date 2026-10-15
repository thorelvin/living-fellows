// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.MainThread;
import zombie.characters.IsoPlayer;
import zombie.core.physics.CarController;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

/** Isolated live-harness input for a real player seated in a lead vehicle. */
public final class SCConvoyHarness {
    private static final boolean ENABLED =
            "1".equals(System.getenv("SC_LIVE_CONVOY_HARNESS"));

    private SCConvoyHarness() {}

    public static boolean driveLead(IsoPlayer player, boolean forward) {
        if (!ENABLED || Thread.currentThread() != MainThread.mainThread
                || GameClient.client || GameServer.server || player == null)
            return false;
        BaseVehicle car = player.getVehicle();
        if (car == null || car.getDriver() != player || car.getSquare() == null)
            return false;
        CarController controller = car.getController();
        if (controller == null) return false;
        if (forward && !car.isEngineRunning()) car.tryStartEngine(true);
        CarController.ClientControls controls = controller.getClientControls();
        controls.steering = 0.0f;
        controls.forward = forward;
        controls.backward = false;
        controls.brake = !forward;
        controls.shift = false;
        return true;
    }
}
