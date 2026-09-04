// SPDX-License-Identifier: MIT

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Public-signature gate against the installed Project Zomboid 42.20.4 JAR. */
public final class SCNativeApiSignatureTest {
    private SCNativeApiSignatureTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Method method(Class<?> type, String name, Class<?>... parameters)
            throws NoSuchMethodException {
        return type.getMethod(name, parameters);
    }

    public static void main(String[] args) throws Exception {
        Class<?> player = Class.forName("zombie.characters.IsoPlayer");
        Class<?> character = Class.forName("zombie.characters.IsoGameCharacter");
        Class<?> survivor = Class.forName("zombie.characters.IsoSurvivor");
        Class<?> cell = Class.forName("zombie.iso.IsoCell");
        Class<?> descriptor = Class.forName("zombie.characters.SurvivorDesc");
        Class<?> survivorFactory = Class.forName("zombie.characters.SurvivorFactory");
        Class<?> survivorType = Class.forName("zombie.characters.SurvivorFactory$SurvivorType");
        Class<?> attackType = Class.forName("zombie.AttackType");
        Class<?> inventoryItem = Class.forName("zombie.inventory.InventoryItem");
        Class<?> handWeapon = Class.forName("zombie.inventory.types.HandWeapon");
        Class<?> bodyDamage = Class.forName("zombie.characters.BodyDamage.BodyDamage");
        Class<?> bodyPart = Class.forName("zombie.characters.BodyDamage.BodyPart");
        Class<?> movingObject = Class.forName("zombie.iso.IsoMovingObject");
        Class<?> isoObject = Class.forName("zombie.iso.IsoObject");
        Class<?> stats = Class.forName("zombie.characters.Stats");
        Class<?> characterStat = Class.forName("zombie.characters.CharacterStat");
        Class<?> fluidContainer = Class.forName("zombie.entity.components.fluids.FluidContainer");
        Class<?> window = Class.forName("zombie.iso.objects.IsoWindow");
        Class<?> pathBehavior = Class.forName("zombie.pathfind.PathFindBehavior2");
        Class<?> luaGlobals = Class.forName("zombie.Lua.LuaManager$GlobalObject");
        Class<?> companion = Class.forName("survivorcompanion.bridge.SCNativeCompanion");
        Class<?> bridge = Class.forName("survivorcompanion.bridge.SCBridge");
        Class<?> square = Class.forName("zombie.iso.IsoGridSquare");
        Class<?> camera = Class.forName("zombie.iso.IsoCamera");
        Class<?> gameCharacter = Class.forName("zombie.characters.IsoGameCharacter");
        Class<?> mainThread = Class.forName("zombie.MainThread");
        Class<?> luaEventManager = Class.forName("zombie.Lua.LuaEventManager");
        Class<?> luaEvent = Class.forName("zombie.Lua.Event");
        Class<?> gameTime = Class.forName("zombie.GameTime");
        Class<?> roomDef = Class.forName("zombie.iso.RoomDef");
        Class<?> mapItem = Class.forName("zombie.inventory.types.MapItem");
        Class<?> worldMapSymbols = Class.forName("zombie.worldMap.symbols.WorldMapSymbols");
        Class<?> worldMapBaseSymbol = Class.forName("zombie.worldMap.symbols.WorldMapBaseSymbol");
        Class<?> worldMapTextSymbol = Class.forName("zombie.worldMap.symbols.WorldMapTextSymbol");
        Class<?> uiWorldMap = Class.forName("zombie.worldMap.UIWorldMap");
        Class<?> uiWorldMapV3 = Class.forName("zombie.worldMap.UIWorldMapV3");
        Class<?> worldMapSymbolsV2 = Class.forName("zombie.worldMap.symbols.WorldMapSymbolsV2");
        Class<?> worldMapTextSymbolV2 = Class.forName(
                "zombie.worldMap.symbols.WorldMapSymbolsV2$WorldMapTextSymbolV2");
        Class<?> kahluaTable = Class.forName("se.krka.kahlua.vm.KahluaTable");

        require(Modifier.isFinal(survivor.getModifiers()), "stock IsoSurvivor must remain final");
        require(player.isAssignableFrom(companion) && Modifier.isFinal(companion.getModifiers()),
                "SCNativeCompanion must remain a final IsoPlayer subtype");
        require(companion.getField("RESERVED_NON_LOCAL_PLAYER_INDEX").getInt(null) == 3,
                "SCNativeCompanion reserved player index changed");
        require(companion.getDeclaredMethod("isLocalPlayer").getReturnType() == boolean.class,
                "SCNativeCompanion non-local override changed");
        require(companion.getDeclaredMethod("getCompanionActionGroupName").getReturnType()
                        == String.class
                        && companion.getDeclaredMethod("getCompanionActionStateName")
                                .getReturnType() == String.class,
                "SCNativeCompanion action-context diagnostics changed");
        require(companion.getDeclaredMethod("isMoving").getReturnType() == boolean.class
                        && companion.getDeclaredMethod("isPlayerMoving").getReturnType()
                                == boolean.class
                        && companion.getDeclaredMethod("setMoving", boolean.class).getReturnType()
                                == void.class,
                "SCNativeCompanion player locomotion ownership changed");
        require(companion.getDeclaredMethod("MoveForward", float.class, float.class,
                        float.class, float.class).getReturnType() == void.class,
                "SCNativeCompanion deferred movement override changed");
        require(companion.getDeclaredMethod("update").getReturnType() == void.class,
                "SCNativeCompanion guarded update override changed");
        require(companion.getDeclaredMethod("setIsAiming", boolean.class).getReturnType()
                        == void.class
                        && companion.getDeclaredMethod("setCompanionTacticalMovement",
                                boolean.class, float.class, float.class).getReturnType()
                                == boolean.class
                        && companion.getDeclaredMethod("isCompanionTacticalMovement")
                                .getReturnType() == boolean.class,
                "SCNativeCompanion tactical locomotion contract changed");
        require(companion.getDeclaredMethod("isCompanionMovementClear",
                        float.class, float.class, float.class).getReturnType() == boolean.class,
                "SCNativeCompanion continuous collision contract changed");
        require(companion.getDeclaredMethod("addLineChatElement", String.class).getReturnType()
                        == void.class
                        && companion.getDeclaredMethod("setCompanionSpeechDisplayMillis", int.class)
                                .getReturnType() == boolean.class,
                "SCNativeCompanion readable overhead speech contract changed");
        require(method(bridge, "requestSpawn", square, String.class, String.class,
                boolean.class, String.class).getReturnType() == long.class,
                "deferred bridge requestSpawn signature changed");
        require(method(bridge, "getSpawnState", long.class).getReturnType() == String.class
                        && method(bridge, "getSpawnResult", long.class).getReturnType() == companion
                        && method(bridge, "cancelSpawnRequest", long.class).getReturnType() == boolean.class,
                "deferred bridge poll/cancel signatures changed");
        require(method(bridge, "recover", companion, square).getReturnType() == boolean.class,
                "native companion recovery signature changed");
        require(method(bridge, "retryCleanup", companion).getReturnType() == boolean.class
                        && method(bridge, "retryCleanupAll").getReturnType() == boolean.class
                        && method(bridge, "getCleanupPendingCount").getReturnType() == int.class
                        && method(bridge, "getCleanupFailure", companion).getReturnType()
                                == String.class,
                "native cleanup ownership/retry signatures changed");
        Method runtimeContract = companion.getDeclaredMethod("runtimeContractFailure");
        runtimeContract.setAccessible(true);
        require("".equals(runtimeContract.invoke(null)),
                "native private-method runtime contract failed: "
                        + runtimeContract.invoke(null));
        Method combatCollisionFailure = companion.getDeclaredMethod("combatCollisionFailure");
        combatCollisionFailure.setAccessible(true);
        Method combatCollisionReady = companion.getDeclaredMethod("combatCollisionReady");
        combatCollisionReady.setAccessible(true);
        require(Boolean.TRUE.equals(combatCollisionReady.invoke(null)),
                "native combat collision capability is unavailable (review 4.3): "
                        + combatCollisionFailure.invoke(null));
        Method floorAttackReady = companion.getDeclaredMethod("floorAttackReady");
        floorAttackReady.setAccessible(true);
        require(Boolean.TRUE.equals(floorAttackReady.invoke(null)),
                "native floor-attack (stomp) capability is unavailable (review 4.3)");
        require(method(bridge, "isCombatCollisionReady").getReturnType() == boolean.class
                        && method(bridge, "isFloorAttackReady").getReturnType() == boolean.class
                        && method(bridge, "getCombatCapabilityFailure").getReturnType()
                                == String.class,
                "combat capability bridge signatures changed (review 4.3)");
        for (String reflected : new String[] {
                "updateInternal", "updateWhileInVehicle", "checkActionGroup" }) {
            Class<?> owner = reflected.equals("updateInternal") ? character : player;
            Method privateMethod = owner.getDeclaredMethod(reflected);
            require(privateMethod.getParameterCount() == 0
                            && privateMethod.getReturnType() == void.class,
                    "version-pinned private method changed: " + owner.getSimpleName()
                            + "." + reflected);
        }
        require(method(luaEventManager, "getEvents", java.util.ArrayList.class,
                        java.util.HashMap.class).getReturnType() == void.class
                        && luaEvent.getField("callbacks").getType() == java.util.ArrayList.class,
                "constructor event-guard signatures changed");
        require(method(mainThread, "queueInvokeOnMainThread", Runnable.class).getReturnType()
                        == void.class,
                "Project Zomboid main-thread queue signature changed");
        require(method(mainThread, "isRunning").getReturnType() == boolean.class,
                "Project Zomboid main-thread readiness signature changed");
        require(method(gameTime, "getWorldAgeHours").getReturnType() == double.class
                        && method(gameTime, "getTimeOfDay").getReturnType() == float.class,
                "faction-life GameTime signatures changed");
        require(method(roomDef, "getFreeUnoccupiedSquare").getReturnType() == square,
                "faction-life RoomDef free-square signature changed");
        require(Modifier.isStatic(method(mapItem, "getSingleton").getModifiers())
                        && method(mapItem, "getSingleton").getReturnType() == mapItem
                        && method(mapItem, "getSymbols").getReturnType() == worldMapSymbols
                        && Modifier.isStatic(method(mapItem, "SaveWorldMap").getModifiers())
                        && method(mapItem, "SaveWorldMap").getReturnType() == void.class,
                "global world-map item signatures changed");
        require(Modifier.isStatic(method(worldMapSymbols, "getDefaultTextLayerID").getModifiers())
                        && method(worldMapSymbols, "getDefaultTextLayerID").getReturnType()
                                == String.class
                        && method(worldMapSymbols, "addTranslatedText", String.class,
                                String.class, float.class, float.class, float.class, float.class,
                                float.class, float.class).getReturnType() == worldMapTextSymbol,
                "world-map rumour text signatures changed");
        require(method(worldMapTextSymbol, "getTranslatedText").getReturnType() == String.class,
                "world-map rumour duplicate-detection signature changed");
        require(Modifier.isPublic(uiWorldMap.getConstructor(kahluaTable).getModifiers())
                        && method(uiWorldMap, "getAPIv3").getReturnType() == uiWorldMapV3
                        && method(uiWorldMapV3, "setMapItem", mapItem).getReturnType() == void.class
                        && method(uiWorldMapV3, "getSymbolsAPIv2").getReturnType()
                                == worldMapSymbolsV2
                        && method(worldMapSymbolsV2, "addTranslatedText", String.class,
                                String.class, float.class, float.class).getReturnType()
                                == worldMapTextSymbolV2,
                "Kahlua-visible world-map rumour bridge signatures changed");
        require(method(worldMapBaseSymbol, "setAnchor", float.class, float.class).getReturnType()
                        == void.class
                        && method(worldMapBaseSymbol, "setRGBA", float.class, float.class,
                                float.class, float.class).getReturnType() == void.class
                        && method(worldMapBaseSymbol, "setPrivate").getReturnType() == void.class,
                "world-map rumour symbol configuration signatures changed");
        require(method(camera, "getCameraCharacter").getReturnType() == gameCharacter
                        && method(camera, "setCameraCharacter", gameCharacter).getReturnType()
                                == boolean.class,
                "Project Zomboid camera ownership signatures changed");
        Constructor<?> constructor = player.getConstructor(cell, descriptor,
                int.class, int.class, int.class, boolean.class);
        require(Modifier.isPublic(constructor.getModifiers()), "IsoPlayer NPC constructor is not public");
        require(method(player, "setNpc", boolean.class).getReturnType() == void.class,
                "setNpc(boolean) signature changed");
        require(method(player, "isNpc").getReturnType() == boolean.class,
                "isNpc() signature changed");
        require(method(player, "isLocalPlayer").getReturnType() == boolean.class,
                "isLocalPlayer() signature changed");
        require(method(player, "isPlayerMoving").getReturnType() == boolean.class
                        && method(player, "updateMovementRates").getReturnType() == void.class,
                "IsoPlayer locomotion-animation signatures changed");
        require(method(player, "isRunning").getReturnType() == boolean.class
                        && method(player, "isSprinting").getReturnType() == boolean.class
                        && method(player, "isSneaking").getReturnType() == boolean.class
                        && method(player, "setRunning", boolean.class).getReturnType() == void.class
                        && method(player, "setSprinting", boolean.class).getReturnType() == void.class
                        && method(player, "setSneaking", boolean.class).getReturnType() == void.class,
                "Copy-player locomotion signatures changed");
        require(method(player, "setIsAiming", boolean.class).getReturnType() == void.class
                        && method(player, "isAiming").getReturnType() == boolean.class,
                "IsoPlayer weapon-ready animation signatures changed");
        require(method(player, "setInstance", player).getReturnType() == void.class,
                "IsoPlayer.setInstance(IsoPlayer) signature changed");
        require(method(survivorFactory, "CreateSurvivor", survivorType, boolean.class)
                        .getReturnType() == descriptor,
                "gender-correct SurvivorFactory overload changed");
        Method specificPlayer = method(luaGlobals, "getSpecificPlayer", int.class);
        require(Modifier.isStatic(specificPlayer.getModifiers())
                        && specificPlayer.getReturnType() == player,
                "Lua getSpecificPlayer(int) signature changed");
        Method activePlayers = method(luaGlobals, "getNumActivePlayers");
        require(Modifier.isStatic(activePlayers.getModifiers())
                        && activePlayers.getReturnType() == int.class,
                "Lua getNumActivePlayers() signature changed");

        require(method(player, "AttemptAttack").getParameterCount() == 0,
                "AttemptAttack must take zero arguments");
        require(method(player, "DoAttack", float.class).getReturnType() == boolean.class,
                "DoAttack(float) signature changed");
        require(method(player, "CanAttack").getReturnType() == boolean.class,
                "CanAttack() signature changed");
        require(method(player, "setDoShove", boolean.class).getReturnType() == void.class
                        && method(player, "isDoShove").getReturnType() == boolean.class,
                "shove action-state signatures changed");
        require(method(player, "setDoGrapple", boolean.class).getReturnType() == void.class
                        && method(player, "isDoGrapple").getReturnType() == boolean.class,
                "grapple action-state signatures changed");
        require(method(player, "setAttackType", attackType).getReturnType() == void.class,
                "setAttackType(AttackType) signature changed");
        require(method(player, "getAttackType").getReturnType() == attackType
                        && method(player, "getUseHandWeapon").getReturnType() == handWeapon
                        && method(player, "getPrimaryHandItem").getReturnType() == inventoryItem
                        && method(player, "getSecondaryHandItem").getReturnType() == inventoryItem,
                "native attack/equipment readback signatures changed");
        require(method(player, "isPerformingAttackAnimation").getReturnType() == boolean.class
                        && method(player, "clearHandToHandAttack").getReturnType() == void.class,
                "native attack animation lifecycle signatures changed");
        require(method(player, "setAuthorizedHandToHandAction", boolean.class).getReturnType() == void.class
                        && method(player, "isAuthorizedHandToHandAction").getReturnType() == boolean.class,
                "melee-action authorization signatures changed");
        require(method(player, "setAuthorizedHandToHand", boolean.class).getReturnType() == void.class
                        && method(player, "isAuthorizedHandToHand").getReturnType() == boolean.class,
                "shove authorization signatures changed");
        require(method(player, "setAuthorizeShoveStomp", boolean.class).getReturnType() == void.class,
                "setAuthorizeShoveStomp(boolean) signature changed");
        for (String constant : new String[] { "SHOVE", "STOMP", "SHOT", "MELEE_SWING" }) {
            require(Enum.valueOf(attackType.asSubclass(Enum.class), constant) != null,
                    "AttackType." + constant + " is unavailable");
        }

        require(method(character, "faceLocationF", float.class, float.class).getReturnType() == boolean.class,
                "faceLocationF(float,float) signature changed");
        require(method(character, "getForwardDirectionX").getReturnType() == float.class,
                "getForwardDirectionX() signature changed");
        require(method(character, "getForwardDirectionY").getReturnType() == float.class,
                "getForwardDirectionY() signature changed");
        require(method(character, "isTurning").getReturnType() == boolean.class,
                "isTurning() signature changed");
        require(method(character, "MoveForward", float.class, float.class, float.class,
                float.class).getReturnType() == void.class, "MoveForward signature changed");
        require(method(character, "canStandAt", float.class, float.class,
                float.class).getReturnType() == boolean.class, "canStandAt signature changed");
        require(method(character, "setForwardDirection", float.class,
                float.class).getReturnType() == void.class, "setForwardDirection signature changed");
        require(method(character, "setSittingOnFurniture", boolean.class).getReturnType() == void.class,
                "setSittingOnFurniture signature changed");
        require(method(character, "setSitOnFurnitureObject", isoObject).getReturnType() == void.class,
                "setSitOnFurnitureObject signature changed");
        require(method(character, "playEmote", String.class).getReturnType() == void.class,
                "playEmote(String) signature changed");
        require(method(character, "hasFullInventory").getReturnType() == boolean.class,
                "hasFullInventory() signature changed");
        require(method(stats, "get", characterStat).getReturnType() == float.class,
                "Stats.get(CharacterStat) signature changed");
        require(method(stats, "set", characterStat, float.class).getReturnType() == boolean.class,
                "Stats.set(CharacterStat,float) signature changed");
        require(method(isoObject, "hasFluid").getReturnType() == boolean.class
                        && method(isoObject, "getFluidAmount").getReturnType() == float.class
                        && method(isoObject, "isTaintedWater").getReturnType() == boolean.class,
                "IsoObject water-source signatures changed");
        require(method(fluidContainer, "isFilledWithCleanWater").getReturnType() == boolean.class
                        && method(fluidContainer, "isPoisonous").getReturnType() == boolean.class
                        && method(fluidContainer, "isTainted").getReturnType() == boolean.class
                        && method(fluidContainer, "canPlayerEmpty").getReturnType() == boolean.class,
                "FluidContainer clean-water safety signatures changed");
        require(method(pathBehavior, "pathToLocationF", float.class, float.class,
                float.class).getReturnType() == void.class, "pathToLocationF signature changed");
        require(method(pathBehavior, "isTargetLocation", float.class, float.class,
                float.class).getReturnType() == boolean.class, "isTargetLocation signature changed");
        require(method(pathBehavior, "shouldBeMoving").getReturnType() == boolean.class,
                "PathFindBehavior2.shouldBeMoving() signature changed");
        require(method(pathBehavior, "hasStartedMoving").getReturnType() == boolean.class
                        && method(pathBehavior, "isTurningToObstacle").getReturnType() == boolean.class
                        && method(pathBehavior, "isMovingUsingPathFind").getReturnType() == boolean.class
                        && method(pathBehavior, "allowTurnAnimation").getReturnType() == boolean.class
                        && method(pathBehavior, "isStrafing").getReturnType() == boolean.class,
                "PathFindBehavior2 movement telemetry signatures changed");
        require(method(pathBehavior, "pathToNearestTable", kahluaTable).getReturnType() == void.class,
                "PathFindBehavior2.pathToNearestTable(KahluaTable) signature changed");
        require(pathBehavior.getField("pathNextIsSet").getType() == boolean.class
                        && pathBehavior.getField("pathNextX").getType() == float.class
                        && pathBehavior.getField("pathNextY").getType() == float.class,
                "PathFindBehavior2 next-node telemetry fields changed");
        require(method(window, "removeBrokenGlass").getReturnType() == void.class,
                "removeBrokenGlass signature changed");
        require(method(window, "isGlassRemoved").getReturnType() == boolean.class,
                "isGlassRemoved signature changed");
        require(method(movingObject, "isExistInTheWorld").getReturnType() == boolean.class,
                "isExistInTheWorld signature changed");
        require(method(movingObject, "removeFromSquare").getReturnType() == void.class,
                "removeFromSquare signature changed");
        require(method(movingObject, "removeFromWorld").getReturnType() == void.class,
                "removeFromWorld signature changed");
        require(method(character, "setSceneCulled", boolean.class).getReturnType() == void.class,
                "setSceneCulled(boolean) signature changed");
        require(method(character, "isAddedToModelManager").getReturnType() == boolean.class,
                "isAddedToModelManager() signature changed");
        require(method(character, "hasActiveModel").getReturnType() == boolean.class,
                "hasActiveModel() signature changed");

        for (String component : new String[] {
                "getBodyDamage", "getMoodles", "getXp", "getEmitter", "getVisual" }) {
            require(method(player, component).getReturnType() != void.class,
                    component + " return type changed");
        }
        require(method(player, "update").getReturnType() == void.class,
                "IsoPlayer.update() signature changed");

        require(method(bodyDamage, "setInfected", boolean.class).getReturnType() == void.class,
                "BodyDamage.setInfected(boolean) signature changed");
        require(method(bodyDamage, "setInfectionTime", float.class).getReturnType() == void.class,
                "BodyDamage.setInfectionTime(float) signature changed");
        require(method(bodyDamage, "setInfectionMortalityDuration", float.class).getReturnType() == void.class,
                "BodyDamage.setInfectionMortalityDuration(float) signature changed");
        require(method(bodyDamage, "setOverallBodyHealth", float.class).getReturnType() == void.class,
                "BodyDamage.setOverallBodyHealth(float) signature changed");
        require(method(bodyDamage, "getOverallBodyHealth").getReturnType() == float.class,
                "BodyDamage.getOverallBodyHealth() signature changed");
        require(method(bodyDamage, "ReduceGeneralHealth", float.class).getReturnType() == void.class,
                "BodyDamage.ReduceGeneralHealth(float) signature changed");
        require(method(bodyPart, "SetHealth", float.class).getReturnType() == void.class,
                "BodyPart.SetHealth(float) signature changed");
        require(method(bodyPart, "SetBitten", boolean.class).getReturnType() == void.class,
                "BodyPart.SetBitten(boolean) signature changed");
        require(method(bodyPart, "setBandaged", boolean.class, float.class,
                boolean.class, String.class).getReturnType() == void.class,
                "BodyPart.setBandaged(boolean,float,boolean,String) signature changed");

        System.out.println("NATIVE_API_SIGNATURE_PASS IsoSurvivor-final=true IsoCompanion=true"
                + " IsoPlayer-NPC-constructor=true AttackType=true room-facing=true"
                + " player-accessors=true descriptor=true direct-native=true removal=true vitals=true"
                + " needs=true water-source=true emote=true fatal-injury=true deferred-spawn=true"
                + " faction-life=true world-map-rumours=true readable-speech=true"
                + " reflection-contract=true cleanup-retry=true");
    }
}
