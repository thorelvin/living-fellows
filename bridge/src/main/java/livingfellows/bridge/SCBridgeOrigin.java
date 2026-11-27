// SPDX-License-Identifier: MIT
package livingfellows.bridge;

import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
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
            Path location = Path.of(source.getLocation().toURI());
            return classify(location.toString(), Files.isRegularFile(location.resolveSibling("projectzomboid.jar")));
        } catch (RuntimeException | URISyntaxException failure) {
            return UNKNOWN;
        }
    }

    static String classify(String path, boolean besideGameJar) {
        if (path == null || path.isBlank()) return UNKNOWN;
        String lower = path.replace('\\', '/').toLowerCase(Locale.ROOT);
        if (lower.endsWith("/media/java/livingfellowsbridge.jar")) {
            if (lower.contains("/steamapps/workshop/content/")) return WORKSHOP;
            if (lower.contains("/zomboid/workshop/")) return STAGING;
            return MODS;
        }
        String name = lower.substring(lower.lastIndexOf('/') + 1);
        return besideGameJar && name.equals("livingfellowsbridge.jar") ? LAUNCHER : UNKNOWN;
    }

    static String release() {
        Package source = SCBridgeOrigin.class.getPackage();
        String version = source == null ? null : source.getImplementationVersion();
        return version == null || version.isBlank() ? UNKNOWN : version.trim();
    }
}
