// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Locale;

/** Research-only survey of the version-pinned Build 42 character render surface. */
public final class SCRenderApiSurvey {
    private SCRenderApiSurvey() {}

    private static boolean relevant(String name) {
        String value = name.toLowerCase(Locale.ROOT);
        return value.contains("render") || value.contains("model") || value.contains("visual")
                || value.contains("sprite") || value.contains("outfit") || value.contains("worn")
                || value.contains("dress") || value.contains("animation") || value.contains("animplayer")
                || value.equals("add") || value.equals("remove") || value.equals("say")
                || value.contains("speak") || value.contains("chat");
    }

    private static void survey(String className) throws Exception {
        Class<?> type = Class.forName(className);
        System.out.println("CLASS " + type.getName());
        Arrays.stream(type.getDeclaredFields())
                .filter(field -> relevant(field.getName()) || relevant(field.getType().getName()))
                .sorted(Comparator.comparing(Field::toString))
                .forEach(field -> System.out.println("FIELD " + Modifier.toString(field.getModifiers())
                        + " " + field.getType().getTypeName() + " " + field.getName()));
        Arrays.stream(type.getDeclaredMethods())
                .filter(method -> relevant(method.getName()) || relevant(method.getReturnType().getName()))
                .sorted(Comparator.comparing(Method::toString))
                .forEach(method -> System.out.println("METHOD " + method));
    }

    public static void main(String[] args) throws Exception {
        for (String className : new String[] {
                "zombie.characters.IsoGameCharacter",
                "zombie.characters.IsoPlayer",
                "zombie.characters.IsoLivingCharacter",
                "zombie.core.skinnedmodel.ModelManager",
                "zombie.core.skinnedmodel.animation.AnimationPlayer",
                "zombie.iso.sprite.IsoSprite"
        }) {
            survey(className);
        }
    }
}
