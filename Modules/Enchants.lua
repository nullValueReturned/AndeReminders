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

-- Every slot that can carry gem sockets, in report order.
local GEM_SLOTS = {
    { id = 1,  name = "Head"      }, { id = 2,  name = "Neck"      }, { id = 3,  name = "Shoulder"  },
    { id = 5,  name = "Chest"     }, { id = 6,  name = "Waist"     }, { id = 7,  name = "Legs"      },
    { id = 8,  name = "Feet"      }, { id = 9,  name = "Wrist"     }, { id = 10, name = "Hands"     },
    { id = 11, name = "Finger 1"  }, { id = 12, name = "Finger 2"  }, { id = 13, name = "Trinket 1" },
    { id = 14, name = "Trinket 2" }, { id = 15, name = "Back"      }, { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand"  },
}
local GEM_SLOT_NAME = {}
for _, slot in ipairs(GEM_SLOTS) do GEM_SLOT_NAME[slot.id] = slot.name end

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
    if db.enchants.gems == nil then db.enchants.gems = true end
    if not db.enchants.gemIgnored then db.enchants.gemIgnored = {} end
    if not db.enchants.slots then db.enchants.slots = {} end
    for _, slot in ipairs(ENCHANTABLE_SLOTS) do
        if not db.enchants.slots[slot.id] then
            db.enchants.slots[slot.id] = { enabled = true, minIlvl = 250 }
        end
    end
end

function EnchantModule:ShowAlert(text, items)
    enchantAlert:Show(text, items)
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

-- total sockets, socketed gems for an item link; nil while the item data is not available.
-- The gem fields are blanked before asking for the item stats: the stats of a gemmed link
-- depend on the gems being cached, which is not the case right after a reload, so a fully
-- gemmed item could read as having only empty sockets. The gems actually in the item are read
-- straight from the link (fields 4-7: itemID:enchant:gem1:gem2:gem3:gem4).
local function GetSocketInfo(link)
    local itemString = link:match("item:[^|]*")
    if not itemString then return nil end
    local fields = { strsplit(":", itemString) }
    if #fields < 7 then return nil end

    local filled = 0
    for i = 4, 7 do
        if (tonumber(fields[i]) or 0) > 0 then filled = filled + 1 end
        fields[i] = ""
    end

    local stats = C_Item.GetItemStats(table.concat(fields, ":"))
    if not stats then return nil end
    local total = 0
    for key, count in pairs(stats) do
        if type(key) == "string" and key:find("^EMPTY_SOCKET_") then total = total + count end
    end
    return total, filled
end

-- Slot ids (in report order) holding an item with at least one empty socket.
function EnchantModule:CheckGems(db)
    local empty = {}
    for _, slot in ipairs(GEM_SLOTS) do
        if not db.enchants.gemIgnored[slot.id] then
            local link = GetInventoryItemLink("player", slot.id)
            local total, filled = nil, nil
            if link then total, filled = GetSocketInfo(link) end
            if total and total > filled then
                table.insert(empty, slot.id)
            end
        end
    end
    return empty
end

-- /ar gems: what the gem check sees on each slot, for diagnosing wrong results.
function EnchantModule:DebugGems()
    for _, slot in ipairs(GEM_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local total, filled = GetSocketInfo(link)
            Util.Print(slot.name .. ": sockets " .. tostring(total) .. ", gems " .. tostring(filled))
        end
    end
end

-- silent: skip the chat line (used when re-checking right after an Ignore click).
function EnchantModule:RunCheck(silent)
    if UnitLevel("player") < GetMaxLevelForPlayerExpansion() then return end
    if not AR.db then return end
    if InCombatLockdown() then
        needsRecheck = true
        return
    end
    needsRecheck = false
    local db = AR.db
    local missing = self:CheckAll(db)
    local gems    = db.enchants.gems and self:CheckGems(db) or {}
    if #missing == 0 and #gems == 0 then
        enchantAlert:Reset()
        return
    end

    local notify = db.enchants.notify

    if notify.chat and not silent then
        if #missing > 0 then Util.Print("Missing enchant: " .. table.concat(missing, ", ")) end
        if #gems > 0 then
            local names = {}
            for _, id in ipairs(gems) do table.insert(names, GEM_SLOT_NAME[id]) end
            Util.Print("Empty gem socket: " .. table.concat(names, ", "))
        end
    end

    if notify.screen then
        local items = {}
        -- Ignoring an enchant slot unticks it in the settings table; a gem slot goes on the
        -- ignore list shown next to the gem checkbox.
        for _, slot in ipairs(ENCHANTABLE_SLOTS) do
            for _, name in ipairs(missing) do
                if name == slot.name then
                    table.insert(items, {
                        text = "|cFFFFCC00" .. slot.name .. "|r  missing enchant",
                        onIgnore = function()
                            db.enchants.slots[slot.id].enabled = false
                            self:RunCheck(true)
                        end,
                    })
                end
            end
        end
        for _, id in ipairs(gems) do
            table.insert(items, {
                text = "|cFFFFCC00" .. GEM_SLOT_NAME[id] .. "|r  empty gem socket",
                onIgnore = function()
                    db.enchants.gemIgnored[id] = true
                    self:RunCheck(true)
                end,
            })
        end
        self:ShowAlert("", items)
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

local CreateFrame = AR.UI.CreateFrame

function EnchantModule:BuildUI(parent, db)
    local COL_NAME_X  = 16
    local COL_CHECK_X = 185
    local COL_LABEL_X = 236
    local ROW_HEIGHT  = 30

    AR.UI.Title(parent, "Enchant & Gem Reminders", COL_NAME_X, -16)

    AR.UI.NotifyRow(parent, COL_NAME_X, -48, db.enchants.notify)

    -- Gem sockets (the per-slot table below only covers enchants).
    local cbGems = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbGems:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, -78)
    cbGems:SetChecked(db.enchants.gems)
    cbGems:SetScript("OnClick", function(self)
        db.enchants.gems = self:GetChecked()
        EnchantModule:RunCheck(true)
    end)

    local cbGemsLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbGemsLabel:SetPoint("LEFT", cbGems, "RIGHT", 6, 0)
    cbGemsLabel:SetText("Also warn about empty gem sockets")

    local gemIgnoredText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gemIgnoredText:SetPoint("LEFT", cbGemsLabel, "RIGHT", 16, 0)

    local gemClear = AR.UI.Button(parent, "Clear ignored", 96, 20)
    gemClear:SetPoint("LEFT", gemIgnoredText, "RIGHT", 10, 0)
    gemClear:SetScript("OnClick", function()
        wipe(db.enchants.gemIgnored)
        parent:GetScript("OnShow")()
        EnchantModule:RunCheck(true)
    end)

    local hThreshold = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hThreshold:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -120)
    hThreshold:SetText("ITEM LEVEL")

    local cbGlobalIlvl = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbGlobalIlvl:SetPoint("LEFT", hThreshold, "RIGHT", 12, 0)
    cbGlobalIlvl:SetChecked(db.enchants.globalIlvl.enabled)

    local cbGlobalIlvlLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbGlobalIlvlLabel:SetPoint("LEFT", cbGlobalIlvl, "RIGHT", 2, 0)
    cbGlobalIlvlLabel:SetText("Use one minimum for all slots:")

    local globalIlvlInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    globalIlvlInput:SetSize(58, 24)
    globalIlvlInput:SetPoint("LEFT", cbGlobalIlvlLabel, "RIGHT", 8, 0)
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

    AR.UI.Divider(parent, -152, COL_NAME_X - 4)

    local HEADER_TOP = -164

    local hSlot = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSlot:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, HEADER_TOP)
    hSlot:SetText("SLOT")

    local hRemind = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRemind:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_CHECK_X + 2, HEADER_TOP)
    hRemind:SetText("REMIND")

    local hIlvl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIlvl:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_LABEL_X, HEADER_TOP)
    hIlvl:SetText("MIN ITEM LEVEL (PER SLOT)")

    local SLOTS_TOP = HEADER_TOP - 22
    local slotEditBoxes = {}
    local slotChecks    = {}

    for i, slot in ipairs(ENCHANTABLE_SLOTS) do
        local slotData = db.enchants.slots[slot.id]
        local y = SLOTS_TOP - (i - 1) * ROW_HEIGHT

        AR.UI.RowStripe(parent, y + 5, ROW_HEIGHT, i, COL_NAME_X - 4)

        local nameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 4, y - 1)
        nameLabel:SetText(slot.name)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_CHECK_X, y + 4)
        cb:SetChecked(slotData.enabled)
        cb:SetScript("OnClick", function(self) slotData.enabled = self:GetChecked() end)
        slotChecks[slot.id] = cb

        local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editBox:SetSize(64, 24)
        editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_LABEL_X, y + 2)
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

    -- Slots can be switched off from the alert's Ignore button while this tab is already built.
    parent:SetScript("OnShow", function()
        for _, slot in ipairs(ENCHANTABLE_SLOTS) do
            slotChecks[slot.id]:SetChecked(db.enchants.slots[slot.id].enabled)
        end
        local names = {}
        for _, gslot in ipairs(GEM_SLOTS) do
            if db.enchants.gemIgnored[gslot.id] then table.insert(names, gslot.name) end
        end
        gemIgnoredText:SetText(#names > 0 and ("Ignored: " .. table.concat(names, ", ")) or "")
        gemClear:SetShown(#names > 0)
    end)
    parent:GetScript("OnShow")()
end

AR:RegisterModule("Enchants & Gems", EnchantModule)
