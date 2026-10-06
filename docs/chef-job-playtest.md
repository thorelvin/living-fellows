# Chef job playtest

Assign a companion **Chef** in the base job selector. The Chef works while on base duty. Stock cooking pauses when there is no powered camp fridge, and resumes when one becomes available. The stock target is one safe prepared dish per on-duty resident.

For the first test, put a bowl and fresh salad ingredient, or bread slices and a safe sandwich filling, in marked Food/Tools storage or another loaded camp container. The Chef uses marked storage first and respects its withdrawal reserve. A cooked dish goes to a marked Food fridge first, then to another powered camp fridge.

For soup, provide a pot, two bowls, clean water from a reachable sink, and either a powered oven or an already lit campfire. The Chef fills the pot, cooks through the game's heat system, divides the soup into two bowls with the native handcraft recipe, and returns the empty pot to camp storage. It does not light or refuel campfires.

Four additional dishes use Build 42's native evolved recipes: **fish soup**, **fish stew**, **venison stew**, and a **venison sandwich**. Put fish fillets or venison in camp Food storage. The three pot dishes accept raw meat, but must finish cooking before the Chef serves or stores them; stews are divided into two bowls and the pot is returned just like soup. The automatic job rotates through available dishes and skips a named dish when its required meat or equipment is missing.

Two everyday dishes extend the rotation: **stir fry** and **pasta**. Stir fry needs a frying pan, a suitable vegetable or other native stir fry ingredient, and a heat source. The cooked meal stays in its pan until eaten; Project Zomboid returns the pan when the food is consumed. Pasta needs dry pasta, a pot that holds at least 1.5 L of clean water, two bowls, a suitable native pasta topping, and a heat source. The Chef uses the game's `PlacePastaInCookingPot2` recipe, then the evolved `PastaPot` recipe, cooks the result, divides it into bowls with `Make2Bowls`, and returns the empty pot. In both cases the Chef stores only food confirmed cooked and safe.

Ingredient audit against Build 42's loot tables and recipes:

| Ingredient | Source and Chef preparation |
| --- | --- |
| Fresh salad filling | Scavenged vegetables or other safe native salad ingredients. |
| Whole bread / bread slices | Whole bread appears in bakery and kitchen loot. Loose slices are rare. With a loaf and a knife, the Chef uses native `SliceBread` to make three slices, uses one, and keeps the others for later meals. |
| Fish fillet | Scavenged from fish shops and food storage. If companions bring home a whole fish, the Chef uses native `SliceFillet` with a sharp knife to make two fillets, then cooks one in soup or stew. |
| Venison | Scavenged from hunter and farm freezer loot. The Chef cooks raw venison in stew, or cooks it separately before using it in a sandwich. |
| Bowl, pot, knife | Scavenged kitchen equipment. Two bowls, a pot, clean water, and a heat source are needed for pot meals. A knife is needed to slice a loaf. |
| Stir fry supplies | Frying pan and a suitable native ingredient such as a scavenged or farmed vegetable. |
| Pasta supplies | Dry pasta appears in grocery and kitchen distributions. A pot, 1.5 L clean water, two bowls, and a native pasta topping are required. |

The Chef will not use rotten, burnt, or poisoned food. When the only suitable fish fillet or venison is frozen, the Chef carries one piece out of storage and waits for the game to thaw it before preparing the dish. The Chef keeps a borrowed slicing knife and spare bread slices or fish fillets in their inventory so they remain available for another meal.

Right-click a Chef on base duty and choose **Cook me a meal** for a one-time order. The Chef gives the safe finished dish to the player when the player is inside camp and reachable. If the player leaves, the Chef keeps the dish until they return. The one-time order also works without a fridge for salad and sandwich; soup requires a fridge.

The controller records exact items around the native recipe action. On reload it recognizes a tagged finished dish. If the native result cannot be proven, it blocks the job instead of consuming new ingredients. Canceling a Chef job returns its borrowed supplies; an active native or hot cooking action must finish first. After a reload, cancellation waits for a job with missing source receipts to recover rather than discard its carried supplies. The Chef approaches a camp crafting table for handcraft steps and checks carry capacity before starting them; Build 42 drops crafted output on the floor when the character is overloaded.

Automated coverage: `tests/gameplay/run_gameplay_tests.ps1` includes the Chef controller harness for safe stock, power gating, one-time order deduplication, exact sourcing, native completion, cancellation, reload receipts, all four meat dishes, stir fry, pasta preparation and two-bowl delivery, native bread and fish slicing, thawing frozen fish and venison, and cooking venison before sandwich assembly. The focused client probe `scripts/Invoke-LiveSandboxTests.ps1 -LivingFellowsOnly -ChefRecipesProbe` passed in the isolated cloned save (run `SC-Harness-20261005-191056-6a782a77`, 26 passes, zero failures): Build 42 rejected ramen as a salad filling, accepted a transient pasta base for topping selection, and completed potato stir fry, dry-pasta pot preparation, tomato pasta, and two-bowl division with the pot returned. The probe marked dishes cooked to test Chef stock checks; actual oven/campfire timing, Chef navigation to a table, and final fridge delivery still need an in-game Chef playtest.
