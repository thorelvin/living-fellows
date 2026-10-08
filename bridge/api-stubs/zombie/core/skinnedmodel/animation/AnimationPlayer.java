// SPDX-License-Identifier: MIT
package zombie.core.skinnedmodel.animation;

import org.lwjgl.util.vector.Vector3f;
import zombie.core.skinnedmodel.model.SkeletonBone;

public class AnimationPlayer {
    public AnimationMultiTrack getMultiTrack() { return null; }
    public void resetDeferredMovementAccum() {}
    public float getRenderedAngle() { return 0; }
    public int getSkinningBoneIndex(String name, int fallback) { return fallback; }
    public Vector3f getBoneWorldPosition(SkeletonBone bone, Vector3f output) { return output; }
}
