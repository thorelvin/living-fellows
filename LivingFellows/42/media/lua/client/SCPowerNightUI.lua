-- SPDX-License-Identifier: MIT
-- Existing EMMA terminal service pages provide keyboard/mouse pagination.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
SC.PowerNightUI=SC.PowerNightUI or {}
local UI=SC.PowerNightUI
local function option(label,action,value) return {label=label,serviceAction=action,serviceValue=value} end
function UI.menu(window)
    local page=window.menuPage
    if page~="power_night" and page~="pn_library" and page~="pn_copy" then return nil end
    local snap=SC.PowerNight.snapshot()
    if page=="power_night" then
        return {option("Tonight / broadcast status","pn_status"),
            option("Archive recordings","page","pn_library"),option("Copy a recording (keep original)","page","pn_copy"),
            option(snap.enabled and "Disable nightly broadcasts" or "Enable nightly broadcasts","pn_toggle"),
            option("Back to services","page","home_services")}
    elseif page=="pn_library" then
        local rows={}
        for _,row in ipairs(snap.library or {}) do rows[#rows+1]=option((row.medium=="tv" and "TV: " or row.medium=="radio" and "Radio: " or "Unavailable: ")..row.title,"pn_record",row.id) end
        rows[#rows+1]=option("Back to Power Night","page","power_night")
        return rows
    elseif page=="pn_copy" then
        local rows={}
        for _,item in ipairs(SC.ControlUtil.items(window.player)) do
            local row=SC.PowerNightCatalog.item(item)
            if row then rows[#rows+1]=option(row.title,"pn_copy",item) end
        end
        if #rows==0 then rows[#rows+1]=option("No compatible recordings carried","pn_status") end
        rows[#rows+1]=option("Back to Power Night","page","power_night")
        return rows
    end
end
function UI.status()
    local s=SC.PowerNight.snapshot()
    if not s.available then return {s.reason} end
    local lines={"POWER NIGHT / EMMA county archive", "Every evening, 20:00-21:00. "..(s.enabled and "Enabled." or "Disabled."),
        s.grid and "Grid power is available." or "The county transmitter is off: grid power required.",
        "TV: EMMA Archive TV / "..tostring(s.tv or "unavailable")..". Radio: "..(s.radio and string.format("%.1f FM",s.radio/1000) or "unavailable")..".",
        "Turn on and tune your receiver yourself. Keep the volume sensible.",
        "Available companions may join. Duties, needs and emergencies come first."}
    if s.night then
        for _,medium in ipairs({"tv","radio"}) do
            local row=SC.PowerNightCatalog.resolve(s.night[medium])
            lines[#lines+1]=(medium=="tv" and "Tonight on TV: " or "Tonight on radio: ")..(row and row.title or "No available recording")
        end
    else lines[#lines+1]="Tonight's programmes are selected at 20:00; newly archived recordings are favoured." end
    lines[#lines+1]="Reruns share lessons with physical recordings. Each survivor learns a lesson once."
    return lines
end
function UI.input(window,action,value,show)
    if action=="pn_status" then show(window,UI.status())
    elseif action=="pn_record" then
        local row=SC.PowerNightCatalog.resolve(value)
        show(window,row and (row.title.." / "..(row.medium=="tv" and "TV" or "radio")..". Kept in the shared county archive.")
            or "This recording is currently unavailable. Its archive entry is preserved.")
    elseif action=="pn_toggle" then
        local _,message=SC.PowerNight.setEnabled(window.player,window.object,not SC.PowerNight.snapshot().enabled)
        show(window,message)
    elseif action=="pn_copy" then
        local item,player,computer=value,window.player,window.object
        if not SC.PowerNight.computerAccess(player,computer) then show(window,"Computer access was lost.") return true end
        local okay,message=SC.TerminalServices.install(player,computer,function()
            return SC.PowerNight.copy(player,computer,item)
        end,100)
        show(window,okay and "Copying queued. Keep the original recording with you and stay at the powered computer." or message)
    else return false end
    return true
end
return UI
