// SPDX-License-Identifier: MIT

import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Runs clean-room Lua sources with the Kahlua compiler bundled by the game. */
public final class KahluaTestRunner {
    private static final ClassLoader LOADER = KahluaTestRunner.class.getClassLoader();

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            throw new IllegalArgumentException("Pass Lua files in execution order");
        }

        Class<?> platformType = Class.forName("se.krka.kahlua.j2se.J2SEPlatform", true, LOADER);
        Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform", true, LOADER);
        Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable", true, LOADER);
        Class<?> compilerType = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler", true, LOADER);
        Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread", true, LOADER);

        Object platform = platformType.getMethod("getInstance").invoke(null);
        Object environment = platformType.getMethod("newEnvironment").invoke(platform);
        Object thread = threadType.getConstructor(platformInterface, tableType).newInstance(platform, environment);
        var ownerField = threadType.getDeclaredField("debugOwnerThread");
        ownerField.setAccessible(true);
        ownerField.set(thread, Thread.currentThread());
        var load = compilerType.getMethod("loadis", Reader.class, String.class, tableType);
        var pcall = threadType.getMethod("pcall", Object.class, Object[].class);

        List<String> completed = new ArrayList<>();
        for (String argument : args) {
            Path file = Path.of(argument).toAbsolutePath().normalize();
            Object closure;
            try (Reader reader = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
                closure = load.invoke(null, reader, file.toString(), environment);
            }
            Object[] result = (Object[]) pcall.invoke(thread, closure, new Object[0]);
            if (result.length == 0 || !Boolean.TRUE.equals(result[0])) {
                String detail = result.length > 1 ? String.valueOf(result[1]) : "unknown Kahlua failure";
                if (result.length > 2) {
                    StringBuilder diagnostic = new StringBuilder(detail);
                    for (int index = 2; index < result.length; index++) {
                        diagnostic.append(System.lineSeparator()).append(String.valueOf(result[index]));
                    }
                    detail = diagnostic.toString();
                }
                throw new AssertionError(file + ": " + detail);
            }
            completed.add(file.getFileName().toString());
        }
        System.out.println("Kahlua PASS: " + String.join(", ", completed));
    }
}
