// SPDX-License-Identifier: MIT
package zombie.iso;

public class IsoMovingObject extends IsoObject {
    public IsoGridSquare getMovingSquare() { return null; }
    public boolean isExistInTheWorld() { return false; }
    public float getX() { return 0; }
    public float getY() { return 0; }
    public float getNextX() { return 0; }
    public float getNextY() { return 0; }
    public float getLastX() { return 0; }
    public float getLastY() { return 0; }
    public float setNextX(float value) { return value; }
    public float setNextY(float value) { return value; }
    public void moveUnmodded(float x, float y) {}
    public boolean isCollidedThisFrame() { return false; }
    public boolean isCollidedWithVehicle() { return false; }
}
