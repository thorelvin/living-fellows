// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

/** Version-pinned premain hook that makes the final stock shell extensible before class definition. */
public final class SCBridgeAgent {
    private static final int EXPECTED_CLASS_MAJOR = 69;
    private static final int ACC_FINAL = 0x0010;
    private static volatile boolean transformed;
    private static volatile String status = "agent has not started";

    private SCBridgeAgent() {}

    public static void premain(String arguments, Instrumentation instrumentation) {
        status = "waiting for IsoSurvivor definition";
        instrumentation.addTransformer(new IsoSurvivorAccessTransformer(), false);
        SCExposure.installAsync();
    }

    public static boolean isTransformed() {
        return transformed;
    }

    public static String getStatus() {
        return status;
    }

    private static final class IsoSurvivorAccessTransformer implements ClassFileTransformer {
        @Override
        public byte[] transform(
                Module module,
                ClassLoader loader,
                String className,
                Class<?> classBeingRedefined,
                ProtectionDomain protectionDomain,
                byte[] classfileBuffer) throws IllegalClassFormatException {
            if (!"zombie/characters/IsoSurvivor".equals(className)) {
                return null;
            }
            try {
                byte[] transformedBytes = classfileBuffer.clone();
                int major = unsignedShort(transformedBytes, 6);
                if (major != EXPECTED_CLASS_MAJOR) {
                    status = "unexpected IsoSurvivor class version " + major;
                    throw new IllegalClassFormatException(status);
                }
                int accessOffset = accessFlagsOffset(transformedBytes);
                int accessFlags = unsignedShort(transformedBytes, accessOffset);
                if ((accessFlags & ACC_FINAL) == 0) {
                    status = "IsoSurvivor is unexpectedly non-final";
                    throw new IllegalClassFormatException(status);
                }
                writeUnsignedShort(transformedBytes, accessOffset, accessFlags & ~ACC_FINAL);
                transformed = true;
                status = "ready";
                return transformedBytes;
            } catch (IllegalClassFormatException failure) {
                throw failure;
            } catch (RuntimeException failure) {
                status = "IsoSurvivor class layout mismatch";
                throw new IllegalClassFormatException(status + ": " + failure.getMessage());
            }
        }
    }

    private static int accessFlagsOffset(byte[] bytes) {
        if (readInt(bytes, 0) != 0xCAFEBABE) {
            throw new IllegalArgumentException("not a Java class file");
        }
        int constantPoolCount = unsignedShort(bytes, 8);
        int offset = 10;
        for (int index = 1; index < constantPoolCount; index++) {
            int tag = unsignedByte(bytes, offset++);
            switch (tag) {
                case 1 -> offset += 2 + unsignedShort(bytes, offset);
                case 3, 4 -> offset += 4;
                case 5, 6 -> {
                    offset += 8;
                    index++;
                }
                case 7, 8, 16, 19, 20 -> offset += 2;
                case 9, 10, 11, 12, 17, 18 -> offset += 4;
                case 15 -> offset += 3;
                default -> throw new IllegalArgumentException("unknown constant-pool tag " + tag);
            }
            if (offset < 0 || offset > bytes.length - 2) {
                throw new IllegalArgumentException("truncated constant pool");
            }
        }
        return offset;
    }

    private static int unsignedByte(byte[] bytes, int offset) {
        return bytes[offset] & 0xff;
    }

    private static int unsignedShort(byte[] bytes, int offset) {
        return (unsignedByte(bytes, offset) << 8) | unsignedByte(bytes, offset + 1);
    }

    private static int readInt(byte[] bytes, int offset) {
        return (unsignedByte(bytes, offset) << 24)
                | (unsignedByte(bytes, offset + 1) << 16)
                | (unsignedByte(bytes, offset + 2) << 8)
                | unsignedByte(bytes, offset + 3);
    }

    private static void writeUnsignedShort(byte[] bytes, int offset, int value) {
        bytes[offset] = (byte) ((value >>> 8) & 0xff);
        bytes[offset + 1] = (byte) (value & 0xff);
    }
}
