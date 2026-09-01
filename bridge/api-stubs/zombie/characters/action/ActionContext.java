// SPDX-License-Identifier: MIT
package zombie.characters.action;

/** Compile-only Build 42 action-context surface used by the native bridge. */
public final class ActionContext {
    public ActionGroup getGroup() { return null; }
    public String getCurrentStateName() { return ""; }
    public ActionState peekNextState() { return null; }
    public boolean canTransitionToState(String name) { return false; }
}
