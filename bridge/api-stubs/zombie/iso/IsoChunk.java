// SPDX-License-Identifier: MIT
package zombie.iso;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.zip.CRC32;

public class IsoChunk {
    public int wx;
    public int wy;
    public final ArrayList<IsoChunkMap> refs = new ArrayList<>();
    public IsoChunk(IsoCell cell) {}
    public void removeFromWorld() {}
    public ByteBuffer Save(ByteBuffer buffer, CRC32 crc, boolean hotSave) throws IOException { return buffer; }
    public static void SafeWrite(int wx, int wy, ByteBuffer buffer) throws IOException {}
}
