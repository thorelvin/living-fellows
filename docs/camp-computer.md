<!-- SPDX-License-Identifier: MIT -->

# The camp computer: EMMA

Every desktop computer in Knox Country still has EMMA on it: the Emergency
Management Assistant, an unfinished civil defense program the state installed
shortly before there was no state. She answers plain English at a green
terminal. She is calm, precise and not especially kind about it.

There is no network and no outside service. EMMA is a small offline parser
with short-term context, and every fact she gives you comes from the save.

## Using a computer

Right-click a desktop computer and choose **Use computer**. Your character
walks over, faces the screen and the terminal opens. The computer needs power:
a generator in range, or grid power inside a building while the grid still
runs. An unpowered computer shows the option greyed out, with the reason.

- Type a question and press **Enter**. EMMA thinks for a moment, then types.
- **Enter** while she is still typing skips to the end of her reply.
- **Up** and **Down** recall earlier lines. **Page Up**, **Page Down** and the
  mouse wheel scroll back.
- Type `clear` to wipe the screen, and `exit` or press **Esc** to leave.

The terminal closes if you walk away. If the power fails, the screen shows the
failure and goes dark.

## What she can tell you

| Ask something like | She answers with |
| --- | --- |
| `status` | One camp report: people, work, food, power, weather and movement |
| `who is here`, `where is Kate` | Your recruited companions, what they are doing and where, by distance and compass direction from the terminal |
| `who is hurt`, `how is Kate` | Health, bleeding, stress and spirits. Expedition members are reported as away |
| `how many nails`, `any ammo left` | Counts across marked camp storage, with which containers hold them |
| `how much food` | Food items, total calories and roughly how many days they last for the people at camp |
| `what is everyone doing`, `any problems` | Work in progress, waiting and blocked, with blocked reasons |
| `power`, `weather`, `time` | Generator fuel and condition, outside temperature and sky, game date and day count |
| `any zombies` | Movement within 40 meters of the terminal, nearest distance and direction |
| `expedition` | The away team's leader, members and last reported progress |
| `advice` | The most urgent thing she can see, in order: bleeding, low health, low generator fuel, a crowd outside, blocked work, low food, night |
| `remember the key is in the van` | Saves a note. `what did i tell you` reads notes back; `forget everything` erases them |

She tolerates typos, follows up on the last question (`and screws?`,
`is she hurt?`, `and now?`), and asks "Did you mean ...?" when she is unsure;
answer `yes` or `no`. She also does arithmetic, small talk, jokes and poems,
and has opinions about being insulted.

## Rules

- **Storage and work need the camp network.** Questions about storage, food
  and jobs need the computer inside your marked camp. Outside it, EMMA still
  answers about your people, power, weather, time and movement, and tells you
  to carry her inside. A desktop computer is a movable object.
- **Bounded reads.** Every answer reads the world once, when you ask. Storage
  counting stops at 40 containers, 600 items each and 4,000 in total, and
  EMMA says when a count may be incomplete (for example, an unloaded
  container). The zombie count scans at most 2,000 entries.
- **Memory.** Each computer keeps its own small memory in the save: the name
  you gave with `call me ...`, up to eight notes of 80 characters, and when
  you last visited. Damaged or oversized memory is cleaned up or ignored on
  read.
- **Single-player keyboard player only**, like the rest of the mod.

## Playtest

In a cloned save with a marked camp, a generator and a desktop computer:

1. Right-click the computer with the generator off. **Use computer** should be
   greyed out with the no-power reason. Turn the generator on and use it. The
   character should walk over and face the screen; the boot screen types out.
2. Ask `how many nails`, then `and screws?`, then `how many of them`. Compare
   the counts with the shelves.
3. Ask `who is hurt` and `how is <name>` for a companion. Wound a companion
   and ask again.
4. Ask `status`, `power`, `weather`, `time` and `any zombies`. Check the
   generator fuel against its own panel.
5. Type `call me <name>` and `remember <something>`, leave with `exit`, save
   and reload, and use the same computer. EMMA should greet you by name, say
   how long you were gone and read the note back with `what did i tell you`.
6. Use a computer outside the camp. Storage questions should be refused with
   the camp-network line; people questions should still work.
7. Walk away mid-reply, and separately turn the generator off while the
   terminal is open. The first closes at once; the second shows
   `*** POWER FAILURE ***` before closing.

The `terminal` gameplay harness covers the intents, typo tolerance, context,
every answer against fixtures, memory normalization, fuzzed input and the live
world adapter against fake game objects. The UI tests cover the menu entry,
the walk-and-sit action, the boot screen, typing, history, clear, exit,
walking away, power loss and memory across sessions.
