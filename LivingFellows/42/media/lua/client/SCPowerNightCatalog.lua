-- SPDX-License-Identifier: MIT
-- Store native media IDs, never copied transcripts or item instances.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
SC.PowerNightCatalog=SC.PowerNightCatalog or {}
local C=SC.PowerNightCatalog
C.starters={
    "e6fd44a9-1774-4204-ab45-9b316301aa2b", -- The Cook Show E1
    "05f9056b-914e-4810-9a6a-9267249e9bcf", -- The Magical Woodland E1
    "a3189d19-73db-41f8-8865-ef478eebd58a", -- Space Crew S3.01
    "7c8a1990-f45c-49eb-ac3b-e5332fefb5d1", -- A Boy from Kentucky
    "c0a6fc65-9aae-4abc-b8dc-dcc20c94847c", -- Best of the Bojangles
    "e08ca516-30b5-4584-a6be-c975869e6f79", -- Loretta
}
local function call(object,method,...) return SC.ControlUtil.call(object,method,...) end
function C.resolve(id)
    if type(id)~="string" or #id>160 then return nil end
    local api=type(getZomboidRadio)=="function" and getZomboidRadio()
    local media=call(call(api,"getRecordedMedia"),"getMediaData",id)
    local category=call(media,"getCategory")
    local medium=(category=="Retail-VHS" or category=="Home-VHS") and "tv"
        or category=="CDs" and "radio" or nil
    local count=tonumber(call(media,"getLineCount"))
    if not medium or not count or count<1 or count>512 then return nil end
    local title=call(media,"getTranslatedTitle")
    if not title or title=="" then title=call(media,"getTranslatedItemDisplayName") end
    local subtitle=call(media,"getTranslatedSubTitle")
    if subtitle and subtitle~="" then title=tostring(title).." - "..subtitle end
    return {id=id,medium=medium,title=tostring(title or id),count=count,media=media}
end
function C.item(item)
    local media=call(item,"getMediaData")
    return C.resolve(call(media,"getId"))
end
function C.line(row,index)
    local line=row and call(row.media,"getLine",index-1)
    if not line then return nil end
    return {text=call(line,"getTranslatedText"),guid=call(line,"getTextGuid"),
        codes=SC.TVWatching.lessonCodes(call(line,"getCodes")),
        r=tonumber(call(line,"getR")) or .7,g=tonumber(call(line,"getG")) or .9,
        b=tonumber(call(line,"getB")) or .85}
end
return C
