local AR = AndeReminders

-- Slots that can receive enchants (mirrors NorthernSkyRaidTools logic)
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

local EnchantModule = {}
local checkTimer    = nil   -- debounce handle
local alertFrame    = nil   -- on-screen alert, created lazily

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function EnchantModule:InitDB(db)
    if not db.enchants then
        db.enchants = { slots = {}, notify = {} }
    end
    if not db.enchants.notify then
        db.enchants.notify = {}
    end
    -- Notification defaults
    if db.enchants.notify.chat   == nil then db.enchants.notify.chat   = true  end
    if db.enchants.notify.screen == nil then db.enchants.notify.screen = true  end
    -- Global ilvl override
    if not db.enchants.globalIlvl then
        db.enchants.globalIlvl = { enabled = true, value = 250 }
    end
    -- Per-slot defaults
    if not db.enchants.slots then
        db.enchants.slots = {}
    end
    for _, slot in ipairs(ENCHANTABLE_SLOTS) do
        if not db.enchants.slots[slot.id] then
            db.enchants.slots[slot.id] = { enabled = true, minIlvl = 250 }
        end
    end
end

-- ---------------------------------------------------------------------------
-- On-screen alert frame
-- ---------------------------------------------------------------------------

local function GetAlertFrame()
    if alertFrame then return alertFrame end

    alertFrame = CreateFrame("Frame", "AndeRemindersEnchantAlert", UIParent, "BackdropTemplate")
    alertFrame:SetSize(360, 80)
    alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -220)
    alertFrame:SetMovable(true)
    alertFrame:EnableMouse(true)
    alertFrame:RegisterForDrag("LeftButton")
    alertFrame:SetScript("OnDragStart", alertFrame.StartMoving)
    alertFrame:SetScript("OnDragStop", alertFrame.StopMovingOrSizing)
    alertFrame:SetFrameStrata("MEDIUM")
    alertFrame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        tile = true, tileSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    alertFrame:Hide()

    -- Header
    local header = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 10, -10)
    header:SetText("|cFFFF6600AR|r")
    alertFrame.header = header

    -- Body text (slot list)
    local body = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetPoint("TOPLEFT",  alertFrame, "TOPLEFT",  10, -26)
    body:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -10, -26)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    alertFrame.body = body

    -- Close button
    local closeBtn = CreateFrame("Button", nil, alertFrame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        alertFrame:Hide()
    end)

    return alertFrame
end

function EnchantModule:ShowAlert(text)
    local af = GetAlertFrame()

    af.body:SetText(text)
    -- Resize frame to fit the text
    af:SetHeight(af.body:GetHeight() + 44)

    af:Show()
end

-- ---------------------------------------------------------------------------
-- Check logic
-- ---------------------------------------------------------------------------

-- Returns true if the given slot has an item but is missing an enchant.
-- Adapted from NorthernSkyRaidTools ReadyCheck.lua (EnchantCheck).
function EnchantModule:CheckSlot(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return false end  -- nothing equipped

    -- Off-hand: skip enchant check for shields (armor classId == 4)
    if slotId == 17 then
        local _, _, _, _, _, _, _, _, _, _, _, classId = GetItemInfo(link)
        if classId == 4 then return false end
    end

    -- Item link format: item:ITEMID:ENCHANTID:...
    local _, enchantStr = link:match("item:(%d+):(%d+)")
    local enchantId = tonumber(enchantStr) or 0
    return enchantId == 0  -- true = enchant is missing
end

-- Returns the effective item level of an equipped item (0 if empty/uncached).
function EnchantModule:GetSlotItemLevel(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return 0 end
    local name, _, _, itemLevel = GetItemInfo(link)
    if not name then return 0 end
    return itemLevel or 0
end

-- Returns a list of slot names that are missing enchants, respecting per-slot settings.
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

-- Run the check and dispatch notifications.
function EnchantModule:RunCheck()
    if UnitLevel("player") < 90 then return end
    if not AR.db then return end
    local missing = self:CheckAll(AR.db)
    if #missing == 0 then
        if alertFrame and alertFrame:IsShown() then alertFrame:Hide() end
        return
    end

    local notify = AR.db.enchants.notify
    local slots  = table.concat(missing, ", ")

    if notify.chat then
        print("|cFFFF6600[AndeReminders]|r Missing enchant: " .. slots)
    end
    if notify.screen then
        self:ShowAlert("|cFFFFCC00Missing enchant:|r\n" .. slots)
    end
end

-- Schedule a check with a short debounce so rapid events (login gear loading,
-- multiple swaps) collapse into a single pass.
local function ScheduleCheck()
    if checkTimer then
        checkTimer:Cancel()
    end
    checkTimer = C_Timer.NewTimer(2, function()
        checkTimer = nil
        EnchantModule:RunCheck()
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local enchantEvents = CreateFrame("Frame")
enchantEvents:RegisterEvent("PLAYER_LOGIN")
enchantEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
enchantEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
enchantEvents:SetScript("OnEvent", function(_, event)
    ScheduleCheck()
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

    -- Section title
    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Enchant Reminders")
    sectionTitle:SetTextColor(1, 0.82, 0)

    -- ---- Notification options ----
    local notifyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notifyLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -36)
    notifyLabel:SetText("Notify via:")
    notifyLabel:SetTextColor(0.7, 0.7, 0.7)

    -- Chat checkbox
    local cbChat = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbChat:SetSize(22, 22)
    cbChat:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 60, -33)
    cbChat:SetChecked(db.enchants.notify.chat)
    cbChat:SetScript("OnClick", function(self)
        db.enchants.notify.chat = self:GetChecked()
    end)

    local cbChatLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbChatLabel:SetPoint("LEFT", cbChat, "RIGHT", 2, 0)
    cbChatLabel:SetText("Chat")

    -- Screen checkbox
    local cbScreen = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbScreen:SetSize(22, 22)
    cbScreen:SetPoint("LEFT", cbChatLabel, "RIGHT", 16, 0)
    cbScreen:SetChecked(db.enchants.notify.screen)
    cbScreen:SetScript("OnClick", function(self)
        db.enchants.notify.screen = self:GetChecked()
    end)

    local cbScreenLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbScreenLabel:SetPoint("LEFT", cbScreen, "RIGHT", 2, 0)
    cbScreenLabel:SetText("On-screen")

    -- Global iLvl checkbox
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
        db.enchants.globalIlvl.value = tonumber(self:GetText()) or 0
    end
    globalIlvlInput:SetScript("OnEnterPressed", function(self)
        SaveGlobalIlvl(self)
        self:ClearFocus()
    end)
    globalIlvlInput:SetScript("OnEditFocusLost", SaveGlobalIlvl)

    -- Divider between notify options and slot list
    local notifyDiv = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    notifyDiv:SetHeight(1)
    notifyDiv:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    notifyDiv:SetBackdropColor(0.28, 0.28, 0.28, 1)
    notifyDiv:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, -60)
    notifyDiv:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -60)

    -- ---- Column headers ----
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

    -- Divider below column headers
    local colDiv = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colDiv:SetHeight(1)
    colDiv:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    colDiv:SetBackdropColor(0.28, 0.28, 0.28, 1)
    colDiv:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, HEADER_TOP - 14)
    colDiv:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, HEADER_TOP - 14)

    -- ---- Slot rows ----
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
        cb:SetScript("OnClick", function(self)
            slotData.enabled = self:GetChecked()
        end)

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
            slotData.minIlvl = tonumber(self:GetText()) or 0
        end
        editBox:SetScript("OnEnterPressed", function(self)
            SaveValue(self)
            self:ClearFocus()
        end)
        editBox:SetScript("OnEditFocusLost", SaveValue)

        table.insert(slotEditBoxes, editBox)
    end

    -- ---- Global iLvl enable/disable wiring ----
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
