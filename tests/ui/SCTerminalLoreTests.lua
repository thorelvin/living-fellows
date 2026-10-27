-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,Lore=SC.Terminal,SC.TerminalLore
local check,before=T.check,T.checks
local player=T.player(101,100,0)
local computer=T.computer(T.square(100,100,0,true))
computer.data.LF_ComputerBrand="FamilyDentistry"
check(Terminal.open(player,computer),"expanded archive fixture opens")
local w=Terminal.window w:flush()
w.world.clock=function() return {year=1993,month=6,day=20,worldHours=300} end
local owner=w.system.archive
local security=w.system.locked
local function enter(value)
    w:setFocusMode("menu") w.entry:setText(value) w:submit() w:flush()
end
enter("3")
check(w.menuPage=="lore" and #w:menuOptions()<=9,"county-file menu respects immediate digit controls")
local found,categories={},{}
local function choose(field,value)
    for index,option in ipairs(w:menuOptions()) do
        if option[field]==value then enter(tostring(index)) return true end
    end
end
for _,category in ipairs(SC.TerminalKnowledge.CATEGORIES) do
    enter("county files")
    for _=1,#SC.TerminalKnowledge.CATEGORIES do
        if choose("referenceCategory",category.id) then break end
        check(choose("referencePage",w.referencePage+1),"category page has a single-key shortcut")
    end
    check(w.referenceCategory==category.id,"category can be opened by keyboard")
    categories[category.id]=true
    for page=0,#Lore.REFERENCE do
        check(w.referencePage==page and #w:menuOptions()<=9,"reference page accessible with a single key")
        check(#w:menuLayout()==#w:menuOptions(),"every numbered choice fits above the input and hints")
        local nextPage
        for index,option in ipairs(w:menuOptions()) do
            if option.referenceId then
                found[option.referenceId]=true
                enter(tostring(index))
                local entry=Lore.reference(option.referenceId)
                check(w.rows[#w.rows-1].text~=nil and w.system.archive==owner,"reading reference retains original owner")
                local added=#Terminal.wrap(entry.date.." - "..entry.title,w:columns())
                    +#Terminal.wrap(entry.text,w:columns())+#Terminal.wrap("Archived local file; not a current-world observation.",w:columns())
                check(w.scroll==math.max(0,added-w:visibleRows()),"long files open at their beginning")
            elseif option.referencePage==page+1 then nextPage=option.referencePage end
        end
        if not nextPage then break end
        check(choose("referencePage",nextPage),"next file page has a native digit shortcut")
    end
    check(choose("referenceCategory","__categories") and not w.referenceCategory,"Back returns to categories")
end
local count=0 for _ in pairs(found) do count=count+1 end
check(count==120,"all reference files are reachable through category menus")
local originalCore=getCore
for _,size in ipairs({{1280,720},{1920,1080},{2560,1440},{640,720},{960,540}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    w:refreshLayout()
    for _,category in ipairs(SC.TerminalKnowledge.CATEGORIES) do
        w.referenceCategory,w.referencePage,w.menuSelection=category.id,0,1
        for _=1,#Lore.REFERENCE do
            local options=w:menuOptions()
            check(#w:menuLayout()==#options,"wrapped archive choices fit at "..size[1].."x"..size[2])
            local nextPage
            for _,option in ipairs(options) do if option.referencePage==w.referencePage+1 then nextPage=option.referencePage end end
            if not nextPage then break end
            w.referencePage=nextPage
        end
    end
end
getCore=originalCore w:refreshLayout()
w.world.clock=function() return {year=1993,month=6,day=9} end
enter("county files")
check(not w:displayLocalFile(Lore.reference("knox_spread"),true),"direct selection cannot reveal a future record")
for _,entry in ipairs(w.referenceCatalog) do check(entry.id~="knox_spread","future titles are absent from menus") end
w:otherKey(Keyboard.KEY_ESCAPE)
check(w.menuPage==nil and w.menuSelection==1 and not w.closed,"Escape returns to the top menu safely")
w:close()
check(Terminal.open(player,computer),"archive can be reopened")
w=Terminal.window w:flush()
check(w.system.archive==owner and w.system.locked==security,"new lore does not change saved files or security")
w:close()
SC_TEST_REPORT=SC_TEST_REPORT.."; Expanded reference UI: "..(T.checks-before).." checks passed"
