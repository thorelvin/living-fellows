-- SPDX-License-Identifier: MIT
-- Original July 1993 reader text. No codes are quoted from the owner's files.
LivingFellows=LivingFellows or {}
LivingFellows.TerminalLockCardData={
    sites={police="POL",emergency="FIR",security="SEC",military="MIL",pharmacy="PHA",clinic="CLN",
        education="EDU",research="LAB",media="PRS",bank="BNK",hotel="HTL",transport="TRN",electronics="ELX",
        mechanic="GAR",hardware="HDW",grocery="GRO",fuel="FUL",restaurant="FOD",cafe="CAF",community="COM",
        government="GOV",industry="PLT",entertainment="REC",retail="RTL",office="OFC",general="GEN"},
    search={"Cards like that live in drawers. Look around this room.",
        "The reader wants an access card. The drawers may have a better memory than the staff.",
        "There may be a card nearby. People rarely took their work home willingly.",
        "Check the furniture in this room. An access card is easier to lose than a computer."},
    absent={"The cardholder signed out on %1. The card left with them.",
        "Last sign-out: %1. The access card went home. The reader log stayed here.",
        "The card left this building on %1. Fortunately, the reader kept a partial copy.",
        "Card returned to its holder on %1. You will have to work from the old read."},
    encoded={"Service card encoded. Please do not lose it. Everyone loses it.",
        "Service stripe written. A small promotion, with no change in salary.",
        "You now have a service card. The responsibility fits in a shirt pocket.",
        "Service card ready. This is the part where I ask you to keep it somewhere sensible."},
}
return LivingFellows.TerminalLockCardData
