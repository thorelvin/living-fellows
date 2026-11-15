# EMMA chat follow-up, 0.27.22

User handoff: `C:\ZOMBOID\codex-handoff-0.27.22-emma-chat-fixes.md`.
Worktree `C:\ZOMBOID\work\r2722`, branch `living_fellows/0.27.22`, starts at
`61981815`. Tested practical rest/visitor repairs and the parked-car follow fix
are carried forward. The separate 0.27.21 live fixture change is not modified
here. The local installed 0.27.21 copy includes the car fix; its live retest is
pending because the user cannot test now.

## Development evidence

| Handoff fix | State | Native evidence |
| --- | --- | --- |
| F1: selected-context loop | Implemented | Before: strict exit 1, `harness-20261115-190728-cf752c`; after: strict exit 0, `harness-20261115-191052-dad936` |
| F2–F10 | Pending | No completion claimed |

Evidence roots are under `build/emma-talk-polish`. F1 adds a source-origin
deadline, requires overlap/anaphoric continuation, gives strong own questions
and social turns their own routing, and rejects a consecutive selection repeat.
Its current 23 public cases cover all four voices. The existing context harness
also passes with 286 checks.

Every development run includes the wired synthetic care harness: **575/575**
detections across the canonical opened corpus, **88 negative controls**, zero
false care, and private response priority on all four voices. Care implementation
and data are not edited. No care input or private reply body is emitted by that
harness. The full existing corpus gate remains wired and is still required.

These are development receipts, not fresh blind evidence. Remaining work:
implement and prove F2–F10; replay the public session; preserve the cumulative
non-regression floor; run the full release gate; bump release metadata; build and
check the local playground. Do not publish the playground.
