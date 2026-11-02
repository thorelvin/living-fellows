-- SPDX-License-Identifier: MIT
-- The printable and live wheel share this fixed mapping. Never seed it.
SurvivorCompanion=SurvivorCompanion or {}
SurvivorCompanion.TerminalLockWheelData={
    outer="ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    inner="QWERTYUIOPASDFGHJKLZXCVBNM",
    windows={0,8,17},
    markers={{name="DIAMOND",position=0},{name="CIRCLE",position=6},
        {name="TRIANGLE",position=13},{name="SQUARE",position=19}},
    pages={
        {title="LARCHFIELD OWNER'S MANUAL",art="ManualCover",text={
            "County edition, 1993. Keep this handbook with your computer.",
            "Your computer is a precision instrument. So was the office clock. Try to remember where that went.",
            "The last page contains your recovery wheel. One handbook works with every Larchfield machine."}},
        {title="1 / ELECTRICITY IS NOT A SUGGESTION",art="ManualPower",text={
            "Connect the power cord to a working supply. A generator is a supply. A promise from the maintenance office is not.",
            "Save your work before switching off. Unsaved work is classed as a voluntary donation to the void.",
            "Keep liquids away from the case. The machine does not need coffee. It already knows everything you are avoiding."}},
        {title="2 / FILES AND OTHER RESPONSIBILITIES",art="ManualFiles",text={
            "Deleted files may remain in recoverable sectors. Search for an unusual word you remember from the document.",
            "A sector index points to another file. Follow the index before concluding that the computer has a personal grievance.",
            "Copy important files to a disk. Label the disk. The label IMPORTANT is not a filing system."}},
        {title="3 / LIMITED WARRANTY",art="ManualWarranty",text={
            "Do not open the case while powered. If you do, Larchfield recommends a different hobby.",
            "Our warranty covers manufacturing faults. It does not cover water, fire, deliberate impact or the disappearance of civil government.",
            "For service, contact your local dealer. If your dealer answers by biting, discontinue the call."}},
        {title="4 / ACCOUNT RECOVERY WHEEL",text={
            "Turn the named symbol to the outer letter.",
            "Read or click the requested window.",
            "Arrows or mouse wheel turn the ring.",
            "One mapping works on every Larchfield machine."}},
    },
}
return SurvivorCompanion.TerminalLockWheelData
