// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.iso.objects.IsoDeadBody;

/** Compile-only API surface for the version-pinned companion bridge. */
@FunctionalInterface
public interface CharacterDiedListener {
    void onDied(IsoGameCharacter character, IsoDeadBody body);
}
