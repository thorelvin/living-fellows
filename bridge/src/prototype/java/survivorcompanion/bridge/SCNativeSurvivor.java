// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;

import zombie.characters.CharacterSoundEmitter;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoSurvivor;
import zombie.characters.SurvivorDesc;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.Moodles.Moodles;
import zombie.core.skinnedmodel.visual.BaseVisual;
import zombie.iso.IsoCell;

/** A stock IsoSurvivor with the native components absent from the Build 42 shell class. */
public final class SCNativeSurvivor extends IsoSurvivor {
    private final SurvivorDesc companionDescriptor;

    public SCNativeSurvivor(SurvivorDesc descriptor, IsoCell cell, int x, int y, int z) {
        super(descriptor, cell, x, y, z);
        companionDescriptor = descriptor;
        installNativeComponents();
        descriptor.setInstance(this);
    }

    @Override
    public BaseVisual getVisual() {
        return companionDescriptor.getHumanVisual();
    }

    public boolean hasNativeComponents() {
        return getBodyDamage() != null
                && getMoodles() != null
                && getXp() != null
                && getEmitter() != null
                && getVisual() != null;
    }

    private void installNativeComponents() {
        try {
            setCharacterField("bodyDamage", new BodyDamage(this));
            setCharacterField("moodles", new Moodles(this));
            setCharacterField("emitter", new CharacterSoundEmitter(this));
            setXp(new IsoGameCharacter.XP(this, this));
        } catch (ReflectiveOperationException failure) {
            throw new IllegalStateException("42.20.4 native component layout mismatch", failure);
        }
        if (!hasNativeComponents()) {
            throw new IllegalStateException("native IsoSurvivor components were not initialized");
        }
    }

    private void setCharacterField(String name, Object value) throws ReflectiveOperationException {
        Field field = IsoGameCharacter.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(this, value);
    }
}
