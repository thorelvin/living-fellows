// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.function.Predicate;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.network.fields.hit.HitInfo;

/** Limits protection to an owned companion's committed firearm collision. */
final class SCCompanionFirearmProtection {
    private static final StackWalker WALKER = StackWalker.getInstance();

    private SCCompanionFirearmProtection() {}

    private static final class LuaAccess {
        static Field environment, caller, thread;
        static Method pcall;

        static {
            try {
                Class<?> manager = Class.forName("zombie.Lua.LuaManager");
                environment = manager.getField("env");
                caller = manager.getField("caller");
                thread = manager.getField("thread");
                pcall = caller.getType().getMethod("pcall", thread.getType(), Object.class, Object[].class);
            } catch (ReflectiveOperationException | LinkageError unavailable) {
                pcall = null;
            }
        }
    }

    static final class Shot {
        final String decision;
        final Predicate<IsoGameCharacter> protects;
        int removed;

        Shot(String decision, Predicate<IsoGameCharacter> protects) {
            this.decision = decision;
            this.protects = protects;
        }

        boolean allowed() {
            return "allow".equals(decision) || "protect".equals(decision) && protects != null;
        }

        void filter(ArrayList<HitInfo> hits) {
            if (hits == null || protects == null) return;
            for (int index = hits.size() - 1; index >= 0; index--) {
                HitInfo hit = hits.get(index);
                if (hit == null || !(hit.getObject() instanceof IsoGameCharacter target)
                        || !protects.test(target)) continue;
                hits.remove(index);
                SCStayWithMeProtection.recycle(hit);
                removed++;
            }
        }
    }

    static Shot begin(IsoGameCharacter shooter, IsoGameCharacter aimTarget) {
        if (LuaAccess.pcall != null) {
            try {
                if (LuaAccess.environment.get(null) instanceof KahluaTable env
                        && env.rawget("SurvivorCompanion") instanceof KahluaTable sc
                        && sc.rawget("Combat") instanceof KahluaTable combat) {
                    Object caller = LuaAccess.caller.get(null);
                    Object thread = LuaAccess.thread.get(null);
                    Object check = combat.rawget("firearmCommitPolicy");
                    Object filter = combat.rawget("firearmCandidateProtected");
                    Object result = call(caller, thread, check, shooter, aimTarget);
                    if (result instanceof String decision) {
                        if (!"protect".equals(decision)) return new Shot(decision, null);
                        if (filter != null) {
                            return new Shot(decision,
                                    target -> !Boolean.FALSE.equals(call(caller, thread, filter, shooter, target)));
                        }
                    }
                }
            } catch (ReflectiveOperationException | RuntimeException | LinkageError unavailable) {
                // Missing policy cannot authorize a weapon discharge.
            }
        }
        return new Shot("firearm_policy_unavailable", null);
    }

    private static Object call(Object caller, Object thread, Object function, Object... arguments) {
        if (function == null) return null;
        try {
            Object[] result = (Object[]) LuaAccess.pcall.invoke(caller, thread, function, arguments);
            return result != null && result.length >= 2 && Boolean.TRUE.equals(result[0]) ? result[1] : null;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError unavailable) {
            return null;
        }
    }

    // The stock getter is also used while building and drawing the ballistic
    // list. Only the direct read in attackCollisionCheck feeds its wound loop.
    static boolean readsResolvedHits() {
        return WALKER.walk(frames -> frames.skip(2).findFirst()
                .map(frame -> "zombie.CombatManager".equals(frame.getClassName())
                        && "attackCollisionCheck".equals(frame.getMethodName())).orElse(false));
    }
}
