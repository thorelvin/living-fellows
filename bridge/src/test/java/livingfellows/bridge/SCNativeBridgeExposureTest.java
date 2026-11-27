// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.lang.reflect.Method;
import java.lang.reflect.Field;
import java.lang.reflect.Array;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import se.krka.kahlua.vm.KahluaTable;

/** Verifies the production bootstrap against the real Project Zomboid Kahlua runtime. */
public final class SCNativeBridgeExposureTest {
    private SCNativeBridgeExposureTest() {}

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    /** Exercise actual pinned-runtime body parts, including attachments with no active injury. */
    private static void testBodyFacts() throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        Object unsafe = singleton.get(null);
        Method allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        zombie.characters.IsoPlayer actor = (zombie.characters.IsoPlayer) allocate.invoke(
                unsafe, zombie.characters.IsoPlayer.class);
        Class<?> damageClass = Class.forName("zombie.characters.BodyDamage.BodyDamage");
        Object damage = allocate.invoke(unsafe, damageClass);
        Field actorDamage = zombie.characters.IsoGameCharacter.class.getDeclaredField("bodyDamage");
        actorDamage.setAccessible(true);
        actorDamage.set(actor, damage);
        Field stats = damageClass.getDeclaredField("stats");
        stats.setAccessible(true);
        stats.set(damage, Class.forName("zombie.characters.Stats").getConstructor().newInstance());
        Field partsField = damageClass.getDeclaredField("bodyParts");
        partsField.setAccessible(true);
        ArrayList<Object> parts = new ArrayList<>();
        partsField.set(damage, parts);
        Class<?> partClass = Class.forName("zombie.characters.BodyDamage.BodyPart");
        Class<?> typeClass = Class.forName("zombie.characters.BodyDamage.BodyPartType");
        Object foot = typeClass.getField("Foot_R").get(null);
        Map<Object, Object> values = new LinkedHashMap<>();
        KahluaTable table = (KahluaTable) Proxy.newProxyInstance(KahluaTable.class.getClassLoader(),
                new Class<?>[]{KahluaTable.class}, (proxy, method, arguments) -> {
                    if (method.getName().equals("rawset")) { values.put(arguments[0], arguments[1]); return null; }
                    if (method.getName().equals("wipe")) { values.clear(); return null; }
                    if (method.getName().equals("toString")) return "body-facts-table";
                    if (method.getName().equals("hashCode")) return System.identityHashCode(proxy);
                    if (method.getName().equals("equals")) return proxy == arguments[0];
                    if (!method.getReturnType().isPrimitive()) return null;
                    if (method.getReturnType() == boolean.class) return false;
                    if (method.getReturnType() == char.class) return '\0';
                    return 0;
                });

        Object part = partClass.getConstructor(typeClass, zombie.characters.IsoGameCharacter.class)
                .newInstance(foot, actor);
        parts.add(part);
        require(SCBridge.fillBodyFacts(actor, table) == 0 && Double.valueOf(0).equals(values.get("count")),
                "healthy body part must not publish a wound tuple");

        partClass.getMethod("setStitched", boolean.class).invoke(part, true);
        partClass.getMethod("setStitchTime", float.class).invoke(part, 45.0f);
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(1).equals(values.get("count")),
                "a stitch-only native part was skipped before tuple publication");
        require(values.get(1) == part && Double.valueOf(0).equals(values.get(2))
                        && Double.valueOf(4096).equals(values.get(3)) && "Foot_R".equals(values.get(4))
                        && !values.containsKey(5),
                "stitch-only fact must preserve the four-field tuple and Lua number types");

        partClass.getMethod("setBandaged", boolean.class, float.class, boolean.class, String.class)
                .invoke(part, true, 10.0f, false, "Base.Bandage");
        require(!(Boolean) partClass.getMethod("stitched").invoke(part),
                "native dressing setup must cover the stitched flag");
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(4104).equals(values.get(3)),
                "covered native stitch timer was omitted from body flags");

        part = partClass.getConstructor(typeClass, zombie.characters.IsoGameCharacter.class)
                .newInstance(foot, actor);
        parts.set(0, part);
        partClass.getMethod("setSplint", boolean.class, float.class).invoke(part, true, 0.0f);
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(1).equals(values.get("count"))
                        && values.get(1) == part && Double.valueOf(8192).equals(values.get(3)),
                "zero-factor spent native splint was skipped or marked as an active fracture");
        partClass.getMethod("setFractureTime", float.class).invoke(part, 10.0f);
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(8704).equals(values.get(3)),
                "an active fracture must coexist with its splint flag");
        partClass.getMethod("setFractureTime", float.class).invoke(part, 0.0f);
        partClass.getMethod("setSplint", boolean.class, float.class).invoke(part, false, 0.0f);
        partClass.getMethod("setSplintFactor", float.class).invoke(part, 1.0f);
        require(!(Boolean) partClass.getMethod("isSplint").invoke(part)
                        && SCBridge.fillBodyFacts(actor, table) == 1
                        && Double.valueOf(8192).equals(values.get(3)),
                "a positive native splint factor must remain a visible attachment without its flag");

        part = partClass.getConstructor(typeClass, zombie.characters.IsoGameCharacter.class)
                .newInstance(foot, actor);
        parts.set(0, part);
        partClass.getMethod("setBandaged", boolean.class, float.class, boolean.class, String.class)
                .invoke(part, true, 10.0f, false, "Base.Bandage");
        partClass.getMethod("setBiteTime", float.class).invoke(part, 5.0f);
        partClass.getMethod("setScratchTime", float.class).invoke(part, 5.0f);
        partClass.getMethod("setCutTime", float.class).invoke(part, 5.0f);
        partClass.getMethod("setDeepWoundTime", float.class).invoke(part, 5.0f);
        require(!(Boolean) partClass.getMethod("bitten").invoke(part)
                        && !(Boolean) partClass.getMethod("scratched").invoke(part)
                        && !(Boolean) partClass.getMethod("isCut").invoke(part)
                        && !(Boolean) partClass.getMethod("deepWounded").invoke(part),
                "native covered-injury setup must have hidden booleans");
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(234).equals(values.get(3)),
                "covered bite, scratch, cut and deep-wound timers must remain visible in body facts");

        part = partClass.getConstructor(typeClass, zombie.characters.IsoGameCharacter.class)
                .newInstance(foot, actor);
        parts.set(0, part);
        partClass.getMethod("setBandaged", boolean.class, float.class, boolean.class, String.class)
                .invoke(part, true, 10.0f, false, "Base.Bandage");
        require(SCBridge.fillBodyFacts(actor, table) == 1 && Double.valueOf(8).equals(values.get(3)),
                "a healed clean dressing must remain available for cosmetic display");

        parts.clear();
        require(SCBridge.fillBodyFacts(actor, table) == 0 && Double.valueOf(0).equals(values.get("count"))
                        && !values.containsKey(1) && !values.containsKey(3),
                "empty native body facts retained a previous attachment tuple");
    }

    private static void testOptionalOptimizerBoundary() throws Exception {
        require(!SCBridge.configurePZOptimizerAdapter(true)
                        && "absent".equals(SCBridge.getPZOptimizerAdapterState()),
                "vanilla runtime must not activate the optimizer adapter");
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        Object unsafe = singleton.get(null);
        Method allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        SCNativeCompanion actor = (SCNativeCompanion) allocate.invoke(unsafe, SCNativeCompanion.class);
        zombie.characters.IsoPlayer player = (zombie.characters.IsoPlayer) allocate.invoke(unsafe,
                zombie.characters.IsoPlayer.class);
        zombie.characters.IsoZombie attacker = (zombie.characters.IsoZombie) allocate.invoke(unsafe,
                zombie.characters.IsoZombie.class);
        Field owners = SCBridge.class.getDeclaredField("OWNED");
        owners.setAccessible(true);
        @SuppressWarnings("unchecked") java.util.Set<SCNativeCompanion> owned =
                (java.util.Set<SCNativeCompanion>) owners.get(null);
        Field enabled = SCPZOptimizerCompatibility.class.getDeclaredField("enabled");
        enabled.setAccessible(true);
        Field target = zombie.characters.IsoZombie.class.getField("target");
        long priorCalls = SCBridge.getPZOptimizerInlineCalls();
        try {
            enabled.setBoolean(null, true);
            target.set(attacker, player);
            require(!SCPZOptimizerCompatibility.beforeSubmit(attacker), "real player attack was intercepted");
            require(!SCPZOptimizerCompatibility.beforeSubmit(actor), "non-zombie evaluator was intercepted");
            target.set(attacker, actor);
            require(!SCPZOptimizerCompatibility.beforeSubmit(attacker), "unowned NPC attack was intercepted");
            owned.add(actor);
            require(SCPZOptimizerCompatibility.beforeSubmit(attacker), "owned LF target was still deferred");
            owned.remove(actor);
            require(!SCPZOptimizerCompatibility.beforeSubmit(attacker), "released actor retained the inline exception");
            owned.add(actor);
            SCBridge.configurePZOptimizerAdapter(false);
            require(!SCPZOptimizerCompatibility.beforeSubmit(attacker)
                            && "disabled".equals(SCBridge.getPZOptimizerAdapterState()),
                    "turning compatibility off must immediately delegate normally");
            require(SCBridge.getPZOptimizerInlineCalls() == priorCalls + 1,
                    "inline metrics included unrelated actors");
        } finally {
            enabled.setBoolean(null, false);
            owned.remove(actor);
            SCBridge.configurePZOptimizerAdapter(true);
        }
    }

    private static void testWindowPermissionIsolation() throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field field = unsafeClass.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        Object unsafe = field.get(null);
        Method allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        zombie.iso.IsoObject window = (zombie.iso.IsoObject) allocate.invoke(unsafe, zombie.iso.IsoObject.class);
        zombie.iso.IsoObject other = (zombie.iso.IsoObject) allocate.invoke(unsafe, zombie.iso.IsoObject.class);
        zombie.iso.IsoGridSquare inside = (zombie.iso.IsoGridSquare) allocate.invoke(unsafe, zombie.iso.IsoGridSquare.class);
        zombie.iso.IsoGridSquare outside = (zombie.iso.IsoGridSquare) allocate.invoke(unsafe, zombie.iso.IsoGridSquare.class);
        SCWindowActionGuard guard = new SCWindowActionGuard(), neighbour = new SCWindowActionGuard();
        require(guard.approve(window, "climb", inside, 1), "window permission rejected");
        require(!neighbour.consume(window, "climb", inside, 2), "permission leaked to another actor");
        require(guard.consume(window, "climb", inside, 2), "exact window permission not accepted");
        require(!guard.consume(window, "climb", inside, 3), "window permission replayed");
        guard.approve(window, "climb", inside, 10);
        require(!guard.consume(other, "climb", inside, 11), "permission accepted a different window");
        require(!guard.consume(window, "climb", inside, 12), "failed match retained permission");
        guard.approve(window, "climb", inside, 20);
        require(!guard.consume(window, "climb", outside, 21), "window permission crossed from the wrong side");
        guard.approve(window, "climb", inside, 30);
        require(!guard.consume(window, "smash", inside, 31), "climb permission allowed smashing");
        guard.approve(window, "smash", inside, 40);
        require(!guard.consume(window, "smash", inside, 500_000_040L), "expired permission survived");
        guard.approve(window, "climb", inside, 50); guard.clear();
        require(!guard.consume(window, "climb", inside, 51), "cancel retained window permission");
        for (Class<?> type : new Class<?>[]{zombie.iso.objects.IsoWindow.class, zombie.iso.objects.IsoThumpable.class}) {
            require(SCNativeCompanion.class.getMethod("climbThroughWindow", type).getDeclaringClass() == SCNativeCompanion.class,
                    "native window overload bypassed approval: " + type);
            require(SCNativeCompanion.class.getMethod("climbThroughWindow", type, Integer.class).getDeclaringClass() == SCNativeCompanion.class,
                    "native window flags overload bypassed approval: " + type);
        }
        require(SCNativeCompanion.class.getMethod("climbThroughWindow", zombie.iso.IsoObject.class).getDeclaringClass() == SCNativeCompanion.class
                && SCNativeCompanion.class.getMethod("climbThroughWindowFrame", zombie.iso.objects.IsoWindowFrame.class).getDeclaringClass() == SCNativeCompanion.class
                && SCNativeCompanion.class.getMethod("smashWindow", zombie.iso.objects.IsoWindow.class).getDeclaringClass() == SCNativeCompanion.class,
                "native generic/frame/smash path bypassed approval");
    }

    private static void testOnBedRenderLiftIsolation() throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        Object unsafe = singleton.get(null);
        Method allocate = unsafeClass.getMethod("allocateInstance", Class.class);
        SCNativeCompanion actor = (SCNativeCompanion) allocate.invoke(
                unsafe, SCNativeCompanion.class);
        SCNativeCompanion other = (SCNativeCompanion) allocate.invoke(
                unsafe, SCNativeCompanion.class);
        float physicalZ = actor.getZ();
        float otherZ = other.getZ();
        Field renderThread = SCNativeCompanion.class
                .getDeclaredField("bridgeOnBedRenderThread");
        renderThread.setAccessible(true);
        actor.setBridgeOnBedRenderLift(0.18f, null);
        try {
            require(Float.compare(actor.getZ(), physicalZ) == 0,
                    "bed render lift changed physical Z outside render");
            renderThread.set(actor, Thread.currentThread());
            require(Math.abs(actor.getZ() - physicalZ - 0.18f) < 0.00001f,
                    "model-camera render guard did not lift this actor");
            require(Float.compare(other.getZ(), otherZ) == 0,
                    "bed render lift leaked to another companion");
            AtomicReference<Float> concurrentZ = new AtomicReference<>();
            Thread observer = new Thread(() -> concurrentZ.set(actor.getZ()));
            observer.start();
            observer.join();
            require(Float.compare(concurrentZ.get(), physicalZ) == 0,
                    "bed render lift leaked to a concurrent physical read");
        } finally {
            renderThread.set(actor, null);
            actor.clearBridgeOnBedRenderLift();
        }
        require(Float.compare(actor.getZ(), physicalZ) == 0
                        && actor.getBridgeOnBedRenderLift() == 0.0f,
                "bed render lift did not clear without changing physical Z");
        float x = actor.getX(), y = actor.getY();
        actor.setSleepModelOffset(null, 0.25f, -0.25f, 0.10f);
        try {
            require(actor.getX() == x && actor.getY() == y && actor.getZ() == physicalZ,
                    "sleep model correction changed physical coordinates");
            renderThread.set(actor, Thread.currentThread());
            require(Math.abs(actor.getX() - x - 0.25f) < 0.00001f
                            && Math.abs(actor.getY() - y + 0.25f) < 0.00001f,
                    "sleep correction was not isolated to model rendering");
            AtomicReference<Float> concurrentX = new AtomicReference<>();
            Thread observer = new Thread(() -> concurrentX.set(actor.getX()));
            observer.start(); observer.join();
            require(concurrentX.get() == x && other.getX() == 0.0f,
                    "sleep correction leaked to physical reads or another actor");
        } finally {
            renderThread.set(actor, null);
            actor.clearSleepModelOffset();
        }
        require(actor.getX() == x && actor.getY() == y && actor.getZ() == physicalZ,
                "sleep model correction was not cleared");
    }

    private static void testHandoverLoaderBoundary() throws Exception {
        Class<?> unsafeClass=Class.forName("sun.misc.Unsafe");
        Field singleton=unsafeClass.getDeclaredField("theUnsafe");singleton.setAccessible(true);
        Object unsafe=singleton.get(null);
        Method allocate=unsafeClass.getMethod("allocateInstance",Class.class);
        zombie.characters.IsoPlayer human=(zombie.characters.IsoPlayer)allocate.invoke(unsafe,zombie.characters.IsoPlayer.class);
        SCNativeCompanion cold=(SCNativeCompanion)allocate.invoke(unsafe,SCNativeCompanion.class);
        Field leader=SCSplitScreenProbe.class.getDeclaredField("leader");leader.setAccessible(true);
        Field probe=SCSplitScreenProbe.class.getDeclaredField("coldProbe");probe.setAccessible(true);
        Object oldLeader=leader.get(null),oldProbe=probe.get(null);
        try {
            leader.set(null,cold);probe.set(null,null);
            require(!SCHandoverNative.ownsLoader(cold,1),"unowned ordinary NPC loader was accepted");
            probe.set(null,cold);
            require(SCHandoverNative.ownsLoader(cold,1),"exact hidden LF map loader was skipped while paused");
            require(!SCHandoverNative.ownsLoader(cold,0) && !SCHandoverNative.ownsLoader(human,1)
                    && SCHandoverNative.ownsLoader(human,0) && !SCHandoverNative.ownsLoader(cold,2),
                    "succession loader ownership escaped the primary and exact LF secondary slots");
        } finally {leader.set(null,oldLeader);probe.set(null,oldProbe);}
    }
    public static void main(String[] args) throws Exception {
        testHandoverLoaderBoundary();
        testOptionalOptimizerBoundary();
        Class<?> randomClass = Class.forName("zombie.core.random.RandStandard");
        Object random = randomClass.getField("INSTANCE").get(null);
        randomClass.getMethod("init").invoke(random);
        Class<?> fileSystemClass = Class.forName("zombie.ZomboidFileSystem");
        Object fileSystem = fileSystemClass.getField("instance").get(null);
        fileSystemClass.getMethod("setCacheDir", String.class).invoke(fileSystem,
                System.getProperty("java.io.tmpdir") + "LivingFellows-native-exposure-test");
        fileSystemClass.getMethod("init").invoke(fileSystem);

        Class<?> mainThreadClass = Class.forName("zombie.MainThread");
        mainThreadClass.getField("mainThread").set(null, Thread.currentThread());
        Field initialized = mainThreadClass.getDeclaredField("isInitialized");
        initialized.setAccessible(true);
        initialized.setBoolean(null, true);
        Method flushInvokeQueue = mainThreadClass.getDeclaredMethod("flushInvokeQueue");
        flushInvokeQueue.setAccessible(true);

        Class<?> bootstrapClass = Class.forName("livingfellows.bridge.SCBootstrap");
        bootstrapClass.getMethod("start").invoke(null);
        Thread.sleep(150L);
        require(!(Boolean) bootstrapClass.getMethod("isReady").invoke(null),
                "bootstrap exposed into LuaManager before the game initialized Kahlua");

        Class<?> managerClass = Class.forName("zombie.Lua.LuaManager");
        managerClass.getMethod("init").invoke(null);
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (!(Boolean) bootstrapClass.getMethod("isReady").invoke(null)
                && System.nanoTime() < deadline) {
            flushInvokeQueue.invoke(null);
            Thread.sleep(10L);
        }
        require((Boolean) bootstrapClass.getMethod("isReady").invoke(null),
                "production bootstrap did not expose the bridge: "
                        + bootstrapClass.getMethod("getStatus").invoke(null));
        testBodyFacts();

        int requestsBeforeContractFailure = SCBridge.getSpawnRequestCount();
        for (String missing : new String[] {
                "IsoGameCharacter.updateInternal is unavailable",
                "IsoPlayer.updateWhileInVehicle has an incompatible signature",
                "IsoPlayer.checkActionGroup is inaccessible"
        }) {
            SCNativeCompanion.failRuntimeContractForTests(missing);
            String failedReady = SCBridge.checkReady();
            long rejected = SCBridge.requestSpawn(null, "Negative", "Contract", false, "");
            require(failedReady.equals("native bridge runtime contract failed: " + missing)
                            && rejected == -1L
                            && SCBridge.getSpawnRequestCount() == requestsBeforeContractFailure
                            && SCBridge.getLastFailure().contains(missing),
                    "missing reflected method did not fail closed before allocating a request: "
                            + missing);
        }
        SCNativeCompanion.failRuntimeContractForTests(null);
        require(SCNativeCompanion.runtimeContractFailure().isEmpty(),
                "negative runtime-contract seam did not restore production readiness");

        Object environment = managerClass.getField("env").get(null);
        Object thread = managerClass.getField("thread").get(null);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        String source = "assert(SCBridge ~= nil, 'SCBridge is not exposed')\n"
                + "assert(SCBridge.openBugReportDraft('') == false, 'report browser guard is unavailable')\n"
                + "assert(AttackType ~= nil, 'AttackType is not exposed')\n"
                + "assert(AttackType.SHOVE ~= nil, 'AttackType.SHOVE is unavailable')\n"
                + "assert(AttackType.STOMP ~= nil, 'AttackType.STOMP is unavailable')\n"
                + "assert(AttackType.SHOT ~= nil, 'AttackType.SHOT is unavailable')\n"
                + "assert(AttackType.MELEE_SWING ~= nil, 'AttackType.MELEE_SWING is unavailable')\n"
                + "SC_TEST_PROTOCOL = SCBridge.getProtocol()\n"
                + "SC_TEST_READY = SCBridge.checkReady()\n"
                + "SC_TEST_VIEW_API = SCBridge.setViewOffset ~= nil and SCBridge.clearViewOffset ~= nil\n"
                + "SC_TEST_VIEW_RESTORE_API = SCSplitScreenProbe ~= nil and SCSplitScreenProbe.pollPrimaryViewRestore ~= nil and SCSplitScreenProbe.debugSetPrimaryViewRestoreMode ~= nil and SCSplitScreenProbe.debugPrimaryCutawaySample ~= nil\n"
                + "SC_TEST_VIEW_RESTORE_IDLE = SCSplitScreenProbe.pollPrimaryViewRestore()\n"
                + "SC_TEST_REMOTE_ARRIVAL_API = SCSplitScreenProbe.remoteArrivalCapability ~= nil\n"
                + "    and SCSplitScreenProbe.remoteArrivalCapability() == true\n"
                + "    and SCSplitScreenProbe.prepareRemoteArrival ~= nil\n"
                + "    and SCSplitScreenProbe.acknowledgeRemoteArrival ~= nil\n"
                + "    and SCSplitScreenProbe.remoteArrivalSlotSqlId ~= nil\n"
                + "    and SCSplitScreenProbe.primaryAreaContains ~= nil\n"
                + "    and SCSplitScreenProbe.releaseJoinedLeaderAtCamp ~= nil\n"
                + "    and SCSplitScreenProbe.persistCampLeaderSlotForReuse ~= nil\n"
                + "    and not SCSplitScreenProbe.canReleaseJoinedLeaderAtCamp({}, 500, 500, 0)\n"
                + "    and SCSplitScreenProbe.primaryRetainsHomeVehicle ~= nil\n"
                + "    and not SCSplitScreenProbe.primaryRetainsHomeVehicle(nil, -1)\n"
                + "    and not SCSplitScreenProbe.primaryAreaContains(500, 500, 0)\n"
                + "    and SCSplitScreenProbe.releaseRemoteArrival ~= nil\n"
                + "    and SCSplitScreenProbe.cancelRemoteArrival ~= nil\n"
                + "    and not SCSplitScreenProbe.canReleaseRemoteArrival(1)\n"
                + "SC_TEST_VEHICLE_SAVE_API = SCSplitScreenProbe.homeVehicleSaveCapability ~= nil\n"
                + "    and SCSplitScreenProbe.requestHomeVehicleSave ~= nil and SCSplitScreenProbe.pollHomeVehicleSave ~= nil\n"
                + "    and SCSplitScreenProbe.homeVehicleSaveFailure ~= nil and SCSplitScreenProbe.homeVehicleSaveReceipt ~= nil\n"
                + "    and SCSplitScreenProbe.restoreHomeVehicleSave ~= nil and SCSplitScreenProbe.cancelHomeVehicleSave ~= nil\n"
                + "    and SCSplitScreenProbe.attachRemoteArrivalVehicleSave ~= nil\n"
                + "    and SCSplitScreenProbe.requestHomeVehicleSave(nil) == 0 and SCSplitScreenProbe.pollHomeVehicleSave(0) == 'failed'\n"
                + "SC_TEST_VIEWPOINT_API = SCBridge.isViewpoint3DActive ~= nil and SCBridge.isViewpoint3DActive() == false\n"
                + "SC_TEST_STOCK_COMPARATOR_API = SCSplitScreenProbe.debugReleaseStockObserver ~= nil and SCSplitScreenProbe.debugPlayerSqlId ~= nil and not SCSplitScreenProbe.debugReleaseStockObserver(nil)\n"
                + "SC_TEST_BED_POSE_API = SCBridge.shiftOnBedPoseTowardPillow ~= nil\n"
                + "SC_TEST_BED_EXIT_API = SCBridge.recoverBedExit ~= nil and not SCBridge.recoverBedExit(nil, nil, nil)\n"
                + "SC_TEST_BED_POSE_REJECTS_NIL = not SCBridge.shiftOnBedPoseTowardPillow(nil, 0, 0, 0)\n"
                + "SC_TEST_BED_RENDER_LIFT_API = SCBridge.setOnBedRenderLift ~= nil\n"
                + "SC_TEST_BED_RENDER_LIFT_REJECTS_NIL = not SCBridge.setOnBedRenderLift(nil, 180)\n"
                + "SC_TEST_EXPEDITION_ZOOM_API = SCBridge.readExpeditionZoom ~= nil and SCBridge.setExpeditionZoomStep ~= nil and SCBridge.restoreExpeditionZoom ~= nil\n"
                + "SC_TEST_EXPEDITION_ZOOM_REJECTS_UNJOINED = not SCBridge.readExpeditionZoom({}) and not SCBridge.setExpeditionZoomStep(5)\n"
                + "SC_TEST_STORY_SHELTER_API = SCBridge.setStoryZombieIgnored ~= nil\n"
                + "SC_TEST_STORY_SHELTER_REJECTS_NIL = not SCBridge.setStoryZombieIgnored(nil, true)\n"
                + "SC_TEST_DRIVE_API = SCBridge.driveStart ~= nil and SCBridge.driveSet ~= nil\n"
                + "    and SCBridge.driveStop ~= nil and SCBridge.driveStatus ~= nil\n"
                + "    and SCBridge.scanLane ~= nil and SCBridge.driveFollow ~= nil\n"
                + "    and SCBridge.driveFollowTuned ~= nil\n"
                + "    and SCBridge.driveApproach ~= nil\n"
                + "    and SCBridge.driveAlign ~= nil\n"
                + "    and SCBridge.driveTurnAround ~= nil\n"
                + "SC_TEST_PASSENGER_DRIVE_API = SCBridge.driveStartWithPassenger ~= nil\n"
                + "SC_TEST_PASSENGER_DRIVE_REJECTS_NIL = not SCBridge.driveStartWithPassenger(nil, nil, true)\n"
                + "SC_TEST_ROAD_AVOIDANCE_API = SCBridge.planRoadRouteAvoidingAll ~= nil\n"
                + "local avoided = {}\n"
                + "SC_TEST_ROAD_AVOIDANCE_CALL = SCBridge.planRoadRouteAvoidingAll(\n"
                + "    nil, 20, 10, 100, 10, '60,10,8;', avoided)\n"
                + "    and avoided.status == 'INVALID_REQUEST' and avoided.reason == 'invalid_avoidance'\n"
                + "    and not SCBridge.planRoadRouteAvoidingAll(nil, 20, 10, 100, 10, '', nil)\n"
                + "SC_TEST_DRIVE_REJECTS_NIL = not SCBridge.driveStart(nil, true)\n"
                + "    and not SCBridge.driveSet(nil, 0, 10, true) and not SCBridge.driveStop(nil)\n"
                + "    and not SCBridge.driveStatus(nil, {}) and not SCBridge.scanLane(nil, 8, {})\n"
                + "    and not SCBridge.driveFollow(nil, '1,1,6;9,1,6', 10)\n"
                + "    and not SCBridge.driveFollowTuned(nil, '1,1,6;9,1,6', 10, 2)\n"
                + "    and not SCBridge.driveApproach(nil, '1,1,5;9,1,5', 5)\n"
                + "    and not SCBridge.driveAlign(nil, 9, 1)\n"
                + "    and not SCBridge.driveTurnAround(nil, true)\n"
                + "SC_TEST_ATTACK_TYPES = true\n";
        Object closure = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableClass)
                .invoke(null, source, "SCNativeBridgeExposureTest.lua", environment);
        thread.getClass().getMethod("call", Object.class, Object[].class)
                .invoke(thread, closure, (Object) new Object[0]);
        Method rawget = tableClass.getMethod("rawget", Object.class);
        require("42.22-isocompanion-38".equals(rawget.invoke(environment, "SC_TEST_PROTOCOL")),
                "Lua received the wrong native bridge protocol");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_VIEW_API")),
                "production bridge did not expose the camera offset contract");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_BED_POSE_API"))
                        && Boolean.TRUE.equals(rawget.invoke(environment,
                                "SC_TEST_BED_POSE_REJECTS_NIL")),
                "production bridge did not expose a guarded settled bed pose shift");
        float leftBedX = SCBridge.bedPillowShiftX(11.1875f, 11);
        float rightBedX = SCBridge.bedPillowShiftX(12023.84765625f, 12023);
        require(leftBedX == 11.6875f && rightBedX == 12023.34765625f
                        && (int) Math.floor(leftBedX) == 11
                        && (int) Math.floor(rightBedX) == 12023,
                "bed pillow correction must retain its lane from either entry side");
        require(Float.isNaN(SCBridge.bedPillowShiftX(Float.NaN, 11))
                        && Float.isNaN(SCBridge.bedPillowShiftX(12.2f, 11)),
                "bed pillow correction must reject an unrelated source column");
        require(SCBridge.bedSideShiftX(12024.375f, 12023) == 12023.875f
                        && SCBridge.bedSideShiftX(21.75f, 22) == 22.25f,
                "settled east/west entries must correct only half a tile into the adjacent pillow");
        require(Float.isNaN(SCBridge.bedSideShiftX(Float.NaN, 11))
                        && Float.isNaN(SCBridge.bedSideShiftX(12.8f, 11))
                        && Float.isNaN(SCBridge.bedSideShiftX(12.2f, 10))
                        && Float.isNaN(SCBridge.bedSideShiftX(12.2f, 12)),
                "side correction must reject distant, same-column and over-half-tile placement");
        require(SCBridge.class.getMethod("shiftOnBedPoseTowardPillow",
                        SCNativeCompanion.class, int.class, int.class, int.class)
                        .getReturnType() == boolean.class,
                "settled bed pose shift changed its Lua-facing signature");
        require(!SCBridge.shiftOnBedPoseTowardPillow(null, 0, 0, 0)
                        && SCBridge.getLastFailure().contains("null"),
                "settled bed pose shift admitted a missing actor");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_BED_RENDER_LIFT_API"))
                        && Boolean.TRUE.equals(rawget.invoke(environment,
                                "SC_TEST_BED_RENDER_LIFT_REJECTS_NIL")),
                "production bridge did not expose a guarded bed render lift");
        require(SCBridge.class.getMethod("setOnBedRenderLift",
                        SCNativeCompanion.class, int.class)
                        .getReturnType() == boolean.class,
                "bed render lift changed its Lua-facing signature");
        require(!SCBridge.setOnBedRenderLift(null, 180)
                        && SCBridge.getLastFailure().contains("null"),
                "bed render lift admitted a missing actor");
        testOnBedRenderLiftIsolation();
        testWindowPermissionIsolation();
        require(SCBridge.class.getMethod("alignSleepingBedModel", SCNativeCompanion.class,
                        zombie.iso.IsoObject.class).getReturnType() == boolean.class
                        && !SCBridge.alignSleepingBedModel(null, null),
                "sleep model alignment must expose an owned-actor guard");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_EXPEDITION_ZOOM_API"))
                        && Boolean.TRUE.equals(rawget.invoke(environment,
                                "SC_TEST_EXPEDITION_ZOOM_REJECTS_UNJOINED")),
                "production bridge did not expose a guarded expedition zoom contract");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_VIEW_RESTORE_API"))
                        && "cancelled".equals(rawget.invoke(environment, "SC_TEST_VIEW_RESTORE_IDLE")),
                "production Kahlua bridge omitted the additive deferred-view capability");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_REMOTE_ARRIVAL_API")),
                "production Kahlua bridge omitted the guarded remote-arrival transaction");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_VEHICLE_SAVE_API")),
                "production Kahlua bridge omitted or opened the guarded committed-vehicle save API");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_VIEWPOINT_API")),
                "optional Viewpoint state was not safely exposed to Lua");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_BED_EXIT_API")),
                "bed-specific recovery was not exposed with owned-actor guards");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_STOCK_COMPARATOR_API"))
                        && SCSplitScreenProbe.debugPlayerSqlId(null) == Integer.MIN_VALUE,
                "production Kahlua bridge omitted or opened the guarded stock comparator");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_STORY_SHELTER_API")),
                "production bridge did not expose the owned story zombie shelter API");
        require(Boolean.TRUE.equals(rawget.invoke(environment,
                        "SC_TEST_STORY_SHELTER_REJECTS_NIL")),
                "Lua could not call the story zombie shelter API or it accepted nil");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_DRIVE_API")),
                "production bridge did not expose the companion driving API");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_PASSENGER_DRIVE_API"))
                        && Boolean.TRUE.equals(rawget.invoke(environment,
                                "SC_TEST_PASSENGER_DRIVE_REJECTS_NIL")),
                "Lua could not call the guarded passenger driving entry");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_ROAD_AVOIDANCE_API"))
                        && Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_ROAD_AVOIDANCE_CALL")),
                "Lua could not call the bounded multi-circle planner or invalid text was accepted");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_DRIVE_REJECTS_NIL")),
                "Lua could not call the companion driving API or it accepted nil");
        require(Boolean.TRUE.equals(rawget.invoke(environment, "SC_TEST_ATTACK_TYPES")),
                "production bridge did not expose the native attack enum contract");
        String readiness = String.valueOf(rawget.invoke(environment, "SC_TEST_READY"));
        require(SCBridge.isSupportedGameVersion("42.22")
                        && SCBridge.isSupportedGameVersion("42.22.2")
                        && !SCBridge.isSupportedGameVersion("42.21")
                        && !SCBridge.isSupportedGameVersion("42.22.1")
                        && !SCBridge.isSupportedGameVersion("42.23")
                        && !SCBridge.isSupportedGameVersion("42.19")
                        && !SCBridge.isSupportedGameVersion("42.20"),
                "native bridge release-family gate is too broad or rejects a valid live label");
        require(!readiness.contains("requires Project Zomboid"),
                "live 42.22 label was incorrectly rejected by the version gate: " + readiness);
        require(!readiness.isEmpty(),
                "headless readiness unexpectedly bypassed the local-player isolation gate");

        Class<?> isoCamera = Class.forName("zombie.iso.IsoCamera");
        Class<?> playerCamera = Class.forName("zombie.iso.PlayerCamera");
        Object cameras = isoCamera.getField("cameras").get(null);
        Object camera = playerCamera.getConstructor(int.class).newInstance(0);
        Array.set(cameras, 0, camera);
        playerCamera.getField("rightClickX").setFloat(camera, 7.0f);
        playerCamera.getField("rightClickY").setFloat(camera, -5.0f);
        require(!SCBridge.setViewOffset(Float.NaN, 1.0f)
                        && SCBridge.getLastFailure().contains("finite"),
                "camera offset accepted a non-finite coordinate");
        require(SCBridge.setViewOffset(30.0f, 40.0f),
                "camera offset rejected a finite main-thread coordinate");
        require(Math.abs(playerCamera.getField("deferedX").getFloat(camera) - 9.6f) < 0.001f
                        && Math.abs(playerCamera.getField("deferedY").getFloat(camera) - 12.8f) < 0.001f,
                "camera offset did not clamp to the sixteen-tile radial bound");
        require(playerCamera.getField("rightClickX").getFloat(camera) == 7.0f
                        && playerCamera.getField("rightClickY").getFloat(camera) == -5.0f,
                "camera offset overwrote the independent right-click aim lean");
        require(SCBridge.clearViewOffset()
                        && playerCamera.getField("deferedX").getFloat(camera) == 0.0f
                        && playerCamera.getField("deferedY").getFloat(camera) == 0.0f
                        && playerCamera.getField("rightClickX").getFloat(camera) == 7.0f
                        && playerCamera.getField("rightClickY").getFloat(camera) == -5.0f,
                "camera offset clear did not restore only the deferred view");
        require(!SCBridge.setExpeditionZoomStep(0)
                        && SCBridge.getLastFailure().contains("1 to 10")
                        && SCBridge.restoreExpeditionZoom(),
                "expedition zoom step bounds or idempotent restore changed");
        System.out.println("NATIVE_BRIDGE_EXPOSURE_PASS protocol=true kahlua=true multi-circle=true attack-types=true camera-offset=true bed-pose=true bed-render-lift=true expedition-zoom=true version-family-gate=true local-player-gate=true reflection-negative=true");
    }
}
