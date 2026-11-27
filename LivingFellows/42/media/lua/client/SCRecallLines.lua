-- SPDX-License-Identifier: MIT
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local R={catalogs={},pools={}} SC.RecallLines=R
local function pool(id,requires,asserts,lines)
    local topic="recall."..id
    local variants,display={},{}
    for n,line in ipairs(lines) do
        variants[#variants+1]={id=tostring(n),text=line,clean=line}
        display[#display+1]={line,clean=line}
    end
    local packets={{id=topic,scene=topic,ideaId=topic,shape="spoken_memory",
        voiceWeights={common=1},requires=requires,asserts=asserts,variants=variants}}
    R.pools[id]={topic=topic,packets=packets} R.catalogs[#R.catalogs+1]=packets
    if SC.Dialogue then SC.Dialogue.register(topic,{common=display}) end
end
pool("escape",{"known","direct","close_call","has_place","has_when"},{"known_escape_place_date"},{
    "I remember the close call at {place}, {when}. A quiet seat means more after that.",
    "That close call at {place}, {when}, still comes back when things go quiet.",
    "{place}, {when}. Getting through that close call wasn't something I'd take for granted.",
    "I keep a little room in my head for the close call at {place}, {when}. A reminder to be careful.",
    "After that escape at {place}, {when}, I appreciate a plain evening.",
    "I can still place that close call: {place}, {when}. I'd prefer fewer like it.",
    "{place}, {when}. An escape I'd rather remember than repeat.",
    "That narrow escape at {place}, {when}, makes ordinary worries feel smaller.",
})
pool("counted_fight",{"known","direct","fight","has_place","has_when","has_count","has_weapon","has_name"},
    {"credited_kills","recorded_weapon_place_date"},{
    "{who} accounted for {count} of them at {place}, {when}, with {weapon}.",
    "The count at {place}, {when}, was {count}. {who}, using {weapon}. That's the plain version.",
    "{who} brought down {count} at {place}, {when}, with {weapon}. I don't need a taller story.",
    "{count} at {place}, {when}. {who} used {weapon}; the number doesn't need polishing.",
    "I remember the count: {count}. {name}, {weapon}, {place}, {when}.",
    "The memory is specific enough: {name}, {count} of them, {weapon}, at {place}, {when}.",
    "{place}, {when}: {who} dealt with {count}, using {weapon}. Enough for one story.",
    "No extra bodies for effect. {who} accounted for {count} with {weapon} at {place}, {when}.",
})
pool("fight_plain",{"known","direct","fight","has_count","has_place","has_when","has_name"},{"confirmed_kill_count_place_date"},{
    "{who} accounted for {count} of them {when}, {place}. That's the number I remember.",
    "The count was {count}: {name}, {when}, {place}. No need to add to it.",
    "{when}, {place}, {who} brought down {count}. The plain story is enough.",
    "{count} of them, {name}, {place}, {when}. I like keeping the actual details.",
    "I remember the tally from {place}, {when}: {count}, down to {by}.",
    "{who} dealt with {count}, {place}, {when}. I don't want a larger number for effect.",
    "{place}, {when}. {who} accounted for {count}. We can leave the count alone.",
    "The number at {place}, {when}, was {count}, down to {by}. I remember that much clearly."})
pool("cover",{"known","direct","player_close_call","covered","has_you","has_place","has_when"},{"accepted_cover_during_player_release"},{
    "There was cover while {you} got free at {place}, {when}. I remember that.",
    "{place}, {when}. {you} got free with cover. A memory worth keeping straight.",
    "I remember {you} getting clear at {place}, {when}, while cover was given.",
    "{you} got free at {place}, {when}. There was cover; I won't turn it into a fairy tale.",
    "That moment at {place}, {when}: cover, then {you} getting free.",
    "I think of {place}, {when}, and {you} making it clear under cover.",
    "{you} got out with cover at {place}, {when}. That's enough of a story.",
    "At {place}, {when}, {you} got free while there was cover. I remember both parts.",
})
pool("player_free",{"known","direct","player_close_call","has_you","has_place","has_when"},{"observed_player_restriction_release"},{
    "I remember {you} getting free at {place}, {when}. I don't need to add anything to that.",
    "{place}, {when}. {you} got clear. A small sentence for a large relief.",
    "That close call with {you} at {place}, {when}, stays with me.",
    "{you} got free at {place}, {when}. I'd rather remember that than imagine another ending.",
    "I think about {place}, {when}, and {you} getting clear again.",
    "The part I keep from {place}, {when}, is {you} getting free.",
    "That moment with {you} at {place}, {when}, reminds me to keep close.",
    "I remember the close call at {place}, {when}. {you} got clear; that's the important part.",
})
pool("death",{"known","direct","death","has_name","has_when"},{"known_named_death_date"},{
    "I remember losing {name}, {when}. Some quiet moments still belong to that loss.",
    "{name}, lost {when}. I don't want the name to fade into a number.",
    "We lost {name}, {when}. Saying it still takes a little time.",
    "I keep thinking of {name}. {when} doesn't feel very far away when I do.",
    "The loss of {name}, {when}, is part of what this place means to me now.",
    "I remember {name}, and the loss {when}. I don't need a better way to phrase it.",
    "{name} died {when}. I'd like to leave room for the person, not just the end.",
    "When things settle, I find myself remembering {name}, lost {when}.",
})
pool("homecoming",{"known","direct","homecoming","has_place","has_when"},{"actual_expedition_return_place_date"},{
    "I remember that expedition coming home to {place}, {when}. A return is worth remembering.",
    "{place}, {when}: the expedition came home. I like a story that reaches home.",
    "That return to {place}, {when}, belongs among the memories worth keeping.",
    "The expedition got back to {place}, {when}. I still like hearing the word 'back'.",
    "I think of the homecoming at {place}, {when}. A little less road in the world for a moment.",
    "{when}, at {place}, the expedition returned. That's the part I want to keep.",
    "I remember the return to {place}, {when}. Nothing grand needed adding.",
    "The expedition came home at {place}, {when}. A useful reminder of what the trip was for.",
})
pool("haul",{"known","direct","homecoming","verified_haul","has_count","has_place","has_when"},{"verified_returned_item_count"},{
    "That expedition returned {count} items at {place}, {when}. Actual supplies, not promises.",
    "{count} items came back from that expedition at {place}, {when}. I remember the real haul.",
    "The haul was {count} items, at {place}, {when}. A useful number to remember.",
    "{place}, {when}: {count} items returned with the expedition. That's the count we could keep.",
    "I remember the expedition haul at {place}, {when}. {count} items made it back.",
    "The expedition returned {count} items to {place}, {when}. I prefer that kind of arithmetic.",
    "{count} things actually returned at {place}, {when}. The expedition gave us something concrete.",
    "At {place}, {when}, that expedition's returned haul was {count} items. No imaginary extras.",
})
pool("alarm",{"known","direct","alarm","all_clear","has_place","has_when"},{"fought_off_alarm_place_date"},{
    "I remember the alarm at {place}, {when}, and being able to call it clear afterwards.",
    "{place}, {when}. That alarm is a sound I don't need repeated.",
    "The alarm at {place}, {when}, ended. I try to remember the ending as well as the noise.",
    "I think of that alarm at {place}, {when}. Quiet seemed valuable afterwards.",
    "{when}, at {place}, we got through the alarm. I can still place the sound.",
    "That fought-off alarm at {place}, {when}, earned a place in my memory.",
    "The alarm at {place}, {when}, is one reason I appreciate an ordinary noise.",
    "I remember {place}, {when}: the alarm, then the all clear.",
})
pool("camp_night",{"known","direct","camp_night","has_place","has_when"},{"recorded_first_camp_night"},{
    "That first night at {place}, {when}. A place starts meaning something when it has a night behind it.",
    "I remember the first camp night at {place}, {when}. It gave the days a beginning here.",
    "{place}, {when}: our first camp night. I like having that small landmark.",
    "The first night at {place} was {when}. It's part of how I count this place as home.",
    "I keep the first camp night at {place}, {when}, separate from all the nights since.",
    "{when}, at {place}, that first camp night became something to remember.",
    "The first camp night at {place}, {when}, still feels like a little boundary in my life.",
    "I remember {place}, {when}, as the first camp night here. A modest beginning.",
})
pool("meeting",{"known","direct","meeting","has_name","has_when"},{"actual_first_meeting"},{
    "I remember meeting {name}, {when}. A stranger becoming a familiar face starts somewhere.",
    "{name}, {when}. That was the first meeting; now the name feels ordinary to say.",
    "I keep the first meeting with {name}, {when}, among the small beginnings.",
    "I remember when {name} was still a new face, {when}.",
    "That first hello with {name} was {when}. A little thing with a long shadow.",
    "Meeting {name}, {when}, gave me another name to remember.",
    "{when}, I met {name}. I like remembering people before they were familiar.",
    "The first meeting with {name}, {when}, belongs in the story too."})
pool("recruitment",{"known","direct","recruitment","has_when"},{"actual_recruitment"},{
    "I remember joining up, {when}. Choosing company still seems worth remembering.",
    "Joining this group, {when}, gave the road a different shape for me.",
    "{when}, I joined. I keep that decision among the ones I can still call mine.",
    "I remember being recruited, {when}. A plain invitation can carry a lot.",
    "That decision to join, {when}, is a beginning I haven't forgotten.",
    "I joined {when}. It's a small date beside some things, but it matters to me.",
    "I remember choosing to come along, {when}. Company was part of the reason.",
    "{when}, I became part of this group. I like keeping track of that."})
pool("burial",{"known","direct","burial","has_place","has_when"},{"verified_closed_grave"},{
    "I remember the burial at {place}, {when}. It deserved the time we gave it.",
    "The burial at {place} was {when}. I don't want that care to disappear into the days.",
    "{place}, {when}. That burial is a quiet part of the story.",
    "I remember the burial at {place}, {when}, without needing to make a speech about it.",
    "That burial at {place}, {when}, still asks for a gentle sort of quiet.",
    "{when}, at {place}, we had that burial. Some work deserves remembering softly.",
    "The burial at {place}, {when}, belongs among the things we took care with.",
    "I keep the burial at {place}, {when}, in mind when the days begin to blur."})
pool("milestone",{"known","direct","milestone","has_count","has_when"},{"actual_world_day_milestone"},{
    "Day {count}, {when}. It was worth noticing that the days were still adding up.",
    "I remember marking day {count}, {when}. A number can mean more than arithmetic.",
    "{when}, day {count} came round. We could still count another day.",
    "Day {count} was {when}. I like keeping a few ordinary dates among the hard ones.",
    "I remember day {count}, {when}. A small place to stop the days blurring together.",
    "That day {count} milestone, {when}, deserved a place in the memory.",
    "{when}, we reached day {count}. Nothing needs adding to the number.",
    "I keep day {count}, {when}, as a little mark on the road through all this."})
pool("bite",{"known","direct","observed_bite","has_name","has_when"},{"witnessed_bite_only"},{
    "I remember {name}'s bite, {when}. It's a hard memory to carry without turning it into a verdict.",
    "That bite involving {name}, {when}, still calls for care in how we speak.",
    "{name} was bitten {when}. I remember the wound, not an answer to every question after it.",
    "I remember the bite {name} suffered, {when}. Fear shouldn't erase the person.",
    "The bite involving {name}, {when}, is something I know about. I won't invent the rest.",
    "I keep {name}'s bite, {when}, separate from guesses about what came next.",
    "{when}, {name} was bitten. I remember why we needed to be careful and decent.",
    "I remember that bite involving {name}, {when}. I don't need to add rumours to it."})
pool("heard",{"known","heard","has_heard_from","has_summary","has_when"},{"on_screen_told_by_receipt"},{
    "{heard_from} told me about {summary}. It happened {when}; I wasn't there myself.",
    "I heard about {summary} from {heard_from}. It happened {when}; I'm keeping the source with the story.",
    "{summary} happened {when}. That's a story {heard_from} told me, not one I witnessed.",
    "I remember {heard_from} telling me about {summary}, which happened {when}.",
    "What I know of {summary} came from {heard_from}. The event was {when}.",
    "{heard_from} gave me the account of {summary}. It happened {when}; I won't pretend I saw it.",
    "I wasn't there for {summary}, which happened {when}. {heard_from} told me afterwards.",
    "That account of {summary} came from {heard_from}. It happened {when}; I remember who said it.",
})
pool("heard_undated",{"known","heard","has_heard_from","has_summary"},{"on_screen_told_by_without_invented_date"},{
    "{heard_from} told me about {summary}. I wasn't given a date, and I wasn't there myself.",
    "What I know of {summary} came from {heard_from}. I'm keeping the source with the story.",
    "I heard about {summary} from {heard_from}. I don't know more than I was told.",
    "{heard_from} gave me the account of {summary}. I won't pretend I witnessed it."})
local detailLines={
    agree="{who} was there. That's another part of the plain story.",
    tease="{who} was there. Don't add a second copy for dramatic effect.",
    pushback="{who} was there. Let's keep the rest separate from guessing.",
    comfort="{who} was there. We can remember the people without rushing it.",
    deflect="{who} was there. That's the detail I can add.",
}
for tag,line in pairs(detailLines) do
    pool("detail_"..tag,{"known","direct","has_source","source_present"},{"observed_named_participant"},{line})
end
return R
