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
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.characters.ecs.ECSComponent;
import zombie.characters.action.ActionContext;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.pathfind.PathFindBehavior2;
import zombie.ai.StateMachine;
import zombie.ai.State;
import zombie.vehicles.BaseVehicle;
import zombie.chat.ChatElement;

public class IsoGameCharacter extends IsoMovingObject {
    private String sayLine;
    private final java.util.Stack<BaseAction> characterActions = new java.util.Stack<>();
    private boolean aiming;
    private boolean aimAtFloor;
    private boolean performingAttackAnimation;
    private boolean performingShoveAnimation;
    private boolean performingStompAnimation;

    public static class XP {
        public XP(IsoGameCharacter owner, IsoGameCharacter remoteOwner) {}
    }

    public void MoveForward(float dist, float x, float y, float soundDelta) {}
    public void addLineChatElement(String line) { sayLine = line; }
    public String getSayLine() { return sayLine; }
    public void setSayLine(String line) {
        if (line == null) throw new NullPointerException("speech line");
        sayLine = line;
    }
    public void setLastSpokenLine(String line) {}
    public void setSpeaking(boolean speaking) {}
    public void setSpeakTime(int milliseconds) {}
    public ChatElement getChatElement() { return null; }
    public void SayDebug(int channel, String line) { sayLine = line; }
    public void addToWorld() {}
    public boolean canStandAt(float x, float y, float z) { return false; }
    public IsoCell getCell() { return null; }
    public BodyDamage getBodyDamage() { return null; }
    public ActionContext getActionContext() { return null; }
    public java.util.Stack<BaseAction> getCharacterActions() { return characterActions; }
    public void StartAction(BaseAction action) { characterActions.add(action); }
    public IsoGridSquare getCurrentSquare() { return null; }
    public BaseCharacterSoundEmitter getEmitter() { return null; }
    public Moodles getMoodles() { return null; }
    public BaseVisual getVisual() { return null; }
    public AnimationPlayer getAnimationPlayer() { return null; }
    public boolean hasAnimationPlayer() { return false; }
    public zombie.iso.Vector2 getForwardDirection() { return null; }
    public PathFindBehavior2 getPathFindBehavior2() { return null; }
    public zombie.ai.astar.AStarPathFinderResult getFinder() { return null; }
    public void setPath2(zombie.pathfind.Path path) {}
    public <T> T get(State.Param<T> parameter) { return null; }
    public <T> void set(State.Param<T> parameter, T value) {}
    public StateMachine getStateMachine() { return null; }
    public void changeState(State state) {}
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
    public float getHealth() { return 0; }
    public int getLastHitCount() { return 0; }
    public boolean isDead() { return false; }
    public boolean isOnFloor() { return false; }
    public boolean isClimbing() { return false; }
    public boolean isManualFloorAtkButtonDown() { return false; }
    public boolean isMeleeButtonDown() { return false; }
    public zombie.pathfind.Path getPath2() { return null; }
    public zombie.iso.Vector2 getDeferredMovement(zombie.iso.Vector2 result) { return result; }
    public boolean isBlockMovement() { return false; }
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
    public boolean isAiming() { return aiming; }
    public void setIsAiming(boolean aiming) { this.aiming = aiming; }
    public boolean isAimAtFloor() { return aimAtFloor; }
    public void setAimAtFloor(boolean value) { aimAtFloor = value; }
    public void setDoShove(boolean value) {}
    public void setShoveStompAnim(boolean value) {}
    public boolean getVariableBoolean(String key) { return false; }
    public boolean isPerformingAttackAnimation() { return performingAttackAnimation; }
    public void setPerformingAttackAnimation(boolean value) { performingAttackAnimation = value; }
    public boolean isPerformingShoveAnimation() { return performingShoveAnimation; }
    public void setPerformingShoveAnimation(boolean value) { performingShoveAnimation = value; }
    public boolean isPerformingStompAnimation() { return performingStompAnimation; }
    public void setPerformingStompAnimation(boolean value) { performingStompAnimation = value; }
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
