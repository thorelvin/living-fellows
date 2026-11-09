-- SPDX-License-Identifier: MIT
-- One foreground lookup over bounded conversation metadata. No native objects,
-- cached readings, executable requests or background discovery live here.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local F={} SC.EmmaFollowups=F
local function guide(id,subject,page)
    return {guideId=id,subject=subject,page=page or 1}
end
local function facet(id) return {facet=id} end
F.subjects={
    generator={label="generator",aliases={"generator","generators","genny"},guideId="survival_generator",
        rules={fuel=facet("generator_fuel"),fuel_level=facet("generator_level"),remaining=facet("generator_level"),placement=facet("generator_location"),
            runtime=facet("generator_runtime"),noise=guide("survival_noise","generator"),
            tools=guide("survival_generator","generator"),needs=guide("survival_generator","generator"),status={intent="power"},
            specialist={intent="skills",query="electrical"},repair=guide("generator","generator"),
            refuel=guide("generator","generator")}},
    fuel={label="fuel",aliases={"fuel","gasoline","petrol","gas"},guideId="survival_fuel",
        rules={find=guide("survival_fuel","fuel")}},
    vehicle={label="vehicle",aliases={"car","cars","vehicle","vehicles","truck","trucks","van","vans"},guideId="survival_car_start",
        rules={fuel=facet("vehicle_fuel"),fuel_level=facet("vehicle_level"),remaining=facet("vehicle_level"),runtime=facet("vehicle_runtime"),tools=guide("survival_car_start","vehicle"),
            needs=guide("survival_car_start","vehicle"),noise=guide("survival_noise","vehicle"),start=guide("survival_car_start","vehicle")}},
    water={label="water",aliases={"water"},guideId="survival_water_find",
        rules={find=guide("survival_water_find","water"),safe=guide("survival_water_purify","water"),
            purify=guide("survival_water_purify","water")}},
    food={label="food",aliases={"food","meals"},guideId="survival_food_spoil",
        rules={preserve=guide("survival_food_preserve","food"),runtime=guide("survival_food_spoil","food"),safe=guide("survival_food_spoil","food"),
            cook=guide("survival_cooking","food")}},
    wood={label="wood expedition",aliases={"wood","logging"},guideId="wood",
        rules={tools=guide("wood","wood"),needs=guide("wood","wood"),find=guide("wood","wood"),deliver=guide("delivery","wood"),
            specialist={intent="skills",query="axe handling"},progress={intent="expedition"},quantity={intent="expedition"},remaining={intent="expedition"},
            deliver_status={intent="deliveries"},transport=guide("wood","wood",2)}},
    fishing={label="fishing expedition",aliases={"fishing","fishing trip"},guideId="fishing",
        rules={tools=guide("fishing","fishing"),needs=guide("fishing","fishing"),find=guide("fishing","fishing"),deliver=guide("delivery","fishing"),
            progress={intent="expedition"},quantity={intent="expedition"},remaining={intent="expedition"},deliver_status={intent="deliveries"},transport=guide("fishing","fishing",2)}},
    expedition={label="expedition",aliases={"expedition","expeditions","mission"},guideId="expeditions",
        rules={needs=guide("expeditions","expedition"),tools=guide("expeditions","expedition"),
            deliver=guide("delivery","expedition"),progress={intent="expedition"},quantity={intent="expedition"},remaining={intent="expedition"},runtime={intent="expedition"},
            deliver_status={intent="deliveries"},transport=guide("expeditions","expedition",2),
            contact=guide("radio_reports","expedition"),target=guide("targets","expedition")}},
    storage={label="camp storage",aliases={"storage","shelves"},guideId="storage",
        rules={remove=guide("storage","storage"),sort=guide("sorting","storage")}},
    jobs={label="camp jobs",aliases={"jobs","chores"},guideId="jobs",
        rules={blocked={intent="blocked"},tools=guide("jobs","jobs",2)}},
    rest={label="companion rest",aliases={"rest","tiredness","stamina"},guideId="rest",
        rules={placement=guide("rest","rest"),blocked=guide("rest","rest",2)}},
    camp={label="camp",aliases={"camp","base"},guideId="camp",
        rules={next=facet("camp_first_steps"),storage=guide("storage","storage"),work=guide("jobs","jobs")}},
    relationships={label="relationships",aliases={"recruitment","trust","relationships"},guideId="recruit",
        rules={supplies=facet("trust_help"),trust=facet("trust_progress"),learning=facet("trust_help"),blocked=guide("recruit","relationships",2),
            next=facet("trust_help")}},
    medical={label="medical help",aliases={"medicine","medical","first aid","wounds","injuries"},guideId="medicine",
        rules={treatment=guide("medicine","medical"),tools=guide("medicine","medical"),next=guide("medicine","medical"),
            trust=facet("trust_progress"),supplies=facet("trust_help"),
            specialist={intent="skills",query="first aid"},learning=guide("survival_skills","medical")}},
    skills={label="skills",aliases={"skills","training"},guideId="survival_skills",
        rules={learning=guide("survival_skills","skills"),next=guide("survival_skills","skills")}},
    threats={label="nearby zombies",aliases={"zombies","zombie","zeds","horde"},guideId="survival_combat",
        rules={progress={intent="zombies"},range={intent="zombies"},next=guide("survival_combat","threats"),
            noise=guide("survival_noise","threats")}},
    computer={label="computer",aliases={"computer","computers","pc","terminal"},guideId="computer",
        rules={upgrade=facet("computer_upgrades"),power=guide("ups","computer"),memory=guide("memory","computer"),
            specialist={intent="skills",query="electrical"},
            data=guide("offline","computer"),next=facet("computer_upgrades")}},
    radio={label="radio",aliases={"radio","walkie talkie","handset"},guideId="radio",
        rules={tools=guide("radio","radio"),needs=guide("radio","radio"),range=guide("radio_reports","radio"),
            scan=guide("scanner","radio"),contact=guide("radio_reports","radio"),taxi=guide("taxi","radio"),
            specialist={intent="skills",query="electrical"},blocked=guide("scanner","radio"),next=guide("scanner","radio")}},
    controls={label="building controls",aliases={"controls","shutters","doors","lights","sensors"},guideId="controls",
        rules={scan=guide("controls","controls"),access=guide("doors","controls"),lighting=guide("lights","controls"),
            specialist={intent="skills",query="electrical"},alarm=guide("security","controls"),power=guide("lights","controls"),next=guide("controls","controls")}},
    farming={label="farming",aliases={"farming","crops","plots","farmer"},guideId="farming",
        rules={tools=guide("farming","farming"),needs=guide("farming","farming"),blocked=guide("farming","farming",2),
            specialist={intent="skills",query="farming"},storage=guide("farming","farming",2)}},
    orders={label="companion orders",aliases={"orders","following","regroup"},guideId="orders",
        rules={blocked=guide("orders","orders",2),next=guide("orders","orders")}},
}
F.facets={
    generator_fuel={guideId="survival_fuel",subject="fuel",parent="generator",title="Fuel for generators",
        lines={"Generators run on gasoline. Use a compatible fuel container when refuelling.",
            "Ask where to find it for fuel sources, or how much fuel is left for a current generator reading."}},
    vehicle_fuel={guideId="survival_fuel",subject="fuel",parent="vehicle",title="Fuel for vehicles",
        lines={"Standard vehicles use gasoline. Check the vehicle's own information if a vehicle mod changes its requirements.",
            "Ask where to find it for fuel sources."}},
    generator_location={guideId="survival_generator",subject="generator",title="Placing a generator",
        lines={"Keep a running generator outdoors. Indoors, its fumes are dangerous.",
            "Keep it near the building it supplies and somewhere you can defend. I cannot verify a particular placement from this reference."}},
    generator_runtime={guideId="survival_generator",subject="generator",title="Generator runtime",
        lines={"Runtime depends on the electrical load and available fuel. I do not have a verified consumption rate here.",
            "Check the generator's information panel for consumption. Ask how much fuel is left for its current recorded percentage."}},
    generator_level={guideId="generator",subject="generator",title="Current generator fuel",reading=true},
    vehicle_level={guideId="survival_car_start",subject="vehicle",title="Current vehicle fuel",
        lines={"I do not have a specific vehicle's current fuel reading in this conversation. Check that vehicle's fuel gauge or information panel."}},
    vehicle_runtime={guideId="survival_car_start",subject="vehicle",title="Vehicle fuel use",
        lines={"Fuel use varies with the vehicle, its engine and the driving. I do not have a measured consumption rate or a verified range for a specific car here."}},
    camp_first_steps={guideId="camp",subject="camp",title="First things at camp",
        lines={"Mark permitted storage for food, clean water, medicine and tools. Give workers usable routes to those supplies.",
            "Then assign base-duty jobs from More > Base. Ask about storage or jobs for the next steps."}},
    trust_help={guideId="recruit",subject="relationships",title="Helping a survivor",
        lines={"Open Talk and offer food, drinking water or medical help. You can offer supplies without opening a trade.",
            "Help a real need. Repeated gifts give diminishing trust; check the relationship explanation rather than handing over everything."}},
    trust_progress={guideId="recruit",subject="relationships",title="Understanding trust",
        lines={"Talk shows the survivor's relationship stage, progress and recent reasons for change.",
            "Personal trust, household standing, contracts and family obligations are separate conditions. Check their current Talk choices; I cannot promise they will join."}},
    computer_upgrades={guideId="computer",subject="computer",title="Computer upgrades",
        lines={"Use Local services > Computer upgrades. A mounted two-way radio opens station radio services; a UPS provides battery backup.",
            "Building controls have their own connections and components. Ask about the radio, backup power or building controls for that branch."}},
}
local guideSubjects={generator="generator",survival_generator="generator",survival_fuel="fuel",
    survival_car_start="vehicle",water="water",survival_water_find="water",survival_water_purify="water",
    food="food",survival_food_spoil="food",survival_food_preserve="food",survival_cooking="food",
    wood="wood",fishing="fishing",expeditions="expedition",targets="expedition",radio_reports="expedition",
    storage="storage",sorting="storage",jobs="jobs",retry="jobs",rest="rest",survival_sleep="rest",
    camp="camp",recruit="relationships",strangers="relationships",medicine="medical",survival_bleeding="medical",
    survival_deep_wound="medical",survival_glass_bullet="medical",survival_fracture="medical",
    survival_wound_infection="medical",survival_pills="medical",survival_bite="medical",survival_herbs="medical",
    survival_skills="skills",survival_combat="threats",computer="computer",offline="computer",memory="computer",
    ups="computer",radio="radio",scanner="radio",controls="controls",doors="controls",lights="controls",
    security="controls",farming="farming",survival_farming="farming",orders="orders"}
local function has(text,values)
    for _,value in ipairs(values) do if text:find(" "..value.." ",1,true) then return true end end
    return false
end
function F.subject(topic)
    if not topic then return nil end
    if F.subjects[topic.subject] then return topic.subject end
    if topic.kind=="guide" then return guideSubjects[topic.id] end
    if topic.kind=="item" and #(topic.item or {})==1 and F.subjects[topic.item[1]] then return topic.item[1] end
    if topic.intent=="jobs" or topic.intent=="blocked" then return "jobs" end
    if topic.originIntent=="people_hurt" then return "medical" end
    if topic.intent=="zombies" then return "threats" end
    if topic.intent=="expedition" or topic.intent=="deliveries" then return "expedition" end
    if topic.intent=="skills" then return topic.query=="first aid" and "medical" or "skills" end
end
function F.annotate(topic,slots,reply)
    local subject=reply.followupSubject or slots.followupSubject or F.subject(topic)
    if F.subjects[subject] then topic.subject=subject end
    local parent=reply.followupParent or slots.followupParent
    if F.subjects[parent] and parent~=subject then topic.parentSubject=parent end
    if F.facets[slots.facet] then topic.facet=slots.facet end
end
local function questionKind(text)
    if has(text,{"how much do we have","how many do we have","do we have any","is that enough"}) then return "quantity" end
    if text==" who can help " or has(text,{"who is best at that","who is best at it","who can help her",
        "who can help him","who can help them","who can help with that","who can treat","who could treat"}) then return "specialist" end
    if has(text,{"what can i give","what should i give","give them","give him","give her","offer them"}) then return "supplies" end
    if has(text,{"trust","relationship"}) and has(text,{"increase","improve","build","gain"}) then return "supplies" end
    if has(text,{"trust","relationship","progress with them"}) then return "trust" end
    if has(text,{"what next","what now","next steps","what should i do","where do i start","how can i help"}) then return "next" end
    if has(text,{"where are they","where is she","where is he","how close","how many are there",
        "are they home","how is it going","what have they found","why did they return"}) then return "progress" end
    if has(text,{"stored","still pending","cargo pending","did they unload","delivery status"}) then return "deliver_status" end
    if has(text,{"how long","consumption"}) or has(text,{"how much"}) and has(text,{"use","consume","burn"}) then return "runtime" end
    if has(text,{"how much is left","how much remains","how many left","how many still to go"}) then return "remaining" end
    if has(text,{"how much fuel","fuel left","fuel remaining","fuel level"}) then return "fuel_level" end
    if has(text,{"is it running","is it still running","is it on"}) then return "status" end
    if has(text,{"refuel","refuelling","refueling"}) then return "refuel" end
    if has(text,{"put","place","placement","indoors","inside","where should i keep","where do i keep"}) then return "placement" end
    if has(text,{"where"}) and has(text,{"find","get","obtain","from"}) then return "find" end
    if has(text,{"fuel","gasoline","petrol","gas"}) then return "fuel" end
    if has(text,{"purify","boil","clean it","make it safe"}) then return "purify" end
    if has(text,{"drink","safe","tainted","rotten","spoiled"}) then return "safe" end
    if has(text,{"preserve","keep it fresh","keep them fresh","last longer"}) then return "preserve" end
    if has(text,{"cook","cooking"}) then return "cook" end
    if has(text,{"treat","bandage","help her","help him","help them"}) then return "treatment" end
    if has(text,{"learn","improve","train","get better","increase it"}) then return "learning" end
    if has(text,{"what do they need","what does it need","what will i need","what does she need","what does he need",
        "what do i need","what do we need"}) then return "needs" end
    if has(text,{"tools","equipment","requirements"}) then return "tools" end
    if has(text,{"noise","noisy","loud","attract"}) then return "noise" end
    if has(text,{"repair","fix"}) then return "repair" end
    if has(text,{"deliver","delivery","unload","bring it home","bring them home"}) then return "deliver" end
    if has(text,{"drive","driving","transport","walking"}) then return "transport" end
    if has(text,{"contact","recall","call them","radio report"}) then return "contact" end
    if has(text,{"destination","target","choose on map"}) then return "target" end
    if has(text,{"unmark","remove marking","remove the marking"}) then return "remove" end
    if has(text,{"sort","sorting"}) then return "sort" end
    if has(text,{"blocked","stuck","retry","not join","not joining","refuse","refused"}) then return "blocked" end
    if has(text,{"upgrade","upgrades","add to it","fit to it"}) then return "upgrade" end
    if has(text,{"battery","backup","without power","power goes out","still run"}) then return "power" end
    if has(text,{"remember","notes","memory","forget"}) then return "memory" end
    if has(text,{"internet","network","data","know that"}) then return "data" end
    if has(text,{"how far","range","reach"}) then return "range" end
    if has(text,{"scan","scanner","discover","discovery"}) then return "scan" end
    if has(text,{"taxi","markus","marcus"}) then return "taxi" end
    if has(text,{"lock","unlock","shutters","doors"}) then return "access" end
    if has(text,{"lights","lighting"}) then return "lighting" end
    if has(text,{"alarm","siren","sensors"}) then return "alarm" end
    if has(text,{"storage","shelves"}) then return "storage" end
    if has(text,{"work","jobs","duty"}) then return "work" end
    if has(text,{"start","hotwire","keys"}) then return "start" end
end
local function result(subject,kind,parent)
    local rule=F.subjects[subject].rules[kind]
    if not rule then return nil end
    if rule.intent then return rule.intent,{query=rule.query,followupSubject=subject,followupParent=parent} end
    if rule.facet then
        local spec=F.facets[rule.facet]
        return "guide",{guideId=spec.guideId,page=1,facet=rule.facet,
            followupSubject=spec.subject,followupParent=spec.parent}
    end
    return "guide",{guideId=rule.guideId,page=rule.page,followupSubject=rule.subject,
        followupParent=parent}
end
function F.resolve(session,raw)
    local c=SC.TerminalConversation
    local value=table.concat(SC.TerminalBrain.tokens(raw)," ")
    local text=" "..value.." "
    if c.more(value) or c.refresh(value) then return nil end
    -- Instructions may use a guide. Requests always keep the existing checked
    -- action path; pronouns never construct an executable request here.
    local advisory=value:find("^how ") or value:find("^why ") or value:find("^when ") or value:find("^should i ")
    if not advisory and has(text,{"refuel","send","queue","reset","repair","start","retry","remove"}) then return nil end
    local bareStock=value=="how much do we have" or value=="how many do we have" or value=="do we have any"
    if has(text,{"do we have","we got","in storage","on shelves"}) and not bareStock then return nil end
    local latest=c.latest(session)
    local current,parent=F.subject(latest),latest and latest.parentSubject
    local kind=questionKind(text)
    if value:find("^who ") and kind~="specialist" then return nil end
    if latest and latest.kind=="item" and kind=="quantity" then return nil end
    if latest and (latest.kind=="person" or latest.kind=="people")
        and (kind=="needs" or kind=="progress") then return nil end
    local explicit={}
    for id,spec in pairs(F.subjects) do
        if has(text,spec.aliases) and not (id=="fuel" and (kind=="fuel" or kind=="fuel_level" or kind=="runtime")) then
            explicit[#explicit+1]=id
        end
    end
    table.sort(explicit)
    local pending=session.context.followupChoice
    session.context.followupChoice=nil
    if pending and (session.turns or 0)-pending.turn<=2 and #explicit==1 then
        local short=#SC.TerminalBrain.tokens(value)<=3
        local allowed=#pending.choices==0
        for _,id in ipairs(pending.choices) do if id==explicit[1] then allowed=true end end
        if short and allowed then return result(explicit[1],pending.kind) end
    end
    local pronoun=has(text,{"it","its","they","them","their","those","that","these"})
    local follow=pronoun or value:find("^and ") or value:find("^also ") or value:find("^what about ")
    local question=value:find("^what ") or value:find("^which ") or value:find("^where ")
        or value:find("^how ") or value:find("^can ") or value:find("^does ")
        or value:find("^do ") or value:find("^is ") or value:find("^are ")
        or value:find("^why ") or value:find("^when ") or value:find("^should ") or follow
    if #explicit==1 then
        local subject=explicit[1]
        if kind and question then
            local intent,slots=result(subject,kind)
            if intent then return intent,slots end
        end
        if has(text,{"tell me about","what is","what are","what about"}) or value:find("^back to ")
            or value:find("^go back to ") then
            return "guide",{guideId=F.subjects[subject].guideId,page=1,followupSubject=subject}
        end
        return nil
    end
    if not kind or not question then
        if not kind and question and follow and current and latest.kind~="person" and latest.kind~="people"
            and latest.kind~="item" then return "followup_clarify",{subject=current} end
        return nil
    end
    if #explicit>1 then return "followup_clarify",{kind=kind,choices=explicit} end
    local elliptical=kind=="next" or kind=="tools" or kind=="needs" or kind=="remaining"
        or kind=="fuel" or kind=="fuel_level" or kind=="range" or kind=="specialist" or kind=="quantity"
    if not follow and not (current and elliptical) then return nil end
    -- The newest subject is most specific (wood trip before expedition).
    -- Consult its parent only for an unsupported facet (fuel before generator).
    if current and F.subjects[current].rules[kind] then return result(current,kind,parent) end
    if F.subjects[parent] and parent~=current and F.subjects[parent].rules[kind] then return result(parent,kind) end
    if kind=="fuel" or kind=="fuel_level" or kind=="runtime" and has(text,F.subjects.fuel.aliases) then
        return "followup_clarify",{kind=kind,choices={"generator","vehicle"}}
    end
    if current then return "followup_clarify",{subject=current} end
end
function F.render(slots,read)
    local spec=F.facets[slots.facet]
    if not spec or spec.guideId~=slots.guideId then return nil end
    local lines={spec.title..":"}
    if spec.reading then
        local power=read("power")
        local fuel=type(power)=="table" and tonumber(power.fuel)
        if type(power)=="table" and power.source=="generator" and fuel and fuel==fuel and fuel>=0 and fuel<=100 then
            lines[#lines+1]="The local generator has "..math.floor(fuel+.5).."% fuel remaining."
        else lines[#lines+1]="A current generator fuel reading is unavailable here. I cannot infer it from the last conversation." end
    else for _,line in ipairs(spec.lines) do lines[#lines+1]=line end end
    return lines,spec.subject,spec.parent
end
function F.clarify(session,reply,turn)
    local slots=turn.slots or {}
    local subject=F.subjects[slots.subject]
    if subject then
        reply.category="chat"
        reply.lines={"I am following the "..subject.label..", but I do not have an answer to that detail.",
            "If you are changing subjects, name the person or system you mean."}
        session.context.followupChoice=nil
        return
    end
    local labels,choices={},{}
    for _,id in ipairs(slots.choices or {}) do if F.subjects[id] then
        choices[#choices+1]=id;labels[#labels+1]=F.subjects[id].label
    end end
    reply.category="chat"
    reply.lines={#labels>0 and "Do you mean the "..table.concat(labels," or the ").."? Name one so I can answer that question."
        or "Which thing do you mean? Name it so I can follow that question without guessing."}
    session.context.followupChoice={kind=slots.kind,choices=choices,turn=session.turns or 0}
end
return F
