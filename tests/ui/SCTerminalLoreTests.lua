-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,Lore=SC.Terminal,SC.TerminalLore
local check,before=T.check,T.checks
local player=T.player(101,100,0)
local computer=T.computer(T.square(100,100,0,true))
computer.data.LF_ComputerBrand="FamilyDentistry"
check(Terminal.open(player,computer),"expanded archive fixture opens")
local w=Terminal.window w:flush()
local owner=w.system.archive
local security=w.system.locked
local function enter(value)
    w:setFocusMode("menu") w.entry:setText(value) w:submit() w:flush()
end
enter("3")
check(w.menuPage=="lore" and #w:menuOptions()<=9,"county-file menu respects immediate digit controls")
local found={}
for page=0,5 do
    check(w.referencePage==page and #w:menuOptions()<=9,"reference page accessible with a single key")
    local options=w:menuOptions()
    for index,option in ipairs(options) do
        if option.referenceId then
            found[option.referenceId]=true
            enter(tostring(index))
            local entry=Lore.reference(option.referenceId)
            check(w.rows[#w.rows-1].text~=nil and w.system.archive==owner,"reading reference retains original owner")
            local added=#Terminal.wrap(entry.date.." - "..entry.title,w:columns())
                +#Terminal.wrap(entry.text,w:columns())+#Terminal.wrap("Archived local file; not a current-world observation.",w:columns())
            check(w.scroll==math.max(0,added-w:visibleRows()),"long files open at their beginning")
        end
    end
    if page<5 then
        local moved
        for index,option in ipairs(w:menuOptions()) do
            if option.referencePage==page+1 then enter(tostring(index)) moved=true break end
        end
        check(moved,"next reference page has a native digit shortcut")
    end
end
local count=0 for _ in pairs(found) do count=count+1 end
check(count==16,"all sixteen reference files are reachable")
w:otherKey(Keyboard.KEY_ESCAPE)
check(w.menuPage==nil and w.menuSelection==1 and not w.closed,"Escape returns to the top menu safely")
w:close()
check(Terminal.open(player,computer),"archive can be reopened")
w=Terminal.window w:flush()
check(w.system.archive==owner and w.system.locked==security,"new lore does not change saved files or security")
w:close()
SC_TEST_REPORT=SC_TEST_REPORT.."; Expanded reference UI: "..(T.checks-before).." checks passed"
