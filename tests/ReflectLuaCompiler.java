// SPDX-License-Identifier: MIT

import java.io.Reader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public final class ReflectLuaCompiler {
    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("--reflect")) {
            Class<?> type = Class.forName(args[1]);
            for (Constructor<?> constructor : type.getConstructors()) {
                System.out.println(constructor.toGenericString());
            }
            for (Method method : type.getDeclaredMethods()) {
                if (Modifier.isPublic(method.getModifiers())) {
                    System.out.println(method.toGenericString());
                }
            }
            return;
        }
        Class<?> compiler = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        Method loadReader = null;
        for (Method method : compiler.getDeclaredMethods()) {
            if (method.getName().equals("loadis")
                    && method.getParameterCount() == 3
                    && method.getParameterTypes()[0] == Reader.class) {
                loadReader = method;
                break;
            }
        }
        if (loadReader == null) {
            throw new IllegalStateException("LuaCompiler.loadis(Reader, ...) was not found");
        }
        boolean run = args.length > 0 && args[0].equals("--run");
        int firstSource = run ? 1 : 0;
        Object environment = null;
        Object thread = null;
        Method protectedCall = null;
        if (run) {
            Class<?> platformType = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
            Object platform = platformType.getMethod("getInstance").invoke(null);
            environment = platformType.getMethod("newEnvironment").invoke(platform);
            Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform");
            Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable");
            Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread");
            thread = threadType.getConstructor(platformInterface, tableType).newInstance(platform, environment);
            Field debugOwner = threadType.getDeclaredField("debugOwnerThread");
            debugOwner.setAccessible(true);
            debugOwner.set(thread, Thread.currentThread());
            protectedCall = threadType.getMethod("pcall", Object.class, Object[].class);
        }
        boolean failed = false;
        for (int index = firstSource; index < args.length; index++) {
            String value = args[index];
            Path source = Path.of(value);
            try (Reader reader = Files.newBufferedReader(source, StandardCharsets.UTF_8)) {
                Object closure = loadReader.invoke(null, reader, source.toString(), environment);
                if (run) {
                    Object[] result = (Object[]) protectedCall.invoke(thread, new Object[] { closure, new Object[0] });
                    if (result.length == 0 || !Boolean.TRUE.equals(result[0])) {
                        StringBuilder detail = new StringBuilder();
                        for (int resultIndex = 1; resultIndex < result.length; resultIndex++) {
                            if (resultIndex > 1) detail.append(" | ");
                            detail.append(String.valueOf(result[resultIndex]));
                        }
                        if (detail.length() == 0) detail.append("unknown Lua error");
                        throw new IllegalStateException(detail.toString());
                    }
                    System.out.println("OK RUN " + source);
                } else {
                    System.out.println("OK " + source);
                }
            } catch (InvocationTargetException exception) {
                failed = true;
                Throwable cause = exception.getCause();
                System.err.println("FAIL " + source + ": " + cause);
            }
        }
        if (failed) {
            System.exit(1);
        }
    }
}
