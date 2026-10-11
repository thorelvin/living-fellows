// SPDX-License-Identifier: MIT
package zombie.core.properties;

import zombie.iso.SpriteDetails.IsoFlagType;

/** Compile-only Project Zomboid API shape; excluded from the bridge JAR. */
public class PropertyContainer {
    public boolean has(IsoFlagType flag) { return false; }
    public String get(String name) { return null; }
}
