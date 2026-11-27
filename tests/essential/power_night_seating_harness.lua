-- SPDX-License-Identifier: MIT
-- Both receiver preparations must reach scoring; generic rest cannot silently
-- discard a better TV seat in favour of a radio seat or reserve one twice.
local SC=LivingFellows
local F=SC.TestFixture
local actor=F.actor('sc-power-night-seat',0,0)
local _,_,_,candidates=SC.Downtime._sleepForTests()
local originalTV,originalRadio=SC.TVWatching.candidate,SC.RadioListening.candidate
local tvSeat={kind='sit',score=60,powerNight=true,object={},fact={seatingFor='tv_watch'}}
local radioSeat={kind='sit',score=50,powerNight=true,object={},fact={seatingFor='radio_listen'}}
SC.TVWatching.candidate=function() return tvSeat end
SC.RadioListening.candidate=function() return radioSeat end
local rows=candidates(actor,{recruited=true,order='base_duty'},{safeSince=0},100000,'sit')
local tv,radio=0,0
for _,row in ipairs(rows) do if row==tvSeat then tv=tv+1 elseif row==radioSeat then radio=radio+1 end end
assert(tv==1,'TV preparation must be offered exactly once')
assert(radio==1,'radio preparation must be offered exactly once')
SC.TVWatching.candidate,SC.RadioListening.candidate=originalTV,originalRadio
print('POWER_NIGHT_SEATING_PASS both-media=true unique=true')
