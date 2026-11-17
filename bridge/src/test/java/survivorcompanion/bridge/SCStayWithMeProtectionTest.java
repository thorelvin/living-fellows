// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.ArrayList;
import java.util.HashMap;
import se.krka.kahlua.vm.KahluaTable;
import zombie.CombatManager;
import zombie.Lua.LuaManager;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoMovingObject;
import zombie.network.fields.hit.HitInfo;

/** Executes the shipped LF actor's virtual getter, with native-shaped boundaries. */
public final class SCStayWithMeProtectionTest {
    private static int checks;
    private static void check(boolean value, String reason) {
        checks++;
        if (!value) throw new AssertionError(reason);
    }
    private static final class Table implements KahluaTable {
        final HashMap<Object, Object> data = new HashMap<>();
        public Object rawget(Object key) { return data.get(key); }
        public void rawset(Object key, Object value) { data.put(key, value); }
        public void rawset(int key, Object value) { data.put(key, value); }
        public void wipe() { data.clear(); }
    }
    private static final class Body extends IsoZombie {
        final Table data = new Table();
        boolean marker, puppet;
        float health = 100;
        @Override public boolean getVariableBoolean(String key) {
            return ("NotAloneBody".equals(key) && marker)
                    || ("SWMSeatPuppet".equals(key) && puppet);
        }
        @Override public boolean hasModData() { return !data.data.isEmpty(); }
        @Override public KahluaTable getModData() { return data; }
    }
    private static final class Contact extends HitInfo {
        final IsoMovingObject target;
        Contact(IsoMovingObject target) { this.target = target; }
        @Override public IsoMovingObject getObject() { return target; }
    }
    private static SCNativeCompanion companion() throws Exception {
        var field = Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe");
        field.setAccessible(true);
        Object unsafe = field.get(null);
        return (SCNativeCompanion)unsafe.getClass().getMethod("allocateInstance", Class.class)
                .invoke(unsafe, SCNativeCompanion.class);
    }
    private static void applyNativeWounds(ArrayList<HitInfo> hits) {
        for (HitInfo hit : hits) {
            if (hit != null && hit.getObject() instanceof Body body) body.health = 0;
        }
    }
    public static void main(String[] args) throws Exception {
        SCNativeCompanion actor = companion();
        Body rin = new Body(), otherOwner = new Body(), visual = new Body(), zombie = new Body();
        rin.marker = true;
        otherOwner.data.rawset("notAloneBody", true);
        visual.puppet = true;
        ArrayList<HitInfo> raw = actor.getHitInfoList();
        Contact enemy = new Contact(zombie), first = new Contact(rin), second = new Contact(otherOwner);
        raw.add(first);raw.add(enemy);raw.add(second);raw.add(new Contact(visual));raw.add(new Contact(rin));
        ArrayList<HitInfo> permitted = actor.getHitInfoList();
        check(permitted == raw && permitted.size() == 1 && permitted.get(0) == enemy,
                "SWM native hits removed from mixed bystanders and repeated pellet contacts, preserving the real enemy");
        applyNativeWounds(permitted);
        check(rin.health == 100 && otherOwner.health == 100 && visual.health == 100 && zombie.health == 0,
                "only the ordinary zombie receives simulated collision damage");
        check(CombatManager.getInstance().hitInfoPool.released.size() == 4,
                "every discarded native hit returns to its pool exactly once");
        raw.clear();raw.add(first);
        rin.marker = false;
        check(actor.getHitInfoList().size() == 1, "a released unmarked body is not permanently immune");
        raw.clear();raw.add(first);
        rin.marker = true;
        check(actor.getHitInfoList().isEmpty(), "late identity promotion is rechecked at impact");
        IsoPlayer player = new IsoPlayer(null, null, 0, 0, 0, false);
        player.getHitInfoList().add(first);
        check(player.getHitInfoList().size() == 1, "the local player and other mods' attackers retain their own hit lists");
        rin.marker = false;
        Table env = new Table(), sc = new Table(), adapter = new Table();
        env.rawset("SurvivorCompanion", sc);sc.rawset("StayWithMeAdapter", adapter);
        adapter.rawset("owns", new Object());LuaManager.env = env;
        LuaManager.caller.owned.add(rin);
        raw.clear();raw.add(enemy);raw.add(first);
        check(actor.getHitInfoList().size() == 1 && raw.get(0) == enemy,
                "unmarked API-owned client/server mirrors are protected by the live Lua adapter");
        LuaManager.caller.owned.clear();
        raw.add(first);
        check(actor.getHitInfoList().size() == 2, "Lua ownership removal takes effect without a retained callback result");
        LuaManager.caller.fail = true;
        check(actor.getHitInfoList().isEmpty(), "a failing live identity callback cannot authorize native damage");
        LuaManager.env = null;LuaManager.caller.fail = false;
        raw.add(enemy);
        check(actor.getHitInfoList().size() == 1, "unloaded Lua world keeps ordinary native hits working");
        check(SCStayWithMeProtection.filter(null) == null && !SCStayWithMeProtection.protects(null),
                "empty engine boundaries remain harmless");
        System.out.println("STAY_WITH_ME_NATIVE_PASS checks=" + checks);
    }
}
