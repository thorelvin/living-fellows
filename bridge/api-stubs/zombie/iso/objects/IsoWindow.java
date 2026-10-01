// SPDX-License-Identifier: MIT
package zombie.iso.objects;
import zombie.iso.IsoObject;
import zombie.characters.IsoGameCharacter;
public class IsoWindow extends IsoObject {
    public int getObjectIndex() { return -1; }
    public boolean IsOpen() { return false; }
    public void ToggleWindow(IsoGameCharacter character) {}
}
