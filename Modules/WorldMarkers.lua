local AR = AndeReminders

local WorldMarkersModule = {}

-- World marker placement is a protected action (requires a hardware event),
-- so the real placement has to run through a SecureActionButtonTemplate with
-- a macro attribute. Everything else (the keybind capture UI, storage) is
-- plain insecure Lua that just points a physical key at these buttons.
local BUTTON_PREFIX     = "AndeRemindersWM"
local CLEAR_BUTTON_NAME = "AndeRemindersWMClear"

local ACTIONS = {
    { key = "star",     label = "Star",     bindingTarget = "CLICK " .. BUTTON_PREFIX .. "1:LeftButton" },
    { key = "circle",   label = "Circle",   bindingTarget = "CLICK " .. BUTTON_PREFIX .. "2:LeftButton" },
    { key = "diamond",  label = "Diamond",  bindingTarget = "CLICK " .. BUTTON_PREFIX .. "3:LeftButton" },
    { key = "triangle", label = "Triangle", bindingTarget = "CLICK " .. BUTTON_PREFIX .. "4:LeftButton" },
    { key = "moon",     label = "Moon",     bindingTarget = "CLICK " .. BUTTON_PREFIX .. "5:LeftButton" },
    { key = "square",   label = "Square",   bindingTarget = "CLICK " .. BUTTON_PREFIX .. "6:LeftButton" },
    { key = "cross",    label = "Cross",    bindingTarget = "CLICK " .. BUTTON_PREFIX .. "7:LeftButton" },
    { key = "skull",    label = "Skull",    bindingTarget = "CLICK " .. BUTTON_PREFIX .. "8:LeftButton" },
    { key = "clearAll", label = "Clear All Markers", bindingTarget = "CLICK " .. CLEAR_BUTTON_NAME .. ":LeftButton" },
}

local markerButtons = {}
local clearButton
local rowRefreshers = {}

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
    clearButton:SetAttribute("macrotext", SLASH_CLEAR_WORLD_MARKER1 .. " 0")
    clearButton:RegisterForClicks("AnyUp", "AnyDown")

    ApplyMarkerMode(useCursor)
end

-- ---------------------------------------------------------------------------
-- Keybind storage
-- ---------------------------------------------------------------------------

local function ApplyAllBindings(db)
    for _, action in ipairs(ACTIONS) do
        local key = db.worldMarkers.keybinds[action.key]
        if key then
            SetBinding(key, action.bindingTarget)
        end
    end
end

local function ClearKeyFromOtherActions(db, newKey, exceptActionKey)
    for _, action in ipairs(ACTIONS) do
        if action.key ~= exceptActionKey and db.worldMarkers.keybinds[action.key] == newKey then
            db.worldMarkers.keybinds[action.key] = nil
            if rowRefreshers[action.key] then rowRefreshers[action.key]() end
        end
    end
end

local function SetActionKey(db, action, newKey)
    local oldKey = db.worldMarkers.keybinds[action.key]
    if oldKey then
        SetBinding(oldKey)
    end
    if newKey then
        ClearKeyFromOtherActions(db, newKey, action.key)
        SetBinding(newKey, action.bindingTarget)
    end
    db.worldMarkers.keybinds[action.key] = newKey
end

-- ---------------------------------------------------------------------------
-- Key capture widget
-- ---------------------------------------------------------------------------

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    UNKNOWN = true, LeftButton = true, RightButton = true,
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

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    text:SetText("Press a key to bind (ESC to cancel)")
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
    ApplyAllBindings(db)
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function WorldMarkersModule:BuildUI(parent, db)
    local COL_NAME_X = 12
    local ROW_HEIGHT = 26

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("World Marker Keybinds")
    sectionTitle:SetTextColor(1, 0.82, 0)

    local y = -36

    local cbCursor = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbCursor:SetSize(24, 24)
    cbCursor:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbCursor:SetChecked(db.worldMarkers.useCursor)
    cbCursor:SetScript("OnClick", function(self)
        local wanted = self:GetChecked()
        if InCombatLockdown() then
            self:SetChecked(not wanted)
            print("|cFFFF6600[AndeReminders]|r Can't change World Marker mode while in combat.")
            return
        end
        db.worldMarkers.useCursor = wanted
        ApplyMarkerMode(wanted)
    end)

    local cursorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cursorLabel:SetPoint("LEFT", cbCursor, "RIGHT", 6, 0)
    cursorLabel:SetText("Place markers at cursor position instead of on target")

    y = y - 30

    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

    y = y - 16

    for _, action in ipairs(ACTIONS) do
        if action.key == "clearAll" then
            y = y - 8
        end

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        label:SetText(action.label)

        local bindBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        bindBtn:SetSize(140, 22)
        bindBtn:SetPoint("LEFT", label, "RIGHT", 10, -1)

        local function Refresh()
            bindBtn:SetText(db.worldMarkers.keybinds[action.key] or "Unbound")
        end
        Refresh()
        rowRefreshers[action.key] = Refresh

        bindBtn:SetScript("OnClick", function()
            bindBtn:SetText("Press a key...")
            StartKeyCapture(function(keyString)
                if keyString then
                    SetActionKey(db, action, keyString)
                end
                Refresh()
            end)
        end)

        local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        clearBtn:SetSize(22, 22)
        clearBtn:SetPoint("LEFT", bindBtn, "RIGHT", 4, 0)
        clearBtn:SetText("x")
        clearBtn:SetScript("OnClick", function()
            SetActionKey(db, action, nil)
            Refresh()
        end)

        y = y - ROW_HEIGHT
    end

    parent:HookScript("OnHide", function()
        if captureFrame then captureFrame:Hide() end
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local wmEvents = CreateFrame("Frame")
wmEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
wmEvents:SetScript("OnEvent", function()
    if pendingModeApply and AR.db and AR.db.worldMarkers then
        ApplyMarkerMode(AR.db.worldMarkers.useCursor)
    end
end)

AR:RegisterModule("Markers", WorldMarkersModule)
