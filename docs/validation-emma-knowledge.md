<!-- SPDX-License-Identifier: MIT -->

# EMMA conversation, local-reference and business expansion

27 October 2026, continuation of `living_fellows/0.26.72` after `170f2312`.
Lua-only changes; native bridge and save schemas are unchanged.

## Scope

- 88 new original reference files: 68 setting topics, eight station-help files
  and twelve unverified outbreak fragments. Combined with the original 16,
  the reference archive has 104 files. Thirty-two new owners add 128 personal
  entries, for 117 owners and 468 entries.
  All 85 published owner identities and their files remain available unchanged.
- Twenty-four new conversation subjects, plus additional jokes, poems, stories,
  identity/feeling replies and fallbacks. Replies do not infer actual injuries,
  current supplies or remote contacts from fiction or small talk.
- Bounded topic matching, conservative one-edit corrections, explicit related
  follow-ups and calendar access checks. The normalised clock uses the game's
  zero-based month. Missing/invalid clocks fail closed. Future titles are not
  listed and direct file selection rechecks its date.
- Category menus use measured wrapped labels. Short views reduce the page
  size and cycle through More/First files. Transcript caching includes the
  actual column count so changing focus cannot paint wide text over a sidebar.
  Archive paragraphs remain intact until display wrapping, preventing ragged
  short fragments when switching between menu and chat widths.
- Lore remains available outside camp; camp records do not. Inventory counts,
  actual companion names, explicit requests and confirmation paths keep their
  existing precedence. Static references cannot issue orders or supply a fresh
  expedition report.
- Six generated transparent headers adapt the installed stock flyers for
  Twiggy's, West Point DIY, The Wizard's Keep, Taco del Pancho, Muldraugh
  Police and Rosewood Fire. Five new identities use specific native advert
  rectangles; Taco's whole-mall rectangle remains excluded. This is original
  local-story fiction using game business identities, not newly discovered
  canonical staff or proof that those premises are occupied in a running save.
- The darker pass adds 64 personal entries and twelve fragments in an eighth
  category. Original stories use administrative satire, restrained crime
  writing and unresolved horror: altered reports, missing passengers, payroll
  anomalies and compromised witnesses. Supernatural readings remain unverified;
  the prose establishes no new canonical infection cause, medical conclusion,
  quest target, actual missing LF actor or live camp event.

## Research

The installed 42.21.0 `media/radio/RadioData.xml` and English `RadioData.json`
verify broadcaster names, frequencies and report material. English
`Print_Media.json` supplies dated newspaper context. The stock
`media/lua/server/radio/ISDynamicRadio.lua` assigns the automated emergency
channel a world-specific frequency, so EMMA does not invent one fixed AEBS
frequency. Stock channel frequencies are directory entries, not claims of
current reception. Game content is paraphrased in original prose; the game
files themselves are not redistributed.

The Indie Stone dates the event to 6 July 1993 in
[Knox Event: 30 Years On](https://projectzomboid.com/blog/news/2023/07/knox-event-30-years-on/).
Its [Spiffo article](https://projectzomboid.com/blog/news/2026/08/show-your-spiffos-pride-and-help-us-fundraise/)
also confirms the restaurant mascot. Neither supplies a definitive origin for
the infection. The expansion does not attribute one to burgers, smells or a
restricted facility, and does not substitute real-world presidential history
for the game's unnamed President.

Source hashes and matching translation IDs, without copied broadcasts:
[knowledge-sources.json](../artifacts/emma/research/knowledge-sources.json).
The follow-up uses installed stock flyers and `PrintMediaDefinitions` for
business identities and specific premises. The official
[Build 42 overview](https://projectzomboid.com/blog/features-overview-build-42-20/)
also identifies the western towns and expanded printed world storytelling.
[community-sources.json](../artifacts/emma/research/community-sources.json)
records the inspected source hashes and the excluded whole-mall advert.
[Artwork and prompts](terminal-community-art-manifest.json) record all six
built-in imagegen outputs, refinements, file hashes, transparency and bounds.
`audit_community_art.py` verifies real alpha, transparent margins and byte-for-byte
copies of the selected generated files; it does not rewrite image pixels.

## Verification

The focused knowledge harness exercises every new alias in three phrasings,
all new conversation questions, typos, related-file exhaustion, calendar and
missing-clock checks, item/brand ambiguity, local-vs-remote threat scope,
outside-camp access and read-only replies. The UI suite traverses every category
and reference, checks number-key access and reading anchors, and measures
choices at 1280x720, 1920x1080, 2560x1440, 640x720 and 960x540. A focus-width
regression reproduces the native sidebar transition.

Native checks reuse an existing disposable cloned world, without reading or
writing the player's current save. They use the map office PC, actual terminal
input and real framebuffer captures: conversation, dated category listing,
keyboard access to the Muldraugh file, direct future-record refusal, related
follow-up and a live inventory query. The actual cloned save had 101 dated files
available and eight categories; the three later incident reports remained
hidden. Six further captures use the actual terminal window and native renderer
with explicit header/owner presentation fixtures on that cloned computer.
Each computer is reopened so the text, glass, input and header use the same
palette. These captures verify presentation, not naturally encountered brand
assignment. Specific-premises assignment, mall exclusion, private upstairs
rooms and matching owner selection are checked headlessly. No player slot
was acquired by reading or browsing.

The final full project gate passed **29/29 stages**, including normal and debug
compilation of all 237 Lua files, gameplay/UI regressions, installer transactions
and Workshop/standalone packages.

The subsequent font/menu follow-up reduces text from 32 to 28 pixels at 720p,
44 to 40 at 1080p and 88 to 80 at 4K, while retaining the native font minimum.
Menu layout uses spare space between measured choices before scrolling any
choice away. The complete UI suite passes, with new checks for all five home
shortcuts in both menu and chat focus at six viewport sizes, including 960x540.
A fresh native 1280x720 run confirms all five shortcuts, without clipping or
overlap, and repeats the conversation, archive and six-logo checks. The captures
below include the outbreak expansion. Focused checks include 2,492 knowledge
assertions, 1,584 lore/branding assertions, all 101 preceding owner IDs through
normalization, and the expanded 468-entry collection. Each fragment retains an
unverified source label, remains unavailable before its date and uses read-only
replies. The native probe also opens the new category and a note by number,
then checks a typed fragment alias without replacing the saved owner. Existing
singing replies retain their original intent. Literal U-Store It names are
recognized before chat shorthand expands U to 'you'; live stock questions
retain their existing precedence.

- [Full gate](../artifacts/emma/native-acceptance/knowledge-project-gate.log)
- [Native checks](../artifacts/emma/native-acceptance/terminal-knowledge-evidence.log)
- [Conversation](../artifacts/emma/native-acceptance/emma-knowledge-conversation.png)
- [Categories](../artifacts/emma/native-acceptance/emma-knowledge-categories.png)
- [Reflowed town file](../artifacts/emma/native-acceptance/emma-knowledge-town.png)
- [Outbreak fragment](../artifacts/emma/native-acceptance/emma-knowledge-outbreak.png)
- [Twiggy's: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-Twiggys.png)
- [West Point DIY: aqua](../artifacts/emma/native-acceptance/emma-knowledge-logo-WestPointDIY.png)
- [Wizard's Keep: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-WizardsKeep.png)
- [Taco del Pancho: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-TacoDelPancho.png)
- [Muldraugh Police: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-MuldraughPolice.png)
- [Rosewood Fire: aqua](../artifacts/emma/native-acceptance/emma-knowledge-logo-RosewoodFire.png)

This run does not revalidate the separate expedition return/lighting and
parking issues. Local installation is separate from this source-validation pass.
