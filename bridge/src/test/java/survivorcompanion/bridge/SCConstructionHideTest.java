// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;

/**
 * A companion is hidden from the moment it is constructed until the mod has
 * finished dressing it. That hide has to end whatever else happens: an
 * invisible companion is a worse bug than a visible costume change, so the
 * actor's own update gives up on waiting after a few seconds.
 */
public final class SCConstructionHideTest {
    private SCConstructionHideTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Method expired = SCNativeCompanion.class.getDeclaredMethod(
                "constructionHideExpired", long.class, long.class);
        expired.setAccessible(true);

        require(Boolean.FALSE.equals(expired.invoke(null, 0L, 9_999_999L)),
                "a companion that was never hidden is never force-revealed");
        require(Boolean.FALSE.equals(expired.invoke(null, 1_000L, 1_000L)),
                "the hide survives the frame it was set in");
        require(Boolean.FALSE.equals(expired.invoke(null, 1_000L, 4_999L)),
                "the hide survives an ordinary restore");
        require(Boolean.TRUE.equals(expired.invoke(null, 1_000L, 5_000L)),
                "a hide nothing ever lifted lifts itself");
        require(Boolean.TRUE.equals(expired.invoke(null, 1_000L, 900_000L)),
                "and stays lifted");

        System.out.println("SC_CONSTRUCTION_HIDE_PASS");
    }
}
