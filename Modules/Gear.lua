local AR   = AndeReminders
local Util = AR.Util

-- ---------------------------------------------------------------------------
-- Spec data: primary stat + weapon-type requirements per specialization ID.
-- ---------------------------------------------------------------------------
local SPEC_DATA = {
    -- Warrior
    [71]  = { name = "Arms Warrior",           stat = "STR", require2H = true,  forbidShield = true  },
    [72]  = { name = "Fury Warrior",           stat = "STR",                    forbidShield = true  },
    [73]  = { name = "Prot Warrior",           stat = "STR",                    requireShield = true },
    -- Paladin
    [65]  = { name = "Holy Paladin",           stat = "INT",                    requireShield = true },
    [66]  = { name = "Prot Paladin",           stat = "STR",                    requireShield = true },
    [70]  = { name = "Ret Paladin",            stat = "STR", require2H = true,  forbidShield = true  },
    -- Death Knight
    [250] = { name = "Blood DK",               stat = "STR", require2H = true  },
    [251] = { name = "Frost DK",               stat = "STR"                    },
    [252] = { name = "Unholy DK",              stat = "STR", require2H = true  },
    -- Demon Hunter
    [577] = { name = "Havoc DH",               stat = "AGI" },
    [581] = { name = "Vengeance DH",           stat = "AGI" },
    [1480] = { name = "Devourer DH",           stat = "INT" },
    -- Druid
    [102] = { name = "Balance Druid",          stat = "INT" },
    [103] = { name = "Feral Druid",            stat = "AGI" },
    [104] = { name = "Guardian Druid",         stat = "AGI" },
    [105] = { name = "Resto Druid",            stat = "INT" },
    -- Evoker
    [1467] = { name = "Devastation Evoker",    stat = "INT" },
    [1468] = { name = "Preservation Evoker",   stat = "INT" },
    [1473] = { name = "Augmentation Evoker",   stat = "INT" },
    -- Hunter
    [253] = { name = "BM Hunter",              stat = "AGI" },
    [254] = { name = "MM Hunter",              stat = "AGI" },
    [255] = { name = "Survival Hunter",        stat = "AGI" },
    -- Mage
    [62]  = { name = "Arcane Mage",            stat = "INT" },
    [63]  = { name = "Fire Mage",              stat = "INT" },
    [64]  = { name = "Frost Mage",             stat = "INT" },
    -- Monk
    [268] = { name = "Brewmaster Monk",        stat = "AGI" },
    [269] = { name = "Windwalker Monk",        stat = "AGI" },
    [270] = { name = "Mistweaver Monk",        stat = "INT" },
    -- Priest
    [256] = { name = "Disc Priest",            stat = "INT" },
    [257] = { name = "Holy Priest",            stat = "INT" },
    [258] = { name = "Shadow Priest",          stat = "INT" },
    -- Rogue
    [259] = { name = "Assassination Rogue",    stat = "AGI" },
    [260] = { name = "Outlaw Rogue",           stat = "AGI" },
    [261] = { name = "Subtlety Rogue",         stat = "AGI" },
    -- Shaman
    [262] = { name = "Elemental Shaman",       stat = "INT" },
    [263] = { name = "Enhancement Shaman",     stat = "AGI", forbidShield = true },
    [264] = { name = "Resto Shaman",           stat = "INT" },
    -- Warlock
    [265] = { name = "Affliction Warlock",     stat = "INT" },
    [266] = { name = "Demonology Warlock",     stat = "INT" },
    [267] = { name = "Destruction Warlock",    stat = "INT" },
}

local SLOT_NAMES = {
    [1]  = "Head",     [2]  = "Neck",      [3]  = "Shoulder",
    [5]  = "Chest",    [6]  = "Waist",     [7]  = "Legs",
    [8]  = "Feet",     [9]  = "Wrist",     [10] = "Hands",
    [11] = "Finger 1", [12] = "Finger 2",  [13] = "Trinket 1",
    [14] = "Trinket 2",[15] = "Back",      [16] = "Main Hand",
    [17] = "Off Hand",
}
-- Report order for per-slot results (pairs() over SLOT_NAMES is unordered).
local SLOT_ORDER = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local MAIN_HAND, OFF_HAND, BACK = 16, 17, 15
local DEFAULT_DURABILITY_PERCENT = 50
local ENGINEERING_SKILL_LINE = 202
local GOBLIN_GLIDER_RECIPE   = 126392

local GearModule = {}
local durabilityWarnFrame = nil
local needsRecheck = false  -- a scheduled check was skipped because the player was in combat

local gearAlert = AR.UI.CreateAlert({
    name = "AndeRemindersGearAlert", anchor = "gear", width = 380, fallbackY = -300,
})

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function GearModule:InitDB(db)
    if not db.gear then db.gear = {} end
    if not db.gear.notify then db.gear.notify = {} end
    if db.gear.notify.chat   == nil then db.gear.notify.chat   = true end
    if db.gear.notify.screen == nil then db.gear.notify.screen = true end
    if not db.gear.checks then db.gear.checks = {} end
    if db.gear.checks.weaponType    == nil then db.gear.checks.weaponType    = true end
    if db.gear.checks.weaponStat    == nil then db.gear.checks.weaponStat    = true end
    if db.gear.checks.lowIlvl       == nil then db.gear.checks.lowIlvl       = true end
    if db.gear.checks.lowDurability == nil then db.gear.checks.lowDurability = true end
    if db.gear.checks.cloakGlider  == nil then db.gear.checks.cloakGlider   = true end
    if db.gear.lowIlvlThreshold    == nil then db.gear.lowIlvlThreshold     = 50   end
    if db.gear.durabilityThreshold == nil then db.gear.durabilityThreshold = DEFAULT_DURABILITY_PERCENT end
end

function GearModule:ShowAlert(text)
    gearAlert:Show(text)
end

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------

function GearModule:CheckWeaponType(specData)
    local issues = {}
    local mhLink = GetInventoryItemLink("player", MAIN_HAND)
    local ohLink = GetInventoryItemLink("player", OFF_HAND)
    local ohIsShield = ohLink ~= nil and Util.IsShield((Util.GetItemType(ohLink)))

    if specData.require2H and mhLink then
        local equipLoc, classID = Util.GetItemType(mhLink)
        if classID == 2 and not Util.IsTwoHanded(equipLoc) then
            table.insert(issues, specData.name .. ": main hand should be a 2-handed weapon")
        end
    end

    if specData.requireShield and not ohIsShield then
        table.insert(issues, specData.name .. ": off-hand should be a shield")
    end

    if specData.forbidShield and ohIsShield then
        table.insert(issues, specData.name .. ": shield equipped (wrong for this spec)")
    end

    return issues
end

function GearModule:CheckWeaponStat(specData)
    local issues = {}
    local mhLink = GetInventoryItemLink("player", MAIN_HAND)
    if not mhLink then return issues end

    local _, classID = Util.GetItemType(mhLink)
    if classID ~= 2 then return issues end

    local stats = C_Item.GetItemStats(mhLink)
    if not stats then return issues end

    local hasSTR = (stats["ITEM_MOD_STRENGTH_SHORT"]  or 0) > 0
    local hasAGI = (stats["ITEM_MOD_AGILITY_SHORT"]   or 0) > 0
    local hasINT = (stats["ITEM_MOD_INTELLECT_SHORT"]  or 0) > 0

    if not hasSTR and not hasAGI and not hasINT then return issues end

    local wrong = false
    if specData.stat == "STR" and not hasSTR then wrong = true end
    if specData.stat == "AGI" and not hasAGI then wrong = true end
    if specData.stat == "INT" and not hasINT then wrong = true end

    if wrong then
        table.insert(issues, specData.name .. ": weapon has wrong primary stat (need " .. specData.stat .. ")")
    end

    return issues
end

function GearModule:CheckLowItemLevel(threshold)
    local issues = {}
    for _, slot in ipairs(SLOT_ORDER) do
        local ilvl = Util.GetEquippedItemLevel(slot)
        if ilvl and ilvl > 0 and ilvl < threshold then
            table.insert(issues, SLOT_NAMES[slot] .. ": item level " .. ilvl .. " (below " .. threshold .. ")")
        end
    end
    return issues
end

local function IsEngineeringSkillLine(professionIndex)
    if not professionIndex then return false end
    local _, _, _, _, _, _, skillLine = GetProfessionInfo(professionIndex)
    return skillLine == ENGINEERING_SKILL_LINE
end

-- true / false when the cloak's tooltip is readable, nil when it is not.
local function CloakHasOnUse()
    local data = C_TooltipInfo.GetInventoryItem("player", BACK)
    if not data or not data.lines then return nil end
    local onUseLine = Enum.TooltipDataLineType.ItemSpellTriggerOnUse
    for _, line in ipairs(data.lines) do
        -- Line types are language independent; the localized "Use:" prefix is a fallback for
        -- lines the client does not type as an on-use trigger.
        if line.type == onUseLine then return true end
        local text = Util.SafeString(line.leftText)
        if ITEM_SPELL_TRIGGER_ONUSE and text ~= "" and text:find(ITEM_SPELL_TRIGGER_ONUSE, 1, true) then
            return true
        end
    end
    return false
end

function GearModule:CheckCloakGlider()
    local p1, p2 = GetProfessions()
    if not (IsEngineeringSkillLine(p1) or IsEngineeringSkillLine(p2)) then return nil end
    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(GOBLIN_GLIDER_RECIPE)
    if not (recipeInfo and recipeInfo.learned) then return nil end
    if not GetInventoryItemLink("player", BACK) then return nil end
    if CloakHasOnUse() == false then
        return "Missing cloak glider enchant"
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Durability warning frame (separate anchor from gear alerts)
-- ---------------------------------------------------------------------------

local function GetDurabilityWarnFrame()
    if durabilityWarnFrame then return durabilityWarnFrame end

    durabilityWarnFrame = CreateFrame("Frame", "AndeRemindersDurabilityWarn", UIParent)
    durabilityWarnFrame:SetSize(1200, 70)

    local anchor = AR.anchorFrames and AR.anchorFrames["repair"]
    if anchor then
        durabilityWarnFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        durabilityWarnFrame:SetPoint("TOP", UIParent, "TOP", 0, -380)
    end

    durabilityWarnFrame:SetFrameStrata("MEDIUM")
    durabilityWarnFrame:Hide()

    local label = durabilityWarnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(STANDARD_TEXT_FONT, 48, "")
    label:SetPoint("CENTER", durabilityWarnFrame, "CENTER", 0, 0)
    label:SetText("|cFFFF6600[AR]|r Low Durability \226\128\148 Repair your gear!")
    durabilityWarnFrame.label = label

    return durabilityWarnFrame
end

function GearModule:CheckLowDurability()
    local threshold = ((AR.db and AR.db.gear.durabilityThreshold) or DEFAULT_DURABILITY_PERCENT) / 100
    for slot in pairs(SLOT_NAMES) do
        local current, max = GetInventoryItemDurability(slot)
        if current and max and max > 0 and current / max < threshold then
            return true
        end
    end
    return false
end

function GearModule:RunDurabilityCheck()
    if not AR.db or not AR.db.gear then return end
    if InCombatLockdown() then return end

    if not AR.db.gear.checks.lowDurability then
        -- The option was unticked while the banner was up: take it down.
        if durabilityWarnFrame then durabilityWarnFrame:Hide() end
        return
    end

    local wf = GetDurabilityWarnFrame()
    if self:CheckLowDurability() then
        wf:Show()
    else
        wf:Hide()
    end
end

function GearModule:RunCheck()
    if UnitLevel("player") < GetMaxLevelForPlayerExpansion() then return end
    if not AR.db or not AR.db.gear then return end
    if InCombatLockdown() then
        needsRecheck = true
        return
    end
    needsRecheck = false
    local db = AR.db

    local _, specId = Util.GetSpec()
    if not specId then return end
    local specData = SPEC_DATA[specId]

    local issues = {}

    if db.gear.checks.weaponType and specData then
        for _, v in ipairs(self:CheckWeaponType(specData)) do table.insert(issues, v) end
    end

    if db.gear.checks.weaponStat and specData then
        for _, v in ipairs(self:CheckWeaponStat(specData)) do table.insert(issues, v) end
    end

    if db.gear.checks.lowIlvl then
        for _, v in ipairs(self:CheckLowItemLevel(db.gear.lowIlvlThreshold or 50)) do
            table.insert(issues, v)
        end
    end

    if db.gear.checks.cloakGlider then
        local gliderIssue = self:CheckCloakGlider()
        if gliderIssue then table.insert(issues, gliderIssue) end
    end

    if #issues == 0 then
        gearAlert:Hide()
        return
    end

    local notify = db.gear.notify
    if notify.chat then
        for _, issue in ipairs(issues) do
            Util.Print(issue)
        end
    end
    if notify.screen then
        self:ShowAlert(table.concat(issues, "\n"))
    end
end

local ScheduleCheck = Util.Debounce(2, function()
    GearModule:RunCheck()
    GearModule:RunDurabilityCheck()
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local gearEvents = CreateFrame("Frame")
gearEvents:RegisterEvent("PLAYER_LOGIN")
gearEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
gearEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gearEvents:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")  -- also fires when inspecting others
gearEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
gearEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
gearEvents:RegisterEvent("PLAYER_DEAD")
gearEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
gearEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        gearAlert:Hide()
        if durabilityWarnFrame then durabilityWarnFrame:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        GearModule:RunDurabilityCheck()
        -- Gear swapped mid-fight was not checked; do it now that combat is over.
        if needsRecheck then ScheduleCheck() end
    elseif event == "PLAYER_DEAD" or event == "UPDATE_INVENTORY_DURABILITY" then
        GearModule:RunDurabilityCheck()
    else
        ScheduleCheck()
    end
end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

function GearModule:BuildUI(parent, db)
    local X       = 16
    local ROW_H   = 34
    local CHECK_X = 14

    AR.UI.Title(parent, "Gear Reminders", X, -16)

    AR.UI.NotifyRow(parent, X, -48, db.gear.notify)
    AR.UI.Divider(parent, -80, X - 4)

    local ROWS_TOP = -96

    -- Toggle + label bound to db.gear.checks[key] (onChange runs after a click);
    -- returns the label for chaining.
    local function AddCheck(y, key, text, onChange)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", CHECK_X, y + 4)
        cb:SetChecked(db.gear.checks[key])
        cb:SetScript("OnClick", function(self)
            db.gear.checks[key] = self:GetChecked()
            if onChange then onChange() end
        end)

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        label:SetText(text)
        return label
    end

    local function Stripe(y, i) AR.UI.RowStripe(parent, y + 6, ROW_H, i, X - 4) end
    Stripe(ROWS_TOP, 1);             AddCheck(ROWS_TOP,             "weaponType", "Wrong weapon type for spec (2H / 1H / shield)")
    Stripe(ROWS_TOP - ROW_H, 2);     AddCheck(ROWS_TOP - ROW_H,     "weaponStat", "Wrong main stat on weapon (STR / AGI / INT)")
    Stripe(ROWS_TOP - ROW_H * 2, 1); local lIL = AddCheck(ROWS_TOP - ROW_H * 2, "lowIlvl", "Item level below")

    local ilvlBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    ilvlBox:SetSize(56, 24)
    ilvlBox:SetPoint("LEFT", lIL, "RIGHT", 10, 0)
    ilvlBox:SetAutoFocus(false)
    ilvlBox:SetNumeric(true)
    ilvlBox:SetMaxLetters(4)
    ilvlBox:SetText(tostring(db.gear.lowIlvlThreshold or 50))

    local function SaveThreshold(self)
        local v = tonumber(self:GetText()) or 50
        db.gear.lowIlvlThreshold = v
        self:SetText(tostring(v))  -- an emptied box shows the value that is actually stored
    end
    ilvlBox:SetScript("OnEnterPressed", function(self) SaveThreshold(self) self:ClearFocus() end)
    ilvlBox:SetScript("OnEditFocusLost", SaveThreshold)

    local lILunit = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lILunit:SetPoint("LEFT", ilvlBox, "RIGHT", 8, 0)
    lILunit:SetText("ilvl  (ignores shirt & tabard)")

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", X, ROWS_TOP - ROW_H * 3 - 8)
    note:SetText("Trinket stat checking is not supported: too many trinkets carry no primary stat.")
    note:SetTextColor(1, 1, 1, 0.35)
    note:SetWidth(520)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")

    AR.UI.Divider(parent, ROWS_TOP - ROW_H * 3 - 40, X - 4)

    local DUR_TOP = ROWS_TOP - ROW_H * 3 - 56
    Stripe(DUR_TOP, 1)
    local lDur = AddCheck(DUR_TOP, "lowDurability", "Low durability warning below",
        function() GearModule:RunDurabilityCheck() end)

    local durBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    durBox:SetSize(48, 24)
    durBox:SetPoint("LEFT", lDur, "RIGHT", 10, 0)
    durBox:SetAutoFocus(false)
    durBox:SetNumeric(true)
    durBox:SetMaxLetters(3)
    durBox:SetText(tostring(db.gear.durabilityThreshold or DEFAULT_DURABILITY_PERCENT))

    local function SaveDurability(self)
        local v = tonumber(self:GetText()) or DEFAULT_DURABILITY_PERCENT
        if v < 1 then v = 1 elseif v > 99 then v = 99 end
        db.gear.durabilityThreshold = v
        self:SetText(tostring(v))
        GearModule:RunDurabilityCheck()
    end
    durBox:SetScript("OnEnterPressed", function(self) SaveDurability(self) self:ClearFocus() end)
    durBox:SetScript("OnEditFocusLost", SaveDurability)

    local lDurUnit = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lDurUnit:SetPoint("LEFT", durBox, "RIGHT", 8, 0)
    lDurUnit:SetText("%  (persists until repaired)")

    Stripe(DUR_TOP - ROW_H, 2)
    AddCheck(DUR_TOP - ROW_H, "cloakGlider", "Missing Goblin Glider cloak tinker (Engineering)")
end

AR:RegisterModule("Gear", GearModule)
