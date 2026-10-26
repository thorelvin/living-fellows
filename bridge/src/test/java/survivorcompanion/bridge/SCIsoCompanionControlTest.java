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
import zombie.characters.IsoPlayer;
import zombie.inventory.types.HandWeapon;
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

    private static void testLivingViewHandoff(IsoPlayer primary,
            SCNativeCompanion first, SCNativeCompanion second) throws Exception {
        var field = SCSplitScreenProbe.class.getDeclaredField("leader");
        field.setAccessible(true);
        Object priorLeader = field.get(null);
        IsoPlayer[] slots = IsoPlayer.players;
        IsoPlayer priorSlot = slots[1];
        int priorCount = IsoPlayer.numPlayers;
        int firstId = first.sqlId, secondId = second.sqlId;
        try {
            first.sqlId = 2;
            second.sqlId = 3;
            first.markCoopLeaderForProbe();
            field.set(null, first);
            slots[1] = first;
            IsoPlayer.numPlayers = 2;
            IsoPlayer.setInstance(primary);
            boolean rejected = false;
            try {
                SCSplitScreenProbe.handoffLiving(second);
            } catch (IllegalStateException expected) {
                rejected = true;
            }
            require(rejected && slots[1] == first && first.sqlId == 2,
                    "living handoff overwrote a distinct saved local-player row");
            second.sqlId = -1;
            require(SCSplitScreenProbe.handoffLiving(second) == second
                            && slots[1] == second && first.sqlId == -1
                            && second.sqlId == 2 && first.getPlayerNum() == 3
                            && second.getPlayerNum() == 1,
                    "living handoff did not transfer the one local view and SQL row");
        } finally {
            first.unmarkCoopLeaderForProbe();
            second.unmarkCoopLeaderForProbe();
            first.sqlId = firstId;
            second.sqlId = secondId;
            field.set(null, priorLeader);
            slots[1] = priorSlot;
            IsoPlayer.numPlayers = priorCount;
            IsoPlayer.setInstance(primary);
        }
    }

    private static void testPrimaryViewReleaseRefresh(IsoPlayer primary,
            SCNativeCompanion formerLeader, IsoCell cell) throws Exception {
        Class<?> losClass = Class.forName("zombie.iso.LosUtil");
        boolean[] los = (boolean[]) losClass.getField("cachecleared").get(null);
        boolean[] previousLos = los.clone();
        boolean[] previousDirty = cell.playerCutawaysDirty.clone();
        var directionsField = IsoCell.class.getField("lastPlayerDir");
        Object[] directions = (Object[]) directionsField.get(cell);
        Object[] previousDirections = directions.clone();
        boolean previousGridDirty = primary.dirtyRecalcGridStack;
        float previousGridTime = primary.dirtyRecalcGridStackTime;
        var map = cell.getChunkMap(0);
        require(map != null && map.getChunks() != null && map.getChunks().length > 1,
                "primary view release fixture needs its native chunk map");
        zombie.iso.IsoChunk[] chunks = map.getChunks();
        zombie.iso.IsoChunk previousChunk = chunks[0];
        zombie.iso.IsoChunk previousUntouched = chunks[1];
        var rendered = new zombie.iso.IsoChunk(cell);
        var untouched = new zombie.iso.IsoChunk(cell);
        Object firstLevels = rendered.getRenderLevels(0);
        Object secondLevels = rendered.getRenderLevels(1);
        Method clearDirty = firstLevels.getClass().getMethod("clearDirty", int.class, float.class);
        Method isDirty = firstLevels.getClass().getMethod("isDirty", int.class, long.class, float.class);
        var nativeLevels = zombie.iso.IsoChunk.class.getDeclaredField("renderLevels");
        nativeLevels.setAccessible(true);
        Object[] untouchedLevels = (Object[]) nativeLevels.get(untouched);
        Object previousUntouchedLevels = untouchedLevels[0];
        try {
            Arrays.fill(los, false);
            Arrays.fill(cell.playerCutawaysDirty, false);
            Arrays.fill(directions, zombie.iso.IsoDirections.S);
            primary.dirtyRecalcGridStack = false;
            primary.dirtyRecalcGridStackTime = 90.0f;
            rendered.lightingNeverDone[0] = false;
            untouched.lightingNeverDone[0] = true;
            chunks[0] = rendered;
            chunks[1] = untouched;
            clearDirty.invoke(firstLevels, 0, 1.0f);
            clearDirty.invoke(secondLevels, 0, 1.0f);
            require(!(Boolean) isDirty.invoke(firstLevels, 0, 2048L, 1.0f)
                            && !(Boolean) isDirty.invoke(secondLevels, 0, 2048L, 1.0f),
                    "view release fixture starts with clean per-view cutaways");
            IsoPlayer.setInstance(primary);
            zombie.iso.IsoCamera.setCameraCharacter(formerLeader);

            SCSplitScreenProbe.restorePrimaryViewAfterRelease(primary, cell);

            require(zombie.iso.IsoCamera.getCameraCharacter() == primary
                            && IsoPlayer.getInstance() == primary
                            && IsoPlayer.players[0] == primary && IsoPlayer.players[1] == null
                            && IsoPlayer.numPlayers == 1,
                    "released companion view retained its former camera owner or altered player slots");
            require(los[0] && !los[1] && !los[2] && !los[3]
                            && cell.playerCutawaysDirty[0]
                            && !cell.playerCutawaysDirty[1] && !cell.playerCutawaysDirty[2]
                            && !cell.playerCutawaysDirty[3]
                            && directions[0] == null && directions[1] == zombie.iso.IsoDirections.S
                            && primary.dirtyRecalcGridStack && primary.dirtyRecalcGridStackTime == 0.0f,
                    "view release did not invalidate only the primary sight, peeking and grid caches");
            require((Boolean) isDirty.invoke(firstLevels, 0, 2048L, 1.0f)
                            && !(Boolean) isDirty.invoke(secondLevels, 0, 2048L, 1.0f)
                            && untouchedLevels[0] == previousUntouchedLevels,
                    "view release did not refresh rendered primary cutaways independently of other views");
        } finally {
            System.arraycopy(previousLos, 0, los, 0, los.length);
            System.arraycopy(previousDirty, 0, cell.playerCutawaysDirty, 0, previousDirty.length);
            System.arraycopy(previousDirections, 0, directions, 0, directions.length);
            primary.dirtyRecalcGridStack = previousGridDirty;
            primary.dirtyRecalcGridStackTime = previousGridTime;
            chunks[0] = previousChunk;
            chunks[1] = previousUntouched;
            IsoPlayer.setInstance(primary);
            zombie.iso.IsoCamera.setCameraCharacter(primary);
        }
    }

    private static Object privateField(Object target, String name) throws Exception {
        var field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static void clearLightingWork(zombie.iso.IsoChunk chunk) throws Exception {
        Arrays.fill((boolean[]) zombie.iso.IsoChunk.class.getField("lightCheck").get(chunk), false);
        int minimum = (Integer) zombie.iso.IsoChunk.class.getMethod("getMinLevel").invoke(chunk);
        int maximum = (Integer) zombie.iso.IsoChunk.class.getMethod("getMaxLevel").invoke(chunk);
        for (int level = minimum; level <= maximum; level++) {
            Object data = zombie.iso.IsoChunk.class.getMethod("getLevelData", int.class).invoke(chunk, level);
            Arrays.fill((boolean[]) data.getClass().getField("lightCheck").get(data), false);
        }
    }

    private static boolean lightingWorkMatches(zombie.iso.IsoChunk chunk,
            boolean primary, boolean secondary) throws Exception {
        boolean[] checks = (boolean[]) zombie.iso.IsoChunk.class.getField("lightCheck").get(chunk);
        int minimum = (Integer) zombie.iso.IsoChunk.class.getMethod("getMinLevel").invoke(chunk);
        int maximum = (Integer) zombie.iso.IsoChunk.class.getMethod("getMaxLevel").invoke(chunk);
        for (int player = 0; player < 4; player++) {
            boolean expected = player == 0 ? primary : player == 1 && secondary;
            if (checks[player] != expected) return false;
            for (int level = minimum; level <= maximum; level++) {
                Object data = zombie.iso.IsoChunk.class.getMethod("getLevelData", int.class)
                        .invoke(chunk, level);
                if (((boolean[]) data.getClass().getField("lightCheck").get(data))[player]
                        != expected) return false;
            }
        }
        return true;
    }

    private static void testDeferredPrimaryViewRestore(IsoPlayer primary,
            SCNativeCompanion formerLeader, IsoCell cell) throws Exception {
        var camera = zombie.iso.IsoCamera.frameState;
        var core = zombie.core.Core.getInstance();
        int previousWidth = zombie.core.Core.width, previousHeight = zombie.core.Core.height;
        boolean previousDebug = zombie.core.Core.debug;
        Thread previousThread = zombie.MainThread.mainThread;
        int previousFrame = camera.frameCount, previousIndex = camera.playerIndex;
        var previousFrameOwner = camera.camCharacter;
        var previousFrameSquare = camera.camCharacterSquare;
        int previousFrameWidth = camera.offscreenWidth, previousFrameHeight = camera.offscreenHeight;
        float previousZoom = camera.zoom;
        boolean previousGrid = primary.dirtyRecalcGridStack;
        float previousGridTime = primary.dirtyRecalcGridStackTime;
        boolean[] dirty = cell.playerCutawaysDirty.clone();
        boolean[] los = zombie.iso.LosUtil.cachecleared.clone();
        var chunks = cell.getChunkMap(0).getChunks();
        var previousChunk = chunks[0];
        var previousUnlitChunk = chunks[1];
        var secondaryChunks = cell.getChunkMap(1).getChunks();
        var previousSecondaryChunk = secondaryChunks[0];
        var rendered = new zombie.iso.IsoChunk(cell);
        var unlit = new zombie.iso.IsoChunk(cell);
        var secondaryOnly = new zombie.iso.IsoChunk(cell);
        Method setLevels = zombie.iso.IsoChunk.class.getMethod("setMinMaxLevel", int.class, int.class);
        setLevels.invoke(rendered, -1, 1);
        setLevels.invoke(unlit, -1, 1);
        setLevels.invoke(secondaryOnly, -1, 1);
        var primaryLevels = rendered.getRenderLevels(0);
        var secondaryLevels = rendered.getRenderLevels(1);
        Method clear = primaryLevels.getClass().getMethod("clearDirty", int.class, float.class);
        Method isDirty = primaryLevels.getClass().getMethod("isDirty", int.class, long.class, float.class);
        var cutaways = zombie.iso.fboRenderChunk.FBORenderCutaways.getInstance();
        Object[] cutawayPlayers = (Object[]) privateField(cutaways, "perPlayerData");
        var checkSquare = cutawayPlayers[0].getClass().getDeclaredField("checkSquare");
        checkSquare.setAccessible(true);
        Object previousCheck0 = checkSquare.get(cutawayPlayers[0]);
        Object previousCheck1 = checkSquare.get(cutawayPlayers[1]);
        Object[] renderPlayers = (Object[]) privateField(
                zombie.iso.fboRenderChunk.FBORenderCell.instance, "perPlayerData");
        var lastZ = renderPlayers[0].getClass().getDeclaredField("lastZ");
        lastZ.setAccessible(true);
        int[] previousLastZ = new int[4];
        for (int index = 0; index < 4; index++) previousLastZ[index] = lastZ.getInt(renderPlayers[index]);
        try {
            zombie.MainThread.mainThread = Thread.currentThread();
            zombie.core.Core.width = 1280;
            zombie.core.Core.height = 720;
            zombie.core.Core.debug = false;
            require(!SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("C"),
                    "non-debug gameplay selected the experimental renderer reset");
            zombie.core.Core.debug = true;
            require(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("B"), "B mode unavailable");
            camera.playerIndex = 0;
            camera.camCharacter = primary;
            camera.camCharacterSquare = primary.getCurrentSquare();
            camera.offscreenWidth = core.getOffscreenWidth(0);
            camera.offscreenHeight = core.getOffscreenHeight(0);
            camera.zoom = core.getZoom(0);
            require(camera.offscreenWidth > 0 && camera.offscreenHeight > 0,
                    "deferred view fixture has no native solo viewport");
            chunks[0] = rendered;
            chunks[1] = unlit;
            secondaryChunks[0] = secondaryOnly;
            rendered.lightingNeverDone[0] = false;
            unlit.lightingNeverDone[0] = true;
            clearLightingWork(rendered);
            clearLightingWork(unlit);
            clearLightingWork(secondaryOnly);
            zombie.iso.IsoChunk.class.getMethod("checkLightingLater_OnePlayer_AllLevels", int.class)
                    .invoke(secondaryOnly, 1);
            clear.invoke(primaryLevels, 0, 1.0f);
            clear.invoke(secondaryLevels, 0, 1.0f);
            checkSquare.set(cutawayPlayers[0], primary.getCurrentSquare());
            checkSquare.set(cutawayPlayers[1], primary.getCurrentSquare());
            lastZ.setInt(renderPlayers[0], 9);
            Arrays.fill(cell.playerCutawaysDirty, false);
            Arrays.fill(zombie.iso.LosUtil.cachecleared, false);
            primary.dirtyRecalcGridStack = false;
            primary.dirtyRecalcGridStackTime = 1;
            camera.frameCount = 100;
            zombie.iso.IsoCamera.setCameraCharacter(formerLeader);
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            require(!primary.dirtyRecalcGridStack && !cell.playerCutawaysDirty[0]
                            && !(Boolean) isDirty.invoke(primaryLevels, 0, 2048L, 1.0f)
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "release applied renderer work before a completed solo frame");
            require("waiting".equals(SCSplitScreenProbe.pollPrimaryViewRestore()),
                    "release consumed its own unfinished frame");
            camera.frameCount++;
            camera.playerIndex = 1;
            require("waiting".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && checkSquare.get(cutawayPlayers[0]) != null
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "stale slot-one frame consumed primary restoration");
            camera.playerIndex = 0;
            camera.offscreenWidth--;
            require("waiting".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "split viewport dimensions consumed primary restoration");
            camera.offscreenWidth++;
            camera.camCharacter = formerLeader;
            require("waiting".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "former leader frame consumed primary restoration");
            camera.camCharacter = primary;
            camera.frameCount++;
            require("applied".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && primary.dirtyRecalcGridStack && primary.dirtyRecalcGridStackTime == 20
                            && cell.playerCutawaysDirty[0] && !cell.playerCutawaysDirty[1]
                            && zombie.iso.LosUtil.cachecleared[0] && !zombie.iso.LosUtil.cachecleared[1]
                            && checkSquare.get(cutawayPlayers[0]) == null
                            && checkSquare.get(cutawayPlayers[1]) != null
                            && (Boolean) isDirty.invoke(primaryLevels, 0, 2048L, 1.0f)
                            && !(Boolean) isDirty.invoke(secondaryLevels, 0, 2048L, 1.0f)
                            && lastZ.getInt(renderPlayers[0]) == 9
                            && lightingWorkMatches(rendered, true, false)
                            && lightingWorkMatches(unlit, true, false)
                            && lightingWorkMatches(secondaryOnly, false, true),
                    "B restoration missed primary caches, reset C state, or leaked to slot one");
            primary.dirtyRecalcGridStack = false;
            clearLightingWork(rendered);
            clearLightingWork(unlit);
            require("applied".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && !primary.dirtyRecalcGridStack
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "completed restoration repeated its renderer mutations");

            require(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("C"), "C mode unavailable");
            for (Object player : renderPlayers) lastZ.setInt(player, 9);
            primary.dirtyRecalcGridStackTime = 90;
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            camera.frameCount++;
            require("applied".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && primary.dirtyRecalcGridStackTime == 90,
                    "C restoration shortened a longer native grid timer");
            for (Object player : renderPlayers) require(lastZ.getInt(player) == Integer.MAX_VALUE,
                    "C restoration did not call the native CPU view reset");

            require(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("observe"), "observe unavailable");
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            require(primary.dirtyRecalcGridStackTime == 0,
                    "observe baseline changed the previously shipped immediate refresh");
            primary.dirtyRecalcGridStack = false;
            clear.invoke(primaryLevels, 0, 1.0f);
            checkSquare.set(cutawayPlayers[0], primary.getCurrentSquare());
            camera.frameCount++;
            require("applied".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && !primary.dirtyRecalcGridStack
                            && checkSquare.get(cutawayPlayers[0]) != null
                            && !(Boolean) isDirty.invoke(primaryLevels, 0, 2048L, 1.0f),
                    "observe mode changed renderer state at the deferred boundary");

            require(SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("B"), "B mode unavailable");
            clearLightingWork(rendered);
            clearLightingWork(unlit);
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            IsoPlayer.numPlayers = 2;
            require("cancelled".equals(SCSplitScreenProbe.pollPrimaryViewRestore()),
                    "new multiplayer layout retained the old solo restoration");
            require(lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "cancelled new-view restoration queued stale primary lighting work");
            IsoPlayer.numPlayers = 1;
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            var worldCell = zombie.iso.IsoWorld.class.getField("currentCell");
            var previousCell = worldCell.get(zombie.iso.IsoWorld.instance);
            try {
                worldCell.set(zombie.iso.IsoWorld.instance, null);
                require("cancelled".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                                && lightingWorkMatches(rendered, false, false)
                                && lightingWorkMatches(unlit, false, false),
                        "world identity change applied old-world lighting work");
            } finally {
                worldCell.set(zombie.iso.IsoWorld.instance, previousCell);
            }
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            require(SCSplitScreenProbe.releaseForWorldExit()
                            && "cancelled".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && !primary.dirtyRecalcGridStack,
                    "world exit performed or retained pending renderer work");
            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            camera.camCharacter = formerLeader;
            for (int count = 0; count < 60; count++) {
                camera.frameCount++;
                String status = SCSplitScreenProbe.pollPrimaryViewRestore();
                require(status.equals(count == 59 ? "failed" : "waiting"),
                        "primary-frame wait was not bounded to sixty callbacks");
            }
            camera.camCharacter = primary;
            require("failed".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && !primary.dirtyRecalcGridStack
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false),
                    "failed restoration later repeated a partial renderer reset");

            SCSplitScreenProbe.armPrimaryViewRestore(primary, cell);
            camera.playerIndex = 1;
            for (int count = 0; count < 60; count++) {
                camera.frameCount++;
                String status = SCSplitScreenProbe.pollPrimaryViewRestore();
                require(status.equals(count == 59 ? "failed" : "waiting")
                                && !primary.dirtyRecalcGridStack
                                && lightingWorkMatches(rendered, false, false)
                                && lightingWorkMatches(unlit, false, false),
                        "permanent slot-one frame escaped the bounded primary recovery");
            }
            require(SCSplitScreenProbe.releaseDiagnostics().contains("primary_frame_timeout"),
                    "stale slot-one frame timeout lost its concrete diagnostic");
            camera.playerIndex = 0;
            require("failed".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && lightingWorkMatches(rendered, false, false)
                            && lightingWorkMatches(unlit, false, false)
                            && lightingWorkMatches(secondaryOnly, false, true),
                    "a late primary frame applied timed-out lighting or altered secondary work");

            // A real promoted-to-detached transition must complete its native
            // postupdate pass while leaving local owners and frame state intact.
            formerLeader.markCoopLeaderForProbe();
            formerLeader.unmarkCoopLeaderForProbe();
            var updates = SCNativeCompanion.class.getDeclaredField("bridgePostUpdateCount");
            updates.setAccessible(true);
            long before = updates.getLong(formerLeader);
            // Use the engine's ordinary offscreen animation-skip frame. The
            // headless fixture has no body model/GL context; the rest of the
            // actual native postupdate must still return and advance count.
            var animationFrame = zombie.characters.IsoGameCharacter.class
                    .getDeclaredField("animationUpdatingThisFrame");
            animationFrame.setAccessible(true);
            boolean previousAnimationFrame = animationFrame.getBoolean(formerLeader);
            try {
                animationFrame.setBoolean(formerLeader, false);
                formerLeader.postupdate();
            } finally {
                animationFrame.setBoolean(formerLeader, previousAnimationFrame);
            }
            require(updates.getLong(formerLeader) > before
                            && formerLeader.getBridgeFailure().isEmpty()
                            && formerLeader.getPlayerNum() == 3
                            && IsoPlayer.numPlayers == 1 && IsoPlayer.players[0] == primary
                            && IsoPlayer.players[1] == null && IsoPlayer.getInstance() == primary
                            && zombie.iso.IsoCamera.getCameraCharacter() == primary
                            && camera.camCharacter == primary && camera.playerIndex == 0,
                    "completed post-demotion update changed local-player or frame ownership: count="
                            + before + "/" + updates.getLong(formerLeader)
                            + " index=" + formerLeader.getPlayerNum()
                            + " countPlayers=" + IsoPlayer.numPlayers
                            + " singleton=" + (IsoPlayer.getInstance() == primary)
                            + " camera=" + (zombie.iso.IsoCamera.getCameraCharacter() == primary)
                            + " frame=" + (camera.camCharacter == primary) + "/" + camera.playerIndex
                            + " failure=" + formerLeader.getBridgeFailure()
                            + " post=" + formerLeader.getCompanionPostUpdateDiagnostic());
        } finally {
            var cancel = SCSplitScreenProbe.class.getDeclaredMethod("cancelPrimaryViewRestore", String.class);
            cancel.setAccessible(true);
            cancel.invoke(null, "test_cleanup");
            SCSplitScreenProbe.debugSetPrimaryViewRestoreMode("B");
            zombie.core.Core.debug = previousDebug;
            zombie.core.Core.width = previousWidth;
            zombie.core.Core.height = previousHeight;
            zombie.MainThread.mainThread = previousThread;
            camera.frameCount = previousFrame;
            camera.playerIndex = previousIndex;
            camera.camCharacter = previousFrameOwner;
            camera.camCharacterSquare = previousFrameSquare;
            camera.offscreenWidth = previousFrameWidth;
            camera.offscreenHeight = previousFrameHeight;
            camera.zoom = previousZoom;
            primary.dirtyRecalcGridStack = previousGrid;
            primary.dirtyRecalcGridStackTime = previousGridTime;
            System.arraycopy(dirty, 0, cell.playerCutawaysDirty, 0, 4);
            System.arraycopy(los, 0, zombie.iso.LosUtil.cachecleared, 0, 4);
            chunks[0] = previousChunk;
            chunks[1] = previousUnlitChunk;
            secondaryChunks[0] = previousSecondaryChunk;
            checkSquare.set(cutawayPlayers[0], previousCheck0);
            checkSquare.set(cutawayPlayers[1], previousCheck1);
            for (int index = 0; index < 4; index++) lastZ.setInt(renderPlayers[index], previousLastZ[index]);
            IsoPlayer.numPlayers = 1;
            IsoPlayer.setInstance(primary);
            zombie.iso.IsoCamera.setCameraCharacter(primary);
        }
    }

    private static void testRetainedMovementAndPathState(SCNativeCompanion actor) throws Exception {
        // Repeat the previously oscillating 0.54-tile alignment pulse at several
        // decision gaps and game multipliers, using production endpoint clamping.
        for (int gap : new int[] { 6, 12, 24 }) {
            for (float multiplier : new float[] { 0.5f, 1.0f, 3.0f }) {
                float y = 0.70f;
                for (int frame = 0; frame < gap * 4; frame++) {
                    float remaining = Math.abs(0.5f - y);
                    float step = SCNativeCompanion.boundedMovementDistance(
                            0.045f, multiplier, remaining, 0.06f) * multiplier;
                    y += Math.signum(0.5f - y) * step;
                    require(y >= 0.5f - 0.00001f, "retained input overshot doorway center");
                }
                require(Math.abs(y - 0.5f) <= 0.06f,
                        "bounded alignment did not converge across delayed decisions");
            }
        }
        require(!SCNativeCompanion.validMovementTarget(Float.NaN, 1, 0, 0, .06f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 1, 0, .06f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 0, 0, -.1f, 750)
                        && !SCNativeCompanion.validMovementTarget(1, 1, 0, 0, .06f, 0),
                "invalid/manual cross-floor target was accepted");
        actor.MoveForward(.045f, 1, 0, 0);
        actor.applyBridgeMovementFacing(true);
        require(actor.getForwardDirection().x < -0.99f,
                "open-ground corpse haul faced its travel direction and pushed the body");
        actor.applyBridgeMovementFacing(false);
        require(actor.getForwardDirection().x > 0.99f,
                "ordinary open-ground movement inherited backward drag facing");
        require(actor.setCompanionMovementTarget(actor.getX() + .2f, actor.getY(), actor.getZ(), .06f, 750),
                "native manual endpoint was not retained");
        var targetField = SCNativeCompanion.class.getDeclaredField("bridgeMoveHasTarget");
        var expiryField = SCNativeCompanion.class.getDeclaredField("bridgeMoveExpiresNanos");
        targetField.setAccessible(true);
        expiryField.setAccessible(true);
        require(targetField.getBoolean(actor), "bounded movement lost its endpoint");
        actor.MoveForward(.045f, 0, 1, 0);
        require(!targetField.getBoolean(actor), "unbounded input reused the previous endpoint");
        expiryField.setLong(actor, System.nanoTime() - 1);
        require(!actor.isMoving() && !actor.hasPendingMovement(),
                "expired unbounded input retained movement or ownership");
        actor.setMoving(false);

        float stableX = actor.getX(), stableY = actor.getY();
        actor.setNextX(stableX);
        actor.setNextY(stableY);
        actor.moveUnmodded(Float.NaN, 0);
        actor.moveUnmodded(0, Float.POSITIVE_INFINITY);
        actor.MoveForward(Float.NaN, 1, 0, 0);
        require(actor.getNextX() == stableX && actor.getNextY() == stableY
                        && actor.getX() == stableX && actor.getY() == stableY,
                "invalid movement reached native physics or translated the actor");
        actor.setNextX(Float.NaN);
        actor.setNextY(Float.NaN);
        var guardPhysics = SCNativeCompanion.class.getDeclaredMethod("guardPhysicsMovement");
        guardPhysics.setAccessible(true);
        guardPhysics.invoke(actor);
        require(actor.getNextX() == stableX && actor.getNextY() == stableY
                        && actor.getCompanionCollisionDiagnostic().contains("invalid=4:"),
                "invalid pending physics vector was not discarded and diagnosed");

        var reconcile = SCNativeCompanion.class.getDeclaredMethod("reconcileBridgePathState");
        reconcile.setAccessible(true);
        var behavior = actor.getPathFindBehavior2();
        behavior.pathNextIsSet = true;
        behavior.pathNextX = 999;
        behavior.pathNextY = 999;
        actor.pathToLocationF(actor.getX() + 2, actor.getY(), actor.getZ());
        require(!behavior.pathNextIsSet, "replacement route retained a stale movement waypoint");
        // Real PFB returns isMovingUsingPathFind=true even with no route yet.
        require(behavior.isMovingUsingPathFind() && !behavior.hasStartedMoving(),
                "pending-path native API fixture changed");
        reconcile.invoke(actor);
        require("pending".equals(actor.getCompanionPathStatus()) && !actor.isPlayerMoving(),
                "pending path incorrectly started the walk animation");
        actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.found;
        reconcile.invoke(actor);
        require("ready".equals(actor.getCompanionPathStatus()) && actor.isPlayerMoving()
                        && !behavior.hasStartedMoving(),
                "ready path cannot bootstrap animation before first deferred movement");
        var applyMovementFacing = SCNativeCompanion.class
                .getDeclaredMethod("applyBridgeMovementFacing");
        applyMovementFacing.setAccessible(true);
        var manualX = SCNativeCompanion.class.getDeclaredField("bridgeMoveX");
        var manualY = SCNativeCompanion.class.getDeclaredField("bridgeMoveY");
        manualX.setAccessible(true);
        manualY.setAccessible(true);
        manualX.setFloat(actor, 0.707f);
        manualY.setFloat(actor, 0.707f);
        actor.setForwardDirection(0.0f, 1.0f);
        applyMovementFacing.invoke(actor);
        require(Math.abs(actor.getForwardDirection().x) < 0.01f
                        && actor.getForwardDirection().y > 0.99f,
                "ready path without a waypoint inherited stale southeast manual facing");
        behavior.pathNextIsSet = true;
        behavior.pathNextX = actor.getX() - 2.0f;
        behavior.pathNextY = actor.getY();
        applyMovementFacing.invoke(actor);
        require(actor.getForwardDirection().x < -0.99f
                        && Math.abs(actor.getForwardDirection().y) < 0.01f,
                "native path did not turn the model toward its current waypoint");
        actor.applyBridgeMovementFacing(true);
        require(actor.getForwardDirection().x > 0.99f,
                "native door path did not keep backward corpse drag facing");
        actor.applyBridgeMovementFacing(false);
        require(actor.getForwardDirection().x < -0.99f,
                "ordinary native path inherited backward drag facing");
        var stopping = behavior.getClass().getDeclaredField("stopping");
        stopping.setAccessible(true);
        stopping.setBoolean(behavior, true);
        reconcile.invoke(actor);
        require("stopping".equals(actor.getCompanionPathStatus()) && !actor.isPlayerMoving()
                        && actor.hasPendingMovement(),
                "stopping path must drain walk animation without losing native completion ownership");
        actor.setForwardDirection(0.0f, 1.0f);
        applyMovementFacing.invoke(actor);
        require(Math.abs(actor.getForwardDirection().x) < 0.01f
                        && actor.getForwardDirection().y > 0.99f,
                "stopping path reused stale manual facing during its animation tail");
        behavior.pathNextIsSet = true;
        behavior.cancel();
        reconcile.invoke(actor);
        require(!actor.isPlayerMoving() && !actor.hasPendingMovement()
                        && !behavior.pathNextIsSet && "none".equals(actor.getCompanionPathStatus()),
                "cancelled path retained movement or a continuation point");
        require(!SCNativeCompanion.pathRequestTerminal(true, false, false, false)
                        && SCNativeCompanion.pathRequestTerminal(false, false, false, false)
                        && SCNativeCompanion.pathRequestTerminal(true, true, false, false)
                        && SCNativeCompanion.pathRequestTerminal(true, false, true, false)
                        && SCNativeCompanion.pathRequestTerminal(true, false, false, true),
                "native path pending/terminal handshake changed");

        // The guard consumes the engine's own per-swing latch, which can reset
        // for the next swing/automatic-shot entry without a bridge cooldown.
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, false);
        require(SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED)), "first impact rejected");
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, true);
        require(!SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED)), "duplicate impact admitted");
        actor.set(zombie.ai.states.SwipeStatePlayer.ATTACKED, false);
        require(SCNativeCompanion.shouldDriveAttackCollision(true,
                        actor.get(zombie.ai.states.SwipeStatePlayer.ATTACKED))
                        && !SCNativeCompanion.shouldDriveAttackCollision(false, false),
                "new swing reset or stale-event rejection failed");
        require(SCNativeCompanion.collisionTargetAffected(1.0f, .75f, false, false)
                        && SCNativeCompanion.collisionTargetAffected(0.1f, 0.1f, false, true)
                        && !SCNativeCompanion.collisionTargetAffected(1.0f, 1.0f, false, false)
                        && !SCNativeCompanion.collisionTargetAffected(Float.NaN, Float.NaN,
                                false, false),
                "native target-specific collision evidence changed");
        require(SCNativeCompanion.shouldForceStompCollision(true, true)
                        && !SCNativeCompanion.shouldForceStompCollision(true, false)
                        && !SCNativeCompanion.shouldForceStompCollision(false, true),
                "native stomp flag was not restricted to an armed stomp swing");

        // Build 42 stores attack ownership in several independent flags. A dead
        // target can leave the animation latch active after the ordinary hand-
        // to-hand clear, which makes applyBridgeMovement reject every follow
        // pulse. The bounded stale-release contract must clear all of them.
        actor.setAttackStarted(true);
        actor.setInitiateAttack(true);
        actor.setPerformingAttackAnimation(true);
        actor.setPerformingShoveAnimation(true);
        actor.setPerformingStompAnimation(true);
        actor.setShoveStompAnim(true);
        require(actor.releaseCompanionStaleAttack()
                        && !actor.isAttackStarted()
                        && !actor.isPerformingAttackAnimation()
                        && !actor.isPerformingShoveAnimation()
                        && !actor.isPerformingStompAnimation(),
                "stale dead-target release retained a native attack owner");

        var collision = SCNativeCompanion.class.getDeclaredMethod("driveCompanionAttackCollision", String.class);
        collision.setAccessible(true);
        int serial = actor.getCompanionAttackCollisionSerial();
        require(Boolean.FALSE.equals(collision.invoke(actor, "MeleeSwing"))
                        && actor.getCompanionAttackCollisionSerial() == serial,
                "outgoing attack event advanced impact evidence outside a swing");
        require(actor.getCompanionAttackCollisionHitCount() == 0
                        && actor.getCompanionAttackCollisionTarget() == null
                        && !actor.didCompanionAttackCollisionHitTarget(),
                "rejected attack event fabricated native target-hit evidence");
        actor.getActionContext().reportEvent("EventClimbFence");
        actor.getActionContext().reportEvent("EventHitReaction");
        require(actor.cancelCompanionStuckClimb()
                        && !actor.getActionContext().hasEventOccurred("EventClimbFence")
                        && actor.getActionContext().hasEventOccurred("EventHitReaction"),
                "pending climb cancellation failed or cleared an unrelated native event");
        actor.getActionContext().clearEvent("EventHitReaction");
    }

    private static void testStockObserverCustomTeardown(IsoPlayer primary,
            SCNativeCompanion retained, IsoCell cell) throws Exception {
        boolean debug = zombie.core.Core.debug;
        Thread mainThread = zombie.MainThread.mainThread;
        IsoPlayer singleton = IsoPlayer.getInstance();
        var cameraOwner = zombie.iso.IsoCamera.getCameraCharacter();
        IsoPlayer[] slots = IsoPlayer.players.clone();
        int count = IsoPlayer.numPlayers;
        int primarySql = primary.sqlId, retainedSql = retained.sqlId;
        var joins = zombie.iso.IsoWorld.instance.addCoopPlayers;
        int joinCount = joins.size();
        var map = cell.getChunkMap(1);
        boolean ignored = map.ignore;
        var primaryMap = cell.getChunkMap(0);
        boolean primaryIgnored = primaryMap.ignore;
        String[] boundsNames = { "xMinTiles", "xMaxTiles", "yMinTiles", "yMaxTiles" };
        int[] previousBounds = new int[4];
        for (int index = 0; index < 4; index++) {
            var field = primaryMap.getClass().getDeclaredField(boundsNames[index]);
            field.setAccessible(true);
            previousBounds[index] = field.getInt(primaryMap);
        }
        IsoPlayer observer = null;
        try {
            zombie.MainThread.mainThread = Thread.currentThread();
            zombie.core.Core.debug = false;
            boolean rejected = false;
            try { SCSplitScreenProbe.start(0, 0, 0); }
            catch (IllegalStateException expected) { rejected = true; }
            require(rejected && !SCSplitScreenProbe.debugReleaseStockObserver(primary)
                            && SCSplitScreenProbe.debugPlayerSqlId(primary) == Integer.MIN_VALUE,
                    "stock diagnostic was admitted outside debug mode");
            zombie.core.Core.debug = true;
            require(!SCSplitScreenProbe.debugReleaseStockObserver(primary)
                            && !SCSplitScreenProbe.debugReleaseStockObserver(retained)
                            && SCSplitScreenProbe.debugPlayerSqlId(primary) == primary.sqlId,
                    "stock teardown accepted an untracked primary or retained companion");
            // No PlayerDB is opened by this fixture. A positive identity that
            // its allocator has never reserved must be rejected before joining.
            primary.sqlId = 1234567;
            rejected = false;
            try { SCSplitScreenProbe.start(0, 0, 0); }
            catch (IllegalStateException expected) {
                rejected = String.valueOf(expected.getMessage()).contains("not reserved");
            }
            primary.sqlId = primarySql;
            require(rejected && IsoPlayer.numPlayers == 1 && IsoPlayer.players[1] == null,
                    "stock observer risked assigning an unreserved retained SQL row");

            observer = SCSplitScreenProbe.start(0, 0, 0);
            require(observer.getClass() == IsoPlayer.class && observer.sqlId == -1
                            && primary.sqlId == primarySql && retained.sqlId == retainedSql
                            && joins.size() == joinCount + 1
                            && !SCSplitScreenProbe.debugReleaseStockObserver(observer),
                    "stock start copied a retained identity or released an incomplete join");
            require(SCSplitScreenProbe.acceptsDebugStockObserverLayout(IsoPlayer.players)
                            && SCSplitScreenProbe.isDebugStockObserver(observer),
                    "exact tracked stock loader did not preserve companions during its asynchronous join");
            var loader = joins.remove(joins.size() - 1);
            require(!SCSplitScreenProbe.acceptsDebugStockObserverLayout(IsoPlayer.players),
                    "missing exact loader retained permission for a pending stock view");
            joins.add(loader);
            // Complete only the loader's public layout in this deterministic
            // fixture. Actual AddCoopPlayer streaming/render is the live gate.
            joins.remove(joins.size() - 1);
            IsoPlayer.players[1] = observer;
            observer.setCurrentSquare(primary.getCurrentSquare());
            observer.setSquare(primary.getCurrentSquare());
            observer.setMovingSquare(primary.getCurrentSquare());
            cell.getObjectList().add(observer);
            cell.getAddList().add(observer);
            map.ignore = false;
            primaryMap.ignore = false;
            for (int index = 0; index < 4; index++) {
                var field = primaryMap.getClass().getDeclaredField(boundsNames[index]);
                field.setAccessible(true);
                field.setInt(primaryMap, index % 2 == 0 ? -8 : 8);
            }
            zombie.core.Core.debug = false;
            require(!SCSplitScreenProbe.acceptsDebugStockObserverLayout(IsoPlayer.players)
                            && !SCSplitScreenProbe.isDebugStockObserver(observer),
                    "stock layout exception escaped its debug guard");
            zombie.core.Core.debug = true;
            IsoPlayer.players[1] = primary;
            require(!SCSplitScreenProbe.acceptsDebugStockObserverLayout(IsoPlayer.players)
                            && !SCSplitScreenProbe.isDebugStockObserver(primary),
                    "a foreign slot-one player inherited the tracked stock exception");
            IsoPlayer.players[1] = observer;
            var isolation = SCBridge.class.getDeclaredMethod("localPlayerIsolationFailure");
            isolation.setAccessible(true);
            require("".equals(isolation.invoke(null)),
                    "tracked stock comparator would retire retained companions through the runtime gate");
            primary.sqlId = primarySql + 1;
            require(!SCSplitScreenProbe.debugReleaseStockObserver(observer)
                            && SCSplitScreenProbe.releaseDiagnostics().contains("stockIssue=protected_sql_changed"),
                    "stock teardown ignored a changed primary SQL identity");
            primary.sqlId = primarySql;
            float x = observer.getX();
            observer.setX(primary.getX() + 17.0f);
            require(!SCSplitScreenProbe.debugReleaseStockObserver(observer)
                            && SCSplitScreenProbe.releaseDiagnostics().contains("stockIssue=primary_area_unavailable"),
                    "stock teardown unloaded a remote area the primary does not own");
            observer.setX(x);
            // Vanilla removeFromWorld always obtains its animation player to
            // release ragdoll state. Supply an initialized empty native player
            // because this headless fixture has no body model to allocate one.
            Class<?> animationType = Class.forName("zombie.core.skinnedmodel.animation.AnimationPlayer");
            var animationConstructor = animationType.getDeclaredConstructor();
            animationConstructor.setAccessible(true);
            var animationField = zombie.characters.IsoGameCharacter.class.getDeclaredField("animPlayer");
            animationField.setAccessible(true);
            animationField.set(observer, animationConstructor.newInstance());
            int lightingOriginX = (Integer) map.getClass().getMethod("getWorldXMin").invoke(map);
            int lightingOriginY = (Integer) map.getClass().getMethod("getWorldYMin").invoke(map);
            require(SCSplitScreenProbe.debugReleaseStockObserver(observer),
                    "guarded stock custom teardown failed: " + SCSplitScreenProbe.releaseDiagnostics());
            var pendingRestore = SCSplitScreenProbe.class.getDeclaredField("primaryViewRestore");
            pendingRestore.setAccessible(true);
            Object lightingPlan = privateField(pendingRestore.get(null), "lightingRelease");
            require(lightingPlan != null
                            && ((Integer) privateField(lightingPlan, "originX")) == lightingOriginX
                            && ((Integer) privateField(lightingPlan, "originY")) == lightingOriginY
                            && SCSplitScreenProbe.releaseDiagnostics().contains("secondaryLighting=pending"),
                    "committed release lost the active secondary lighting origin before deferred retirement");
            require(SCSplitScreenProbe.isReleased() && IsoPlayer.getInstance() == primary
                            && zombie.iso.IsoCamera.getCameraCharacter() == primary
                            && observer.getCurrentSquare() == null && !observer.isExistInTheWorld()
                            && !cell.getObjectList().contains(observer) && !cell.getAddList().contains(observer)
                            && primary.sqlId == primarySql && retained.sqlId == retainedSql && observer.sqlId == -1
                            && SCSplitScreenProbe.releaseDiagnostics().contains("stockIssue=released_custom_stock_teardown")
                            && "waiting".equals(SCSplitScreenProbe.pollPrimaryViewRestore())
                            && !SCSplitScreenProbe.debugReleaseStockObserver(observer),
                    "stock teardown changed retained SQL/actors, repeated removal, or missed deferred restoration");
        } finally {
            SCSplitScreenProbe.releaseForWorldExit();
            while (joins.size() > joinCount) joins.remove(joins.size() - 1);
            System.arraycopy(slots, 0, IsoPlayer.players, 0, slots.length);
            IsoPlayer.numPlayers = count;
            primary.sqlId = primarySql;
            retained.sqlId = retainedSql;
            if (observer != null) {
                cell.getObjectList().remove(observer);
                cell.getAddList().remove(observer);
            }
            map.ignore = ignored;
            primaryMap.ignore = primaryIgnored;
            for (int index = 0; index < 4; index++) {
                var field = primaryMap.getClass().getDeclaredField(boundsNames[index]);
                field.setAccessible(true);
                field.setInt(primaryMap, previousBounds[index]);
            }
            IsoPlayer.setInstance(singleton);
            zombie.iso.IsoCamera.setCameraCharacter(cameraOwner);
            zombie.MainThread.mainThread = mainThread;
            zombie.core.Core.debug = debug;
        }
    }

    private static void testReadOnlyGroundWallSample(IsoPlayer primary, IsoCell cell) throws Exception {
        var square = primary.getCurrentSquare();
        var map = cell.getChunkMap(0);
        var chunks = map.getChunks();
        var previousChunk = chunks[0];
        boolean previousIgnore = map.ignore, previousDebug = zombie.core.Core.debug;
        var chunkField = square.getClass().getField("chunk");
        Object previousSquareChunk = chunkField.get(square);
        String[] boundsNames = { "xMinTiles", "xMaxTiles", "yMinTiles", "yMaxTiles" };
        int[] previousBounds = new int[4];
        var performance = Class.forName("zombie.core.PerformanceSettings").getField("fboRenderChunk");
        boolean previousFbo = performance.getBoolean(null);
        byte[] flags = (byte[]) privateField(square, "targetPlayerCutawayFlags");
        byte previousFlag = flags[0];
        var chunk = new zombie.iso.IsoChunk(cell);
        try {
            zombie.core.Core.debug = true;
            performance.setBoolean(null, true);
            map.ignore = false;
            for (int index = 0; index < 4; index++) {
                var field = map.getClass().getDeclaredField(boundsNames[index]);
                field.setAccessible(true);
                previousBounds[index] = field.getInt(map);
                field.setInt(map, index % 2 == 0 ? 0 : 8);
            }
            chunk.getClass().getField("loaded").setBoolean(chunk, true);
            chunk.getClass().getMethod("setSquare", int.class, int.class, int.class,
                    zombie.iso.IsoGridSquare.class).invoke(chunk, 0, 0, 0, square);
            chunkField.set(square, chunk);
            chunks[0] = chunk;
            require(cell.getGridSquare(0, 0, 0) == square,
                    "ground-wall diagnostic fixture is not in the primary map");
            Object level = chunk.getClass().getMethod("getCutawayDataForLevel", int.class).invoke(chunk, 0);
            Object levelMap = privateField(privateField(chunk, "cutawayData"), "levelData");
            require(levelMap.getClass().getMethod("get", int.class).invoke(levelMap, 32) == level,
                    "native ground cutaway level is not keyed at z+32");
            var wallType = Class.forName("zombie.iso.fboRenderChunk.FBORenderCutaways$CutawayWall");
            Object wall = wallType.getConstructor().newInstance();
            wallType.getField("x1").setInt(wall, 0);
            wallType.getField("x2").setInt(wall, 1);
            wallType.getField("y1").setInt(wall, 0);
            wallType.getField("y2").setInt(wall, 0);
            var trueRange = Class.forName("zombie.iso.fboRenderChunk.FBORenderCutaways$PlayerInRange")
                    .getField("True");
            trueRange.setAccessible(true);
            Object range = trueRange.get(null);
            java.lang.reflect.Array.set(privateField(wall, "playerInRange"), 0, range);
            ((int[]) privateField(wall, "occludedSquaresMaskForSeenRooms"))[0] = 7;
            ((List<Object>) privateField(level, "allWalls")).add(wall);
            flags[0] = 1;
            chunk.getRenderLevels(0).invalidateAll(2048L);
            Object[] levelSlots = (Object[]) privateField(chunk, "renderLevels");
            Object[] previousLevelSlots = levelSlots.clone();
            int levelCount = (Integer) levelMap.getClass().getMethod("size").invoke(levelMap);
            String facts = SCSplitScreenProbe.debugPrimaryCutawaySample(0, 0, 0);
            require(facts.contains("sample=loaded;fbo=true;targetBits=1")
                            && facts.contains("cutawaysDirty=true")
                            && facts.contains("wallsTotal=1;wallsScanned=1;wallsMatched=1;walls=N,True,7")
                            && facts.contains("frameRoom=") && facts.contains("primaryRoom=")
                            && facts.contains("viewport=") && facts.contains("primaryZoom=")
                            && Arrays.equals(levelSlots, previousLevelSlots)
                            && (Integer) levelMap.getClass().getMethod("size").invoke(levelMap) == levelCount
                            && flags[0] == 1,
                    "read-only ground-wall sample missed native z+32 data or changed cache state: " + facts);
            require(SCSplitScreenProbe.debugPrimaryCutawaySample(0, 0, 32).contains("sample=invalid_z"),
                    "cutaway sample accepted an invalid native floor");
        } finally {
            chunks[0] = previousChunk;
            chunkField.set(square, previousSquareChunk);
            flags[0] = previousFlag;
            map.ignore = previousIgnore;
            zombie.core.Core.debug = previousDebug;
            performance.setBoolean(null, previousFbo);
            for (int index = 0; index < 4; index++) {
                var field = map.getClass().getDeclaredField(boundsNames[index]);
                field.setAccessible(true);
                field.setInt(map, previousBounds[index]);
            }
        }
    }

    @SuppressWarnings("unchecked")
    /**
     * CB-02. While the engine plays an incoming reaction it owns the
     * companion's body: the bridge must contribute no translation of its own
     * and must not re-aim the actor at a retained combat target. Drives the
     * real reaction states from the installed runtime rather than asserting on
     * a name predicate in isolation.
     */
    private static void testNativeReactionOwnership(SCNativeCompanion actor,
            zombie.iso.IsoMovingObject aimTarget) throws Exception {
        var machine = actor.getStateMachine();
        var currentField = machine.getClass().getDeclaredField("currentState");
        var subStatesField = machine.getClass().getDeclaredField("subStates");
        currentField.setAccessible(true);
        subStatesField.setAccessible(true);
        Object originalRoot = currentField.get(machine);
        List<Object> slots = (List<Object>) subStatesField.get(machine);
        List<Object> originalSlots = new ArrayList<>(slots);
        Class<?> stateClass = Class.forName("zombie.ai.State");
        var slotConstructor = Class.forName("zombie.ai.StateMachine$SubstateSlot")
                .getDeclaredConstructor(stateClass);
        slotConstructor.setAccessible(true);
        var applyMovement = SCNativeCompanion.class.getDeclaredMethod("applyBridgeMovement");
        applyMovement.setAccessible(true);
        var advancePath = SCNativeCompanion.class.getDeclaredMethod("advanceBridgePath");
        advancePath.setAccessible(true);
        var applyAim = SCNativeCompanion.class.getDeclaredMethod("applyCompanionAim");
        applyAim.setAccessible(true);
        var pathActiveField = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActiveField.setAccessible(true);
        var aimTargetField = SCNativeCompanion.class.getDeclaredField("bridgeAimTarget");
        aimTargetField.setAccessible(true);
        Object originalAim = aimTargetField.get(actor);
        boolean[] movementProbeBlocked = { false };
        // The aim probe needs a target the companion is not standing on, or
        // the direction vector is zero and nothing can be observed.
        // Reached reflectively: the bridge compiles against compile-only stubs
        // that do not declare every real accessor, and widening them for a test
        // would weaken the boundary the stub-control gate protects.
        var setX = aimTarget.getClass().getMethod("setX", float.class);
        var setY = aimTarget.getClass().getMethod("setY", float.class);
        float targetX = aimTarget.getX(), targetY = aimTarget.getY();
        setX.invoke(aimTarget, actor.getX() + 3.0f);
        setY.invoke(aimTarget, actor.getY() + 3.0f);
        // applyCompanionAim drops a target that is not in the world, and
        // isExistInTheWorld() means "listed in my square's moving objects".
        // Place the probe target there for the duration of this test.
        // isExistInTheWorld() reads IsoObject.square (not getCurrentSquare(),
        // which returns the separate `current` field) and requires the object
        // to be listed in that square's moving objects.
        var squareField = Class.forName("zombie.iso.IsoObject").getDeclaredField("square");
        squareField.setAccessible(true);
        Object originalSquare = squareField.get(aimTarget);
        Object targetSquare = originalSquare != null ? originalSquare
                : invoke(aimTarget, "getCurrentSquare");
        if (originalSquare == null && targetSquare != null) {
            squareField.set(aimTarget, targetSquare);
        }
        List<Object> targetMovers = targetSquare == null ? null
                : (List<Object>) invoke(targetSquare, "getMovingObjects");
        boolean placedTarget = targetMovers != null && !targetMovers.contains(aimTarget)
                && targetMovers.add(aimTarget);
        require((Boolean) invoke(aimTarget, "isExistInTheWorld"),
                "aim probe target could not be placed in the world");
        var moveRequested = SCNativeCompanion.class.getDeclaredField("bridgeMoveRequested");
        var moving = SCNativeCompanion.class.getDeclaredField("bridgeMoving");
        var expires = SCNativeCompanion.class.getDeclaredField("bridgeMoveExpiresNanos");
        var moveX = SCNativeCompanion.class.getDeclaredField("bridgeMoveX");
        var moveY = SCNativeCompanion.class.getDeclaredField("bridgeMoveY");
        var distance = SCNativeCompanion.class.getDeclaredField("bridgeMoveDistance");
        for (var field : new java.lang.reflect.Field[] {
                moveRequested, moving, expires, moveX, moveY, distance }) {
            field.setAccessible(true);
        }
        try {
            slots.clear();
            currentField.set(machine, null);
            require(!actor.isCompanionNativeReactionActive(),
                    "idle actor falsely owns a native reaction");
            require(SCNativeCompanion.OWNER_NONE.equals(actor.getCompanionMovementOwner()),
                    "idle actor claimed a movement owner");
            for (String stateName : new String[] { "PlayerHitReactionState",
                    "PlayerHitReactionPVPState", "StaggerBackState", "PlayerFallDownState",
                    "PlayerFallingState", "PlayerGetUpState", "PlayerOnGroundState",
                    "PlayerSitOnGroundState", "BumpedState", "CollideWithWallState" }) {
                Object nativeState = Class.forName("zombie.ai.states." + stateName)
                        .getMethod("instance").invoke(null);
                currentField.set(machine, nativeState);
                require(actor.isCompanionNativeReactionActive(),
                        stateName + " was not recognised as an incoming reaction");
                require(SCNativeCompanion.OWNER_REACTION.equals(
                                actor.getCompanionMovementOwner()),
                        stateName + " did not take movement ownership");

                // Manual-movement gating is deliberately NOT asserted here.
                // isCompanionMovementClear() refuses every direction in this
                // harness world, so applyBridgeMovement cannot translate the
                // actor whether or not the reaction gate exists -- an assertion
                // would pass for the wrong reason. Recorded as an explicit gap
                // rather than a silent pass (the audit's CB-12 rule); the gate
                // itself is the same nativeOwnsBody() call proven above for
                // root motion, path advancement and facing.
                if (!movementProbeBlocked[0]) {
                    boolean anyClear = false;
                    for (float[] candidate : new float[][] {
                            { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) {
                        anyClear |= actor.isCompanionMovementClear(
                                actor.getX() + candidate[0] * 0.25f,
                                actor.getY() + candidate[1] * 0.25f, actor.getZ());
                    }
                    movementProbeBlocked[0] = !anyClear;
                    require(!anyClear,
                            "the harness world became walkable: enable the manual-movement"
                                    + " reaction assertion instead of skipping it");
                }

                pathActiveField.setBoolean(actor, true);
                actor.setVariable("bPathfind", true);
                actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.failed;
                advancePath.invoke(actor);
                require(actor.getVariableBoolean("bPathfind"),
                        stateName + " allowed a native path update to compete with the reaction");
                pathActiveField.setBoolean(actor, false);
                actor.setVariable("bPathfind", false);

                // A retained combat target must not keep rotating a companion
                // who is being hit, staggered or knocked down. Establish first
                // that this setup can turn the actor at all when no reaction
                // owns it -- otherwise the assertion that follows is vacuous.
                aimTargetField.set(actor, aimTarget);
                currentField.set(machine, null);
                actor.setForwardDirection(0.0f, 1.0f);
                applyAim.invoke(actor);
                require(actor.getForwardDirection().x != 0.0f
                                || actor.getForwardDirection().y != 1.0f,
                        "aim probe could not turn an unowned companion, so the"
                                + " reaction-facing assertion would prove nothing");
                currentField.set(machine, nativeState);
                actor.setForwardDirection(0.0f, 1.0f);
                applyAim.invoke(actor);
                require(actor.getForwardDirection().x == 0.0f
                                && actor.getForwardDirection().y == 1.0f,
                        stateName + " let a stale combat target re-aim a reacting companion");
                aimTargetField.set(actor, null);

                currentField.set(machine, null);
                slots.add(slotConstructor.newInstance(nativeState));
                require(actor.isCompanionNativeReactionActive(),
                        stateName + " child ownership was missed");
                slots.clear();
                require(!actor.isCompanionNativeReactionActive(),
                        stateName + " ownership survived state exit");
            }

            // Precedence: a held victim is often also on the ground, and it is
            // the grapple offset that positions them against the grappler.
            Object onGround = Class.forName("zombie.ai.states.PlayerOnGroundState")
                    .getMethod("instance").invoke(null);
            Object climb = Class.forName("zombie.ai.states.ClimbOverFenceState")
                    .getMethod("instance").invoke(null);
            currentField.set(machine, climb);
            require(SCNativeCompanion.OWNER_TRAVERSAL.equals(
                            actor.getCompanionMovementOwner()),
                    "traversal lost ownership to a lower-precedence claim");
            slots.add(slotConstructor.newInstance(onGround));
            require(SCNativeCompanion.OWNER_REACTION.equals(
                            actor.getCompanionMovementOwner()),
                    "a reaction did not outrank traversal");
            slots.clear();
            currentField.set(machine, null);

            require(SCNativeCompanion.ownerIsExclusiveNative(SCNativeCompanion.OWNER_GRAPPLE)
                            && SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_REACTION)
                            && SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_TRAVERSAL)
                            && SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_SEATING)
                            && !SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_ATTACK)
                            && !SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_CORPSE_DRAG)
                            && !SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_PATH)
                            && !SCNativeCompanion.ownerIsExclusiveNative(
                                    SCNativeCompanion.OWNER_NONE),
                    "native seating must own root motion while corpse dragging leaves bridge translation available");
            require(SCNativeCompanion.exclusiveGrappleOwnsBody(true, false, true)
                            && SCNativeCompanion.exclusiveGrappleOwnsBody(false, true, false)
                            && !SCNativeCompanion.exclusiveGrappleOwnsBody(false, true, true)
                            && !SCNativeCompanion.exclusiveGrappleOwnsBody(false, false, false),
                    "corpse carrier grapple was not separated from hostile grapple ownership");
            require(SCNativeCompanion.isReactionStateName("StaggerBackState")
                            && !SCNativeCompanion.isReactionStateName("IdleState")
                            && !SCNativeCompanion.isReactionStateName("PlayerHitReaction")
                            && !SCNativeCompanion.isReactionStateName(null),
                    "reaction classifier matched on something other than an exact state name");
        } finally {
            currentField.set(machine, originalRoot);
            slots.clear();
            slots.addAll(originalSlots);
            aimTargetField.set(actor, originalAim);
            setX.invoke(aimTarget, targetX);
            setY.invoke(aimTarget, targetY);
            if (placedTarget) targetMovers.remove(aimTarget);
            squareField.set(aimTarget, originalSquare);
            actor.setMoving(false);
        }
    }

    private static void testNativeTraversalOwnership(SCNativeCompanion actor) throws Exception {
        var machine = actor.getStateMachine();
        var currentField = machine.getClass().getDeclaredField("currentState");
        var subStatesField = machine.getClass().getDeclaredField("subStates");
        currentField.setAccessible(true);
        subStatesField.setAccessible(true);
        Object originalRoot = currentField.get(machine);
        List<Object> slots = (List<Object>) subStatesField.get(machine);
        List<Object> originalSlots = new ArrayList<>(slots);
        Class<?> stateClass = Class.forName("zombie.ai.State");
        var slotConstructor = Class.forName("zombie.ai.StateMachine$SubstateSlot")
                .getDeclaredConstructor(stateClass);
        slotConstructor.setAccessible(true);
        var applyMovement = SCNativeCompanion.class.getDeclaredMethod("applyBridgeMovement");
        applyMovement.setAccessible(true);
        var advancePath = SCNativeCompanion.class.getDeclaredMethod("advanceBridgePath");
        advancePath.setAccessible(true);
        var pathActiveField = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActiveField.setAccessible(true);
        require(!actor.isClimbing(), "native traversal regression requires a false legacy climbing field");
        try {
            slots.clear();
            currentField.set(machine, null);
            require(!actor.isCompanionTraversalActive(), "idle actor falsely owns native traversal");
            for (String stateName : new String[] { "ClimbOverFenceState", "ClimbOverWallState",
                    "ClimbThroughWindowState", "ClimbSheetRopeState", "ClimbDownSheetRopeState",
                    "OpenWindowState", "SmashWindowState" }) {
                Object nativeState = Class.forName("zombie.ai.states." + stateName)
                        .getMethod("instance").invoke(null);
                // Use real runtime state instances and native state-machine
                // slots without invoking world-dependent animation enter hooks.
                currentField.set(machine, nativeState);
                require(actor.isCompanionTraversalActive() && !actor.isClimbing(),
                        stateName + " root ownership was hidden by the legacy climbing field");
                actor.MoveForward(.045f, 1, 0, 0);
                float x = actor.getX(), y = actor.getY();
                applyMovement.invoke(actor);
                require(!actor.hasPendingMovement() && actor.getX() == x && actor.getY() == y,
                        stateName + " allowed retained manual input to compete with native traversal");
                pathActiveField.setBoolean(actor, true);
                actor.setVariable("bPathfind", true);
                actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.failed;
                advancePath.invoke(actor);
                require(actor.getVariableBoolean("bPathfind"),
                        stateName + " allowed native path update to compete with traversal");
                pathActiveField.setBoolean(actor, false);
                actor.setVariable("bPathfind", false);
                currentField.set(machine, null);
                slots.add(slotConstructor.newInstance(nativeState));
                require(actor.isCompanionTraversalActive(), stateName + " child ownership was missed");
                slots.clear();
                require(!actor.isCompanionTraversalActive(), stateName + " ownership survived state exit");
            }
            Object fence = Class.forName("zombie.ai.states.ClimbOverFenceState")
                    .getMethod("instance").invoke(null);
            slots.add(slotConstructor.newInstance(fence));
            actor.setVariable("ClimbingFence", true);
            actor.getActionContext().reportEvent("EventClimbFence");
            require(actor.cancelCompanionTraversal() && !actor.isCompanionTraversalActive()
                            && !actor.getVariableBoolean("ClimbingFence")
                            && !actor.getActionContext().hasEventOccurred("EventClimbFence"),
                    "native child traversal cancellation did not run its exit hook or clear its event");
        } finally {
            currentField.set(machine, originalRoot);
            slots.clear();
            slots.addAll(originalSlots);
            actor.setMoving(false);
        }
        require(actor.getCompanionCollisionDiagnostic().startsWith("move{")
                        && actor.getCompanionCollisionDiagnostic().contains("};collision{"),
                "native physics evidence is not exposed as a read-only diagnostic");
        // IsoPlayer.hopFence(dir, false) fires ClimbOverFence as its whole
        // effect; the stock handler cannot resolve a non-local companion.
        String before = actor.getCompanionContextualActionDiagnostic();
        long prior = Long.parseLong(before.substring("suppressed=".length(), before.indexOf(',')));
        actor.triggerContextualAction("ClimbOverFence", null, zombie.iso.IsoDirections.N);
        require(actor.getCompanionContextualActionDiagnostic()
                        .equals("suppressed=" + (prior + 1) + ",last=ClimbOverFence"),
                "companion entered the local player's contextual action hook");
    }

    private static void testZeroDeferredDuplicatePathNode(SCNativeCompanion actor) throws Exception {
        float x = actor.getX(), y = actor.getY(), z = actor.getZ();
        actor.pathToLocationF(x + .3f, y, z);
        var behavior = actor.getPathFindBehavior2();
        var pathField = behavior.getClass().getDeclaredField("path");
        pathField.setAccessible(true);
        var path = (zombie.pathfind.Path) pathField.get(behavior);
        path.getClass().getMethod("clear").invoke(path);
        var add = path.getClass().getMethod("addNode", float.class, float.class, float.class);
        for (float point : new float[] { x - .3f, x, x, x + .3f }) add.invoke(path, point, y, z);
        actor.getFinder().progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.found;
        actor.setPath2(path);
        var startedMoving = behavior.getClass().getDeclaredField("startedMoving");
        startedMoving.setAccessible(true);
        startedMoving.setBoolean(behavior, true);
        var deferred = actor.getDeferredMovement(new zombie.iso.Vector2());
        require(deferred.x == 0 && deferred.y == 0, "duplicate-node fixture requires zero deferred motion");
        var invalid = SCNativeCompanion.class.getDeclaredField("bridgeInvalidMovementCount");
        invalid.setAccessible(true);
        long before = invalid.getLong(actor);
        behavior.getClass().getMethod("update").invoke(behavior);
        require(invalid.getLong(actor) == before + 1,
                "real native duplicate-node fixture did not reach the zero-deferred invalid vector");
        require(Float.isFinite(actor.getNextX()) && Float.isFinite(actor.getNextY())
                        && actor.getX() == x && actor.getY() == y,
                "native zero-deferred duplicate waypoint corrupted the actor's physical position");
        behavior.cancel();
        actor.setMoving(false);
    }

    private static void testDeferredAccumulatorConsumption(SCNativeCompanion actor) throws Exception {
        Class<?> animationClass = Class.forName("zombie.core.skinnedmodel.animation.AnimationPlayer");
        var constructor = animationClass.getDeclaredConstructor();
        constructor.setAccessible(true);
        Object animation = constructor.newInstance();
        var ownerAnimation = Class.forName("zombie.characters.IsoGameCharacter").getDeclaredField("animPlayer");
        ownerAnimation.setAccessible(true);
        Object original = ownerAnimation.get(actor);
        var accumulatorField = animationClass.getDeclaredField("deferredMovementAccum");
        var snapshotField = animationClass.getDeclaredField("deferredMovement");
        accumulatorField.setAccessible(true);
        snapshotField.setAccessible(true);
        var accumulator = (zombie.iso.Vector2) accumulatorField.get(animation);
        var snapshot = (zombie.iso.Vector2) snapshotField.get(animation);
        var consume = SCNativeCompanion.class.getDeclaredMethod("consumeBridgeDeferredMovement");
        consume.setAccessible(true);
        var machine = actor.getStateMachine();
        var currentField = machine.getClass().getDeclaredField("currentState");
        currentField.setAccessible(true);
        Object originalState = currentField.get(machine);
        try {
            ownerAnimation.set(actor, animation);
            snapshot.x = .025f; snapshot.y = -.01f;
            for (int frame = 0; frame < 50; frame++) {
                accumulator.x += .025f; accumulator.y -= .01f;
                consume.invoke(actor);
                require(accumulator.x == 0 && accumulator.y == 0,
                        "unconsumed animation motion accumulated across companion simulation frames");
                require(snapshot.x == .025f && snapshot.y == -.01f,
                        "consuming the accumulator erased the native path's current motion snapshot");
            }

            // Unlike ordinary path/manual motion, stock traversal animations
            // own their displacement.  The companion omits IsoPlayer's local
            // update, so the bridge must run the inherited deferred-movement
            // step while that real native state is active.
            Object wallState = Class.forName("zombie.ai.states.ClimbOverWallState")
                    .getMethod("instance").invoke(null);
            currentField.set(machine, wallState);
            actor.setNextX(actor.getX());
            actor.setNextY(actor.getY());
            float beforeX = actor.getNextX(), beforeY = actor.getNextY();
            accumulator.x = .08f;
            accumulator.y = 0.0f;
            consume.invoke(actor);
            require(accumulator.x == 0 && accumulator.y == 0,
                    "native traversal did not consume its root-motion accumulator");
            require(actor.getNextX() != beforeX || actor.getNextY() != beforeY,
                    "native traversal success animation did not translate the companion body");

            // CB-02: an incoming reaction carries the body the same way. While
            // one owns the actor the bridge contributes no translation of its
            // own, so this root motion is the only displacement applied.
            for (String reactionState : new String[] { "PlayerHitReactionState",
                    "StaggerBackState", "PlayerFallDownState", "PlayerGetUpState" }) {
                Object state = Class.forName("zombie.ai.states." + reactionState)
                        .getMethod("instance").invoke(null);
                currentField.set(machine, state);
                actor.setNextX(actor.getX());
                actor.setNextY(actor.getY());
                float reactionX = actor.getNextX(), reactionY = actor.getNextY();
                accumulator.x = .08f;
                accumulator.y = 0.0f;
                consume.invoke(actor);
                require(accumulator.x == 0 && accumulator.y == 0,
                        reactionState + " did not consume its root-motion accumulator");
                require(actor.getNextX() != reactionX || actor.getNextY() != reactionY,
                        reactionState + " played without translating the companion body");
            }

            // SeatingManager computes a start position that includes the sit
            // clip's displacement. A normal player applies that displacement
            // in IsoPlayer.updateInternal2; the bridge must apply it here.
            Object sitState = Class.forName("zombie.ai.states.PlayerSitOnFurnitureState")
                    .getMethod("instance").invoke(null);
            currentField.set(machine, sitState);
            require(actor.isCompanionFurnitureSeatingActive()
                            && SCNativeCompanion.OWNER_SEATING.equals(
                                    actor.getCompanionMovementOwner()),
                    "furniture sit state did not take native movement ownership");
            actor.setNextX(actor.getX());
            actor.setNextY(actor.getY());
            float sitX = actor.getNextX(), sitY = actor.getNextY();
            accumulator.x = .08f;
            accumulator.y = 0.0f;
            consume.invoke(actor);
            require(accumulator.x == 0 && accumulator.y == 0
                            && (actor.getNextX() != sitX || actor.getNextY() != sitY),
                    "furniture sit animation did not translate the companion body");
            // Get On Bed is a separate native player state. Its root motion
            // must move a non-local companion off the entry tile and onto the
            // mattress just as it does for the player.
            Object bedState = Class.forName("zombie.ai.states.PlayerOnBedState")
                    .getMethod("instance").invoke(null);
            currentField.set(machine, bedState);
            require(actor.isCompanionFurnitureSeatingActive()
                            && SCNativeCompanion.OWNER_SEATING.equals(
                                    actor.getCompanionMovementOwner()),
                    "on-bed state did not take native movement ownership");
            actor.setNextX(actor.getX());
            actor.setNextY(actor.getY());
            float bedX = actor.getNextX(), bedY = actor.getNextY();
            accumulator.x = .08f;
            accumulator.y = 0.0f;
            consume.invoke(actor);
            require(accumulator.x == 0 && accumulator.y == 0
                            && (actor.getNextX() != bedX || actor.getNextY() != bedY),
                    "on-bed animation did not translate the companion body");
            currentField.set(machine, null);
            require(!actor.isCompanionFurnitureSeatingActive(),
                    "furniture movement ownership survived state exit");
        } finally {
            currentField.set(machine, originalState);
            ownerAnimation.set(actor, original);
            actor.setNextX(actor.getX());
            actor.setNextY(actor.getY());
        }
    }

    private static void testFloorAttackInputLease(SCNativeCompanion actor, Object localPlayer,
            SCNativeCompanion otherActor) throws Exception {
        Object localFloor = invoke(localPlayer, "isManualFloorAtkButtonDown");
        Object localMelee = invoke(localPlayer, "isMeleeButtonDown");
        require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "companion acquired unrequested local-player attack input");
        require(actor.setCompanionFloorAttackInput(true, false)
                        && actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "floor weapon attack did not retain manual-floor without stomp input");
        require(actor.setCompanionFloorAttackInput(false, false)
                        && !actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "failed floor preflight did not clear owned input");
        require(actor.setCompanionFloorAttackInput(true, true)
                        && actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                "stomp did not retain both manual-floor and melee input");
        Class<?> coreClass = Class.forName("zombie.core.Core");
        Object core = coreClass.getMethod("getInstance").invoke(null);
        boolean autoProne = (Boolean) coreClass.getMethod("isOptionAutoProneAtk").invoke(core);
        var setAutoProne = coreClass.getMethod("setOptionAutoProneAtk", boolean.class);
        var stompDisabled = Class.forName("zombie.ai.states.SwipeStatePlayer")
                .getMethod("isStompingDisabled", Class.forName("zombie.characters.IsoGameCharacter"), boolean.class);
        try {
            setAutoProne.invoke(core, false);
            require(Boolean.FALSE.equals(stompDisabled.invoke(null, actor, true)),
                    "native Swipe entry ignored the actor-owned floor input when player auto-prone was disabled");
            actor.setCompanionFloorAttackInput(false, false);
            require(Boolean.TRUE.equals(stompDisabled.invoke(null, actor, true)),
                    "native Swipe entry retained released floor input");
            actor.setCompanionFloorAttackInput(true, true);
        } finally {
            setAutoProne.invoke(core, autoProne);
        }
        var startDeadline = SCNativeCompanion.class.getDeclaredField("bridgeFloorInputStartDeadline");
        var hardDeadline = SCNativeCompanion.class.getDeclaredField("bridgeFloorInputHardDeadline");
        startDeadline.setAccessible(true);
        hardDeadline.setAccessible(true);
        startDeadline.setLong(actor, System.nanoTime() - 1);
        require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                "floor input remained pressed after the bounded start window");

        var machine = actor.getStateMachine();
        var stateField = machine.getClass().getDeclaredField("currentState");
        stateField.setAccessible(true);
        Object originalState = stateField.get(machine);
        try {
            require(actor.setCompanionFloorAttackInput(true, true), "stomp lease failed to rearm");
            stateField.set(machine, zombie.ai.states.SwipeStatePlayer.instance());
            require(actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                    "native swing did not inherit the explicit floor input");
            startDeadline.setLong(actor, System.nanoTime() - 1);
            require(actor.isManualFloorAtkButtonDown() && actor.isMeleeButtonDown(),
                    "pending deadline released input during an accepted native swing");
            require(!actor.setCompanionFloorAttackInput(true, false) && actor.isMeleeButtonDown(),
                    "a later input request changed the stance of an in-flight stomp");
            stateField.set(machine, originalState);
            require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "floor input was not released at native swing exit");
            require(actor.setCompanionFloorAttackInput(true, false), "floor weapon lease failed to rearm");
            stateField.set(machine, zombie.ai.states.SwipeStatePlayer.instance());
            require(actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "floor weapon lease changed into a stomp during native swing");
            hardDeadline.setLong(actor, System.nanoTime() - 1);
            require(!actor.isManualFloorAtkButtonDown() && !actor.isMeleeButtonDown(),
                    "stuck native swing retained manual-floor input past its safety bound");
        } finally {
            stateField.set(machine, originalState);
            actor.setCompanionFloorAttackInput(false, false);
        }
        require(localFloor.equals(invoke(localPlayer, "isManualFloorAtkButtonDown"))
                        && localMelee.equals(invoke(localPlayer, "isMeleeButtonDown"))
                        && !otherActor.isManualFloorAtkButtonDown() && !otherActor.isMeleeButtonDown(),
                "one companion's floor intent changed player or other-companion input");
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

    private static void testCompanionBallisticInput(SCNativeCompanion actor, IsoPlayer primary) throws Exception {
        Class<?> access = Class.forName(SCNativeCompanion.class.getName() + "$BallisticAccess");
        for (String name : new String[] { "GET_CONTROLLER", "GET_RETICLE", "GET_ID", "SET_VECTOR",
                "X", "Y", "Z", "IS_PRONE", "AIM_HEIGHT", "UPDATE_RETICLE", "MAX_RANGE", "RANGE_MOD" }) {
            var cached = access.getDeclaredField(name);
            cached.setAccessible(true);
            require(java.lang.reflect.Modifier.isStatic(cached.getModifiers())
                            && java.lang.reflect.Modifier.isFinal(cached.getModifiers()) && cached.get(null) != null,
                    "supported game is missing cached native ballistic metadata: " + name);
        }
        var missingType = SCNativeCompanion.class.getDeclaredMethod("resolveBallisticClass", String.class);
        var missingMethod = SCNativeCompanion.class.getDeclaredMethod("resolveBallisticMethod",
                Class.class, String.class, Class[].class);
        var missingField = SCNativeCompanion.class.getDeclaredMethod("resolveBallisticField", Class.class, String.class);
        missingType.setAccessible(true);
        missingMethod.setAccessible(true);
        missingField.setAccessible(true);
        require(missingType.invoke(null, "survivorcompanion.nonexistent.Ballistics") == null
                        && missingMethod.invoke(null, null, "absent", new Class<?>[0]) == null
                        && missingField.invoke(null, null, "absent") == null,
                "optional ballistic lookup failure escaped its existing fallback");
        Class<?> characterClass = Class.forName("zombie.characters.IsoGameCharacter");
        Class<?> controllerClass = Class.forName("zombie.core.physics.BallisticsController");
        Class<?> vectorClass = Class.forName("zombie.iso.Vector3");
        var controllerField = characterClass.getDeclaredField("ballisticsController");
        var squareField = Class.forName("zombie.iso.IsoObject").getDeclaredField("square");
        var aimField = SCNativeCompanion.class.getDeclaredField("bridgeAimTarget");
        controllerField.setAccessible(true);
        squareField.setAccessible(true);
        aimField.setAccessible(true);
        Object oldController = controllerField.get(actor), oldAim = aimField.get(actor);
        Object oldSquare = squareField.get(primary);
        Object square = oldSquare != null ? oldSquare : actor.getCurrentSquare();
        require(square != null, "ballistic input fixture needs a loaded square");
        @SuppressWarnings("unchecked")
        List<Object> movers = (List<Object>) invoke(square, "getMovingObjects");
        boolean added = !movers.contains(primary) && movers.add(primary);
        Object controller = controllerClass.getMethod("alloc").invoke(null);
        Object reticle = controllerClass.getMethod("getIsoAimingPosition").invoke(controller);
        var set = vectorClass.getMethod("set", float.class, float.class, float.class);
        set.invoke(reticle, -100f, -101f, -102f);
        var select = SCNativeCompanion.class.getDeclaredMethod("selectCompanionBallisticReticle");
        var restore = SCNativeCompanion.class.getDeclaredMethod("restoreCompanionBallisticReticle", Object[].class);
        select.setAccessible(true);
        restore.setAccessible(true);
        IsoPlayer[] slots = IsoPlayer.players.clone();
        int count = IsoPlayer.numPlayers;
        Object targetPoint = vectorClass.getConstructor().newInstance();
        set.invoke(targetPoint, primary.getX(), primary.getY(), primary.getZ());
        Class<?> combatClass = Class.forName("zombie.CombatManager");
        Object combat = combatClass.getMethod("getInstance").invoke(null);
        var physicsHeight = SCNativeCompanion.class.getDeclaredMethod("companionPhysicsAimHeight",
                Class.forName("zombie.iso.IsoMovingObject"));
        physicsHeight.setAccessible(true);
        var onFloor = primary.getClass().getMethod("setOnFloor", boolean.class);
        boolean priorFloor = (Boolean) invoke(primary, "isOnFloor");
        try {
            onFloor.invoke(primary, false);
            float standingHeight = ((Number) physicsHeight.invoke(null, primary)).floatValue();
            require(standingHeight > primary.getZ()
                            && standingHeight == ((Number) invoke(primary, "getAimOriginPosZ")).floatValue(),
                    "standing NPC aim must use the native chest height, not its feet");
            onFloor.invoke(primary, true);
            require((Boolean) invoke(primary, "isProne")
                            && ((Number) physicsHeight.invoke(null, primary)).floatValue() == primary.getZ(),
                    "a prone target must retain low physical aim");
        } finally {
            onFloor.invoke(primary, priorFloor);
        }
        var hittable = combatClass.getDeclaredMethod("isHittableBallisticsTarget",
                controllerClass, float.class, vectorClass);
        hittable.setAccessible(true);
        try {
            squareField.set(primary, square);
            require(primary.isExistInTheWorld(), "ballistic target not in native square");
            controllerField.set(actor, controller);
            aimField.set(actor, primary);
            require(!(Boolean) hittable.invoke(combat, controller, 0.25f, targetPoint),
                    "pre-fix native reticle filter must reject an enemy away from the player's cursor");
            Object[] outer = (Object[]) select.invoke(actor);
            require((Boolean) hittable.invoke(combat, controller, 0.25f, targetPoint),
                    "actor-local aim input did not reach the stock native target filter");
            Object[] nested = (Object[]) select.invoke(actor);
            restore.invoke(null, new Object[] { nested });
            require((Boolean) hittable.invoke(combat, controller, 0.25f, targetPoint),
                    "nested restore lost the outer shot's selected input");
            restore.invoke(null, new Object[] { outer });
            require(vectorClass.getField("x").getFloat(reticle) == -100f
                            && vectorClass.getField("y").getFloat(reticle) == -101f
                            && vectorClass.getField("z").getFloat(reticle) == -102f,
                    "shot scope did not restore the exact previous controller input");
            Object[] retiredInput = (Object[]) select.invoke(actor);
            controllerField.set(actor, null);
            set.invoke(reticle, 777f, 778f, 779f);
            restore.invoke(null, new Object[] { retiredInput });
            require(vectorClass.getField("x").getFloat(reticle) == 777f
                            && vectorClass.getField("y").getFloat(reticle) == 778f
                            && vectorClass.getField("z").getFloat(reticle) == 779f,
                    "a retired shot changed a released/pooled controller's new input");
            controllerField.set(actor, controller);
            aimField.set(actor, null);
            require(select.invoke(actor) == null, "an absent target invented ballistic input");
            aimField.set(actor, primary);
            movers.remove(primary);
            require(select.invoke(actor) == null, "a removed target retained ballistic input");
            if (!added) movers.add(primary);
            require(Arrays.equals(slots, IsoPlayer.players) && IsoPlayer.numPlayers == count
                            && IsoPlayer.getInstance() == primary && !actor.isLocalPlayer(),
                    "NPC ballistic input changed local-player ownership");

            var captureScratch = SCNativeCompanion.class.getDeclaredMethod("captureCompanionBallisticScratch", Class.class);
            var restoreScratch = SCNativeCompanion.class.getDeclaredMethod("restoreCompanionBallisticScratch", Object[].class);
            captureScratch.setAccessible(true);
            restoreScratch.setAccessible(true);
            Object[] originalScratch = (Object[]) captureScratch.invoke(null, combatClass);
            var rangeFilter = combatClass.getDeclaredMethod("lambda$calculateHitListWeapon$0",
                    float.class, Class.forName("zombie.iso.IsoMovingObject"));
            rangeFilter.setAccessible(true);
            try {
                Object start = originalScratch[0];
                set.invoke(start, primary.getX() + 1000f, primary.getY(), primary.getZ());
                require((Boolean) rangeFilter.invoke(null, 12f, primary),
                        "stock range prefilter must reject a nearby enemy when another actor owns the shared ray");
                Object[] outerScratch = (Object[]) captureScratch.invoke(null, combatClass);
                set.invoke(start, primary.getX(), primary.getY(), primary.getZ());
                require(!(Boolean) rangeFilter.invoke(null, 12f, primary),
                        "native range prefilter did not honor the shot's current muzzle origin");
                Object[] nestedScratch = (Object[]) captureScratch.invoke(null, combatClass);
                set.invoke(start, 2000f, 2001f, 2002f);
                restoreScratch.invoke(null, new Object[] { nestedScratch });
                require(!(Boolean) rangeFilter.invoke(null, 12f, primary),
                        "nested shot failed to restore its outer native muzzle origin");
                restoreScratch.invoke(null, new Object[] { outerScratch });
                require((Boolean) rangeFilter.invoke(null, 12f, primary),
                        "scoped shot leaked its origin into another character's targeting context");
            } finally {
                restoreScratch.invoke(null, new Object[] { originalScratch });
            }
        } finally {
            controllerField.set(actor, oldController);
            aimField.set(actor, oldAim);
            squareField.set(primary, oldSquare);
            if (added) movers.remove(primary);
            else if (!movers.contains(primary)) movers.add(primary);
            controllerClass.getMethod("release").invoke(controller);
        }
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
        boolean coopPvpBefore = (Boolean) playerClass.getMethod("getCoopPVP").invoke(null);
        playerClass.getMethod("setCoopPVP", boolean.class).invoke(null, false);
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
        require("VoiceMale".equals(descriptorClass.getMethod("getVoicePrefix")
                        .invoke(firstDescriptor))
                        && "VoiceFemale".equals(descriptorClass.getMethod("getVoicePrefix")
                                .invoke(secondDescriptor)),
                "companion construction did not normalize sex-specific player vocals");

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
        require("player".equals(invoke(actor, "getCompanionActionGroupName"))
                        && !String.valueOf(invoke(actor,
                                "getCompanionActionStateName")).isBlank(),
                "companion did not expose its player ActionContext safely");
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
        // A clear-line vanilla path normally selects input-owned player movement.
        // The companion has no local input, so its override must retain the native
        // path state instead of walking in place with only animation flags set.
        actor.getClass().getMethod("pathToLocationF", float.class, float.class, float.class)
                .invoke(actor, 2.5f, 0.5f, 0.0f);
        var pathMoveRequested = SCNativeCompanion.class.getDeclaredField("bridgeMoveRequested");
        pathMoveRequested.setAccessible(true);
        require((Boolean) actor.getClass().getMethod("getVariableBoolean", String.class)
                        .invoke(actor, "bPathfind")
                        && !(Boolean) invoke(actor, "isPlayerMoving")
                        && ((SCNativeCompanion) actor).hasPendingMovement()
                        && !pathMoveRequested.getBoolean(actor),
                "a pathfinder-owned search animated forward before movement began");
        invoke(invoke(actor, "getPathFindBehavior2"), "cancel");
        actor.getClass().getMethod("setMoving", boolean.class).invoke(actor, false);
        require(!(Boolean) actor.getClass().getMethod("getVariableBoolean", String.class)
                        .invoke(actor, "bPathfind"),
                "external path stop retained vanilla's bPathfind animation state");
        var pathActive = SCNativeCompanion.class.getDeclaredField("bridgePathActive");
        pathActive.setAccessible(true);
        var pathStarted = SCNativeCompanion.class.getDeclaredField("bridgePathStartedThisRun");
        pathStarted.setAccessible(true);
        pathActive.setBoolean(actor, true);
        require(!(Boolean) invoke(actor, "isPlayerMoving"),
                "pending native path search reported player locomotion");
        pathStarted.setBoolean(actor, true);
        require((Boolean) invoke(actor, "isPlayerMoving"),
                "started native path state recursed through IsoPlayer movement callbacks");
        pathStarted.setBoolean(actor, false);
        pathActive.setBoolean(actor, false);
        // Companions used to walk through closed doors. Build 42 sets
        // LCC_IGNORE_DOORS for every non-animal, non-zombie character in
        // IsoGameCharacter.pathToAux, so the engine plans straight through a
        // closed door expecting the character to open it -- and a companion's
        // contextual actions are deliberately suppressed, so nothing did.
        // A companion's aim never steadied, so every shot was a snap shot with
        // almost no chance of a critical -- guns fired, bullets flew, no
        // headshots. The engine's own step has to run for this actor.
        {
            SCNativeCompanion aimer = (SCNativeCompanion) actor;
            long before = aimer.getCompanionAimingDelayUpdates();
            var step = SCNativeCompanion.class.getDeclaredMethod("updateCompanionAimingDelay");
            step.setAccessible(true);
            step.invoke(aimer);
            require(aimer.getCompanionAimingDelayUpdates() == before + 1,
                    "the engine's aim-steadying step did not run for a companion");
            // That it is CALLED from the update is asserted at the source by
            // test_core_static.py: driving a whole update here needs a world
            // this harness does not have.
        }

        // A companion swung and fired in silence: SwipeStatePlayer's swing-sound
        // handler, and the "Always" variant it delegates to, both return unless
        // the character is the local player. The bridge drives it instead, so
        // the event has to actually reach that code.
        {
            SCNativeCompanion sounded = (SCNativeCompanion) actor;
            long before = sounded.getCompanionSwingSoundEvents();
            var unrelated = new zombie.core.skinnedmodel.advancedanimation.AnimEvent();
            unrelated.eventName = "SomeOtherEvent";
            sounded.OnAnimEvent(null, null, unrelated);
            require(sounded.getCompanionSwingSoundEvents() == before,
                    "an unrelated animation event was treated as a swing sound");
            var swing = new zombie.core.skinnedmodel.advancedanimation.AnimEvent();
            swing.eventName = "PlaySwingSound";
            swing.parameterValue = "";
            sounded.OnAnimEvent(null, null, swing);
            require(sounded.getCompanionSwingSoundEvents() == before + 1,
                    "a PlaySwingSound event never reached the companion's own sound path");
        }

        // One step later: the flesh noise belongs to the victim's damage code
        // and plays for anyone, so a companion's shovel landed with a squish
        // and no shovel. A swing that hits nothing must stay silent.
        {
            SCNativeCompanion hitter = (SCNativeCompanion) actor;
            long before = hitter.getCompanionHitSoundEvents();
            hitter.driveCompanionHitSoundForTests(new Object(), 0);
            require(hitter.getCompanionHitSoundEvents() == before,
                    "a swing that connected with nothing still reached the hit-sound path");
            hitter.driveCompanionHitSoundForTests(null, 3);
            require(hitter.getCompanionHitSoundEvents() == before,
                    "a landed swing with no weapon still reached the hit-sound path");
            hitter.driveCompanionHitSoundForTests(new Object(), 2);
            require(hitter.getCompanionHitSoundEvents() == before + 1,
                    "a landed melee swing never reached the companion's own hit-sound path");
            // The value above is not a HandWeapon, so resolving its sound
            // throws. Reaching the require below at all proves the throw did
            // not escape into the swing, and nothing was played for it.
            require(hitter.getCompanionHitSounds() == 0,
                    "a value with no impact sound still played one");
            require(!hitter.getCompanionHitSoundFailure().isEmpty(),
                    "a reflective failure on the hit-sound path was not contained");
        }

        // Foliage parity. A direct step carries a fixed distance from Lua, so
        // without this factor a companion crossed a hedge at full walking speed
        // while the player has to push through it.
        require(SCNativeCompanion.foliageSpeedFactor(false, false, 1.0f,
                        SCNativeCompanion.FOLIAGE_SLOW_FACTOR) == 1.0f,
                "open ground was slowed as if it were foliage");
        require(SCNativeCompanion.foliageSpeedFactor(true, false, 1.0f,
                        SCNativeCompanion.FOLIAGE_SLOW_FACTOR)
                        == SCNativeCompanion.FOLIAGE_SLOW_FACTOR,
                "a hedge square did not slow a direct companion step");
        require(SCNativeCompanion.foliageSpeedFactor(true, true, 0.8f,
                        SCNativeCompanion.FOLIAGE_SLOW_FACTOR) == 0.8f,
                "a sapling ignored the engine's own IsoTree slow factor");
        require(SCNativeCompanion.foliageSpeedFactor(true, true, 1.5f,
                        SCNativeCompanion.FOLIAGE_SLOW_FACTOR) == 1.0f,
                "a profession bonus let foliage make a companion faster than open ground");
        require(SCNativeCompanion.foliageSpeedFactor(true, true, 0.0f,
                        SCNativeCompanion.FOLIAGE_SLOW_FACTOR)
                        == SCNativeCompanion.FOLIAGE_SLOW_FACTOR,
                "an unusable tree factor was taken literally instead of falling back");
        require(SCNativeCompanion.foliageSpeedFactor(true, false, 1.0f, Float.NaN) == 1.0f
                        && SCNativeCompanion.foliageSpeedFactor(true, false, 1.0f, 0.0f) == 1.0f,
                "a broken foliage factor could stop a companion dead in a hedge");
        require(((SCNativeCompanion) actor).getCompanionTerrainSpeedFactor() == 1.0f,
                "a companion on no known square was slowed for foliage it cannot be in");
        // The factor has to shorten the step, not merely be available.
        require(SCNativeCompanion.boundedMovementDistance(
                        0.045f * SCNativeCompanion.FOLIAGE_SLOW_FACTOR, 1.0f, 4.0f, 0.06f)
                        < SCNativeCompanion.boundedMovementDistance(0.045f, 1.0f, 4.0f, 0.06f),
                "a foliage-scaled walk step was no shorter than an open-ground step");

        SCNativeCompanion infectedCompanion = (SCNativeCompanion) actor;
        require(infectedCompanion.setCompanionInfectionGait(0.55f)
                        && Math.abs(infectedCompanion.getFootInjurySpeedModifier()) >= 0.55f,
                "late Knox did not select the native player's heavy-limp walk blend");
        infectedCompanion.updateMovementRates();
        require(Math.abs(((Number) variableFloat.invoke(actor,
                        "WalkInjury", 0.0f)).floatValue()) >= 0.55f,
                "late Knox did not reach the player's real WalkInjury animation scalar");
        require(SCNativeCompanion.lateKnoxDirectStepFactor(0.55f) < 1.0f
                        && SCNativeCompanion.lateKnoxDirectStepFactor(0.0f) == 1.0f,
                "direct bridge steps did not follow the late Knox walk pace");
        require(!infectedCompanion.setCompanionInfectionGait(Float.NaN)
                        && !infectedCompanion.setCompanionInfectionGait(1.0f)
                        && infectedCompanion.setCompanionInfectionGait(0.0f),
                "invalid gait values were accepted or a healed gait could not clear");

        require(SCNativeCompanion.doorIsSoleObstruction(false, true),
                "a step clear of everything but a door was not held");
        require(!SCNativeCompanion.doorIsSoleObstruction(true, true),
                "a wall was misreported as a door and would stall the actor");
        require(!SCNativeCompanion.doorIsSoleObstruction(false, false),
                "an open doorway was treated as blocked");
        require(!SCNativeCompanion.doorIsSoleObstruction(true, false),
                "an impossible probe result was treated as a door");
        require(!((SCNativeCompanion) actor).isCompanionPathBlockedByDoor(),
                "an actor with no active native path claimed a door block");
        // The guard has to be part of the step decision, not merely available.
        require(SCNativeCompanion.shouldAdvanceBridgePath(false, false, true, false, false),
                "an ordinary path step was refused");
        require(!SCNativeCompanion.shouldAdvanceBridgePath(false, false, true, false, true),
                "a native path step crossed a closed door");
        require(!SCNativeCompanion.shouldAdvanceBridgePath(false, false, false, false, false),
                "a path step advanced with no active path");
        require(!SCNativeCompanion.shouldAdvanceBridgePath(false, false, true, true, false),
                "a path step competed with an exclusive native owner");
        require(!SCNativeCompanion.shouldAdvanceBridgePath(true, false, true, false, false)
                        && !SCNativeCompanion.shouldAdvanceBridgePath(
                                false, true, true, false, false),
                "a disabled bridge or a seated companion still advanced its path");
        require(!SCNativeCompanion.shouldApplyCompanionAim(true, false, false),
                "ordinary forward locomotion can be reversed by a stale combat aim target");
        require(SCNativeCompanion.shouldApplyCompanionAim(true, true, false),
                "tactical strafe lost its target-facing ownership");
        require(SCNativeCompanion.shouldApplyCompanionAim(true, false, true),
                "an active attack lost the target angle required by its hit arc");
        require(SCNativeCompanion.shouldApplyCompanionAim(false, false, false),
                "a stationary companion no longer tracks its combat target");
        require(SCNativeCompanion.isCompanionBallisticTargetInRange(3f, 4f, 0f, 5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(3f, 4.01f, 0f, 5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, 0f, 3.31f, 5f),
                "ballistic model preparation escaped the weapon's actual range or native floor limit");
        require(!SCNativeCompanion.isCompanionBallisticTargetInRange(Float.NaN, 0f, 0f, 5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, Float.POSITIVE_INFINITY, 0f, 5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, 0f, Float.NaN, 5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, 0f, 0f, Float.POSITIVE_INFINITY)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, 0f, 0f, -5f)
                        && !SCNativeCompanion.isCompanionBallisticTargetInRange(0f, 0f, 0f, 0f),
                "invalid native coordinates or weapon range admitted model preparation");
        require(SCNativeCompanion.shouldBridgeMovementOwnFacing(true, false, false),
                "ordinary manual movement did not own its forward direction");
        require(!SCNativeCompanion.shouldBridgeMovementOwnFacing(true, true, false),
                "manual movement stole facing from tactical strafe");
        require(!SCNativeCompanion.shouldBridgeMovementOwnFacing(true, false, true),
                "manual movement stole facing from an active attack");
        require(SCNativeCompanion.corpseDragFacingSign(false) == 1.0f
                        && SCNativeCompanion.corpseDragFacingSign(true) == -1.0f,
                "corpse dragging must face against travel on both direct and native paths");
        testRetainedMovementAndPathState((SCNativeCompanion) actor);
        testCompanionBallisticInput((SCNativeCompanion) actor, (IsoPlayer) localPlayer);
        testNativeTraversalOwnership((SCNativeCompanion) actor);
        testNativeReactionOwnership((SCNativeCompanion) actor,
                (zombie.iso.IsoMovingObject) secondActor);
        testZeroDeferredDuplicatePathNode((SCNativeCompanion) actor);
        testDeferredAccumulatorConsumption((SCNativeCompanion) actor);
        testFloorAttackInputLease((SCNativeCompanion) actor, localPlayer, (SCNativeCompanion) secondActor);
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
        var attackMarker = ((SCNativeCompanion) actor).getModData();
        attackMarker.rawset("SC_PlayerAttackProtected", Boolean.TRUE);
        require(!SCBridge.isProtectRecruitedCompanions()
                        && !((SCNativeCompanion) actor).blocksPlayerWeaponHit((IsoPlayer) localPlayer),
                "player attack protection must default off");
        SCBridge.setProtectRecruitedCompanions(true);
        require(((SCNativeCompanion) actor).blocksPlayerWeaponHit((IsoPlayer) localPlayer)
                        && !((SCNativeCompanion) actor).blocksPlayerWeaponHit((SCNativeCompanion) secondActor),
                "protected ally blocks only the local player's weapon hit");
        HandWeapon testWeapon = new HandWeapon("Base", "Test", "Test", "Base.Test");
        Class<?> scriptItemClass = Class.forName("zombie.scripting.objects.Item");
        Object scriptItem = scriptItemClass.getConstructor().newInstance();
        scriptItemClass.getMethod("setWeaponCategories", java.util.Set.class)
                .invoke(scriptItem, java.util.Collections.emptySet());
        testWeapon.getClass().getMethod("setWeaponCategories", java.util.Set.class)
                .invoke(testWeapon, java.util.Collections.emptySet());
        testWeapon.getClass().getMethod("setScriptItem", scriptItemClass).invoke(testWeapon,
                scriptItem);
        float protectedHealth = ((SCNativeCompanion) actor).getHealth();
        float protectedBodyHealth = ((SCNativeCompanion) actor).getBodyDamage()
                .getOverallBodyHealth();
        Object protectedAttacker = invoke(actor, "getAttackedBy");
        require(((SCNativeCompanion) actor).Hit(testWeapon, (IsoPlayer) localPlayer,
                        0.1f, false, 1.0f, false) == 0.0f
                        && ((SCNativeCompanion) actor).getHealth() == protectedHealth
                        && ((SCNativeCompanion) actor).getBodyDamage()
                                .getOverallBodyHealth() == protectedBodyHealth
                        && invoke(actor, "getAttackedBy") == protectedAttacker,
                "player weapon hit damaged a protected recruit");
        // CombatManager bloodies its target and may knock off a helmet before
        // Hit runs; the local swing's own hit list must veto both for an ally.
        zombie.util.list.PZArrayList<zombie.network.fields.hit.HitInfo> swingTargets =
                ((IsoPlayer) localPlayer).getHitInfoList();
        swingTargets.clear();
        require(!((SCNativeCompanion) actor).protectedFromLocalSwing(),
                "a protected ally outside the local swing must keep ordinary blood and helmet hits");
        swingTargets.add(new zombie.network.fields.hit.HitInfo().init(
                (SCNativeCompanion) actor, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f));
        require(((SCNativeCompanion) actor).protectedFromLocalSwing()
                        && !((SCNativeCompanion) actor).helmetFall(true),
                "the local swing must not bloody or unhelm a protected recruit");
        attackMarker.rawset("SC_PlayerAttackProtected", Boolean.FALSE);
        require(!((SCNativeCompanion) actor).protectedFromLocalSwing(),
                "an unprotected survivor in the local swing keeps blood and helmet hits");
        swingTargets.clear();
        require(!((SCNativeCompanion) actor).blocksPlayerWeaponHit((IsoPlayer) localPlayer),
                "hostile, exiled, or unrecruited marker must remain hittable");
        float unprotectedDamage = ((SCNativeCompanion) actor).Hit(testWeapon,
                (IsoPlayer) localPlayer, 0.1f, false, 1.0f, false);
        // The headless control leaves the global damage multiplier at zero;
        // a positive vanilla hit result and attacker assignment prove that the
        // protected-target veto did not consume an unprotected survivor's hit.
        require(unprotectedDamage > 0.0f
                        && invoke(actor, "getAttackedBy") == localPlayer,
                "player weapon hit was consumed for an unprotected survivor");
        SCBridge.setProtectRecruitedCompanions(false);
        attackMarker.rawset("SC_PlayerAttackProtected", Boolean.TRUE);
        require(!((SCNativeCompanion) actor).blocksPlayerWeaponHit((IsoPlayer) localPlayer),
                "turning the option off must restore player weapon hits immediately");
        attackMarker.rawset("SC_PlayerAttackProtected", Boolean.FALSE);
        testLivingViewHandoff((IsoPlayer) localPlayer,
                (SCNativeCompanion) actor, (SCNativeCompanion) secondActor);
        testPrimaryViewReleaseRefresh((IsoPlayer) localPlayer,
                (SCNativeCompanion) secondActor, (IsoCell) cell);
        testDeferredPrimaryViewRestore((IsoPlayer) localPlayer,
                (SCNativeCompanion) secondActor, (IsoCell) cell);
        testStockObserverCustomTeardown((IsoPlayer) localPlayer,
                (SCNativeCompanion) secondActor, (IsoCell) cell);
        testReadOnlyGroundWallSample((IsoPlayer) localPlayer, (IsoCell) cell);
        require((Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "owned NPCs did not enable the vanilla IsoPlayer hit gate");
        Class<?> movingObjectClass = Class.forName("zombie.iso.IsoMovingObject");
        boolean playerMayHitCompanion = (Boolean) Class.forName("zombie.CombatManager")
                .getMethod("checkPVP", movingObjectClass, movingObjectClass, boolean.class)
                .invoke(null, localPlayer, actor, true);
        require(playerMayHitCompanion,
                "CombatManager still rejected player weapon hits against an owned companion");
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
        require((Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "retiring one NPC disabled player damage while another remained owned");
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
        require(!(Boolean) playerClass.getMethod("getCoopPVP").invoke(null),
                "last NPC teardown did not restore the previous vanilla hit-gate state");
        playerClass.getMethod("setCoopPVP", boolean.class).invoke(null, coopPvpBefore);
        System.out.println("ISO_COMPANION_CONTROL_PASS actors=2 index=3 components=true voice-position=true local-state=unchanged"
                + " movement=true animation-scalars=true rollback=true transient-ownership=true ownership=true pvp-hit-gate=true permadeath=true teardown=true"
                + " cleanup-retry=true view-release-refresh=true view-release-deferred=true stock-custom-teardown=true ground-wall-sample=true post-demotion-postupdate-complete=true update="
                + (updateReachedRenderBoundary ? "contained-render-boundary" : "complete"));
    }
}
