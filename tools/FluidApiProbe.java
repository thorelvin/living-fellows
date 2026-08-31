// SPDX-License-Identifier: MIT

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Comparator;

public final class FluidApiProbe {
    public static void main(String[] args) throws Exception {
        for (String name : new String[] {
                "zombie.entity.components.fluids.FluidInstance",
                "zombie.entity.components.fluids.FluidSample",
                "zombie.entity.components.fluids.FluidContainer"
        }) {
            Class<?> type = Class.forName(name);
            System.out.println("### " + name);
            Field[] fields = type.getFields();
            Arrays.sort(fields, Comparator.comparing(Field::getName));
            for (Field field : fields) {
                System.out.println("FIELD " + Modifier.toString(field.getModifiers()) + " "
                        + field.getType().getTypeName() + " " + field.getName());
            }
            Method[] methods = type.getMethods();
            Arrays.sort(methods, Comparator.comparing(Method::getName)
                    .thenComparing(Method::toGenericString));
            for (Method method : methods) {
                if (method.getDeclaringClass() == Object.class) continue;
                System.out.println("METHOD " + method.toGenericString());
            }
        }
    }
}
