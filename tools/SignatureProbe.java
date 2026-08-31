// SPDX-License-Identifier: MIT
package tools;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Member;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Comparator;

/** Prints public/protected declarations without inspecting implementation bodies. */
public final class SignatureProbe {
    private SignatureProbe() {}

    private static boolean visible(Member member) {
        int modifiers = member.getModifiers();
        return Modifier.isPublic(modifiers) || Modifier.isProtected(modifiers);
    }

    private static String typeName(Class<?> type) {
        return type.getTypeName();
    }

    private static String parameters(Class<?>[] types) {
        return String.join(", ", Arrays.stream(types).map(SignatureProbe::typeName).toList());
    }

    private static void printClass(String className) throws ReflectiveOperationException {
        Class<?> type = Class.forName(className, false, SignatureProbe.class.getClassLoader());
        System.out.println("===== " + Modifier.toString(type.getModifiers()) + " " + type.getName() + " extends "
                + (type.getSuperclass() == null ? "<none>" : type.getSuperclass().getTypeName()) + " =====");

        Arrays.stream(type.getDeclaredFields())
                .filter(SignatureProbe::visible)
                .sorted(Comparator.comparing(Field::getName))
                .forEach(field -> System.out.println("FIELD " + Modifier.toString(field.getModifiers()) + " "
                        + typeName(field.getType()) + " " + field.getName()));

        Arrays.stream(type.getDeclaredConstructors())
                .filter(SignatureProbe::visible)
                .sorted(Comparator.comparing(Constructor::toString))
                .forEach(constructor -> System.out.println("CTOR " + Modifier.toString(constructor.getModifiers())
                        + " (" + parameters(constructor.getParameterTypes()) + ")"));

        Arrays.stream(type.getDeclaredMethods())
                .filter(SignatureProbe::visible)
                .sorted(Comparator.comparing(Method::getName).thenComparing(Method::toString))
                .forEach(method -> System.out.println("METHOD " + Modifier.toString(method.getModifiers()) + " "
                        + typeName(method.getReturnType()) + " " + method.getName() + "("
                        + parameters(method.getParameterTypes()) + ")"));
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        for (String className : args) {
            printClass(className);
        }
    }
}
