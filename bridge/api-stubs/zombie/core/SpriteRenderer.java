// SPDX-License-Identifier: MIT
package zombie.core;

/** Compile-only render queue API, verified against the installed 42.21 JAR. */
public final class SpriteRenderer {
    public static final SpriteRenderer instance = new SpriteRenderer();
    public void glEnable(int flag) {}
    public void glDisable(int flag) {}
    public void glDepthFunc(int mode) {}
    public void glDepthMask(boolean enabled) {}
    public void glBlendFunc(int source, int destination) {}
    public void renderPoly(float x0, float y0, float x1, float y1,
            float x2, float y2, float x3, float y3,
            float red, float green, float blue, float alpha) {}
}
