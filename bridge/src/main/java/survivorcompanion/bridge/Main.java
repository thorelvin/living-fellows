// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

/** Conventional Java-mod entry point for loaders such as ZombieBuddy. */
public final class Main {
    private Main() {}

    public static void main(String[] arguments) {
        SCBootstrap.start();
    }
}
