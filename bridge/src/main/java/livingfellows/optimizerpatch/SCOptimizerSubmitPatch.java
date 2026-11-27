// SPDX-License-Identifier: MIT
package livingfellows.optimizerpatch;

import me.zed_0xff.zombie_buddy.Patch;
import livingfellows.bridge.SCPZOptimizerCompatibility;
import zombie.characters.IsoGameCharacter;

// Outside the bridge's auto-discovered patch package. The optional adapter
// explicitly installs this package only after validating PZOptimizer's bytes.
@Patch(className = "pzopt.ActionEval", methodName = "submit", warmUp = true)
public final class SCOptimizerSubmitPatch {
    private SCOptimizerSubmitPatch() {}

    // Covers the public submit and the private overload used by submitWithHead.
    // Skipping returns boolean false: the caller completes its normal inline
    // postupdate, preserving visibility until the attack graph has evaluated.
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.Argument(0) IsoGameCharacter character) {
        return SCPZOptimizerCompatibility.beforeSubmit(character);
    }
}
