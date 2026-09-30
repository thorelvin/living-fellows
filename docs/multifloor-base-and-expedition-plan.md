# Multifloor base work and expedition scavenging

## Existing pieces

- Camp zones already store a floor (`z`). Work and production targets retain it.
- Navigation already gives cross-floor destinations to Project Zomboid's native stair pathfinder. The local planar pathfinder should not invent stair edges.
- Expedition places already know a building's floor range from map metadata, and the search action already uses Navigation to approach a container.

## Missing links

1. The base context menu only offers a new camp area from a square already inside a camp area. An upstairs square cannot pass that test until the area exists.
2. Camp-only work rejects every cross-floor request, even between two designated floors of the same building.
3. Expedition loot search reads loaded squares only at the companion's current `z`; site membership accepts only `z=0`. Upper-floor containers can never be selected.

## Implementation

1. Offer an area-zone start on an upper or lower floor when the clicked square projects into an existing camp area and both floors belong to the same map building. Preserve the current same-floor two-corner drawing workflow. The player explicitly marks each work floor, including stair access.
2. Permit camp-only native stair routes when both endpoints are in designated camp areas and in the same building. During a native route, stop if the actor leaves the admitted camp area. Keep corpse dragging blocked across floors.
3. Read the selected building's bounded floor range from the metagrid. Validate every loot source against the selected building at its actual floor. Interleave loaded-square searches across those floors under the existing scan budget; the current container approach then owns movement through stairs. Other scavenging remains local to the actor's floor.
4. Keep exterior expedition travel on ground level. Return movement uses the same existing navigation and stair handling when search has moved the leader upstairs.

## Verification

- Fixture: upstairs area can be offered over an existing area, but another building cannot be claimed through this shortcut.
- Navigation: same-building cross-floor work starts a native path; a route leaving admitted areas stops; dragging a body remains blocked.
- Expedition: upstairs source membership and loot selection work, while neighboring buildings and floors outside the site's range fail.
- One controlled live two-floor house run should verify a companion actually ascends, loots, returns, and does not strand followers. Game timing and animation stalls are a separate performance investigation.
