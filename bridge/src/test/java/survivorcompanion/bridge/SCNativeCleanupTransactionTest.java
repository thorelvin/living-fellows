// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;

import zombie.MainThread;
import zombie.characters.SurvivorDesc;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.SliceY;

/** Real-game-JAR fault matrix for bridge ownership and native teardown. */
public final class SCNativeCleanupTransactionTest {
    private SCNativeCleanupTransactionTest() {}

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Object invoke(Method method, Object target, Object... arguments)
            throws Exception {
        try {
            return method.invoke(target, arguments);
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException runtime) throw runtime;
            if (cause instanceof Error error) throw error;
            if (cause instanceof Exception exception) throw exception;
            throw failure;
        }
    }

    @SuppressWarnings({ "rawtypes", "unchecked" })
    private static SurvivorDesc companionDescriptor(boolean female, String forename)
            throws Exception {
        Class<?> factoryClass = Class.forName("zombie.characters.SurvivorFactory");
        Class<?> typeClass = Class.forName("zombie.characters.SurvivorFactory$SurvivorType");
        List<String> forenames = (List<String>) factoryClass
                .getField(female ? "FemaleForenames" : "MaleForenames").get(null);
        List<String> surnames = (List<String>) factoryClass.getField("Surnames").get(null);
        if (forenames.isEmpty()) forenames.add(forename);
        if (surnames.isEmpty()) surnames.add("Companion");
        Object neutral = Enum.valueOf((Class<? extends Enum>) typeClass, "Neutral");
        SurvivorDesc descriptor = (SurvivorDesc) factoryClass
                .getMethod("CreateSurvivor", typeClass, boolean.class)
                .invoke(null, neutral, female);
        descriptor.setForename(forename);
        descriptor.setSurname("Companion");
        return descriptor;
    }

    @SuppressWarnings("unchecked")
    private static void initializeCharacterRuntime() throws Exception {
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);

        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir")
                        + "SurvivorCompanion-native-cleanup-control");
        fileSystemClass.getMethod("init").invoke(fileSystem);

        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        managerClass.getMethod("RunLua", String.class).invoke(null,
                "media/lua/shared/Definitions/HairOutfitDefinitions.lua");
        Class.forName("zombie.core.skinnedmodel.population.HairStyles")
                .getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.BeardStyles")
                .getMethod("init").invoke(null);
        Class.forName("zombie.core.skinnedmodel.population.OutfitManager")
                .getMethod("init").invoke(null);
        Object hairDefinitions = Class.forName("zombie.characters.HairOutfitDefinitions")
                .getField("instance").get(null);
        hairDefinitions.getClass().getMethod("checkDirty").invoke(hairDefinitions);

        Class<?> colorClass = Class.forName("zombie.core.ImmutableColor");
        Object color = colorClass.getConstructor(float.class, float.class, float.class)
                .newInstance(0.3f, 0.2f, 0.1f);
        List<Object> commonHairColors = (List<Object>) Class
                .forName("zombie.characters.SurvivorDesc")
                .getField("HairCommonColors").get(null);
        if (commonHairColors.isEmpty()) commonHairColors.add(color);
        Object populationTemplates = Class
                .forName("zombie.core.skinnedmodel.population.PopTemplateManager")
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
        Class.forName("zombie.entity.GameEntityManager")
                .getMethod("Init", int.class).invoke(null, 0);
        // The headless runtime does not load the ordinary name catalog. Seed
        // the same factory lists used by production requestSpawn().
        companionDescriptor(false, "Seed");
    }

    private static IsoGridSquare newSquare(IsoCell cell, int x, int y) throws Exception {
        return new IsoGridSquare(cell, new SliceY(), x, y, 0);
    }

    private static IsoGridSquare[][] newSafeGrid(IsoCell cell, int originX, int originY)
            throws Exception {
        IsoGridSquare[][] grid = new IsoGridSquare[3][3];
        Object chunk = Class.forName("zombie.iso.IsoChunk")
                .getConstructor(IsoCell.class).newInstance(cell);
        Class<?> flagClass = Class.forName("zombie.iso.SpriteDetails.IsoFlagType");
        Object solidFloor = flagClass.getField("solidfloor").get(null);
        for (int x = 0; x < 3; x++) {
            for (int y = 0; y < 3; y++) {
                IsoGridSquare square = newSquare(cell, originX + x, originY + y);
                square.getClass().getField("chunk").set(square, chunk);
                Object properties = square.getClass().getMethod("getProperties").invoke(square);
                properties.getClass().getMethod("set", flagClass).invoke(properties, solidFloor);
                square.getClass().getField("solidFloor").setBoolean(square, true);
                square.getClass().getField("solidFloorCached").setBoolean(square, true);
                grid[x][y] = square;
            }
        }
        for (int x = 0; x < 3; x++) {
            for (int y = 0; y < 3; y++) {
                IsoGridSquare square = grid[x][y];
                if (x > 0) square.getClass().getField("w").set(square, grid[x - 1][y]);
                if (x < 2) square.getClass().getField("e").set(square, grid[x + 1][y]);
                if (y > 0) square.getClass().getField("n").set(square, grid[x][y - 1]);
                if (y < 2) square.getClass().getField("s").set(square, grid[x][y + 1]);
            }
        }
        return grid;
    }

    private static SCNativeCompanion newActor(IsoCell cell, IsoGridSquare square,
            String name) throws Exception {
        SCNativeCompanion actor = SCBridge.constructCompanion(
                companionDescriptor(false, name), cell, square.getX(), square.getY(), square.getZ());
        actor.setX(square.getX() + 0.5f);
        actor.setY(square.getY() + 0.5f);
        actor.setZ(square.getZ());
        actor.setCurrentSquare(square);
        actor.setSquare(square);
        actor.setMovingSquare(square);
        return actor;
    }

    private static void addOwned(SCNativeCompanion actor) throws Exception {
        Method addOwned = SCBridge.class.getDeclaredMethod("addOwned", SCNativeCompanion.class);
        addOwned.setAccessible(true);
        invoke(addOwned, null, actor);
    }

    private static void completeSpawn(long requestId) throws Exception {
        Method complete = SCBridge.class.getDeclaredMethod("completeSpawn", long.class);
        complete.setAccessible(true);
        invoke(complete, null, requestId);
    }

    private static void initializeWorldAndLocalPlayer(IsoCell cell, IsoGridSquare localSquare)
            throws Exception {
        Class<?> worldClass = Class.forName("zombie.iso.IsoWorld");
        Object world = worldClass.getConstructor().newInstance();
        worldClass.getField("instance").set(null, world);
        worldClass.getField("currentCell").set(world, cell);

        Class<?> descriptorClass = Class.forName("zombie.characters.SurvivorDesc");
        Object descriptor = descriptorClass.getConstructor().newInstance();
        descriptorClass.getMethod("setForename", String.class).invoke(descriptor, "Control");
        descriptorClass.getMethod("setSurname", String.class).invoke(descriptor, "Player");
        descriptorClass.getMethod("setFemale", boolean.class).invoke(descriptor, false);

        Class<?> colorClass = Class.forName("zombie.core.ImmutableColor");
        Object color = colorClass.getConstructor(float.class, float.class, float.class)
                .newInstance(0.3f, 0.2f, 0.1f);
        Object visual = descriptorClass.getMethod("getHumanVisual").invoke(descriptor);
        visual.getClass().getMethod("setHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalHairColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setNaturalBeardColor", colorClass).invoke(visual, color);
        visual.getClass().getMethod("setHairModel", String.class).invoke(visual, "Bald");
        visual.getClass().getMethod("setBeardModel", String.class).invoke(visual, "");
        visual.getClass().getMethod("setSkinTextureName", String.class)
                .invoke(visual, "MaleBody01");

        Class<?> playerClass = Class.forName("zombie.characters.IsoPlayer");
        Object localPlayer = playerClass.getConstructor(IsoCell.class, descriptorClass,
                        int.class, int.class, int.class, boolean.class)
                .newInstance(cell, descriptor, localSquare.getX(), localSquare.getY(), 0, false);
        localPlayer.getClass().getMethod("setCurrentSquare", IsoGridSquare.class)
                .invoke(localPlayer, localSquare);
        playerClass.getMethod("setLocalPlayer", int.class, playerClass)
                .invoke(null, 0, localPlayer);
        playerClass.getMethod("setInstance", playerClass).invoke(null, localPlayer);
        Class<?> gameCharacterClass = Class.forName("zombie.characters.IsoGameCharacter");
        Class.forName("zombie.iso.IsoCamera")
                .getMethod("setCameraCharacter", gameCharacterClass)
                .invoke(null, localPlayer);
    }

    private static void initializeBridgeReadiness() throws Exception {
        MainThread.mainThread = Thread.currentThread();
        Field initialized = MainThread.class.getDeclaredField("isInitialized");
        initialized.setAccessible(true);
        initialized.setBoolean(null, true);
        SCBootstrap.start();
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (!SCBootstrap.isReady() && System.nanoTime() < deadline) Thread.sleep(10L);
        require(SCBootstrap.isReady(), "native bridge did not become ready: "
                + SCBootstrap.getStatus());
        require(SCBridge.checkReady().isEmpty(),
                "headless native bridge readiness failed: " + SCBridge.checkReady());
    }

    private static void assertCleanBridge(String context) {
        require(SCBridge.getOwnedCount() == 0, context + " left owned companions");
        require(SCBridge.getCleanupPendingCount() == 0,
                context + " left cleanup-pending companions");
        require(SCBridge.getSpawnRequestCount() == 0, context + " left spawn requests");
    }

    public static void main(String[] args) throws Exception {
        initializeCharacterRuntime();
        IsoCell cell = new IsoCell(128, 128);
        initializeWorldAndLocalPlayer(cell, newSquare(cell, 2, 2));
        initializeBridgeReadiness();

        Method validSquare = SCBridge.class.getDeclaredMethod("validSpawnSquare",
                IsoGridSquare.class);
        validSquare.setAccessible(true);
        IsoGridSquare spawnSquare = newSafeGrid(cell, 0, 0)[0][0];
        require((Boolean) invoke(validSquare, null, spawnSquare),
                "real-JAR safe-square fixture did not satisfy production validation");

        SCBridge.failNextBridgeStepsForTests("spawn:render-validation");
        long failedSpawn = SCBridge.requestSpawn(spawnSquare,
                "Render", "Failure", false, "");
        require(failedSpawn > 0L, "render-failure request was rejected: "
                + SCBridge.getLastFailure());
        completeSpawn(failedSpawn);
        String failedSpawnState = SCBridge.getSpawnState(failedSpawn);
        require(SCBridge.getSpawnResult(failedSpawn) == null
                        && SCBridge.getSpawnFailure(failedSpawn).contains("render validation"),
                "failed spawn lost its primary render-validation evidence: "
                        + SCBridge.getSpawnFailure(failedSpawn));
        if ("failed".equals(failedSpawnState)) {
            require(SCBridge.getOwnedCount() == 0
                            && SCBridge.getCleanupPendingCount() == 0
                            && SCBridge.forgetSpawnRequest(failedSpawn),
                    "clean failed-spawn teardown retained ownership or its request");
        } else {
            // Build 42's headless GameEntityManager cannot always complete the
            // world detach. Production must retain the actor and make the same
            // request retryable instead of dropping the reference.
            require("cleanup_pending".equals(failedSpawnState)
                            && SCBridge.getSpawnRequestCount() == 1
                            && SCBridge.getOwnedCount() == 1
                            && SCBridge.getCleanupPendingCount() == 1
                            && SCBridge.cancelSpawnRequest(failedSpawn),
                    "failed spawn did not retain and retry an unverified teardown: "
                            + SCBridge.getSpawnFailure(failedSpawn));
        }
        assertCleanBridge("failed spawn cleanup");

        SCBridge.failNextBridgeStepsForTests(
                "spawn:render-validation", "cleanup:current-square");
        long pendingSpawn = SCBridge.requestSpawn(spawnSquare,
                "Pending", "Cleanup", false, "");
        require(pendingSpawn > 0L, "cleanup-pending request was rejected: "
                + SCBridge.getLastFailure());
        completeSpawn(pendingSpawn);
        require("cleanup_pending".equals(SCBridge.getSpawnState(pendingSpawn))
                        && SCBridge.getSpawnResult(pendingSpawn) == null
                        && SCBridge.getSpawnRequestCount() == 1
                        && SCBridge.getOwnedCount() == 1
                        && SCBridge.getCleanupPendingCount() == 1,
                "failed spawn teardown lost its request or native ownership");
        require(SCBridge.cancelSpawnRequest(pendingSpawn)
                        && "unknown".equals(SCBridge.getSpawnState(pendingSpawn)),
                "cleanup-pending spawn could not be retried through cancellation: "
                        + SCBridge.getLastFailure());
        assertCleanBridge("failed spawn cleanup retry");

        long cancelledBeforeCompletion = SCBridge.requestSpawn(spawnSquare,
                "Cancelled", "Queued", false, "");
        require(cancelledBeforeCompletion > 0L
                        && SCBridge.cancelSpawnRequest(cancelledBeforeCompletion),
                "pending spawn cancellation failed: " + SCBridge.getLastFailure());
        completeSpawn(cancelledBeforeCompletion);
        require("unknown".equals(SCBridge.getSpawnState(cancelledBeforeCompletion)),
                "a queued completion resurrected a cancelled request");
        assertCleanBridge("cancel/queued-completion race");

        long cancelledDuringCompletion = SCBridge.requestSpawn(spawnSquare,
                "Cancelled", "Constructing", false, "");
        require(cancelledDuringCompletion > 0L,
                "constructing-race request was rejected: " + SCBridge.getLastFailure());
        CountDownLatch completionPaused = new CountDownLatch(1);
        CountDownLatch resumeCompletion = new CountDownLatch(1);
        AtomicBoolean cancellationAccepted = new AtomicBoolean();
        SCBridge.pauseSpawnCompletionForTests(completionPaused, resumeCompletion);
        Thread canceller = new Thread(() -> {
            try {
                completionPaused.await();
                cancellationAccepted.set(
                        SCBridge.cancelSpawnRequest(cancelledDuringCompletion));
            } catch (InterruptedException failure) {
                Thread.currentThread().interrupt();
            } finally {
                resumeCompletion.countDown();
            }
        }, "SC-cancel-during-construction-test");
        SCBridge.failNextCleanupStepForTests("current-square");
        canceller.start();
        completeSpawn(cancelledDuringCompletion);
        canceller.join(5_000L);
        require(!canceller.isAlive() && cancellationAccepted.get()
                        && "cleanup_pending".equals(
                                SCBridge.getSpawnState(cancelledDuringCompletion))
                        && SCBridge.getSpawnRequestCount() == 1
                        && SCBridge.getOwnedCount() == 1
                        && SCBridge.getCleanupPendingCount() == 1,
                "cancel-during-construction lost request/actor ownership: state="
                        + SCBridge.getSpawnState(cancelledDuringCompletion)
                        + " requests=" + SCBridge.getSpawnRequestCount()
                        + " owned=" + SCBridge.getOwnedCount()
                        + " cleanup=" + SCBridge.getCleanupPendingCount());
        require(SCBridge.cancelSpawnRequest(cancelledDuringCompletion)
                        && "unknown".equals(
                                SCBridge.getSpawnState(cancelledDuringCompletion)),
                "cancel-during-construction cleanup was not retryable: "
                        + SCBridge.getLastFailure());
        assertCleanBridge("cancel/during-construction race");

        IsoGridSquare cleanupSquare = newSquare(cell, 30, 30);
        String[] cleanupSteps = {
                "model", "world", "square-list", "moving-square",
                "current-square", "render-square"
        };
        for (String step : cleanupSteps) {
            SCNativeCompanion actor = newActor(cell, cleanupSquare, "Cleanup-" + step);
            addOwned(actor);
            SCBridge.failNextCleanupStepForTests(step);
            require(!SCBridge.remove(actor)
                            && SCBridge.isCompanion(actor)
                            && SCBridge.getOwnedCount() == 1
                            && SCBridge.getCleanupPendingCount() == 1
                            && SCBridge.getCleanupFailure(actor).contains(step + "="),
                    "cleanup fault lost ownership/evidence at " + step + ": "
                            + SCBridge.getLastFailure());
            require(SCBridge.retryCleanup(actor)
                            && !SCBridge.isCompanion(actor)
                            && SCBridge.getOwnedCount() == 0
                            && SCBridge.getCleanupPendingCount() == 0
                            && actor.getCurrentSquare() == null
                            && actor.getSquare() == null
                            && actor.getMovingSquare() == null
                            && !actor.isExistInTheWorld()
                            && !actor.isAddedToModelManager(),
                    "cleanup retry did not verify complete detachment at " + step + ": "
                            + SCBridge.getLastFailure());
        }
        assertCleanBridge("cleanup fault matrix");

        SCNativeCompanion first = newActor(cell, cleanupSquare, "RemoveAll-First");
        SCNativeCompanion second = newActor(cell, cleanupSquare, "RemoveAll-Second");
        // Avoid the real-JAR headless GameEntityManager boundary here so the
        // only failure is the designated transaction fault and removeAll can
        // prove that it continues to the other actor.
        for (SCNativeCompanion actor : new SCNativeCompanion[] { first, second }) {
            actor.removeFromSquare();
            actor.setMovingSquare(null);
            actor.setCurrentSquare(null);
            actor.setSquare(null);
        }
        addOwned(first);
        addOwned(second);
        SCBridge.failNextCleanupStepForTests("current-square");
        require(!SCBridge.removeAll()
                        && SCBridge.getOwnedCount() == 1
                        && SCBridge.getCleanupPendingCount() == 1
                        && (SCBridge.isCompanion(first) ^ SCBridge.isCompanion(second)),
                "removeAll did not commit one success while retaining one failure: owned="
                        + SCBridge.getOwnedCount() + " pending="
                        + SCBridge.getCleanupPendingCount() + " first="
                        + SCBridge.isCompanion(first) + " second="
                        + SCBridge.isCompanion(second) + " failure="
                        + SCBridge.getLastFailure());
        require(SCBridge.retryCleanupAll()
                        && !SCBridge.isCompanion(first)
                        && !SCBridge.isCompanion(second),
                "removeAll cleanup retry did not release the retained actor: "
                        + SCBridge.getLastFailure());
        assertCleanBridge("removeAll partial failure");

        IsoGridSquare oldCurrent = newSquare(cell, 40, 40);
        IsoGridSquare oldRender = newSquare(cell, 41, 40);
        IsoGridSquare oldMoving = newSquare(cell, 40, 41);
        SCNativeCompanion recovering = newActor(cell, oldCurrent, "Recovery");
        recovering.setSquare(oldRender);
        recovering.setMovingSquare(oldMoving);
        IsoGridSquare expectedCurrent = recovering.getCurrentSquare();
        IsoGridSquare expectedRender = recovering.getSquare();
        IsoGridSquare expectedMoving = recovering.getMovingSquare();
        float oldX = recovering.getX();
        float oldY = recovering.getY();
        float oldZ = recovering.getZ();
        boolean oldWorldMembership = recovering.isExistInTheWorld();
        addOwned(recovering);
        IsoGridSquare recoveryTarget = newSafeGrid(cell, 50, 50)[1][1];
        require((Boolean) invoke(validSquare, null, recoveryTarget),
                "recovery target did not satisfy production validation");
        SCBridge.failNextBridgeStepsForTests(
                "recovery:final-check", "recovery:headless-square-detach");
        require(!SCBridge.recover(recovering, recoveryTarget)
                        && SCBridge.getLastFailure().contains("prior state restored")
                        && SCBridge.isCompanion(recovering)
                        && SCBridge.getOwnedCount() == 1
                        && SCBridge.getCleanupPendingCount() == 0
                        && Float.compare(recovering.getX(), oldX) == 0
                        && Float.compare(recovering.getY(), oldY) == 0
                        && Float.compare(recovering.getZ(), oldZ) == 0
                        && recovering.getCurrentSquare() == expectedCurrent
                        && recovering.getSquare() == expectedRender
                        && recovering.getMovingSquare() == expectedMoving
                        && recovering.isExistInTheWorld() == oldWorldMembership,
                "recovery final-check failure did not roll back exact placement: "
                        + SCBridge.getLastFailure() + " owned=" + SCBridge.getOwnedCount()
                        + " pending=" + SCBridge.getCleanupPendingCount()
                        + " companion=" + SCBridge.isCompanion(recovering)
                        + " xyz=" + recovering.getX() + "," + recovering.getY() + ","
                        + recovering.getZ() + " expected=" + oldX + "," + oldY + ","
                        + oldZ + " current=" + (recovering.getCurrentSquare() == expectedCurrent)
                        + " render=" + (recovering.getSquare() == expectedRender)
                        + " moving=" + (recovering.getMovingSquare() == expectedMoving)
                        + " world=" + recovering.isExistInTheWorld()
                        + " expectedWorld=" + oldWorldMembership);
        if (!SCBridge.remove(recovering)) {
            require(SCBridge.isCompanion(recovering)
                            && SCBridge.getCleanupPendingCount() == 1
                            && SCBridge.retryCleanup(recovering),
                    "rolled-back companion cleanup was not retryable: "
                            + SCBridge.getLastFailure());
        }
        assertCleanBridge("recovery rollback");

        SCBridge.failNextBridgeStepsForTests();
        System.out.println("NATIVE_CLEANUP_TRANSACTION_PASS cleanup-steps=6"
                + " spawn-rollback=true request-race=true construction-race=true remove-all-partial=true"
                + " recovery-rollback=true ownership=true retry=true");
    }
}
