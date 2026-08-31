// SPDX-License-Identifier: MIT
package zombie.iso;

import zombie.characters.IsoGameCharacter;

/** Compile-only Build 42 camera ownership API used by the isolation guard. */
public final class IsoCamera {
    private IsoCamera() {}

    public static IsoGameCharacter getCameraCharacter() { return null; }
    public static boolean setCameraCharacter(IsoGameCharacter character) { return true; }
}
