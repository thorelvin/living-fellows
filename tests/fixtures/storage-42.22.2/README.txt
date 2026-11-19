Storage purpose contracts for native Project Zomboid 42.22.2
=========================================================

SCStorageCategoryCases.lua contains 838 explicit expected destinations and the
native runtime category, display category and typed tags observed for each item.
cases-review.json records the same data with the policy behind each expectation.
These are shelf-purpose contracts, not expected combat/loadout classifications.
Thirteen cases are also physical representatives for the native sorting test.

Metadata was captured with instanceItem/getAllItems in an isolated native PZO
V2.2 game running LF 0.27.40 (0951a9fe). The observed runtime is pinned by
tests/core/pz-runtime.json. No game assets or executable code are included here.
Expected purposes were assigned from native metadata and the storage policy:
medical equipment in Medical; work equipment in Tools; maps in Literature;
water vessels in Water; usable bags in Clothes; gun parts in Weapons; building
supplies in Construction; raw components and ordinary household stock in Crafting.
Runtime clothing and dedicated farm equipment retain their specific purposes.
Food/fresh-food representatives retain the existing spoilage-based policy.
This fixture does not assert a new rule for every mod item or every native type.

loadout-roles-02740.txt separately captures all 5,100 native loadout roles from
that baseline. The native probe compares every role, allowing only the intended
Base.Garbagebag change from trash to container. Storage changes must not silently
rewrite which items a companion considers combat or personal equipment.

tests/essential/storage_categories_harness.lua uses native-shaped models and
these concrete expectations to check classification, floor intake, car unloading,
logistics deposits, ordinary sorting and stable valid placements. It also checks
unknown mod items, dual-use hand tools, capacity and deposit permissions.

scripts/Test-PzoStorageCategories.ps1 checks the real native catalogue against
these contracts and the baseline roles, then exercises real registered crate
destinations and physical sorting under the actual PZO loader. The baseline
negative stages the two 0.27.40 classifiers and must fail on Base.TireIron.
See tests/live/pzo_startup/README.txt for prerequisites and execution.
