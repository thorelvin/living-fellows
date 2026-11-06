// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;

/** One actor's single-use permission, issued immediately before a checked action. */
final class SCWindowActionGuard {
    private static final long LIFETIME_NANOS = 500_000_000L;
    private IsoObject approved, blocked;
    private IsoGridSquare source;
    private String operation, blockedOperation = "";
    private long expires;

    boolean approve(IsoObject object, String action, IsoGridSquare from, long now) {
        clear();
        if (object == null || from == null || !("climb".equals(action) || "smash".equals(action))) return false;
        approved = object;
        source = from;
        operation = action;
        expires = now + LIFETIME_NANOS;
        return true;
    }

    boolean consume(IsoObject object, String action, IsoGridSquare from, long now) {
        boolean accepted = approved == object && object != null && source == from
                && action.equals(operation) && now - expires < 0L;
        clear();
        if (!accepted) { blocked = object; blockedOperation = action; }
        return accepted;
    }

    IsoObject blocked() { return blocked; }
    String blockedOperation() { return blockedOperation; }
    void clear() { approved = null; source = null; operation = null; expires = 0; blocked = null; blockedOperation = ""; }
}
