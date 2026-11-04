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

        if (args.length == 2 && args[0].equals("--groups")) {
            String name = null;
            List<String> files = new ArrayList<>();
            int groups = 0;
            for (String line : Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8)) {
                if (line.isBlank()) continue;
                if (line.startsWith("--group ")) {
                    if (name != null) {
                        runGroup(name, files);
                        groups++;
                    }
                    name = line.substring(8).trim();
                    files = new ArrayList<>();
                } else {
                    if (name == null) throw new IllegalArgumentException("A file precedes its group");
                    files.add(line);
                }
            }
            if (name == null) throw new IllegalArgumentException("No Lua groups were supplied");
            runGroup(name, files);
            System.out.println("Kahlua groups PASS count=" + (groups + 1));
        } else {
            runGroup("files", List.of(args));
        }
    }

    private static void runGroup(String name, List<String> files) throws Exception {
        if (name.isBlank() || files.isEmpty()) {
            throw new IllegalArgumentException("A Lua group requires a name and files");
        }
        // Production modules and their fixture share a world within a scenario;
        // the next group gets a new environment and thread, even in this JVM.
        Class<?> platformType = Class.forName("se.krka.kahlua.j2se.J2SEPlatform", true, LOADER);
        Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform", true, LOADER);
        Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable", true, LOADER);
        Class<?> compilerType = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler", true, LOADER);
        Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread", true, LOADER);

        Object platform = platformType.getMethod("getInstance").invoke(null);
        Object environment = platformType.getMethod("newEnvironment").invoke(platform);
        // Real Java values as game code leaves them in Lua tables: a boxed
        // Float (not a Lua number) and an arbitrary object, both userdata.
        var rawset = tableType.getMethod("rawset", Object.class, Object.class);
        rawset.invoke(environment, "SC_TEST_BOXED_FLOAT", Float.valueOf(0.75f));
        rawset.invoke(environment, "SC_TEST_JAVA_OBJECT", new Object());
        Object thread = threadType.getConstructor(platformInterface, tableType).newInstance(platform, environment);
        var ownerField = threadType.getDeclaredField("debugOwnerThread");
        ownerField.setAccessible(true);
        ownerField.set(thread, Thread.currentThread());
        var load = compilerType.getMethod("loadis", Reader.class, String.class, tableType);
        var pcall = threadType.getMethod("pcall", Object.class, Object[].class);

        List<String> completed = new ArrayList<>();
        for (String argument : files) {
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
                throw new AssertionError("[" + name + "] " + file + ": " + detail);
            }
            completed.add(file.getFileName().toString());
        }
        Object report = tableType.getMethod("rawget", Object.class)
            .invoke(environment, "SC_TEST_REPORT");
        if (report != null) {
            System.out.println(String.valueOf(report));
        }
        System.out.println("Kahlua PASS [" + name + "]: "
            + (name.equals("files") ? String.join(", ", completed) : completed.size() + " files"));
    }
}
