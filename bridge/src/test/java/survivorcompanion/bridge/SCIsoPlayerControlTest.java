// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;

/** Non-release control showing why additional IsoPlayer instances are unsafe companions. */
public final class SCIsoPlayerControlTest {
    private SCIsoPlayerControlTest() {}

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

    public static void main(String[] args) throws ReflectiveOperationException {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-player-control-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);
        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        managerClass.getMethod("RunLua", String.class).invoke(null,
                "media/lua/shared/Definitions/HairOutfitDefinitions.lua");
        Class.forName("zombie.core.skinnedmodel.population.HairStyles")
                .getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.BeardStyles")
                .getMethod("init").invoke(null);
        Class<?> outfitManagerClass = Class.forName("zombie.core.skinnedmodel.population.OutfitManager");
        outfitManagerClass.getMethod("init").invoke(null);
        Class<?> hairDefinitionsClass = Class.forName("zombie.characters.HairOutfitDefinitions");
        Object hairDefinitions = hairDefinitionsClass.getField("instance").get(null);
        hairDefinitionsClass.getMethod("checkDirty").invoke(hairDefinitions);
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
        Object descriptor = descriptorClass.getConstructor().newInstance();
        descriptorClass.getMethod("setForename", String.class).invoke(descriptor, "Control");
        descriptorClass.getMethod("setSurname", String.class).invoke(descriptor, "Fellow");
        descriptorClass.getMethod("setFemale", boolean.class).invoke(descriptor, false);
        Object visual = descriptorClass.getMethod("getHumanVisual").invoke(descriptor);
        Class<?> colorClass = Class.forName("zombie.core.ImmutableColor");
        Object hairColor = colorClass.getConstructor(float.class, float.class, float.class)
                .newInstance(0.3f, 0.2f, 0.1f);
        visual.getClass().getMethod("setHairColor", colorClass).invoke(visual, hairColor);
        visual.getClass().getMethod("setNaturalHairColor", colorClass).invoke(visual, hairColor);
        visual.getClass().getMethod("setBeardColor", colorClass).invoke(visual, hairColor);
        visual.getClass().getMethod("setNaturalBeardColor", colorClass).invoke(visual, hairColor);
        visual.getClass().getMethod("setHairModel", String.class).invoke(visual, "Bald");
        visual.getClass().getMethod("setBeardModel", String.class).invoke(visual, "");
        visual.getClass().getMethod("setSkinTextureName", String.class).invoke(visual, "MaleBody01");
        Class<?> playerClass = Class.forName("zombie.characters.IsoPlayer");
        Object[] singletonBefore = ((Object[]) playerClass.getField("players").get(null)).clone();
        int playerCountBefore = playerClass.getField("numPlayers").getInt(null);
        Object instanceBefore = playerClass.getMethod("getInstance").invoke(null);
        Object environment = managerClass.getField("env").get(null);
        Object thread = managerClass.getField("thread").get(null);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Method rawset = tableClass.getMethod("rawset", Object.class, Object.class);
        rawset.invoke(environment, "SC_TEST_CELL", cell);
        rawset.invoke(environment, "SC_TEST_DESC", descriptor);
        String constructorMode = System.getProperty("sc.constructor", "six-false");
        String constructorExpression = switch (constructorMode) {
            case "cell" -> "IsoPlayer.new(SC_TEST_CELL)";
            case "five" -> "IsoPlayer.new(SC_TEST_CELL, SC_TEST_DESC, 0, 0, 0)";
            case "six-true" -> "IsoPlayer.new(SC_TEST_CELL, SC_TEST_DESC, 0, 0, 0, true)";
            default -> "IsoPlayer.new(SC_TEST_CELL, SC_TEST_DESC, 0, 0, 0, false)";
        };
        String fieldWriteProbe = Boolean.getBoolean("sc.fieldwrite")
                ? "local SC_TEST_PLAYER_INDEX_FIELD = getClassField(SC_TEST_ACTOR, 30)\n"
                    + "SC_TEST_PLAYER_INDEX_FIELD:setInt(SC_TEST_ACTOR, -1)\n"
                    + "assert(SC_TEST_ACTOR:getPlayerNum() == -1, 'reflected non-local player number failed')\n"
                : "";
        String source = "assert(IsoPlayer ~= nil, 'IsoPlayer is not exposed')\n"
                + "assert(IsoPlayer.new ~= nil, 'IsoPlayer constructor is not exposed')\n"
                + "SC_TEST_ACTOR = " + constructorExpression + "\n"
                + "assert(SC_TEST_ACTOR ~= nil, 'IsoPlayer construction failed')\n"
                + fieldWriteProbe
                + "SC_TEST_ACTOR:setNpc(true)\n";
        Object closure = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCIsoPlayerControlTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);
        Object actor = tableClass.getMethod("rawget", Object.class).invoke(environment, "SC_TEST_ACTOR");
        require(actor != null && playerClass.isInstance(actor), "Kahlua returned no IsoPlayer control");
        int slotProbe = Integer.getInteger("sc.slotprobe", -1);
        if (slotProbe >= 0) {
            playerClass.getMethod("setLocalPlayer", int.class, playerClass)
                    .invoke(null, slotProbe, actor);
            System.out.println("SLOT_PROBE assigned=" + slotProbe + " actorIndex="
                    + playerClass.getField("playerIndex").getInt(actor));
            playerClass.getMethod("setLocalPlayer", int.class, playerClass)
                    .invoke(null, slotProbe, (Object) null);
            System.out.println("SLOT_PROBE cleared=" + slotProbe + " actorIndex="
                    + playerClass.getField("playerIndex").getInt(actor));
        }
        actor.getClass().getMethod("setCurrentSquare", squareClass).invoke(actor, square);

        require((Boolean) invoke(actor, "isNpc"), "player control did not retain NPC mode");
        require(!(Boolean) invoke(actor, "isLocalPlayer"), "player control became a local player");
        require(invoke(actor, "getBodyDamage") != null, "player BodyDamage is null");
        require(invoke(actor, "getMoodles") != null, "player Moodles is null");
        require(invoke(actor, "getXp") != null, "player XP is null");
        require(invoke(actor, "getEmitter") != null, "player emitter is null");
        require(invoke(actor, "getVisual") != null, "player HumanVisual is null");

        require(invoke(actor, "getVehicle") == null, "new NPC control unexpectedly entered a vehicle");
        Class.forName("zombie.iso.areas.isoregion.IsoRegions").getMethod("init").invoke(null);
        boolean updatePassed = true;
        String updateBlocker = null;
        try {
            invoke(actor, "update");
            require(!(Boolean) invoke(actor, "isDead"), "NPC control died during one update");
        } catch (RuntimeException failure) {
            if (failure.getClass().getName().equals("zombie.core.opengl.RenderContextQueueException")
                    && String.valueOf(failure.getMessage()).contains("No GLCapabilities")) {
                updatePassed = false;
                updateBlocker = "headless fixture has no OpenGL render context";
            } else {
                throw failure;
            }
        }

        int playerIndex = playerClass.getField("playerIndex").getInt(actor);
        int numPlayers = playerClass.getField("numPlayers").getInt(null);
        Object[] players = (Object[]) playerClass.getField("players").get(null);
        Object instanceAfter = playerClass.getMethod("getInstance").invoke(null);
        require(playerCountBefore == numPlayers, "NPC control mutated IsoPlayer.numPlayers");
        require(Arrays.equals(singletonBefore, players), "NPC control mutated IsoPlayer.players");
        require(instanceBefore == instanceAfter, "NPC control mutated the IsoPlayer singleton");
        require(Arrays.stream(players).noneMatch(value -> value == actor),
                "NPC control occupied an IsoPlayer.players slot");
        System.out.println("IsoPlayer control native components passed; constructor=" + constructorMode
                + " playerIndex=" + playerIndex
                + " numPlayers=" + numPlayers + " singletonSlots=" + players.length
                + "; Kahlua constructor exposed=true; npc=true; local=false; singleton mutation=false");
        if (updatePassed) {
            System.out.println("IsoPlayer control update passed in the real game-Java fixture");
        } else {
            System.out.println("CONTROL_INCOMPLETE: " + updateBlocker
                    + "; update/death/vehicle behavior requires a private in-game playtest");
        }
    }
}
