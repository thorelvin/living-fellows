// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/** The step-clearance rule that lets a companion wedged against furniture walk out. */
public final class SCMovementClearanceTest {
    private static int checks;

    private static void require(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        require(SCNativeCompanion.movementLeavesObstacle(false, true, true),
                "a clear sweep is always allowed");
        require(SCNativeCompanion.movementLeavesObstacle(false, false, false),
                "a clear sweep does not depend on the stand points");
        require(!SCNativeCompanion.movementLeavesObstacle(true, true, true),
                "a companion standing free must not walk into an obstacle");
        require(!SCNativeCompanion.movementLeavesObstacle(true, true, false),
                "a step into a spot it cannot stand on stays blocked");
        require(SCNativeCompanion.movementLeavesObstacle(true, false, true),
                "a companion wedged in furniture may step to free ground");
        require(!SCNativeCompanion.movementLeavesObstacle(true, false, false),
                "a wedged companion may not step deeper into geometry");
        System.out.println("MOVEMENT_CLEARANCE_PASS checks=" + checks);
    }
}
