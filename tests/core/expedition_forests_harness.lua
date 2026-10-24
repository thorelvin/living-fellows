-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local F = SC.ExpeditionForests
local checks, queried, squares = 0, 0, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "forest check " .. checks .. ": " .. message)
end
local actor = { x = 199, y = 199, z = 0 }
SC.GameplayUtil = { position = function(a) return a.x, a.y, a.z end }
SC.BaseLife = { isInside = function(p) return p.x >= 180 and p.x <= 198 and p.y >= 180 and p.y <= 198 end }
SC.Factions = { describeLocation = function() return { nearestStreet = { name = "Oak Street" } } end }
local function zone(kind, x, y, width, height)
    return { getType = function() return kind end, getX = function() return x end,
        getY = function() return y end, getWidth = function() return width end,
        getHeight = function() return height end,
        contains = function(_, px, py) return px >= x and px < x + width and py >= y and py < y + height end }
end
local zones = { zone("Forest", 100, 100, 30, 30), zone("DeepForest", 205, 205, 90, 90),
    zone("Vegitation", 199, 199, 90, 90), zone("Forest", 180, 180, 19, 19) }
local grid = { getZonesIntersecting = function(_, x, y, z, width, height)
    queried = queried + 1
    local list = {}
    for _, v in ipairs(zones) do
        if v:getX() < x + width and v:getX() + v:getWidth() > x
            and v:getY() < y + height and v:getY() + v:getHeight() > y then list[#list + 1] = v end
    end
    return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
end }
function getWorld() return { getMetaGrid = function() return grid end } end
local result, reason
for _ = 1, 150 do result, reason = F.preview(actor, "straight", { radius = 1000 }); if result then break end end
check(result and #result.candidates == 3, "automatic lookup returns at most three separated forest patches")
check(result.candidates[1].anchor.x == 205 and result.candidates[1].anchor.y == 205,
    "an adjacent metadata cell beats a farther forest in the starting cell")
check(result.candidates[1].label:find("Oak Street", 1, true), "labels use direction and a human street name")
check(queried <= 9, "distance lower bounds stop a completed nearest-site scan")
for _, site in ipairs(result.candidates) do
    check(F.validSite(site) and site.type ~= "Vegitation" and not SC.BaseLife.isInside(site.anchor),
        "only forest metadata outside camp is eligible")
end
local site = result.candidates[1]
local trees = 0
local diagnostics = {}
SC.GameplayUtil.diagnostic = function(_, _, message) diagnostics[#diagnostics + 1] = message end
SC.GameplayUtil.gridSquare = function()
    squares = squares + 1
    return { getTree = function()
        trees = trees + 1
        return { getObjectIndex = function() return 0 end, getSize = function() return trees <= 2 and 1 or 2 end }
    end }
end
local verified = F.verify(site, actor)
check(verified == true and squares == 3, "one actual mature tree is sufficient; saplings do not count")
check(#diagnostics == 1 and diagnostics[1]:find("matureTrees=1", 1, true)
    and diagnostics[1]:find("reason=forest_verified", 1, true), "verification logs actual terminal evidence once")
SC.GameplayUtil.gridSquare = function() squares = squares + 1 return nil end
local before = squares
local ready, why = F.verify(site, actor)
check(ready == nil and why == "forest_verify_pending" and squares - before == 48,
    "arrival checks yield after 48 native squares")
for _ = 1, 8 do ready, why = F.verify(site, actor); if ready ~= nil then break end end
check(ready == false and why == "forest_unloaded", "unloaded terrain is never reported as verified timber")
check(#diagnostics == 2 and diagnostics[2]:find("loadedSquares=0", 1, true),
    "a failed verification logs loaded-square evidence once, never every scan slice")
F.reset()
zones = { zone("Forest", 205, 205, 70, 70), zone("DeepForest", 600, 200, 70, 70) }
local reached, rejected = nil, 0
for _ = 1, 200 do
    local batch, why = F.preview(actor, "drive", { radius = 1000, cacheKey = "car-A" })
    if batch then
        for _, patch in ipairs(batch.candidates) do
            if patch.anchor.x >= 600 then reached = patch break end
            check(F.reject(actor, "drive", patch.id, "car-A"), "unusable drive patches admit bounded continuation")
            rejected = rejected + 1
        end
    elseif why ~= "forest_scan_pending" then break end
    if reached then break end
end
check(reached and rejected >= 3, "rejecting the closest three resumes discovery to a farther roadside forest")
local walking
for _ = 1, 150 do walking = F.preview(actor, "straight", { radius = 1000 }); if walking then break end end
check(walking and walking.candidates[1].anchor.x == 205,
    "drive-specific rejection never poisons subsequent walking discovery")
local changedCar
for _ = 1, 150 do changedCar = F.preview(actor, "drive", { radius = 1000, cacheKey = "car-B" }); if changedCar then break end end
check(changedCar and changedCar.candidates[1].anchor.x == 205,
    "changing car admission identity clears stale route rejections")
check(not F.reject(actor, "drive", changedCar.candidates[1].id, "car-A"),
    "stale car rejection callbacks cannot modify a new discovery session")
local nearCar
for _ = 1, 40 do
    nearCar = F.nearCar(actor, { x = 600.4, y = 200.2, z = 0 }, reached, "road-stop-A")
    if nearCar then break end
end
check(nearCar and #nearCar.candidates == 2,
    "a separate bounded road-stop scan finds two alternatives beyond the global nearest three")
for _, patch in ipairs(nearCar.candidates) do
    check((patch.anchor.x - 600)^2 + (patch.anchor.y - 200)^2 <= 64^2
        and (patch.anchor.x - reached.anchor.x)^2 + (patch.anchor.y - reached.anchor.y)^2 >= 24^2
        and patch.distance <= 1000,
        "car-side alternatives remain distinct, close to the road stop and inside the origin search radius")
end
F.reset()
zones = { zone("Vegitation", 200, 200, 100, 100), zone("Forest", 4000, 4000, 20, 20) }
for _ = 1, 150 do result, reason = F.preview(actor, "road", { radius = 1000 }); if reason ~= "forest_scan_pending" then break end end
check(result == nil and reason == "no_suitable_forest", "out-of-radius forests and nonforest zones are rejected")
check(F.preview(actor, "teleport", {}) == nil, "unsupported travel modes fail closed")
check(not F.validSite({}), "malformed persisted forest descriptors fail closed")
print("EXPEDITION_FORESTS_KAHLUA_PASS checks=" .. checks)
