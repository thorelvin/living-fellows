// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/**
 * Low-speed cruise rules for a companion at the wheel. A companion presses the
 * same four inputs a player does (steer, gas, reverse, brake); this class only
 * decides which, from the car's speed, the requested cruise speed and the
 * distance to the nearest obstacle the lane scan found. It uses no game types,
 * so the core gate checks it directly.
 */
final class SCDriveControl {
    /** Companion driving is new: it cruises slowly and never faster than this. */
    static final float MAX_CRUISE_KMH = 30.0f;
    /** Reversing is only ever a slow manoeuvre. */
    static final float MAX_REVERSE_KMH = 6.0f;
    /** A requested speed below this but above zero still moves the car. */
    static final float MIN_CRUISE_KMH = 3.0f;
    /** Below this the car counts as standing still. */
    static final float STOPPED_KMH = 0.6f;
    /** Never creep closer than this to an obstacle, in tiles from the bumper. */
    static final float HOLD_GAP_TILES = 3.0f;
    /** The gap kept during slow manoeuvres such as a three-point turn. */
    static final float MANEUVER_GAP_TILES = 1.0f;
    private static final float SPEED_UP_BELOW_KMH = 1.0f;
    private static final float BRAKE_ABOVE_KMH = 3.0f;
    // Conservative: real Build 42 brakes stop harder than this.
    private static final float BRAKE_DECELERATION = 3.0f;
    private static final float REACTION_SECONDS = 0.4f;
    private static final float STOP_MARGIN_TILES = 1.5f;

    private SCDriveControl() {}

    /** The four controls Build 42's CarController reads every frame. */
    record Input(float steering, boolean forward, boolean backward, boolean brake) {}

    /** Zero, negative or NaN means stop; anything else is held to the cruise band. */
    static float clampCruise(double kmh) {
        if (!(kmh > 0.0)) return 0.0f;
        if (kmh < MIN_CRUISE_KMH) return MIN_CRUISE_KMH;
        return (float) Math.min(kmh, MAX_CRUISE_KMH);
    }

    /** -1 is the player's left key, +1 the right key. NaN steers straight. */
    static float clampSteering(double value) {
        if (!(value == value)) return 0.0f;
        return (float) Math.max(-1.0, Math.min(1.0, value));
    }

    /** Tiles a car moving at this speed needs to come to a stop, plus a margin. */
    static float stoppingDistance(float speedKmh) {
        float metresPerSecond = Math.abs(speedKmh) / 3.6f;
        return STOP_MARGIN_TILES + metresPerSecond * REACTION_SECONDS
                + metresPerSecond * metresPerSecond / (2.0f * BRAKE_DECELERATION);
    }

    /** True when an obstacle this far ahead means the car must stop now. */
    static boolean mustStop(float speedKmh, float obstacleTiles) {
        return mustStop(speedKmh, obstacleTiles, HOLD_GAP_TILES);
    }

    static boolean mustStop(float speedKmh, float obstacleTiles, float holdGap) {
        return obstacleTiles >= 0.0f
                && obstacleTiles <= Math.max(stoppingDistance(speedKmh), holdGap);
    }

    /**
     * One frame of cruise control.
     *
     * @param obstacleTiles distance from the front bumper to the nearest
     *     obstacle in the lane, or a negative value when the lane is clear
     */
    static Input cruise(float speedKmh, float targetKmh, float steering, float obstacleTiles) {
        return cruise(speedKmh, targetKmh, steering, obstacleTiles, HOLD_GAP_TILES);
    }

    static Input cruise(float speedKmh, float targetKmh, float steering, float obstacleTiles,
                        float holdGap) {
        float steer = clampSteering(steering);
        if (!(speedKmh == speedKmh)) return new Input(steer, false, false, true);
        if (targetKmh <= 0.0f || mustStop(speedKmh, obstacleTiles, holdGap)) {
            // Brake only while rolling. Build 42's controller forces game speed to
            // 1x on every frame with a pedal down, so a car at rest is left with
            // no input; the controller then holds it with its light parking brake.
            boolean rolling = Math.abs(speedKmh) > STOPPED_KMH;
            return new Input(steer, false, false, rolling);
        }
        if (speedKmh < -STOPPED_KMH) return new Input(steer, false, false, true);
        if (speedKmh < targetKmh - SPEED_UP_BELOW_KMH) return new Input(steer, true, false, false);
        if (speedKmh > targetKmh + BRAKE_ABOVE_KMH) return new Input(steer, false, false, true);
        return new Input(steer, false, false, false);
    }

    /**
     * One frame of reversing at targetKmh (a positive speed). Build 42 reports
     * reverse as a negative speed. obstacleTiles is measured from the rear
     * bumper backwards.
     */
    static Input reverse(float speedKmh, float targetKmh, float steering, float obstacleTiles) {
        float steer = clampSteering(steering);
        if (!(speedKmh == speedKmh)) return new Input(steer, false, false, true);
        float backwards = -speedKmh;
        float target = Math.min(Math.max(targetKmh, 0.0f), MAX_REVERSE_KMH);
        if (target <= 0.0f || mustStop(backwards, obstacleTiles, MANEUVER_GAP_TILES)) {
            boolean rolling = Math.abs(speedKmh) > STOPPED_KMH;
            return new Input(steer, false, false, rolling);
        }
        if (speedKmh > STOPPED_KMH) return new Input(steer, false, false, true);
        if (backwards < target - SPEED_UP_BELOW_KMH) return new Input(steer, false, true, false);
        if (backwards > target + BRAKE_ABOVE_KMH) return new Input(steer, false, false, true);
        return new Input(steer, false, false, false);
    }
}
