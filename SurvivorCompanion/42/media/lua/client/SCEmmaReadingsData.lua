-- SPDX-License-Identifier: MIT
-- Foreground body/calendar vocabulary and original EMMA lines from the plan.
require "SCEmmaLanguageData"
require "SCTerminalLines"
local SC=SurvivorCompanion
local D=SC.EmmaLanguageData
D.ME_INTENTS={
    {id="me_status",phrases={["how am i"]=12,["am i ok"]=12,["am i okay"]=12,["am i alright"]=12,
        ["am i hurt"]=12,["am i sick"]=12,["check me"]=12,["scan me"]=12,["what is wrong with me"]=14,
        ["how is my health"]=14,["check my health"]=14,["am i healthy"]=12,["diagnose me"]=12,["my wounds"]=12,["my injuries"]=12}},
    {id="me_infected",phrases={["am i infected"]=16,["am i going to turn"]=16,["will i turn"]=16,
        ["did it get in"]=14,["do i have the virus"]=16,["do i have knox"]=16,["am i clean"]=14,
        ["was the scratch bad"]=14,["is the bite bad"]=14,["how long do i have"]=16,
        ["how long until i turn"]=16,["is it all in my head"]=14,["my infection"]=14}},
    {id="me_need",phrases={["am i hungry"]=14,["am i thirsty"]=14,["am i tired"]=14,["am i exhausted"]=14,
        ["do i need sleep"]=14,["do i need to eat"]=14,["am i drunk"]=14,["am i cold"]=14,["am i hot"]=14,
        ["am i stressed"]=14,["am i in pain"]=14,["my needs"]=14,["am i carrying too much"]=14}},
    {id="me_look",phrases={["how do i look"]=14,["do i look ok"]=14,["what do i look like"]=14}},
    {id="me_kills",phrases={["how many zombies have i killed"]=18,["how many have i killed"]=16,
        ["my kills"]=16,["kill count"]=14,["how many kills"]=14}},
    {id="me_survived",phrases={["how long have i survived"]=18,["how long have i been alive"]=16,
        ["how many days have i survived"]=18,["days survived"]=16}},
    {id="me_where",phrases={["where am i"]=16,["what is this place"]=14,["what town is this"]=16,["what building is this"]=16}},
    {id="me_skills",phrases={["what are my skills"]=16,["what am i good at"]=16,["my skills"]=14}},
    {id="me_file",phrases={["my file"]=16,["what do you know about me"]=16,["my traits"]=16}},
}
D.TIME_INTENTS={
    {id="helicopter",words={helicopter=10,chopper=10,flyover=10,aircraft=8},
        phrases={["when is the helicopter"]=16,["was that a helicopter"]=16}},
    {id="water_off",phrases={["water shut off"]=16,["water go off"]=16,["water stop"]=14,
        ["when does the water"]=16,["when will the water"]=16,["water shutoff"]=16}},
    {id="power_off",phrases={["power go out"]=16,["power go off"]=16,["when does the power"]=16,
        ["when will the power"]=16,["lights go out"]=14,["electricity go off"]=16,["grid fail"]=16,["power shutoff"]=16}},
    {id="forecast",words={forecast=12,tomorrow=9,tonight=8},
        requires={"forecast","weather","rain","raining","snow","snowing","storm","stormy","fog","foggy",
            "frost","freezing","temperature","hot","cold","sunny","cloudy","windy"},
        phrases={["will it rain"]=14,["weather tomorrow"]=16,
        ["is a storm coming"]=16,["will it snow"]=14,["next storm"]=16,["going to rain"]=14,
        ["next snow"]=16,["next fog"]=16,["next frost"]=16,["weather in"]=12,["weather next"]=12,
        ["rain in"]=12,["snow in"]=12,["forecast for"]=12}},
    {id="daylight",phrases={["when does it get dark"]=16,["when is sunset"]=16,["when is dawn"]=16,
        ["how long until morning"]=16,["how long until dark"]=16,["when is sunrise"]=16,
        ["when does the sun"]=14,["how long until night"]=16}},
    {id="calendar",phrases={["what is coming"]=14,["what happens next"]=14,["what should i prepare for"]=16,
        ["any dates"]=12,["the schedule"]=12,["what is on the calendar"]=16}},
}
local P=D.pools
P.teaser_body={"I need medical tables before I can read you. Boot EMMA on a clinic, pharmacy or research computer, or recover twelve ordinary machines."}
P.teaser_calendar={"I need county schedules. Boot EMMA on an official computer, or recover twelve ordinary machines. Dawn and dusk I can tell you now."}
P.me_fine={
    "Nothing wrong with you that I can find. I looked thoroughly. You should feel complimented.",
    "Your body is in better condition than the county. A low bar. You cleared it.",
    "You are well. I checked twice, because it is unusual.",
}
P.me_infected={
    "Knox infection, confirmed. I will not make a joke about this.",
    "I have read you three times hoping I was wrong. I am not wrong. You are infected.",
    "You are carrying it. Tell your people. Do not make them find out alone.",
}
P.boot_infected_lead={
    "Before you ask me anything, there is something about you.",
    "Stop. Before the camp report, there is something about you.",
}
P.me_fake={
    "No Knox infection detected. The false-infection symptoms are real; the virus is not present in this reading.",
    "Not infected, {name}. Your body is rehearsing the worst. Tell it the performance is cancelled.",
}
P.me_clean={
    "No Knox infection detected. That does not rule out an ordinary wound infection. Keep looking after the wound.",
    "No Knox infection detected. Your blood is your own. All of it, for now.",
}
P.me_bleeding={"Your {part} is bleeding. Typing can wait. You cannot.","You are bleeding from the {part}. Bandage it. Now."}
P.me_deep={"There is a deep wound on your {part}. It needs treatment, not optimism."}
P.me_fracture={"Your {part} is fractured. Keep it supported and avoid putting it under strain."}
P.me_lodged={"Something is still in your {part}. Glass or lead. Deal with the lodged object before closing the wound."}
P.me_burn={"Burned {part}. Clean it, cover it, and stay away from whatever did that."}
P.me_dirty={"The bandage on your {part} is filthy. A dirty bandage is a wound wearing a hat."}
P.me_festering={"The wound on your {part} has an ordinary infection. That is separate from Knox. Keep it clean and treated."}
P.me_scratch={"A scratch on your {part}. Keep it clean and covered while it heals."}
P.me_cut={"A cut on your {part}. Keep it clean and covered while it heals."}
P.me_bite={"A bite on your {part}. Treat the wound. The separate blood reading tells us whether Knox took."}
P.me_hungry={"Hunger detected. I would suggest the beans. I always suggest the beans.","You are hungry. Eat something safe before you make another plan."}
P.me_thirsty={"You need water. Clean water. Boiled, if it came from anywhere interesting."}
P.me_tired={"You are tired, {name}. Lock up, lie down. I will keep watch. Figuratively."}
P.me_winded={"You are out of breath. Rest a minute. The dead do not get tired. You do. Plan around it."}
P.me_panic={"You are frightened. Reasonable. Breathe slower. Panic burns fuel you do not have."}
P.me_stress={"You are wound tight. Do one small thing with your hands. Then the next one."}
P.me_unhappy={"Low spirits. Find something that is not a chore. Talk to somebody who is not a computer."}
P.me_bored={"Bored. Read something, fix something, talk to someone. I volunteer, reluctantly."}
P.me_angry={"Anger detected. Use it on a woodpile, not on your people."}
P.me_sick={"You have a sickness reading. That alone does not tell me its cause. The Knox reading is separate."}
P.me_cold_illness={"You have a cold. Rest, warmth, and try not to sneeze near anything dead."}
P.me_drunk={"Intoxicated. I will answer your questions. Leave the driving for later."}
P.me_pain={"You are in pain. Treat the cause and give yourself time to rest."}
P.me_wet={"Wet clothes steal heat. Get dry before the cold finds out. It always finds out."}
P.me_windchill={"Wind chill is affecting you. Get sheltered, dry and warm."}
P.me_cold={"You are too cold. Get dry, get warm, and stop typing with numb fingers."}
P.me_hot={"You are overheating. Take off a layer. Find shade. Drink."}
P.me_heavy={"You are carrying too much. Your knees have filed a complaint. I am forwarding it."}
P.me_smell={"The stench is affecting you. Move away from the bodies."}
P.me_injured={"Your overall health is reduced. Check the wound readings and look after yourself."}
P.me_uncomfortable={"Discomfort recorded. Check what you are wearing and carrying."}
P.me_cant_sprint={"You cannot sprint comfortably at the moment. Do not build your escape plan around it."}
P.me_look={"You look like someone who has lasted {days} in this county. That is a compliment. Mostly."}
P.me_kills={"{kills} of them since you arrived. I count. Somebody has to.","You have put down {kills}. Each one was somebody once."}
P.me_kills_none={"None. Either you are very careful or very lucky. I suspect the second."}
P.me_survived={"You have lasted {days}. Most people managed considerably less. Do not get comfortable.","{days} survived. I keep the count. You keep adding to it. A good arrangement."}
P.me_where={"You are in {place}, talking to me. Of all the places to be, it is a defensible one."}
P.me_skills={"On file: {skills}. Everything else is enthusiasm."}
P.news_bitten_blind={"I cannot read your blood yet. Treat the wound and find me a clinic or pharmacy computer. Twelve ordinary machines will also recover the medical index."}
P.news_hurt_blind={"Look after the wound first. I need a medical index before I can read your own condition."}
P.heli_before={"A helicopter may sweep the county on {day}, between {start} and {finish}. It is not a rescue. Be indoors."}
P.heli_soon={"The possible flyover is {day}, between {start} and {finish}. Fill the water, bar the doors, stay in."}
P.heli_window={"The helicopter's possible flight window is open. I cannot confirm that it is overhead. Stay indoors and listen."}
P.heli_now={"The helicopter is active. Stay inside. Do not make yourself interesting."}
P.heli_after={"The recorded flight window was {day}. I cannot prove whether the aircraft reached you."}
P.heli_none={"No flights on the current county schedule. The sky is not offering you a rescue."}
P.water_before={"The water stops on {day}, in about {days}. Fill everything that holds water, then the things that do not."}
P.water_soon={"The water shutoff is {day}. Fill your containers while the taps still work."}
P.water_after={"The water shutoff was {day}. Some fixtures may still hold a little. Plan for rain collection and purification."}
P.water_never={"The water company's schedule shows no shutoff. Either they planned well or they stopped planning."}
P.power_before={"The grid fails on {day}, in about {days}. Charge what can be charged. Cook what can be cooked."}
P.power_soon={"The power shutoff is {day}. Prepare another supply before the refrigerator becomes a cupboard."}
P.power_after={"The scheduled grid shutoff was {day}. Check the actual supply before trusting anything that hums."}
P.power_restored={"The grid's original shutoff was {day}. You brought some of it back. I noticed that warmly."}
P.power_never={"The power company shows no shutoff date. Optimists to the end."}
P.forecast={"Forecast for {day}: {sky}, around {tempC} C, {tempF} F. Plan your errands around it, or do not, and get wet."}
P.forecast_storm={"Storm conditions are forecast {when}. Thunder covers footsteps. Theirs and yours."}
P.forecast_cold={"Freezing temperatures are forecast {when}. Find blankets before you find out how cold."}
P.forecast_snow={"Snow is forecast {when}. Dress for the journey home as well as the journey out."}
P.forecast_fog={"Fog is forecast {when}. Being difficult to see works both ways."}
P.daylight_dusk={"Next dusk: {day} at {time}. You have about {hours}. Be where you are sleeping before then."}
P.daylight_dawn={"Next dawn: {day} at {time}. About {hours} to go. One of the few promises the county still keeps."}
P.calendar_lead={"The schedule, in order of inconvenience:"}
SC.TerminalLines.THINK.body={"Reading your condition...","Checking the operator file..."}
SC.TerminalLines.THINK.calendar={"Reading the county schedule...","Checking the almanac..."}
return D
