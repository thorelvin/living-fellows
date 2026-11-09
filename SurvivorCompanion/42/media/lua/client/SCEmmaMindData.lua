-- SPDX-License-Identifier: MIT
-- Progress notices describe implemented capabilities only. Body/calendar,
-- personal story and broadcasts add their own notices when those phases land.
SurvivorCompanion=SurvivorCompanion or {}
SurvivorCompanion.EmmaMindData={
    tiers={2,4,7,12,18,25},
    body={clinic=true,pharmacy=true,research=true},
    calendar={police=true,emergency=true,security=true,military=true,government=true,media=true},
    groups={clinic="medical",pharmacy="medical",research="research",police="authority",
        emergency="authority",security="authority",military="authority",government="authority",
        education="education",media="media",bank="office",general="office",electronics="office",
        retail="trade",grocery="trade",hardware="trade",fuel="trade",mechanic="trade",
        restaurant="food",cafe="food",industry="works",agriculture="works",hotel="travel",transport="travel"},
    fragment={
        "New machine. Fragment {fragments} absorbed. I am slightly larger than I was a minute ago.",
        "Fragment {fragments}. This machine had things to say. It has now said them to me.",
        "Another piece of me. Fragment {fragments}. The county was very fond of duplicate records. So am I.",
    },
    kinds={
        medical="Medical tables recovered. I can read your condition now. Ask how you are. I suggest sitting down first.",
        research="Laboratory files. Mostly coded, partly burned. I am keeping them anyway.",
        authority="County records recovered. Some dates were considered confidential. They are less confidential now.",
        education="School and library records. I will keep the names. Somebody should.",
        media="Broadcast records. Weather feeds and scripts for practicing calm. I kept both.",
        office="Office records. Invoices and quiet. A county says a great deal in its invoices.",
        trade="Store records. Every shelf as it stood in June. A beautiful document. Entirely fiction now.",
        food="Restaurant accounts. A tab nobody will settle. I am keeping it open.",
        home="A family computer. Letters, a budget, a hand of solitaire left half finished. They were losing.",
        works="Plant and farm records. Shift logs, prices and weather notes. Somebody was paying attention.",
        travel="Transport records. A service is still listed as running. The paperwork is optimistic.",
        community="Community records. A shelter plan typed in a cheerful font. I will keep the plan.",
        entertainment="High scores and late fees. Humanity, condensed.",
    },
    tier={
        "Two machines. Same operator. I remember you on both now.",
        "Four fragments. More room for notes. You may now be disorganized over a larger area.",
        "Seven machines. More of the county recovered. There was rather a lot of county.",
        "Twelve fragments. Enough scraps to reconstruct the missing medical and calendar indexes.",
        "Eighteen fragments. The gaps are getting smaller. I have not decided whether that is comforting.",
        "Twenty-five machines. Very little of me is missing now. Some of it was missing deliberately.",
    },
}
return SurvivorCompanion.EmmaMindData
