// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.Reader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;

/** Real-JAR control for the stock final IsoSurvivor driven by clean Lua AI. */
public final class SCIsoSurvivorControlTest {
    private SCIsoSurvivorControlTest() {}

    private static Object invoke(Object target, String name, Object... arguments)
            throws ReflectiveOperationException {
        Method selected = Arrays.stream(target.getClass().getMethods())
                .filter(method -> method.getName().equals(name)
                        && method.getParameterCount() == arguments.length)
                .findFirst().orElseThrow();
        try {
            return selected.invoke(target, arguments);
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

    public static void main(String[] args) throws Exception {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "SurvivorCompanion-survivor-control-test");
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
        String constructor = System.getProperty("sc.survivor.constructor", "descriptor");
        String construction = switch (constructor) {
            case "cell" -> "SC_TEST_SURVIVOR = IsoSurvivor.new(SC_TEST_CELL)\n";
            case "descriptor-true" -> "SC_TEST_SURVIVOR = IsoSurvivor.new(SC_TEST_DESC, SC_TEST_CELL, 0, 0, 0, true)\n";
            case "descriptor-false" -> "SC_TEST_SURVIVOR = IsoSurvivor.new(SC_TEST_DESC, SC_TEST_CELL, 0, 0, 0, false)\n";
            default -> "SC_TEST_SURVIVOR = IsoSurvivor.new(SC_TEST_DESC, SC_TEST_CELL, 0, 0, 0)\n";
        };
        String source = "assert(IsoSurvivor ~= nil, 'IsoSurvivor is not exposed')\n"
                + "assert(IsoSurvivor.new ~= nil, 'IsoSurvivor constructor is not exposed')\n"
                + construction
                + "assert(SC_TEST_SURVIVOR ~= nil, 'IsoSurvivor construction failed')\n";
        Object closure = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCIsoSurvivorControlTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);
        Object actor = tableClass.getMethod("rawget", Object.class)
                .invoke(environment, "SC_TEST_SURVIVOR");
        Class<?> survivorClass = Class.forName("zombie.characters.IsoSurvivor");
        require(actor != null && survivorClass.isInstance(actor),
                "Kahlua returned no stock IsoSurvivor control");
        actor.getClass().getMethod("setCurrentSquare", squareClass).invoke(actor, square);

        boolean componentsReady = true;
        for (String component : new String[] {
                "getBodyDamage", "getMoodles", "getXp", "getEmitter", "getVisual",
                "getInventory", "getPathFindBehavior2", "getModData" }) {
            Object value = invoke(actor, component);
            System.out.println("SURVIVOR_COMPONENT constructor=" + constructor + " " + component
                    + "=" + (value == null ? "null" : value.getClass().getName()));
            componentsReady &= value != null;
        }
        require(componentsReady, "stock survivor has null native components");
        require(!(Boolean) invoke(actor, "isDead"), "stock survivor started dead");
        invoke(actor, "update");
        require(!(Boolean) invoke(actor, "isDead"), "stock survivor died during native update");

        require(playerCountBefore == playerClass.getField("numPlayers").getInt(null),
                "stock survivor mutated IsoPlayer.numPlayers");
        require(Arrays.equals(singletonBefore, (Object[]) playerClass.getField("players").get(null)),
                "stock survivor mutated IsoPlayer.players");
        require(instanceBefore == playerClass.getMethod("getInstance").invoke(null),
                "stock survivor mutated the IsoPlayer singleton");

        invoke(actor, "addToWorld");
        require((Boolean) invoke(actor, "isExistInTheWorld"),
                "stock survivor did not enter the world");
        invoke(actor, "removeFromWorld");
        invoke(actor, "removeFromSquare");
        actor.getClass().getMethod("setCurrentSquare", squareClass).invoke(actor, new Object[] { null });
        require(!(Boolean) invoke(actor, "isExistInTheWorld"),
                "stock survivor remained in the world after removal");
        require(invoke(actor, "getCurrentSquare") == null,
                "stock survivor retained its square after removal");

        System.out.println("ISO_SURVIVOR_CONTROL_PASS Kahlua-constructor=true components=true"
                + " update=true world-lifecycle=true local-player-state=unchanged");
    }
}
