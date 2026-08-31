// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.characters.SurvivorDesc;
import zombie.iso.IsoCell;

/** Real-JAR safety control for the custom IsoPlayer-based companion prototype. */
public final class SCIsoCompanionControlTest {
    private SCIsoCompanionControlTest() {}

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        try {
            return target.getClass().getMethod(name).invoke(target);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtime) throw runtime;
            if (cause instanceof Error error) throw error;
            throw failure;
        }
    }

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    @SuppressWarnings({ "rawtypes", "unchecked" })
    private static Object companionDescriptor(boolean female, String forename) throws Exception {
        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Class<?> factoryClass = Class.forName("zombie.characters.SurvivorFactory");
        Class<?> typeClass = Class.forName("zombie.characters.SurvivorFactory$SurvivorType");
        List<String> forenames = (List<String>) factoryClass
                .getField(female ? "FemaleForenames" : "MaleForenames").get(null);
        List<String> surnames = (List<String>) factoryClass.getField("Surnames").get(null);
        if (forenames.isEmpty()) forenames.add(forename);
        if (surnames.isEmpty()) surnames.add("Companion");
        Object neutral = Enum.valueOf((Class<? extends Enum>) typeClass, "Neutral");
        Object descriptor = factoryClass.getMethod("CreateSurvivor", typeClass, boolean.class)
                .invoke(null, neutral, female);
        descriptorClass.getMethod("setForename", String.class).invoke(descriptor, forename);
        descriptorClass.getMethod("setSurname", String.class).invoke(descriptor, "Companion");
        return descriptor;
    }

    public static void main(String[] args) throws Exception {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-isocompanion-control");
        fileSystemClass.getMethod("init").invoke(fileSystem);
        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        managerClass.getMethod("RunLua", String.class).invoke(null,
                "media/lua/shared/Definitions/HairOutfitDefinitions.lua");
        Class.forName("zombie.core.skinnedmodel.population.HairStyles").getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.BeardStyles").getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.OutfitManager").getMethod("init").invoke(null);
        Object hairDefinitions = Class.forName("zombie.characters.HairOutfitDefinitions")
                .getField("instance").get(null);
        hairDefinitions.getClass().getMethod("checkDirty").invoke(hairDefinitions);
        Class<?> colorClass = Class.forName("zombie.core.ImmutableColor");
        Object color = colorClass.getConstructor(float.class, float.class, float.class)
                .newInstance(0.3f, 0.2f, 0.1f);
        List<Object> commonHairColors = (List<Object>) Class.forName("zombie.characters.SurvivorDesc")
                .getField("HairCommonColors").get(null);
        if (commonHairColors.isEmpty()) commonHairColors.add(color);
        Object populationTemplates = Class.forName("zombie.core.skinnedmodel.population.PopTemplateManager")
                .getField("instance").get(null);
        for (String[] fixture : new String[][] {
                { "maleSkins", "MaleBody01" }, { "femaleSkins", "FemaleBody01" }
        }) {
            List<String> skins = (List<String>) populationTemplates.getClass()
                    .getField(fixture[0]).get(populationTemplates);
            if (skins.isEmpty()) skins.add(fixture[1]);
        }
        Class<?> soundManagerClass = Class.forName("zombie.SoundManager");
        soundManagerClass.getField("instance").set(null,
                Class.forName("zombie.DummySoundManager").getConstructor().newInstance());

        Class<?> cellClass = Class.forName("zombie.iso.IsoCell");
        Object cell = cellClass.getConstructor(int.class, int.class).newInstance(64, 64);
        Class<?> sliceClass = Class.forName("zombie.iso.SliceY");
        Class<?> squareClass = Class.forName("zombie.iso.IsoGridSquare");
        Object square = squareClass.getConstructor(cellClass, sliceClass, int.class, int.class, int.class)
                .newInstance(cell, sliceClass.getConstructor().newInstance(), 0, 0, 0);
        squareClass.getField("solidFloor").setBoolean(square, true);
        Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
        Object world = worldClass.getConstructor().newInstance();
        worldClass.getField("instance").set(null, world);
        worldClass.getField("currentCell").set(world, cell);

        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Object localDescriptor = descriptorClass.getConstructor().newInstance();
        descriptorClass.getMethod("setForename", String.class).invoke(localDescriptor, "Control");
        descriptorClass.getMethod("setSurname", String.class).invoke(localDescriptor, "Player");
        descriptorClass.getMethod("setFemale", boolean.class).invoke(localDescriptor, false);
        Object visual = descriptorClass.getMethod("getHumanVisual").invoke(localDescriptor);
        visual.getClass().getMethod("setHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setHairModel", String.class).invoke(visual, "Bald");
        visual.getClass().getMethod("setBeardModel", String.class).invoke(visual, "");
        visual.getClass().getMethod("setSkinTextureName", String.class).invoke(visual, "MaleBody01");

        Class<?> playerClass = Class.forName("zombie.characters.IsoPlayer");
        Object localPlayer = playerClass.getConstructor(cellClass, descriptorClass,
                        int.class, int.class, int.class, boolean.class)
                .newInstance(cell, localDescriptor, 0, 0, 0, false);
        localPlayer.getClass().getMethod("setCurrentSquare", squareClass).invoke(localPlayer, square);
        playerClass.getMethod("setLocalPlayer", int.class, playerClass)
                .invoke(null, 0, localPlayer);
        playerClass.getMethod("setInstance", playerClass).invoke(null, localPlayer);
        Class<?> cameraClass = Class.forName("zombie.iso.IsoCamera");
        Class<?> gameCharacterClass = Class.forName("zombie.characters.IsoGameCharacter");
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, localPlayer);
        Object[] slotsBefore = ((Object[]) playerClass.getField("players").get(null)).clone();
        int countBefore = playerClass.getField("numPlayers").getInt(null);
        Object singletonBefore = playerClass.getMethod("getInstance").invoke(null);
        Object cameraBefore = cameraClass.getMethod("getCameraCharacter").invoke(null);
        Class<?> companionClass = Class.forName("survivorcompanion.bridge.SCNativeCompanion");
        Object firstDescriptor = companionDescriptor(false, "First");
        ArrayList<Event> eventList = new ArrayList<>();
        HashMap<String, Event> eventMap = new HashMap<>();
        LuaEventManager.getEvents(eventList, eventMap);
        Event createLiving = eventMap.get("OnCreateLivingCharacter");
        require(createLiving != null, "OnCreateLivingCharacter event is unavailable");
        int callbacksBefore = createLiving.callbacks.size();
        createLiving.callbacks.add(null);
        Object actor;
        try {
            actor = SCBridge.constructCompanion((SurvivorDesc) firstDescriptor,
                    (IsoCell) cell, 0, 0, 0);
            require(createLiving.callbacks.size() == callbacksBefore + 1
                            && createLiving.callbacks.get(callbacksBefore) == null,
                    "constructor guard did not restore the exact callback sequence");
        } finally {
            createLiving.callbacks.remove(callbacksBefore);
        }
        actor.getClass().getMethod("setCurrentSquare", squareClass).invoke(actor, square);
        Object secondDescriptor = companionDescriptor(true, "Second");
        Object secondActor = SCBridge.constructCompanion((SurvivorDesc) secondDescriptor,
                (IsoCell) cell, 0, 0, 0);
        secondActor.getClass().getMethod("setCurrentSquare", squareClass).invoke(secondActor, square);

        // A dedicated probe covers the complete live spawn registration. The
        // headless fixture has no initialized GameEntityManager unregister
        // path, so detach its square references directly after the assertion
        // instead of mixing that fixture limitation into the teardown test.
        Object membershipDescriptor = companionDescriptor(false, "Membership");
        Object membershipActor = SCBridge.constructCompanion((SurvivorDesc) membershipDescriptor,
                (IsoCell) cell, 0, 0, 0);
        membershipActor.getClass().getMethod("setCurrentSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("setSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("setMovingSquare", squareClass)
                .invoke(membershipActor, square);
        membershipActor.getClass().getMethod("addToWorld").invoke(membershipActor);
        require((Boolean) invoke(membershipActor, "isExistInTheWorld"),
                "native companion was not registered in its square moving-object list");
        membershipActor.getClass().getMethod("removeFromSquare").invoke(membershipActor);
        membershipActor.getClass().getMethod("setMovingSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });
        membershipActor.getClass().getMethod("setCurrentSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });
        membershipActor.getClass().getMethod("setSquare", squareClass)
                .invoke(membershipActor, new Object[] { null });

        require(playerClass.isInstance(actor), "companion is not an IsoPlayer subtype");
        require((Boolean) invoke(actor, "isNpc"), "companion is not in NPC mode");
        require(!(Boolean) invoke(actor, "isLocalPlayer"), "companion became local");
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, true);
        actor.getClass().getMethod("MoveForward", float.class, float.class, float.class, float.class)
                .invoke(actor, 0.045f, 1.0f, 0.0f, 1.0f);
        require((Boolean) invoke(actor, "isMoving"),
                "companion lost its generic NPC movement state to IsoPlayer input semantics");
        require((Boolean) invoke(actor, "isPlayerMoving"),
                "player animation graph did not receive companion movement state");
        require(((SCNativeCompanion) actor).hasPendingMovement(),
                "companion did not retain movement for the native physics window");
        ((SCNativeCompanion) actor).synchronizePlayerLocomotion();
        Method variableFloat = actor.getClass().getMethod("getVariableFloat",
                String.class, float.class);
        require(((Number) variableFloat.invoke(actor, "WalkSpeed", -1.0f)).floatValue() > 0.0f
                        && ((Number) variableFloat.invoke(actor, "RunSpeed", -1.0f)).floatValue() > 0.0f
                        && ((Number) variableFloat.invoke(actor, "IdleSpeed", -1.0f)).floatValue() > 0.0f,
                "player locomotion speed scalars remained frozen at zero");
        require(((SCNativeCompanion) actor).setCompanionTacticalMovement(true, 0.55f, -0.55f),
                "NPC aiming control did not retain tactical movement");
        require((Boolean) invoke(actor, "isAiming")
                        && ((SCNativeCompanion) actor).isCompanionTacticalMovement()
                        && Math.abs(((Number) variableFloat.invoke(actor,
                                "DeltaX", 0.0f)).floatValue() - 0.55f) < 0.001f
                        && Math.abs(((Number) variableFloat.invoke(actor,
                                "DeltaY", 0.0f)).floatValue() + 0.55f) < 0.001f,
                "stock IsoPlayer diagonal backward animation inputs were not retained");
        require(((SCNativeCompanion) actor).setCompanionTacticalMovement(false, 0.0f, 0.0f)
                        && !(Boolean) invoke(actor, "isAiming")
                        && !((SCNativeCompanion) actor).isCompanionTacticalMovement(),
                "tactical movement state did not clear cleanly");
        actor.getClass().getMethod("setIsAiming", boolean.class).invoke(actor, true);
        ((SCNativeCompanion) actor).synchronizePlayerLocomotion();
        require((Boolean) invoke(actor, "isAiming")
                        && !((SCNativeCompanion) actor).isCompanionTacticalMovement(),
                "locomotion synchronization cancelled an ordinary combat aiming state");
        actor.getClass().getMethod("setIsAiming", boolean.class).invoke(actor, false);
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, false);
        require(!(Boolean) invoke(actor, "isMoving"),
                "companion movement state did not stop cleanly");
        require(!(Boolean) invoke(actor, "isPlayerMoving"),
                "player animation graph retained movement after stop");
        require(!((SCNativeCompanion) actor).hasPendingMovement(),
                "stopping the companion left a stale native movement request");
        var pathActive = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActive.setAccessible(true);
        pathActive.setBoolean(actor, true);
        require((Boolean) invoke(actor, "isPlayerMoving"),
                "native path state recursed through IsoPlayer movement callbacks");
        pathActive.setBoolean(actor, false);
        require(((Number) invoke(actor, "getPlayerNum")).intValue() == 3,
                "companion did not retain reserved non-local index");
        require(((Number) invoke(secondActor, "getPlayerNum")).intValue() == 3
                        && (Boolean) invoke(secondActor, "isNpc")
                        && !(Boolean) invoke(secondActor, "isLocalPlayer"),
                "second companion did not retain isolated NPC state");
        require(SCNativeCompanion.hasGenericCharacterUpdate(),
                "version-pinned generic IsoGameCharacter update is unavailable");
        for (String component : new String[] {
                "getBodyDamage", "getMoodles", "getXp", "getEmitter", "getVisual",
                "getInventory", "getPathFindBehavior2", "getModData" }) {
            require(invoke(actor, component) != null, "component is null: " + component);
        }
        SCNativeCompanion.LocalPlayerState rollback = SCNativeCompanion.LocalPlayerState.capture();
        require(rollback != null && rollback.matches(), "local-player rollback snapshot failed");
        Object[] mutableSlots = (Object[]) playerClass.getField("players").get(null);
        mutableSlots[1] = actor;
        playerClass.getField("numPlayers").setInt(null, 2);
        playerClass.getMethod("setInstance", playerClass).invoke(null, actor);
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, actor);
        require(!rollback.matches() && rollback.restore() && rollback.matches(),
                "local-player state mutation was not repaired transactionally");

        SCNativeCompanion.LocalPlayerState ownershipGuard =
                SCNativeCompanion.LocalPlayerState.capture();
        playerClass.getMethod("setInstance", playerClass).invoke(null, actor);
        cameraClass.getMethod("setCameraCharacter", gameCharacterClass).invoke(null, actor);
        require(ownershipGuard.slotsMatch() && !ownershipGuard.ownersMatch()
                        && ownershipGuard.restore() && ownershipGuard.matches(),
                "companion ownership contamination was not rejected and repaired");

        Class.forName("zombie.iso.areas.isoregion.IsoRegions").getMethod("init").invoke(null);
        boolean updateReachedRenderBoundary = false;
        for (Object candidate : new Object[] { actor, secondActor }) {
            try {
                invoke(candidate, "update");
                String bridgeFailure = String.valueOf(invoke(candidate, "getBridgeFailure"));
                if (!bridgeFailure.isEmpty()) {
                    boolean renderContextBoundary = bridgeFailure.contains("RenderContextQueueException")
                            && bridgeFailure.contains("No GLCapabilities");
                    boolean headlessAnimationBoundary = bridgeFailure.contains("NullPointerException")
                            && bridgeFailure.contains("AnimationPlayer.setModel");
                    require(renderContextBoundary || headlessAnimationBoundary,
                            "companion contained an unexpected native update failure: " + bridgeFailure);
                    updateReachedRenderBoundary = true;
                } else {
                    require(!(Boolean) invoke(candidate, "isDead"),
                            "companion died during native update");
                }
            } catch (RuntimeException failure) {
                if (failure.getClass().getName().equals("zombie.core.opengl.RenderContextQueueException")
                        && String.valueOf(failure.getMessage()).contains("No GLCapabilities")) {
                    updateReachedRenderBoundary = true;
                } else {
                    throw failure;
                }
            }
        }

        Object[] slotsAfter = (Object[]) playerClass.getField("players").get(null);
        require(countBefore == playerClass.getField("numPlayers").getInt(null),
                "companion changed IsoPlayer.numPlayers");
        require(Arrays.equals(slotsBefore, slotsAfter), "companion changed IsoPlayer.players");
        require(singletonBefore == playerClass.getMethod("getInstance").invoke(null),
                "companion changed the IsoPlayer singleton");
        require(cameraBefore == cameraClass.getMethod("getCameraCharacter").invoke(null),
                "companion changed the IsoCamera character");
        require(Arrays.stream(slotsAfter).noneMatch(value -> value == actor),
                "companion occupied a local-player slot");
        require(Arrays.stream(slotsAfter).noneMatch(value -> value == secondActor),
                "second companion occupied a local-player slot");
        require(slotsAfter[0] == localPlayer, "companion displaced local player 0");
        Method addOwned = SCBridge.class.getDeclaredMethod("addOwned", SCNativeCompanion.class);
        addOwned.setAccessible(true);
        addOwned.invoke(null, actor);
        addOwned.invoke(null, secondActor);
        require(SCBridge.getOwnedCount() == 2
                        && SCBridge.isCompanion(actor) && SCBridge.isCompanion(secondActor),
                "bridge identity ownership did not retain two companions");
        Object deathSquare = invoke(actor, "getCurrentSquare");
        actor.getClass().getMethod("setHealth", float.class).invoke(actor, 0.0f);
        actor.getClass().getMethod("setOnDeathDone", boolean.class).invoke(actor, true);
        var corpseReady = SCNativeCompanion.class.getDeclaredField("corpseReady");
        corpseReady.setAccessible(true);
        corpseReady.setBoolean(actor, true);
        require(SCBridge.retireDead((SCNativeCompanion) actor)
                        && SCBridge.getOwnedCount() == 1 && !SCBridge.isCompanion(actor)
                        && invoke(actor, "getCurrentSquare") == deathSquare,
                "finalized death retirement removed the corpse actor from its world square");
        Object cleanupDescriptor = companionDescriptor(false, "Cleanup");
        SCNativeCompanion cleanupActor = SCBridge.constructCompanion(
                (SurvivorDesc) cleanupDescriptor, (IsoCell) cell, 0, 0, 0);
        cleanupActor.setCurrentSquare((zombie.iso.IsoGridSquare) square);
        cleanupActor.setSquare((zombie.iso.IsoGridSquare) square);
        cleanupActor.setMovingSquare((zombie.iso.IsoGridSquare) square);
        addOwned.invoke(null, cleanupActor);
        SCBridge.failNextCleanupStepForTests("current-square");
        require(!SCBridge.remove(cleanupActor)
                        && SCBridge.isCompanion(cleanupActor)
                        && SCBridge.getOwnedCount() == 2
                        && SCBridge.getCleanupPendingCount() == 1
                        && !SCBridge.getCleanupFailure(cleanupActor).isEmpty(),
                "failed teardown lost native ownership or cleanup evidence");
        require(SCBridge.retryCleanup(cleanupActor)
                        && !SCBridge.isCompanion(cleanupActor)
                        && SCBridge.getCleanupPendingCount() == 0
                        && SCBridge.getOwnedCount() == 1,
                "native cleanup retry did not commit ownership removal");
        require(SCBridge.removeAll() && SCBridge.getOwnedCount() == 0
                        && !SCBridge.isCompanion(secondActor),
                "bridge teardown did not clear all owned companion references: "
                        + SCBridge.getLastFailure());
        System.out.println("ISO_COMPANION_CONTROL_PASS actors=2 index=3 components=true local-state=unchanged"
                + " movement=true animation-scalars=true rollback=true transient-ownership=true ownership=true permadeath=true teardown=true"
                + " cleanup-retry=true update="
                + (updateReachedRenderBoundary ? "contained-render-boundary" : "complete"));
    }
}
