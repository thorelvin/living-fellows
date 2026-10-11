// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/**
 * Turns a car round in a bounded number of legs, the way a driver does on a
 * narrow road: forward at full lock, stop, reverse at the opposite lock, stop,
 * and forward again until the car faces the new way. Both kinds of leg rotate
 * the car the same way round. A leg ends when the car faces the target, when
 * something is close ahead (forward) or behind (reverse), or when it runs out
 * of time. Uses no game types.
 *
 * <p>Headings are radians from atan2(y, x) with y growing south, so a right
 * (clockwise) turn grows the heading. {@code side} +1 turns right, -1 left.
 */
final class SCTurnAround {
    static final float DONE_ERROR = (float) Math.toRadians(18.0);
    /** A reverse leg may end once a forward leg can finish the rest. */
    private static final float FINISH_FORWARD = (float) Math.toRadians(70.0);
    static final float FORWARD_KMH = 4.0f;
    static final float REVERSE_KMH = 3.0f;
    static final long LEG_LIMIT_MS = 7000L;
    static final int MAX_LEGS = 9;
    /**
     * End a leg this close to something, in tiles from the bumper. It sits just
     * above where the manoeuvre brake holds a slow car (SCDriveControl), so a
     * leg ends instead of waiting out its timer against a wall.
     */
    static final float LEG_CLEARANCE = 2.0f;
    /** A leg whose car has not moved for this long is over. */
    private static final long STALL_MS = 1200L;
    private static final float STALL_KMH = 0.4f;
    /** A reverse leg that makes things worse this much has its wheel flipped. */
    private static final float WRONG_WAY = (float) Math.toRadians(6.0);
    private static final long WRONG_WAY_CHECK_MS = 1500L;

    enum State { FORWARD, REVERSE, DONE, FAILED }

    /** One frame of manoeuvre: the wheel and a signed target speed (negative reverses). */
    static final class Step {
        float steering;
        float targetKmh;
        boolean settling;
    }

    private final float targetHeading;
    private final int side;
    private State state = State.FORWARD;
    private boolean settling;
    private State nextLeg = State.FORWARD;
    private int legs = 1;
    private long legStartedAt = -1L;
    private float legStartRemaining;
    private float reverseSign = 1.0f;
    private boolean reverseChecked;
    private long stillSince = -1L;
    private String reason = "";

    SCTurnAround(float targetHeading, int side) {
        this.targetHeading = targetHeading;
        this.side = side >= 0 ? 1 : -1;
    }

    State state() {
        return state;
    }

    int legs() {
        return legs;
    }

    int side() {
        return side;
    }

    float reverseSign() {
        return reverseSign;
    }

    String reason() {
        return reason;
    }

    /** For tests: start with the reverse wheel the wrong way round. */
    void startWithReverseSign(float sign) {
        reverseSign = sign < 0.0f ? -1.0f : 1.0f;
    }

    static float wrap(float angle) {
        double value = angle;
        while (value > Math.PI) value -= 2.0 * Math.PI;
        while (value < -Math.PI) value += 2.0 * Math.PI;
        return (float) value;
    }

    /** Rotation still to go in this turn's direction, in [0, 2pi). */
    float remaining(float heading) {
        double value = side * (targetHeading - heading);
        value %= 2.0 * Math.PI;
        if (value < 0.0) value += 2.0 * Math.PI;
        return (float) value;
    }

    /** True when the car faces the target closely enough, either side of it. */
    boolean aligned(float heading) {
        return Math.abs(wrap(targetHeading - heading)) <= DONE_ERROR;
    }

    /**
     * @param frontClear tiles clear ahead of the front bumper, negative when clear
     * @param rearClear tiles clear behind the rear bumper, negative when clear
     */
    Step update(float heading, float speedKmh, float frontClear, float rearClear, long nowMs,
                Step out) {
        Step step = out == null ? new Step() : out;
        step.steering = 0.0f;
        step.targetKmh = 0.0f;
        step.settling = false;
        if (state == State.DONE || state == State.FAILED) return step;
        if (aligned(heading)) {
            state = State.DONE;
            reason = "aligned";
            return step;
        }
        if (legStartedAt < 0L) {
            legStartedAt = nowMs;
            legStartRemaining = remaining(heading);
        }
        if (settling) {
            step.settling = true;
            if (Math.abs(speedKmh) > SCDriveControl.STOPPED_KMH) return step;
            settling = false;
            legs++;
            if (legs > MAX_LEGS) {
                state = State.FAILED;
                reason = "too_many_legs";
                return step;
            }
            state = nextLeg;
            legStartedAt = nowMs;
            legStartRemaining = remaining(heading);
            reverseChecked = false;
            stillSince = -1L;
        }
        float rest = remaining(heading);
        long elapsed = nowMs - legStartedAt;
        // Something the scans cannot see can still hold the car: a stalled leg is over.
        if (Math.abs(speedKmh) < STALL_KMH) {
            if (stillSince < 0L) stillSince = nowMs;
        } else {
            stillSince = -1L;
        }
        boolean stalled = elapsed > STALL_MS && stillSince >= 0L && nowMs - stillSince > STALL_MS;
        if (state == State.FORWARD) {
            boolean blocked = frontClear >= 0.0f && frontClear <= LEG_CLEARANCE;
            if (blocked || stalled || elapsed > LEG_LIMIT_MS) {
                endLeg(State.REVERSE, blocked ? "front_close" : stalled ? "stalled" : "leg_time");
                step.settling = true;
                return step;
            }
            step.steering = side;
            step.targetKmh = FORWARD_KMH;
            return step;
        }
        // Reverse: the opposite lock turns the car the same way round. If the
        // car turns the wrong way anyway, flip the wheel once for this turn.
        if (!reverseChecked && elapsed > WRONG_WAY_CHECK_MS) {
            reverseChecked = true;
            if (rest > legStartRemaining + WRONG_WAY) reverseSign = -reverseSign;
        }
        boolean blocked = rearClear >= 0.0f && rearClear <= LEG_CLEARANCE;
        if (blocked || stalled || elapsed > LEG_LIMIT_MS || rest <= FINISH_FORWARD) {
            endLeg(State.FORWARD, blocked ? "rear_close" : stalled ? "stalled"
                    : rest <= FINISH_FORWARD ? "forward_can_finish" : "leg_time");
            step.settling = true;
            return step;
        }
        step.steering = -side * reverseSign;
        step.targetKmh = -REVERSE_KMH;
        return step;
    }

    private void endLeg(State next, String why) {
        settling = true;
        nextLeg = next;
        reason = why;
    }
}
