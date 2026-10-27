// SPDX-License-Identifier: MIT
package zombie.core.opengl;
/** Compile-only 42.21 public queued uniform API. */
public final class ShaderUniformSetter {
    public ShaderUniformSetter setNext(ShaderUniformSetter next) { return next; }
    public static ShaderUniformSetter uniform1f(Shader shader, String name, float value) {
        return new ShaderUniformSetter();
    }
}
