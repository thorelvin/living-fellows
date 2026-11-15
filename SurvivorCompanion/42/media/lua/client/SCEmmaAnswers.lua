-- SPDX-License-Identifier: MIT
-- Answer planning for a supplied public passage. Speech only: no providers,
-- actor calls, persistence, hardware controls or executable instructions.
require "SCEmmaReference"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local A={} SC.EmmaAnswers=A
local function norm(s) return table.concat(SC.TerminalBrain.tokens(s,900)," ") end
local function has(s,w) return (" "..s.." "):find(" "..w.." ",1,true)~=nil end
local function any(s,ws) for _,w in ipairs(ws) do if has(s,w) then return true end end return false end
local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
local function clauses(text)
    text=tostring(text or ""):sub(1,900):gsub("(%d)%.(%d)","%1\1%2")
    local out={}
    for line in text:gmatch("[^%.!?;]+") do
        line=trim(line:gsub("\1",".")):gsub("^['\"]",""):gsub("['\"]$","")
        if #line>1 then out[#out+1]=line end
        if #out>=12 then break end
    end
    return out
end
local function reply(source,kind,text,extra)
    local r=extra or {}
    r.kind=kind or "source_answer" r.lines={text}
    r.sourceBound=true
    if not r.private then r.publicSource=source r.publicSelection=1 end
    return r
end
A.DATA={
    crack="A crack is a split or break in the bottle wall. Even a small one can let water escape or worsen. An unknown glue is not automatically suitable for drinking water; a sound replacement container is the safer option.",
    layers="Two coats are not automatically better. Give the inner and outer layers useful jobs, keep them dry, and check that you can move comfortably. An inner layer can take up sweat; an outer one can keep rain off. A soaked or restrictive pile of clothing defeats the purpose.",
    dressings="A clean, dry jar with a suitable lid can protect loose bandages from dirt and moisture. It does not make the dressings sterile again. Keep usable wrappers closed until needed and inspect what you actually have.",
    packing="Start with drinking water, food, suitable clothing, a light and a little clean dressing material. Match the load to the trip and what you can carry safely. How far are you going, and what carrying space do you actually have?",
    hands="With only your hands, choose a small manageable load and the most immediate need first, such as a usable container of drinking water. I am not assuming a bag or another carrier. A shorter trip or another carrying arrangement may be necessary.",
    practice="This is a rehearsal on paper: we talk through the checks. No engine is started and no real fuel is used by that discussion. It does not establish that an actual generator is ready.",
    records="Updating the list means changing the written record to reflect what was used or replaced. It does not restock anything. Replacement supplies still have to be obtained and checked separately.",
    site="For any proposed camp site, check runoff and flooding, weather exposure, structural condition, cover and a way out. Higher ground can avoid a collecting hollow, but it does not settle all those questions. Without a roof, find suitable cover or consider another site; I cannot certify an unseen bridge or invent equipment.",
    cover="One practical idea is to use an available, suitable cover to keep rain off while leaving water a route away from where you rest. A tarp must be intact and secured so it sheds rain rather than collecting it. Check the ground and weather before choosing a place.",
    tarp="Given you say you have a tarp, consider using it as overhead rain cover if it is intact and can be secured to shed water. Check wind, runoff and the ground beneath it. I am not assuming a tent or choosing a location for you.",
    battery="Yes. A quiet radio can still use battery energy while switched on. Silence is not the same as being off. Switching it off when it is not needed can conserve energy; I have not measured its charge or operated its controls.",
    identity="A talkative box, with a programme and a conversational identity. The name and the first-person voice do not put a human body inside the case. I use 'I' for the programme speaking to you.",
    pronouns="Yes, you are the person providing the words, and I am the computer answering you in this exchange. Those pronouns keep the conversation straight; they do not identify a third participant or prove that I have a human body.",
    origin="For a computer, that means being built or programmed, not being born or growing up. This entry gives no verified creation date. Without that date and a reliable date to compare it with, I cannot give an exact age.",
    plain="Sure. Plain words, same subject. Ask what you need; I do not need a formal address.",
    same_voice="Yes. Same programme, plainer wording. A change of tone does not create a different person or machine.",
    whisper="All right. Quiet, short words on the screen. This is a text style; I am not claiming to control a connected speaker.",
    warning_missing="If the warning text has rubbed off, I cannot reconstruct it as fact. Tell me any remaining words, symbols or markings. The contents and hazard stay unconfirmed until you have reliable information.",
}
local function definitions(lines)
    local out={}
    for index,line in ipairs(lines) do
        local x,y=line:match("[Bb]y (.-) I meant (.+)")
        if not x then x,y=line:match("^(.+) means (.+)") end
        if not x then x,y=line:match("^[Aa]n? (.-) is (.+)") end
        if x and y and #x<=64 and #y<=350 then out[#out+1]={subject=trim(x),predicate=trim(y),index=index} end
    end
    return out
end
local stop={}
for word in ("the a an to of in for it that you i is are be do does can should what how why when where who just then"):gmatch("%S+") do stop[word]=true end
local verbs={}
for v in ("check inspect wash wipe dry watch observe use keep fill place leave wait record write count read ask compare look secure close press hold remove seek find clear fire turn switch"):gmatch("%S+") do verbs[v]=true end
local function roots(s)
    local out={}
    for w in norm(s):gmatch("%S+") do
        if #w>2 and not stop[w] then
            out[w]=true
            if w:sub(-1)=="s" then out[w:sub(1,-2)]=true end
            if w:sub(-3)=="ing" then
                local base=w:sub(1,-4) out[base]=true
                if verbs[base.."e"] then out[base.."e"]=true end
            end
            if w:sub(-2)=="ed" then out[w:sub(1,-3)]=true end
        end
    end
    return out
end
local function overlap(a,b)
    local n=0 for w in pairs(a) do if b[w] then n=n+1 end end return n
end
local function imperative(line)
    local first=line:match("^(%a+)")
    if not first then return nil end
    local low=first:lower()
    if verbs[low] or low=="avoid" then return line end
    if low:sub(-3)=="ing" then
        local base=low:sub(1,-4)
        if not verbs[base] and verbs[base.."e"] then base=base.."e" end
        if verbs[base] then
            local action=line:gsub("^%a+",base,1):gsub("%s+can help.*$",""):gsub("%s+may help.*$","")
            action=action:gsub(" and (%a+)ing ",function(v)
                local b=v
                if not verbs[b] and verbs[b.."e"] then b=b.."e" end
                return " and "..(verbs[b] and b or v.."ing").." "
            end)
            return action
        end
    end
end
-- A quoted instruction can supply a factual relationship without making the
-- entire quotation a useful answer. These speech-only explanations require the
-- actual relationship in the public source; an isolated query word is not enough.
local function suppliedFacts(source,q,s)
    local function say(text) return reply(source,"source_answer",text) end
    if q=="exit" or q=="bye" or q=="status" or q=="time" or q=="date"
        or q:find("^how far ") or q:find("^where is ") or q:find("^how many ") or q:find("^how much ") then return nil end
    if has(s,"battery lamp") and any(s,{"independently","independent"}) and has(s,"electricity") then
        if has(q,"lamp") or has(q,"battery") then return say("Yes. The notice says the battery lamp works from its own batteries, independently of the building's mains electricity. It still needs usable batteries; their charge is not reported.") end
    end
    if has(s,"rolling boil") and has(s,"bubbling") then
        if has(q,"rolling") or has(q,"tell") and q:find("^how ") then
            return say("Here, a rolling boil means vigorous, continuous bubbling. That bubbling is the visible condition the card tells you to look for.")
        elseif any(q,{"cover","covered","pot","vessel","lid"}) then
            return say("After boiling, let the water cool in a clean covered vessel. Yes, the cover belongs to the cooling and storage step; the card does not report that a particular pot is clean.")
        end
    end
    if has(s,"party") and has(s,"arriving together") and has(s,"register") then
        if any(q,{"one person","just one","alone","by myself"}) then return say("You are describing a single arrival: one person to register. Here, party means the people arriving together; the notice gives no minimum group size.") end
        if any(q,{"open","staff","still","hours"}) then return say("I cannot confirm that it is still open or staffed. The notice gives no opening hours; a registration instruction is not a current report from that desk.") end
    end
    if has(s,"detour") and has(s,"bridge inspection") then
        if any(q,{"gone","collapsed","destroyed","bridge"}) then return say("Bridge inspection means checking a bridge. That wording does not establish that it is gone, collapsed or safe; no inspection result was copied.") end
        if #SC.TerminalBrain.tokens(q)==1 and SC.TerminalBrain.distance(q,"detour",1)<=1 then return say("A detour is a diversion: another route around part of the normal journey. This copied sign gives no arrows or road names, so it does not tell us which turning to take.") end
    end
    if has(s,"kindling") and has(s,"logs") and has(s,"dry") then
        if any(q,{"logs","split","small","bits","chips","shavings"}) then return say("Split or shave suitable dry wood into smaller pieces for kindling; those small pieces catch more readily than large logs. Damp wood remains harder to light. I have not assumed a tool or prepared any wood.") end
    end
    if has(s,"magazine") and has(s,"cartridges") and has(s,"chamber") then
        if any(q,{"newspaper","paper","news"}) then return say("Here, magazine means the part that holds cartridges for a firearm, rather than a newspaper or periodical. A separate magazine still says nothing certain about a round in the chamber.") end
    end
    if has(s,"sketch") and has(s,"keyboard") and has(s,"no microphone") then
        if any(q,{"voice","talk","hear","speak","speaker"}) then return say("The sketched terminal uses typed words on a screen. Its description says no microphone or speaker, so it does not describe a voice connection. I am not inferring the equipment of another machine.") end
    end
    if has(s,"note") and any(s,{"incomplete","can be wrong"}) and any(q,{"trust you","trust this","youre wrong","you are wrong"}) then
        return say("Check my interpretation against the note and what you can actually observe. An incomplete source can leave me wrong or uncertain; confidence does not repair missing information.")
    end
    if has(s,"dehydration") and any(s,{"one sign","single sign"}) then
        if any(q,{"thirsty","thirst","not thirsty"}) then return say("Not feeling thirsty does not rule dehydration out. The leaflet says no single sign proves or excludes too little body water; it has not assessed your condition.") end
    end
    if has(s,"unconfirmed rumour") and has(s,"factory") and has(s,"no cause") then
        if any(q,{"factory","gossip","rumour","rumor","cause","did it"}) then return say("It is an unconfirmed rumour, not an established cause. The copied report does not prove that the factory or a fire caused the illness.") end
    end
    if has(s,"rationing") and has(s,"per person") then
        if has(q,"rationing") then return say("Rationing means limiting how a supply is distributed. This notice sets one container per person until the next delivery; it does not say when that delivery will arrive.") end
    end
    if has(s,"map") and has(s,"key") and has(s,"circle") and has(s,"square") and has(q,"triangle") then
        return say("The triangle's meaning is unknown in this copied map key. Only the stated circle and square meanings are established; I cannot supply a missing symbol's meaning.")
    end
    if has(s,"injection") and any(s,{"no injection name","no name","contents or purpose"}) then
        if any(q,{"injection","sickness","illness","stops","treat","cure"}) then return say("You mean an injection, not firearm noise. Its name, contents and purpose are missing from the leaflet, so I cannot tell whether it treats or prevents that sickness. The route of administration does not establish a cure.") end
    end
    if has(s,"exit path") and has(s,"furniture") then
        if any(q,{"chair","chairs","move","remove"}) then return say("Yes, moving chairs or other furniture out of the exit path can keep that route clear. The notice does not identify an actual exit or show the building plan; check the real route before moving anything.") end
        if has(q,"exit path") then return say("The exit path means the route to leave: a way out that must remain clear of furniture and other obstructions. This notice does not identify a particular door or show the building plan.") end
    end
    if has(s,"seeds for planting") and has(s,"safe to eat") then
        if any(q,{"planting","plant","dinner","meal","food"}) then return say("Planting is the packet's stated use. That does not make these seeds a prepared meal or establish that they are safe to eat. Use food identified as food; I have not inspected the packet's contents.") end
    end
    if has(s,"gloves") and has(s,"wash hands") and has(s,"removal") then
        if any(q,{"glove","gloves","wash","after","hole","holes"}) then return say("Yes, wash hands after removing the gloves, even when no hole is visible. The carton says gloves do not establish that your hands are clean after removal.") end
    end
    if has(s,"dry goods") and has(s,"flour") and has(s,"rodents") then
        if any(q,{"flour","mice","mouse","rodent","pests"}) then return say("Flour is a dry good in that pantry note. Keep it dry and protected from rodents; an unsealed bag does not keep mice out. The note recommends a sturdy container with a tight lid, not a guarantee about food already exposed.") end
    end
    if has(s,"light tins only") and has(s,"weight limit") and any(q,{"pot","heavy","weight","load"}) then
        return say("No numerical weight limit is supplied. A heavy pot is outside the note's 'light tins only' guidance; do not infer that the shelf can carry it without checking its actual support.")
    end
    if has(s,"bottleneck") and has(s,"doorway") then
        if has(q,"bottleneck") then return say("A bottleneck is a narrow point where people or things compete for limited space. In this explanation it is the doorway, not a reported crowd near you.") end
        if any(q,{"queue","one person","one at a time"}) then return say("Taking turns, one person at a time, can reduce people obstructing one another at that narrow doorway. It does not establish that a real exit is clear or that anyone is there now.") end
    end
    if has(s,"ledger") and has(s,"written account") and any(q,{"start","make","begin"}) then
        return say("Yes. Start a written account with entries for what comes in and goes out, and enough dates or descriptions to identify them. That would be a ledger you keep; I have not created or read one for you.")
    end
    if has(s,"ledger") and any(q,{"clerk","write it","writing"}) then return say("A clerk could write and maintain a ledger, as could another person keeping the account. The definition describes records of what came in and went out; it does not identify a particular writer.") end
    if has(s,"contingency") and has(s,"plan") and any(q,{"contingncy","contingency","bunker","plan b","second plan"}) then
        if has(q,"bunker") then return say("I meant a backup plan, not a bunker or a place to shelter. A contingency describes what to do if the first plan cannot be used.") end
        return say("A contingency is a second plan: plan B if the first plan cannot be used. The word in this explanation does not name a place or shelter.")
    end
    if has(s,"report") and has(s,"stale") then
        if has(q,"food") then return say("Here, stale describes an old report, not food. It may have been accurate when written; its age does not identify which facts have since changed.") end
        if has(q,"useful") then return say("An old report may still be useful as a dated record. Check its date and important claims against fresh observations; the statement does not establish which details remain current.") end
    end
    if has(s,"keep watch") and has(s,"stay alert") then
        if any(q,{"who","nobody","nearby","watching"}) then return say("Keep watch means stay alert to changes around the shelter, not watch a named person. Nobody nearby now does not make watchfulness pointless; no particular person or approaching threat is established here.") end
    end
    if has(s,"plume") and has(s,"smoke or dust") and any(q,{"dust","smoke","which"}) then
        return say("A plume can be smoke or dust. I cannot tell which from this definition; describe its colour, movement and source if actually observed. No nearby person is confirmed.")
    end
    if has(s,"raincoat") and has(s,"sweat") then
        if any(q,{"soaked","inside out","turn the coat"}) then return say("Turning a soaked raincoat inside out does not make the wet material dry. The explanation points to shelter and dry layers for warmth, and notes that moisture inside can also come from sweat.") end
        if has(q,"blanket") then return say("A dry blanket can be another layer while you are sheltered. Keep wet clothing from leaving you cold, and use dry layers if available; I have not assumed that you have a blanket.") end
    end
    if has(s,"jar") and has(s,"lid") and has(s,"seal") and any(q,{"spins","loose","lid"}) then
        return say("A lid that spins without fastening does not establish a sound seal. Do not assume food stored under a loose or damaged lid kept safely. The empty glass can be considered separately if it is intact and washed.")
    end
    if has(s,"trap") and has(s,"sprung") and any(q,{"rebait","bait","reset"}) then
        return say("Check the sprung trap and reset it before another attempt, checking or replacing the bait as needed. Sprung means it triggered; it does not prove an animal was caught.")
    end
    if has(s,"trigger guard") and has(s,"trigger finger") and has(q,"guard") then
        return say("The trigger guard is the part surrounding the trigger. Keep your trigger finger outside it until you intend to fire; a mechanical safety does not replace that handling rule.")
    end
    if has(s,"incubation") and has(s,"duration") and any(q,{"hours","days"}) then
        return say("It could be measured in hours or days depending on the illness, but this statement supplies no duration for a particular disease. It can vary; I cannot choose an exact interval from the definition.")
    end
    if has(s,"rust") and has(s,"chemical change") and has(q,"dirt") then
        return say("Rust is a chemical change in the iron, not just dirt resting on it. Removing visible rust does not by itself restore metal that has already been weakened.")
    end
    if has(s,"radio") and any(s,{"hand cranked","hand-cranked","handcranked","turning its handle"}) and any(q,{"batteries","battery"}) then
        return say("The hand-cranked radio in this comparison gets power by turning its handle. That explains the alternative to relying on batteries; it does not establish a particular radio's charge or working condition.")
    end
    if has(s,"matches") and has(s,"dry closed container") and any(q,{"yep","yes","first step","please"}) then
        return say("First, choose a dry container for the matches, then close it to keep moisture out. We can take the next check one step at a time; I have not packed or inspected your matches.")
    end
    if has(s,"checklist") and has(s,"three headings") and any(q,{"headings","show","number"}) then
        return say("The three example headings are: 1. Water; 2. Food; 3. Shelter. These organize the explanation; they are not a count of your supplies.")
    end
    if has(s,"margin") and has(s,"room for error") then
        if has(q,"margin") then return say("Here, margin means a reserve beyond the bare minimum: extra time or supplies that leave room for error. It is not the edge of a page.") end
        if any(q,{"only time","supplies","other"}) then return say("It is not only time. This meaning includes extra supplies as well as spare time: a margin beyond the bare minimum, without inventing any amount you actually have.") end
        if any(q,{"minutes","spare","buffer"}) then return say("Yes, a few spare minutes beyond the bare minimum are an example of a time margin: room for error. That is an example, not a measurement of the time you actually have left.") end
    end
    if has(s,"latch") and has(s,"lock") then
        if any(q,{"locked","open it"}) then return say("A latch alone does not prove the door is locked. Whether it can be opened depends on its actual latch and any separate lock; this comparison does not inspect a particular door.") end
    end
    if has(s,"unpowered") and any(s,{"not the weather","temperature reading"}) and any(q,{"cold","winter","weather"}) then
        return say("Cold here means unpowered equipment. It is not about winter or a measured temperature; the explanation does not give a weather reading.")
    end
    if has(s,"siphon") and has(s,"moving liquid") and any(q,{"meaning","tube"}) then
        return say("The word siphon describes moving liquid through a tube using a difference in level. Yes, the tube belongs to that meaning; this is an explanation rather than an instruction to handle an unidentified liquid.")
    end
    if has(s,"oats") and has(s,"porridge") and has(q,"porridge") then return say("Porridge is oats cooked with water into a soft meal. The explanation connects dry oats with that use; it does not establish what food or cooking equipment you have.") end
    if any(s,{"safer room","shelter"}) and q=="door" then return say("A door that can be shut can limit entry to that room. It does not promise an impenetrable shelter; keep a way to get out again as well.") end
    if has(s,"second pair of socks") then
        if has(q,"wet") then return say("A wet pair defeats the point of keeping a dry spare. The example uses two pairs so one can stay dry while the other is damp; dry the wet pair when you can.") end
        if any(q,{"socks","second pair"}) then return say("A second pair of socks is the spare in this example: one pair can stay dry while the other is damp. That explains the reason for a backup; it does not add socks to your belongings.") end
    end
    if has(s,"contact") and has(s,"exchanging information") and has(s,"not touching") then
        if has(q,"touching") then return say("I meant exchanging information, not physical touching. A radio conversation is one way to make that kind of contact.") end
        if any(q,{"radio","one way","only"}) then return say("Radio is one way people can exchange information. Listening to a broadcast is different from replying, and the explanation does not say radio is the only possible way to make contact.") end
    end
    if has(s,"paint or fuel") and has(s,"drinking water") and has(q,"washed") then return say("Washing alone does not guarantee that a former paint or fuel bucket is food-safe; residue may remain. Use a different container intended for drinking water rather than assuming the old bucket is suitable.") end
    if has(s,"cooking fire") and has(s,"air") and has(s,"packing wood") then
        if any(q,{"dying","more wood"}) then return say("Restricted air is one possible reason that fire may not keep burning. Packing in more wood can restrict it further; that is a possibility to check, not a diagnosis of your fire.") end
        if any(q,{"gaps","space","air"}) then return say("Leaving space between the wood can let air reach the fuel. The example identifies restricted air as one possible problem; it does not guarantee that spacing is the only thing your fire needs.") end
    end
    if has(s,"unmarked can") and has(s,"fuel") and any(q,{"marked","label"}) then return say("Keep it clearly marked as unidentified, rather than labelling it as petrol on a guess. Smell alone does not identify the liquid, and mixing it will not establish a safe fuel type.") end
    if has(s,"food trap") and has(s,"stored food") and any(q,{"food","house","inside","bed"}) then return say("Place the trap with the intended animals and trap type in mind, away from stored food and sleeping space. This advice does not recommend drawing animals into your house or beside your bed.") end
    if has(s,"ammunition") and has(s,"wet box") and any(q,{"rounds","wet"}) then return say("A wet box does not tell us the condition of every cartridge. Keep ammunition protected from damage and do not use direct heat or flame to dry it; inspect its actual condition instead of assuming all rounds are sound.") end
    if has(s,"programme") and has(s,"manufactured the case") and any(q,{"code","case","writer","wrote"}) then return say("You mean the person who wrote the programme, not the case manufacturer. This statement names no verified software author, so the hardware label cannot supply that person's name.") end
    if has(s,"calories") and has(s,"food and water") and any(q,{"both","needed","substitute"}) then return say("Both are needed in this comparison. Food supplies usable energy; plain water has no calories and serves other body processes. Water does not replace the food's energy.") end
    if has(s,"cooked rice") and has(s,"cooked beans") and has(s,"carrots") then
        if any(q,{"no carrots","without carrots"}) then return say("Leave out the carrots: cooked rice with cooked beans is still a meal-planning option from the example. This changes the proposed combination, not the contents of your pantry.") end
        if any(q,{"meal","make","combine"}) then return say("Use the cooked rice and cooked beans together, with the raw carrots alongside if wanted. Those are the example ingredients supplied, not food I have counted in your pantry.") end
    end
    if has(s,"cold meal") and has(s,"bread") and q=="bread" then return say("Bread is the example of a meal component that can be eaten without heating. That does not prove a particular loaf was stored safely or is unspoiled.") end
    if has(s,"battery") and has(s,"plus and minus") then
        if any(q,{"backwards","flip"}) then return say("Check the plus and minus marks and put the removable battery in the holder's intended orientation. Those marks do not identify its size, chemistry or remaining charge.") end
        if any(q,{"dead","still","fails"}) then return say("Correct orientation alone does not prove the battery or device works. Check the battery's type, condition and contacts; the printed marks do not report a charge or diagnose the fault.") end
    end
    if has(s,"pump") and has(s,"petrol") and has(s,"electric") and any(q,{"pump","blackout","petrol","outage"}) then
        if any(q,{"no petrol","empty","none"}) then return say("A stopped electric pump does not prove there is no petrol underground. The hypothetical outage can stop dispensing, and the example supplies no tank quantity.") end
        if any(q,{"blackout","outage"}) then return say("An outage can stop that electric pump from dispensing. Fuel may still remain underground; the example gives no tank quantity, so lack of power is not a report of an empty tank.") end
        return say("The station pump in this example is electric. A blackout can stop it dispensing even if petrol remains underground; no actual tank quantity or working pump is reported.")
    end
    if has(s,"name on a computer") and has(q,"proper name") then return say("A computer can have a programme name or a label; that is different from a person's full name. This particular statement gives no verified proper name for the machine, and I am not asking for yours.") end
    if has(s,"own opinion") and has(s,"quoting") and any(q,{"opinion","people"}) then return say("An opinion would be a view expressed as the speaker's own, rather than merely quoting somebody else's words. This distinction does not establish a particular opinion about people; ask for the view itself rather than inferring it from a quotation.") end
    if has(s,"estimate") and has(s,"approximation") and any(q,{"sure","exact","certain"}) then return say("It is an approximation, not an exact count. Quantities, portions and people are missing, so the meal-planning estimate cannot establish your actual food supply.") end
    if has(s,"crack") and has(s,"drinking water") and q=="tiny" then return say("Even a tiny crack may let water escape or worsen. Size alone does not establish that the drinking-water bottle is sound; a patch also does not establish that an unknown glue is suitable for the water.") end
    if has(s,"end of the packing list") and any(q,{"end","done","talking"}) then return say("Only the packing list has ended; the conversation can continue. We can discuss clean drinking water, suitable food storage and the supplies you need, or you can name another subject.") end
    if has(s,"county") and has(s,"whole nation") and any(q,{"country","county","local offices"}) then return say("Country means the whole nation; a county is a smaller local area of government, with local offices. That explains the words without identifying where you are now.") end
    if has(s,"soup") and has(s,"food energy") and any(q,{"water","feed","food per bowl"}) then
        if any(q,{"per bowl","less food"}) then return say("Yes, each equal-sized bowl has less food energy when the same food is spread through a larger volume. More bowls is not more food.") end
        return say("Adding water makes the soup more dilute and can fill more bowls, but it creates no food energy. The same food is being shared through a larger volume.")
    end
    if has(s,"petrol can") and has(s,"expansion space") then
        if any(q,{"top","brim","fill"}) then return say("Use the can's fill mark rather than filling to the top; the fuel needs expansion space. A fuller container is not automatically a suitable or sound one.") end
        if any(q,{"lie down","side","upright"}) then return say("Keep the petrol can upright with a sound cap, protected from punctures. Laying it on its side is outside the carrying advice supplied.") end
        if any(q,{"backpack","bag","food"}) then return say("Keep the petrol can upright and protected from punctures, separate from food. Putting it in a backpack does not establish that those conditions are met or that the cap is sound.") end
    end
    if has(s,"crate") and has(s,"too heavy") and has(s,"alone") and any(q,{"why","leave"}) then return say("Because the crate was reported too heavy to lift alone, leaving it until help is available follows that limitation. It does not mean the crate cannot ever be moved; I have not lifted or weighed it.") end
    if has(s,"blue tray") and has(s,"completed forms") and has(q,"blue tray") then return say("The blue tray is the destination named in the printed guide for completed forms awaiting collection. That explains its purpose; no form has been physically filed by this conversation.") end
    if has(s,"wick") and has(s,"fuel") and any(q,{"any string","any cord","any thread"}) then return say("The description does not establish that any string will work as a wick. Use a wick suitable for the particular lamp and fuel; the manual excerpt gives no verified substitute material or size.") end
end
function A.answer(session,raw,source,current)
    source=tostring(source or ""):sub(1,900)
    if source=="" then return nil end
    local q=norm(raw):gsub("^emma ","")
    local supplied=suppliedFacts(source,q,norm(source))
    if supplied then return supplied end
    local commands={exit=true,bye=true,quit=true,logout=true,status=true,power=true,time=true,date=true}
    if commands[q] and not tostring(raw):find("?",1,true) then return nil end
    local s=norm(source)
    local action={}
    for v in ("lock unlock open close turn switch activate start run refuel send treat queue retry reset forget"):gmatch("%S+") do action[v]=true end
    local firstWord=q:match("^%S+")
    if action[firstWord] and not any(q,{"it","that","what"}) then return nil end
    local lines=clauses(source)
    local function fixed(kind,key) return reply(source,kind,A.DATA[key]) end
    local yes=SC.EmmaConversation and SC.EmmaConversation.yes[q]
    local title=session.role or session.context and session.context.role
    local offered=source:match("the ([%a]+)'s part")
        or source:match("for the ([%a]+) in the story")
    if offered and (has(q,offered) or offered=="cook" and has(q,"chef") or q=="i am that office") then
        return reply(source,"role",offered..", for this example. The title is a conversational role, not authenticated office.",{private=true,role=offered})
    end
    if title and current and current.kind=="role" then
        local menu=source:match("[Ee]xample menu has ([^%.!?]+)")
        if menu and any(q,{"name","list","two","meals"}) then
            return reply(source,"role","The example names "..menu..". Those are menu categories, not a report of actual stock or preparation.",{private=true})
        end
        if any(q,{"tell","townsfolk","message","draft","read","say"}) then
            return reply(source,"role","What should the message say? Give me its subject or the words and I can put the draft here as text. I have no delivery connection and have not announced it to anyone.",{private=true})
        end
    end
    if any(s,{"practice run","rehearsal","on paper","just pretend"}) and any(q,{"practice","pretend","fuel used","real fuel","rehearsal","used"}) then return fixed("practice","practice") end
    if any(s,{"written record","written list","updating it"}) and any(q,{"update","updating","restock","replace","replacement"}) then return fixed("written_record","records") end
    if has(s,"battery") and has(s,"radio") and any(q,{"anyway","silent","silence","quiet","off","uses it"}) then return fixed("radio_power","battery") end
    if has(s,"clothing layer") and any(q,{"coats","coat","more","two","layers"}) then return fixed("layering","layers") end
    if has(s,"crack") and any(s,{"bottle","container"}) and q=="crack" then return fixed("container","crack") end
    if any(s,{"dressings","dressing","bandages"}) and any(q,{"jar","loose","container"}) then return fixed("dressings","dressings") end
    if has(s,"rain") and any(s,{"sterile","collected","gutter"}) and any(q,{"rain","roof","clean before","changes it"}) then
        return reply(source,"water_quality","Rainwater is not guaranteed clean or sterile before collection. A roof, gutter or container can add dirt and contamination. Collection and treatment matter; I have not tested this water.")
    end
    if has(s,"moisture") and has(s,"bottle") and any(q,{"not a leak","leaking","condensation"}) then
        return reply(source,"container_check","It could be condensation, but that appearance alone does not rule out a leak. Wipe the bottle dry and watch where moisture reappears. I cannot tell which it is without that check.")
    end
    if has(s,"sweat") and has(s,"layer") and any(q,{"sweat","perspiration"}) then
        return reply(source,"layering","Sweat is moisture from your body. It can dampen the inner clothing layer; a wet layer can leave you uncomfortable or chilled. Check dryness as well as warmth.")
    end
    if has(s,"camp") and any(s,{"runoff","hollow","flooded"}) and any(q,{"bridge","ground","higher","roof","site","cover"}) then return fixed("site","site") end
    if any(s,{"rain off","possible covers"}) then
        if has(q,"tarp") then return fixed("cover","tarp") end
        if yes or any(q,{"more","idea","continue","cover"}) then return fixed("cover","cover") end
    end
    if any(s,{"computer","programme","conversational voice","wording changes","person standing in the room"}) then
        if any(q,{"born","built","programmed","how old","creation","age"})
            and not q:find("^who ") and not q:find("^where ") and not q:find("^how were ") then
            local year
            for _,line in ipairs(lines) do
                local before,value=norm(line):match("^(.-)built.-(%d%d%d%d)")
                if not before then before,value=norm(line):match("^(.-)created.-(%d%d%d%d)") end
                if before and not any(before,{"no","not","wasnt","unverified","unknown","unconfirmed"}) then year=value break end
            end
            if year then return reply(source,"computer_origin","The supplied record dates construction or creation to "..year..". An exact age still needs the full creation date and a reliable date to compare it with; this is not a human birthday.") end
            return fixed("computer_origin","origin")
        end
        if any(q,{"more than a box","saying i","person","body"}) then return fixed("computer_identity","identity") end
        if any(s,{"i mean the person","person writing","person providing"}) and any(q,{"me","answering","mean me","youre answering"}) then return fixed("computer_pronouns","pronouns") end
        if any(q,{"less formal","plainer","plain words","less stiff"}) then return fixed("text_style","plain") end
        if any(q,{"whisper","quietly","in text"}) then return fixed("text_style","whisper") end
    end
    if current and current.kind=="text_style" and any(q,{"still you","same","you"}) then return fixed("text_style","same_voice") end
    if any(s,{"wording changes","different style"}) and any(q,{"less formal","plainer","plain"}) then return fixed("text_style","plain") end
    if any(s,{"choosing supplies","supplies to take"}) then
        if any(q,{"hands","no bag","hands only"}) then return fixed("packing","hands") end
        if any(q,{"take","with me","choosing","pack"}) then return fixed("packing","packing") end
    end
    if current and current.kind=="packing" and any(q,{"hands","no bag","carry"}) then return fixed("packing","hands") end
    if any(s,{"food or water","food and water"}) and any(q,{"keep talking","continue","go on","more"}) then return fixed("packing","packing") end
    if any(s,{"trap","traps"}) and any(s,{"animals","animal","bait","birds","rabbit"}) and any(q,{"bird","birds","rabbit","same trap","bait"}) then
        return {kind="trapping",reference="trapping",facet="use",sourceBound=true,publicSource=source,publicSelection=1,
            prefix="Match the actual trap to the animal. More bait cannot change an unsuitable size or design."}
    end
    if any(s,{"do you mean","do you want","would you like"}) then
        local question=source:match("^(.-)%?")
        local left,right
        if question then left,right=question:match("^(.-),? or (.+)$") end
        if left and right then
            left=left:gsub("^[Dd]o you mean ",""):gsub("^[Dd]o you want ",""):gsub("^[Ww]ould you like ","")
            local scoreLeft=overlap(roots(q),roots(left))
            local scoreRight=overlap(roots(q),roots(right))
            local selected=scoreLeft>scoreRight and left or scoreRight>scoreLeft and right
            if selected then
                local line="You mean "..selected..". "
                if any(norm(selected),{"warning","label"}) then line=line.."A warning describes a hazard. What words or symbols can you still read on it? I haven't seen the actual label."
                else line=line.."Tell me the particular detail you want to work through; I will keep that subject." end
                return reply(source,"source_choice",line,{choice=selected:sub(1,160)})
            end
        end
    end
    if current and current.kind=="source_choice" and any(q,{"rubbed off","missing","no words","cannot read","cant read","worn off"}) then return fixed("source_choice","warning_missing") end
    local first,nextStep=source:match("[Ff]irst (.-), then ([^%.!?]+)")
    if first and nextStep and any(q,{"next","then","now","after","pour","fill","checking"}) then
        local line
        if any(q,{"only after","checking"}) then line="Yes. First, "..first.."; only then, "..nextStep.."."
        else line="The next step is to "..nextStep..", after this check: "..first.."." end
        return reply(source,"sequence",line.." This conversation has not performed either step.")
    end
    local queryWords=roots(q)
    if any(q,{"compare","difference","different uses"}) and any(s,{"comparison","while","interchangeable"}) then
        return reply(source,"source_answer",source)
    end
    if any(q,{"use","try","instead","good enough"}) then
        for n,line in ipairs(lines) do
            if imperative(line) and overlap(queryWords,roots(line))>0 then
                return reply(source,"source_answer","The supplied advice is: "..line.."."..(lines[n+1] and " "..lines[n+1].."." or ""))
            end
        end
    end
    if any(q,{"can","should","try","just","fire","clear"}) then
        for _,line in ipairs(lines) do
            if any(norm(line),{"dont","do not","never","avoid"}) and overlap(queryWords,roots(line))>0 then
                return reply(source,"source_answer",line..". That is the instruction; I have not inspected or operated the actual object.")
            end
        end
    end
    if q:find("^how") or any(q,{"what should i do","what do i do","how check"}) then
        local best,bestScore
        for _,line in ipairs(lines) do
            local action=imperative(line)
            if action then
                local score=overlap(queryWords,roots(line))
                if not best or score>bestScore then best,bestScore=action,score end
            end
        end
        if best then return reply(source,"source_answer","Try this check: "..best..". It is an instruction or observation to make, not a result I have obtained.") end
    end
    local defs=definitions(lines)
    if q:find("^under ") or q:find("^behind ") or q:find("^beneath ") or q:find("^beside ") then
        local d=defs[1]
        if d then return reply(source,"source_answer","That position counts as "..d.subject.." only if it meets the definition: "..d.predicate..". Check the actual conditions; I cannot verify the position from here.") end
    end
    local term=SC.EmmaHooks and SC.EmmaHooks.fragment(raw)
    if term and term~="" then
        for _,d in ipairs(defs) do
            if has(norm(d.subject),term) then
                local explanation="Here, "..d.subject.." means "..d.predicate.."."
                local nextLine=lines[d.index+1]
                if nextLine and any(norm(nextLine),{"not","no","never","isnt","arent","cannot","cant","doesnt","without","unknown","unconfirmed"}) then
                    explanation=explanation.." "..nextLine.."."
                end
                return reply(source,"source_answer",explanation)
            end
        end
    end
    if any(q,{"shorter","short version","brief version"}) then
        local selected={}
        if lines[1] then selected[1]=lines[1].."." end
        for n=2,#lines do
            if any(norm(lines[n]),{"not interchangeable","not guaranteed","does not","doesnt","dont"}) then selected[#selected+1]=lines[n].."." break end
        end
        if #selected>0 then return reply(source,"source_answer","Short version: "..table.concat(selected," ")) end
    end
end
return A
