// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.characters.IsoSurvivor;
import zombie.characters.SurvivorDesc;
import zombie.characters.SurvivorFactory;
import zombie.core.Core;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** Version-pinned, deliberately narrow access to world-spawned IsoSurvivors. */
public final class SCBridge {
    public static final String PROTOCOL = "42.20.4-sc.1";
    public static final String REQUIRED_GAME_VERSION = "42.20.4";

    private static final float MAX_MOVE_DISTANCE = 0.25f;
    private static final int MAX_NAME_LENGTH = 48;
    private static final int MAX_OUTFIT_LENGTH = 96;

    private SCBridge() {}

    public static String getProtocol() {
        return PROTOCOL;
    }

    public static String getRequiredGameVersion() {
        return REQUIRED_GAME_VERSION;
    }

    public static String getDetectedGameVersion() {
        try {
            String version = Core.getInstance().getVersionNumber();
            return version == null ? "unavailable" : version.trim();
        } catch (Throwable ignored) {
            return "unavailable";
        }
    }

    public static boolean isMultiplayer() {
        return GameClient.client || GameServer.server;
    }

    public static String checkReady() {
        String compatibility = checkCompatibility(getDetectedGameVersion(), isMultiplayer());
        if (!compatibility.isEmpty()) {
            return compatibility;
        }
        if (!SCBridgeAgent.isTransformed()) {
            return SCBridgeAgent.getStatus();
        }
        if (!SCExposure.isReady()) {
            return SCExposure.getStatus();
        }
        return "";
    }

    public static String checkCompatibility(String detectedVersion, boolean multiplayer) {
        String detected = detectedVersion == null ? "unavailable" : detectedVersion.trim();
        if (!REQUIRED_GAME_VERSION.equals(detected)) {
            return "requires Project Zomboid " + REQUIRED_GAME_VERSION + "; detected " + detected;
        }
        if (multiplayer) {
            return "Living Fellows: Companion is single-player only";
        }
        return "";
    }

    public static boolean isIsoSurvivor(Object value) {
        return value instanceof IsoSurvivor;
    }

    public static IsoSurvivor spawn(
            IsoGridSquare square,
            String forename,
            String surname,
            boolean female,
            String outfit) {
        String readiness = checkReady();
        if (!readiness.isEmpty()) {
            throw new IllegalStateException(readiness);
        }
        validateSpawnSquare(square);

        IsoSurvivor actor = null;
        try {
            SurvivorDesc descriptor = SurvivorFactory.CreateSurvivor();
            if (descriptor == null) {
                throw new IllegalStateException("the game did not create a survivor descriptor");
            }
            descriptor.setFemale(female);
            descriptor.setForename(cleanText(forename, MAX_NAME_LENGTH, "Fellow"));
            descriptor.setSurname(cleanText(surname, MAX_NAME_LENGTH, "Survivor"));
            String cleanOutfit = cleanText(outfit, MAX_OUTFIT_LENGTH, "");
            if (!cleanOutfit.isEmpty()) {
                descriptor.dressInNamedOutfit(cleanOutfit);
            }

            IsoCell cell = square.getCell();
            actor = new SCNativeSurvivor(
                    descriptor,
                    cell,
                    square.getX(),
                    square.getY(),
                    square.getZ());
            actor.setX(square.getX() + 0.5f);
            actor.setY(square.getY() + 0.5f);
            actor.setZ(square.getZ());
            actor.setCurrentSquare(square);
            descriptor.setInstance(actor);

            if (!cell.getSurvivorList().contains(actor)) {
                cell.getSurvivorList().add(actor);
            }
            if (actor.getWorldObjectIndex() < 0) {
                actor.addToWorld();
            }
            if (actor.getCurrentSquare() != square || actor.isDead()
                    || !((SCNativeSurvivor) actor).hasNativeComponents()) {
                throw new IllegalStateException("spawned survivor did not enter the requested square alive");
            }
            return actor;
        } catch (Throwable failure) {
            if (actor != null) {
                removeUnchecked(actor);
            }
            if (failure instanceof RuntimeException runtime) {
                throw runtime;
            }
            throw new IllegalStateException("survivor spawn failed", failure);
        }
    }

    public static boolean remove(IsoSurvivor actor) {
        if (actor == null) {
            return false;
        }
        return removeUnchecked(actor);
    }

    public static boolean move(
            IsoSurvivor actor,
            float directionX,
            float directionY,
            float distance,
            float soundDelta,
            boolean running,
            boolean sneaking) {
        if (!validLivingActor(actor) || !Float.isFinite(directionX) || !Float.isFinite(directionY)
                || !Float.isFinite(distance) || distance <= 0.0f || distance > MAX_MOVE_DISTANCE
                || !Float.isFinite(soundDelta) || soundDelta < 0.0f) {
            return false;
        }

        float lengthSquared = directionX * directionX + directionY * directionY;
        if (lengthSquared < 0.000001f) {
            stop(actor);
            return true;
        }
        float inverseLength = (float) (1.0 / Math.sqrt(lengthSquared));
        float x = directionX * inverseLength;
        float y = directionY * inverseLength;
        if (!canMove(actor, x, y, distance)) {
            stop(actor);
            return false;
        }

        actor.setForwardDirection(x, y);
        actor.setRunning(running);
        actor.setSprinting(false);
        actor.setSneaking(sneaking);
        actor.setMoving(true);
        actor.MoveForward(distance, x, y, soundDelta);
        return true;
    }

    public static void stop(IsoSurvivor actor) {
        if (actor == null) {
            return;
        }
        actor.setMoving(false);
        actor.setRunning(false);
        actor.setSprinting(false);
        actor.setSneaking(false);
    }

    private static boolean canMove(IsoSurvivor actor, float x, float y, float distance) {
        IsoGridSquare current = actor.getCurrentSquare();
        if (current == null) {
            return false;
        }
        float nextX = actor.getX() + x * distance;
        float nextY = actor.getY() + y * distance;
        float nextZ = actor.getZ();
        if (!actor.canStandAt(nextX, nextY, nextZ)) {
            return false;
        }

        IsoGridSquare destination = current.getCell().getGridSquare(
                (int) Math.floor(nextX),
                (int) Math.floor(nextY),
                (int) Math.floor(nextZ));
        if (destination == null || destination.isSolid() || destination.isSolidTrans()
                || !destination.TreatAsSolidFloor()) {
            return false;
        }
        if (destination == current) {
            return true;
        }

        int deltaX = Integer.compare(destination.getX(), current.getX());
        int deltaY = Integer.compare(destination.getY(), current.getY());
        int deltaZ = Integer.compare(destination.getZ(), current.getZ());
        return !current.testCollideAdjacent(actor, deltaX, deltaY, deltaZ)
                && !current.isBlockedTo(destination);
    }

    private static boolean validLivingActor(IsoSurvivor actor) {
        return actor != null && !actor.isDead() && actor.getCurrentSquare() != null;
    }

    private static void validateSpawnSquare(IsoGridSquare square) {
        if (square == null || square.getCell() == null || square.getChunk() == null) {
            throw new IllegalArgumentException("spawn square is not currently loaded");
        }
        if (square.isSolid() || square.isSolidTrans() || !square.TreatAsSolidFloor()
                || !square.isFree(true) || !square.isSafeToSpawn()) {
            throw new IllegalArgumentException("spawn square is unsafe or obstructed");
        }
    }

    private static boolean removeUnchecked(IsoSurvivor actor) {
        boolean success = true;
        IsoCell cell = actor.getCell();
        try {
            stop(actor);
        } catch (Throwable ignored) {
            success = false;
        }
        try {
            actor.removeFromWorld();
        } catch (Throwable ignored) {
            success = false;
        }
        try {
            actor.removeFromSquare();
        } catch (Throwable ignored) {
            success = false;
        }
        try {
            if (cell != null) {
                cell.getSurvivorList().remove(actor);
            }
        } catch (Throwable ignored) {
            success = false;
        }
        return success;
    }

    private static String cleanText(String value, int maximumLength, String fallback) {
        String clean = value == null ? "" : value.trim();
        clean = clean.replaceAll("[\\p{Cntrl}]", "");
        if (clean.length() > maximumLength) {
            clean = clean.substring(0, maximumLength);
        }
        if (clean.isEmpty()) {
            clean = fallback;
        }
        return clean;
    }
}
