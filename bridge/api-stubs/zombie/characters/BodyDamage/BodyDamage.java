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
    public float getCatchACold() { return 0.0f; }
    public void setCatchACold(float value) {}
    public boolean isHasACold() { return false; }
    public void setHasACold(boolean value) {}
    public float getColdStrength() { return 0.0f; }
    public void setColdStrength(float value) {}
    public float getTimeToSneezeOrCough() { return 0.0f; }
    public void setTimeToSneezeOrCough(float value) {}
    public int getSneezeCoughActive() { return 0; }
    public void setSneezeCoughActive(int value) {}
    public int getSneezeCoughTime() { return 0; }
    public void setSneezeCoughTime(int value) {}
}
