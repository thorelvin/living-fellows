-- SPDX-License-Identifier: MIT
-- Load the actual SCHomeTrip module first. These cases verify its public UI
-- reason mapping without route planning, native motion or game-world setup.
local Home=assert(SurvivorCompanion and SurvivorCompanion.HomeTrip)
local previousGetText=getText
getText=function(key) return "translated:"..key end
local cases={
    NoStop={"parking_approach_rejected","parking_approach_failed","parking_approach_out_of_range",
        "parking_approach_timeout","parking_approach_blocked","parking_streaming_stalled",
        "parking_failed_drive_not_at_road_end","parking_alignment_unavailable","parking_alignment_limit",
        "parking_alignment_failed","parking_alignment_timeout","parking_alignment_pose_or_speed",
        "parking_alignment_displacement","parking_alignment_room_changed","parking_alignment_target_not_forward",
        "parking bay requires a clear forward approach",
        "parking approach requires a clear two-point route within 15 tiles"},
    ParkingStopped={"parking_requires_arrived_drive","drive_owner_lost","native_released","released",
        "left_driver_seat","bridge_failure","survival_priority","parking car is missing","companion is not driving"},
    CarUnsettled={"parking_not_loaded"},
}
for suffix,reasons in pairs(cases) do
    for _,reason in ipairs(reasons) do
        local result=Home.reasonText(reason)
        assert(result=="translated:UI_SC_HomeTrip_"..suffix,
            "parking and released-drive failures must choose readable home-trip text: "..reason)
    end
end
assert(Home.reasonText("a future unknown diagnostic")=="translated:UI_SC_HomeTrip_Unavailable",
    "unknown diagnostic English must not become player-facing text")
getText=previousGetText
print("HOME_TRIP_REASON_UI_PASS")
