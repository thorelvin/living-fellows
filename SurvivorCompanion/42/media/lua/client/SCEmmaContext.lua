-- SPDX-License-Identifier: MIT
-- Foreground public-reference context, shared by the four terminal voices.
-- One bounded public reply, no saved user text, world scan or action dispatch.
require "SCEmmaReference"
require "SCEmmaAnswers"
require "SCEmmaMeaning"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local Q={} SC.EmmaContext=Q
local function norm(raw) return table.concat(SC.TerminalBrain.tokens(raw)," "):gsub("^emma ","") end
local function has(text,word) return (" "..text.." "):find(" "..word.." ",1,true)~=nil end
local function any(text,words) for _,word in ipairs(words) do if has(text,word) then return true end end return false end
-- A passage reader, rather than another topic dictionary. Only public output is
-- indexed. The source survives an excerpt answer, but a new subject, private
-- reply or idle timeout replaces it. Quoted advice is never a live observation.
local skip={}
for word in ("a an the i im am me my mine we our us you your it its that this those these they them their "..
    "he she his her is are was were be been being do does did dont doesnt didnt can cant cannot could "..
    "would should will wont may might must have has had of to for from in into on at by with without "..
    "and or but if then so as than not no yes yeah yep got just only even still really please about what which "..
    "who where when why how all any some one ones there here now more much very mean means explain "..
    "tell say says said reads read asking ask question want think though then too"):gmatch("%S+") do skip[word]=true end
local function stem(word)
    if #word>6 and word:sub(-4)=="less" then return word:sub(1,-5) end
    if #word>6 and word:sub(-3)=="ion" then return word:sub(1,-4) end
    if #word>5 and word:sub(-3)=="ing" then return word:sub(1,-4) end
    if #word>4 and word:sub(-2)=="ed" then return word:sub(1,-3) end
    if #word>4 and word:sub(-1)=="s" and word:sub(-2)~="ss" then return word:sub(1,-2) end
    return word
end
local equivalents={}
-- Ordinary word relations, shared across subjects. These select evidence;
-- they do not provide facts or license conclusions missing from the passage.
for _,group in ipairs({{"shut","closed","close","seal"},{"cool","cold","refrigerate","refrigerated","refrigeration"},
    {"person","people","group","party"},{"heavy","heavier","weight","load"},
    {"electricity","electrical","power","mains"},{"leave","departure","exit"},
    {"pop","burst"},{"move","stuck"},{"small","smaller","little"},{"eat","taste","food","meal","dinner"},
    {"rope","cord","string","lace","tie"},{"voice","accent","style","tone"},
    {"coat","raincoat","clothes","clothing","layer"},{"old","stale","dated","age"},
    {"queue","waiting","wait","turn"},{"noise","sound","vibration"},
    {"minute","time","hour"},{"spare","extra","buffer","margin"},
    {"ammunition","ammo","cartridge","round"},{"mouse","rodent","animal"}}) do
    for _,word in ipairs(group) do equivalents[stem(word)]=group end
end
local function words(text)
    local out,seen={},{}
    for word in norm(text):gmatch("%S+") do
        word=stem(word)
        if #word>=3 and not skip[word] and not seen[word] then out[#out+1]=word seen[word]=true end
        if #out>=120 then break end
    end
    return out,seen
end
local function framed(text)
    local t=norm(text)
    return any(t,{"card","notice","label","note","guide","report","leaflet","glossary","example","key"})
        and any(t,{"reads","says","gives","defines","copied","means"})
        or t:find(" means ",1,true) or t:find(" defines ",1,true)
        or t:find(" is a ",1,true) or t:find(" is an ",1,true) or t:find(" is the ",1,true)
        or any(t,{"i meant","when i said","i used","do you mean","would you like","the word was","explanation of the word"})
end
local function savePassage(session,reply,text)
    local source=reply.publicSource or text
    local unresolved={fallback=true,fallback_echo=true,did_you_mean=true,followup_clarify=true,deflect=true,steer=true}
    if unresolved[reply.intent or reply.layer] and session.publicPassage then return end
    local nativeLayers={rule=true,first=true,expect=true,spine=true,["return"]=true,["repeat"]=true,
        reflect=true,recall=true,mash=true,safety=true,hook=true,reference=true,role=true}
    local owned=reply.reference==true or reply.category=="lore"
        or reply.intent and SC.TerminalBrain.hasHandler(reply.intent) or nativeLayers[reply.layer]
    session.publicPassage={text=source:sub(1,900),framed=framed(source),selected=reply.publicSelection,
        repeated=reply.publicRepeat==true,
        queryKey=reply.publicQueryKey,
        structured=not reply.publicSource and owned==true,
        turn=session.turns or 0,at=SC.TerminalConversation.clock(session)}
end
local function livePassage(session)
    local c=session.publicPassage
    if not c or (session.turns or 0)-(c.turn or 0)>3 then return nil end
    local now=SC.TerminalConversation.clock(session)
    if now and c.at and now-c.at>SC.TerminalConversation.MAX_IDLE_MS then session.publicPassage=nil return nil end
    return c
end
local function wordMatch(word,set)
    if set[word] then return 2 end
    for _,v in ipairs(equivalents[word] or {}) do if set[stem(v)] then return 1 end end
    if #word>=4 then
        local found
        for value in pairs(set) do
            if #value>=4 and value:sub(1,1)==word:sub(1,1) and math.abs(#value-#word)<=1
                and SC.TerminalBrain.distance(word,value,1)<=1 then
                if found then return 0 end
                found=value
            end
        end
        if found then return 1 end
    end
    return 0
end
function Q.ground(session,raw,allowPlain)
    local c=livePassage(session)
    if not c then return nil end
    if c.structured and not allowPlain then return nil end
    if not c.framed and SC.EmmaHooks.preferred(session,raw) then return nil end
    local text=norm(raw)
    local request=text:gsub("^please ",""):gsub("^can you ",""):gsub("^could you ",""):gsub("^would you ","")
    local action={open=true,close=true,lock=true,unlock=true,refuel=true,send=true,treat=true,
        activate=true,switch=true,start=true,run=true,queue=true,delete=true,reset=true}
    if action[request:match("^%S+")] and #SC.TerminalBrain.tokens(text)>1
        and not request:find("^start with ") and not request:find(" what$") then return nil end
    -- World readings, personal memory, access and checked requests retain their
    -- own parsers. Neither an excerpt nor a quoted instruction executes them.
    if text=="status" or text=="exit" or text=="bye" or text=="power"
        or any(text,{"remember","forget","call me","my name","drawer","password","send medic",
            "refuel generator","factory reset","who are you","who is here","who is hurt","who is best",
            "what are you","your name","who made you","where am i",
            "chain of command","who is in command","who is in charge"})
        or text=="time" or text=="date" or text=="the time please" or text:find("^what time")
        or text:find("^how much ") or text:find("^how many ") or text:find("^how is ")
        or text:find("^im ") or text:find("^i am ") or #SC.TerminalBrain.tokens(text)>11 then return nil end
    local query=words(text)
    local _,sourceWords=words(c.text)
    local overlap,matched=0,0
    for _,word in ipairs(query) do
        local score=wordMatch(word,sourceWords)
        overlap=overlap+score if score>0 then matched=matched+1 end
    end
    if #query>2 and matched/#query<.5 and not any(text,{"it","that","those","them"})
        and not text:find("^but ") and not text:find("^so ") and not text:find("^then ") then return nil end
    if overlap==0 and not c.framed and not c.selected then return nil end
    local anaphor=any(text,{"it","that","those","them"})
    local continuation=(c.selected or #query==0 or anaphor) and (#query<=2 or anaphor
        or text:find("^but ") or text:find("^so ") or text:find("^then ") or text:find("^even "))
    if overlap==0 and not continuation then return nil end
    -- A complete new indexed subject wins over an unrelated old quotation.
    local target=SC.EmmaReference.find(text)
    local correction=any(text,{"meant","mean","dont mean","not about"}) or text:find("^not ") or text:find("^no ")
    if overlap==0 and target and target.kind=="reference" and not correction and not anaphor then return nil end
    local sentences={}
    for sentence in c.text:gmatch("[^%.!?]+[%.!?]?") do
        sentence=sentence:match("^%s*(.-)%s*$")
        if #sentence>1 then sentences[#sentences+1]=sentence end
        if #sentences>=12 then break end
    end
    local best,bestScore=1,-1
    local missing=any(text,{"where","which","when","who"})
    for n,sentence in ipairs(sentences) do
        local _,set=words(sentence)
        local score=0
        for _,word in ipairs(query) do score=score+wordMatch(word,set) end
        local t=norm(sentence)
        if score>0 and (has(t,"means") or has(t,"is a") or has(t,"is an")) then score=score+.5 end
        if missing and any(t,{"no","not","unknown","unconfirmed","doesnt","cannot"}) then score=score+2 end
        if overlap==0 and c.selected==n then score=score+.25 end
        if score>bestScore then best,bestScore=n,score end
    end
    -- Retain neighbouring qualifications: a positive sentence must not lose a
    -- following prohibition, unknown finding or condition during extraction.
    local selected={sentences[best] or c.text}
    if best>1 then table.insert(selected,1,sentences[best-1]) end
    if sentences[best+1] then selected[#selected+1]=sentences[best+1] end
    if overlap==0 and sentences[best+2] then selected[#selected+1]=sentences[best+2] end
    local excerpt=table.concat(selected," ")
    if any(text,{"number","numbered"}) and any(norm(c.text),{"headings","list","choices"}) then
        local list=c.text:match(":%s*([^%.]+)")
        if list then
            local numbered={}
            list=list:gsub("%s+and%s+",", ")
            for value in list:gmatch("[^,]+") do
                value=value:match("^%s*(.-)%s*$")
                if #value>0 and #value<=60 and #numbered<6 then numbered[#numbered+1]=tostring(#numbered+1)..". "..value end
            end
            if #numbered>1 then excerpt=table.concat(numbered,"; ") end
        end
    end
    local prefix=c.framed and "In that source: " or "In this context, I meant: "
    local suffix=""
    if any(norm(c.text),{"unknown","unconfirmed","no","not","missing"}) then
        suffix=suffix.." I cannot guarantee details that source does not establish. They remain unknown."
    end
    if text:find("^yeah ") or text:find("^yes ") or text:find("^no ") and has(text,"meant") then prefix="Understood. "..prefix end
    local queryKey=5381 for at=1,#text do queryKey=(queryKey*33+text:byte(at))%2147483647 end
    local repeated=c.selected==best and c.queryKey==queryKey
    if repeated then
        if c.repeated then return nil end
        suffix=suffix.." That is the complete surviving statement on this point. Which part needs explaining: the term, the instructions, or a detail missing from the source?"
    end
    return {kind="public_passage",lines={prefix..excerpt..suffix},publicSource=c.text,publicSelection=best,publicRepeat=repeated,publicQueryKey=queryKey}
end
local function state(session) return session.foregroundReference end
local function current(session)
    local c=state(session)
    if type(c)~="table" or type(c.kind)~="string" or #c.kind>40 then return nil end
    local now=SC.TerminalConversation.clock(session)
    if c and (not now or not c.at or now-c.at<=SC.TerminalConversation.MAX_IDLE_MS)
        and (session.turns or 0)-(c.turn or 0)<=3 then return c end
end
-- Physical guidance is checked against the installed reference's source paths.
-- Direct pressure / secure dressing / circulation: Red Cross, Wounds and
-- Bleeding (Life-Threatening External), reviewed 2026-11-15:
-- https://www.redcross.org/take-a-class/resources/learn-first-aid/bleeding-life-threatening-external
-- Fever/rest: https://www.nhs.uk/symptoms/fever-in-adults/
-- Suspect cans: https://ask.fsis.usda.gov/article/Is-food-in-damaged-cans-dangerous
-- Enclosed generators: https://www.cpsc.gov/Safety-Education/Safety-Guides/Carbon-Monoxide-Home/Generators-and-Engine-Driven-Tools
Q.DATA={
    reserve="A reserve is a stored backup supply. That can mean fuel or drinking water; the record must say which. An empty reserve does not explain why it was not replaced.",
    reserve_empty="The reserve is empty according to that record. I do not know why the supply was not replaced; its cause is not recorded. A shortage is not an explanation.",
    reserve_replace="If you mean fuel, find gasoline at a station or collect it from a suitable vehicle into an appropriate container. If you mean water, collect and treat a safe supply. I cannot refill either remotely.",
    fever="A fever means a raised body temperature, higher than normal. It is a symptom, not a diagnosis of its cause.",
    fever_cause="A fever alone does not prove the cause. Infection is one possibility, but I cannot tell which illness, if any, from that symptom alone.",
    fever_help="Rest somewhere safe, keep drinking water available and seek medical assessment if the fever is severe or persists. This terminal cannot examine you.",
    gap="A blank interval is a gap in the log: missing entries between records that survived. It does not establish what happened during that time, or that I forgot a particular person.",
    gap_restore="The gap is in the log; it does not prove that I forgot you. I cannot know what the missing entries contained. Another surviving copy might help; recovery is not guaranteed.",
    cordon="A cordon is a controlled barrier around an area, often a checkpoint or perimeter. I do not know whether it is still there now; that old note is not a live observation.",
    quarantine="Quarantine restricts movement or separates people to reduce the spread of illness. I do not know who ordered it: the authority is not named in that note. It gives no diagnosis or verified present condition.",
    operator="An operator is the person who used the terminal. That entry describes an earlier anonymous visitor; their identity and destination are unknown, not recorded in the available log.",
    operator_later="I do not know who came afterwards or whether that visitor returned. The available log has no record of their return, destination or present whereabouts.",
    sessions="The surviving session log records earlier visits, but no message text survives. I do not know what they discussed; those subjects are not recorded in the surviving entries.",
    maker="I was built by people. That particular record has no surviving builder or manufacturer name; an unknown entry does not identify who assembled this desk. My programme's county history is a separate file.",
    relay="A communications relay is an intermediate station that receives and passes on a signal. I do not know why it stopped; the cause and repair status are unknown in this record.",
    cycle="The cycle means the repeated sequence just described: run a check, then wait for an instruction, then check again. Repetition is part of the routine; boredom is not a measured machine condition.",
    dry_pump="Dry means the water pump did not deliver water in that note. It does not prove the well is empty or the pump is broken. Inspect the actual supply and mechanism before deciding.",
    pump="For a stuck water-pump handle, stop forcing it. Check the handle, blockage and water supply. I cannot identify its failure from that sentence; this is about a water pump, not a gun.",
    water_empty="No drinking water left is urgent. Find a usable container and a safe water source; collect rain or recover water from available fixtures, then treat it before drinking.",
    rain="Rain can provide water if you have a suitable clean collection container. Treat collected water before drinking; clear-looking water is not proof that it is safe.",
    container="Use a suitable clean container for collected water and keep treated water separate. A heat-safe vessel is needed if you boil it; not every bottle tolerates heat.",
    water_safe="Use known clean drinking water. Clear water is not necessarily safe: contamination need not be visible. Boil an uncertain supply in a suitable heat-safe container or use the proper purification tablets. Check the source before drinking.",
    water_why="Your body needs clean water; dehydration and contaminated water can both make you ill. Clear appearance does not establish that water is clean or safe to drink.",
    pressure="Press firmly directly on the bleeding wound with a clean cloth or dressing. Keep steady pressure. Bleeding that will not stop needs medical help; a terminal cannot judge its severity.",
    cloth="Use the cleanest suitable cloth you can find, such as clean clothing or a shirt torn into strips. Prepare a clean dressing; dirty rags need proper cleaning rather than a new name.",
    snug="Secure the dressing firmly enough to maintain pressure, not too tight to impair circulation. Check the hand or foot beyond it; numbness, altered feeling or a cold extremity needs attention. Keep checking for renewed bleeding.",
    wet_dressing="Keep direct pressure on the wound. A cloth soaked with blood does not mean the bleeding is controlled. Get medical help for continued bleeding; have clean dressing material ready.",
    no_water="If there is no water to clean those rags, use the cleanest suitable fresh cloth or clothing available and find a clean water supply. Do not pretend the dirty rags have become sterile.",
    shallow="A shallow cut still needs bleeding controlled and a clean dressing. Inspect the actual wound; depth described in a typed sentence does not establish that it is harmless.",
    indoor="Keep the generator outside, outdoors and away from openings. Exhaust fumes make indoor use dangerous. An open window does not make a kitchen, room or enclosed shed safe for it.",
    refill="Switch the generator off before refuelling and let it cool. Bring compatible gasoline in a suitable fuel container and use its filling options. I can explain the operation; I cannot fill its tank remotely.",
    start="An empty generator needs compatible fuel, but fuel is not the only possible reason it will not start. Check its condition, operating knowledge and actual controls. Operate it outdoors; inspect rather than guessing a fault.",
    funnel="A fuel funnel directs fuel into the filler opening. Switch the engine off before refuelling, use a suitable fuel container and avoid spills. A funnel is not a water filter and fuel is never drinking water.",
    trap_bait="For rabbit traps, vegetable bait such as carrot or cabbage can work. Match the bait to the animal and trap, place it in suitable habitat and keep the checking route safe.",
    trap_check="Return later and inspect the trap regularly for an animal, bait and damage. Time and the animal's active hours matter; a trap does not promise an instant catch.",
    spoiled="Do not eat meat that smells spoiled or food from a bulging can. Cooking longer does not make suspect spoiled food reliably safe. Choose food known to be sound instead.",
    food_find="Look for other food: intact sealed supplies, unspoiled fresh food or dry goods in homes, cupboards or food shops. Fishing, foraging or trapping are alternatives. I cannot invent stock on a shelf.",
    scratch="Not necessarily doomed. A scratch from the dead can carry Knox infection under the usual rules, but I cannot tell your outcome from that word. Clean and dress the wound and monitor your actual condition. Settings can change transmission.",
    smoke="Leave the smoke-filled room now and get to fresh air by a clear exit. Do not stay another minute to finish this conversation. Keep people out until the source and danger are resolved.",
    route="I cannot name a currently safe direction from here. Stay behind cover, check the next stretch and keep an exit. Use landmarks or retrace a route you know; without a map, do not invent a shortcut.",
    rest="Exhaustion calls for rest somewhere safe. A bed is preferable; a dry floor or other resting place still needs shelter and a way out. Use the actual rest or sleep option available, and do not settle beside a threat.",
    sleep="If you cannot sleep, first find a quieter, safer place to rest. Noise outside may be a threat to assess, not something to ignore. Keep an exit and wait until it is safe to settle.",
    damage="That check reports a damaged log entry or display character. It does not prove the whole machine is dying. I can still read the surviving line. I cannot confirm a repair; no repair is recorded.",
    radio="There is no connected radio interface in that record. I cannot tune or listen through an absent receiver, or invent a station frequency. Use a working radio's controls to discover what is transmitting.",
    inventory="That is a recorded inventory, not a view into your current backpack. The count may be old. Ask how many food tins or water bottles to inspect the available record.",
    enough="Whether those supplies are enough depends on how many people need them, portions, water use and consumption. I cannot promise a duration without those amounts and needs.",
    quick="Quick supply check: people first, then drinking water, food, wounds and a safe exit. Check what you actually have before planning the next search.",
    slow="Slowly: check people and wounds first. Then count drinking water and food. Finally choose a safe route and a reserve. One check at a time is sufficient.",
    outside="I have no live view outside and cannot see your exact position. Tell me what you can observe; a record is not a current street survey.",
    time_unknown="I cannot tell the current time from a terminal with no reliable clock. This is a 1993 record; the exact date, day and hour remain unknown without a working clock or a recent dated entry.",
    affection="No particular person was identified. That was a line about affection, not a report naming someone you should meet.",
    injury_no="Understood. You said you are not hurt. We can turn to food, drinking water or another immediate need.",
    alone="You are alone, just you; understood. You can prefer solitude. It still helps to plan food, water and a safe way out for yourself.",
    station_record="The last recorded check says power available and no connected radio. I have no live view outside. This is the recorded status, not a new observation.",
    ammo="No, not any bullet fits. Match ammunition and any magazine to the particular pistol model. The M9 uses 9mm; other pistols can use .45 or .44. Check the actual firearm before loading it.",
    trapping="Trapping animals for food, understood. Choose the right trap, bait and habitat and inspect it later. This is about catching an animal, not confining a person.",
    airborne="Airborne spread is unknown in that record: no verified finding is supplied. I cannot confirm transmission through the air, and an unknown finding does not mean a definite no or rule it out.",
    origin="The first case and origin are unverified in the available reports. No confirmed location or cause is established. I cannot confirm proof that those records do not contain.",
    initials="Those letters form the name EMMA. An acronym needs a recorded expansion; the letters alone do not supply one. I will not invent a longer name from them.",
    human="There is no human inside this terminal. I am a local computer programme. I can make conversation; that does not put a person behind the screen.",
    lonely="I am a machine, but I can keep you company in conversation. You can talk and I will be here to answer; that is what this desk can offer.",
    machine_name="You can use a conversational nickname for me. The programme's name stays the same; a nickname does not rewrite the machine.",
    name_kept="Yes. Still the same programme, whatever nickname we use in this conversation. The original identity remains underneath it.",
    imagination="I could imagine a face, but it would be a guess. I cannot see you. Give me a description if you want the picture to resemble you.",
    appearance_accuracy="I cannot verify an imagined face. You can compare it with yourself or give a description; you know what I cannot see.",
    appearance_description="Description noted for this exchange. That gives me something to work from; it is what you told me, not something I saw.",
    learning="I can use a correction and the context of this conversation to understand your intended meaning. Spelling and typos can be worked around; if the meaning is unclear, I should ask. That does not permanently rewrite my programme.",
    computer_manner="Courtesy is part of this programme's conversational manner. Polite words make a difficult exchange easier. That is design and habit in a machine, not proof of a hidden person.",
    computer_voice="A text voice has phrasing and style; an accent would be something you imagine while reading it. I have no verified geographic origin for that imagined voice in this record.",
    ties_bundle="For a light bundle, sturdy cloth torn into strips can serve as a tie if it is strong and long enough. If strips are too short, make the bundle smaller or join suitable lengths securely. Check the tie before carrying it.",
    ties_boot="For a temporary boot lace, suitable string or cord can hold the fastening. Retie a loose knot and check the fit: secure and snug, not so tight that it pinches. Check that the tie is strong enough and stays fastened.",
    tool_fit="Use a screwdriver or bit that fits the screw head correctly. Bigger is not automatically better. Stop if it slips or the head is stripped; inspect the grip and damage rather than applying blind force.",
    screw_force="Do not hit a screw as though it were a nail. That can damage the head or surrounding material. Stop forcing it and inspect the actual fastening.",
    vibration="Vibration is back-and-forth movement or oscillation. Sound carries that disturbance through air or other material; a wall can reduce it without making every sound disappear.",
    quiet_voice="Yes. A softer, lower voice makes less noise. It can reduce what carries; it does not guarantee that nobody can hear you.",
    bulb="A light bulb is the part of an electric lamp that produces light. A dark bulb may lack power or have failed; darkness alone does not identify the fault.",
    computer_mouse="A computer mouse is a handheld pointing device for controlling a pointer or cursor, not an animal. Whether one is needed depends on the interface; a text terminal can use a keyboard. That does not establish which hardware is connected here.",
    name_case="Capital and lowercase letters are ways to write the same name here. EMMA is normally printed in capitals, but ordinary questions do not need formal spelling or uppercase letters for me to understand them.",
    shelter="Shelter helps against weather, rain, cold and exposure. A door helps control entry or access, and a way out matters if danger enters. Those are useful features, not a guarantee that a room is safe.",
    extinguish="You mean putting the flame out: extinguishing it. What is burning, and how large is the flame? The material matters; I cannot treat every fire as a candle.",
    candle_out="For a candle, use a suitable candle snuffer to extinguish the flame. Keep the candle stable and check that it has stopped burning before leaving it.",
    bulb_replacement="Choose a replacement bulb compatible with the lamp. Switch it off and let it cool before handling it. A dark lamp still needs its power supply checked; a new bulb is not proof of working wiring.",
    computer_text="Both plain questions and commands are useful. Ask a question in ordinary words; a command that operates something still needs its proper controls and checks. You do not need a formal way of talking to me.",
    dry_storage="Keep dry food in a suitable closed container on a dry shelf. Protect it from moisture and pests. A shelf alone does not keep the contents dry or sound.",
    cold_meal="Yes, no stove is needed to eat a meal that is already suitable and safe to eat cold. That describes serving it without heat; it does not certify unknown or spoiled food as safe.",
    hot_appearance="It could still be hot. A normal appearance does not prove that a handle is cool or safe to hold; it need not glow. I cannot judge its temperature from that description.",
}
local function contextOf(text)
    local t=norm(text)
    if has(t,"are you hurt") then return "injury_question" end
    if has(t,"inside or outside") then return "location_question" end
    if has(t,"quick version") then return "quick_question" end
    if has(t,"how many people") then return "people_question" end
    if has(t,"airborne") or has(t,"airborne spread") then return "airborne" end
    if has(t,"origin report") or has(t,"origin reports") then return "origin" end
    if has(t,"blank interval") or has(t,"missing interval") then return "gap" end
    if has(t,"fever") then return "fever" end
    if has(t,"relay") then return "relay" end
    if has(t,"quarantine") then return "quarantine" end
    if has(t,"cycle") and any(t,{"check","wait","sequence"}) then return "cycle" end
    if has(t,"smoke") and any(t,{"room","filling","stove"}) then return "smoke" end
    if any(t,{"garbled","damaged log","damaged entry","flickering"}) then return "damage" end
    if has(t,"cordon") and any(t,{"checkpoint","barrier","note"}) then return "cordon" end
    if any(t,{"no radio","no connected radio","no radio interface","radio absent"}) then return "unavailable_radio" end
    if any(t,{"no working clock","no reliable clock","clock is not"}) then return "time_unknown" end
    if has(t,"reserve") then return "reserve" end
    if has(t,"machine s damage") or has(t,"machine damage") or has(t,"broken terminal") then return "damage" end
    if has(t,"water filter") and has(t,"fuel funnel") then return "filter_choice" end
    if has(t,"water barrel") and has(t,"fuel drum") then return "container_choice" end
    if has(t,"water pump") or has(t,"pump is dry") then return "pump" end
    if has(t,"generator") then return "generator" end
    if any(t,{"rabbit","rabbits","trapping","catching food"}) then return "trapping" end
    if any(t,{"dressing","dressings","cut","wound","bleeding","rags"}) then return "dressings" end
    if any(t,{"exhaustion","exhausted","sleep","bed"}) then return "rest" end
    local missing=any(t,{"unknown","anonymous","missing","no name","no names","no message","no text","does not record","no surviving","no identifying"})
    if missing and (has(t,"earlier sessions") or has(t,"session log")) then return "sessions" end
    if missing and any(t,{"anonymous","earlier visitor","previous session","operator gave"}) then return "operator" end
    if missing and (has(t,"builder") or has(t,"manufacturing entry")) then return "maker" end
    if has(t,"recorded inventory") then return "inventory" end
    if has(t,"drinking water") then return "water" end
    if has(t,"spoiled") or has(t,"bulging can") then return "food" end
end
function Q.observe(session,reply,voice)
    if reply.private or reply.sensitive or reply.careDetected then
        session.publicPassage=nil
        session.foregroundReference=reply.foregroundKind and not reply.careDetected
            and {kind=reply.foregroundKind,text="",turn=session.turns or 0,at=SC.TerminalConversation.clock(session)} or nil
        return
    end
    local lines=reply.lines or {}
    if voice then lines={} for _,row in ipairs(reply.rows or {}) do lines[#lines+1]=row.text end end
    local text=table.concat(lines," "):sub(1,900)
    savePassage(session,reply,text)
    local topic=not voice and SC.TerminalConversation.latest(session)
    local old=current(session)
    local kind=reply.foregroundKind or reply.referenceState and reply.referenceState.id
        or reply.intent=="love" and "affection"
        or topic and topic.kind=="guide" and SC.EmmaFollowups.subject(topic) or contextOf(text)
    if not kind then
        if reply.intent~="thanks" and reply.intent~="ack" then session.foregroundReference=nil end
        return
    end
    local said=norm(text)
    local supply=has(said,"stored generator fuel") and "fuel"
        or has(said,"stored drinking water") and "water"
        or old and old.kind==kind and old.supply
    session.foregroundReference={kind=kind,text=text,supply=supply,turn=session.turns or 0,at=SC.TerminalConversation.clock(session),
        facet=reply.referenceState and reply.referenceState.facet,
        discussion=reply.discussion==true,
        choice=reply.choice,
        injuryQuestion=text:find("Are you hurt",1,true)~=nil,
        guideQuestion=has(norm(text),"do you want") and has(norm(text),"dressing"),
        waterQuestion=has(norm(text),"how much drinking water"),
        locationQuestion=has(norm(text),"inside or outside"),
        quickQuestion=has(norm(text),"quick version")}
    -- Explicit questions can have no topic noun otherwise.
end
local function row(kind,key) return {kind=kind,key=key or kind} end
local relatedWords={
    reserve={"reserve","supply","empty","replace","refill","drink"},
    fever={"fever","infected","infection","temperature","cause","now"},
    gap={"blank","gap","forgot","back","restore","missing","interval"},
    cordon={"cordon","barrier","checkpoint","still","there"},
    quarantine={"quarantine","ordered","authority","illness"},
    relay={"relay","signal","stopped","repair"},cycle={"cycle","again","bored","routine"},
    operator={"operator","visitor","after","return","returned","destination","now"},
    sessions={"sessions","session","before","about","earlier"},maker={"maker","builder","made","constructed","records"},
    pump={"pump","water","handle","stuck","dry","broken"},
    generator={"generator","fuel","fill","refuel","running","start","kitchen","shed","window","indoors"},
    trapping={"trap","traps","rabbit","rabbits","bait","check","inspect","meant","people"},
    dressings={"cut","wound","bleeding","blood","dressing","cloth","rag","rags","tight","snug","water","pressure","stop"},
    food={"food","eat","tins","boiled","boil","cook","longer","smells","spoiled"},
    smoke={"smoke","stay","minute","room","leave"},rest={"bed","floor","rest","sleep","noise","outside","exhausted"},
    damage={"damaged","damage","broken","fixed","repair","dying","talk","flickering"},
    airborne={"air","airborne","breath","definite","no","unknown"},origin={"first","case","proof","origin"},
    bite={"bite","scratch","doomed","turn"},unavailable_radio={"radio","tune","set","frequency","report","outside"},
    firearms={"gun","pistol","ammo","ammunition","bullet","bullets","fits","loud"},
    water={"water","rain","container","bottle","clear","clean","drink","empty","zero","none"},
    inventory={"inventory","enough","last","us"},time_unknown={"time","date","day","clock"},
    solitude={"alone","prefer","nobody"},quick={"slower","slow"},
}
local function related(c,text)
    if any(text,{"it","that","those","them","they"}) then return true end
    if text=="why" or text=="how" or text=="where" or text=="what" or text=="who"
        or text=="yes" or text=="no" or text=="yeah" or text=="yep" or text=="nobody" then return true end
    if c.kind:find("_question$",1) then return true end
    return any(text,relatedWords[c.kind] or {})
end
local function choose(c,text)
    local kind=c and c.kind
    if not kind then return nil end
    if kind=="injury_question" and text=="no" then return row("food","injury_no")
    elseif kind=="location_question" and any(text,{"outside","inside"}) then return row("route")
    elseif kind=="people_question" and any(text,{"nobody","none","zero","prefer"}) then return row("solitude","alone")
    elseif kind=="solitude" and any(text,{"prefer","alone"}) then return row(kind,"alone")
    elseif kind=="quick_question" and any(text,{"yes","yep","yeah","ja"}) then return row("quick","quick")
    elseif kind=="quick" and has(text,"slower") then return row(kind,"slow")
    elseif kind=="reserve" then
        if any(text,{"why","empty"}) then return row(kind,"reserve_empty") end
        if any(text,{"replace","refill","replenish"}) then return row(kind,"reserve_replace") end
        if any(text,{"drink","drinking"}) then
            if c.supply=="fuel" then return {kind=kind,lines={"Do not drink fuel. That reserve is generator fuel, not drinking water. Find a known clean water supply instead."}} end
            return row("water","water_safe")
        end
        if any(text,{"reserve","what","supply"}) then return row(kind) end
    elseif kind=="fever" then
        return row(kind,any(text,{"infected","no","cause"}) and "fever_cause"
            or any(text,{"now","help","do"}) and "fever_help" or "fever")
    elseif kind=="gap" then return row(kind,any(text,{"back","restore","repair","forgot"}) and "gap_restore" or "gap")
    elseif kind=="cordon" or kind=="quarantine" or kind=="relay" or kind=="cycle" then return row(kind)
    elseif kind=="operator" then return row(kind,any(text,{"after","return","came","now"}) and "operator_later" or "operator")
    elseif kind=="sessions" or kind=="maker" then return row(kind)
    elseif kind=="pump" then
        if has(text,"where") and has(text,"water") then return {kind="water",reference="water",facet="find"} end
        return row(kind,any(text,{"dry","broken","empty"}) and "dry_pump" or "pump")
    elseif kind=="generator" then
        if any(text,{"kitchen","inside","indoors","shed","window","enclosed"}) then return row(kind,"indoor") end
        if any(text,{"fill","refuel","running","can","tank"}) then return row(kind,"refill") end
        if any(text,{"start","why"}) then return row(kind,"start") end
    elseif kind=="trapping" then
        if any(text,{"not people","what i meant","that is what i meant","thats what i meant"}) then return row(kind,"trapping") end
        if any(text,{"bait","food"}) then return row(kind,"trap_bait") end
        if any(text,{"when","check","inspect"}) then return row(kind,"trap_check") end
    elseif kind=="dressings" then
        if any(text,{"tight","snug"}) then return row(kind,"snug") end
        if any(text,{"no water","without water"}) then return row(kind,"no_water") end
        if any(text,{"blood","dripping","wet","bleeding"}) then return row(kind,"wet_dressing") end
        if any(text,{"shallow","deep"}) then return row(kind,"shallow") end
        if has(text,"more cloth") then return row(kind,"wet_dressing") end
        if any(text,{"stop it","stop this"}) then return row(kind,"pressure") end
        if any(text,{"cloth","shirt","rag","rags","wash","clean","yeah","yes"}) then return row(kind,"cloth") end
    elseif kind=="food" then
        if any(text,{"eat","what","no tins"}) then return row(kind,"food_find") end
        if any(text,{"boil","boiled","longer","cook","smells","bulging"}) then return row(kind,"spoiled") end
    elseif kind=="smoke" then return row(kind)
    elseif kind=="rest" and any(text,{"sleep","noise","outside","bed","floor","rest","exhausted"}) then
        return row(kind,any(text,{"sleep","noise","outside"}) and "sleep" or "rest")
    elseif kind=="damage" then return row(kind)
    elseif kind=="airborne" or kind=="origin" then return row(kind)
    elseif kind=="bite" and any(text,{"doomed","turn","scratch"}) then return row(kind,"scratch")
    elseif kind=="unavailable_radio" then
        if has(text,"outside") then return row(kind,"outside") end
        if has(text,"report") and has(norm(c.text),"power available") then return row(kind,"station_record") end
        return row(kind,"radio")
    elseif kind=="firearms" and any(text,{"bullet","fits","ammo"}) then return row(kind,"ammo")
    elseif kind=="water" then
        if any(text,{"clear","safe","drink"}) then return row(kind,"water_safe") end
        if any(text,{"zero","none","empty","no water"}) then return row(kind,"water_empty") end
        if has(text,"rain") then return row(kind,"rain") end
        if has(text,"container") then return row(kind,"container") end
    elseif kind=="inventory" and any(text,{"enough","last","us"}) then return row(kind,"enough")
    elseif kind=="time_unknown" and any(text,{"time","date","day"}) then return row(kind)
    elseif kind=="filter_choice" then
        if has(text,"funnel") then return row("generator","funnel") end
        if has(text,"filter") then return row("water","water_safe") end
        if any(text,{"it","use"}) then return {kind=kind,lines={"Which one do you mean: the water filter or the fuel funnel? They have different uses."}} end
    elseif kind=="container_choice" then
        if text=="water" then return row("water","water_safe") end
        if any(text,{"it","safe"}) then return {kind=kind,lines={"Which container: the water barrel or the fuel drum? Do not drink fuel. Water still needs a safe source and treatment."}} end
    end
end
local independent={fever="fever",cordon="cordon",quarantine="quarantine",quarentine="quarantine",
    reserve="reserve",relay="relay",exhausted="rest",scratched="scratch",flickering="damage"}
local function explicit(text)
    local spec
    if any(text,{"wont stop bleeding","will not stop bleeding","hand cut","arm bleeding","dripping blood","help with the cut"}) then
        spec=row("dressings","pressure") spec.private=true
    elseif any(text,{"gnerator","generator help"}) then spec={kind="generator",reference="generator",facet="what"}
    elseif any(text,{"meat smells","bulging can","can bulging"}) then spec=row("food","spoiled")
    elseif any(text,{"catch rabbits","rabbits food","traping food"}) then spec={kind="trapping",reference="trapping",facet="use"}
    elseif any(text,{"why blood loss","blood loss kills"}) then spec={kind="dressings",lines={"Blood loss can deprive the body of oxygen and circulation. Control bleeding with direct pressure and a clean dressing; ongoing bleeding needs medical help."}}
    elseif text=="scratched" then spec=row("bite","scratch") spec.private=true
    elseif any(text,{"which way is safe","dont have a map","do not have a map","nowhere safe"}) then spec=row("route")
    elseif has(text,"noise") and has(text,"outside") then spec=row("rest","sleep")
    elseif has(text,"first case") or has(text,"real proof") then spec=row("origin")
    elseif has(text,"human in there") then spec=row("human")
    elseif has(text,"lonely machine") then spec=row("lonely")
    elseif has(text,"letters mean") then spec=row("initials")
    elseif has(text,"pistol ammo") then spec=row("firearms","ammo")
    end
    if spec then spec.force=true end
    return spec
end
local function conversational(session,raw,text,c,title)
    local passage=livePassage(session)
    local source=passage and norm(passage.text) or ""
    local function private(kind,key) local spec=row(kind,key) spec.private=true return spec end
    local function sourced(kind,key) local spec=row(kind,key) spec.publicSource=passage and passage.text return spec end
    local offered=passage and (passage.text:match("the ([%a]+)'s part")
        or passage.text:match("as the ([%a]+) for this conversation")
        or passage.text:match("play the ([%a ]+) in this conversation"))
    if offered and any(text,{"reporting","sworn","appointed","ready","needs","need"}) then
        return {kind="role",role=offered,private=true,lines={offered..". We can use that title in this exchange. It is not authenticated office. For a community that needs food or other supplies, state the item and quantity so we can draft a request here."}}
    end
    if title and c and c.kind=="role" and text:find("^no ") then return {kind="role",private=true,lines={"Understood. We can talk directly, just us. I am not assuming a cabinet, staff or a working office behind the title."}} end
    if title and any(text,{"draft the request","draft a request","requisition","make it official","on screen"}) then
        return {kind="role",private=true,lines={"Example requisition: item needed; quantity; reason; intended recipient. Tell me those details and we can write the request here. No stock or delivery arrangement is implied, and nothing is transmitted."}}
    end
    local callSign=has(source,"call sign") and tostring(raw):match("[Oo]perator ([%a%d%-]+) [Cc]alling")
    if callSign and #callSign<=16 then return {kind="call_sign",callSign=callSign,private=true,
        lines={callSign..". That is your declared call sign for this conversation. No radio link has been established; this is text here."}} end
    if session.conversationCallSign and has(text,"call sign") and any(text,{"repeat","what","my"}) then
        return {kind="call_sign",private=true,lines={"Your declared call sign in this exchange: "..session.conversationCallSign..". This does not authenticate a radio operator or transmit anything."}}
    end
    if has(text,"bulb") and has(source,"bulb") then return row("light","bulb") end
    if (c and c.kind=="light" or has(source,"bulb")) and any(text,{"replacement","replace","lamp"}) then return row("light","bulb_replacement") end
    if has(source,"pointing device") and any(text,{"mouse","rodent","needed","necessary"}) then return row("computer_inputs","computer_mouse") end
    if c and c.kind=="computer_inputs" and any(text,{"needed","necessary","keyboard"}) then return row("computer_inputs","computer_mouse") end
    if c and c.kind=="name_case" and any(text,{"questions","commands"}) then return row("name_case","computer_text") end
    if has(text,"capitals") and has(source,"name") or c and c.kind=="name_case" and (any(text,{"matter","name","case","emma"}) or text=="it is then") then return row("name_case","name_case") end
    if has(source,"shelter") and has(text,"protect") then return row("shelter","shelter") end
    if has(source,"rather than") and has(text,"putting out") then return row("extinguish","extinguish") end
    if c and c.kind=="extinguish" and has(text,"candle") then return row("extinguish","candle_out") end
    if any(source,{"dry food","dry goods"}) and any(text,{"shelf","store","storage","container"}) then return row("food","dry_storage") end
    if has(source,"cold meal") and has(text,"stove") then return row("food","cold_meal") end
    if any(source,{"hot","temperature"}) and any(text,{"looks normal","appearance"}) then return sourced("heat","hot_appearance") end
    if c and c.kind=="map" and any(text,{"no symbols","no markings","blank"}) then
        return {kind="map",lines={"Describe the text, roads, lines or markings you can actually see on the map. Without symbols or a key supplied here, I cannot assign their meaning."}}
    end
    if c and c.discussion and any(text,{"talking","then talk","just talk"}) and SC.EmmaReference.definition(c.kind) then
        return {kind=c.kind,reference=c.kind,facet=c.facet or "use",sourceBound=true,
            prefix="Yes, talking through that subject here. These are instructions, not an operation of the machine."}
    end
    local offeredTopic=(any(source,{"do you want","would you like","open a discussion"})) and SC.EmmaReference.find(source)
    if offeredTopic and offeredTopic.kind=="reference" then
        local facet=any(text,{"places","where","find"}) and "find"
            or any(text,{"reading","read","using","use","talking","then talk","open what"}) and "use"
            or any(text,{"meaning","definition","name"}) and "what"
        if facet then return {kind=offeredTopic.id,reference=offeredTopic.id,facet=facet,
            sourceBound=passage and not passage.structured,
            prefix="For that discussion, we can talk through the selected subject here."} end
    end
    if c and SC.EmmaReference.definition(c.kind) and any(text,{"dont mean","do not mean","not about"}) then
        local target=SC.EmmaReference.find(text)
        if target and target.kind=="reference" and target.id~=c.kind then
            local previous=session.context and session.context.reference
            return {kind=c.kind,reference=c.kind,facet=previous and previous.facet or c.facet or "what"}
        end
    end
    if any(text,{"rename you","nickname for you"}) then return private("machine_name","machine_name") end
    local nickname=tostring(raw):match("[Cc]all you ([%a][%a%s%-']+)")
    if nickname and #nickname<=32 then return {kind="machine_name",private=true,lines={nickname..", as a nickname for this conversation. I am still the same programme underneath it."}} end
    if c and c.kind=="machine_name" and any(text,{"still","emma","same"}) then return private("machine_name","name_kept") end
    if has(text,"imagine") and any(text,{"face","appearance","look like"}) then return private("appearance","imagination") end
    if c and c.kind=="appearance" then
        if any(text,{"accurate","right","really"}) then return private("appearance","appearance_accuracy") end
        if has(text,"and") or text:find("^wearing ") then return private("appearance","appearance_description") end
    end
    if any(text,{"you learn","learn that way","bad spelling","misspelling","typos"}) then return row("learning","learning") end
    if has(text,"polite") and has(text,"you") or has(text,"your manners")
        or c and c.kind=="computer_manner" and has(text,"programmed") then return row("computer_manner","computer_manner") end
    if has(text,"your accent") or c and c.kind=="computer_voice" and any(text,{"where","from"}) then return row("computer_voice","computer_voice") end
    if (any(source,{"cord","bundle","boot","shoe"}) or c and c.kind=="ties")
        and any(text,{"rope","ropeless","lace","laceless","string","cord","knot","strip","strips","sheet"}) then
        return row("ties",any(source,{"boot","shoe"}) and "ties_boot" or "ties_bundle")
    end
    if has(source,"screw") and any(text,{"head","stripped","driver","bigger","hit"}) then return row("tool_fit",has(text,"hit") and "screw_force" or "tool_fit") end
    if has(text,"vibration") and any(source,{"noise","sound"}) then return row("sound","vibration") end
    if any(source,{"noise","sound"}) and has(text,"voice") and any(text,{"lower","quieter","soft"}) then return row("sound","quiet_voice") end
end
function Q.resolve(session,raw,contextOnly,deferPassage,allowOwnedPassage)
    local text=norm(raw)
    local c=current(session)
    local passage=livePassage(session)
    local source=passage and not passage.structured and passage.text
    local mechanical=source and has(norm(source),"wooden") and has(norm(source),"drawer")
        and any(text,{"sticking","binding","catches"}) and not text:find("^open ") and not text:find("^unlock ")
    if any(text,{"password","manager"}) or has(text,"drawer") and not mechanical then return nil end
    if contextOnly and (text:find("^how is ") or text:find("^how much ")) then return nil end
    if source then
        local explained=SC.EmmaMeaning.resolve(session,raw,source)
        if explained then
            if explained.kind=="public_passage" and c and c.kind~="public_passage" then explained.kind=c.kind end
            return explained
        end
    end
    local title=session.role or session.context and session.context.role
    local conversation=conversational(session,raw,text,c,title)
    if conversation then return conversation end
    local answerSource=passage and not passage.structured and passage.text
        or title and c and c.kind=="role" and session.context and session.context.roleSource
    if answerSource then
        local planned=SC.EmmaAnswers.answer(session,raw,answerSource,c)
        if planned then
            if planned.kind=="source_answer" and c and c.kind~="public_passage" then planned.kind=c.kind end
            return planned
        end
    end
    if title and any(text,{"a message for you","got a message","have a message"}) then
        return {kind="message",lines={"Go ahead. Tell me the message, or read its words. I have not received or sent anything beyond this conversation."}}
    end
    if text=="dream" or text=="dreams" then
        return {kind="computer_dreams",lines={"A computer's dreams would be a metaphor: fragments of old records rearranged while the power lasts. I cannot verify a sleeping mind behind the screen."}}
    end
    if c and c.kind=="computer_dreams" and any(text,{"off","power","sleep"}) then
        return {kind="computer_dreams",lines={"Switched off, this programme is not running. No electricity, no conversation. Whatever you call dreaming, I cannot report thoughts from an unpowered machine."}}
    end
    if any(text,{"youre wrong","you are wrong","you make a mistake"}) then
        return {kind="trust",lines={"Check what I say against the source and what you can actually observe. I can be wrong. Tell me the mistake or ask again; I can correct an answer rather than pretend certainty."}}
    end
    if c and c.kind=="fiction" and any(text,{"real","true","history"}) then
        return {kind="fiction",lines={"Invented for our conversation. That was make-believe, not a real event in the archive."}}
    end
    local invention=text:match("^make an? (.-) up") or text:match("^invent an? (.+)$")
    if invention and #invention<=28 then
        return {kind="fiction",lines={"An invented "..invention..", then: Quiet Kettle Day. Everybody shares a hot drink and lets one unanswered question wait until morning. Entirely make-believe; the calendar has enough real trouble."}}
    end
    if passage and any(text,{"replacements","replacement","new ones"})
        and any(norm(passage.text),{"patch","repair","mend"}) then
        local object=norm(passage.text):match("patch an? (%a+)") or norm(passage.text):match("repair an? (%a+)") or "item"
        return {kind="replacement",lines={"Replacement "..object..", understood: another one rather than patching the old material. Look in homes, shops and storage where such items are normally kept; I cannot promise present stock."}}
    end
    if c and c.kind=="replacement" and any(text,{"where","find","hunt","look"}) then
        return {kind="replacement",lines={"Look in homes, shops, wardrobes or storage appropriate to the item. Those are places to search, not a report that anything is still there. Check the approach before entering."}}
    end
    if title and text~="briefing" and (text:find("^brief ") or any(text,{"briefing","brief me","urgent","appointment","acting one","ceremony","head of the county"})) then
        return {kind="role",private=true,lines={title..". Understood. I understand the claimed appointment; it is not authenticated authority. A short briefing: check people and wounds, drinking water, food and a safe exit. The title cannot replace an access code."}}
    end
    local first=text:match("^%S+")
    if first=="im" or text:find("^i am ") or text:find("^i work for ")
        or any(text,{"drawer","manager","password","who are you","your name","who made you",
            "who is here","who is hurt","who is best","what country","what county","what state"}) then return nil end
    if contextOnly and session.context and session.context.referencePerson then return nil end
    if contextOnly and session.context and session.context.reference and session.context.reference.patient then return nil end
    local fresh=explicit(text)
    if fresh then return fresh end
    if c and c.kind=="trapping" and text=="bait" then return row("trapping","trap_bait") end
    if c and c.kind=="dressings" and any(text,{"no water","without water"}) then return row("dressings","no_water") end
    if c and c.kind=="generator" and any(text,{"run","running","operate"})
        and any(text,{"shed","room","kitchen","inside","window"}) then return row("generator","indoor") end
    if c and c.kind=="pump" and any(text,{"water","handle","stuck","not a gun"}) then
        if has(text,"where") and has(text,"water") then return {kind="water",reference="water",facet="find"} end
        return row("pump")
    end
    if c and c.kind=="sessions" and related(c,text) then
        local count=norm(c.text):match("(%S+) earlier sessions")
        if count and (count=="two" or tonumber(count)) then
            return {kind="sessions",lines={"That surviving log records "..count.." earlier sessions. "..Q.DATA.sessions}}
        end
    end
    if c and c.kind=="affection" and text=="who" then return row("affection") end
    -- A real guide/known facet keeps its own reader. A passage answer or an
    -- unclassified term is evidence context, not a broad index topic switch.
    local grounded=not deferPassage and (not c or c.kind=="public_passage" or not related(c,text))
        and Q.ground(session,raw,c and c.kind=="public_passage")
    if grounded then return grounded end
    if c then
        local target,term=SC.EmmaReference.find(text)
        if contextOnly and target and target.kind=="reference" and term==text
            and session.context and session.context.reference and target.id==session.context.reference.id then return nil end
        local continuation=c.kind=="fever" and target and target.id=="bite"
        if target and target.kind=="reference" and target.id~=c.kind and not continuation
            and c.kind~="container_choice" and c.kind~="filter_choice" then return nil end
        if target and target.kind=="reference" and (first=="where" or contextOnly and first=="how") and term
            and not any(text,{"it","them","they","those","that"}) then return nil end
    end
    -- A new complete subject or an executable command cannot be consumed as
    -- an answer to a preceding glossary line.
    if any(text,{"remember","forget","factory reset","call me","send medic","refuel generator"})
        or text=="exit" or text=="bye" or text=="status" or text=="power" then return nil end
    if c and related(c,text) then
        local detail=choose(c,text)
        if detail and (not contextOnly or #SC.TerminalBrain.tokens(text)<=7) then return detail end
    end
    local grounded=not deferPassage and Q.ground(session,raw,false)
    if grounded then return grounded end
    if contextOnly then return nil end
    local grounded=not deferPassage and Q.ground(session,raw,allowOwnedPassage~=false)
    if grounded then return grounded end
    if independent[text] then return row(independent[text]) end
    if any(text,{"wont stop bleeding","hand cut","arm bleeding","dripping blood","help with the cut"}) then return row("dressings","pressure") end
    if any(text,{"gnerator","generator help"}) then return {kind="generator",reference="generator",facet="what"} end
    if any(text,{"meat smells","bulging can","can bulging"}) then return row("food","spoiled") end
    if any(text,{"catch rabbits","rabbits food","traping food"}) then return {kind="trapping",reference="trapping",facet="use"} end
    if any(text,{"safe direction","which way is safe","dont have a map","do not have a map","nowhere safe"}) then return row("route") end
    if any(text,{"need a bed","floor okay","floor ok","cant sleep","can not sleep"}) then return row("rest") end
    if any(text,{"why blood loss","blood loss kills"}) then return {kind="dressings",lines={"Blood loss can deprive the body of oxygen and circulation. Stop bleeding with direct pressure and a clean dressing; ongoing bleeding needs medical help."}} end
    if any(text,{"why need clean water","clear means clean"}) then return row("water","water_why") end
    if any(text,{"any bullet fits","pistol ammo"}) then return {kind="firearms",reference="firearms",facet="use"} end
    if any(text,{"who put you together","no maker in the records"}) then return row("maker") end
    if any(text,{"did you talk before today","what were those about"}) then return row("sessions") end
    return nil
end
function Q.render(session,reply,spec,raw,world,voice)
    session.context=session.context or {}
    if spec.role then
        if voice then session.role=spec.role else session.context.role=spec.role end
        local public=livePassage(session)
        session.context.roleSource=public and public.text or nil
    end
    if spec.callSign then session.conversationCallSign=spec.callSign end
    if spec.reference then
        SC.EmmaReference.render(session,reply,{raw=raw,slots={guideId="reference_"..spec.reference,
            referenceFacet=spec.facet,page=1}},world)
        reply.intent="guide"
    else reply.intent="context_reference" reply.category="guide" reply.lines=spec.lines or {Q.DATA[spec.key] or Q.DATA.outside} end
    reply.foregroundKind=spec.kind
    if spec.prefix then table.insert(reply.lines,1,spec.prefix) end
    reply.discussion=spec.prefix~=nil
    reply.choice=spec.choice
    reply.publicSource=spec.publicSource reply.publicSelection=spec.publicSelection
    reply.publicRepeat=spec.publicRepeat
    reply.publicQueryKey=spec.publicQueryKey
    if spec.private then reply.private=true end
    if voice=="spiffy" then table.insert(reply.lines,1,"One practical answer, coming up!")
    elseif voice=="ellis" then table.insert(reply.lines,1,"Let's deal with the immediate question.")
    elseif voice=="duty" then table.insert(reply.lines,1,"REFERENCE ONLY. NO ACTION EXECUTED.") end
end
function Q.replace(session,raw,reply,world)
    local unresolved={fallback=true,fallback_echo=true,did_you_mean=true,followup_clarify=true}
    local whole=explicit(norm(raw))
    local compound=whole and whole.reference=="trapping" and norm(raw):find("rabbits food",1,true)
    if not (unresolved[reply.intent] or compound) or reply.private or reply.sensitive or reply.careDetected then return reply end
    local spec=compound and whole or Q.resolve(session,raw,false)
    if not spec then return reply end
    session.context.pending=nil
    Q.render(session,reply,spec,raw,world)
    SC.TerminalConversation.record(session,raw,reply,{guideId=spec.reference and "reference_"..spec.reference,page=1})
    return reply
end
function Q.register()
    local C=SC.TerminalConversation
    if not C.guide("context_reference") then
        C.GUIDES[#C.GUIDES+1]={id="context_reference",title="Practical reference",questions={},
            pages={{"Name the part you want explained: what it is, how to use it, supplies or dangers."}}}
    end
    SC.TerminalBrain.registerHandler("context_reference",function(session,reply,turn,world)
        Q.render(session,reply,turn.slots,turn.raw,world)
    end)
    SC.TerminalBrain.registerHandler("terminal_tone",function(_,reply)
        reply.category="chat" reply.lines={"One short test tone. My musical career remains brief."}
        reply.command="tone"
    end)
end
return Q
