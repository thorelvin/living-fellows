// SPDX-License-Identifier: MIT
package zombie.scripting.objects;

/** Compile-only Build 42 vehicle script surface: body extents for the lane scan. */
public final class VehicleScript {
    public float maxSpeed;
    public org.joml.Vector3f getExtents() { return null; }
    public int getWheelCount() { return 0; }
    public Wheel getWheel(int index) { return null; }
    public float getSteeringClamp(float speed) { return 0; }
    public static final class Wheel {
        public boolean front;
        public org.joml.Vector3f getOffset() { return null; }
    }
}
