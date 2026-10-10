// SPDX-License-Identifier: MIT
package zombie.network.fields.hit;

import zombie.iso.IsoMovingObject;

public class HitInfo {
    public HitInfo init(IsoMovingObject object, float dot, float distSq,
            float x, float y, float z) { return this; }
    public IsoMovingObject getObject() { return null; }
}
