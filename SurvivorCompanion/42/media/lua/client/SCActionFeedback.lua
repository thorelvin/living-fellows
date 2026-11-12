-- SPDX-License-Identifier: MIT
-- Player wording only: reading feedback never starts, retries or cancels work.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ActionFeedback = SC.ActionFeedback or {}
local F = SC.ActionFeedback

local wording = {
    storage_full = { "Destination storage is full.", "Free space or permit another destination." },
    storage_missing = { "No permitted storage is available.", "Mark a suitable destination and allow deposits." },
    unloaded = { "The destination is not loaded.", "Return nearby; the task can continue when the area loads." },
    path = { "A route could not be found.", "Check access to the destination, including doors and stairs." },
    crowded = { "Another person is in the way.", "Waiting for the way to clear.", true },
    supplies = { "Required supplies are unavailable.", "Check permitted storage, available stock and other workers' claims." },
    tool = { "A usable tool is missing.", "Provide an unbroken tool in permitted storage or the companion's inventory." },
    capacity = { "There is not enough safe carrying space.", "Free carrying space or provide a suitable bag or vehicle." },
    unsafe = { "Work paused because the area is unsafe.", "The companion will reassess after the danger passes.", true },
    night = { "Outdoor work is paused for the night.", "Work can resume in daylight or after a night-work policy change.", true },
    interrupted = { "The action was interrupted.", "It can be attempted again after the current activity finishes." },
    uncertain = { "The previous item transfer needs checking.", "Review the task before retrying; item ownership must be confirmed." },
    watch = { "Under watch: indoor duties only.", "Review the camp decision to change the restriction." },
    restricted = { "Camp work is paused by a camp decision.", "Review the decision; food, drink, rest and medical care remain available." },
    preparing = { "Still looking for usable supplies.", "The search is continuing in bounded steps.", true },
    animal_zone = { "The animal enclosure could not be checked safely.", "Keep the whole animal zone within camp work reach (normally 30 tiles beyond camp), and stay nearby until it loads." },
    animal_native = { "Animal care stopped before its result was confirmed.", "Check the animal, trough or hutch. The farmer will retry without replacing missing items." },
    animal_feed_trough_missing = { "Animals need a separate feed trough.", "Place an empty trough in the animal zone. Each trough holds feed or water." },
    animal_water_trough_missing = { "Animals need a separate water trough.", "Place an empty trough in the animal zone. Existing feed will be left intact." },
    animal_hutch_missing = { "The chicken pen has no usable hutch.", "Place a compatible hutch inside its animal zone." },
    animal_roost_delayed = { "Some chickens have not returned to shelter.", "The farmer is leaving the door open. Check the hutch entrance and any birds still outside." },
    animal_cattle_enclosure_small = { "The pasture is below its animals' native enclosure minimum.", "Expand or connect the animal zone. Care will continue without moving the herd." },
    animal_cattle_unsafe = { "Animal care is paused near an agitated bull or ram.", "Keep the farmer clear until the animal settles. The job will retry." },
    animal_shear_stressed = { "The sheep is too stressed to shear safely.", "Let it settle. Collected wool is preserved and the farmer will retry." },
    animal_shear_not_ready = { "No eligible adult sheep could be confirmed.", "Shearing needs a healthy, unled sheep at least 200 days old, with a full enough fleece. Lambs are left alone." },
    animal_shear_tool_unavailable = { "The farmer needs usable shears.", "Put unbroken manual shears or charged electric shears in permitted Farming or Tools storage." },
    animal_wool_storage_missing = { "Wool delivery is waiting for storage with room.", "Allow deposits and clear space in Crafting or General storage. No more fleece is cut while delivery is blocked." },
    animal_shear_load_full = { "The farmer has reached a safe wool carrying limit.", "The current batch will be delivered before shearing continues. Clear unnecessary carried gear if even one wool item will not fit." },
    animal_shear_uncertain = { "A shearing result could not be confirmed safely.", "Inspect the sheep and its nearby wool. Existing items are preserved; missing or ambiguous wool will never be replaced." },
    animal_wool_missing = { "The exact shorn wool could not be located.", "Check the pasture and the original farmer. Its receipt is retained, and no replacement wool will be created." },
    animal_shear_floor_unavailable = { "The sheep's ground could not be checked safely.", "Let the area load and clear loose clutter beside the animal, then retry." },
    animal_milk_stressed = { "The animal is too stressed to milk safely.", "Farmers can calm animals in managed pens. Keep water, feed and a safe approach available; milking will retry after a pause." },
    animal_soothe_unavailable = { "The animal cannot be approached safely for calming.", "Keep it in its managed pen, unled and out of danger. Farmers use the ordinary petting action when it permits handling." },
    animal_soothe_uncertain = { "The calming action could not be confirmed.", "The animal has been released. This attempt will not be replayed; a later visit can be offered after the cooldown." },
    farm_water_carry_capacity_low = { "The farmer cannot safely carry another watering dose.", "Free some carrying space or let the exhausted farmer rest. Existing water and borrowed equipment are preserved." },
    animal_milk_food_storage_missing = { "Milk delivery is waiting for storage with room.", "Mark an empty compatible barrel as Milk, or clear space in Fresh food or Regular food storage. Cow and sheep milk remain separate. Retry is automatic after three minutes." },
    milk_storage_incompatible = { "This container cannot store milk safely.", "Use an empty compatible fluid barrel or one containing only cow or sheep milk. Existing water or other contents will not be discarded." },
    animal_manure_storage_missing = { "Manure delivery is waiting for storage.", "Mark a composter or a spare crate as Manure and allow deposits. Full composters use marked crates as overflow. Retry is automatic after three minutes." },
    animal_manure_capacity = { "This tile has more manure than the farmer can safely collect.", "Free carrying space or clear part of the pile manually. The whole native pickup must fit; other farm duties can continue." },
    animal_manure_uncertain = { "The collected manure could not be confirmed safely.", "Check the original farmer and collection tile. Exact item receipts are retained; no replacement manure will be created." },
    medic_kit_unavailable = { "No first aid kit is available.", "Put a compatible kit in permitted Medical storage or give one to the Medic. Loose supplies remain usable." },
    medic_kit_supplies_missing = { "The Medic is short of usable supplies.", "Stock clean dressings and a splint in permitted Medical storage. Kit stocking retries after three minutes and does not prevent urgent treatment." },
    animal_milk_container_unavailable = { "The farmer needs an empty milk container.", "Put an empty, compatible bucket, pot or bottle in permitted Farming storage, with carrying room available." },
    animal_milk_approach_timeout = { "The farmer could not settle beside the animal.", "Keep a clear space beside it. It has been released and the job will retry." },
    animal_milk_daylight = { "Milking is waiting for daylight.", "Farmers milk between 07:00 and 20:00. Collected milk can still be delivered." },
    animal_milk_not_ready = { "The animal is not ready for milking.", "Only healthy, lactating adult cows and ewes with readable udder and ownership data are eligible." },
    animal_milk_daily_limit = { "Milking is paused by the daily limit.", "The farmer can finish this animal's existing delivery, then waits for the next game day." },
    animal_milk_cow_unavailable = { "The animal could not be confirmed in its loaded camp pasture.", "The farmer will retry when it returns. Existing milk is preserved." },
    animal_milk_approach_missing = { "Neither side of the animal is accessible for milking.", "Clear space around it and the trough. The farmer will retry without moving the animal." },
    animal_milk_resting = { "The animal is resting after interrupted milking.", "The farmer will retry after at least one game hour. Collected milk is preserved." },
    animal_milk_container_missing = { "The borrowed milk container could not be located safely.", "Its receipt is retained. Check the farmer and pasture; no container or milk will be replaced." },
    animal_milk_uncertain = { "Milking stopped because its measurements could not be confirmed.", "The exact container is retained for recovery. No milk will be added to compensate." },
    animal_milk_container_changed = { "The borrowed milk container is no longer empty or compatible.", "Its contents will be preserved. Return an empty compatible container to Farming storage." },
    animal_zone_limit = { "The camp already tracks its maximum number of animal zones.", "Use an existing enclosure. Known flock identities are retained so missing birds cannot be locked outside." },
    radio_work_no_power = { "Radio watch is paused: the computer has no power.", "Restore its power. Shift progress is saved and the job retries automatically.", true },
    radio_work_radio_missing = { "The computer's two-way radio is missing or broken.", "Mount a working walkie-talkie; the operator's progress is saved." },
    radio_work_locked = { "The assigned computer is locked.", "Unlock it to resume the saved radio shift." },
    unknown = { "The task stopped before completion.", "Review its details and available retry controls." },
    quarantine_area_missing = { "Quarantine is pending: no area is marked.", "Mark a reachable quarantine area. Indoor duties continue under watch." },
    quarantine_area_unloaded = { "Quarantine is pending: the area is not loaded.", "Return nearby. Indoor duties continue under watch." },
    quarantine_unreachable = { "Quarantine is pending: the area cannot be reached.", "Check its doors and stairs, or move the area. Indoor duties continue under watch." },
    exile_route_unavailable = { "Departure is pending: no safe route out was found.", "Clear an exit, retry departure or release the restriction." },
    authorization_expired = { "The final decision needs confirmation again.", "Review the current situation before authorizing an irreversible action." },
    final_action_needs_review = { "A previous irreversible action needs inspection.", "Check the companion and release the decision when appropriate. It will not be replayed automatically." },
    mercy_executor_unavailable = { "The chosen companion cannot carry out this decision.", "Choose the outcome again to select an available companion, or choose a reversible option." },
    crisis_decision_changed = { "The camp decision changed while this control was open.", "Review the updated decision before trying again." },
    private_camp_decision = { "Camp duties are restricted.", "Review or release the restriction; its private cause has not been disclosed." },
    waiting_for_safety = { "Waiting for a safe, free moment.", "Urgent orders, self-care and nearby danger take priority. The decision remains pending.", true },
    final_action_requires_weapon = { "The chosen companion has no usable weapon for this decision.", "Provide equipment and review the decision, or choose a reversible option." },
    native_final_action_unavailable = { "This final action could not start.", "Review the companion and equipment, or choose a reversible option." },
    native_end_life_unavailable = { "The required native action is unavailable.", "Check Support for bridge status, or choose a reversible option." },
    native_bleach_drink_unavailable = { "The required drinking action is unavailable.", "Check Support or choose a reversible option." },
    bleach_missing = { "The companion has no usable bleach for this decision.", "Check the supplies or choose a different outcome." },
    bite_not_confirmed = { "A bite has not been confirmed to you.", "Review witnessed reports or medical findings before considering a final outcome." },
    safety_delay_active = { "The decision is still in its safety delay.", "Wait briefly, then review and confirm it deliberately." },
    crisis_actor_busy = { "This person is already involved in another final decision.", "Resolve that decision or choose another available companion." },
}
local exact = {
    destination_full = "storage_full", floor_storage_full = "storage_full", haul_destinations_full = "storage_full",
    floor_storage_missing = "storage_missing", floor_storage_unavailable = "storage_missing",
    floor_pickup_animation_replaced = "interrupted", loot_animation_replaced = "interrupted",
    work_side_busy = "crowded", watch_indoor_duty = "watch", infection_restriction = "restricted",
    cleaning_supplies_scanning = "preparing", haul_scan_pending = "preparing",
    log_yard_rope_missing = "supplies", log_yard_rope_search_pending = "preparing",
    log_yard_rope_moved = "supplies", log_yard_unloaded = "unloaded",
    log_yard_craft_receipt_uncertain = "uncertain",
    log_yard_unstack_receipt_uncertain = "uncertain", log_yard_bundle_metadata_missing = "uncertain",
    log_yard_unstack_reconciling = "preparing",
    animal_audit_pending = "preparing", animal_audit_incomplete = "animal_zone",
    animal_flock_not_loaded = "animal_zone", animal_zone_unavailable = "animal_zone",
    animal_zone_outside_camp = "animal_zone", animal_action_incomplete = "animal_native",
    animal_sheep_unsafe = "animal_cattle_unsafe", animal_shear_capacity_unknown = "capacity",
    animal_wool_carrier_unavailable = "animal_wool_missing",
    animal_egg_recovery_pending = "uncertain", farm_food_storage_missing = "storage_missing",
}

function F.text(key, fallback, ...)
    local value
    if type(getText) == "function" then
        local ok, translated = pcall(getText, "UI_SC_Feedback_" .. key, ...)
        if ok then value = translated end
    end
    if value and value ~= "UI_SC_Feedback_" .. key then return value end
    local args = { ... }
    local result = (fallback or key):gsub("%%(%d+)", function(index) return tostring(args[tonumber(index)] or "") end)
    return result
end

function F.reason(reason)
    reason = tostring(reason or "unknown")
    local code = reason:match("^([^:]+)") or reason
    local kind = exact[code] or (wording[code] and code)
    if not kind then
        if code:find("unverified", 1, true) or code:find("unaccounted", 1, true)
            or code:find("owner_unknown", 1, true) then kind = "uncertain"
        elseif code:find("unloaded", 1, true) then kind = "unloaded"
        elseif code:find("path", 1, true) or code:find("route", 1, true)
            or code:find("approach_failed", 1, true) then kind = "path"
        elseif code:find("reserved", 1, true) or code:find("crowd", 1, true) then kind = "crowded"
        elseif code:find("capacity", 1, true) or code:find("carry", 1, true)
            or code == "floor_worker_full" then kind = "capacity"
        elseif code:find("tool_missing", 1, true) or code == "missing_tool" then kind = "tool"
        elseif code:find("missing", 1, true) or code:find("supply", 1, true) then kind = "supplies"
        elseif code:find("unsafe", 1, true) or code:find("danger", 1, true) then kind = "unsafe"
        elseif code:find("night", 1, true) then kind = "night"
        elseif code:find("planning", 1, true) or code:find("scan_pending", 1, true) then kind = "preparing"
        elseif code:find("interrupt", 1, true) or code:find("replaced", 1, true) then kind = "interrupted"
        else kind = "unknown" end
    end
    local row = wording[kind]
    return { cause = F.text(kind .. "_cause", row[1]), nextStep = F.text(kind .. "_next", row[2]),
        waiting = row[3] == true, kind = kind, known = kind ~= "unknown", rawReason = reason }
end

function F.failure(summary)
    if type(summary) ~= "table" then return nil end
    local failure = summary.feedbackVersion == 1 and summary.blocker
        or (summary.feedbackVersion == nil and not summary.active and summary.lastFailure)
    if type(failure) ~= "table" then return nil end
    local result = F.reason(failure.reason)
    result.action, result.targetLabel = failure.action, failure.targetLabel
    local retry = summary.retry
    if retry and retry.action == failure.action and retry.targetKey == failure.targetKey then
        result.remainingMs = math.max(0, tonumber(retry.remainingMs) or 0)
        result.automatic = retry.exhausted ~= true
    end
    result.at = failure.at
    return result
end

function F.describe(result)
    if not result then return nil end
    local value = result.cause .. " " .. result.nextStep
    if result.automatic and (result.remainingMs or 0) > 0 then
        value = value .. " " .. F.text("retry", "Retrying in %1 seconds.", math.ceil(result.remainingMs / 1000))
    end
    return value
end

function F.crisis(row)
    if row.pendingReason then return F.describe(F.reason(row.pendingReason)) end
    if row.stage == "awaiting_authorization" then
        return F.text("final_wait", "The camp proposed an irreversible outcome. Your confirmation is required; ordinary care continues.")
    end
    if row.finalAuthorized then return F.text("final_safe", "Authorized; waiting for a safe opportunity to carry out the decision.") end
    if row.restriction == "watch" then return F.describe(F.reason("watch_indoor_duty")) end
    if row.restriction == "quarantine" then return F.text("quarantined", "At the quarantine area. Work is paused; self-care remains available.") end
    if row.restriction == "exiled" then return F.text("exiled", "Ordered to leave camp. Review the decision to recall this companion.") end
    return F.text("discovered", "The camp is discussing a reported bite or observed symptoms. Review the known evidence and available choices.")
end

return F
