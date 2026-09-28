// SPDX-License-Identifier: MIT
package zombie.iso;

import java.util.HashMap;

public class IsoChunkMap {
    public static final HashMap<Integer, IsoChunk> SharedChunks = new HashMap<>();
    public boolean ignore;
    public int playerId;
    public IsoChunkMap(IsoCell cell) {}
    public void Unload() {}
    public IsoChunk[] getChunks() { return null; }
    public int getWorldXMinTiles() { return -1; }
    public int getWorldYMinTiles() { return -1; }
    public int getWorldXMaxTiles() { return -1; }
    public int getWorldYMaxTiles() { return -1; }
}
