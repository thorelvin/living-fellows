-- SPDX-License-Identifier: MIT
-- Authored summaries checked against the installed Project Zomboid 42.22.2.
-- Paths below are relative to the game's media directory; no game files ship.
LivingFellows=LivingFellows or {}
local D={} LivingFellows.EmmaReferenceData=D
local function topic(id,title,aliases,source,facets,exact)
    D[#D+1]={id=id,title=title,aliases=aliases,source=source,facets=facets,exact=exact or {}}
end
topic("trapping","Traps and small animals",{"trap","traps","trapping","snare","snares","cage","rabbit","rabbits","squirrel","mouse trap"},
    "scripts/generated/recipes/recipes_trapping.txt; lua/server/Traps/TrapDefinition.lua; lua/server/Traps/ISUI/ISTrapMenu.lua; lua/shared/Translate/EN/Recipes.json",{
    what="A baited trap catches small animals. The trap, bait, habitat and animal's active hours all matter. A cage is a proposal, not a food delivery.",
    make="A wooden crate trap needs planks, nails, a saw and a hammer, plus knowledge of its recipe. A stick trap uses sticks and twine.",
    use="Place the trap in suitable habitat, add bait the animal eats, leave it quiet and check it later. Rabbits favour vegetable bait; birds use different traps and bait.",
    find="Look for trapping knowledge in magazines and for tools in sheds or workshops. Woodland is useful habitat, but a tree does not guarantee a rabbit.",
    why="Trapping can add food without chasing every meal. Keep a second food source while you wait.",
    dangers="An empty trap proves no catch, not that you chose the right bait. Check bait and the trap's condition. Do not let the checking route become more dangerous than the meal is worth.",
    catch="Box, crate, cage and snare traps can catch rabbits or squirrels. Stick traps catch birds; mouse traps catch mice and rats. Match the bait and habitat to the animal."},
    {make="Game survival reference: Make Crate Trap uses three planks and five nails, with a saw and hammer kept as tools. Make Stick Trap uses four sturdy sticks and one twine. Check the learned-recipe requirements in Crafting.",
     use="Game survival reference: use the trap item's placement option, then the placed trap's context menu to add bait and check for an animal. This reference does not place or check a trap for you."})
topic("firearms","Firearms and ammunition",{"gun","guns","firearm","firearms","pistol","revolver","rifle","shotgun","ammo","ammunition","bullet","bullets","shell","shells","reloading"},
    "scripts/generated/items/weapon.txt; lua/shared/TimedActions/ISReloadWeaponAction.lua; lua/shared/Translate/EN/SurvivalGuide.json; lua/shared/Translate/EN/ItemName.json",{
    what="A firearm is a loud weapon that needs ammunition matched to that gun. Shotguns use shotgun shells; pistols and rifles do not all share a cartridge.",
    make="Start with a sound firearm and the correct ammunition. I have no verified manufacturing recipe for the particular gun you mean; inspect a learned recipe before committing supplies.",
    use="Check the chamber, magazine and ammunition before trouble. Leave room to reload and a way to withdraw. A gun solves a nearby problem loudly enough to invite another.",
    find="Police stations, gun shops and some homes are possible places to look for guns or ammunition. Those are search leads, not a claim that a shelf is stocked or a route is safe.",
    why="A firearm gives distance. Melee weapons conserve ammunition and usually draw less attention. Choose an escape plan before choosing the impressive noise.",
    dangers="Gunfire attracts attention. Panic, tiredness and a crowd at arm's length are poor conditions for learning. Never assume a different model uses the same magazine or ammunition.",
    noise="Yes, gunfire is loud and can attract zombies. A quiet route around the fight is often cheaper than the ammunition."},
    {use="Game survival reference: inspect the firearm for its ammo and magazine type. Load compatible ammunition into a detachable magazine when required, insert it, and use the weapon's reload/rack options as needed. The M9 takes 9mm, the M1911 .45, and the B-F pistol .44. The standard shotguns take shotgun shells."})
topic("fishing","Fishing",{"fishing","fish","fishing rod","bait","lure","fishing line"},
    "lua/shared/Fishing/FishingRod.lua; lua/shared/Fishing/fishing_properties.lua; scripts/generated/recipes/recipes_fishing.txt",{
    what="Fishing uses a rod with suitable line, hook or lure, and bait where needed, to turn time at the water into a possible meal. The water has not signed a guarantee.",
    make="A fishing rod needs compatible line and a hook or lure. The rod and its rig must be usable before you set out.",
    use="Choose accessible water, prepare the rod and rig, then fish from somewhere you can leave safely. Bring spare equipment and enough food to survive a poor catch.",
    find="Look for rods and tackle among fishing and sporting supplies. Suitable water still needs a safe bank and a route home.",
    why="A catch adds fresh food while shops become less useful. Fresh fish still need sensible cooking or preservation.",
    dangers="Do not stare at a float while the dead walk up behind you. Damaged tackle and bad conditions can waste time without producing a fish."},
    {use="Game survival reference: use the fishing rod's equipment options to fit compatible line and a hook/lure, with bait where required. Use the fishing interaction at the water. Check the current fishing panel rather than assuming an old-build spear instruction applies."})
topic("foraging","Foraging",{"forage","foraging","berries","mushroom","mushrooms","wild food","search mode","investigate area"},
    "lua/shared/Translate/EN/SurvivalGuide.json; lua/shared/Foraging/forageSystem.lua",{
    what="Foraging means looking carefully for useful things in the landscape: food, stones, plants and other small finds.",
    make="You do not manufacture a patch of woodland. Learn what you are looking for and carry room for what you can identify.",
    use="Search slowly in a suitable area and pay attention to what you actually find. Unknown berries and mushrooms are not improved by optimism.",
    find="Different landscapes, seasons and conditions offer different finds. The area information helps; it does not promise a particular item.",
    why="Small finds can replace a missing ingredient or supplement food. They are useful precisely because you cannot order them from a shelf.",
    dangers="Some wild foods are poisonous. Poor light and weather limit what you can see. Stay alert to people and zombies while searching the ground."},
    {use="Game survival reference: open Investigate Area using the spyglass icon and choose Enable Search Mode. Read the area information and inspect each find before taking or eating it."})
topic("dressings","Bandages and dressings",{"bandage","bandages","dressing","dressings","rag","rags","ripped sheets","sheet","sheets","disinfectant","sterilized rag","sterilised rag","bleeding","blood"},
    "lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/recipes/recipes_medical.txt; lua/client/XpSystem/ISUI/ISHealthPanel.lua",{
    what="A bandage or clean rag covers a wound and helps control bleeding. It does not cure a zombie bite or turn a deep wound into an ordinary scratch.",
    make="Rip suitable clean clothing into rags. Use a proper disinfecting method when available. Sheets are bandages waiting for an undignified promotion.",
    use="Find the bleeding wound and apply a clean dressing. Check it again and replace a dirty dressing. Treat any deeper injury according to what it actually is.",
    find="Look for medical dressings in first-aid supplies and suitable cloth among household linens or clothing. Inspect what you take; a dirty rag needs cleaning.",
    why="Blood belongs inside. A dressing buys the wound time to heal; it is not proof that infection or a lodged object has been resolved.",
    dangers="Changing a dressing can expose an unhealed wound to renewed bleeding. Have the clean replacement ready. A disinfected bandage does not prevent Knox infection from a zombie wound.",
    change="Have a clean replacement ready, remove the dirty dressing and apply the replacement to the same wound. Do not discard your only dressing before preparing another."},
    {make="Game survival reference: use the Rip Clothing option on suitable cloth items to obtain rags. The medical recipes include cleaning dirty dressings and disinfecting rags/bandages; check the available water/disinfectant and recipe requirements.",
     use="Game survival reference: open Health, select the injured body part and choose the bandaging option with a suitable dressing in your inventory. Remove a dirty bandage and apply a clean replacement when needed."})
topic("fuel","Gasoline and fuel",{"gasoline","petrol","fuel","gas station","gas pump","pump","siphon","siphoning","gas can","gas canister"},
    "lua/shared/Translate/EN/SurvivalGuide.json; lua/client/Vehicles/ISUI/ISVehiclePartMenu.lua",{
    what="Gasoline is fuel for ordinary cars and portable generators. It is not drinking water, despite both being things you may carry home in a container.",
    make="I have no verified recipe for manufacturing gasoline here. Recover existing fuel instead of guessing at chemistry.",
    use="Keep gasoline in a compatible container and refuel the intended engine while it is stopped. Keep flames away from the work.",
    find="Try a gas station with a powered pump, or siphon a vehicle that actually has fuel. Siphoning needs a suitable hose and a container with room.",
    why="Fuel keeps an engine or generator running. Its value depends on the machine and the work; not every problem deserves another noisy engine.",
    dangers="Gasoline is flammable. A station may be empty, unpowered or crowded. A map symbol is not a current fuel reading."},
    {find="Game survival reference: use a powered pump's fill options with a compatible liquid container. For vehicle siphoning, use the vehicle's Siphon Gasoline option with a suitable hose and container; the tank must actually contain fuel.",
     use="Game survival reference: use the vehicle's fuel interaction or its nearby vehicle menu. For a portable generator, use its refuelling option with compatible gasoline; check the displayed fuel and condition."})
topic("generator","Portable generators",{"generator","generators","genny","generator fumes","generator repair"},
    "lua/client/ISUI/ISGeneratorInfoWindow.lua; lua/shared/TimedActions/ISFixGenerator.lua; lua/shared/TimedActions/ISAddFuel.lua",{
    what="A portable generator burns gasoline to supply nearby electrical equipment. Its fumes belong outdoors, regardless of how convenient the kitchen corner looks.",
    make="I have no verified recipe for building this portable generator from scratch. Find one, learn to operate it and bring fuel.",
    use="Place it outdoors, connect it properly, check fuel and condition, then operate it according to the instructions. Keep the equipment and route to it accessible.",
    find="Garages and storage buildings are possible places to search. I cannot certify one at a particular address from a general file.",
    why="It can keep useful appliances working after the grid fails. A refrigerator's usefulness still depends on how much fuel you can spare.",
    dangers="Running one indoors is dangerous. Poor condition also needs attention. Switch it off before refuelling or repair; do not treat the sound of an engine as proof that everything is well."},
    {use="Game survival reference: use the generator's context options for connection, information, fuel and operation. Check that you have the required operating knowledge. The information panel reports consumption; I cannot infer runtime from a fuel percentage alone."})
topic("tools","Tools and basic crafting",{"tool","tools","hammer","saw","nail","nails","plank","planks","crafting","craft","basic crafting"},
    "lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/recipes/recipes_trapping.txt",{
    what="A tool lets you do a particular job. A hammer, a saw and the materials are separate requirements; enthusiasm is regrettably not a substitute for either.",
    make="Use a recipe you know, with the listed materials, tools and a suitable surface or workstation where required. Start with what you actually possess.",
    use="Check the task before carrying a whole workshop. Keep the needed tool usable and enough space to handle its materials.",
    find="Sheds, garages, workshops and hardware storage are reasonable places to search. They are possibilities, not guaranteed inventories.",
    why="The right tool saves time and turns recovered materials into useful work. A spare nail weighs less than a second trip.",
    dangers="Some tasks need skills or a workstation in addition to the items. Check all requirements before dismantling the thing you still need."},
    {make="Game survival reference: open Crafting and select the recipe. Its requirements show the materials, retained tools, knowledge, skill and surface/station conditions. Building static objects uses the Build menu; a recipe and a construction are different choices."})
topic("clothing","Clothing and repair",{"clothes","clothing","hole","holes","tailoring","patch","patching","needle","thread","repair clothes"},
    "lua/shared/TimedActions/ISRepairClothing.lua; lua/shared/Translate/EN/SurvivalGuide.json",{
    what="Clothing provides warmth and may provide protection. Holes are a poor addition to either feature.",
    make="Use a known tailoring recipe and its materials. Repair work needs a needle, thread and suitable fabric; not every garment can be repaired in every way.",
    use="Inspect the garment and the part you want to patch or reinforce. Match clothing to the weather and keep a dry change when you can.",
    find="Homes and clothing shops are places to look for garments. Sewing supplies and recoverable fabric are separate things to bring home.",
    why="Dry layers help control temperature. A useful patch can extend the life of a garment without making it bite-proof.",
    dangers="A padded sleeve is not a promise against a bite. Excess clothing can also leave you too hot. Check condition and protection rather than trusting the appearance."},
    {use="Game survival reference: inspect the garment, select a body part and use the available patch/padding option. Keep the garment, suitable fabric, needle and thread in your inventory. Skill and material affect the result; some repairs remain unavailable."})
topic("stealth","Sneaking and crowds",{"stealth","sneak","sneaking","horde","hordes","sneaking zombies","noise","quiet","hide","hiding","line of sight"},
    "lua/shared/Translate/EN/SurvivalGuide.json",{
    what="Stealth means giving the dead fewer chances to notice you. It is quieter movement and cover, not invisibility.",
    make="You cannot make a safe route merely by naming one. Watch the ground, entrances and exits, then choose a route that leaves room to turn back.",
    use="Move quietly, use cover and break line of sight before changing direction. Avoid sprinting into an area you have not checked.",
    find="Look for cover and an exit on the route you can actually see. No general file can name a currently safe house for you.",
    why="Avoiding a fight saves endurance, injuries and supplies. With a horde, distance and an exit are more useful than winning the first exchange.",
    dangers="Crouching does not prevent nearby zombies seeing or hearing you. Do not corner yourself, and do not assume a wall has made every observer forget you."},
    {use="Game survival reference: use your bound Crouch/Sneak control and move beside cover. The survival guide warns that crouching still permits detection at close range and uses more endurance than ordinary walking. Use your aim/strafe control to look around carefully."})
topic("loot","Where to search",{"loot","looting","scavenge","scavenging","hardware store","pharmacy","police station","gun shop","warehouse","shed","garage","loot locations"},
    "lua/shared/Translate/EN/SurvivalGuide.json; lua/shared/Translate/EN/Muldraugh, KY.json; lua/server/Items/ProceduralDistributions.lua",{
    what="A search plan connects a need to a plausible kind of building. It does not manufacture the contents of that building.",
    make="Choose the supplies you need, a destination you know and a carrying plan. Leave room for the unexpected and enough strength for the return.",
    use="Check the approach and exits before entering. Search what you can carry safely, then return and store it where the camp permits.",
    find="Try garages or sheds for tools, homes and shops for food, medical premises for dressings, and police or gun shops for firearms. All may be empty or dangerous.",
    why="A specific need makes a shorter, more useful trip than collecting everything heavy. The return journey is part of the plan.",
    dangers="Noise, weight and blocked exits turn a full bag into a liability. Old directories and loot tables do not certify present stock or safety."})
topic("vehicle","Vehicle repair",{"vehicle","vehicles","car","cars","engine","battery","tyre","tire","mechanics","vehicle repair","car repair"},
    "lua/client/Vehicles/ISUI/ISVehiclePartMenu.lua; lua/shared/Translate/EN/SurvivalGuide.json",{
    what="A working car needs more than fuel: inspect its engine, battery, tyres and other parts. A key alone is an administrative achievement.",
    make="I have no verified recipe for building a whole car here. Recover a vehicle and replace or repair the parts for which you have the tools and skill.",
    use="Inspect before travelling. Check fuel, battery charge, tyres and engine condition; take the supplies needed for the trip and leave room to manoeuvre.",
    find="Parked vehicles may supply compatible replacement parts. Check the required vehicle type and skill before removing something you cannot install.",
    why="Transport extends a useful supply trip, but brings noise, fuel use and repair work. Compare the actual route with what you could carry on foot.",
    dangers="Engine noise attracts zombies. Poor tyres or engine condition can spoil an escape. Not every damaged part is repairable, and incompatible parts are not made compatible by carrying them farther."},
    {use="Game survival reference: open Vehicle Mechanics at the hood or through the vehicle menu. Select the actual part to see its condition and the tools, skill and compatible parts needed for the available work."})
topic("shutoff","Power and water shutoff",{"shutoff","power shutoff","water shutoff","power goes off","water goes off","electricity off","water off","grid fails"},
    "lua/shared/Translate/EN/Sandbox.json; lua/shared/Translate/EN/SurvivalGuide.json",{
    what="Mains electricity and the unlimited water supply can stop. The schedule depends on this world's rules; I cannot read an exact future shutoff date from an old file.",
    make="Prepare stored clean water, safe cooking and a plan for food before the service fails. A plan is cheaper while the taps still work.",
    use="Use remaining water in fixtures carefully after shutoff, and treat unsafe collected water. Plan generator fuel and eat perishables while they are still good.",
    find="Check the actual services at your location and the supplies already stored. Rivers remain a water source, but their water needs treatment.",
    why="A fridge without power becomes a cupboard with a deadline. Water preparation cannot wait until you are already thirsty.",
    dangers="Do not assume a fixed number of days applies everywhere. Electricity and water can fail separately; an operating light does not prove the taps will last."},
    {what="Game survival reference: the sandbox Water Shutoff and Electricity Shutoff settings control the schedule relative to the default start date. Settings can postpone or disable the usual schedule. This reference does not reveal the selected random shutoff day."})
topic("winter","Cold and seasons",{"winter","cold","warmth","snow","season","seasons","freezing","hypothermia","wet clothes"},
    "lua/shared/Translate/EN/SurvivalGuide.json; lua/shared/Translate/EN/Moodles.json",{
    what="Cold, wet clothing and poor shelter can make an ordinary journey dangerous. Winter is not a larger summer with better scenery.",
    make="Prepare dry layers, shelter and safe heat before you need them. Keep another way to cook if the electricity fails.",
    use="Keep dry, adjust layers and rest somewhere sheltered when you are too cold. Check yourself rather than judging the weather through a window alone.",
    find="Look for suitable clothing and shelter on a route you know. I cannot promise a heated building or dry coat at a map symbol.",
    why="Temperature affects what you can safely do. Seasonal plans also affect food and crops; do not assume last month's method stays reliable.",
    dangers="Wetness and wind make exposure harder. Heat sources bring fire and ventilation risks. A running generator belongs outdoors."})
topic("moods","Boredom, stress and panic",{"boredom","bored","stress","stressed","panic","panicking","fear","scared"},
    "lua/shared/Translate/EN/Moodles.json; lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/items/literature.txt",{
    what="Boredom, stress and panic are different pressures. A book may help a quiet afternoon; it is not an answer to somebody reaching through the door.",
    make="Choose a small safe activity, company or something to read. Do not manufacture excitement by looking for a fight.",
    use="For panic, first get away from immediate danger and find a defensible place. For boredom, try reading or another safe activity. Give tired people time to rest.",
    find="Books and magazines are possible finds in homes and bookshops. Company is closer if you already have somebody you trust.",
    why="Your condition affects decisions and capabilities. Taking a pause before a risky task is work on that task, however little the paperwork appreciates it.",
    dangers="An old file cannot tell me how you feel. If this is about your day, you may simply talk to me."})
topic("bite","Bites and Knox infection",{"bite","bites","bitten","zombification","knox infection","turning","will i turn","infection","infected"},
    "lua/shared/Translate/EN/Sandbox.json; lua/shared/Translate/EN/SurvivalGuide.json",{
    what="A zombie bite is a grave infection risk. Ordinary wound infection and the Knox Infection are different things.",
    make="I have no verified cure to manufacture. A dressing treats the wound; it is not an antidote to the Knox Infection.",
    use="Stop the bleeding, treat the actual injury and get somewhere safe. If this concerns a companion, name them so I keep the advice attached to the right person.",
    find="There is no verified cure depot in this archive. Medical supplies can help an ordinary injury without curing Knox infection.",
    why="Zombie wounds can pass the infection. There are conditions I cannot establish from here, and I cannot diagnose infection from a typed sentence alone.",
    dangers="I have no verified cure for Knox infection. A clean bandage cannot promise protection from turning. Treat the injury and keep the person safe and comfortable. Feeling sick alone does not prove Knox infection; other causes exist."},
    {what="Game survival reference: check Zombie Lore's Transmission and Infection Mortality settings. They can change or disable the usual outcome. Under standard infection rules a zombie bite transmits Knox infection; ordinary wound disinfectant does not cure it."})
topic("weapons","Choosing a weapon",{"weapon","weapons","best weapon","melee","axe","crowbar","knife","spear","bat"},
    "lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/items/weapon.txt",{
    what="A melee weapon strikes within reach; a firearm spends ammunition to reach farther. Neither replaces room to withdraw.",
    make="Use a weapon you can handle and inspect its condition. For a crafted weapon, follow a known recipe rather than assuming every sharp object will attach to every stick.",
    use="Face one threat at a time, leave space for the swing and stop before you are exhausted. A downed zombie can still be a problem if you stop watching the others.",
    find="Tools and sporting equipment may supply usable melee weapons. Police and gun shops are possible firearm searches, with no promise of stock or safety.",
    why="The best weapon is one you can use reliably in the space available. Melee conserves ammunition; firearms make a louder problem for the neighbourhood.",
    dangers="A crowd can get inside your reach. Do not test a new weapon while tired or surrounded. Keep an escape route even when the first blow goes well."},
    {use="Game survival reference: equip the weapon, hold your bound Aim control and use Attack toward the cursor. At close range an attack can shove instead. The Shove/Stomp control can stomp a downed zombie; check your key bindings rather than assuming the default buttons."})
topic("water","Drinking water",{"water","drinking water","tainted water","rainwater","rain water","boil water","water bottle","river water"},
    "lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/recipes/recipes_medical.txt",{
    what="Clean drinking water is a supply to protect. Tainted water is not made safe by looking clear.",
    make="Boil tainted water in a suitable heat-safe container, or use the proper purification tablets. Keep the treated water separate from what still needs treatment.",
    use="Carry clean water and replenish it before the container is empty. Treat water collected from a river or rain rather than assuming the source is safe.",
    find="Use the taps while they work, recover remaining water from fixtures after shutoff, or collect and treat water from outside sources. Rivers and rain do not come with a cleanliness certificate.",
    why="Thirst makes other jobs harder and becomes dangerous. A stored reserve turns tomorrow's search into a choice rather than an emergency.",
    dangers="Tainted water can cause sickness. Not every container belongs in a fire or microwave. Check treatment and container options before heating it."},
    {make="Game survival reference: use a compatible heat-safe cooking container to boil tainted water, or the water-purification recipe with purification tablets. Check the liquid/container information to confirm it is safe before drinking.",
     use="Game survival reference: clean water in the main inventory is automatically consumed by default. Use the container's drink/fill or Transfer Liquid options for manual handling; settings and mods may alter automatic drinking."})
topic("food","Food and preservation",{"food","cooking","cook","fridge","refrigerator","freezer","canned food","cans","rotten food","fresh food"},
    "lua/shared/Translate/EN/SurvivalGuide.json; scripts/generated/items/food.txt",{
    what="Food provides energy. Fresh food spoils; refrigeration buys time while the appliance has power.",
    make="Cook suitable ingredients with the right container and heat source. Keep safe ingredients apart from rotten ones; a saucepan does not reverse time.",
    use="Eat perishables while they are good and keep durable food for later. Inspect what you are cooking and remove it before it burns.",
    find="Homes and food shops are possible searches. Fishing, foraging, farming and trapping can supplement supplies, each with its own requirements.",
    why="A working freezer is temporary storage, not a permanent promise. Planning meals and preserving food reduces the number of urgent trips.",
    dangers="Rotten or unsuitable raw food can make you ill. A powered fridge still needs a fuel or grid plan; an unpowered one cannot preserve food indefinitely."},
    {use="Game survival reference: inspect food freshness and cooking information. Use an appropriate cooking container or the crafting/cooking options for the recipe, then watch its cooking progress. Refrigerator and freezer protection depends on power."})
topic("fire","Fire and safe heat",{"fire","flames","burning","campfire","camp fire","smoke","fire safety"},
    "lua/shared/Camping/ISCampingMenu.lua; lua/shared/Translate/EN/SurvivalGuide.json",{
    what="Fire supplies heat and can spread, burn people and destroy shelter. Keep clear of flames, preserve an exit and extinguish a fire only when you can do so safely.",
    make="Prepare a suitable fire site, fuel and a working ignition method. Keep it clear of the things and people you want to retain.",
    use="Control the fire, keep an escape route and attend to the food or warmth you need. Put it out when it is no longer needed.",
    find="Bring appropriate fuel and ignition supplies; do not depend on finding them beside the place you become cold.",
    why="Fire can keep you warm and make water or food safer. The point is useful heat, not the largest possible demonstration.",
    dangers="Keep away from flames, combustible surroundings and enclosed fumes. If a building is burning, get clear rather than trying to save every item.",
    extinguish="For a controlled campfire, use its extinguishing action. If a fire is spreading through a building, leave by a clear exit and keep people back; do not stand in flames to recover possessions."},
    {use="Game survival reference: the campfire context menu offers fuel, lighting and extinguishing actions when their requirements are met. Check the actual fuel/ignition options; do not assume one lighting item works without the required tinder or fuel."})
topic("night","Moving after dark",{"night","nighttime","darkness","dark","after dark","flashlight","torch"},
    "lua/shared/Translate/EN/SurvivalGuide.json; lua/shared/Translate/EN/Moodles.json",{
    what="Night reduces what you can see and can catch you tired. The dead have not agreed to office hours.",
    make="Plan light, shelter and the route home while you can still see it. A reserve battery weighs less than a bad surprise.",
    use="Slow down, check the next stretch and use a light when you need it. Stay with a route you know and avoid a tired fight.",
    find="Look for a flashlight and suitable batteries before setting out. A lit building is not automatically occupied, safe or supplied.",
    why="Waiting for daylight can save a difficult journey. If you must move, a short known route beats a confident guess in the dark.",
    dangers="Darkness hides obstructions and threats. Tiredness further limits your capabilities. Leave enough time and strength to return."})
topic("visitors","Visitors and strangers",{"visitor","visitors","stranger","strangers","someone outside","people outside"},
    "mod:SCTerminalConversation.lua; mod:SCUISocial.lua",{
    what="A stranger is a person you have not established a relationship with. Keep an exit and find out what they actually want.",
    make="You cannot manufacture trust with a title. Talk, listen and help a real need when you can do so safely.",
    use="Meet somewhere defensible and use the conversation they offer. Keep supplies and sleeping people protected while you decide whether to invite them closer.",
    find="Use the people and encounters you have actually observed. This terminal cannot reveal a stranger hiding in an unvisited building.",
    why="Another person can bring skills, trade or trouble. Their behaviour and needs are better evidence than the first impression.",
    dangers="I cannot judge that stranger's intentions from here; keep an exit and protect your people while you decide. Do not assume every conversation is safe or every stranger wants to join. Respect an actual refusal."},
    {use="Game survival reference: select the survivor and open Talk or their context options. Recruitment, assistance and trade appear according to that survivor's actual state; a typed claim cannot enable a missing option."})
topic("trade","Trading with survivors",{"trade","trading","barter","trader","merchant","buy","sell"},
    "mod:SCTerminalConversation.lua; mod:SCUISocial.lua",{
    what="Trade is an exchange somebody is actually willing to make. Your need for an item is not the other person's agreement.",
    make="Bring something the other person values, keep your own reserve and review the offered terms before accepting.",
    use="Talk to the survivor and use trade when it is offered. Check both sides of the exchange before committing.",
    find="A trader must be someone you have met or reached through a real contact. I have no verified shop inventory for a stranger I cannot identify.",
    why="A fair exchange can fill a missing supply without searching another building. Friendship and recruitment still have their own conditions.",
    dangers="Do not trade away the supplies your people need to return safely. A gift, a trade and a contract are separate promises."},
    {use="Game survival reference: open the survivor's Talk choices and choose the offered trade. Review the real items and terms in that interface. The reference neither places an order nor transfers your items."})
topic("recruit","Recruiting a companion",{"recruit","recruiting","recruitment","new companion","new follower","join us","get followers"},
    "mod:SCTerminalConversation.lua; mod:SCUISocial.lua",{
    what="Recruitment means another survivor agrees to join you. That agreement depends on the person and their present obligations.",
    make="Build trust by helping real needs, keeping people safe and spending time together. Repeating a gift is not the same as building a relationship.",
    use="Meet the survivor, talk and use Recruit when they offer it. Read the actual reason if they cannot join.",
    find="Start with survivors you have actually met. A household, contract or family obligation can matter as much as personal trust.",
    why="A willing companion adds skills and another person to care for. Make room in the food and shelter plan before making a speech.",
    dangers="Trust does not erase every obligation. Do not promise yourself that every friendly stranger will become a follower."},
    {use="Game survival reference: select the survivor and choose Recruit when it is available in their offered choices. Talk shows the relationship stage and reasons. A disabled choice needs its actual condition resolved."})
topic("moving_camp","Moving camp",{"moving camp","move camp","moving base","move base","new base","new camp","relocate"},
    "mod:SCTerminalConversation.lua; mod:SCUIContext.lua",{
    what="Moving camp means choosing a new place and getting the people and supplies there. Start with shelter, water, exits and a route you have checked.",
    make="Prepare the destination before abandoning the last usable shelter. Plan who can travel, what must be carried and what can wait.",
    use="Start with shelter, water, defensible entrances and more than one exit. Move in manageable trips and keep track of people and essential supplies. Establish usable work and storage areas.",
    find="Shortlist explored houses or other buildings with shelter, water access and exits, then inspect them. Use witnessed reports, not an attractive map shape, to establish the state of the doors or neighbours.",
    why="A safer or better supplied site can justify the work. Compare that gain with the cost of transporting everyone and starting the camp's work again.",
    dangers="A camp marker does not carry supplies or make an injured person fit to walk. Keep enough food, water and strength for the move itself."},
    {use="Game survival reference: moving the camp requires Abandon camp first. Review its confirmation, then use Set camp core here at the new location. Re-establish the needed storage/work markings and arrange transport separately."})
topic("map","Maps and routes",{"map","maps","route","routes","landmark","landmarks","where do i go"},
    "lua/shared/Translate/EN/SurvivalGuide.json; mod:SCTerminalConversation.lua",{
    what="A map records places. Combine it with landmarks you recognise, a way back and what someone actually observed on the route.",
    make="Add clear notes about places you visited. Keep a date with a report that might change, such as a blocked road or a searched building.",
    use="Choose a route you can follow and leave room to turn back. Check the next landmark rather than treating a drawn line as a cleared road.",
    find="Read found maps and keep your own explored map up to date. I cannot reveal an unvisited route from a place name alone.",
    why="A known route saves time and helps you return. Keeping useful notes is less dramatic than getting lost, which is part of its appeal.",
    dangers="A map does not establish present safety, stock or occupancy. A straight distance may hide a much longer walk around obstacles."},
    {use="Game survival reference: open the map with its bound control and use the map's notes/annotation tools. Read a found map through its item options. Expedition Choose on map keeps the normal map's zoom and annotation controls."})
topic("broadcasts","Broadcasts and news",{"broadcast","broadcasts","broadcaster","news","radio news","news report"},
    "lua/shared/Translate/EN/RadioData.json; radio/RadioData.xml; mod:SCTerminalConversation.lua; mod:SCTerminalRadioUI.lua",{
    what="A broadcast is a report heard through a receiver. Check the station, source and date; an archived transmission is not a fresh view of the county.",
    make="I cannot manufacture a real news report. Keep an honest note of what was actually heard and when.",
    use="Tune a working receiver and listen. Compare a dated report with current local observations before acting on it.",
    find="Radio examples include LBMW Kentucky Radio and KnoxTalk; WBLN News is a television broadcaster. Use an actual receiver to discover what is transmitting now.",
    why="A report can warn of a wider event or preserve something you would otherwise miss. The speaker's confidence still needs a source beside it.",
    dangers="Silence does not prove safety, and an old reassurance does not establish a clear road now. This computer has no outside connection merely because it can display a station's name."},
    {use="Game survival reference: open radio for the mounted receiver when available, or use a working handheld. The scanner and presets depend on the actual receiver, power and tuning range. Archive files remain dated reading."})
for _,row in ipairs(D) do if row.id=="firearms" then
    row.subtypes={shotgun="A shotgun is a loud firearm that uses shotgun shells. Its shells are not interchangeable with pistol or rifle cartridges.",
        pistol="A pistol is a handgun. Match ammunition and any magazine to that particular model; not every pistol uses 9mm."}
end end
return D
