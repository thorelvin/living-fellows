// SPDX-License-Identifier: MIT
package se.krka.kahlua.vm;

/** Compile-only surface for the version-pinned Kahlua table API. */
public interface KahluaTable {
    Object rawget(Object key);
    void rawset(Object key, Object value);
    void rawset(int key, Object value);
    void wipe();
}
