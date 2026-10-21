AndeReminders = {}
local AR = AndeReminders

AR.registeredModules = {}
AR.modules           = {}  -- registered name -> module
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
    self.modules[name] = module
end

function AR:InitDB()
    AR:LoadProfile()
    if not AR.db.anchors then AR.db.anchors = {} end
    if not AR.db.anchorOpts then AR.db.anchorOpts = { snap = false, size = 10 } end
    if not AR.db.accent then
        AR.db.accent = { r = AR.UI.accent.r, g = AR.UI.accent.g, b = AR.UI.accent.b }
    end
    AR.UI.SetAccent(AR.db.accent.r, AR.db.accent.g, AR.db.accent.b)
    -- LibDBIcon manages: hide, minimapPos, lock, radius.
    if not AR.db.minimap then AR.db.minimap = { hide = false } end
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
local selectedAnchor

function AR:GetAnchorDefs() return ANCHOR_DEFS end

local function Deselect()
    if selectedAnchor then
        selectedAnchor:EnableKeyboard(false)
        selectedAnchor.selected:Hide()
        selectedAnchor = nil
    end
end

-- Click an anchor to select it: the arrow keys then nudge it (Shift = 10 units).
local function Select(f)
    if selectedAnchor == f then return end
    Deselect()
    selectedAnchor = f
    f:EnableKeyboard(true)
    f.selected:Show()
end

function AR:ToggleAnchors()
    AR.anchorsShown = not AR.anchorsShown
    for _, f in pairs(AR.anchorFrames) do
        f:SetAlpha(AR.anchorsShown and 1 or 0)
        f:EnableMouse(AR.anchorsShown)
    end
    if not AR.anchorsShown then Deselect() end
    if toggleAnchorsBtn then
        toggleAnchorsBtn:SetText(AR.anchorsShown and "Hide Anchors" or "Toggle Anchors")
    end
end

-- Offsets are from the screen centre. Everything anchored to the frame follows it.
function AR:SetAnchorPosition(name, x, y)
    local f = AR.anchorFrames[name]
    if not f then return end
    AR.db.anchors[name].x, AR.db.anchors[name].y = x, y
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if AR.OnAnchorMoved then AR.OnAnchorMoved(name) end
end

local function SnapToGrid(v)
    local opts = AR.db.anchorOpts
    if opts and opts.snap then
        local grid = math.max(1, opts.size or 10)
        return math.floor(v / grid + 0.5) * grid
    end
    return v
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

        local selected = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        selected:SetAllPoints()
        AR.UI.OnAccent(function(r, g, b) selected:SetColorTexture(r, g, b, 0.30) end)
        selected:Hide()
        f.selected = selected

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", f, "CENTER", 0, 0)
        lbl:SetText(def.label)

        f:SetScript("OnMouseDown", function(self) Select(self) end)
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            -- Re-anchoring also updates dependents (notification frames) correctly.
            AR:SetAnchorPosition(def.name, SnapToGrid(math.floor(cx - ux + 0.5)), SnapToGrid(math.floor(cy - uy + 0.5)))
        end)
        f:SetScript("OnKeyDown", function(self, key)
            local dx, dy = 0, 0
            if key == "LEFT" then dx = -1 elseif key == "RIGHT" then dx = 1
            elseif key == "UP" then dy = 1 elseif key == "DOWN" then dy = -1 end
            -- SetPropagateKeyboardInput is protected during combat lockdown.
            local canPropagate = not InCombatLockdown()
            if dx == 0 and dy == 0 then
                if canPropagate then self:SetPropagateKeyboardInput(true) end  -- not ours: let the game have the key
                return
            end
            if canPropagate then self:SetPropagateKeyboardInput(false) end
            local step = IsShiftKeyDown() and 10 or 1
            local cur = AR.db.anchors[def.name]
            AR:SetAnchorPosition(def.name, cur.x + dx * step, cur.y + dy * step)
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
        if AR.anchorFrames[def.name] then AR:SetAnchorPosition(def.name, def.x, def.y) end
    end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------

local LDB_NAME = "AndeReminders"

function AR:CreateMinimapButton()
    local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local dataObject = LDB:GetDataObjectByName(LDB_NAME) or LDB:NewDataObject(LDB_NAME, {
        type = "launcher",
        text = "AndeReminders",
        icon = "Interface\\AddOns\\AndeReminders\\Media\\minimap-icon.tga",
        OnClick = function() AR:ToggleSettings() end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("AndeReminders")
            tooltip:AddLine("|cffff9922Click|r to open the settings window.", 1, 1, 1)
        end,
    })

    if not LDBIcon:IsRegistered(LDB_NAME) then
        LDBIcon:Register(LDB_NAME, dataObject, AR.db.minimap)
    end
    LDBIcon:Refresh(LDB_NAME, AR.db.minimap)
end

function AR:SetMinimapButtonShown(show)
    AR.db.minimap.hide = not show
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon and LDBIcon:IsRegistered(LDB_NAME) then
        LDBIcon:Refresh(LDB_NAME, AR.db.minimap)
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

local SelectTab

function AR:SetWindowScale(scale)
    scale = math.max(0.6, math.min(1.4, scale))
    AR.root.ui.scale = scale
    if settingsFrame then settingsFrame:SetScale(scale) end
end

function SelectTab(index)
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

-- ---------------------------------------------------------------------------
-- Settings search: matches the visible labels of every tab
-- ---------------------------------------------------------------------------

local function StripEscapes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Every label under a tab page. Hidden children (dropdown lists, collapsed panels) are skipped.
local function CollectTexts(frame, out)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:IsObjectType("FontString") then
            local text = region:GetText()
            if type(text) == "string" and text ~= "" then out[#out + 1] = StripEscapes(text) end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsShown() then CollectTexts(child, out) end
    end
end

local MAX_RESULTS = 8

function AR:CreateSearch(window, closeBtn)
    local UI = AR.UI

    local box = UI.CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    box:SetSize(210, 24)
    box:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", box, "LEFT", 8, 0)
    hint:SetText("Search settings...")

    local results = UI.CreateFrame("Frame", nil, window)
    results:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -3)
    results:SetWidth(380)
    results:SetFrameLevel(window:GetFrameLevel() + 60)
    UI.Surface(results, UI.Colors.popup, { 1, 1, 1, 0.14 })
    results:EnableMouse(true)
    results:Hide()

    local rows, hits = {}, {}

    local function Close()
        results:Hide()
        box:SetText("")
        box:ClearFocus()
    end

    local function Pick(i)
        local hit = hits[i]
        if not hit then return end
        Close()
        SelectTab(hit.tab)
    end

    for i = 1, MAX_RESULTS do
        local row = UI.CreateFrame("Button", nil, results)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", results, "TOPLEFT", 4, -4 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", results, "TOPRIGHT", -4, -4 - (i - 1) * 24)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function() Pick(i) end)
        rows[i] = row
    end

    local function Search()
        local q = box:GetText():lower()
        wipe(hits)
        if q ~= "" then
            for index, entry in ipairs(AR.registeredModules) do
                if #hits >= MAX_RESULTS then break end
                local tabName = entry.name
                if tabName:lower():find(q, 1, true) then
                    hits[#hits + 1] = { tab = index, text = "|cFFFFCC00" .. tabName .. "|r" }
                end
                local texts = {}
                if entry.contentFrame then CollectTexts(entry.contentFrame, texts) end
                local seen = {}
                for _, text in ipairs(texts) do
                    if #hits >= MAX_RESULTS then break end
                    if not seen[text] and text:lower():find(q, 1, true) then
                        seen[text] = true
                        hits[#hits + 1] = { tab = index, text = "|cFFFFCC00" .. tabName .. "|r  " .. text }
                    end
                end
            end
        end
        for i, row in ipairs(rows) do
            local hit = hits[i]
            row:SetShown(hit ~= nil)
            if hit then row.label:SetText(hit.text) end
        end
        if #hits > 0 then
            results:SetHeight(8 + #hits * 24)
            results:Show()
        elseif q ~= "" then
            rows[1]:Show()
            rows[1].label:SetText("No matching settings")
            results:SetHeight(32)
            results:Show()
        else
            results:Hide()
        end
    end

    local debounced = AR.Util.Debounce(0.2, Search)
    box:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        debounced()
    end)
    box:SetScript("OnEnterPressed", function() Search(); Pick(1) end)
    box:SetScript("OnEscapePressed", Close)
    window:HookScript("OnHide", function() Close() end)
end

function AR:OpenTab(index)
    self:CreateSettingsWindow()
    settingsFrame:Show()
    SelectTab(index)
end

function AR:CreateSettingsWindow()
    if settingsFrame then return settingsFrame end
    local UI = AR.UI
    local C  = UI.Colors

    local f = UI.CreateFrame("Frame", "AndeRemindersSettings", UIParent)
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetScale(AR.root.ui.scale or 1)
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

    local cbMinimap = UI.CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
    cbMinimap:SetSize(24, 24)
    cbMinimap:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -4, 10)
    cbMinimap:SetChecked(not AR.db.minimap.hide)
    cbMinimap:SetScript("OnClick", function(self) AR:SetMinimapButtonShown(self:GetChecked()) end)
    local minimapLabel = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minimapLabel:SetPoint("LEFT", cbMinimap, "RIGHT", 4, 0)
    minimapLabel:SetText("Minimap icon")

    local accentLabel = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accentLabel:SetPoint("BOTTOMLEFT", cbMinimap, "TOPLEFT", 4, 14)
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

    AR:CreateSearch(f, closeBtn)

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
        AR:CreateMinimapButton()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function PrintHelp()
    AR.Util.Print("commands:")
    print("  /ar                 toggle the settings window")
    print("  /ar <tab>           open a settings tab (general, gear, enchants, talents, bossmods...)")
    print("  /ar check           run every check now and print the status")
    print("  /ar test            show an example of every alert")
    print("  /ar anchors         show / hide the draggable anchor frames")
    print("  /ar reset           put every anchor back at its default position")
    print("  /ar unsnooze        show snoozed alerts again")
    print("  /ar profile [name]  show or switch this character's profile (reloads the UI)")
    print("  /ar gems            list the socket / gem counts the gem check sees")
    print("  /arbm list          list BossMods entries and their trigger types")
    print("  /arbm trigger       fire a 10s test timer to see which entries match")
end

SLASH_ANDEREMINDERS1 = "/ar"
SLASH_ANDEREMINDERS2 = "/andereminders"
SlashCmdList["ANDEREMINDERS"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if msg == "" then
        AR:ToggleSettings()
    elseif cmd == "anchors" then
        AR:ToggleAnchors()
    elseif cmd == "reset" then
        AR:ResetAnchors()
        AR.Util.Print("anchors reset to their default positions.")
    elseif cmd == "check" then
        if AR.RunAllChecks then AR:RunAllChecks(true) end
    elseif cmd == "test" then
        if AR.ShowTestAlerts then AR:ShowTestAlerts() end
    elseif cmd == "gems" then
        for _, entry in ipairs(AR.registeredModules) do
            if entry.module.DebugGems then entry.module:DebugGems() end
        end
    elseif cmd == "unsnooze" then
        AR.UI.UnsnoozeAlerts()
        AR.Util.Print("snoozed alerts will show again at the next check.")
    elseif cmd == "profile" then
        if rest == "" then
            AR.Util.Print("profile: " .. AR.profileName .. "  (available: " .. table.concat(AR:GetProfileNames(), ", ") .. ")")
        else
            local target
            for _, name in ipairs(AR:GetProfileNames()) do
                if name:lower() == rest:lower() then target = name end
            end
            if target then AR:SwitchProfile(target) else AR.Util.Print("no profile named \"" .. rest .. "\".") end
        end
    elseif cmd == "help" then
        PrintHelp()
    else
        -- "/ar gear", "/ar world markers": open the tab whose name starts with the text.
        local wanted = msg:lower()
        for index, entry in ipairs(AR.registeredModules) do
            if entry.name:lower():sub(1, #wanted) == wanted then
                AR:OpenTab(index)
                return
            end
        end
        PrintHelp()
    end
end
