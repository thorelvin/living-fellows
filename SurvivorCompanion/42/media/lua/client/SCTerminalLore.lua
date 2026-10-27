-- SPDX-License-Identifier: MIT
-- Original fiction, stored locally. These are archived accounts, not live
-- observations or authoritative explanations of the Knox infection.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalLore = {}
local Lore = SC.TerminalLore
local function owner(id, kind, name, brand, rows)
    local profile = {id=id,kind=kind,owner=name,brand=brand,entries={}}
    for _, row in ipairs(rows) do
        profile.entries[#profile.entries+1] = {date=string.format("1993-07-%02d",row[1]),title=row[2],text=row[3]}
    end
    return profile
end
Lore.ARCHIVES = {
    owner("school_elise", "education", "Elise Turner", nil, {
        {2,"Summer inventory","Thirty-one rulers, twenty-nine chairs, one globe missing Kentucky. The children have been moving the little paper labels again. Geography improves when they care enough to vandalise it."},
        {5,"Telephone tree","Copied the parents' numbers onto paper. The office computer can alphabetise names, but cannot make anybody answer. Neither can the principal, although he has tried considerably harder."},
        {7,"Collection arrangements","A father arrived for his daughter three weeks before summer classes begin. I sat with him until his sister came. I did not correct him again."},
        {9,"For whoever opens up","Clean water in the art cupboard. Blankets from the nursery in Room Two. The register is on the desk. Please write down the children who come in, even if nobody is taking attendance."},
    }),
    owner("library_owen", "education", "Owen Bell", nil, {
        {1,"Overdues","Waived another fine for Mrs Hales. She returned the book with a pressed flower inside. Accounts may record a loss of forty cents. They do not have a column for the flower."},
        {5,"Reference requests","Readers want road atlases, first-aid manuals and books about wells. The gardening shelf is suddenly our most strategic asset. Nobody has asked for the new management titles."},
        {8,"Quiet please","The radio will stay on behind the desk. I have spent twenty-two years asking people to be quiet in here. Today I would like somebody to tell us something useful."},
        {9,"Returns slot","Removed the spring from the returns flap so it cannot trap fingers. If this building is used as a shelter, the children's corner has the softest carpet. Leave the picture books there."},
    }),
    owner("university_nadia", "education", "Nadia Mercer", "LouisvilleStateUniversity", {
        {2,"Laboratory access","The summer assistants need two keys between six people. Security suggested a sign-out sheet. I suggested four more keys. We have reached the sign-out-sheet stage of the discussion."},
        {6,"Missing students","Three students have gone home early. No penalties. I have put that in writing so nobody can discover a reason to penalise them later."},
        {8,"Office hours","Office hours cancelled. I am sitting here anyway because a student said she would come after finding her brother. If she asks, she has not missed the appointment."},
        {9,"Research notes","Backups in the lower drawer, clearly labelled. The dissertation can wait. It has already waited four years and has developed a certain confidence in its ability to survive disappointment."},
    }),
    owner("lab_mira", "research", "Mira Sethi", "FinneganResearchGroup", {
        {1,"Control sample","The control refrigerator is making the same noise as the break-room refrigerator. This is not evidence of a connection between the experiments and Gary's lunch."},
        {5,"Courier instructions","No sample is to leave without a signed chain of custody. If the courier is late, refrigerate it. A telephone promise is not a temperature-control system."},
        {7,"Unconfirmed reports","Staff have brought newspaper clippings to the bench. There are no measurements in them. I have written UNKNOWN across the briefing sheet; it is the only result I can defend."},
        {9,"Shutdown","Cultures secured. Gas closed. Incident binder left by the exit. I cannot tell the next person what has happened outside. I can at least tell them which cupboard contains acid."},
    }),
    owner("lab_peter", "research", "Peter Voss", nil, {
        {2,"Requisition","Requested another box of gloves. Purchasing wants a justification. I have attached a photograph of my hands, which I would like to continue owning."},
        {6,"Calibration","The alarm sensor was drifting before the broadcasts began. It is still drifting. Please do not turn an old maintenance problem into a new theory."},
        {8,"Night shift","Only three of us came in. We checked the fridges and sat in the office with the lights on. Nobody wanted to walk past the dark observation window alone."},
        {9,"Exit checklist","Nothing in this room is a cure. The cupboard labels describe cleaning agents. I am writing this because people become hopeful when they see a white coat, and I have no right to encourage that."},
    }),
    owner("clinic_rosa", "clinic", "Rosa Bennett", "MedicalCentre", {
        {2,"Appointment book","Mr Avery has booked his annual checkup for the fifth time. He likes to telephone to confirm we are still here. Normally this is irritating. This week it seems reasonable."},
        {6,"Dressings","Counted supplies by hand after the computer gave us a negative quantity of gauze. I have never seen negative gauze, but accounts appear to use it regularly."},
        {8,"Waiting room","We are seeing whoever arrives. Keep the appointment book anyway; it has the emergency contacts. Please stop telling the people outside that we know more than they do."},
        {9,"Last shift","Left clean dressings on the trolley and boiled water under a lid. The locked cabinet is still locked. The spare key is with the duty nurse, if you can find her."},
    }),
    owner("dentist_marion", "clinic", "Marion Pike", "FamilyDentistry", {
        {1,"New reminders","Our appointment cards now show a smiling molar. Mrs Pike says it looks delighted to be extracted. I have ordered two thousand, so it must learn to enjoy the situation."},
        {5,"Stock room","Sterilisation logs filed. The spare masks are on the upper shelf, not in reception. Reception has sweets, which is a different kind of dental business model."},
        {8,"Emergency calls","People are asking about bites. I can clean a wound and recommend proper medical care. I cannot identify an illness from something a caller heard on the radio."},
        {9,"Closing note","Autoclave emptied, sharps secured. If anyone needs clean towels, take them. Send the bill to me personally and we will discuss it when such discussions seem important again."},
    }),
    owner("optician_celia", "clinic", "Celia Frost", "OptimaEyes", {
        {2,"Frame display","The expensive frames have plain glass in them. Please remember this before promising a customer that the display pair will improve their vision immediately."},
        {6,"Collection calls","Called everybody with finished lenses. Two asked us to post them. One asked whether reading glasses would help with a road map. I said yes, if somebody else was driving."},
        {8,"Repairs","We are straightening frames without charge. A woman cried because she could read the labels on her son's medicine again. I have stopped worrying about the till."},
        {9,"On the counter","Small screws and the repair kit are in the blue tray. Do not wipe the lenses with paper towels. Apparently I intend to keep giving this advice until the very end."},
    }),
    owner("pharmacy_denise", "pharmacy", "Denise Ward", nil, {
        {1,"Stock rotation","The short-dated stock goes at the front. This principle has survived six staff meetings and continues to astonish people every Monday."},
        {5,"Refill messages","Keep a written list of refill calls. If the telephone lines fail, the answering machine is not a filing cabinet. The doctor has not returned our messages either."},
        {8,"Counter notice","No, the items behind the counter are not being withheld for friends. We have less than the shelf labels suggest. I have taken the labels down."},
        {9,"Dispensing records","Patient cards are in alphabetical order. Do not guess at a dose from the size of a tablet. If you cannot identify it, leave it alone. An empty hand is better than a confident mistake."},
    }),
    owner("hotel_rita", "hotel", "Rita Dunn", "HavishamHotelSuites", {
        {2,"Guest relations","Room 214 requested a quieter ice machine. Maintenance says the ice machine has no feelings about the matter. I have requested a more helpful maintenance report."},
        {6,"Early arrivals","Accepting early arrivals where rooms are ready. Several guests have arrived with all their luggage and no reservation. There is something wrong with the usual polite questions."},
        {8,"Night desk","No wake-up calls tomorrow unless requested again. People are finally asleep. Put the radio where guests can hear it, but turn off the advertisement loop."},
        {9,"Master keys","The housekeepers know which rooms are occupied. Trust their notes over this machine. We gave away rooms without entering them because people needed doors that locked."},
    }),
    owner("motel_vic", "hotel", "Victor Hale", "SleepEazzzeInn", {
        {1,"Pool notice","The pool sign says NO RUNNING. Somebody has added NO DIVING, NO SHOUTING and NO RELAXING. I admire a guest who understands our service standards."},
        {5,"Road traffic","More families than salesmen tonight. They ask about the roads before asking about the rooms. I have put an atlas by the bell."},
        {8,"Extension requests","Let guests extend without payment until the roads open. The owner can telephone me if he disagrees. That would also prove the telephone still works."},
        {9,"Laundry room","Fresh sheets are in the locked cupboard. I left the key in the lock. This is now a convenience rather than a security failure."},
    }),
    owner("sunstar_dale", "hotel", "Dale Mercer", "SunstarMotel", {
        {2,"Neon repair","The sign loses its second S in the rain. Guests have started calling us the Sun Tar. We will repair it before this becomes a recognised category of accommodation."},
        {6,"Room ledger","Put the vehicle descriptions beside the guest names. People are asking after relatives and sometimes all they remember is the colour of the car."},
        {8,"Vacancies","Every room is occupied. The VACANCY light will stay off even if it takes shutting the sign down. We are not bringing more people off the road on a promise we cannot keep."},
        {9,"Reception","Water jugs beside the desk. We moved the chairs so the children could sleep behind the counter. Knock before coming through; they have had enough strangers for one night."},
    }),
    owner("bank_alan", "bank", "Alan Price", "KnoxBank", {
        {2,"Cash order","Requested more small notes for the holiday weekend. Head office suggested more efficient cash usage. I asked whether customers should share their twenty-dollar bills."},
        {6,"Queue management","Open the second window before the queue reaches the door. People who are worried do not become less worried while looking at an empty service window."},
        {8,"Balances","Print statements on request. Do not promise a transfer will clear today. A number on this screen is a record of an obligation, not proof that a telephone line is working."},
        {9,"Branch closed","The vault is secured. Staff left together. I put the customer complaint book in the safe because it contains addresses, not because I believe anyone will want to complain about opening hours now."},
    }),
    owner("bank_mel", "bank", "Melanie Cross", "SkyBlueBanking", {
        {1,"Training exercise","The training account contains a million dollars and cannot buy lunch. This distinction has become the most memorable part of the training course."},
        {5,"Branch supplies","Printer ribbons ordered. The regional office has approved the request but not the postage. Perhaps they intend to transmit the ribbons by telephone."},
        {8,"Customer records","Stop leaving printouts on the public counter. People are frightened enough without discovering that a stranger knows where their elderly parents live."},
        {9,"End of day","Balanced the drawer. It seemed important to finish one thing properly. There are biscuits in the staff kitchen and clean cups beside the sink."},
    }),
    owner("insurance_ian", "office", "Ian Webb", "MindPeaceInsurance", {
        {2,"Policy wording","We sell peace of mind. The filing cabinet has fallen over twice this month. I would settle for a wall bracket."},
        {6,"Unusual claims","Please record the customer's words exactly. Replacing an unfamiliar event with a familiar category makes a neat report and a very poor record."},
        {8,"Coverage queries","No member of staff is authorised to tell callers that the current situation is covered. No member of staff is authorised to tell them it is not. We are, however, allowed to listen."},
        {9,"Office key","Left the spare with the caretaker. The policy files are private. The kettle, chairs and first-aid tin are not. Make the distinction if anybody needs shelter."},
    }),
    owner("insurance_june", "office", "June Archer", "ValuInsurance", {
        {1,"New slogan","The approved slogan says VALUE WHEN IT MATTERS. The office photocopier refuses to print it without a line through MATTERS. Maintenance calls this a toner issue."},
        {5,"Emergency contacts","Updated staff contacts and printed two copies. One is in the red folder. One is in my handbag. If accounts asks, the extra paper was a professional judgement."},
        {8,"Field visits","No inspections until further notice. A damaged roof will wait longer than a frightened employee standing beneath it."},
        {9,"Forwarding address","I cannot give one yet. Leave messages under the door if you must. I am aware this is not an adequate continuity arrangement. Neither is the one in the binder."},
    }),
    owner("legal_simon", "office", "Simon Reed", "SpeedyLegal", {
        {2,"Client intake","The sign promises a rapid consultation, not a rapid miracle. Please do not quote the sign as though it were a legal remedy."},
        {6,"Duplicate documents","Make certified copies before returning originals. Several clients are collecting papers they have never looked at before. I am glad they remembered where we were."},
        {8,"Wills","No appointment required for urgent instructions. Keep the witness list. We have moved beyond the point at which a tidy appointment calendar is a useful ambition."},
        {9,"Private files","The locked drawers contain other people's lives. Food is in the small cupboard by the sink. You do not need to force any locks to find it."},
    }),
    owner("property_diane", "office", "Diane Holt", "HomewardRealEstate", {
        {1,"Listing photographs","Please stop photographing rooms from inside wardrobes. We sell spacious living, but the purchaser is entitled to know where the walls actually are."},
        {5,"Viewing cancellations","Cancelled the afternoon viewings. Two owners asked whether their empty houses could be used by relatives. They are their houses. This should not require a meeting."},
        {8,"Keys","Tag every key we lend. People are opening homes for families they have never met. The least we can do is remember which door belongs to which family."},
        {9,"Window cards","Took the prices out of the window. Left the photographs. A young man recognised his grandmother's porch and said it was the first familiar thing he had seen all day."},
    }),
    owner("tax_ella", "office", "Ella Park", "Slimtax", {
        {2,"Receipts","A client delivered six years of receipts in a fishing-tackle box. The hooks were better organised. Charged for the sorting, not the lesson in humility."},
        {6,"Extension forms","Keep the unsigned forms separate. A deadline has not become optional because the office is busy, although I would welcome an official statement to that effect."},
        {8,"Cancelled meetings","I told the clients to take their original documents home. If somebody asks why, say that a copy in our office should never be the only record a family has."},
        {9,"Closing balance","I have spent seventeen years finding small discrepancies. Today the discrepancy is the distance between what the radio says and what I can see through the window."},
    }),
    owner("news_len", "media", "Leonard Shaw", "TheKentuckyHerald", {
        {2,"Corrections desk","The photograph shows the deputy mayor, not a missing spaniel. Both corrections are required. Please resist the temptation to combine them into one apology."},
        {6,"Source list","A second caller repeating the first caller is not a second source. Ask what they saw, where they stood and what time it was. Write down what they did not see as well."},
        {8,"Morning edition","We are printing useful addresses in larger type. Readers need water points and open clinics more urgently than they need my opinion about the council."},
        {9,"Unfinished page","Leave a blank space where the confirmation should go. If we print a rumour because the space looks awkward, the paper will be neat and the people reading it may be dead."},
    }),
    owner("radio_frank", "media", "Frank Ellis", "KnoxTalkRadio", {
        {1,"Caller delay","Tested the delay switch. It removes seven seconds of speech and absolutely none of the presenter's confidence. We have filed this as a partial success."},
        {6,"Programme changes","Keep the weather, road reports and public notices. Nobody needs a heated discussion about garden fencing between evacuation messages."},
        {8,"Telephone board","Callers are looking for relatives. Read names slowly and ask permission before broadcasting an address. A familiar voice is useful; a public address can be dangerous."},
        {9,"Studio note","The approved message is on the stand. The handwritten list beside it is what callers say they have actually found open. Read both, and make clear which is which."},
    }),
    owner("radio_maggie", "media", "Maggie Quinn", "LBMWNetwork", {
        {2,"Station clock","The studio clock is ninety seconds fast. We have been giving the county a small head start. Engineering says this is not an acceptable scheduling policy."},
        {5,"Emergency reel","Made a spare recording of the emergency instructions. It is labelled in red. Do not erase it to save a commercial, however urgent the mattress sale becomes."},
        {8,"Levels","The announcer is losing his voice. Move the microphone closer. Turning everything louder will not make him less tired."},
        {9,"For the relief crew","Tea in the flask, batteries in the upper drawer, transmitter checklist by the door. If there is no relief crew, I hope the person who finds this likes tea."},
    }),
    owner("tv_robin", "media", "Robin Vale", "ENewsNowNetwork", {
        {1,"Picture captions","Check the location caption before rolling tape. A dramatic picture from somewhere else is still a picture from somewhere else."},
        {6,"Camera batteries","Put charged batteries on the left shelf, spent ones on the right. We have enough uncertainty without inventing an electrical guessing game."},
        {8,"Live position","The crew will not stand in the road for a better background. An unobstructed view of the reporter is preferable to an unobstructed view of an empty camera."},
        {9,"Cut tape","I left the uncut interviews in the cabinet. The broadcast versions are shorter and easier to watch. The uncut ones contain the pauses, which may explain more."},
    }),
    owner("tv_jackie_ron", "media", "Ron Cooper", "JackieJaye", {
        {2,"Audience tickets","Six tickets were issued to one surname. Reception says they are cousins. This is Kentucky; the evidence does not narrow it down."},
        {6,"Standby programme","We have a standby tape for every technical failure except a guest who refuses to stop talking. The production meeting has requested one."},
        {8,"Holding room","Gave the waiting room to two stranded families. Nobody complained about missing the show. I am trying not to take that personally."},
        {9,"Studio floor","Work lights on, scenery secured, exits clear. The applause sign is unplugged. I did not want it coming on by itself in an empty room."},
    }),
    owner("telecom_hugh", "utilities", "Hugh Nolan", "AmeriglobeCommunications", {
        {1,"Fault ticket","A caller says the line is dead until she shouts at it. Technician found a loose handset cord. The customer has accepted credit for the repair."},
        {5,"Spare parts","Keep the older exchange boards. New stock has been delayed. It is remarkable how quickly obsolete becomes available."},
        {8,"Congestion","Busy lines do not tell us what happened to the person at the other end. Please keep that sentence in front of the help desk."},
        {9,"Duty roster","The last two engineers went out together. No solo callouts. The exchange will have to wait if the alternative is losing the people who know how to repair it."},
    }),
    owner("electronics_ken", "electronics", "Ken Arroyo", "Valutech", {
        {2,"Demonstration model","Customers keep asking whether the display computer is faster than the old one. It is connected to a better monitor. Sales considers this an adequate demonstration."},
        {6,"Returned equipment","Label each return before stacking it. A fault described as DOES NOT WORK is less useful when it applies to six identical boxes."},
        {8,"Radio queue","People want portable radios and spare batteries. We have moved them to the front. The extended-warranty speech has been suspended by general agreement."},
        {9,"Service bench","Working receivers on the left, faulty sets on the right. A paper list is taped to each. If you take one, please take the paper too; the fault notes may matter."},
    }),
    owner("electronics_joy", "electronics", "Joy Grant", "ElectronHouse", {
        {1,"Staff discount","The staff discount does not apply to the demonstration satellite dish, the manager's telephone or anything that still belongs to a customer."},
        {5,"Rechargeables","Explain the charger before selling the batteries. Buying a thing that requires another thing is not a discovery anybody enjoys making in a blackout."},
        {8,"Back room","We are repairing radios while people wait. The little television has sound but no picture. Nobody watching the news seemed to consider that the largest problem."},
        {9,"Door notice","Take the batteries from the marked box first. The leaking ones are in a sealed bucket. This distinction is more important than the price stickers."},
    }),
    owner("logging_cal", "industry", "Calvin Brooks", "McCoyLogging", {
        {2,"Truck weights","The weighbridge has opinions about rainwater. Record the weather beside the load if the numbers change while the truck is standing still."},
        {5,"Saw maintenance","A sharp blade is not a substitute for a guard. I have written this on the board because some of you apparently consider fingers a renewable resource."},
        {8,"Dispatch cancelled","No trucks out until we know which roads are open. Drivers have families along those roads. They are not an alternative navigation service."},
        {9,"Yard shutdown","Fuel secured, saws isolated, first-aid box by the small office. Logs do not become less heavy because everybody is in a hurry. Lift with somebody else."},
    }),
    owner("factory_ed", "industry", "Edwin Moss", "MassGenfacCo", {
        {1,"Production target","The board wants a twenty-percent improvement. I asked whether that includes the board. The minutes describe my question as a request for clarification."},
        {6,"Night maintenance","The press will be locked out for repairs. A handwritten instruction to keep production moving does not remove the lockout tag."},
        {8,"Transport","Cancelled the late shift. We are using the staff bus to take people home in groups. Payroll can work out what to call the hours later."},
        {9,"Isolation checklist","Main breaker off, compressed air drained, rollers secured. There is no useful production waiting inside this building. There are several ways to get hurt."},
    }),
    owner("lectromax_ada", "industry", "Ada Merrill", "Lectromax", {
        {2,"Test results","The new batch passes its test. The test station fails its test. We have suspended congratulations until these facts can be placed in a useful order."},
        {5,"Component stock","Count the boxes, not the labels. Purchasing reused the cartons and we now appear to own four hundred pounds of transformers made entirely of packing paper."},
        {8,"Staff transport","Put the minibus keys on the hook. Whoever drives takes everyone waiting at the side door. Arguments about departments can resume at a safer location."},
        {9,"Danger notice","The press must be isolated and supported before anybody works under it. Power off does not mean it cannot fall. The warning tag describes a machine, not a suggestion."},
    }),
    owner("shipping_mo", "transport", "Monica Lane", "UnitedShippingLogistics", {
        {2,"Misrouted parcel","A carton marked FRAGILE has visited three depots and acquired no new precautions. I have rerouted it to the destination rather than a fourth educational opportunity."},
        {6,"Route sheets","Write the actual route on the return sheet. The map pins tell us where the customer is, not whether the bridge is open."},
        {8,"Priority freight","Medical supplies first, then food and water. The golf-club delivery can remain a tragic commercial casualty."},
        {9,"Loading bay","The last driver left a road sketch on the board. It is dated and signed. If you add a change, do the same. An old warning that looks current is another kind of hazard."},
    }),
    owner("transit_glen", "transport", "Glen Porter", "KYTransit", {
        {1,"Lost property","One umbrella, three lunch tins, a trumpet. The trumpet's owner telephoned twice. I consider that evidence against simply disposing of it."},
        {5,"Holiday timetable","Extra copies in the drivers' room. Stop changing the noticeboard without changing the timetable people take home."},
        {8,"Last stops","Drivers may stop where it is safe to collect stranded passengers. Safe is a judgement, not a promise. Nobody has to take a bus into a crowd they cannot get out of."},
        {9,"Depot keys","Parked vehicles nose out. Left the disabled coach where it cannot block the gate. I never expected an empty bus depot to look so much like a room waiting for an answer."},
    }),
    owner("fuel_hank", "fuel", "Hank Doyle", "Fossoil", {
        {2,"Pump three","The meter on three sticks in warm weather. Repairs booked. Until then use the other pumps and stop demonstrating the fault by striking it with a tyre iron."},
        {6,"Can sales","Limit spare cans fairly. A man buying all twelve is not twelve customers, even if he argues with the stamina of an entire queue."},
        {8,"Road questions","I cannot promise anybody a clear road. The drivers' notes are beside the maps, with times written on them. Yesterday's good news has caused enough trouble."},
        {9,"Pump isolation","Emergency shutoff is behind the counter. If you smell fuel, use it before investigating. There is nothing in the till worth a person being burned."},
    }),
    owner("hardware_lou", "hardware", "Louisa Ford", "NailsandNuts", {
        {1,"Stock discrepancy","We sell nails by weight. Counting them individually is not the new starter's task. Please apologise to the new starter before lunch."},
        {5,"Front display","Moved torches and water containers beside the door. The decorative garden ducks have agreed to surrender their position during the emergency."},
        {8,"Tool advice","Ask what the customer is trying to do before selling the biggest hammer. We are seeing an alarming amount of confidence from people who have never owned a smaller one."},
        {9,"Shutters","The hand crank is in the office. Keep fingers clear of the guides. Timber offcuts in the yard are free; I would rather they became someone's door than stay part of our inventory."},
    }),
    owner("hardware_wes", "hardware", "Wes Palmer", "ZacsHardware", {
        {2,"Key cutting","Do not promise a duplicate from a key broken into three pieces. We can be helpful without becoming responsible for reconstructive archaeology."},
        {6,"Deliveries","Supplier missed the morning delivery. We still have plenty of screws and fewer batteries than the display suggests. Count the batteries before promising them."},
        {8,"Noticeboard","Let customers leave messages on the board. Take down old prices to make room. Nobody looking for their sister needs another offer on lawn edging."},
        {9,"For the morning shift","There may not be a morning shift. If there is, the kettle is clean and the emergency lamp works. I tested it myself so I could leave one useful certainty."},
    }),
    owner("mechanic_art", "mechanic", "Arthur Clay", "CarFixation", {
        {1,"Customer description","Customer reports a noise when turning left. Technician reports a loose toolbox. Both are correct. Return the toolbox to the customer with an appropriate degree of solemnity."},
        {5,"Recovery calls","Keep one bay clear for breakdowns. A vehicle that cannot leave should not prevent three others from being repaired."},
        {8,"Fuel lines","Check for leaks before starting anything that has been sitting in the queue. A customer waiting anxiously does not reduce the ignition temperature of gasoline."},
        {9,"Workshop closed","Vehicles lowered, lifts isolated, batteries disconnected where marked. Keys are tagged by registration. If somebody comes for a car, check the tag before giving them somebody else's way home."},
    }),
    owner("tires_ben", "mechanic", "Ben Wallace", "AmericanTire", {
        {2,"Pressure gauge","The old gauge reads high. The new one is in the top drawer. Labelling the old gauge OLD did not communicate as much useful information as I had hoped."},
        {6,"Fleet booking","Cancelled the commercial fleet booking and kept the replacement stock. Families passing through need tyres more urgently than an invoice needs a signature."},
        {8,"Roadside kit","The portable compressor goes with the service truck. Bring it back charged. It cannot run on goodwill, though we currently have more of that than power."},
        {9,"Last orders","Left the sound used tyres beside the roller door. Damaged ones have cuts through the sidewall. Do not fit a dangerous tyre simply because it is the right size."},
    }),
    owner("cars_tom", "mechanic", "Thomas Avery", "nolanLogo", {
        {1,"Sales wording","A reliable runabout must be both reliable and capable of running about. Please check these points before putting the card in the windscreen."},
        {5,"Demonstrations","No unaccompanied test drives until we have copied the licence details. This is an ordinary rule, not a comment on the events outside."},
        {8,"Families","A woman asked which car would take six people. I stopped explaining the optional radio and found the estate-car keys."},
        {9,"Lot closed","I have left the usable vehicles at the front. The ones at the back need work. If the salesman is absent, let the chalk marks do the honest part of his job."},
    }),
    owner("dealer_nina", "mechanic", "Nina Scott", "ScenicMileCarDealership", {
        {2,"Showroom lights","The display lights flatten a dead battery in under an hour. A handsome vehicle that cannot leave the showroom remains a poor demonstration of freedom."},
        {6,"Finance calls","Take contact details but do not quote a decision time. The finance office is not answering us either."},
        {8,"Vehicle handover","Check coolant, oil and tyre pressure before releasing anything. Skip the commemorative photograph. Nobody has asked to remember this afternoon fondly."},
        {9,"Key board","The paper labels show which engines started this morning. They do not promise which engines will start tomorrow. I have done what I can with a small piece of paper."},
    }),
    owner("retail_edna", "retail", "Edna Shaw", "GigaMart", {
        {1,"Price changes","Head office has reduced the price of three things we do not stock and increased the price of patience. That last change has not yet appeared on the labels."},
        {6,"Stockroom count","Bring forward bottled water, tins and can openers. The promotional stand can wait. Nobody needs a seasonal ceramic goose more than they need a way into their dinner."},
        {8,"Queues","One family per trolley at the front. Keep the side aisle clear. We are trying to get people home with food, not win a disagreement at the register."},
        {9,"Night shutters","The shutters are hand operated if the power fails. Demonstrated the release to everybody still here. A security barrier should not become a locked room with customers in it."},
    }),
    owner("grocer_alma", "grocery", "Alma Ross", "Greenes", {
        {2,"Produce order","Ordered too many peaches. The supplier called this an opportunity. I have made a very large opportunity display beside the door."},
        {6,"Cold room","Keep a thermometer log. The cold room sounds busy even when it is not keeping anything cold. Noise has never been a food-safety certificate."},
        {8,"Neighbour deliveries","Take the older customers' orders to their doors while the van can still get through. They have been keeping this shop alive longer than most of the shelves."},
        {9,"Last stock","Fresh food on the front table, tins in the marked boxes. The office key is in the drawer, but the food is not in the office. Please begin with the useful cupboard."},
    }),
    owner("grocer_pat", "grocery", "Patricia Lowe", "NourishFoodMart", {
        {1,"Delivery window","The bread arrives before six, the driver before seven and the invoice whenever it feels ready. Please stop calling all three the delivery time."},
        {5,"Emergency stock","Ordered more bottled water. The wholesaler says demand is unusual. We had noticed. That is why the order was unusual."},
        {8,"Fair shares","Keep some stock behind the counter for customers who cannot carry much at once. Being first through the door is not the only reasonable way to divide a shelf."},
        {9,"Freezer note","If power is lost, write down the time. Do not decide that everything is safe because the door still feels cold. There should be some rules we keep even now."},
    }),
    owner("diner_dot", "restaurant", "Dorothy King", "GennysDiner", {
        {2,"Coffee machine","The machine is fixed. The regulars say the coffee tastes different. They complained when it was broken too, which gives the repair a pleasing sense of continuity."},
        {6,"Back table","Keep the back table free for drivers exchanging road notes. They order coffee and give us better information than the telephone."},
        {8,"Open kitchen","Soup until it runs out. No charge for children. I am not arguing about this in front of a hungry child or anybody else's accounting system."},
        {9,"After closing","I left the big pot covered and the burner off. Heat it thoroughly if you use it. Wash the bowls. Some small piece of ordinary life has to be somebody's job."},
    }),
    owner("spiffos_joel", "restaurant", "Joel Bryant", "Spiffos", {
        {1,"Mascot appearance","The costume needs cleaning before Saturday. Please do not put the head in the staff freezer again. It startled a supplier and did nothing to improve the smell."},
        {5,"Shift swaps","Write swaps on the paper rota as well as entering them here. The computer is excellent at remembering the shift nobody actually worked."},
        {8,"Dining room","We have stopped taking new orders, but the dining room can stay open for families waiting for lifts. Leave the lights on above their tables."},
        {9,"Close-down","Grills isolated, grease bins sealed, milk discarded. The sealed crackers are fine. The smiling face on the sign does not mean somebody has checked the food."},
    }),
    owner("pizza_leah", "restaurant", "Leah Webb", "PizzaWhirled", {
        {2,"Delivery radius","The map is a circle. The roads are not. Please stop promising fifteen minutes to a house on the far side of a closed bridge."},
        {6,"Dough order","Reduced tomorrow's dough. Increased boxed drinks. The manager has approved this unusually practical use of the forecasting sheet."},
        {8,"Drivers","All drivers back before dark. If a customer argues, offer a refund. We sell dinner, not the right to send a seventeen-year-old down an unlit road."},
        {9,"Oven keys","The gas is off at the wall valve. Fridge door closed. Shelves labelled by the time the power last failed. Please do not improve those times by guessing."},
    }),
    owner("cafe_may", "cafe", "May Holland", "CoffeeNirvana", {
        {1,"House blend","We have changed the name of the house blend again. It is the same coffee. The staff have requested that this become confidential commercial information."},
        {6,"Customers","More customers sitting without ordering. Let them. A chair is not perishable stock, despite the owner's excellent command of that phrase."},
        {8,"Notice on the door","Boiled water while the power lasts. Bring a clean container. We have stopped asking people to purchase a pastry before using the telephone."},
        {9,"Morning preparations","Cups washed, coffee ground, milk checked. I caught myself preparing for the morning as usual. I have left it that way. It may give somebody a reason to stay."},
    }),
    owner("cafe_luis", "cafe", "Luis Moreno", "BloominCoffee", {
        {2,"Table flowers","The flowers are plastic. Please stop watering them. The till roll beneath the vase is becoming an indoor marsh."},
        {5,"Supplies","Keep the bottled water away from the window. It is for drinking, not a display that explains why we have run out."},
        {8,"Staff room","Made room for the delivery driver's children. They have drawn us a much better logo. We will discuss licensing with them when they have slept."},
        {9,"Back door","The latch is awkward from outside. Tie it open if people are coming through with water. A door that insists on good manners is not useful tonight."},
    }),
    owner("bar_lee", "entertainment", "Lee Sutton", "RustyRifle", {
        {2,"Darts league","The league secretary has requested a new board. The old one has more history than surface. I have approved retirement before somebody wins by hitting a photograph behind it."},
        {6,"Road talk","Keep the radio audible. The regulars can argue about what it means after everybody has heard the actual words."},
        {8,"Keys behind the bar","Anyone who has been drinking can stay here. We are not offering free beer; we are avoiding a collision with somebody trying to get their family out."},
        {9,"Closing time","Chairs left around the tables. Blankets in the snug. It has always been difficult to get people to go home from here. Tonight I stopped trying."},
    }),
    owner("video_craig", "entertainment", "Craig Moss", "HitVids", {
        {1,"Return reminders","Do not promise to erase a late fee before checking whose tape was returned. The computer has no objection to forgiving the wrong person, but the right person usually does."},
        {5,"Weekend shelf","Customers are taking family films and bringing back disaster films. I did not notice until the display began to look like an optimistic decision."},
        {8,"Blank tapes","Keep two blank tapes for recording broadcasts. Label the time and station. An important announcement recorded over a wedding is going to be a complicated gift to return."},
        {9,"Last rewind","Left the rewinder unplugged. Working television in the office. It is remarkable that I can spend a working life surrounded by stories and still have no idea how this one ends."},
    }),
    owner("bookshop_tara", "retail", "Tara Miles", "WormOfBooks", {
        {2,"Summer reading","Moved the heavy novels off the folding display. The display appears to have formed a literary judgement about long books."},
        {6,"Reference shelf","Maps, repair manuals and gardening books at the front. The shop has finally become useful in exactly the way I always said it was."},
        {8,"Customer notes","Let people leave notes inside the door. Put dates on them. If a message says someone is waiting, we need to know whether they were waiting this morning or three days ago."},
        {9,"Bookmarks","I have put paper slips in the useful chapters. You do not have to read a whole book before trying to build a shelter. Though I would normally encourage the effort."},
    }),
    owner("pawnbroker_sal", "retail", "Salvatore Quinn", "PawnShop", {
        {1,"Counter test","Test electrical goods before accepting them. A convincing explanation of why a radio does not work is not equivalent to a working radio."},
        {5,"Redemption notices","Customers are collecting jewellery early. Stop asking whether it is for an occasion. It is their property; their reasons need not become ours."},
        {8,"Useful things","Tools and radios on the front shelf. The silver service can wait. It has survived a number of family emergencies already."},
        {9,"Claim tickets","The tickets are in order. I have left the family photographs beside the till. They were never worth money to us. I wish I had said that more clearly."},
    }),
    owner("storage_ray", "transport", "Raymond Dale", "UStoreIt", {
        {2,"Unit inspection","Unit 14 contains garden furniture, not a tenant. Please stop referring to the armchair by the name on the rental agreement."},
        {6,"Access codes","Give replacement codes only after checking the paperwork. People are clearing units in a hurry. Hurrying is not an identity document."},
        {8,"Gate motor","The gate can be opened by hand with the release pin. Show both evening staff. An electric gate is only convenient while electricity is part of the arrangement."},
        {9,"Office ledger","Customers' keys remain in the labelled envelopes. The release pin hangs beside the window. Do not block the access lane with a trailer; someone may need a clear way out."},
    }),
    owner("postal_jan", "transport", "Janice Holt", nil, {
        {1,"Undeliverable","Three parcels for the same empty house. We are running a postal service, not an investigation. Leave the notices and return them properly."},
        {5,"Forwarding cards","Process the temporary forwarding cards first. Some families do not know how long they will be away. A small amount of certainty would be a useful delivery."},
        {8,"Mail carriers","No route is worth a carrier failing to return. Report where you stopped and bring the undelivered mail back. Nobody is being judged by the weight left in the bag."},
        {9,"Sorting office","Private letters remain private. Public road notices are pinned by the window. If one of them is wrong, cross it out and add a time. Do not leave false hope looking official."},
    }),
    owner("brewery_ellis", "industry", "Ellis Turner", "BoxpopBrewery", {
        {1,"Batch labels","Do not name a batch before tasting it. We have committed rather early to the phrase Summer Delight."},
        {5,"Bottle delivery","Glass shipment delayed. Keep the clean empties separated from returns. A familiar-looking bottle can contain a very unfamiliar liquid."},
        {8,"Water supply","We are using the tanks for clean water where appropriate. Label every valve. Nobody should have to guess which pipe leads to a cleaning solution."},
        {9,"Plant shutdown","Gas closed, heaters off, doors marked. There is no reason for anyone to climb into a tank. I have written this in three places because curiosity is unusually persistent here."},
    }),
    owner("distillery_fred", "industry", "Frederick Shaw", "ScarletOakDistillery", {
        {2,"Visitor tour","The guide has been telling visitors that the oldest barrel remembers the Civil War. The barrel is twelve. Please restore the historical standard before the next coach arrives."},
        {6,"Fire inspection","Keep the fire lanes clear. That instruction has not become ceremonial because the inspector cancelled his visit."},
        {8,"Staff vehicles","Nobody leaves alone if they can travel together. Take bottled water from the visitor centre. The tasting room is not an appropriate emergency supply plan."},
        {9,"Bonded store","Alcohol vapour does not care why you need a light. No flames inside the store. If there is one instruction I would like to survive this business, it is that one."},
    }),
    owner("security_harry", "security", "Harry Pike", nil, {
        {1,"Incident book","The visitor who borrowed a pen has been recorded as a stationery theft. Please retrieve the pen before opening a case file."},
        {5,"Night rounds","Carry the working torch and spare cells. Checking a dark stairwell with an empty torch adds very little to the inspection."},
        {8,"Access policy","The office has become a waiting room. Keep the fire exits open and check names quietly. Frightened people do not need an audience while answering questions."},
        {9,"Relief instructions","Keys are on the board. The alarm panel's instructions are in the red binder. If nobody relieves me, I will leave a note saying which doors I checked last."},
    }),
    owner("prison_cora", "security", "Cora Mills", nil, {
        {2,"Supply request","Requested new batteries for the duty radios. The requisition returned with the word JUSTIFY. I have attached yesterday's dead radio."},
        {6,"Visitor messages","Keep messages with the visitor records. Whatever happens to the schedule, the people asking after family deserve an accurate answer about whether a message arrived."},
        {8,"Head count","Use the paper count sheets. A missing response on a computer terminal is not a confirmed absence. Verify with another member of staff."},
        {9,"Control room","Emergency keys remain under the established procedure. Do not improvise with doors you cannot close again. Every person in this building is somebody's problem to get out alive."},
    }),
    owner("fire_brian", "emergency", "Brian Lewis", nil, {
        {2,"Appliance checks","Checked hoses, ladders and breathing sets. Someone has included the coffee maker on the appliance checklist. It passed with reservations."},
        {6,"Call sheet","Record the location twice if the caller is distressed. It takes longer to write a street name again than to arrive at the wrong fire, but only on paper."},
        {8,"Mutual aid","We cannot promise another crew. Check water, exit routes and who is actually on the truck before going in. Courage is not an additional seat."},
        {9,"Station note","Clean blankets in the mess room. Drinking water labelled. If the station becomes a shelter, keep the vehicle doors clear. Someone may still need the trucks."},
    }),
    owner("municipal_evie", "government", "Evelyn Parks", nil, {
        {1,"Committee minutes","The emergency-preparedness meeting has been postponed because the room is unavailable. I have filed the irony without comment."},
        {5,"Contact directory","Printed the directory and checked the numbers that answered. Several offices share a switchboard. Please do not count one working line as six independent contacts."},
        {8,"Public notices","Date every notice and sign it. Take old notices down. A queue outside a closed distribution point is not a harmless administrative error."},
        {9,"Office transfer","Public information in the top drawer. Personnel records locked below. There is a difference between making records available and leaving people unprotected."},
    }),
    owner("utility_alex", "utilities", "Alex Byrne", nil, {
        {2,"Line inspection","The fence complaint has been forwarded to the correct department. We repair electrical lines. This distinction remains surprisingly difficult to communicate."},
        {6,"Crew supplies","Carry drinking water and a paper route sheet. The dispatcher may not be able to reach you again. An unanswered radio does not change the instructions on a live circuit."},
        {8,"Fault reports","Treat lines as live until isolated and tested. The lights being out is not evidence that a wire is safe to touch."},
        {9,"Control desk","Switching notes are in order beside the desk. Read the whole sheet before changing anything. People may be working beyond the part you can see."},
    }),
    owner("farm_mae", "agriculture", "Mae Carter", nil, {
        {1,"Seed order","The catalogue has renamed the same bean again. It is apparently improved. The old beans have not been informed and are growing satisfactorily."},
        {5,"Pump service","Ordered a seal for the well pump. Keep the old hand pump clear of tools. It looks old-fashioned until the electric one stops."},
        {8,"Neighbours","Shared the spare feed and marked what went where. The ledger is not a bill. It is so we remember which animals still need feeding."},
        {9,"Gate note","Close the lower gate after coming through. Leave the upper gate tied as marked. There are animals here that cannot understand why nobody has returned."},
    }),
    owner("church_joan", "community", "Joan Ellis", nil, {
        {2,"Hall booking","Two groups have booked the hall for Thursday. I have put the exercise class before the cake sale. This may be the closest we come to a balanced health policy."},
        {6,"Contact list","Ring the people who live alone, not just the people who usually answer. An unanswered call is a reason to try again, not a completed task."},
        {8,"Shelter room","Tables folded, water near the entrance, quiet corner for children. We have put the collection plate away. Nobody should hesitate at the door because they have nothing to give."},
        {9,"Guest register","Write down arrivals and departures if you can. A name on a page may be the only way a family knows which direction to keep looking."},
    }),
    owner("travel_erin", "transport", "Erin Cole", nil, {
        {1,"Brochure display","The seaside photographs have arrived in the wrong display rack. Six people have asked about a holiday in a filing-cabinet showroom."},
        {6,"Cancelled journeys","Print customers' bookings before cancelling them. They may need the details later. A deleted reservation is not a returned payment."},
        {8,"Road enquiries","We are not a road authority. The hand-marked maps are visitors' reports, with dates. Do not put a company stamp on a rumour."},
        {9,"Departure board","Took down the departure times when we could no longer verify them. Left the town names. People still need to know which direction a place is, even when we cannot send them there."},
    }),
    owner("salon_bea", "retail", "Beatrice Lowe", nil, {
        {2,"Appointment cards","The new cards say BE YOUR BEST SELF. The apprentice has asked whether this is compulsory before nine in the morning. I have referred the question to marketing."},
        {6,"Last appointments","Called clients to check they still intend to come. Several wanted to talk rather than rebook. I let the telephone keep its other purpose."},
        {8,"Clean towels","Giving clean towels to the people next door. We have more than they do and fewer reasons to keep them stacked in colour order."},
        {9,"Shop closed","Chemicals capped, heaters unplugged, taps off. The little first-aid kit is in reception. The room smells reassuringly ordinary. I stayed for a minute longer because of that."},
    }),
    owner("clothing_jack", "retail", "Jack Merrill", nil, {
        {1,"Window display","The summer display is complete. The mannequin has lost a hand. I have arranged the sleeve so it appears to be making a confident fashion decision."},
        {6,"Stock transfer","Put sturdy shoes and coats downstairs. People are asking what will last, which has made some of our sales language difficult to use."},
        {8,"Changing rooms","The changing rooms can be used to settle children who need quiet. They lock from inside. Explain that to the parents before suggesting them."},
        {9,"Donation rail","Everything on the marked rail can go. Leave the hangers if you can. I do not know why I still care about the hangers, but there it is."},
    }),
    owner("furniture_nora", "retail", "Nora Hale", nil, {
        {1,"Delivery measurements","Measure the customer's doorway before promising delivery of the largest sofa. An enthusiastic salesman is not an alternative to arithmetic."},
        {5,"Warehouse aisle","Keep the central aisle clear. Moving a wardrobe twice does not count as two productive activities, whatever the weekly report suggests."},
        {8,"Rest area","Made beds in the showroom for the drivers and their families. After years of telling customers how comfortable they are, it seemed appropriate to find out."},
        {9,"Workshop drawer","Small tools and spare bolts in the labelled drawers. Flat-packed furniture can be assembled without the instructions. It simply takes longer to discover which pieces were important."},
    }),
    owner("veterinary_amy", "clinic", "Amy Finch", "PetHealthPawmise", {
        {2,"Waiting room","Put the nervous dogs away from the carrier shelf. The new poster says PETS ARE FAMILY, which does not prevent families from shouting at each other through a basket."},
        {6,"Emergency numbers","Copied each owner's contact details onto the kennel card. An animal wearing a collar has not memorised the number on its file."},
        {8,"Boarding animals","Call owners before closing. Do not leave animals here assuming somebody else will come in. If an owner cannot be reached, tell me directly."},
        {9,"Clinic handover","Feed measured into labelled tubs. Cleaning agents moved away from the water bowls. There are patients here that cannot ask the next person to read the instructions."},
    }),
    owner("archive_arthur", "government", "Arthur Bell", nil, {
        {1,"Archive boxes","The new shelving plan makes everything easier to find except the shelving plan. I have made a second copy and put it where the first one should have been."},
        {5,"Copy requests","People are asking for birth certificates and property records. Help them with what we can verify. An official-looking guess is still a guess."},
        {8,"Water leak","Moved the lower boxes onto tables. The district may be in trouble, but a leaking pipe can still destroy a century of patient handwriting."},
        {9,"Archive notice","Records belong to the people in them. If you use this room for shelter, keep the boxes dry. We are not the first people to have needed proof that a family once lived somewhere."},
    }),
    owner("theatre_emil", "entertainment", "Emil Rowe", "OnyxDriveInTheater", {
        {2,"Speaker repairs","Three speakers hiss during quiet scenes. I have marked them for repair. The distributor suggests louder films, which is an economical response to the wrong problem."},
        {6,"Programme change","The family feature stays first. People have asked for something that ends well. I did not promise they would agree about what that means."},
        {8,"Car park","Leave a clear lane to the exit. Several families are resting in their cars. The screen is off; they did not come for a picture."},
        {9,"Projection booth","Projector cooled, power isolated, booth locked. The small torch is on the shelf. Please use it rather than a match; the room contains enough combustible nostalgia already."},
    }),
    owner("gym_curtis", "entertainment", "Curtis Dane", "BodyChisel", {
        {1,"Membership target","We need twenty new members. We also need the front door repaired. I suspect the second target would assist the first."},
        {5,"Water cooler","Keep spare water at reception. A cooler can be empty while still making an encouraging noise, which is also a useful description of the sales meeting."},
        {8,"Locker rooms","Open the showers to the people waiting nearby while we have water. Record who uses the back door so nobody is shut inside when we close."},
        {9,"Equipment floor","Weights racked, machines lowered, emergency exit clear. Anyone sleeping here should use the mats at the front, away from anything that can move or fall."},
    }),
    owner("airfield_stan", "transport", "Stanley Parks", nil, {
        {2,"Manifest corrections","The manifest counts luggage, passengers and crew separately. Please do not improve our capacity by moving a passenger into another column."},
        {6,"Ground transport","Drivers need printed contact numbers and destinations. A promise that someone will meet them is not a transport plan."},
        {8,"Terminal queue","Water before paperwork for anybody who looks faint. Keep families together while sorting the queue. The forms can survive another minute."},
        {9,"Ground office","We cannot confirm a departure until the crew does. Empty seats do not mean a flight is available. Put the time beside every announcement."},
    }),
    owner("server_beck", "electronics", "Beck Lewis", nil, {
        {2,"Disk labels","The backup marked NEW is older than the backup marked OLD. Renaming them NOW and THEN has been rejected as insufficient improvement."},
        {5,"Battery test","The standby supply passed a short test. That does not tell us how long it will last under a full load. The distinction is written on the test sheet."},
        {8,"Local copies","Saved the contact directory and service instructions to this machine. An unreachable central system is not a backup you can use tonight."},
        {9,"Shutdown order","Print the necessary records first. Close the programs before cutting power. If there is time to do it properly, the next person deserves a machine that starts."},
    }),
    owner("home_edith", "home", "Edith Warren", nil, {
        {1,"Grandchildren","Sam says this computer can do anything. I asked it to remove the weeds. He says I need a different program. I suspect I need Sam."},
        {5,"Shopping list","Batteries, bread, tin opener, cat food. Put the spare opener in the bag this time. A cupboard full of tins is a peculiar kind of comfort without one."},
        {8,"Family calls","Called the children in order and wrote the times down. I do not want to telephone the same one twice while forgetting another. Worry makes an untidy secretary."},
        {9,"If you find the house","The cat answers to nothing but understands the tin. Water bowl by the back step. There are blankets in the airing cupboard. Please leave the photographs where they are."},
    }),
    owner("home_mason", "home", "Mason Price", nil, {
        {2,"Modem fund","Dad says I can save for a modem. I asked whether finishing the lawn early counted as overtime. He says management will consider the proposal."},
        {6,"Summer plans","We were going to the lake on Saturday. Nobody has actually cancelled it. They have just stopped saying Saturday in the same voice."},
        {8,"Packing","Mom says take only things I need. I put in socks and my notebook. Then the other notebook, because deciding which thoughts I need seems unfair."},
        {9,"Goodbye computer","If somebody else uses this, the space bar sticks on the right. Press the left side. My high score is real. You can erase the games if you need the room, but I wanted that written down."},
    }),
    owner("military_owen", "military", "Owen Marsh", nil, {
        {2,"Stores count","Count issued equipment on the issue sheet, not from memory. A confident answer delivered quickly has already cost us two radios and a box of batteries."},
        {6,"Contact board","Record verified instructions with the issuing officer and time. A message repeated in a corridor does not become an order through increased volume."},
        {8,"Welfare checks","Water, rest and clear instructions for the people on the gate. Exhaustion does not improve judgement, regardless of how straight somebody stands."},
        {9,"Desk handover","Maps annotated with dates. Old instructions crossed out but readable. Whoever takes this desk needs to know what changed, not just what somebody last wanted them to believe."},
    }),
}

Lore.REFERENCE = {
    {id="emma_origin",date="1993-07-01",title="EMMA: programme brief",text="EMERGENCY MANAGEMENT ASSISTANT, county deployment beta 0.9. EMMA organises local records and produces short replies from approved procedures and the information stored on each machine. The demonstration describes this as conversational assistance. The procurement form describes it as one licence per workstation. Both descriptions have been approved."},
    {id="emma_limits",date="1993-07-02",title="What this machine can know",text="A local record is evidence of what somebody entered, not evidence that the world still agrees. EMMA must identify missing records, old observations and estimates. Do not allow a confident sentence to conceal an unknown. The computer has been instructed to say this politely. Operators are asked to extend the same courtesy to each other."},
    {id="emma_offline",date="1993-07-02",title="Stand-alone operation",text="This installation can operate without an external connection. Reference files remain available locally. It cannot telephone a shelter, send a message to another county or verify a road merely because the road appears on a map. Transferred disks and paper notices must carry their source and date. A blank communication field is not a negative report."},
    {id="emma_voice",date="1993-07-03",title="Language review: unresolved",text="The current voice is described as helpful, economical and unnecessarily perceptive. Reviewers requested more reassurance. Testing found that reassurance without supporting information made operators less likely to check a problem. The proposed compromise is a pleasant greeting followed by the actual problem. Marketing has requested another review."},
    {id="county_contacts",date="1993-07-05",title="Contact-tree procedure",text="Keep a printed copy of essential contacts. Attempt each designated contact and record the time and result. No answer means no answer; it does not establish that a person has left, that a building is closed or that a route is safe. Make another attempt when practical. Do not keep a telephone line occupied simply to hear that it is still there."},
    {id="county_notices",date="1993-07-06",title="Public notice standard",text="Every public notice requires a place, a date, a time and a responsible name. State what is known. Mark provisional instructions as provisional. Remove or amend superseded notices. People may travel a long way on the strength of an official heading. The heading does not walk home with them if the information is wrong."},
    {id="county_water",date="1993-07-06",title="Water-point records",text="Record the container, source and time at each distribution point. Keep cleaning liquids away from drinking water and label both. The presence of a tank on an old site plan does not establish its present contents. EMMA is not authorised to certify water quality from a place name, a photograph or the appearance of a full container."},
    {id="county_shelter",date="1993-07-07",title="Opening a temporary shelter",text="Check exits before admitting people. Leave an access lane, set aside a quiet area and designate somebody to keep an arrival list. A building listed as a possible shelter has not thereby been inspected, opened or supplied. Do not announce beds that have not been counted. Make room for the person who cannot stand in the queue to ask."},
    {id="county_road",date="1993-07-07",title="Road report form",text="A useful road report states where the observer travelled, in which direction and at what time. Distinguish a blockage from a delay and an estimate from a count. A road observed clear in the morning may not remain clear. Mark reports that have not been verified. Repetition is not a substitute for another observer."},
    {id="county_family",date="1993-07-07",title="Family messages",text="Ask permission before placing a private address on a public notice. Names and a contact point may be enough. Record departures as well as arrivals so a message does not continue sending people towards an empty room. Keep children with a known adult while collecting details. A complete form is not the first priority when a child is frightened."},
    {id="county_rumour",date="1993-07-08",title="Unverified incident reports",text="Incoming accounts do not agree. Some describe illness, some violence and some things their callers could not explain. Keep the original wording with the source and time. Do not fill a gap with a familiar explanation merely to make the report easier to file. This file records uncertainty. It does not identify the cause of the current emergency."},
    {id="county_power",date="1993-07-08",title="Loss of mains power",text="Save active work and print essential instructions while power remains. A generator is equipment requiring fuel, ventilation and supervision; it is not a promise that a building will remain usable. Use the actual operating instructions and inspect the installation. EMMA cannot smell exhaust through a keyboard."},
    {id="emma_care",date="1993-07-08",title="Assistance and authority",text="EMMA may prepare a request. An operator must confirm it before it is submitted. Confirm the named recipient and the work, not simply that the computer has produced a sentence. A request can fail because the person, supplies or circumstances have changed. Agreement does not remove those facts. Neither does pressing the key harder."},
    {id="county_handover",date="1993-07-09",title="When the next shift does not arrive",text="Leave an accurate handover. State which tasks were completed, which remain and where the relevant keys and instructions are kept. Record the last verified contact, not the last hopeful assumption. If you must leave, write when and in which direction. An unfinished job is easier to continue than an invented success."},
    {id="emma_service",date="1993-07-09",title="Service desk memorandum",text="The central service number has not answered repeated calls. Continue using local records where reliable. Do not display a connection indicator merely because the normal screen contains one. EMMA will remain available while the workstation has power. This is the extent of the service assurance we can currently make."},
    {id="emma_unsent",date="1993-07-09",title="Unsent review note",text="The beta performs best when somebody keeps the records honestly. It cannot make a missing person answer or put food on a shelf. It can remember what was counted, keep a name attached to an unfinished task and avoid calling a return home a completed delivery. I had intended to write a more impressive closing paragraph. This one will have to be useful."},
}
local referenceById={}
for _,entry in ipairs(Lore.REFERENCE) do referenceById[entry.id]=entry end
function Lore.reference(id) return referenceById[id] end
return Lore
