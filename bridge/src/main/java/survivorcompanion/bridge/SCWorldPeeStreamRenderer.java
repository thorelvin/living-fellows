// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.IndieGL;
import zombie.core.SpriteRenderer;
import zombie.core.textures.TextureDraw;
import zombie.iso.IsoCamera;
import zombie.iso.IsoDepthHelper;
import zombie.iso.IsoUtils;
import zombie.iso.PlayerCamera;
import zombie.iso.fboRenderChunk.FBORenderCell;

/** Queues a short-lived stream in the same depth-tested world pass as its actor. */
final class SCWorldPeeStreamRenderer {
    private static final int SEGMENTS = 10;
    private static final int GL_DEPTH_TEST = 2929;
    private static final int GL_LESS = 513;
    private static final int GL_BLEND = 3042;
    private static final int GL_SRC_ALPHA = 770;
    private static final int GL_ONE_MINUS_SRC_ALPHA = 771;
    private static final float[] RED = { 0.82f, 0.96f };
    private static final float[] GREEN = { 0.73f, 0.91f };
    private static final float[] BLUE = { 0.42f, 0.68f };
    private static final float[] ALPHA = { 0.12f, 0.32f };
    private static final float[] HALF_WIDTH = { 1.0f, 0.5f };

    record Stream(float sourceX, float sourceY, float sourceZ,
            float targetX, float targetY, long expiresAtNanos) {}

    private SCWorldPeeStreamRenderer() {}

    static boolean valid(SCNativeCompanion actor, double sourceX, double sourceY,
            double sourceZ, double targetX, double targetY) {
        if (!Double.isFinite(sourceX) || !Double.isFinite(sourceY)
                || !Double.isFinite(sourceZ) || !Double.isFinite(targetX)
                || !Double.isFinite(targetY)) return false;
        float x = actor.getX(), y = actor.getY(), z = actor.getZ();
        return Math.abs(sourceX - x) < 1.0 && Math.abs(sourceY - y) < 1.0
                && sourceZ > z + 0.08 && sourceZ < z + 1.1
                && Math.abs(targetX - x) < 3.0 && Math.abs(targetY - y) < 3.0;
    }

    static int queue(SCNativeCompanion actor, Stream stream) {
        if (stream == null || System.nanoTime() > stream.expiresAtNanos()
                || actor.getCurrentSquare() == null || !actor.hasActiveModel()) return -1;
        IsoCamera.FrameState frame = IsoCamera.frameState;
        if (frame == null) return -1;
        int playerIndex = frame.playerIndex;
        if (playerIndex < 0 || playerIndex >= IsoCamera.cameras.length) return -1;
        PlayerCamera camera = IsoCamera.cameras[playerIndex];
        if (camera == null || actor.getTargetAlpha(playerIndex) <= 0.05f) return -1;

        // Match IsoSprite.renderTextureWithDepth's camera adjustment, screen
        // projection and isometric depth. Each small quad has its own depth.
        float fixX = camera.fixJigglyModelsSquareX;
        float fixY = camera.fixJigglyModelsSquareY;
        float[] wx = new float[SEGMENTS + 1];
        float[] wy = new float[SEGMENTS + 1];
        float[] wz = new float[SEGMENTS + 1];
        float[] sx = new float[SEGMENTS + 1];
        float[] sy = new float[SEGMENTS + 1];
        float groundZ = actor.getZ();
        for (int step = 0; step <= SEGMENTS; step++) {
            float progress = (float) step / SEGMENTS;
            wx[step] = stream.sourceX() +
                    (stream.targetX() - stream.sourceX()) * progress + fixX;
            wy[step] = stream.sourceY() +
                    (stream.targetY() - stream.sourceY()) * progress + fixY;
            wz[step] = Math.max(groundZ + 0.02f,
                    stream.sourceZ() + 0.04f * progress
                    - (stream.sourceZ() - groundZ + 0.02f) * progress * progress);
            sx[step] = IsoUtils.XToScreen(wx[step], wy[step], wz[step], 0)
                    - camera.getOffX();
            sy[step] = IsoUtils.YToScreen(wx[step], wy[step], wz[step], 0)
                    - camera.getOffY();
            if (!Float.isFinite(sx[step]) || !Float.isFinite(sy[step])) return -1;
        }

        float[] nx = new float[SEGMENTS];
        float[] ny = new float[SEGMENTS];
        for (int segment = 0; segment < SEGMENTS; segment++) {
            float dx = sx[segment + 1] - sx[segment];
            float dy = sy[segment + 1] - sy[segment];
            float length = (float) Math.hypot(dx, dy);
            if (length < 0.001f) return -1;
            nx[segment] = -dy / length;
            ny[segment] = dx / length;
        }
        float[] joinX = new float[SEGMENTS + 1];
        float[] joinY = new float[SEGMENTS + 1];
        for (int point = 0; point <= SEGMENTS; point++) {
            if (point == 0 || point == SEGMENTS) {
                int adjacent = Math.min(point, SEGMENTS - 1);
                joinX[point] = nx[adjacent];
                joinY[point] = ny[adjacent];
            } else {
                float x = nx[point - 1] + nx[point];
                float y = ny[point - 1] + ny[point];
                float length = (float) Math.hypot(x, y);
                if (length < 0.01f) {
                    joinX[point] = nx[point];
                    joinY[point] = ny[point];
                } else {
                    float scale = Math.min(1.5f, 1.0f /
                            Math.max(0.25f, (x * nx[point] + y * ny[point]) / length));
                    joinX[point] = x / length * scale;
                    joinY[point] = y / length * scale;
                }
            }
        }

        SpriteRenderer renderer = SpriteRenderer.instance;
        IndieGL.StartShader(0);
        renderer.glEnable(GL_DEPTH_TEST);
        renderer.glDepthFunc(GL_LESS);
        // The preceding model pass may leave GL_BLEND disabled. The default
        // transparent sprite style sets blend factors but does not enable it.
        renderer.glEnable(GL_BLEND);
        renderer.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        // Both translucent layers share a segment depth. Leave the model's
        // depth buffer intact so the second layer can still pass the test.
        renderer.glDepthMask(false);
        try {
            double flowPhase = System.nanoTime() * 0.000000006;
            for (int segment = 0; segment < SEGMENTS; segment++) {
                // A low-amplitude travelling highlight suggests moving fluid
                // without exposing an opaque line against dark ground.
                float flowAlpha = 0.93f + 0.07f
                        * (float) Math.sin(flowPhase - segment * 0.8);
                float midX = (wx[segment] + wx[segment + 1]) * 0.5f;
                float midY = (wy[segment] + wy[segment + 1]) * 0.5f;
                float midZ = (wz[segment] + wz[segment + 1]) * 0.5f;
                float depth = IsoDepthHelper.calculateDepth(midX, midY, midZ);
                float chunkDepth = 0.0f;
                FBORenderCell fbo = FBORenderCell.instance;
                if (fbo != null && fbo.renderTranslucentOnly) {
                    IsoDepthHelper.Results chunk = IsoDepthHelper.getChunkDepthData(
                            (int) Math.floor(frame.camCharacterX / 8.0f),
                            (int) Math.floor(frame.camCharacterY / 8.0f),
                            (int) Math.floor(midX / 8.0f),
                            (int) Math.floor(midY / 8.0f),
                            (int) Math.floor(midZ));
                    chunkDepth = (chunk.depthStart + 0.5f) * 2.0f - 1.0f;
                }
                for (int layer = 0; layer < 2; layer++) {
                    float width = HALF_WIDTH[layer];
                    TextureDraw.nextZ = depth * 2.0f - 1.0f;
                    TextureDraw.nextChunkDepth = chunkDepth;
                    renderer.renderPoly(
                            sx[segment] + joinX[segment] * width,
                            sy[segment] + joinY[segment] * width,
                            sx[segment + 1] + joinX[segment + 1] * width,
                            sy[segment + 1] + joinY[segment + 1] * width,
                            sx[segment + 1] - joinX[segment + 1] * width,
                            sy[segment + 1] - joinY[segment + 1] * width,
                            sx[segment] - joinX[segment] * width,
                            sy[segment] - joinY[segment] * width,
                            RED[layer], GREEN[layer], BLUE[layer],
                            ALPHA[layer] * flowAlpha);
                }
            }
        } finally {
            // The model renderer leaves depth testing off after a character.
            // Restore that state before the next queued world/UI operation.
            renderer.glDepthMask(true);
            renderer.glDisable(GL_DEPTH_TEST);
            IndieGL.EndShader();
            TextureDraw.nextZ = 0.0f;
            TextureDraw.nextChunkDepth = 0.0f;
        }
        return playerIndex;
    }
}
