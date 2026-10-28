-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local Files,Lore,Brands,System=SC.TerminalFiles,SC.TerminalLore,SC.TerminalBrands,SC.TerminalSystem
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local seen,entries,kinds,branded={},{},{},{}
for _,profile in ipairs(Files.all()) do
    check(not seen[profile.id],"duplicate owner save identity") seen[profile.id]=true
    kinds[profile.kind]=true
    if profile.brand then
        check(Brands.BY_ID[profile.brand]~=nil,"owner references uncatalogued firm "..profile.brand)
        branded[profile.brand]=true
        check(Files.choose(profile.kind,17,profile.brand).brand==profile.brand,"firm-specific archive not selected")
    end
    for _,entry in ipairs(profile.entries) do
        check(not entries[entry.text],"duplicate archive prose") entries[entry.text]=true
        check(entry.date>="1993-07-01" and entry.date<="1993-07-09","future-dated owner entry")
    end
end
local kindCount=0 for _ in pairs(kinds) do kindCount=kindCount+1 end
check(#Files.all()==142 and kindCount>=24,"expanded contextual archive coverage incomplete")
local entryCount=0 for _ in pairs(entries) do entryCount=entryCount+1 end
check(entryCount==568,"each of the 142 owners has four distinct files")
check(Files.choose("media",3,"LouisvillePostLogo").id=="news_len",
    "newspaper inherited a television or radio operator archive")
-- Published IDs remain accepted independently of any changed selection pools.
local stable=Files.all()[1]
local state=System.create(19,"police",false,false,"saved-computer")
state.archive=stable.id
local restored=System.normalize(state)
check(restored.archive==stable.id and Files.get(restored.archive)==stable,"old archive identity rerolled on normalize")
for index=1,135 do
    state.archive=Files.all()[index].id
    check(System.normalize(state).archive==state.archive,"published owner archive changed after expansion")
end
local refIds={}
for _,entry in ipairs(Lore.REFERENCE) do
    check(not refIds[entry.id] and Lore.reference(entry.id)==entry,"reference identity invalid") refIds[entry.id]=true
    check(#entry.text<1024 and entry.text:find("[^\032-\126]")==nil,"reference file exceeds text contract")
end
check(#Lore.REFERENCE==150 and Lore.reference("not-a-file")==nil,"local reference catalog incomplete")
for room,kind in pairs({office_herald="media",jackiejayeoffice="media",gigamart="grocery",medclinic="clinic",
    schoollab="education",universitylibrary="education",laboratory="research",radiofactory="industry",
    pharmacy="pharmacy",motelreception="hotel",pawnshopoffice="retail",kidsbedroom="home",
    cardealershipoffice="mechanic",fireoffice="emergency",prisonstorage="security",officechurch="community"}) do
    check(Files.classify(room)==kind,"wrong room context "..room)
end
local savedU,savedDefinitions=SC.GameplayUtil,PrintMediaDefinitions
local squares,reads={},0
SC.GameplayUtil={call=function(object,method,...)
    if not object or type(object[method])~="function" then return nil,false end
    local okay,value=pcall(object[method],object,...) return value,okay
end,gridSquare=function(x,y,z) reads=reads+1 return squares[x..":"..y..":"..z] end}
local function list(rows) return {size=function() return #rows end,get=function(_,index) return rows[index+1] end} end
local function room(name) return {getName=function() return name end} end
local function computer(name,x,y,z,otherRooms,explicit)
    local own=room(name)
    local rows={own} for _,name in ipairs(otherRooms or {}) do rows[#rows+1]=room(name) end
    local building={getRooms=function() return list(rows) end}
    function own:getBuilding() return building end
    local square={getX=function() return x end,getY=function() return y end,getZ=function() return z end,
        getRoom=function() return own end,getBuilding=function() return building end,getObjects=function() return list({}) end}
    local object={getSquare=function() return square end,getModData=function() return {LF_ComputerBrand=explicit} end}
    return object,square,own
end
PrintMediaDefinitions={MiscDetails={fossoil1={location1={{x1=10,y1=20,x2=15,y2=25}}},
    tacodelpancho={location1={{x1=100,y1=100,x2=200,y2=200}}}}}
local object=computer("office",12,22,0)
check(Brands.identify(object)=="Fossoil","verified advert rectangle missed actual office")
object=computer("office",9,22,0)
check(Brands.identify(object)=="_office","neighbour across advertised boundary borrowed brand")
object=computer("bedroom",12,22,1)
check(Brands.identify(object)=="_home","upstairs private home inherited business advert")
object=computer("office",150,150,0)
check(Brands.identify(object)=="_office","whole-mall advert assigned one tenant to every unit")
object=computer("office",1000,1000,0,{"office_herald"})
check(Brands.identify(object)=="TheKentuckyHerald","unique branded room did not identify back office")
object=computer("office",1000,1000,0,{"office_herald","gigamart"})
check(Brands.identify(object)=="_office","mixed building borrowed a firm's identity")
object=computer("medicaloffice",1000,1000,0,{"office_herald"})
check(Brands.identify(object)=="_medical","specialist tenant inherited unrelated building brand")
object=computer("office",1000,1000,0,{},"homewardHouse")
check(Brands.identify(object)=="HomewardRealEstate","photo fragment did not canonicalise")
check(Brands.canonical("kk")=="knoxknews" and Brands.canonical("reporterImage")=="_media","duplicate and image-only identities remain exposed")
local square,own
object,square,own=computer("office",1000,1000,0)
local sign={getProperties=function() return {get=function(_,key) return key=="CustomName" and "Sign" or "Fossoil" end} end}
squares["1001:1000:0"]={getRoom=function() return own end,getObjects=function() return list({sign}) end}
reads=0 check(Brands.identify(object)=="Fossoil" and reads<=81,"bounded same-room sign recognition failed")
squares["1001:1000:0"].getRoom=function() return room("shop next door") end
check(Brands.identify(object)=="_office","sign across tenant wall assigned wrong firm")
PrintMediaDefinitions={MiscDetails={fossoil1={location1="broken-mod-data"}}}
check(Brands.identify(object)=="_office","malformed optional location metadata crashed identification")
for key,id in pairs({twiggys="Twiggys",wpdiy="WestPointDIY",thewizardskeep="WizardsKeep",
    muldraughpd="MuldraughPolice",rosewoodfd="RosewoodFire"}) do
    PrintMediaDefinitions={MiscDetails={[key]={location1={{x1=10,y1=20,x2=15,y2=25}}}}}
    object=computer("office",12,22,0)
    check(Brands.identify(object)==id,"new verified single-business rectangle missed "..id)
    object=computer("office",9,22,0)
    check(Brands.identify(object)=="_office","new logo leaked outside its verified premises "..id)
    object=computer("bedroom",12,22,1)
    check(Brands.identify(object)=="_home","private upstairs room inherited new business logo "..id)
    local known=System.create(31,Brands.kind(id),false,false,"new-firm-"..id,id)
    check(Files.get(known.archive).brand==id,"new firm did not receive its matching owner story "..id)
end
local publicBrandCases={riversidepd={"MeadeCountyPolice","police","sand"},
    wptownhall={"WestPointTownHall","government","aqua"},
    hobbsandperkinshardware={"HobbsPerkinsHardware","hardware","green"},
    ovofarms={"OvoFarms","agriculture","sand"},lennyscarrepair={"LennysCarRepair","mechanic","aqua"},
    ekroncollege={"EkronCommunityCollege","education","aqua"},
    alsautoshop={"AlsAutoShop","mechanic","aqua"},stuartandlogscrapyard={"StuartAndLog","mechanic","aqua"},
    darkwallowguesthouse={"DarkwallowGuestHouse","hotel","aqua"},a1hay={"A1Hay","agriculture","sand"},
    gunsunlimitedechocreek={"GunsUnlimited","retail","green"},goldensunset={"GoldenSunset","clinic","sand"},
    brookslibrary={"BrooksLibrary","education","sand"},lvpdhq={"LouisvillePolice","police","aqua"},
    upscalemobility={"UpscaleMobility","mechanic","sand"},eptoolslv={"EPTools","hardware","aqua"},
    brottauction={"BrottCattleFarm","agriculture","green"},beefchunk={"BeefChunk","industry","sand"},
    artgalleryoflouisville={"ArtGalleryLouisville","research","sand"},gnomesweetgnome={"HomeSweetGnome","industry","aqua"},
    irvingtonspeedway={"IrvingtonSpeedway","entertainment","sand"},sunsetpinesfuneralhome={"SunsetPines","community","sand"},
    roxysrollerrink={"RoxysRollerRink","entertainment","aqua"}}
local rareSeed
for seed=1,1000 do
    if SC.TerminalPresentation.themeFor(seed)=="purple" then rareSeed=seed break end
end
check(rareSeed~=nil,"rare-purple fixture available")
for key,row in pairs(publicBrandCases) do
    local id,kind,theme=row[1],row[2],row[3]
    PrintMediaDefinitions={MiscDetails={[key]={location1={{x1=10,y1=20,x2=15,y2=25}}}}}
    object=computer("office",12,22,0)
    check(Brands.identify(object)==id and Brands.kind(id)==kind,"public/local business identity and context: "..id)
    object=computer("office",9,22,0)
    check(Brands.identify(object)=="_office","public logo borrowed by neighbouring premises: "..id)
    object=computer("bedroom",12,22,1)
    check(Brands.identify(object)==(kind=="hotel" and id or "_home"),"public logo leaked into private home: "..id)
    local profile=Files.choose(kind,17,id)
    check(profile.kind==kind and profile.brand==id,"logo received files from another firm or sector: "..id)
    check(Brands.crop(id,"aqua")~=nil and SC.TerminalPresentation.themeFor(1,id)==theme,
        "public/local header crop and matching colour: "..id)
    check(not Brands.BACKINGS[id],"transparent header lettering was misclassified as a backing: "..id)
    check(SC.TerminalPresentation.themeFor(rareSeed,id)=="purple","brand disabled rare-purple computers: "..id)
end
PrintMediaDefinitions={MiscDetails={circuitalhealing={location1={{x1=10,y1=20,x2=15,y2=25}}}}}
object=computer("medical",12,22,0)
check(Brands.identify(object)=="_medical","mixed Circuital Healing advert claimed the neighbouring medical tenant")
for id,group in pairs({CircuitalHealing="Circuital Healing",ArtGalleryLouisville="Art Gallery of Louisville",
    HomeSweetGnome="Home Sweet Gnome",IrvingtonSpeedway="Irvington Speedway",
    SunsetPines="Sunset Pines Funeral Home",RoxysRollerRink="Roxy's Roller Rink"}) do
    local current,homeRoom
    object,current,homeRoom=computer("office",1000,1000,0)
    local firmSign={getProperties=function() return {get=function(_,key) return key=="CustomName" and "Sign" or group end} end}
    squares["1001:1000:0"]={getRoom=function() return homeRoom end,getObjects=function() return list({firmSign}) end}
    check(Brands.identify(object)==id,"new original logo not recognised from its own room sign: "..id)
    squares["1001:1000:0"].getRoom=function() return room("neighbour") end
    check(Brands.identify(object)=="_office","new sign branding crossed a tenant wall: "..id)
    local kind=Brands.kind(id)
    check(Files.choose(kind,31,id).brand==id,"new business has no matching staff archive: "..id)
end
local gateProfile=Files.choose("security",31,"IrvingtonSpeedway")
check(gateProfile.brand=="IrvingtonSpeedway" and gateProfile.kind=="security",
    "speedway security computers inherited unrelated prison or military stories")
SC.GameplayUtil,PrintMediaDefinitions=savedU,savedDefinitions
for _,id in ipairs({"UStoreIt","PizzaWhirled","SunstarMotel","JackieJaye","Twiggys","WestPointDIY",
    "WizardsKeep","MuldraughPolice","RosewoodFire","TacoDelPancho"}) do
    check(Brands.BY_ID[id]~=nil and Brands.crop(id,"aqua")~=nil,"new company logo has no source crop")
end
check(SC.TerminalPresentation.themeFor(1,"UStoreIt")=="aqua","curated U-Store It palette ignored")
for id,theme in pairs({Twiggys="sand",WestPointDIY="aqua",WizardsKeep="sand",RosewoodFire="aqua",TacoDelPancho="sand"}) do
    check(SC.TerminalPresentation.themeFor(1,id)==theme,"new firm has incompatible phosphor pairing "..id)
end
check(Brands.BACKINGS.MassGenfacCo~=nil and Brands.DARK_INK.TheKentuckyHerald,
    "dark ink and flat-backed native marks lack rendering metadata")
print("TERMINAL_LORE_PASS checks="..checks.." owners="..#Files.all().." entries="..entryCount.." references="..#Lore.REFERENCE)
SC_TEST_REPORT=SC_TEST_REPORT.."; Expanded terminal lore and branding: "..checks.." checks passed"
