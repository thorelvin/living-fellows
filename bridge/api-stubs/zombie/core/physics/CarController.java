// SPDX-License-Identifier: MIT
package zombie.core.physics;

/** Compile-only Build 42 car controller surface: the inputs a driver presses. */
public final class CarController {
    public static final class ClientControls {
        public float steering;
        public boolean forward;
        public boolean backward;
        public boolean brake;
        public boolean shift;

        public void reset() {
            steering = 0.0f;
            forward = false;
            backward = false;
            brake = false;
            shift = false;
        }
    }

    public final ClientControls clientControls = new ClientControls();
    public int parkCallsForTests;

    public ClientControls getClientControls() { return clientControls; }

    public void park() { parkCallsForTests++; }
}
