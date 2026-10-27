// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collection;
import java.util.List;
import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.pathfind.VehiclePoly;
import zombie.vehicles.BaseVehicle;

/** Version checked native operations; never changes player lists or cameras. */
final class SCTerminalDevices {
    private static final int MAX_ITEM_BYTES = 262144;
    private static String clearanceReason="not_checked";
    static String clearanceReason() { return clearanceReason; }
    private SCTerminalDevices() {}

    static Object call(Object target, String name, Object... args) throws ReflectiveOperationException {
        Class<?> type = target instanceof Class<?> c ? c : target.getClass();
        for (Method method : type.getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != args.length) continue;
            try { return method.invoke(target instanceof Class<?> ? null : target, args); }
            catch (IllegalArgumentException wrongOverload) { /* try next overload */ }
        }
        throw new NoSuchMethodException(type.getName() + "." + name);
    }
    private static Class<?> type(String name) throws ClassNotFoundException { return Class.forName(name); }
    private static boolean truth(Object target, String name) throws ReflectiveOperationException {
        return Boolean.TRUE.equals(call(target,name));
    }
    private static List<IsoObject> leaves(IsoObject door) throws ReflectiveOperationException {
        Class<?> doors=type("zombie.iso.objects.IsoDoor");
        List<IsoObject> result=new ArrayList<>();
        if (((Number)call(doors,"getGarageDoorIndex",door)).intValue()>0) {
            Object cursor=call(doors,"getGarageDoorFirst",door);
            for(int i=0;cursor instanceof IsoObject leaf && i<12;i++) {
                if(result.contains(leaf)) break;
                result.add(leaf); cursor=call(doors,"getGarageDoorNext",leaf);
            }
        } else if (((Number)call(doors,"getDoubleDoorIndex",door)).intValue()>0) {
            for(int i=1;i<=4;i++) {
                Object leaf=call(doors,"getDoubleDoorObject",door,i);
                if(leaf instanceof IsoObject object && !result.contains(object)) result.add(object);
            }
        }
        if(result.isEmpty()) result.add(door);
        return result;
    }
    static boolean obstructed(IsoObject door) {
        clearanceReason="door_unavailable";
        if(door==null || door.getSquare()==null) return true;
        try {
            if(((Number)call(door,"getObjectIndex")).intValue()<0) return true;
            List<IsoObject> leaves=leaves(door);
            List<IsoGridSquare> footprint=new ArrayList<>();
            for(IsoObject leaf:leaves) {
                IsoGridSquare square=leaf.getSquare();
                if(square==null) return true;
                Object opposite=call(leaf,"getOppositeSquare");
                if(!(opposite instanceof IsoGridSquare other)) return true;
                if(!footprint.contains(square)) footprint.add(square);
                if(!footprint.contains(other)) footprint.add(other);
            }
            Object vehicles=call(door.getSquare().getCell(),"getVehicles");
            if(!(vehicles instanceof Collection<?> loaded) || loaded.size()>512) { clearanceReason="vehicle_collection_unavailable_or_unbounded"; return true; }
            for(IsoGridSquare square:footprint) {
                if(!square.getMovingObjects().isEmpty() || !square.getStaticMovingObjects().isEmpty()) {
                    clearanceReason="actor_or_body_at:"+square.getX()+":"+square.getY(); return true;
                }
                for(Object value:loaded) {
                    if(!(value instanceof BaseVehicle vehicle) || Math.abs(vehicle.getZ()-square.getZ())>0.5f) continue;
                    VehiclePoly p=vehicle.getPoly();
                    if(p==null) return true;
                    float minX=Math.min(Math.min(p.x1,p.x2),Math.min(p.x3,p.x4));
                    float maxX=Math.max(Math.max(p.x1,p.x2),Math.max(p.x3,p.x4));
                    float minY=Math.min(Math.min(p.y1,p.y2),Math.min(p.y3,p.y4));
                    float maxY=Math.max(Math.max(p.y1,p.y2),Math.max(p.y3,p.y4));
                    if(maxX>=square.getX() && minX<=square.getX()+1 && maxY>=square.getY() && minY<=square.getY()+1) {
                        clearanceReason="vehicle_at:"+square.getX()+":"+square.getY(); return true;
                    }
                }
            }
            clearanceReason="clear"; return false;
        } catch(ReflectiveOperationException | RuntimeException unavailable) {
            clearanceReason="interface_unavailable:"+unavailable.getClass().getSimpleName()+":"+unavailable.getMessage(); return true;
        }
    }
    static boolean locked(IsoObject door, boolean locked) {
        try {
            for(IsoObject leaf:leaves(door)) {
                call(leaf,"setLockedByKey",locked);
                try { call(leaf,"setLocked",locked); }
                catch(NoSuchMethodException thumpable) { call(leaf,"setIsLocked",locked); }
                call(leaf,"syncIsoObject",false,(byte)0,null,null);
                if(truth(leaf,"isLockedByKey")!=locked || truth(leaf,"isLocked")!=locked) return false;
            }
            return true;
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return false; }
    }
    static boolean opened(IsoObject door, boolean open, IsoGameCharacter operator) {
        if(obstructed(door)) return false;
        try {
            if(truth(door,"IsOpen")==open) return true;
            Class<?> doors=type("zombie.iso.objects.IsoDoor");
            if(((Number)call(doors,"getGarageDoorIndex",door)).intValue()>0) call(doors,"toggleGarageDoor",door,true);
            else if(((Number)call(doors,"getDoubleDoorIndex",door)).intValue()>0) call(doors,"toggleDoubleDoor",door,true);
            else call(door,"ToggleDoorActual",operator);
            // The Lua receipt resolves replaced grouped leaves by footprint.
            return true;
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return false; }
    }
    static String pack(Object item) {
        if(item==null) return null;
        try {
            ByteBuffer buffer=ByteBuffer.allocate(MAX_ITEM_BYTES);
            call(item,"saveWithSize",buffer,false);
            byte[] bytes=new byte[buffer.position()]; buffer.flip(); buffer.get(bytes);
            int version=((Number)call(IsoWorld.class,"getWorldVersion")).intValue();
            return version+":"+Base64.getEncoder().encodeToString(bytes);
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return null; }
    }
    static Object unpack(String payload) {
        if(payload==null || payload.length()>MAX_ITEM_BYTES*2) return null;
        try {
            int separator=payload.indexOf(':');
            int version=Integer.parseInt(payload.substring(0,separator));
            int current=((Number)call(IsoWorld.class,"getWorldVersion")).intValue();
            if(version>current || version<1) return null;
            byte[] bytes=Base64.getDecoder().decode(payload.substring(separator+1));
            if(bytes.length>MAX_ITEM_BYTES) return null;
            return call(type("zombie.inventory.InventoryItem"),"loadItem",ByteBuffer.wrap(bytes),version);
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return null; }
    }
    static Object receiver(Object item, IsoObject computer) {
        try {
            Object data=call(item,"getDeviceData");
            Object cell=computer.getSquare().getCell();
            Class<?> radio=type("zombie.iso.objects.IsoRadio");
            Object value=radio.getConstructor(type("zombie.iso.IsoCell"),IsoGridSquare.class,
                    type("zombie.iso.sprite.IsoSprite")).newInstance(cell,computer.getSquare(),computer.getSprite());
            call(value,"setDeviceData",data);
            call(data,"setParent",value);
            // Process/receive as a native world radio, but do not add a second
            // visible computer or a separately saved inventory owner.
            // A projection is not a map leaf. Register only its radio endpoint;
            // the existing LF scheduler drives its native update. An index -1
            // object must not enter the cell's map-object update collection.
            Object manager=call(type("zombie.radio.ZomboidRadio"),"getInstance");
            call(manager,"RegisterDevice",value);
            return value;
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return null; }
    }
    static int silence(Object building, Object manager) {
        try {
            if(manager==null) manager=call(type("zombie.AmbientStreamManager"),"getInstance");
            if(manager==null || !type("zombie.AmbientStreamManager").isInstance(manager)) return -1;
            Field alarms=manager.getClass().getField("alarmList");
            if(!(alarms.get(manager) instanceof List<?> active)) return -1;
            int x=((Number)call(building,"getX")).intValue(), y=((Number)call(building,"getY")).intValue();
            int x2=((Number)call(building,"getX2")).intValue(), y2=((Number)call(building,"getY2")).intValue();
            Class<?> alarm=type("zombie.iso.Alarm");
            Field ax=alarm.getDeclaredField("x"), ay=alarm.getDeclaredField("y"), sound=alarm.getDeclaredField("inst");
            ax.setAccessible(true); ay.setAccessible(true); sound.setAccessible(true);
            Field finished=alarm.getField("finished");
            if(active.size()>1024) return -1;
            Object grid=call(IsoWorld.instance,"getMetaGrid");
            List<Object> matching=new ArrayList<>();
            for(Object value:active) {
                if(!alarm.isInstance(value)) return -1;
                int px=ax.getInt(value), py=ay.getInt(value);
                if(px>=x && px<x2 && py>=y && py<y2) {
                    Object owner=call(grid,"getBuildingAt",px,py);
                    if(owner==null || owner==building) matching.add(value);
                }
            }
            for(Object value:matching) finished.setBoolean(value,true);
            active.removeAll(matching);
            if(active.isEmpty() && !matching.isEmpty()) {
                long handle=sound.getLong(null);
                if(handle!=0L) {
                    call(type("fmod.javafmod"),"FMOD_Studio_EventInstance_Stop",handle,false);
                    sound.setLong(null,0L);
                }
            }
            return matching.size();
        } catch(ReflectiveOperationException | RuntimeException unavailable) { return -1; }
    }
}
