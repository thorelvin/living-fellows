// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.characters.Moodles.Moodles;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoMovingObject;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.core.skinnedmodel.visual.BaseVisual;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot;
import zombie.characters.ecs.ECSComponent;
import zombie.characters.action.ActionContext;
import zombie.pathfind.PathFindBehavior2;
import zombie.vehicles.BaseVehicle;

public class IsoGameCharacter extends IsoMovingObject {
    private String sayLine;

    public static class XP {
        public XP(IsoGameCharacter owner, IsoGameCharacter remoteOwner) {}
    }

    public void MoveForward(float dist, float x, float y, float soundDelta) {}
    public void addLineChatElement(String line) { sayLine = line; }
    public String getSayLine() { return sayLine; }
    public void SayDebug(int channel, String line) { sayLine = line; }
    public void addToWorld() {}
    public boolean canStandAt(float x, float y, float z) { return false; }
    public IsoCell getCell() { return null; }
    public BodyDamage getBodyDamage() { return null; }
    public ActionContext getActionContext() { return null; }
    public IsoGridSquare getCurrentSquare() { return null; }
    public BaseCharacterSoundEmitter getEmitter() { return null; }
    public Moodles getMoodles() { return null; }
    public BaseVisual getVisual() { return null; }
    public PathFindBehavior2 getPathFindBehavior2() { return null; }
    public void pathToLocationF(float x, float y, float z) {}
    public void pathToLocation(int x, int y, int z) {}
    public void pathToCharacter(IsoGameCharacter target) {}
    public void pathToSound(int x, int y, int z) {}
    public BaseVehicle getVehicle() { return null; }
    public int getWorldObjectIndex() { return -1; }
    public XP getXp() { return null; }
    public float getX() { return 0; }
    public float getY() { return 0; }
    public float getZ() { return 0; }
    public boolean isDead() { return false; }
    public void OnAnimEvent(zombie.core.skinnedmodel.advancedanimation.AnimLayer layer,
            zombie.core.skinnedmodel.animation.AnimationTrack track,
            zombie.core.skinnedmodel.advancedanimation.AnimEvent event) {}
    public boolean hasPath() { return false; }
    public boolean isAddedToModelManager() { return false; }
    public boolean hasActiveModel() { return false; }
    public boolean isOnDeathDone() { return false; }
    public void addOnDiedListener(CharacterDiedListener listener, boolean autoRemove) {}
    public void OnDeath() {}
    public boolean isAsleep() { return false; }
    public void setAsleep(boolean asleep) {}
    public void dropHandItems() {}
    public boolean shouldBecomeZombieAfterDeath() { return false; }
    public void forceAwake() {}
    public void initAttachedItems(String groupName) {}
    public void initWornItems(String groupName) {}
    public void removeFromSquare() {}
    public void removeFromWorld() {}
    public void setCurrentSquare(IsoGridSquare square) {}
    public void setSceneCulled(boolean sceneCulled) {}
    public void setAddedToModelManager(ModelManager manager, boolean added) {}
    public void setMovingSquare(IsoGridSquare square) {}
    public void setSquare(IsoGridSquare square) {}
    public void setForwardDirection(float x, float y) {}
    public boolean isAiming() { return false; }
    public void setIsAiming(boolean aiming) {}
    public boolean isAimAtFloor() { return false; }
    public boolean getVariableBoolean(String key) { return false; }
    public boolean isPerformingAttackAnimation() { return false; }
    public void postupdate() {}
    public <ComponentType extends ECSComponent> ComponentType getECSComponent(
            Class<ComponentType> componentTypeClass) { return null; }
    public IAnimationVariableSlot setVariable(String key, float value) { return null; }
    public IAnimationVariableSlot setVariable(String key, boolean value) { return null; }
    public boolean isMoving() { return false; }
    public void setMoving(boolean moving) {}
    public void setRunning(boolean running) {}
    public void setSneaking(boolean sneaking) {}
    public void setSprinting(boolean sprinting) {}
    public void setXp(XP xp) {}
    public float setX(float x) { return x; }
    public float setY(float y) { return y; }
    public float setZ(float z) { return z; }
}
