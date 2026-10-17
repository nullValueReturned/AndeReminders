local AR = AndeReminders

-- Shared helpers. Every game-API wrapper that has moved or been removed between
-- patches lives here, so modules never call a deprecated global directly.

local Util = {}
AR.Util = Util

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------

local CHAT_PREFIX = "|cFFFF6600[AndeReminders]|r "

function Util.Print(msg)
    print(CHAT_PREFIX .. msg)
end

-- ---------------------------------------------------------------------------
-- Secret values (12.0+): protected values addon code may not read or compare
-- ---------------------------------------------------------------------------

function Util.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns v as a plain string, or "" when it is nil, secret, or not text. The secret check
-- comes first and nothing here compares v: tainted code may not compare a secret value.
function Util.SafeString(v)
    if Util.IsSecret(v) then return "" end
    local kind = type(v)
    if kind == "number" then return tostring(v) end
    if kind ~= "string" then return "" end  -- also covers nil
    -- Belt and braces: reading an unflagged secret string throws, so probe inside pcall.
    local ok, copy = pcall(function() return v:sub(1) end)
    return ok and copy or ""
end

-- Returns v as a number, or nil when it is nil, secret, or not numeric.
function Util.SafeNumber(v)
    if Util.IsSecret(v) then return nil end
    return tonumber(v)
end

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

function Util.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local copy = {}
    for k, val in pairs(v) do copy[k] = Util.DeepCopy(val) end
    return copy
end

-- True in any instance (dungeon, raid, scenario, delve, battleground) or while grouped.
-- Backs the "only alert in dungeons, raids and groups" option.
function Util.InGroupContent()
    return (IsInInstance()) or IsInGroup()
end

-- ---------------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------------

-- Returns a function that (re)schedules fn to run `delay` seconds after its last call.
function Util.Debounce(delay, fn)
    local timer
    return function()
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(delay, function()
            timer = nil
            fn()
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Specialization / role
-- ---------------------------------------------------------------------------

-- specIndex, specID, role of the active specialization; nil when none is chosen yet.
function Util.GetSpec()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index or index == 0 then return nil end
    local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(index)
    if not specID or specID == 0 then return nil end
    return index, specID, role
end

-- The assigned group role, falling back to the active spec's role.
function Util.GetRole()
    local role = UnitGroupRolesAssigned("player")
    if not Util.IsSecret(role) and role and role ~= "NONE" then return role end
    local _, _, specRole = Util.GetSpec()
    return specRole
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

-- Two-handed weapons: melee two-handers plus bows, guns and crossbows. (Wands use
-- INVTYPE_RANGEDRIGHT and are one-handed.)
local TWO_HANDED_LOCS = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED   = true,
}

-- equipLoc, classID, subClassID for an item link. Synchronous: never waits on the item cache.
function Util.GetItemType(link)
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    return equipLoc, classID, subClassID
end

function Util.IsTwoHanded(equipLoc)
    return TWO_HANDED_LOCS[equipLoc] == true
end

function Util.IsShield(equipLoc)
    return equipLoc == "INVTYPE_SHIELD"
end

-- Effective item level of an equipped item. GetItemInfo only reports the base level, which
-- ignores upgrades and scaling, so ask for the current level of the equipped item first.
function Util.GetEquippedItemLevel(slot, link)
    link = link or GetInventoryItemLink("player", slot)
    if not link then return nil end

    local location = ItemLocation:CreateFromEquipmentSlot(slot)
    local ilvl = location and C_Item.GetCurrentItemLevel(location)
    if ilvl and ilvl > 0 then return ilvl end

    ilvl = C_Item.GetDetailedItemLevelInfo(link)
    if ilvl and ilvl > 0 then return ilvl end

    local _, _, _, baseLevel = C_Item.GetItemInfo(link)
    return baseLevel
end

-- Enchant ID embedded in an item link (0 when the item has none).
function Util.GetLinkEnchantID(link)
    local enchant = link and link:match("item:%d+:(%d*)")
    return tonumber(enchant) or 0
end

-- ---------------------------------------------------------------------------
-- Fonts (LibSharedMedia when present, four stock fonts otherwise)
-- ---------------------------------------------------------------------------

local Fonts = {}
AR.Fonts = Fonts

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FALLBACK_NAMES = { "Friz Quadrata TT", "Morpheus", "Skurri", "Arial Narrow" }
local FALLBACK_PATHS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.ttf",
    ["Skurri"]           = "Fonts\\skurri.ttf",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
}

Fonts.DEFAULT_NAME = "Friz Quadrata TT"
Fonts.DEFAULT_PATH = "Fonts\\FRIZQT__.TTF"

function Fonts.List()
    if LSM then return LSM:List("font") end
    return FALLBACK_NAMES
end

function Fonts.Path(name)
    if LSM then
        local path = LSM:Fetch("font", name)
        if path then return path end
    end
    return FALLBACK_PATHS[name] or Fonts.DEFAULT_PATH
end

-- SetFont reports an unusable font by returning false, and a FontString with no font throws
-- on SetText, so fall back to the stock font instead of leaving the string unset. (Only an
-- explicit false counts: older clients returned nothing at all.)
function Fonts.Apply(fontString, name, size, flags)
    flags = flags or ""
    if fontString:SetFont(Fonts.Path(name), size, flags) == false then
        fontString:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
end

-- ---------------------------------------------------------------------------
-- Alert sounds (LibSharedMedia when present, a few stock sounds otherwise)
-- ---------------------------------------------------------------------------

local Sounds = {}
AR.Sounds = Sounds

local BUILTIN_SOUNDS = {
    { "Raid Warning", SOUNDKIT and SOUNDKIT.RAID_WARNING },
    { "Ready Check",  SOUNDKIT and SOUNDKIT.READY_CHECK },
    { "Alarm Clock",  SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 },
}

-- Dropdown options: "None" (value "") followed by every available sound.
function Sounds.Options()
    local options, seen = { { label = "None", value = "" } }, {}
    for _, entry in ipairs(BUILTIN_SOUNDS) do
        if entry[2] then
            options[#options + 1] = { label = entry[1], value = entry[1] }
            seen[entry[1]] = true
        end
    end
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            if not seen[name] then options[#options + 1] = { label = name, value = name } end
        end
    end
    return options
end

function Sounds.Play(name)
    if not name or name == "" then return end
    for _, entry in ipairs(BUILTIN_SOUNDS) do
        if entry[1] == name and entry[2] then
            PlaySound(entry[2], "Master")
            return
        end
    end
    local path = LSM and LSM:Fetch("sound", name, true)
    if path then PlaySoundFile(path, "Master") end
end
