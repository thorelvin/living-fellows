-- SPDX-License-Identifier: MIT
local R=SCRealSandboxHarnessProbes.SCHomeRadioProbe
local checks=0
local function expect(ok,message) checks=checks+1 if not ok then error(message) end end
local view={radio={}}
SurvivorCompanion={HomeTrip={describe=function() return view end}}
local f={primary={},radio={orders=2,pendingId=17,pendingVerb="hold"}}
local evidence={}
local function check(name,ok,detail) evidence[#evidence+1]={name=name,ok=ok,detail=detail} return ok end
local writer
SurvivorCompanion.Config={get=function() return true end}
SurvivorCompanion.Diary={writerFor=function() return writer end}
f.crew={{id="crew-1"}}
expect(not R.ready(f),"new recruits must finish normal diary admission before an exact inventory baseline")
writer={diarist=true,bookCreated=true,pencilGiven=false}
expect(not R.ready(f),"a half-initialized diarist must not pass predeparture readiness")
writer.pencilGiven=true
expect(R.ready(f),"a normally initialized book and pencil can enter the exact baseline")
writer={diarist=false}
expect(R.ready(f),"a decided non-diarist requires no invented personal items")
view.radio.lastReply={id=16,verb="hold",acknowledged=true}
expect(R.reply(f,check)==nil and #evidence==0,"an old successful Hold reply must not satisfy a new call")
view.radio.lastReply={id=17,verb="status",acknowledged=true}
expect(R.reply(f,check)==nil and #evidence==0,"matching ID with wrong command must not satisfy recall evidence")
view.radio.lastReply={id=17,verb="hold",acknowledged=true}
view.radio.pending={id=17}
expect(R.reply(f,check)==nil and #evidence==0,"a call still pending must not claim native acknowledgement")
view.radio.pending=nil view.radio.lastReply.acknowledged=false
expect(R.reply(f,check)==false and evidence[1].ok==false,"missing native return ACK must fail acceptance")
view.radio.lastReply.acknowledged=true
expect(R.reply(f,check)==true and evidence[2].ok==true,"exact completed native reply may satisfy acceptance")
local item={getID=function() return 55 end,getFullType=function() return "Base.NailsBox" end}
local items={size=function() return 1 end,get=function() return item end}
local container={getItems=function() return items end}
local part={getItemContainer=function() return container end}
local engine=false
local car={getPartById=function() return part end,isEngineRunning=function() return engine end}
SurvivorCompanion.Vehicle={loadedBySqlId=function() return car end,isStationary=function() return true end}
SurvivorCompanion.GameplayUtil={itemStableId=function() return "cargo-55" end}
f.drive={sqlId=12,vehicle=car,cargo={{id="cargo-55",nativeId=55,itemType="Base.NailsBox"}}}
expect(R.cargo(f,check)==true,"same actual stopped car and native cargo are required")
f.drive.cargo[1].nativeId=56
expect(R.cargo(f,check)==false,"an identical-looking replacement must fail exact cargo proof")
f.drive.cargo[1].nativeId=55 engine=true
expect(R.cargo(f,check)==false,"a running engine after recall must fail acceptance")
print("HOME_RADIO_PROBE_REGRESSION_PASS checks="..checks)
