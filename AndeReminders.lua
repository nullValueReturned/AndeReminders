AndeReminders = {}
local AR = AndeReminders

AR.registeredModules = {}
AR.anchorFrames      = {}
AR.anchorsShown      = false

local ANCHOR_DEFS = {
    { name = "encounter", label = "Combat Text",    x = 0, y = 260, w = 200, h = 50 },
    { name = "talents",   label = "Talent Build",   x = 0, y = 180, w = 300, h = 60 },
    { name = "enchants",  label = "Enchant Alerts", x = 0, y = 90,  w = 360, h = 80 },
    { name = "gear",      label = "Gear Alerts",    x = 0, y = 0,   w = 380, h = 80 },
    { name = "repair",    label = "Repair Warning", x = 0, y = -90, w = 500, h = 70 },
}

-- Runs fn through the game's error handler so one broken module cannot take the rest of
-- the addon down with it.
local function Guarded(fn)
    return xpcall(fn, geterrorhandler())
end

function AR:RegisterModule(name, module)
    table.insert(self.registeredModules, { name = name, module = module })
end

function AR:InitDB()
    if not AndeRemindersDB then AndeRemindersDB = {} end
    AR.db = AndeRemindersDB
    if not AR.db.anchors then AR.db.anchors = {} end
    if not AR.db.accent then
        AR.db.accent = { r = AR.UI.accent.r, g = AR.UI.accent.g, b = AR.UI.accent.b }
    end
    AR.UI.SetAccent(AR.db.accent.r, AR.db.accent.g, AR.db.accent.b)
    for _, def in ipairs(ANCHOR_DEFS) do
        if not AR.db.anchors[def.name] then
            AR.db.anchors[def.name] = { x = def.x, y = def.y }
        end
    end
    for _, entry in ipairs(AR.registeredModules) do
        if entry.module.InitDB then
            Guarded(function() entry.module:InitDB(AR.db) end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Anchor system
-- ---------------------------------------------------------------------------

function AR:GetAnchor(name)
    return AR.anchorFrames[name]
end

local toggleAnchorsBtn

function AR:ToggleAnchors()
    AR.anchorsShown = not AR.anchorsShown
    for _, f in pairs(AR.anchorFrames) do
        f:SetAlpha(AR.anchorsShown and 1 or 0)
        f:EnableMouse(AR.anchorsShown)
    end
    if toggleAnchorsBtn then
        toggleAnchorsBtn:SetText(AR.anchorsShown and "Hide Anchors" or "Toggle Anchors")
    end
end

function AR:CreateAnchors()
    for _, def in ipairs(ANCHOR_DEFS) do
        local saved = AR.db.anchors[def.name]
        local x = (saved and saved.x) or def.x
        local y = (saved and saved.y) or def.y

        local f = AR.UI.CreateFrame("Frame", "AndeRemindersAnchor_" .. def.name, UIParent)
        f:SetSize(def.w, def.h)
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetFrameStrata("HIGH")
        AR.UI.Surface(f, { 0, 0, 0, 0.55 }, { 1, 1, 1, 1 })

        local tint = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        tint:SetAllPoints()
        AR.UI.OnAccent(function(r, g, b)
            f.arBorder:SetColor(r, g, b, 0.95)
            tint:SetColorTexture(r, g, b, 0.16)
        end)

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", f, "CENTER", 0, 0)
        lbl:SetText(def.label)

        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local dx = math.floor(cx - ux + 0.5)
            local dy = math.floor(cy - uy + 0.5)
            AR.db.anchors[def.name].x = dx
            AR.db.anchors[def.name].y = dy
            -- Re-anchor so dependents (notification frames) update correctly
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", dx, dy)
        end)

        f:SetAlpha(0)
        f:EnableMouse(false)

        AR.anchorFrames[def.name] = f
    end
end

-- Puts every anchor back at its default position (e.g. one was dragged off-screen).
function AR:ResetAnchors()
    for _, def in ipairs(ANCHOR_DEFS) do
        AR.db.anchors[def.name] = { x = def.x, y = def.y }
        local f = AR.anchorFrames[def.name]
        if f then
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", def.x, def.y)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------

local settingsFrame
local activeTabIndex = 0

local WINDOW_W, WINDOW_H = 1120, 660
local SIDEBAR_W          = 176
local TOPBAR_H           = 46
local NAV_H              = 34

local function SelectTab(index)
    activeTabIndex = index
    for i, entry in ipairs(AR.registeredModules) do
        if entry.contentFrame then
            entry.contentFrame:SetShown(i == index)
            entry.navAnim:To(i == index and 1 or 0)
        end
    end
    local entry = AR.registeredModules[index]
    if entry and settingsFrame then settingsFrame.crumb:SetText(entry.name) end
end

-- One sidebar entry: hover wash, accent bar that grows in on the active tab, dimmed label.
local function CreateNavItem(parent, entry, index, y)
    local UI = AR.UI
    local item = UI.CreateFrame("Button", nil, parent)
    item:SetHeight(NAV_H)
    item:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)

    local wash = item:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints()

    local bar = item:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("LEFT", item, "LEFT", 0, 0)
    bar:SetWidth(3)

    local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", item, "LEFT", 18, 0)
    label:SetText(entry.name)

    local hover = 0
    local active

    local function Paint()
        local a = active.value
        wash:SetColorTexture(UI.accent.r, UI.accent.g, UI.accent.b, 0.11 * a + 0.045 * hover * (1 - a))
        bar:SetColorTexture(UI.accent.r, UI.accent.g, UI.accent.b, 1)
        bar:SetHeight(math.max(0.01, (NAV_H - 14) * a))
        label:SetTextColor(1, 1, 1, 0.55 + 0.45 * math.max(a, hover))
        label:SetPoint("LEFT", item, "LEFT", 18 + 3 * a, 0)
    end
    active = UI.NewAnim(Paint, 16)
    UI.OnAccent(Paint)
    entry.navAnim = active

    item:SetScript("OnEnter", function() hover = 1; Paint() end)
    item:SetScript("OnLeave", function() hover = 0; Paint() end)
    item:SetScript("OnClick", function() SelectTab(index) end)
    return item
end

function AR:CreateSettingsWindow()
    if settingsFrame then return settingsFrame end
    local UI = AR.UI
    local C  = UI.Colors

    local f = UI.CreateFrame("Frame", "AndeRemindersSettings", UIParent)
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    UI.Surface(f, C.window, C.border)
    f:Hide()
    tinsert(UISpecialFrames, "AndeRemindersSettings")  -- Escape closes the window
    UI.FadeInOnShow(f)

    -- Accent wash fading down from the top edge.
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetPoint("TOPLEFT",  f, "TOPLEFT",  SIDEBAR_W, 0)
    wash:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    wash:SetHeight(180)
    UI.OnAccent(function(r, g, b)
        wash:SetColorTexture(r, g, b, 1)
        wash:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.07))
    end)

    -- Sidebar ---------------------------------------------------------------
    local side = UI.CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
    side:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDEBAR_W)
    local sideBg = side:CreateTexture(nil, "BACKGROUND", nil, 2)
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(unpack(C.side))
    local sideEdge = side:CreateTexture(nil, "BORDER")
    sideEdge:SetPoint("TOPRIGHT"); sideEdge:SetPoint("BOTTOMRIGHT"); sideEdge:SetWidth(1)
    sideEdge:SetColorTexture(unpack(C.border))

    local logo = side:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    logo:SetPoint("TOPLEFT", side, "TOPLEFT", 18, -20)
    UI.OnAccent(function(r, g, b)
        logo:SetText("Ande|cff" .. UI.Hex(r, g, b) .. "Reminders|r")
    end)
    logo:SetTextColor(1, 1, 1, 1)

    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("AndeReminders", "Version")
    local sub = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -3)
    sub:SetText(version and ("v" .. version) or "")

    local navTop = -78
    local navDiv = UI.Divider(side, navTop + 10, 18)

    for i, entry in ipairs(AR.registeredModules) do
        CreateNavItem(side, entry, i, navTop - (i - 1) * NAV_H - 4)
    end

    -- Sidebar footer: accent picker and the anchors toggle.
    local btn = UI.Button(side, AR.anchorsShown and "Hide Anchors" or "Toggle Anchors", SIDEBAR_W - 36, 28)
    btn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 18, 18)
    btn:SetScript("OnClick", function() AR:ToggleAnchors() end)
    toggleAnchorsBtn = btn

    local accentLabel = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accentLabel:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 20)
    accentLabel:SetText("ACCENT")
    local swatch = UI.ColorSwatch(side,
        function() return UI.accent.r, UI.accent.g, UI.accent.b end,
        function(r, g, b)
            AR.db.accent.r, AR.db.accent.g, AR.db.accent.b = r, g, b
            UI.SetAccent(r, g, b)
        end, 20)
    swatch:SetPoint("LEFT", accentLabel, "RIGHT", 10, 0)

    -- Top bar ---------------------------------------------------------------
    local crumbRoot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crumbRoot:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + 22, -17)
    crumbRoot:SetText("SETTINGS  /")
    local crumb = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crumb:SetPoint("LEFT", crumbRoot, "RIGHT", 8, 0)
    f.crumb = crumb

    local closeBtn = UI.CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -9)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local topDiv = f:CreateTexture(nil, "ARTWORK")
    topDiv:SetHeight(1)
    topDiv:SetColorTexture(unpack(C.border))
    topDiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  SIDEBAR_W, -TOPBAR_H)
    topDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TOPBAR_H)

    -- Pages -----------------------------------------------------------------
    for _, entry in ipairs(AR.registeredModules) do
        local content = UI.CreateFrame("Frame", nil, f)
        content:SetPoint("TOPLEFT",     f, "TOPLEFT",     SIDEBAR_W + 1, -(TOPBAR_H + 1))
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        content:Hide()
        entry.contentFrame = content

        if entry.module.BuildUI then
            Guarded(function() entry.module:BuildUI(content, AR.db) end)
        end
    end

    settingsFrame = f

    if #AR.registeredModules > 0 then
        SelectTab(1)
        for _, entry in ipairs(AR.registeredModules) do entry.navAnim:To(entry == AR.registeredModules[1] and 1 or 0, true) end
    end

    return f
end

function AR:ToggleSettings()
    if not settingsFrame then
        self:CreateSettingsWindow()
    end
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Bootstrap
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "AndeReminders" then
        AR:InitDB()
        AR:CreateAnchors()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function PrintHelp()
    AR.Util.Print("commands:")
    print("  /ar            toggle the settings window")
    print("  /ar anchors    show / hide the draggable anchor frames")
    print("  /ar reset      put every anchor back at its default position")
end

SLASH_ANDEREMINDERS1 = "/ar"
SLASH_ANDEREMINDERS2 = "/andereminders"
SlashCmdList["ANDEREMINDERS"] = function(msg)
    local cmd = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if cmd == "" then
        AR:ToggleSettings()
    elseif cmd == "anchors" then
        AR:ToggleAnchors()
    elseif cmd == "reset" then
        AR:ResetAnchors()
        AR.Util.Print("anchors reset to their default positions.")
    else
        PrintHelp()
    end
end
