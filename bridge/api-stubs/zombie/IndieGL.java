// SPDX-License-Identifier: MIT
package zombie;

/** Compile-only render queue API, verified against the installed 42.21 JAR. */
public final class IndieGL {
    public static int testPushes, testPops;
    private IndieGL() {}
    public static void StartShader(int shaderId) {}
    public static void EndShader() {}
    public static void pushShader(zombie.core.opengl.Shader shader, zombie.core.opengl.ShaderUniformSetter values) { testPushes++; }
    public static void popShader(zombie.core.opengl.Shader shader) { testPops++; }
}
