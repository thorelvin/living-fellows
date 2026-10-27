// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.IndieGL;
import zombie.core.opengl.Shader;
import zombie.core.opengl.ShaderUniformSetter;
import zombie.core.textures.Texture;
import zombie.ui.UIElement;

/** A queued UI-only shader. Original game textures and world rendering stay untouched. */
final class SCTerminalLogoRenderer {
    private static Shader shader;
    private static Thread owner;
    private static boolean active;
    private SCTerminalLogoRenderer() {}

    static boolean draw(UIElement host, Texture texture, double x, double y, double width, double height,
            double alpha, double red, double green, double blue,
            double keyRed, double keyGreen, double keyBlue, boolean keyed, boolean mono, boolean darkInk) {
        if (host == null || texture == null || !Double.isFinite(x) || !Double.isFinite(y)
                || !Double.isFinite(width) || !Double.isFinite(height) || width <= 0 || height <= 0
                || width > 32768 || height > 32768 || !unit(alpha)) return false;
        if (!begin(red, green, blue, keyRed, keyGreen, keyBlue, keyed, mono, darkInk)) return false;
        try {
            host.DrawTextureScaledColor(texture, x, y, width, height, 1.0, 1.0, 1.0, alpha);
            return true;
        } finally { end(); }
    }

    private static boolean begin(double red, double green, double blue,
            double keyRed, double keyGreen, double keyBlue, boolean keyed, boolean mono, boolean darkInk) {
        if (!unit(red) || !unit(green) || !unit(blue)
                || !unit(keyRed) || !unit(keyGreen) || !unit(keyBlue)) return false;
        if (active || owner != null && owner != Thread.currentThread()) return false;
        try {
            if (shader == null) {
                owner = Thread.currentThread();
                shader = new Shader("LF_TerminalLogo");
            }
            if (!shader.isCompiled()) return false;
            ShaderUniformSetter values = ShaderUniformSetter.uniform1f(shader, "PaletteR", (float) red);
            ShaderUniformSetter tail = values;
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "PaletteG", (float) green));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "PaletteB", (float) blue));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "KeyR", (float) keyRed));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "KeyG", (float) keyGreen));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "KeyB", (float) keyBlue));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "Keyed", keyed ? 1f : 0f));
            tail = tail.setNext(ShaderUniformSetter.uniform1f(shader, "Monochrome", mono ? 1f : 0f));
            tail.setNext(ShaderUniformSetter.uniform1f(shader, "DarkInk", darkInk ? 1f : 0f));
            IndieGL.pushShader(shader, values);
            active = true;
            return true;
        } catch (RuntimeException | LinkageError unavailable) {
            return false;
        }
    }

    private static void end() {
        if (!active || owner != Thread.currentThread()) return;
        try { IndieGL.popShader(shader); }
        finally { active = false; }
    }

    private static boolean unit(double value) {
        return Double.isFinite(value) && value >= 0 && value <= 1;
    }
}
