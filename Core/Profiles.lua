local AR   = AndeReminders
local Util = AR.Util

-- Saved variables layout:
--   AndeRemindersDB = {
--       profiles    = { [name] = { ...every module's settings... } },
--       profileKeys = { ["Character-Realm"] = name },   -- which profile each character uses
--       ui          = { scale = 1 },                    -- window settings shared by every profile
--   }
-- AR.db is always the active profile's table. New characters start on "Default", so by default
-- every character shares one set of settings; they can be given their own profile at any time.
-- Switching profiles reloads the UI: modules hold references into their profile's tables.

local DEFAULT_PROFILE = "Default"
local EXPORT_PREFIX   = "ARPROFILE1:"

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Picks this character's profile (migrating pre-profile saved variables) and sets AR.db.
function AR:LoadProfile()
    if not AndeRemindersDB then AndeRemindersDB = {} end
    if not AndeRemindersDB.profiles then
        -- Saved variables from before profiles existed: the whole table is the one profile.
        AndeRemindersDB = { profiles = { [DEFAULT_PROFILE] = AndeRemindersDB } }
    end
    local root = AndeRemindersDB
    root.profileKeys = root.profileKeys or {}
    root.ui          = root.ui or {}
    if not root.profiles[DEFAULT_PROFILE] then root.profiles[DEFAULT_PROFILE] = {} end

    local key  = CharKey()
    local name = root.profileKeys[key]
    if not name or not root.profiles[name] then
        name = DEFAULT_PROFILE
        root.profileKeys[key] = name
    end

    AR.root, AR.profileName, AR.db = root, name, root.profiles[name]
end

function AR:GetProfileNames()
    local names = {}
    for name in pairs(AR.root.profiles) do
        if name ~= DEFAULT_PROFILE then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    table.insert(names, 1, DEFAULT_PROFILE)
    return names
end

function AR:SwitchProfile(name)
    if not AR.root.profiles[name] then return end
    AR.root.profileKeys[CharKey()] = name
    ReloadUI()
end

local function CleanName(name)
    return (name or ""):match("^%s*(.-)%s*$")
end

-- New profile holding a copy of the active one. Returns true, or nil and a reason.
function AR:CreateProfile(name)
    name = CleanName(name)
    if name == "" then return nil, "Enter a name for the profile." end
    if AR.root.profiles[name] then return nil, "A profile named \"" .. name .. "\" already exists." end
    AR.root.profiles[name] = Util.DeepCopy(AR.db)
    return true
end

function AR:DeleteProfile(name)
    if name == DEFAULT_PROFILE or not AR.root.profiles[name] then return end
    AR.root.profiles[name] = nil
    for key, used in pairs(AR.root.profileKeys) do
        if used == name then AR.root.profileKeys[key] = DEFAULT_PROFILE end
    end
    if name == AR.profileName then ReloadUI() end
end

local function ReplaceActiveProfile(data)
    local profile = AR.root.profiles[AR.profileName]
    wipe(profile)
    for k, v in pairs(data) do profile[k] = v end
    ReloadUI()
end

function AR:ResetProfile()
    ReplaceActiveProfile({})
end

function AR:CopyProfileFrom(name)
    local source = AR.root.profiles[name]
    if not source or source == AR.db then return end
    ReplaceActiveProfile(Util.DeepCopy(source))
end

-- ---------------------------------------------------------------------------
-- Export / import
-- ---------------------------------------------------------------------------

function AR:ExportProfile()
    local LibSerialize = LibStub("LibSerialize", true)
    local LibDeflate   = LibStub("LibDeflate", true)
    if not LibSerialize or not LibDeflate then return nil, "Missing LibSerialize/LibDeflate" end

    local data = Util.DeepCopy(AR.db)
    -- Runtime bookkeeping that must not travel to another character.
    if data.encounter and data.encounter.midnightFalls then
        data.encounter.midnightFalls.pendingRestore = nil
    end

    local serialized = LibSerialize:Serialize({ kind = "profile", data = data })
    local compressed = LibDeflate:CompressDeflate(serialized, { level = 5 })
    return EXPORT_PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

-- Creates a profile called name from an export string. Returns true, or nil and a reason.
function AR:ImportProfile(str, name)
    local LibSerialize = LibStub("LibSerialize", true)
    local LibDeflate   = LibStub("LibDeflate", true)
    if not LibSerialize or not LibDeflate then return nil, "Missing LibSerialize/LibDeflate" end

    name = CleanName(name)
    if name == "" then return nil, "Enter a name for the profile." end
    if AR.root.profiles[name] then return nil, "A profile named \"" .. name .. "\" already exists." end

    str = CleanName(str)
    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "Not a recognized AndeReminders profile string."
    end
    local decoded = LibDeflate:DecodeForPrint(str:sub(#EXPORT_PREFIX + 1))
    local serialized = decoded and LibDeflate:DecompressDeflate(decoded)
    if not serialized then return nil, "Corrupted profile string." end
    local ok, payload = LibSerialize:Deserialize(serialized)
    if not ok or type(payload) ~= "table" or payload.kind ~= "profile" or type(payload.data) ~= "table" then
        return nil, "Corrupted profile string."
    end

    AR.root.profiles[name] = payload.data
    return true
end
