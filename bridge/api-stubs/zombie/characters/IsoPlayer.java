// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.iso.IsoCell;

/** Compile-only API surface for the version-pinned companion prototype. */
public class IsoPlayer extends IsoLivingCharacter {
    public static IsoPlayer[] players = new IsoPlayer[4];
    public static int numPlayers = 1;
    public int playerIndex;
    public int serverPlayerIndex;
    protected boolean isPlayerMoving;

    public IsoPlayer(IsoCell cell, SurvivorDesc descriptor, int x, int y, int z, boolean animal) {
        super(cell, x, y, z);
    }

    public final int getPlayerNum() { return playerIndex; }
    public static IsoPlayer getInstance() { return null; }
    public static void setInstance(IsoPlayer player) {}
    public boolean isLocalPlayer() { return false; }
    public boolean isPlayerMoving() { return false; }
    public boolean isNpc() { return false; }
    public boolean isInitiateAttack() { return false; }
    public void StopAllActionQueue() {}
    public void setNpc(boolean npc) {}
    public void updateMovementRates() {}
    public void update() {}
}
