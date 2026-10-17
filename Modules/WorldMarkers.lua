local AR                   = AndeReminders
local Util                 = AR.Util

local WorldMarkersModule   = {}
local TargetMarkersModule  = {}

-- World marker placement is a protected action (requires a hardware event),
-- so the real placement has to run through a SecureActionButtonTemplate with
-- a macro attribute. Everything else (the keybind capture UI, storage) is
-- plain insecure Lua that just points a physical key at these buttons.
local BUTTON_PREFIX        = "AndeRemindersWM"
local CLEAR_BUTTON_NAME    = "AndeRemindersWMClear"

-- Target markers (raid target icons) use the same approach: secure buttons that
-- run "/tm N" on the current target, bound to physical keys.
local TM_BUTTON_PREFIX     = "AndeRemindersTM"
local TM_CLEAR_BUTTON_NAME = "AndeRemindersTMClear"

-- World marker indices (/wm N) do NOT follow the same order as raid target
-- icons (/raid_target N). This mapping was confirmed in-game:
--   1 Blue Square, 2 Green Triangle, 3 Purple Diamond, 4 Red Cross,
--   5 Yellow Star, 6 Orange Circle, 7 Pale Blue Moon, 8 White Skull
local WORLD_ACTIONS        = {
    { key = "star",     label = "Star",             index = 5, icon = 1 },
    { key = "circle",   label = "Circle",           index = 6, icon = 2 },
    { key = "diamond",  label = "Diamond",          index = 3, icon = 3 },
    { key = "triangle", label = "Triangle",         index = 2, icon = 4 },
    { key = "moon",     label = "Moon",             index = 7, icon = 5 },
    { key = "square",   label = "Square",           index = 1, icon = 6 },
    { key = "cross",    label = "Cross",            index = 4, icon = 7 },
    { key = "skull",    label = "Skull",            index = 8, icon = 8 },
    { key = "clearAll", label = "Clear All Markers" },
}

-- World markers share their shapes with the raid target icons, so reuse those
-- textures (`icon` is the raid target icon number, not the /wm index).
for _, action in ipairs(WORLD_ACTIONS) do
    if action.icon then
        action.label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. action.icon .. ":16|t " .. action.label
    end
end

-- Raid target icon indices (/tm N): 1 Star, 2 Circle, 3 Diamond, 4 Triangle,
-- 5 Moon, 6 Square, 7 Cross, 8 Skull.
local TARGET_ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local TARGET_ACTIONS = {}
for i, name in ipairs(TARGET_ICON_NAMES) do
    TARGET_ACTIONS[i] = {
        key   = "tm" .. i,
        label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":16|t " .. name,
        index = i,
    }
end
TARGET_ACTIONS[#TARGET_ACTIONS + 1] = { key = "clearAll", label = "Clear All Target Markers" }

local GROUPS = {
    world  = { dbKey = "worldMarkers", actions = WORLD_ACTIONS, buttonPrefix = BUTTON_PREFIX, clearName = CLEAR_BUTTON_NAME },
    target = { dbKey = "targetMarkers", actions = TARGET_ACTIONS, buttonPrefix = TM_BUTTON_PREFIX, clearName = TM_CLEAR_BUTTON_NAME },
}
local GROUP_ORDER = { GROUPS.world, GROUPS.target }

for _, group in ipairs(GROUP_ORDER) do
    for _, action in ipairs(group.actions) do
        if action.key == "clearAll" then
            action.bindingTarget = "CLICK " .. group.clearName .. ":LeftButton"
        else
            action.bindingTarget = "CLICK " .. group.buttonPrefix .. action.index .. ":LeftButton"
        end
    end
end

local markerButtons = {}
local clearButton
local targetButtons = {}
local targetClearButton

-- ---------------------------------------------------------------------------
-- Secure buttons
-- ---------------------------------------------------------------------------

local function MarkerMacro(index, useCursor)
    if useCursor then
        return SLASH_WORLD_MARKER1 .. " [@cursor] " .. index
    end
    return SLASH_CLEAR_WORLD_MARKER1 .. " " .. index .. "\n" .. SLASH_WORLD_MARKER1 .. " " .. index
end

local pendingModeApply = false

local function ApplyMarkerMode(useCursor)
    if InCombatLockdown() then
        -- e.g. /reload fired mid-combat; retry once combat ends.
        pendingModeApply = true
        return false
    end
    for i = 1, 8 do
        markerButtons[i]:SetAttribute("macrotext", MarkerMacro(i, useCursor))
    end
    pendingModeApply = false
    return true
end

local function EnsureButtons(useCursor)
    if clearButton then return end
    for i = 1, 8 do
        local btn = CreateFrame("Button", BUTTON_PREFIX .. i, nil, "SecureActionButtonTemplate")
        btn:SetAttribute("type", "macro")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        markerButtons[i] = btn
    end
    clearButton = CreateFrame("Button", CLEAR_BUTTON_NAME, nil, "SecureActionButtonTemplate")
    clearButton:SetAttribute("type", "macro")
    clearButton:SetAttribute("macrotext", SLASH_CLEAR_WORLD_MARKER1 .. " all")
    clearButton:RegisterForClicks("AnyUp", "AnyDown")

    ApplyMarkerMode(useCursor)
end

-- Raid target icons have no "clear all" call, but each icon can only sit on one
-- unit at a time. Assigning every icon to the player in turn steals it from
-- whichever unit held it, then the final clear removes the player's mark.
-- SetRaidTarget is protected, so this has to run through a secure macro button.
local function BuildClearAllMacro()
    local slash = SLASH_TARGET_MARKER1 or "/tm"
    local lines = {}
    for i = 1, 8 do
        lines[#lines + 1] = slash .. " [@player] " .. i
    end
    lines[#lines + 1] = slash .. " [@player] 0"
    return table.concat(lines, "\n")
end

-- Each target marker key marks either the target or the mouseover unit: the
-- per-key override wins, otherwise the global setting decides.
local function UsesMouseover(tm, action)
    local override = tm.overrides[action.key]
    if override then return override == "mouseover" end
    return tm.useMouseover
end

local pendingTargetApply = false

local function ApplyTargetMode(tm)
    if InCombatLockdown() then
        pendingTargetApply = true
        return false
    end
    local slash = SLASH_TARGET_MARKER1 or "/tm"
    for _, action in ipairs(TARGET_ACTIONS) do
        if action.index then
            local unit = UsesMouseover(tm, action) and " [@mouseover] " or " "
            targetButtons[action.index]:SetAttribute("macrotext", slash .. unit .. action.index)
        end
    end
    pendingTargetApply = false
    return true
end

local function EnsureTargetButtons()
    if targetClearButton then return end
    for i = 1, 8 do
        local btn = CreateFrame("Button", TM_BUTTON_PREFIX .. i, nil, "SecureActionButtonTemplate")
        btn:SetAttribute("type", "macro")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        targetButtons[i] = btn
    end
    targetClearButton = CreateFrame("Button", TM_CLEAR_BUTTON_NAME, nil, "SecureActionButtonTemplate")
    targetClearButton:SetAttribute("type", "macro")
    targetClearButton:SetAttribute("macrotext", BuildClearAllMacro())
    targetClearButton:RegisterForClicks("AnyUp", "AnyDown")
end

-- ---------------------------------------------------------------------------
-- Keybind storage
-- ---------------------------------------------------------------------------

local pendingBindingApply = false

local function ApplyAllBindings(db)
    if InCombatLockdown() then
        -- e.g. /reload fired mid-combat; SetBinding is blocked, so retry once combat ends.
        pendingBindingApply = true
        return false
    end
    for _, group in ipairs(GROUP_ORDER) do
        for _, action in ipairs(group.actions) do
            local key = db[group.dbKey].keybinds[action.key]
            if key then
                SetBinding(key, action.bindingTarget)
            end
        end
    end
    pendingBindingApply = false
    return true
end

-- A key can only drive one action, across both tabs.
local function ClearKeyFromOtherActions(db, newKey, exceptAction)
    for _, group in ipairs(GROUP_ORDER) do
        for _, action in ipairs(group.actions) do
            if action ~= exceptAction and db[group.dbKey].keybinds[action.key] == newKey then
                db[group.dbKey].keybinds[action.key] = nil
                if action.refresh then action.refresh() end
            end
        end
    end
end

local function SetActionKey(db, group, action, newKey)
    if InCombatLockdown() then
        Util.Print("Can't change marker keybinds while in combat.")
        return false
    end
    local keybinds = db[group.dbKey].keybinds
    local oldKey = keybinds[action.key]
    if oldKey then
        SetBinding(oldKey)
    end
    if newKey then
        ClearKeyFromOtherActions(db, newKey, action)
        SetBinding(newKey, action.bindingTarget)
    end
    keybinds[action.key] = newKey
    return true
end

-- ---------------------------------------------------------------------------
-- Key capture widget
-- ---------------------------------------------------------------------------

local IGNORED_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    UNKNOWN = true,
    LeftButton = true,
    RightButton = true,
}

local MOUSE_BUTTON_NAMES = {
    MiddleButton = "BUTTON3",
    Button4      = "BUTTON4",
    Button5      = "BUTTON5",
}

local function BuildKeyString(key)
    if IsShiftKeyDown() then key = "SHIFT-" .. key end
    if IsControlKeyDown() then key = "CTRL-" .. key end
    if IsAltKeyDown() then key = "ALT-" .. key end
    return key
end

local captureFrame

local function GetCaptureFrame()
    if captureFrame then return captureFrame end

    local f = CreateFrame("Frame", "AndeRemindersWMKeyCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableKeyboard(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetPropagateKeyboardInput(false)

    -- Dim the screen and put the prompt on a small card so it reads against any scene.
    local dim = f:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.55)

    local card = AR.UI.CreateFrame("Frame", nil, f)
    card:SetSize(420, 84)
    card:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    AR.UI.Surface(card, AR.UI.Colors.window, AR.UI.Colors.border)

    local text = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", card, "CENTER", 0, 8)
    text:SetText("Press a key to bind")
    AR.UI.AccentText(text)

    local hint = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", text, "BOTTOM", 0, -8)
    hint:SetText("ESC to cancel")
    f.text = text

    f:Hide()
    captureFrame = f
    return f
end

local function StartKeyCapture(onCaptured)
    local f = GetCaptureFrame()

    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            onCaptured(nil)
            return
        end
        if IGNORED_KEYS[key] then return end
        self:Hide()
        onCaptured(BuildKeyString(key))
    end)

    f:SetScript("OnMouseUp", function(self, mouseButton)
        if IGNORED_KEYS[mouseButton] then
            self:Hide()
            onCaptured(nil)
            return
        end
        self:Hide()
        onCaptured(BuildKeyString(MOUSE_BUTTON_NAMES[mouseButton] or mouseButton))
    end)

    f:SetScript("OnMouseWheel", function(self, delta)
        self:Hide()
        onCaptured(BuildKeyString(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)

    f:Show()
end

-- ---------------------------------------------------------------------------
-- Database / registration
-- ---------------------------------------------------------------------------

function WorldMarkersModule:InitDB(db)
    if not db.worldMarkers then db.worldMarkers = {} end
    if db.worldMarkers.useCursor == nil then db.worldMarkers.useCursor = false end
    if not db.worldMarkers.keybinds then db.worldMarkers.keybinds = {} end

    EnsureButtons(db.worldMarkers.useCursor)
    -- Bindings are (re)applied on PLAYER_ENTERING_WORLD, not here: Blizzard
    -- restores the saved binding set around login/reload, which would wipe
    -- out any SetBinding call made this early (during ADDON_LOADED).
end

function TargetMarkersModule:InitDB(db)
    if not db.targetMarkers then db.targetMarkers = {} end
    if not db.targetMarkers.keybinds then db.targetMarkers.keybinds = {} end
    if db.targetMarkers.useMouseover == nil then db.targetMarkers.useMouseover = false end
    -- overrides[actionKey] = "target" | "mouseover"; nil follows the global setting.
    if not db.targetMarkers.overrides then db.targetMarkers.overrides = {} end

    EnsureTargetButtons()
    ApplyTargetMode(db.targetMarkers)
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

local COL_NAME_X = 16
local ROW_HEIGHT = 32

-- Section title, optional extra widgets (returns the next y), then the keybind rows.
-- `rowExtra(action, anchorBtn)` optionally adds a widget to the right of each row.
local function BuildKeybindTab(parent, db, group, title, extraWidgets, rowExtra)
    AR.UI.Title(parent, title, COL_NAME_X, -16)

    local y = extraWidgets(-52)

    AR.UI.Divider(parent, y, COL_NAME_X - 4)

    y = y - 14

    local stripe = 0
    for _, action in ipairs(group.actions) do
        if action.key == "clearAll" then
            y = y - 10
        end

        stripe = stripe + 1
        AR.UI.RowStripe(parent, y + 4, ROW_HEIGHT, stripe, COL_NAME_X - 4)

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 4, y - 2)
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        label:SetText(action.label)

        local bindBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        bindBtn:SetSize(150, 24)
        bindBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 170, y + 1)

        local function Refresh()
            bindBtn:SetText(db[group.dbKey].keybinds[action.key] or "Unbound")
        end
        Refresh()
        action.refresh = Refresh

        bindBtn:SetScript("OnClick", function()
            bindBtn:SetText("Press a key...")
            StartKeyCapture(function(keyString)
                if keyString then
                    SetActionKey(db, group, action, keyString)
                end
                Refresh()
            end)
        end)

        local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        clearBtn:SetSize(24, 24)
        clearBtn:SetPoint("LEFT", bindBtn, "RIGHT", 4, 0)
        clearBtn:SetText("x")
        clearBtn:SetScript("OnClick", function()
            SetActionKey(db, group, action, nil)
            Refresh()
        end)

        if rowExtra and action.index then rowExtra(action, clearBtn) end

        y = y - ROW_HEIGHT
    end

    parent:HookScript("OnHide", function()
        if captureFrame then captureFrame:Hide() end
    end)
end

function WorldMarkersModule:BuildUI(parent, db)
    BuildKeybindTab(parent, db, GROUPS.world, "World Marker Keybinds", function(y)
        local cbCursor = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cbCursor:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
        cbCursor:SetChecked(db.worldMarkers.useCursor)
        cbCursor:SetScript("OnClick", function(self)
            local wanted = self:GetChecked()
            if InCombatLockdown() then
                self:SetChecked(not wanted)
                Util.Print("Can't change World Marker mode while in combat.")
                return
            end
            db.worldMarkers.useCursor = wanted
            ApplyMarkerMode(wanted)
        end)

        local cursorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cursorLabel:SetPoint("LEFT", cbCursor, "RIGHT", 6, 0)
        cursorLabel:SetText("Place markers at cursor position instead of at your feet")

        return y - 30
    end)
end

function TargetMarkersModule:BuildUI(parent, db)
    local tm = db.targetMarkers
    local modeButtons = {}

    local function RefreshModeButtons()
        for action, btn in pairs(modeButtons) do
            local override = tm.overrides[action.key]
            if override then
                btn:SetText(override == "mouseover" and "Mouseover" or "Target")
            else
                btn:SetText("Default (" .. (tm.useMouseover and "Mouseover" or "Target") .. ")")
            end
        end
    end

    local function ApplyChange(revert)
        if InCombatLockdown() then
            revert()
            Util.Print("Can't change Target Marker mode while in combat.")
            return
        end
        ApplyTargetMode(tm)
        RefreshModeButtons()
    end

    BuildKeybindTab(parent, db, GROUPS.target, "Target Marker Keybinds", function(y)
        local cbMouseover = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cbMouseover:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
        cbMouseover:SetChecked(tm.useMouseover)
        cbMouseover:SetScript("OnClick", function(self)
            local wanted = self:GetChecked()
            local previous = tm.useMouseover
            tm.useMouseover = wanted
            ApplyChange(function()
                tm.useMouseover = previous
                self:SetChecked(previous)
            end)
        end)

        local mouseoverLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mouseoverLabel:SetPoint("LEFT", cbMouseover, "RIGHT", 6, 0)
        mouseoverLabel:SetText("Mark the mouseover unit instead of your target (per-key override on the right)")

        local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 44, y - 28)
        hint:SetText("Requires group leader or assist when grouped.")
        return y - 54
    end, function(action, anchor)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(150, 24)
        btn:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
        modeButtons[action] = btn
        btn:SetScript("OnClick", function()
            -- Cycle: Default -> Target -> Mouseover -> Default
            local previous = tm.overrides[action.key]
            if previous == nil then
                tm.overrides[action.key] = "target"
            elseif previous == "target" then
                tm.overrides[action.key] = "mouseover"
            else
                tm.overrides[action.key] = nil
            end
            ApplyChange(function() tm.overrides[action.key] = previous end)
        end)
    end)
    RefreshModeButtons()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local wmEvents = CreateFrame("Frame")
wmEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
wmEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
wmEvents:SetScript("OnEvent", function(_, event)
    if not (AR.db and AR.db.worldMarkers and AR.db.targetMarkers) then return end
    if event == "PLAYER_ENTERING_WORLD" then
        ApplyAllBindings(AR.db)
    else -- PLAYER_REGEN_ENABLED: finish whatever combat lockdown blocked
        if pendingModeApply then ApplyMarkerMode(AR.db.worldMarkers.useCursor) end
        if pendingTargetApply then ApplyTargetMode(AR.db.targetMarkers) end
        if pendingBindingApply then ApplyAllBindings(AR.db) end
    end
end)

AR:RegisterModule("World markers", WorldMarkersModule)
AR:RegisterModule("Target markers", TargetMarkersModule)
