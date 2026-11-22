// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.net.URISyntaxException;
import java.nio.file.Paths;
import java.security.CodeSource;
import java.util.Locale;

/**
 * Names which Living Fellows copy supplied this bridge, never its local path.
 *
 * The standalone installer puts LivingFellowsBridge.jar beside the game, where
 * its launcher or PZO loads it before any mod. ZombieBuddy loads the JAR inside
 * the enabled mod's media/java folder instead. Project Zomboid loads one copy's
 * Lua by folder order (upload staging, then Workshop, then Zomboid\mods), so
 * comparing the two tells the Lua when two editions are mixed.
 */
final class SCBridgeOrigin {
    static final String LAUNCHER = "launcher";
    static final String WORKSHOP = "workshop";
    static final String STAGING = "staging";
    static final String MODS = "mods";
    static final String UNKNOWN = "unknown";

    private SCBridgeOrigin() {}

    static String current() {
        try {
            CodeSource source = SCBridgeOrigin.class.getProtectionDomain().getCodeSource();
            if (source == null || source.getLocation() == null) return UNKNOWN;
            return classify(Paths.get(source.getLocation().toURI()).toString());
        } catch (RuntimeException | URISyntaxException failure) {
            return UNKNOWN;
        }
    }

    static String classify(String path) {
        if (path == null || path.isBlank()) return UNKNOWN;
        String normalized = path.replace('\\', '/');
        String name = normalized.substring(normalized.lastIndexOf('/') + 1);
        if (name.equalsIgnoreCase("LivingFellowsBridge.jar")) return LAUNCHER;
        String lower = normalized.toLowerCase(Locale.ROOT);
        if (!lower.endsWith("/media/java/survivorcompanionbridge.jar")) return UNKNOWN;
        if (lower.contains("/steamapps/workshop/content/")) return WORKSHOP;
        if (lower.contains("/zomboid/workshop/")) return STAGING;
        return MODS;
    }

    static String release() {
        Package source = SCBridgeOrigin.class.getPackage();
        String version = source == null ? null : source.getImplementationVersion();
        return version == null || version.isBlank() ? UNKNOWN : version.trim();
    }
}
