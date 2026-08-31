// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.iso.IsoCell;

/**
 * Research actor that keeps Build 42's player-only character components while
 * remaining outside IsoPlayer.players. Never packaged without the runtime gate.
 */
public final class SCNativeCompanion extends IsoPlayer {
    public static final int RESERVED_NON_LOCAL_PLAYER_INDEX = 3;

    public SCNativeCompanion(SurvivorDesc descriptor, IsoCell cell, int x, int y, int z) {
        super(cell, descriptor, x, y, z, false);
        playerIndex = RESERVED_NON_LOCAL_PLAYER_INDEX;
        serverPlayerIndex = -1;
        setNpc(true);
        descriptor.setInstance(this);
    }

    @Override
    public boolean isLocalPlayer() {
        return false;
    }
}
