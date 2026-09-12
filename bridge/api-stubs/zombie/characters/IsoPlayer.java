// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.iso.IsoCell;
import zombie.iso.IsoDirections;

/** Compile-only API surface for the version-pinned companion prototype. */
public class IsoPlayer extends IsoLivingCharacter {
    public static IsoPlayer[] players = new IsoPlayer[4];
    public static int numPlayers = 1;
    public int playerIndex;
    public int serverPlayerIndex;
    protected boolean isPlayerMoving;
    private boolean initiateAttack;
    private boolean attackStarted;

    public IsoPlayer(IsoCell cell, SurvivorDesc descriptor, int x, int y, int z, boolean animal) {
        super(cell, x, y, z);
    }

    public final int getPlayerNum() { return playerIndex; }
    public static IsoPlayer getInstance() { return null; }
    public static void setInstance(IsoPlayer player) {}
    public static boolean getCoopPVP() { return false; }
    public static void setCoopPVP(boolean enabled) {}
    public boolean isLocalPlayer() { return false; }
    public boolean isPlayerMoving() { return false; }
    public boolean isNpc() { return false; }
    public boolean isInitiateAttack() { return initiateAttack; }
    public void setInitiateAttack(boolean initiate) { initiateAttack = initiate; }
    public boolean isAttackStarted() { return attackStarted; }
    public void setAttackStarted(boolean started) { attackStarted = started; }
    public void clearHandToHandAttack() { attackStarted = false; initiateAttack = false; }
    public boolean isZombiesDontAttack() { return false; }
    public boolean climbOverWall(IsoDirections direction) { return false; }
    public void StopAllActionQueue() {}
    public void setNpc(boolean npc) {}
    public void updateMovementRates() {}
    public void update() {}
}
