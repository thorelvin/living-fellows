// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.network.fields.hit.HitInfo;

/** Filters only LF's own native hit lists, including incidental multi-hits. */
final class SCStayWithMeProtection {
    private SCStayWithMeProtection() {}

    private static final class LuaAccess {
        static Field environment, caller, thread;
        static Method pcall;
        static {
            try {
                Class<?> manager = Class.forName("zombie.Lua.LuaManager");
                environment = manager.getField("env");
                caller = manager.getField("caller");
                thread = manager.getField("thread");
                pcall = caller.getType().getMethod("pcall", thread.getType(), Object.class, Object.class);
            } catch (ReflectiveOperationException | LinkageError unavailable) {
                pcall = null;
            }
        }
    }

    private static final class PoolAccess {
        static Method instance, release;
        static Field pool;
        static {
            try {
                Class<?> manager = Class.forName("zombie.CombatManager");
                instance = manager.getMethod("getInstance");
                pool = manager.getField("hitInfoPool");
                release = pool.getType().getMethod("release", Object.class);
            } catch (ReflectiveOperationException | LinkageError unavailable) {
                release = null;
            }
        }
    }

    static boolean protects(IsoGameCharacter target) {
        if (target == null) return false;
        // These are SWM's published live body and seated-visual markers. Do not
        // infer ownership from a name, outfit, sex, SurvivorNPC or generic brain.
        try {
            if (target.getVariableBoolean("NotAloneBody")
                    || target.getVariableBoolean("SWMSeatPuppet")) return true;
            if (target.hasModData()) {
                KahluaTable data = target.getModData();
                if (data != null && Boolean.TRUE.equals(data.rawget("notAloneBody"))) return true;
            }
        } catch (RuntimeException | LinkageError unreadable) {
            // An initializing mirror can still be identified by SWM's APIs.
        }
        if (LuaAccess.pcall == null) return false;
        try {
            Object value = LuaAccess.environment.get(null);
            if (!(value instanceof KahluaTable env)) return false;
            Object scValue = env.rawget("LivingFellows");
            if (!(scValue instanceof KahluaTable sc)) return false;
            Object adapterValue = sc.rawget("StayWithMeAdapter");
            if (!(adapterValue instanceof KahluaTable adapter)) return false;
            Object owns = adapter.rawget("owns");
            if (owns == null) return false;
            Object[] result = (Object[]) LuaAccess.pcall.invoke(
                    LuaAccess.caller.get(null), LuaAccess.thread.get(null), owns, target);
            // A failing identity callback cannot authorize an incidental wound.
            return result == null || result.length < 2 || !Boolean.TRUE.equals(result[0])
                    || Boolean.TRUE.equals(result[1]);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError unreadable) {
            return true;
        }
    }

    static ArrayList<HitInfo> filter(ArrayList<HitInfo> hits) {
        if (hits == null) return null;
        for (int index = hits.size() - 1; index >= 0; index--) {
            HitInfo hit = hits.get(index);
            if (hit == null || !(hit.getObject() instanceof IsoGameCharacter target)
                    || !protects(target)) continue;
            hits.remove(index);
            recycle(hit);
        }
        return hits;
    }

    static void recycle(HitInfo hit) {
        if (PoolAccess.release == null) return;
        try {
            PoolAccess.release.invoke(PoolAccess.pool.get(PoolAccess.instance.invoke(null)), hit);
        } catch (ReflectiveOperationException | RuntimeException | LinkageError unavailable) {
            // Removing the hit is authoritative; if the pool is unavailable the
            // discarded entry is collected normally, never restored as damage.
        }
    }
}
