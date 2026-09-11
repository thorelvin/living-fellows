// SPDX-License-Identifier: MIT
package zombie.characters;

import zombie.core.skinnedmodel.visual.HumanVisual;

public class SurvivorDesc {
    public void dressInNamedOutfit(String outfit) {}
    public HumanVisual getHumanVisual() { return null; }
    public String getVoicePrefix() { return null; }
    public boolean isFemale() { return false; }
    public void setFemale(boolean female) {}
    public void setForename(String forename) {}
    public void setInstance(IsoGameCharacter instance) {}
    public void setSurname(String surname) {}
    public void setVoicePrefix(String prefix) {}
}
