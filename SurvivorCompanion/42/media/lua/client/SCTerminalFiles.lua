-- SPDX-License-Identifier: MIT
-- Original local files. IDs are save identities; do not rename published IDs.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalFiles = {}
local Files = SC.TerminalFiles
if type(require) == "function" then require "SCTerminalLore" end

local profiles = {
    { id = "dispatch_morrow", kind = "police", owner = "Helen Morrow", entries = {
        { date = "1993-07-02", title = "Shift handover",
          text = "The night desk has one working headset. Day shift has two. I have marked ours PROPERTY OF NIGHT SHIFT, which should settle it until someone learns to read." },
        { date = "1993-07-06", title = "Call categories",
          text = "Three callers described the same man on different roads. Units say the descriptions cannot all be right. There is no box for that on the incident form." },
        { date = "1993-07-08", title = "Keep a line open",
          text = "We have been told to refer illness calls to the county. The county number rings out. I am leaving one line open for the ambulance crews. They keep asking who is in charge." },
        { date = "1993-07-09", title = "Unsent handover",
          text = "Tom called from the roadblock and asked me to ring his house. I did. Nobody answered. I told him I would try again in a minute. I have been trying for forty." },
    } },
    { id = "dispatch_bell", kind = "police", owner = "Leonard Bell", entries = {
        { date = "1993-07-03", title = "Telephone test",
          text = "The new emergency routing system sent our test call to a bowling alley. A man there took the details carefully. We may have found our most dependable contractor." },
        { date = "1993-07-07", title = "Vehicle list",
          text = "Please record car descriptions before giving directions to the checkpoint. Families are following each other and getting separated. A blue station wagon is not a useful description today." },
        { date = "1993-07-08", title = "Radio traffic",
          text = "Someone keeps calling for unit twelve. Twelve signed off yesterday. I checked the roster twice, then went outside to look for his car." },
        { date = "1993-07-09", title = "If another shift arrives",
          text = "The batteries are in the bottom drawer. The paper map has the last confirmed open roads. Do not trust the green pins. I ran out of red ones." },
    } },
    { id = "clinic_shah", kind = "clinic", owner = "Dr. Anita Shah", entries = {
        { date = "1993-07-01", title = "Stock request",
          text = "Ordered gloves, saline and a replacement thermometer. Accounts approved the thermometer. Apparently we can afford to know precisely how badly supplied we are." },
        { date = "1993-07-06", title = "Telephone consultations",
          text = "The fever cases sound similar, but several callers insist nobody else in the household is ill. Asked reception to keep separate notes rather than file them under summer flu." },
        { date = "1993-07-08", title = "Waiting room",
          text = "We moved the chairs apart and opened the side room. The hospital is not accepting transfers. One mother asked whether she should take her daughter home. I could not give her an answer I trusted." },
        { date = "1993-07-09", title = "For whoever opens tomorrow",
          text = "Clean dressings are in the cupboard marked forms. The forms are on the floor. I am going to find our driver. Please do not open the rear examination room without someone with you." },
    } },
    { id = "clinic_price", kind = "clinic", owner = "Ruth Price, reception", entries = {
        { date = "1993-07-02", title = "Appointment reminder",
          text = "Mr. Danner has booked the same checkup three times. He likes the reminder calls. I have put one appointment in the book and three calls on my list." },
        { date = "1993-07-07", title = "Extra hours",
          text = "The doctors are staying late. I put the coffee money toward bread and cheese for everyone. If the partners object, they can deduct two sandwiches from my wages." },
        { date = "1993-07-08", title = "Messages",
          text = "There are twenty-six messages asking when we open. There are four from staff saying they cannot come in. I stopped counting the ones where nobody speaks." },
        { date = "1993-07-09", title = "Closing notice",
          text = "I wrote CLOSED on the sign and then took it down. There are still people outside. My sister is waiting by the car with my coat. I need to choose which door to use." },
    } },
    { id = "home_bennett", kind = "home", owner = "Jamie Bennett", entries = {
        { date = "1993-07-03", title = "Private",
          text = "Dad says this machine is for schoolwork. School is closed, which makes every game I play an act of educational initiative." },
        { date = "1993-07-06", title = "Cancelled",
          text = "Mum cancelled the trip. She says it is nothing to worry about and has filled every bottle we own. Even the horrible souvenir one from Florida." },
        { date = "1993-07-08", title = "Across the road",
          text = "Mrs. Cole left her television on all night. I could see it flickering through the curtains. This morning her dog was at our gate without its lead." },
        { date = "1993-07-09", title = "Back soon",
          text = "We are taking the back roads to Aunt Liz. I left my number under the keyboard for Chris, then remembered he already knows it. I left it there anyway." },
    } },
    { id = "home_ruiz", kind = "home", owner = "Elena Ruiz", entries = {
        { date = "1993-07-01", title = "Summer list",
          text = "Learn to drive. Get a job. Stop letting Daniel win at cards. He read this over my shoulder and says the last one is unrealistic." },
        { date = "1993-07-05", title = "The news",
          text = "Grandma turned the radio off halfway through the report. She said she had heard enough men explain that everything was under control to last a lifetime." },
        { date = "1993-07-08", title = "Packing",
          text = "We get one bag each. Daniel put all his toy cars in his. I told him to take clothes instead, then hid two of the cars in my shoes." },
        { date = "1993-07-09", title = "Kitchen table",
          text = "Grandma will not leave until the washing is dry. Mum has stopped arguing and is helping her fold it. Everyone is speaking very gently. That is worse than the shouting." },
    } },
    { id = "office_walter", kind = "office", owner = "Walter Price", entries = {
        { date = "1993-07-02", title = "Claims bulletin",
          text = "Head office requests that we use reassuring language when discussing the new exclusions. I suggest we reassure customers that the exclusions are extremely thorough." },
        { date = "1993-07-06", title = "Memo: unusual incidents",
          text = "Do not reject a claim merely because the description sounds implausible. Forward it to me. We now have enough implausible descriptions to fill a very ordinary filing cabinet." },
        { date = "1993-07-08", title = "Memo: office attendance",
          text = "Management says attendance remains mandatory. Management has not attended. I have forwarded the notice to their home addresses for clarification." },
        { date = "1993-07-09", title = "Memo: final",
          text = "I am leaving the front door unlocked. If someone needs shelter, our liability position can survive a little uncertainty. The first-aid box is above the copier." },
    } },
    { id = "office_june", kind = "office", owner = "June Mercer", entries = {
        { date = "1993-07-01", title = "Quarterly figures",
          text = "The discrepancy was a postage expense entered as a tractor. Corrected the figures. Left the original printout on my wall as a reminder that numbers can have adventures." },
        { date = "1993-07-07", title = "Forwarding calls",
          text = "Customers are asking whether the roads are open. We sell office supplies. I have started writing down what the delivery drivers tell us because at least they have been outside." },
        { date = "1993-07-08", title = "Petty cash",
          text = "Used the remaining cash for drinking water. Receipts are in the tin. If there is an audit, somebody should be able to explain why there are no paper clips." },
        { date = "1993-07-09", title = "Lunchroom",
          text = "We waited until noon for Dennis. His coat is still on the chair. I put the water in his car and left a note saying where we were going. I wish I knew if he would read it." },
    } },
    { id = "general_grant", kind = "general", owner = "Arthur Grant", entries = {
        { date = "1993-07-02", title = "Maintenance request",
          text = "The door sticks when it rains. It has done this for eleven years. Please stop describing it as a new issue; it will start expecting a birthday card." },
        { date = "1993-07-06", title = "Spare keys",
          text = "Made a second set for the evening staff. The locksmith asked if I wanted a third. I said two shifts were quite enough for anyone." },
        { date = "1993-07-08", title = "Delivery",
          text = "The van arrived without our order. The driver had his children with him and wanted directions north. I gave him the paper map from the wall." },
        { date = "1993-07-09", title = "Last inspection",
          text = "Water off at the stopcock. Windows latched. Back door left on the catch for anybody coming behind us. I have spent years making sure this place was closed properly. Today I hope I got it wrong." },
    } },
    { id = "general_faye", kind = "general", owner = "Faye Norton", entries = {
        { date = "1993-07-01", title = "New computer",
          text = "The salesman promised a paperless office. The instruction book is two hundred pages. I have made a shelf for the future." },
        { date = "1993-07-05", title = "Emergency contact",
          text = "Updated the contact list. Half the numbers belong to people who have moved away. I envy their excellent timing." },
        { date = "1993-07-08", title = "Neighbours",
          text = "We are sharing what we know by writing it on the noticeboard. Nobody trusts the telephone reports now. The board has never had so many readers." },
        { date = "1993-07-09", title = "Note for my replacement",
          text = "The keys are behind the calendar. I know that is a terrible place for keys. Everyone here knows where they are, and that seems more useful than hiding them today." },
    } },
}
for _, profile in ipairs(SC.TerminalLore and SC.TerminalLore.ARCHIVES or {}) do profiles[#profiles+1] = profile end
local byId, byKind, byBrand = {}, {}, {}
for _, profile in ipairs(profiles) do
    byId[profile.id] = profile
    byKind[profile.kind] = byKind[profile.kind] or {}
    table.insert(byKind[profile.kind], profile)
    if profile.brand then
        byBrand[profile.brand] = byBrand[profile.brand] or {}
        table.insert(byBrand[profile.brand], profile)
    end
end

function Files.get(id) return byId[id] end
function Files.choose(kind, seed, brand)
    local related=SC.TerminalBusinessData and SC.TerminalBusinessData.ARCHIVE_BRANDS
    local branded = byBrand[brand] or byBrand[related and related[brand]]
    if branded then
        local matching = {}
        for _, profile in ipairs(branded) do
            if profile.kind == kind then matching[#matching+1] = profile end
        end
        if #matching > 0 then return matching[(seed % #matching)+1] end
    end
    local pool = byKind[kind] or byKind.general
    return pool[(seed % #pool) + 1]
end
function Files.all() return profiles end

function Files.classify(name)
    name = string.lower(string.sub(tostring(name or ""), 1, 96))
    if name:find("police", 1, true) or name == "detectiveoffice" then return "police" end
    if name:find("firestation",1,true) or name=="fireoffice" or name=="firestorage" or name=="firegarage" then return "emergency" end
    if name:find("prison",1,true) or name == "baggagesearch" or name == "security" then return "security" end
    if name:find("army",1,true) or name:find("military",1,true) then return "military" end
    if name:find("pharmacy",1,true) then return "pharmacy" end
    if name == "optometrist" or name == "medclinic" then return "clinic" end
    if name:find("hospital", 1, true) or name:find("medical", 1, true)
        or name:find("clinic", 1, true) or name:find("doctor", 1, true)
        or name:find("dentist", 1, true) then return "clinic" end
    if name:find("school",1,true) or name:find("classroom",1,true) or name:find("library",1,true)
        or name:find("university",1,true) or name == "elementaryhall" then return "education" end
    if name == "lab" or name == "laboratory" then return "research" end
    if name:find("jackiejaye",1,true) or name == "office_herald" or name == "newspaperprint_herald"
        or name == "broadcasting" or name == "communications" or name == "newsroom" or name == "studio" then return "media" end
    if name == "bank" then return "bank" end
    if name:find("hotel",1,true) or name:find("motel",1,true) then return "hotel" end
    if name == "post" or name:find("transport",1,true) or name:find("airport",1,true) then return "transport" end
    if name == "serverroom" or name == "cybercafe" or name:find("electronic",1,true) then return "electronics" end
    if name:find("mechanic",1,true) or name == "carsupply" or name == "cardealershipoffice" then return "mechanic" end
    if name == "hardwarestore" or name == "toolstore" then return "hardware" end
    if name == "gigamart" or name == "grocery" or name == "grocerystore" then return "grocery" end
    if name == "gasstore" or name == "gasstorage" then return "fuel" end
    if name:find("spiffos",1,true) or name:find("restaurant",1,true) or name == "dinerkitchen" then return "restaurant" end
    if name:find("coffee",1,true) or name == "cafe" then return "cafe" end
    if name == "officechurch" or name:find("church",1,true) or name == "communitycentre" then return "community" end
    if name == "townhall" or name:find("government",1,true) or name == "archive" then return "government" end
    if name:find("factory",1,true) or name == "warehouse" or name == "metalshop" or name == "controlroom" then return "industry" end
    if name == "farmstorage" or name == "farming" then return "agriculture" end
    if name == "movierental" or name == "arcade" or name == "recreational" or name == "gym" then return "entertainment" end
    if name:find("store",1,true) or name:find("shop",1,true) then return "retail" end
    if name:find("office", 1, true) or name:find("insurance", 1, true)
        or name:find("bank", 1, true) then return "office" end
    if name:find("bedroom",1,true) or name == "livingroom" or name == "kitchen" or name == "attic" then return "home" end
    return "general"
end
