// SPDX-License-Identifier: MIT
package zombie;

/** Compile-only path resolver for game and mod map data. */
public class ZomboidFileSystem {
    public static final ZomboidFileSystem instance = new ZomboidFileSystem();
    public String getString(String relativePath) { return relativePath; }
}
