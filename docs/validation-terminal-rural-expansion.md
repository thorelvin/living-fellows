<!-- SPDX-License-Identifier: MIT -->

# Local businesses, staff archives and outbreak fragments

27 October 2026, source follow-up to `36259bff` on
`living_fellows/0.26.72`.

This pass adds six transparent headers: Al's Auto Shop, Stuart & Log,
Darkwallow Lake Guest House, A-1 Hay, Guns Unlimited and Golden Sunset Nursing
Home. The catalogue now has 212 distinct identities: 196 named marks and 16
camp or sector emblems. Stock flyers supply the business names and visual
references. These are terminal adaptations, not a claim that the generated
art is an additional stock asset.

Each new header has an original four-entry staff story. Six matching stories
also cover the previous public-service batch: Meade County Police, West Point
Town Hall, Hobbs & Perkins, Ovo Farms, Lenny's Car Repair and Ekron Community
College. Twelve new owners add 48 personal entries, bringing the total to 516
entries across 129 owners. Existing saved owner IDs remain valid; already-used
computers do not receive a different owner's history.

The new accounts concern missing deliveries, evidence kept outside an official
report, an admissions register, care-home transfers and a guest house's second
list of guests. Their writers do not establish an infection origin. They are
original mod fiction, not canonical staff biographies. Twelve business
references and four dated, explicitly unverified fragments bring the county
and EMMA collection to 120 files. Outbreak fragments now contains 16 files;
the eight categories and 24 added conversation subjects are retained.

Golden Sunset receives clinic files and a sand screen; A-1 Hay also uses sand.
Al's, Stuart & Log and Darkwallow use aqua, and Guns Unlimited uses green.
Rare purple still takes priority. All selected PNGs have transparent margins,
and their copied bytes match their generated source. The art manifest records
prompts, identity references, source hashes and read-only alpha measurements.
No pixel-processing step or additional background-removal key is applied.

The six advert keys are checked against the installed 42.21.0
`PrintMediaDefinitions.MiscDetails`. Headless fixtures cover site boundaries,
neighbour exclusion, archive kind, exact firm selection, crop metadata and
theme selection. Hotel guest bedrooms retain the existing accommodation
exception; ordinary private bedrooms do not borrow a business identity.

Parser checks exposed two problems fixed in this pass. Recognised directory
words are no longer spell-corrected into unrelated command words: County must
not become count. An exact complete reference title takes priority over a
shorter companion name inside it, so Lenny's Car Repair remains a business
when a companion named Lenny is present. Short personal queries, actual item
counts and inventory follow-ups retain their existing paths.

## Verification

The focused suites pass: 12,224 brain/world checks, 6,115 security/archive
checks, 1,849 lore/branding checks and 2,925 knowledge checks. The complete UI
suite passes, including all 120 reference files through numbered category
menus at full and narrow viewport sizes. Source/alpha audits pass for all 18
community headers and 17 specific stock advert keys. Whole-mall advertising
remains excluded.

Native preview fixtures reopen a real powered computer in the existing private
clone with each header, its palette and matching owner files. These verify
rendering; site assignment is tested separately by the headless fixtures.
Native acceptance passes for all 18 community headers at 1280x720, with
matching firm-specific owners and all five personal-file shortcuts visible.
The six new headers were visually inspected against their glass and text
palettes. The run also passes typed access to all twelve business references
and four new fragments, date refusal, related-file follow-ups, live inventory
intent, original-owner retention and no secondary player slot.
The dated native catalogue contains 117 available files in eight categories;
the three later reports stay hidden at the clone's current date.
The full project gate passes all 29 stages, including Workshop and standalone
packaging, the installer transaction matrix, Lua compilation in normal and
debug modes, and the existing combat, perception and persistence regressions.

The first combined run exhausted host resources: the project gate reached
26/29 stages, with disk-space failures in packaging/installer copies; the
native JVM reported an allocation failure during loading. A second native
attempt also hit the host's commit limit. Those results are not counted as
acceptance. The full gate passed on a separate run; the final native run
passed with four active JVM processors. Its launcher retained the stock
3 GiB maximum heap despite the requested environment override. No game
settings, player saves or unrelated files were changed to free resources.

The native bridge remains byte-identical at SHA256
`26b1c9eafafcbdbf8c7f772cb6ffcabebf6d9dfc997bbf2c653c54d4528a7de8`,
protocol `42.21-isocompanion-24`. No save schema, network access, confirmed
action or expedition behaviour changes in this pass. Local installation is
separate.

- [Focused suites](../artifacts/emma/native-acceptance/terminal-rural-focused.log)
- [UI suite](../artifacts/emma/native-acceptance/terminal-rural-ui.log)
- [Full project gate](../artifacts/emma/native-acceptance/terminal-rural-project-gate.log)
- [Native acceptance](../artifacts/emma/native-acceptance/terminal-rural-evidence.log)
- [Al's Auto Shop: aqua](../artifacts/emma/native-acceptance/emma-knowledge-logo-AlsAutoShop.png)
- [Stuart & Log: aqua](../artifacts/emma/native-acceptance/emma-knowledge-logo-StuartAndLog.png)
- [Darkwallow: aqua](../artifacts/emma/native-acceptance/emma-knowledge-logo-DarkwallowGuestHouse.png)
- [A-1 Hay: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-A1Hay.png)
- [Guns Unlimited: green](../artifacts/emma/native-acceptance/emma-knowledge-logo-GunsUnlimited.png)
- [Golden Sunset: sand](../artifacts/emma/native-acceptance/emma-knowledge-logo-GoldenSunset.png)
- [New outbreak fragment](../artifacts/emma/native-acceptance/emma-knowledge-rural-files.png)
- [Art and source manifest](terminal-community-art-manifest.json)
