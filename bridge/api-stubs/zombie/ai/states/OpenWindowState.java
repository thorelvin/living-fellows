// SPDX-License-Identifier: MIT
package zombie.ai.states;

import zombie.ai.State;
import zombie.iso.objects.IsoWindow;

public final class OpenWindowState extends State {
    public static final State.Param<IsoWindow> WINDOW = new State.Param<>();
    public static OpenWindowState instance() { return null; }
}
