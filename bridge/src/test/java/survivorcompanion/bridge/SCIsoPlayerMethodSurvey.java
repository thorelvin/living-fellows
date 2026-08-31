// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Locale;

/** Research-only public API survey for the version-pinned private actor experiment. */
public final class SCIsoPlayerMethodSurvey {
    private SCIsoPlayerMethodSurvey() {}

    private static boolean relevant(String name) {
        String lower = name.toLowerCase(Locale.ROOT);
        return lower.contains("playernum") || lower.contains("playerindex")
                || lower.contains("localplayer") || lower.contains("npc")
                || lower.contains("addtoworld") || lower.contains("removefromworld")
                || lower.contains("aim") || lower.contains("moving")
                || lower.equals("update");
    }

    public static void main(String[] args) throws Exception {
        Class<?> player = Class.forName("zombie.characters.IsoPlayer");
        Arrays.stream(player.getConstructors())
                .sorted((left, right) -> left.toString().compareTo(right.toString()))
                .forEach(constructor -> System.out.println("CONSTRUCTOR " + constructor));
        Arrays.stream(player.getMethods())
                .filter(method -> relevant(method.getName()))
                .sorted((left, right) -> left.toString().compareTo(right.toString()))
                .forEach(method -> System.out.println("METHOD " + Modifier.toString(method.getModifiers())
                        + " " + method.getReturnType().getTypeName() + " " + method.getName()
                        + Arrays.toString(Arrays.stream(method.getParameterTypes())
                                .map(Class::getTypeName).toArray(String[]::new))));
        Field[] publicFields = player.getFields();
        for (int fieldIndex = 0; fieldIndex < publicFields.length; fieldIndex++) {
            Field field = publicFields[fieldIndex];
            if (relevant(field.getName())) {
                System.out.println("FIELD index=" + fieldIndex + " " + Modifier.toString(field.getModifiers()) + " "
                        + field.getType().getTypeName() + " " + field.getName());
            }
        }
        Method getter = player.getMethod("getPlayerNum");
        System.out.println("PLAYER_NUM_ACCESSOR getter=" + getter.getReturnType().getTypeName()
                + " writablePublicField=" + !Modifier.isFinal(player.getField("playerIndex").getModifiers()));
        Class<?> globals = Class.forName("zombie.Lua.LuaManager$GlobalObject");
        Arrays.stream(globals.getMethods())
                .filter(method -> {
                    String lower = method.getName().toLowerCase(Locale.ROOT);
                    return lower.contains("classfield") || lower.contains("fieldval");
                })
                .sorted((left, right) -> left.toString().compareTo(right.toString()))
                .forEach(method -> System.out.println("LUA_GLOBAL " + method));
        Class<?> survivor = Class.forName("zombie.characters.IsoSurvivor");
        Arrays.stream(survivor.getConstructors())
                .sorted((left, right) -> left.toString().compareTo(right.toString()))
                .forEach(constructor -> System.out.println("SURVIVOR_CONSTRUCTOR " + constructor));
        for (String required : new String[] {
                "update", "addToWorld", "removeFromWorld", "removeFromSquare", "getBodyDamage",
                "getMoodles", "getXp", "getEmitter", "getVisual", "getCurrentSquare", "isDead",
                "getPathFindBehavior2", "canStandAt", "setForwardDirection", "setRunning",
                "setSprinting", "setSneaking", "setMoving", "MoveForward", "isMoving",
                "getCharacterActions", "faceLocationF", "isTurning", "setPrimaryHandItem",
                "getPrimaryHandItem", "setAimAtFloor", "setAuthorizeShoveStomp", "setAttackType",
                "DoAttack", "openWindow", "smashWindow", "climbThroughWindow", "isClimbing",
                "setKnockedDown", "isKnockedDown", "setSitOnFurnitureObject",
                "setSittingOnFurniture", "isSittingOnFurniture" }) {
            Method[] matches = Arrays.stream(survivor.getMethods())
                    .filter(method -> method.getName().equals(required))
                    .toArray(Method[]::new);
            System.out.println("SURVIVOR_METHOD " + required + "="
                    + (matches.length == 0 ? "missing" : Arrays.toString(matches)));
        }
        Class<?> gameCharacter = Class.forName("zombie.characters.IsoGameCharacter");
        for (Field field : gameCharacter.getDeclaredFields()) {
            String lower = field.getName().toLowerCase(Locale.ROOT);
            if (lower.contains("body") || lower.contains("moodle") || lower.contains("emitter")
                    || lower.equals("xp")) {
                System.out.println("CHARACTER_FIELD " + field);
            }
        }
        for (Method method : gameCharacter.getMethods()) {
            String lower = method.getName().toLowerCase(Locale.ROOT);
            if (lower.startsWith("set") && (lower.contains("body") || lower.contains("moodle")
                    || lower.contains("emitter") || lower.equals("setxp"))) {
                System.out.println("CHARACTER_SETTER " + method);
            }
        }
        for (Class<?> type : new Class<?>[] { survivor, gameCharacter,
                Class.forName("zombie.characters.IsoLivingCharacter") }) {
            for (Method method : type.getDeclaredMethods()) {
                String lower = method.getName().toLowerCase(Locale.ROOT);
                if (lower.contains("init") || lower.contains("bodydamage")
                        || lower.contains("moodle") || lower.contains("emitter")
                        || lower.contains("descriptor")) {
                    System.out.println("DECLARED_METHOD " + type.getName() + " " + method);
                }
            }
        }
        for (String className : new String[] {
                "zombie.characters.BodyDamage.BodyDamage",
                "zombie.characters.Moodles.Moodles",
                "zombie.characters.CharacterSoundEmitter",
                "zombie.characters.IsoGameCharacter$XP" }) {
            Class<?> component = Class.forName(className);
            Arrays.stream(component.getConstructors())
                    .forEach(constructor -> System.out.println("COMPONENT_CONSTRUCTOR " + constructor));
        }
    }
}
