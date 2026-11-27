// SPDX-License-Identifier: MIT
// Test-only: compiled into the disposable live-run agent JAR, never into the
// shipped bridge. SCExposure looks it up by name for convoy live runs.
package livingfellows.harness;

import org.joml.Vector3f;
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
        float speed = car.getCurrentSpeedKmHour();
        controls.forward = forward && speed < 20.0f;
        controls.backward = false;
        controls.brake = !forward || speed > 23.0f;
        controls.shift = false;
        return true;
    }

    /** Keep the real player's car on the chosen street with ordinary inputs. */
    public static boolean driveLeadAlong(IsoPlayer player, boolean forward,
                                         double targetX, double targetY) {
        if (!Double.isFinite(targetX) || !Double.isFinite(targetY)
                || !driveLead(player, forward)) return false;
        BaseVehicle car=player.getVehicle();
        Vector3f heading=car.getForwardVector(new Vector3f());
        double error=Math.atan2(targetY-car.getY(),targetX-car.getX())
                -Math.atan2(heading.z,heading.x);
        while (error>Math.PI) error-=2*Math.PI;
        while (error< -Math.PI) error+=2*Math.PI;
        car.getController().getClientControls().steering=(float)Math.max(-1,Math.min(1,error*2.2));
        return true;
    }
}
