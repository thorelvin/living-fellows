// SPDX-License-Identifier: MIT
package zombie.radio;

/** Compile-only signature pinned to Project Zomboid 42.20.4. */
public class ZomboidRadio {
    public static ZomboidRadio getInstance() { return null; }
    public void SendTransmission(int x, int y, int channel, String text,
            String guid, String codes, float red, float green, float blue,
            int range, boolean television) {}
}
