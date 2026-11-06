// SPDX-License-Identifier: MIT
package me.zed_0xff.zombie_buddy;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Compile-only subset of ZombieBuddy 2.3.3's annotation API. Never packaged. */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface Patch {
    String className();
    String methodName();
    boolean isAdvice() default true;
    boolean warmUp() default false;
    boolean IKnowWhatIAmDoing() default false;
    boolean strictMatch() default false;

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.METHOD)
    @interface OnEnter { boolean skipOn() default false; }

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.PARAMETER)
    @interface Argument { int value() default 0; boolean readOnly() default true; }
}
