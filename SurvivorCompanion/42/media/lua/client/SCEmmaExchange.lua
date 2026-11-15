-- SPDX-License-Identifier: MIT
-- Small conversation tasks. A single foreground frame, no saved text,
-- providers, actor access, equipment operation or physical inventory changes.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local X={} SC.EmmaExchange=X
local function norm(s) return table.concat(SC.TerminalBrain.tokens(s or "",900)," "):gsub("^emma ","") end
local function has(s,w) return (" "..s.." "):find(" "..w.." ",1,true)~=nil end
local function any(s,words) for _,w in ipairs(words) do if has(s,w) then return true end end return false end
local D={
 count_start="I don't have a reported inventory for this supply task yet, so its quantities are unknown. For a supply list, tell me one item and its quantity, for example a number followed by the item. We can follow that item's reported count here. I cannot count unseen cans or inspect the room; these will be figures you report.",
 unknown_food="Food quantity remains unknown. Count or list the food you can actually find, then type the items and quantities. We can keep a reported list here without guessing portions or stock.",
 count_check="That would use more than the quantity previously reported. Check the figures before we subtract anything; I have not inspected or consumed any supplies.",
 archive_start="For a catalogue, start a record with an item number, title or subject, date if known, and where the papers belong. What material are we listing? I cannot inspect or sort it for you.",
 archive_papers="For loose papers, keep related sheets together and list a title or subject, any visible date, and a group or folder label. The contents and number of sheets are still unknown; no physical sorting has been done.",
 archive_dates="Date order can help follow events over time. Use the dates actually written on the papers and keep undated sheets in a separate group until more evidence appears. Do not invent missing dates; this is a sorting plan, not completed work.",
 note_start="Paste the original note text you want shortened. If you want a particular length, tell me how many lines. No source note has been supplied yet.",
 named="Who chose the name is unknown from this exchange; no verified naming history is available. I can discuss the programme's name without inventing a creator or a visit to old records.",
 earlier="I don't have earlier visitor records in this exchange. The people who talked to this computer before you are unknown; that does not make you its first visitor ever.",
 yesterday="No conversation with you yesterday is established here. I cannot claim a remembered visit. Give me a recap in text and we can work from what you tell me now.",
 smell="I cannot smell the surroundings through a text terminal. A written warning or description is information, not a smell I have observed or a diagnosis of the surroundings here.",
 source="The warning came from the supplied note or text, with general explanation of its words. I have not sensed, tested or inspected the actual surroundings; a written warning is not a current finding.",
 door="From the stated inside, check the fitted release: if it has a handle, turn it to release the latch; if it has a push bar, press the bar. Move the door only in its intended direction when the way is clear. The label does not prove it is unlocked or safe; do not force it. I have not opened the door.",
 file="I cannot physically take a form or put it in a tray. Follow the guide's designated tray for completed forms; it does not show its location or contents. I can help draft or check the words you type here, but nothing has been received, filed or sent.",
 abilities="In text I can explain the supplied guide, help draft wording, check text you provide, or organize a list. I cannot handle physical forms, inspect the room or transmit a document merely by discussing it.",
 clock="The current time is unknown from this text. A scheduled or recorded time does not establish what time it is now. Check an available clock or watch, or supply a reliable reading; I have not checked one.",
 undated="The undated note does not identify the event or when it happened. A date, place, fuller notice or matching record would help identify it. An old report does not establish current conditions.",
 carrying="Start with the essentials and a load you can manage: tell me what needs carrying and what carrying space you have. Reduce the load or split it into smaller trips if it is too heavy; no route or equipment is assumed.",
 less="Yes, carry less if that makes the load manageable. Leave lower-priority things or split the load into smaller trips as conditions allow. I have not removed or moved anything for you.",
 split="Splitting into smaller containers can make each part easier to handle, but it does not remove the total weight. Carrying both at once still means carrying the combined load. Smaller trips add travel; check the route and where supplies can wait rather than assuming repeated trips are safe.",
 window="A window can provide light, ventilation or another possible way out, but can also be an entry point. Whether one is useful depends on the room and conditions; it is not a universal requirement or a guarantee of safety. I have not inspected the room.",
 maps="Do you mean maps rather than books? A reference library may hold maps for consultation, but its actual maps and lending arrangements are unknown. What area or kind of route do you need?",
 loans="The supplied notice says the lending desk is closed. That does not establish another way to borrow books or maps, or a reopening time; I cannot promise a loan.",
 route="For route help, give me a starting point and destination, or describe the roads and markings on your map. I can reason from those details; I do not know your current position or a verified safe route.",
 company="I can keep you company in words here. We can talk, or try that small invented story about the key. I have no body to sit beside you or follow you outside.",
 key_story="A small invented story: A clerk found a key that fitted none of the office locks. Instead of forcing it, she labelled it 'not yet' and kept it beside an empty box. On difficult days, the box gave her somewhere to put a little hope.",
 key_end="In that invented story, the key stayed beside the empty box. The clerk never learned what it opened; she decided an unanswered question could stay unanswered until morning. That is fiction, not a key I have inspected.",
 island="The island of words was a metaphor: a small place for reading and conversation. It implies no literal shore or geographic island, and tells us nothing about where this terminal stands.",
 giant="The sleeping giant was a metaphor for a large, quiet filing cabinet, not a living creature. We can 'wake' the joke by starting with one folder or a title for a list; I have not moved furniture or operated anything.",
 boredom="I can use boredom as part of a conversational personality, but that is not a report of human feelings or of watching you during silence. We can keep chatting while this programme is running.",
}
X.DATA=D
local amounts={zero=0,one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10,eleven=11,twelve=12,
 thirteen=13,fourteen=14,fifteen=15,sixteen=16,seventeen=17,eighteen=18,nineteen=19,twenty=20}
local units={can=true,cans=true,tin=true,tins=true,box=true,boxes=true,battery=true,batteries=true,
 candle=true,candles=true,bottle=true,bottles=true,plank=true,planks=true,board=true,boards=true,tool=true,tools=true}
local function number(s)
 local n=amounts[s] or s:match("^%d+$") and tonumber(s)
 if n and n>=0 and n<=9999 and n==math.floor(n) then return n end
end
local function spec(source,kind,text,private,extra)
 local r=extra or {} r.kind=kind r.lines={text} r.sourceBound=true
 if private then r.private=true else r.publicSource=source r.publicSelection=1 end
 return r
end
local function quantity(source,n,unit)
 local line="You reported "..n.." "..unit.." in this conversation. That is the reported count, not a physical scan or live inventory; I have not moved or consumed anything."
 return spec(line,"reported_quantity",line,false,{reportedQuantity={number=n,unit=unit}})
end
function X.resolve(session,raw,source,current,title)
 if not source and current and (current.kind=="shelter" or current.kind=="computer_dreams") and current.text~="" then source=current.text end
 local q,s=norm(raw),norm(source)
 if q=="shorten a note" or q=="draft a note" then return spec(nil,"note_edit",D.note_start,true) end
 local kind=current and current.kind
 local countFrame=current and current.reportedQuantity
 if kind=="reported_quantity" and countFrame then
  for unit in pairs(units) do
   if has(q,unit) and SC.TerminalBrain.singular(unit)~=SC.TerminalBrain.singular(countFrame.unit) then
    return spec(source,"quantity_prompt","I am following the reported count for "..countFrame.unit..". Tell me the other item's quantity rather than reusing that number for it.")
   end
  end
  if q=="status" or q:find("^how many") or any(q,{"count","how much","remaining","left"}) then return quantity(source,countFrame.number,countFrame.unit) end
  local used=q:match("^(%w+) used$") or q:match("^(%w+) consumed$")
  used=used and number(used)
  if used then
   if used>countFrame.number then return spec(source,"reported_quantity",D.count_check,false,{reportedQuantity=countFrame}) end
   return quantity(source,countFrame.number-used,countFrame.unit)
  end
 end
 local tracking=kind=="quantity_prompt" or kind=="reported_quantity"
  or any(s,{"supply checklist","supplies here","supplies and quantities","track the figures","track figures","live inventory"})
 if tracking then
  local value,unit=q:match("^(%w+) ([%a]+)$")
  value=value and number(value)
  if value and units[unit] then
   if tostring(raw):find("^%s*%-") then
    return spec(source,kind=="reported_quantity" and kind or "quantity_prompt","A reported count cannot be negative. Check the number; I have not changed the previous count.",false,{reportedQuantity=countFrame})
   end
   return quantity(source,value,unit)
  end
  if has(q,"unknown") and has(q,"food") then return spec(source,"quantity_prompt",D.unknown_food) end
  if q=="status" or q=="supplies" or q:find("^count ") then return spec(source,"quantity_prompt",D.count_start) end
 end
 local role=norm(title)
 if role=="archivist" or kind=="catalogue" then
  if any(q,{"catalogue","catalog","index","first order"}) then return spec(source,"catalogue",D.archive_start,true) end
  if any(q,{"papers","sheets","documents"}) then return spec(source,"catalogue",D.archive_papers,true) end
  if any(q,{"date","chronological","undated"}) then return spec(source,"catalogue",D.archive_dates,true) end
 end
 if role=="chair" and any(q,{"start","begin","meeting","agenda"}) then
  return spec(source,"meeting","For our pretend meeting: call it to order, then name the agenda items. What should we discuss first? No attendees have been summoned and nothing is being broadcast.",true)
 end
 if kind=="note_edit" then
  if q=="cancel" or q=="stop editing" or q=="stop note" then return spec(nil,"note_closed","Private drafting cancelled. Nothing was saved or sent.",true) end
  local n=q:match("^(%w+) lines?$") n=n and number(n)
  if n and n>=1 and n<=8 then return spec(nil,"note_edit","A note of "..n.." lines, understood. Paste the original note text so I can shorten it without inventing its message.",true,{taskLimit=n}) end
  local leaving=q=="exit" or q=="bye" or q=="status" or q:find("^forget ")
  if q~="" and not leaving then
   local words={} for word in tostring(raw):sub(1,160):gmatch("%S+") do words[#words+1]=word end
   local total=math.min(current.taskLimit or 2,#words)
   local lines={} local at=1
   for n=1,total do
    local last=math.floor(n*#words/total)
    lines[n]=table.concat(words," ",at,last) at=last+1
   end
   if #lines>0 then return spec(nil,"note_edit","Compact draft, keeping the supplied words:\n"..table.concat(lines,"\n"),true,{taskLimit=current.taskLimit}) end
  end
 end
 if any(s,{"shortening a note","shorten a note","note text"}) and (q=="note" or q=="the note") then return spec(source,"note_edit",D.note_start,true) end
 if source==nil then return nil end
 if any(q,{"who named you","who chose your name","who gave you"}) and any(s,{"emma","computer","terminal","programme"}) then return spec(source,"computer_name",D.named) end
 if any(q,{"before me","earlier visitors"}) and any(s,{"emma","computer","terminal","programme"}) then return spec(source,"computer_history",D.earlier) end
 if has(q,"remember") and any(q,{"yesterday","last visit","last time"}) then return spec(source,"computer_history",D.yesterday) end
 if has(q,"smell") and any(q,{"anything","you"}) then return spec(source,"source_basis",D.smell) end
 if has(q,"how") and has(q,"know") and (kind=="source_basis" or any(s,{"note","notice","leaflet","manual","poster"})) then return spec(source,"source_basis",D.source) end
 if kind=="door_instructions" and any(q,{"instructions","how","latch","handle"}) then return spec(source,"door_instructions",D.door) end
 if any(s,{"completed forms","blue tray"}) then
  if q:find("^file ") then return spec(source,"text_help",D.file) end
  if any(q,{"what can you","what can"}) then return spec(source,"text_help",D.abilities) end
 end
 if has(s,"clock") and any(s,{"hasnt been given","no current","unknown","no reliable"})
  and any(q,{"now","check","noon","time","clock"}) then return spec(source,"clock_unknown",D.clock) end
 if any(s,{"undated","doesnt give a date","no date"}) and (q:find("^when") or any(q,{"which flood","which event"})) then return spec(source,"record_date",D.undated) end
 if any(s,{"load","carrying","heavy","weight"}) then
  if has(q,"less") and any(q,{"carry","take","load","weight"}) and not any(q,{"cant","cannot","dont","not"}) then return spec(source,"carrying",D.less) end
  if any(q,{"two","split","smaller","divide"}) and any(q,{"smaller","containers","loads","trips","load"}) then return spec(source,"carrying",D.split) end
  if q=="carrying" or q=="too heavy" then return spec(source,"carrying",D.carrying) end
 end
 if has(q,"window") and any(s,{"shelter","safer room","door helps control"}) then return spec(source,"shelter",D.window) end
 if has(s,"lending desk") and has(s,"closed") and any(q,{"borrow","borrowing","loan"}) then return spec(source,"library",D.loans) end
 if q:find("^no ") and has(q,"maps") and has(s,"library") then return spec(source,"map_planning",D.maps) end
 if (kind=="map_planning" or has(s,"map")) and any(q,{"routes","route help","way back"}) then return spec(source,"map_planning",D.route) end
 if has(s,"story") and has(s,"key") then
  if any(q,{"keep me company","company"}) then return spec(source,"fiction_offer",D.company) end
  if any(q,{"tell","story","continue","go on"}) then return spec(D.key_story,"key_fiction",D.key_story) end
 end
 if kind=="key_fiction" and any(q,{"key","next","ending","then"}) then return spec(D.key_end,"key_fiction",D.key_end) end
 if has(s,"island of words") and any(q,{"island","shore"}) then return spec(source,"metaphor",D.island) end
 if has(s,"sleeping giant") and has(s,"cabinet") and any(q,{"giant","wake"}) then return spec(source,"metaphor",D.giant) end
 if has(q,"bored") and has(q,"you") and (kind=="computer_dreams" or any(s,{"computer","terminal","programme","dreams"})) then return spec(source,"computer_feelings",D.boredom) end
end
return X
