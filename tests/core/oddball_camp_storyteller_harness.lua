-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Camp = SC.OddballCampStoryteller
local F = CampFixture
local checks = 0
local function check(condition, detail)
    checks = checks + 1
    assert(condition, "camp storyteller check " .. checks .. ": " .. detail)
end

local site = Camp.siteFor(SC.GameplayUtil.gridSquare(0, 0, 0), F.player,
    false)
check(site ~= nil and site.kind == "forest_camp",
    "a real tree-filled clearing is selected")
check(site.anchor.x == 0 and site.anchor.y == 0
    and (site.spawn.x ~= 0 or site.spawn.y ~= 0),
    "the campfire and actor use separate tiles")
check(site.house.id == "forest-camp:0:0"
    and site.house.bounds.x1 == -3
    and #site.house.interior >= 1 and #site.house.openings == 0,
    "outdoor camp has a savable faction territory")
F.actor = { actor = true, x = site.spawn.x, y = site.spawn.y, z = 0 }
F.group = { id = "storyteller-test", members = { { actorId = "silas" } },
    standing = "Wary", oddball = { id = "survivalist05_mid_storyteller",
        site = site } }
local built = Camp.onSpawn(F.group, F.actor)
check(built == true and F.fireBuilt == 1,
    "onSpawn places a native campfire")
local fire = F.fires["0:0"]
check(fire and fire.lit and fire.fuel == 180,
    "campfire is lit with finite fuel")
Camp.onSpawn(F.group, F.actor)
check(F.fireBuilt == 1, "reload does not duplicate campfire")
F.fires["0:0"] = nil
Camp.onSpawn(F.group, F.actor)
check(F.fireBuilt == 1,
    "a player-removed campfire stays removed after reload")

Camp.pulse(F.group, F.player, F.now)
check(F.group.discovered == true and #F.lines == 1,
    "Silas invites the nearby player to tell a story")
local options = Camp.menuOptions(F.group, F.player)
check(#options >= 5 and options[3].id == "tell_home_story",
    "the menu offers a choice of story")
local accepted = Camp.action(F.group, "tell_home_story", F.player)
check(accepted == true and F.group.oddball.stage == "telling"
    and F.group.oddball.storyBeat == 2,
    "player begins the story with spoken dialogue")
F.player.x = 20
F.now = F.now + 9000
Camp.pulse(F.group, F.player, F.now)
check(F.group.oddball.storyBeat == 2,
    "the conversation pauses when the player leaves")
F.player.x = 1
for _ = 1, 3 do
    F.now = F.now + 9000
    Camp.pulse(F.group, F.player, F.now)
end
check(F.group.oddball.stage == "story_heard"
    and F.group.oddball.storyTold == true,
    "four-beat story reaches a persistent conclusion")
check(F.reputation == 65 and F.group.standing == "Trusted",
    "he trusts the player after hearing the story")
check(Camp.canRecruit(F.group) == true,
    "Silas becomes recruitable after the story")
check(Camp.action(F.group, "recruit", F.player) == true
    and F.trial,
    "invitation uses the standard faction trial")
local prior = F.reputation
Camp.pulse(F.group, F.player, F.now + 9000)
check(F.reputation == prior, "story reward does not duplicate")
check(Camp.action(F.group, "ask_fishing", F.player) == true,
    "fishing dialogue remains available")

-- In a client VM the campfire is read through CCampfireSystem. Sending a
-- request is not a success readback and must not set campfirePlaced.
F.client = true
F.group.oddball.campfirePlaced = nil
F.commands = {}
F.fires["0:0"] = nil
F.group.id = "faction-oddball-1000-1"
local requested, requestReason = Camp.onSpawn(F.group, F.actor)
check(requested == true and requestReason == "campfire_request_pending"
    and F.group.oddball.campfirePlaced == nil and F.fireBuilt == 1,
    "client queues placement without pretending the fire exists")
local command = F.commands[1]
check(command and command.player == F.player
    and command.module == "LivingFellowsCampStory"
    and command.command == "place"
    and command.args.scene == "survivalist05_mid_storyteller",
    "client sends the exact server command")
Camp.onSpawn(F.group, F.actor)
check(#F.commands == 1, "client pending request is throttled")

F.client = false
local Server = SCStoryCampfireServer
check(F.serverCommandHandler == Server.onClientCommand,
    "server command handler is registered")
F.serverCommandHandler(command.module, command.command,
    command.player, command.args)
check(F.fireBuilt == 2 and F.fires["0:0"].lit,
    "validated server request places a real lit campfire")
local repeated, repeatReason = Server.place(command.player, command.args)
check(repeated == true and repeatReason == "already_handled"
    and F.fireBuilt == 2,
    "server request is idempotent")
local bad = { scene = command.args.scene, groupId = "not-an-encounter",
    x = 0, y = 0, z = 0 }
check(Server.place(F.player, bad) == false,
    "server rejects a forged group id")
bad.groupId = "faction-oddball-1000-2"
check(Server.place(F.player, bad) == false,
    "server permits only one story camp per world")

F.client = true
Camp.onSpawn(F.group, F.actor)
check(F.group.oddball.campfirePlaced == true and #F.commands == 1,
    "client confirms placement only from replicated campfire readback")
F.fires["0:0"] = nil
Camp.onSpawn(F.group, F.actor)
check(F.fireBuilt == 2 and #F.commands == 1,
    "removing the fire remains respected on client and server")
print("PASS: " .. checks .. " forest camp storyteller checks")
