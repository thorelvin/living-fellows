// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Method;
import java.util.Arrays;

/** Developer probe for the game-bundled Java runtime; not shipped in the mod. */
public final class SCBodyDamageApiProbe {
    private SCBodyDamageApiProbe() {}

    public static void main(String[] arguments) throws Exception {
        Class<?> type = Class.forName("zombie.characters.BodyDamage.BodyDamage", false,
                SCBodyDamageApiProbe.class.getClassLoader());
        Arrays.stream(type.getMethods())
                .map(Method::toString)
                .filter(value -> value.toLowerCase().contains("health")
                        || value.toLowerCase().contains("damage"))
                .sorted()
                .forEach(System.out::println);
    }
}
