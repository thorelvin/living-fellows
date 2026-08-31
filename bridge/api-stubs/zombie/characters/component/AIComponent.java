// SPDX-License-Identifier: MIT
package zombie.characters.component;

import zombie.ai.AIBrainPlayerControlVars;
import zombie.characters.ecs.ECSComponent;

/** Compile-only Build 42 NPC AI component surface. */
public class AIComponent extends ECSComponent {
    public AIBrainPlayerControlVars getHumanControlVars() { return null; }
}
