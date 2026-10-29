-- SPDX-License-Identifier: MIT
local T,SC=TERMINAL_TEST,SurvivorCompanion
local Terminal=SC.Terminal
local before=T.checks
local oldWorld=SC.TerminalWorld.new
local count,reads,inside=12,0,true
SC.TerminalWorld.new=function()
    return {camp=function() return {configured=true,inside=inside} end,
        clock=function() return {year=1993,month=6,day=20,worldHours=T.hours} end,
        people=function() return {{id="kate",name="Kate Miller",health=90,fatigue=.8,endurance=.6}} end,
        power=function() return {source="grid"} end,
        storage=function() reads=reads+1 return {containers=1,items=count,groups={
            {name="Nails",type="Base.Nails",category="Material",count=count,where={"garage shelf"}}}} end}
end
Terminal.reset()
local player=T.player(101,100,0)
local pc=T.computer(T.square(100,100,0,true))
local function open(object)
    T.check(Terminal.open(player,object),"conversation window opens")
    local w=Terminal.window w:flush()
    return w
end
local function send(w,line)
    w:setFocusMode("chat") w.entry:setText(line) w:submit() w:flush()
end
local function output(w)
    local rows={}
    for _,row in ipairs(w.rows) do rows[#rows+1]=row.text end
    return table.concat(rows,"\n")
end
local w=open(pc)
send(w,"how many nails")
local session=w.session
w:close()
w=open(pc)
T.check(w.session==session,"brief reopen uses this computer's bounded conversation")
count=20
local previous=reads
send(w,"is that enough for 50")
T.check(output(w):find("you need 30 more",1,true) and reads==previous+1,"reopened follow-up refreshes stock once")
send(w,"remember the gate key is in the van")
w:close()
local memory=pc.data.movableData[Terminal.MEMORY_KEY]
T.check(memory and memory.notes[1]=="the gate key is in the van" and memory.conversation==nil,
    "close saves explicit notes without serializing conversation history")
local other=T.computer(T.square(100,100,0,true))
w=open(other)
send(w,"where are they")
T.check(not output(w):find("garage shelf",1,true) and w.session~=session,
    "another machine at reused coordinates cannot borrow the first machine's subject")
w:close()
w=open(pc)
send(w,"how is Kate") send(w,"thanks") send(w,"how tired is she")
T.check(output(w):find("tiredness 80%",1,true),"UI input and streamed reply retain a named-person thread")
inside=false
previous=reads
send(w,"how many nails")
T.check(reads==previous,"changed camp access cannot be bypassed by conversation memory")
inside=true
w:close()
T.now=T.now+SC.TerminalConversation.MAX_IDLE_MS+1
w=open(pc)
send(w,"what were we talking about")
T.check(not output(w):find("how tired is she",1,true) and w.session.context.person==nil,
    "reopen after idle expiry clears old questions and pronouns")
T.check(#w.session.notes==1,"idle expiry keeps explicitly saved notes")
w:close()
Terminal.reset()
SC.TerminalWorld.new=oldWorld
print("TERMINAL_CONVERSATION_UI_PASS checks="..(T.checks-before))
SC_TEST_REPORT=SC_TEST_REPORT.."; Conversation UI: "..(T.checks-before).." checks passed"
