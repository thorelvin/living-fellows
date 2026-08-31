// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.reflect.Field;

import zombie.characters.CharacterSoundEmitter;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoLivingCharacter;
import zombie.characters.SurvivorDesc;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.Moodles.Moodles;
import zombie.core.skinnedmodel.visual.BaseVisual;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;

/** Non-release experiment: a human character that does not modify the final stock IsoSurvivor. */
public final class SCNativeCharacterPrototype extends IsoLivingCharacter {
    private final SurvivorDesc descriptor;

    public SCNativeCharacterPrototype(SurvivorDesc descriptor, IsoGridSquare square) {
        super(square.getCell(), square.getX() + 0.5f, square.getY() + 0.5f, square.getZ());
        this.descriptor = descriptor;
        setCurrentSquare(square);
        descriptor.setInstance(this);
        initWornItems("Human");
        initAttachedItems("Human");
        try {
            if (getBodyDamage() == null) setCharacterField("bodyDamage", new BodyDamage(this));
            if (getMoodles() == null) setCharacterField("moodles", new Moodles(this));
            if (getEmitter() == null) setCharacterField("emitter", new CharacterSoundEmitter(this));
            if (getXp() == null) setXp(new IsoGameCharacter.XP(this, this));
        } catch (ReflectiveOperationException failure) {
            throw new IllegalStateException("native component initialization failed", failure);
        }
    }

    @Override
    public BaseVisual getVisual() {
        return descriptor.getHumanVisual();
    }

    private void setCharacterField(String name, Object value) throws ReflectiveOperationException {
        Field field = IsoGameCharacter.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(this, value);
    }
}
