// SPDX-License-Identifier: MIT
package zombie.characters.BodyDamage;

import zombie.characters.IsoGameCharacter;
import java.util.ArrayList;

public class BodyDamage {
    public BodyDamage(IsoGameCharacter owner) {}
    public float getHealth() { return 100.0f; }
    public boolean IsInfected() { return false; }
    public float getApparentInfectionLevel() { return 0.0f; }
    public float getInfectionTime() { return -1.0f; }
    public float getInfectionMortalityDuration() { return -1.0f; }
    public ArrayList<BodyPart> getBodyParts() { return new ArrayList<>(); }
    public float getOverallBodyHealth() { return 100.0f; }
    public void ReduceGeneralHealth(float amount) {}
}
