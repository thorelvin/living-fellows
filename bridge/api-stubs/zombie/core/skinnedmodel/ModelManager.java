// SPDX-License-Identifier: MIT
package zombie.core.skinnedmodel;

import zombie.characters.IsoGameCharacter;

/** Compile-only subset of Build 42's model-manager API. */
public final class ModelManager {
    public static final ModelManager instance = new ModelManager();

    public void Add(IsoGameCharacter character) {}
    public void Remove(IsoGameCharacter character) {}
}
