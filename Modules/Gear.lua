local AR = AndeReminders

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

local IS_2H = {
    [1]  = true,  -- Axe (2H)
    [5]  = true,  -- Mace (2H)
    [6]  = true,  -- Polearm
    [8]  = true,  -- Sword (2H)
    [10] = true,  -- Staff
    [2]  = true,  -- Bow
    [3]  = true,  -- Gun
    [18] = true,  -- Crossbow
}

local SLOT_NAMES = {
    [1]  = "Head",     [2]  = "Neck",      [3]  = "Shoulder",
    [5]  = "Chest",    [6]  = "Waist",     [7]  = "Legs",
    [8]  = "Feet",     [9]  = "Wrist",     [10] = "Hands",
    [11] = "Finger 1", [12] = "Finger 2",  [13] = "Trinket 1",
    [14] = "Trinket 2",[15] = "Back",      [16] = "Main Hand",
    [17] = "Off Hand",
}

local GearModule = {}
local checkTimer = nil
local alertFrame = nil
local durabilityWarnFrame = nil

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
    if db.gear.lowIlvlThreshold     == nil then db.gear.lowIlvlThreshold     = 50   end
end

-- ---------------------------------------------------------------------------
-- Gear alert frame (weapon / stat / ilvl issues)
-- ---------------------------------------------------------------------------

local function GetAlertFrame()
    if alertFrame then return alertFrame end

    alertFrame = CreateFrame("Frame", "AndeRemindersGearAlert", UIParent, "BackdropTemplate")
    alertFrame:SetSize(380, 80)

    local anchor = AR.anchorFrames and AR.anchorFrames["gear"]
    if anchor then
        alertFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -300)
    end

    alertFrame:EnableMouse(true)
    alertFrame:SetFrameStrata("MEDIUM")
    alertFrame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        tile = true, tileSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    alertFrame:Hide()

    local header = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 10, -10)
    header:SetText("|cFFFF6600AR|r")
    alertFrame.header = header

    local body = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetPoint("TOPLEFT",  alertFrame, "TOPLEFT",  10, -26)
    body:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -10, -26)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    alertFrame.body = body

    local closeBtn = CreateFrame("Button", nil, alertFrame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() alertFrame:Hide() end)

    return alertFrame
end

function GearModule:ShowAlert(text)
    local af = GetAlertFrame()
    af.body:SetText(text)
    af:SetHeight(af.body:GetHeight() + 44)
    af:Show()
end

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------

function GearModule:CheckWeaponType(specData)
    local issues = {}
    local mhLink = GetInventoryItemLink("player", 16)
    local ohLink = GetInventoryItemLink("player", 17)

    if specData.require2H and mhLink then
        local _, _, _, _, _, _, _, _, _, _, _, classId, subClassId = GetItemInfo(mhLink)
        if classId == 2 and not IS_2H[subClassId] then
            table.insert(issues, specData.name .. ": main hand should be a 2-handed weapon")
        end
    end

    if specData.requireShield then
        local hasShield = false
        if ohLink then
            local _, _, _, _, _, _, _, _, _, _, _, classId, subClassId = GetItemInfo(ohLink)
            hasShield = (classId == 4 and subClassId == 6)
        end
        if not hasShield then
            table.insert(issues, specData.name .. ": off-hand should be a shield")
        end
    end

    if specData.forbidShield and ohLink then
        local _, _, _, _, _, _, _, _, _, _, _, classId, subClassId = GetItemInfo(ohLink)
        if classId == 4 and subClassId == 6 then
            table.insert(issues, specData.name .. ": shield equipped (wrong for this spec)")
        end
    end

    return issues
end

function GearModule:CheckWeaponStat(specData)
    local issues = {}
    local mhLink = GetInventoryItemLink("player", 16)
    if not mhLink then return issues end

    local _, _, _, _, _, _, _, _, _, _, _, classId = GetItemInfo(mhLink)
    if classId ~= 2 then return issues end

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
    for slot, slotName in pairs(SLOT_NAMES) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local name, _, _, ilvl = GetItemInfo(link)
            if name and ilvl and ilvl > 0 and ilvl < threshold then
                table.insert(issues, slotName .. ": item level " .. ilvl .. " (below " .. threshold .. ")")
            end
        end
    end
    return issues
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
    label:SetFont(label:GetFont(), 48)
    label:SetPoint("CENTER", durabilityWarnFrame, "CENTER", 0, 0)
    label:SetText("|cFFFF6600[AR]|r Low Durability \226\128\148 Repair your gear!")
    durabilityWarnFrame.label = label

    return durabilityWarnFrame
end

function GearModule:CheckLowDurability()
    for slot in pairs(SLOT_NAMES) do
        local current, max = GetInventoryItemDurability(slot)
        if current and max and max > 0 and current / max < 0.5 then
            return true
        end
    end
    return false
end

function GearModule:RunDurabilityCheck()
    if not AR.db or not AR.db.gear then return end
    if not AR.db.gear.checks.lowDurability then return end
    if InCombatLockdown() then return end

    local wf = GetDurabilityWarnFrame()
    if self:CheckLowDurability() then
        wf:Show()
    else
        wf:Hide()
    end
end

function GearModule:RunCheck()
    if UnitLevel("player") < 90 then return end
    if not AR.db or not AR.db.gear then return end
    local db = AR.db

    local specIndex = GetSpecialization()
    if not specIndex then return end
    local specId = select(1, GetSpecializationInfo(specIndex))
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

    if #issues == 0 then
        if alertFrame and alertFrame:IsShown() then alertFrame:Hide() end
        return
    end

    local notify = db.gear.notify
    if notify.chat then
        for _, issue in ipairs(issues) do
            print("|cFFFF6600[AndeReminders]|r " .. issue)
        end
    end
    if notify.screen then
        self:ShowAlert(table.concat(issues, "\n"))
    end
end

local function ScheduleCheck()
    if checkTimer then checkTimer:Cancel() end
    checkTimer = C_Timer.NewTimer(2, function()
        checkTimer = nil
        GearModule:RunCheck()
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local gearEvents = CreateFrame("Frame")
gearEvents:RegisterEvent("PLAYER_LOGIN")
gearEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
gearEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gearEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
gearEvents:SetScript("OnEvent", function() ScheduleCheck() end)

local durabilityEvents = CreateFrame("Frame")
durabilityEvents:RegisterEvent("PLAYER_DEAD")
durabilityEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
durabilityEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
durabilityEvents:SetScript("OnEvent", function() GearModule:RunDurabilityCheck() end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function GearModule:BuildUI(parent, db)
    local X       = 12
    local ROW_H   = 28
    local CHECK_X = 12
    local LABEL_X = 40

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", X, -10)
    title:SetText("Gear Reminders")
    title:SetTextColor(1, 0.82, 0)

    local notifyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notifyLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", X, -36)
    notifyLabel:SetText("Notify via:")
    notifyLabel:SetTextColor(0.7, 0.7, 0.7)

    local cbChat = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbChat:SetSize(22, 22)
    cbChat:SetPoint("TOPLEFT", parent, "TOPLEFT", X + 60, -33)
    cbChat:SetChecked(db.gear.notify.chat)
    cbChat:SetScript("OnClick", function(self) db.gear.notify.chat = self:GetChecked() end)

    local cbChatLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbChatLabel:SetPoint("LEFT", cbChat, "RIGHT", 2, 0)
    cbChatLabel:SetText("Chat")

    local cbScreen = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbScreen:SetSize(22, 22)
    cbScreen:SetPoint("LEFT", cbChatLabel, "RIGHT", 16, 0)
    cbScreen:SetChecked(db.gear.notify.screen)
    cbScreen:SetScript("OnClick", function(self) db.gear.notify.screen = self:GetChecked() end)

    local cbScreenLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbScreenLabel:SetPoint("LEFT", cbScreen, "RIGHT", 2, 0)
    cbScreenLabel:SetText("On-screen")

    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, -60)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -60)

    local ROWS_TOP = -70

    local cbWT = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbWT:SetSize(22, 22)
    cbWT:SetPoint("TOPLEFT", parent, "TOPLEFT", CHECK_X, ROWS_TOP)
    cbWT:SetChecked(db.gear.checks.weaponType)
    cbWT:SetScript("OnClick", function(self) db.gear.checks.weaponType = self:GetChecked() end)

    local lWT = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lWT:SetPoint("LEFT", cbWT, "RIGHT", 6, 0)
    lWT:SetText("Wrong weapon type for spec (2H / 1H / shield)")

    local cbWS = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbWS:SetSize(22, 22)
    cbWS:SetPoint("TOPLEFT", parent, "TOPLEFT", CHECK_X, ROWS_TOP - ROW_H)
    cbWS:SetChecked(db.gear.checks.weaponStat)
    cbWS:SetScript("OnClick", function(self) db.gear.checks.weaponStat = self:GetChecked() end)

    local lWS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lWS:SetPoint("LEFT", cbWS, "RIGHT", 6, 0)
    lWS:SetText("Wrong main stat on weapon (STR / AGI / INT)")

    local cbIL = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbIL:SetSize(22, 22)
    cbIL:SetPoint("TOPLEFT", parent, "TOPLEFT", CHECK_X, ROWS_TOP - ROW_H * 2)
    cbIL:SetChecked(db.gear.checks.lowIlvl)
    cbIL:SetScript("OnClick", function(self) db.gear.checks.lowIlvl = self:GetChecked() end)

    local lIL = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lIL:SetPoint("LEFT", cbIL, "RIGHT", 6, 0)
    lIL:SetText("Item level below")

    local ilvlBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    ilvlBox:SetSize(52, 20)
    ilvlBox:SetPoint("LEFT", lIL, "RIGHT", 8, 0)
    ilvlBox:SetAutoFocus(false)
    ilvlBox:SetNumeric(true)
    ilvlBox:SetMaxLetters(4)
    ilvlBox:SetText(tostring(db.gear.lowIlvlThreshold or 50))

    local function SaveThreshold(self)
        db.gear.lowIlvlThreshold = tonumber(self:GetText()) or 50
    end
    ilvlBox:SetScript("OnEnterPressed", function(self) SaveThreshold(self) self:ClearFocus() end)
    ilvlBox:SetScript("OnEditFocusLost", SaveThreshold)

    local lILunit = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lILunit:SetPoint("LEFT", ilvlBox, "RIGHT", 4, 0)
    lILunit:SetText("ilvl  (ignores shirt & tabard)")
    lILunit:SetTextColor(0.65, 0.65, 0.65)

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", X, ROWS_TOP - ROW_H * 3 - 10)
    note:SetText("Note: trinket stat checking is not supported — too many trinkets carry no primary stat.")
    note:SetTextColor(0.45, 0.45, 0.45)
    note:SetWidth(450)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")

    local div2 = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div2:SetHeight(1)
    div2:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div2:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div2:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, ROWS_TOP - ROW_H * 3 - 54)
    div2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, ROWS_TOP - ROW_H * 3 - 54)

    local cbDur = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbDur:SetSize(22, 22)
    cbDur:SetPoint("TOPLEFT", parent, "TOPLEFT", CHECK_X, ROWS_TOP - ROW_H * 3 - 68)
    cbDur:SetChecked(db.gear.checks.lowDurability)
    cbDur:SetScript("OnClick", function(self) db.gear.checks.lowDurability = self:GetChecked() end)

    local lDur = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lDur:SetPoint("LEFT", cbDur, "RIGHT", 6, 0)
    lDur:SetText("Low durability warning (<50%, persists until repaired)")
end

AR:RegisterModule("Gear", GearModule)
