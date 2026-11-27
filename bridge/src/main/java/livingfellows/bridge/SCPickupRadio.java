// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.util.List;
import java.lang.reflect.Method;
import java.lang.reflect.Field;
import zombie.MainThread;
import zombie.characters.IsoPlayer;
import zombie.radio.ZomboidRadio;
import zombie.network.GameClient;
import zombie.network.GameServer;

/** One synchronous native transmission to an exact companion handset. */
final class SCPickupRadio {
    private SCPickupRadio() {}

    static boolean transmit(SCNativeCompanion recipient, Object handset,
            int x, int y, int channel, String text, String guid, String codes, int range) {
        if (Thread.currentThread() != MainThread.mainThread || GameClient.client || GameServer.server
                || !SCBridge.checkReady().isEmpty()
                || x < 0 || y < 0 || x > 30000 || y > 30000 || channel < 1
                || range < 1 || range > 30000 || text == null || text.isBlank() || text.length() > 512
                || guid == null || guid.isBlank() || guid.length() > 128
                || codes == null || codes.isBlank() || codes.length() > 128) return false;
        Object manager = ZomboidRadio.getInstance();
        boolean removed = false, contextual = false;
        try {
            if (recipient != null) {
                if (!SCBridge.isCompanion(recipient) || !recipient.isBridgeHealthy()
                        || recipient.isDead() || recipient.getCurrentSquare() == null || handset == null
                        || SCTerminalDevices.call(recipient,"getEquipedRadio") != handset) return false;
                Object data = SCTerminalDevices.call(handset,"getDeviceData");
                if (!Boolean.TRUE.equals(SCTerminalDevices.call(data,"getIsTurnedOn"))
                        || !Boolean.TRUE.equals(SCTerminalDevices.call(data,"getIsTwoWay"))
                        || ((Number) SCTerminalDevices.call(data,"getChannel")).intValue() != channel
                        || ((Number) SCTerminalDevices.call(data,"getPower")).doubleValue() <= 0) return false;
                Object devices = SCTerminalDevices.call(manager,"getDevices");
                if (!(devices instanceof List<?> known) || known.size() > 2048) return false;
                boolean exists = false;
                for (Object device : known) if (device == handset) { exists = true; break; }
                if (exists) {
                    SCTerminalDevices.call(manager,"UnRegisterDevice",handset);
                    removed = true;
                }
                recipient.beginCompanionRadioTextContext();
                contextual = true;
            }
            // Same single-player packet preparation as SendTransmission. The
            // exact prepared packet also reaches the nonlocal companion below;
            // weather and range interference cannot turn into a false receipt.
            Field interference=ZomboidRadio.class.getDeclaredField("hasAppliedInterference");
            interference.setAccessible(true);
            interference.setBoolean(manager,false);
            Method weather=ZomboidRadio.class.getDeclaredMethod("applyWeatherInterference",String.class,int.class);
            weather.setAccessible(true);
            String transmitted=(String) weather.invoke(manager,text,range);
            boolean distorted=interference.getBoolean(manager);
            String deliveredCodes=distorted?"":codes;
            float red=distorted?.5f:.75f,green=distorted?.5f:.9f,blue=distorted?.5f:.8f;
            SCTerminalDevices.call(manager,"DistributeTransmission",x,y,channel,transmitted,guid,deliveredCodes,
                    red,green,blue,range,false);
            if (recipient != null) {
                boolean listed = false;
                for (IsoPlayer player : IsoPlayer.players) if (player == recipient) listed = true;
                if (!listed) {
                    // The engine visits only IsoPlayer.players here. Run its
                    // exact portable-player receiver for the camp companion,
                    // including native channel, volume, distance and distortion.
                    Method receive = ZomboidRadio.class.getDeclaredMethod("DistributeToPlayer",
                            IsoPlayer.class,int.class,int.class,int.class,String.class,String.class,
                            String.class,float.class,float.class,float.class,int.class,boolean.class);
                    receive.setAccessible(true);
                    receive.invoke(manager,recipient,x,y,channel,transmitted,guid,deliveredCodes,red,green,blue,range,false);
                }
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            return false;
        } finally {
            if (contextual) recipient.endCompanionRadioTextContext();
            if (removed) {
                try { SCTerminalDevices.call(manager,"RegisterDevice",handset); }
                catch (ReflectiveOperationException | RuntimeException ignored) { }
            }
        }
    }
}
