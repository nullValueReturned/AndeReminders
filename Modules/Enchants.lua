local AR   = AndeReminders
local Util = AR.Util

local ENCHANTABLE_SLOTS = {
    { id = 1,  name = "Head"      },
    { id = 3,  name = "Shoulder"  },
    { id = 5,  name = "Chest"     },
    { id = 7,  name = "Legs"      },
    { id = 8,  name = "Feet"      },
    { id = 11, name = "Finger 1"  },
    { id = 12, name = "Finger 2"  },
    { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand"  },
}

local OFF_HAND    = 17
local ARMOR_CLASS = 4  -- shields and held-in-off-hand items cannot be enchanted

local EnchantModule = {}
local needsRecheck = false  -- a scheduled check was skipped because the player was in combat

local enchantAlert = AR.UI.CreateAlert({
    name = "AndeRemindersEnchantAlert", anchor = "enchants", width = 360, fallbackY = -220,
})

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function EnchantModule:InitDB(db)
    if not db.enchants then
        db.enchants = { slots = {}, notify = {} }
    end
    if not db.enchants.notify then db.enchants.notify = {} end
    if db.enchants.notify.chat   == nil then db.enchants.notify.chat   = true  end
    if db.enchants.notify.screen == nil then db.enchants.notify.screen = true  end
    if not db.enchants.globalIlvl then
        db.enchants.globalIlvl = { enabled = true, value = 250 }
    end
    if not db.enchants.slots then db.enchants.slots = {} end
    for _, slot in ipairs(ENCHANTABLE_SLOTS) do
        if not db.enchants.slots[slot.id] then
            db.enchants.slots[slot.id] = { enabled = true, minIlvl = 250 }
        end
    end
end

function EnchantModule:ShowAlert(text)
    enchantAlert:Show(text)
end

-- ---------------------------------------------------------------------------
-- Check logic
-- ---------------------------------------------------------------------------

function EnchantModule:CheckSlot(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return false end

    if slotId == OFF_HAND then
        local _, classID = Util.GetItemType(link)
        if classID == ARMOR_CLASS then return false end
    end

    return Util.GetLinkEnchantID(link) == 0
end

function EnchantModule:GetSlotItemLevel(slotId)
    return Util.GetEquippedItemLevel(slotId) or 0
end

function EnchantModule:CheckAll(db)
    local missing = {}
    local globalIlvl = db.enchants.globalIlvl
    for _, slot in ipairs(ENCHANTABLE_SLOTS) do
        local slotData = db.enchants.slots[slot.id]
        if slotData and slotData.enabled then
            local minIlvl = (globalIlvl and globalIlvl.enabled)
                and (globalIlvl.value or 0)
                or  (slotData.minIlvl or 0)
            local ilvl = self:GetSlotItemLevel(slot.id)
            if ilvl >= minIlvl then
                if self:CheckSlot(slot.id) then
                    table.insert(missing, slot.name)
                end
            end
        end
    end
    return missing
end

function EnchantModule:RunCheck()
    if UnitLevel("player") < GetMaxLevelForPlayerExpansion() then return end
    if not AR.db then return end
    if InCombatLockdown() then
        needsRecheck = true
        return
    end
    needsRecheck = false
    local missing = self:CheckAll(AR.db)
    if #missing == 0 then
        enchantAlert:Hide()
        return
    end

    local notify = AR.db.enchants.notify
    local slots  = table.concat(missing, ", ")

    if notify.chat then
        Util.Print("Missing enchant: " .. slots)
    end
    if notify.screen then
        self:ShowAlert("|cFFFFCC00Missing enchant:|r\n" .. slots)
    end
end

local ScheduleCheck = Util.Debounce(2, function()
    EnchantModule:RunCheck()
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local enchantEvents = CreateFrame("Frame")
enchantEvents:RegisterEvent("PLAYER_LOGIN")
enchantEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
enchantEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
enchantEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
enchantEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
enchantEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        enchantAlert:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Gear swapped mid-fight was not checked; do it now that combat is over.
        if needsRecheck then ScheduleCheck() end
    else
        ScheduleCheck()
    end
end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function EnchantModule:BuildUI(parent, db)
    local COL_NAME_X  = 12
    local COL_CHECK_X = 185
    local COL_LABEL_X = 230
    local COL_INPUT_X = 305
    local ROW_HEIGHT  = 28

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Enchant Reminders")
    sectionTitle:SetTextColor(1, 0.82, 0)

    local cbScreenLabel = AR.UI.NotifyRow(parent, COL_NAME_X, -36, db.enchants.notify)

    local cbGlobalIlvl = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbGlobalIlvl:SetSize(22, 22)
    cbGlobalIlvl:SetPoint("LEFT", cbScreenLabel, "RIGHT", 16, 0)
    cbGlobalIlvl:SetChecked(db.enchants.globalIlvl.enabled)

    local cbGlobalIlvlLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbGlobalIlvlLabel:SetPoint("LEFT", cbGlobalIlvl, "RIGHT", 2, 0)
    cbGlobalIlvlLabel:SetText("Global iLvl:")

    local globalIlvlInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    globalIlvlInput:SetSize(58, 20)
    globalIlvlInput:SetPoint("LEFT", cbGlobalIlvlLabel, "RIGHT", 4, -1)
    globalIlvlInput:SetAutoFocus(false)
    globalIlvlInput:SetNumeric(true)
    globalIlvlInput:SetMaxLetters(4)
    globalIlvlInput:SetText(tostring(db.enchants.globalIlvl.value or 250))

    local function SaveGlobalIlvl(self)
        local v = tonumber(self:GetText()) or 0
        db.enchants.globalIlvl.value = v
        self:SetText(tostring(v))  -- an emptied box shows the value that is actually stored
    end
    globalIlvlInput:SetScript("OnEnterPressed", function(self) SaveGlobalIlvl(self) self:ClearFocus() end)
    globalIlvlInput:SetScript("OnEditFocusLost", SaveGlobalIlvl)

    AR.UI.Divider(parent, -60)

    local HEADER_TOP = -68

    local hSlot = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSlot:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, HEADER_TOP)
    hSlot:SetText("Slot")
    hSlot:SetTextColor(0.6, 0.6, 0.6)

    local hRemind = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRemind:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_CHECK_X - 8, HEADER_TOP)
    hRemind:SetText("Remind")
    hRemind:SetTextColor(0.6, 0.6, 0.6)

    local hIlvl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_LABEL_X, HEADER_TOP)
    hIlvl:SetText("Min iLvl")
    hIlvl:SetTextColor(0.6, 0.6, 0.6)

    AR.UI.Divider(parent, HEADER_TOP - 14)

    local SLOTS_TOP = HEADER_TOP - 20
    local slotEditBoxes = {}

    for i, slot in ipairs(ENCHANTABLE_SLOTS) do
        local slotData = db.enchants.slots[slot.id]
        local y = SLOTS_TOP - (i - 1) * ROW_HEIGHT

        local nameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
        nameLabel:SetText(slot.name)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_CHECK_X, y + 3)
        cb:SetChecked(slotData.enabled)
        cb:SetScript("OnClick", function(self) slotData.enabled = self:GetChecked() end)

        local ilvlLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ilvlLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_LABEL_X, y)
        ilvlLabel:SetText("Min iLvl:")

        local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editBox:SetSize(58, 20)
        editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_INPUT_X, y + 3)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(4)
        editBox:SetText(tostring(slotData.minIlvl or 0))

        local function SaveValue(self)
            local v = tonumber(self:GetText()) or 0
            slotData.minIlvl = v
            self:SetText(tostring(v))
        end
        editBox:SetScript("OnEnterPressed", function(self) SaveValue(self) self:ClearFocus() end)
        editBox:SetScript("OnEditFocusLost", SaveValue)

        table.insert(slotEditBoxes, editBox)
    end

    local function UpdateGlobalIlvlState()
        local enabled = db.enchants.globalIlvl.enabled
        globalIlvlInput:SetEnabled(enabled)
        globalIlvlInput:SetAlpha(enabled and 1 or 0.4)
        for _, eb in ipairs(slotEditBoxes) do
            eb:SetEnabled(not enabled)
            eb:SetAlpha(enabled and 0.4 or 1)
        end
    end

    cbGlobalIlvl:SetScript("OnClick", function(self)
        db.enchants.globalIlvl.enabled = self:GetChecked()
        UpdateGlobalIlvlState()
    end)

    UpdateGlobalIlvlState()
end

AR:RegisterModule("Enchants", EnchantModule)
