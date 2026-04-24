AndeReminders = {}
local AR = AndeReminders

AR.registeredModules = {}
AR.anchorFrames      = {}
AR.anchorsShown      = false

local ANCHOR_DEFS = {
    { name = "talents",  label = "Talent Build",   x = 0, y = 180, w = 300, h = 60 },
    { name = "enchants", label = "Enchant Alerts", x = 0, y = 90,  w = 360, h = 80 },
    { name = "gear",     label = "Gear Alerts",    x = 0, y = 0,   w = 380, h = 80 },
    { name = "repair",   label = "Repair Warning", x = 0, y = -90, w = 500, h = 70 },
}

function AR:RegisterModule(name, module)
    table.insert(self.registeredModules, { name = name, module = module })
end

function AR:InitDB()
    if not AndeRemindersDB then AndeRemindersDB = {} end
    AR.db = AndeRemindersDB
    if not AR.db.anchors then AR.db.anchors = {} end
    for _, def in ipairs(ANCHOR_DEFS) do
        if not AR.db.anchors[def.name] then
            AR.db.anchors[def.name] = { x = def.x, y = def.y }
        end
    end
    for _, entry in ipairs(AR.registeredModules) do
        if entry.module.InitDB then
            entry.module:InitDB(AR.db)
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

        local f = CreateFrame("Frame", "AndeRemindersAnchor_" .. def.name, UIParent, "BackdropTemplate")
        f:SetSize(def.w, def.h)
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetFrameStrata("HIGH")
        f:SetBackdrop({
            bgFile   = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.4, 0.8, 0.4)
        f:SetBackdropBorderColor(0.4, 0.8, 1, 0.9)

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", f, "CENTER", 0, 0)
        lbl:SetText(def.label)
        lbl:SetTextColor(1, 1, 1, 1)

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

-- ---------------------------------------------------------------------------
-- Settings window
-- ---------------------------------------------------------------------------

local settingsFrame
local activeTabIndex = 0

local function SelectTab(index)
    activeTabIndex = index
    for i, entry in ipairs(AR.registeredModules) do
        if entry.contentFrame then
            if i == index then
                entry.contentFrame:Show()
                entry.tabButton:SetBackdropColor(0.15, 0.35, 0.7, 1)
                entry.tabButton:SetBackdropBorderColor(0.5, 0.6, 0.9, 1)
            else
                entry.contentFrame:Hide()
                entry.tabButton:SetBackdropColor(0.05, 0.05, 0.05, 1)
                entry.tabButton:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
            end
        end
    end
end

function AR:CreateSettingsWindow()
    if settingsFrame then return settingsFrame end

    local f = CreateFrame("Frame", "AndeRemindersSettings", UIParent, "BackdropTemplate")
    f:SetSize(540, 460)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        tile = true, tileSize = 32,
    })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("AndeReminders")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local titleDiv = f:CreateTexture(nil, "ARTWORK")
    titleDiv:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    titleDiv:SetHeight(1)
    titleDiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -37)
    titleDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -37)

    -- Toggle Anchors button at the bottom of the window
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(150, 24)
    btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    btn:SetText("Toggle Anchors")
    btn:SetScript("OnClick", function() AR:ToggleAnchors() end)
    toggleAnchorsBtn = btn

    local tabX      = 14
    local TAB_Y     = -40
    local CONTENT_Y = TAB_Y - 28

    for i, entry in ipairs(AR.registeredModules) do
        local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
        tab:SetSize(100, 24)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", tabX, TAB_Y)
        tab:SetBackdrop({
            bgFile   = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
        })
        tab:SetBackdropColor(0.05, 0.05, 0.05, 1)
        tab:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetAllPoints(tab)
        tabText:SetJustifyH("CENTER")
        tabText:SetText(entry.name)

        entry.tabButton = tab
        tabX = tabX + 104

        local content = CreateFrame("Frame", nil, f, "BackdropTemplate")
        content:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, CONTENT_Y)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 44)  -- 44px gap for toggle button
        content:SetBackdrop({
            bgFile   = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
        })
        content:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
        content:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        content:Hide()

        entry.contentFrame = content

        if entry.module.BuildUI then
            entry.module:BuildUI(content, AR.db)
        end

        local tabIndex = i
        tab:SetScript("OnEnter", function(self)
            if activeTabIndex ~= tabIndex then
                self:SetBackdropColor(0.1, 0.2, 0.45, 1)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if activeTabIndex ~= tabIndex then
                self:SetBackdropColor(0.05, 0.05, 0.05, 1)
            end
        end)
        tab:SetScript("OnClick", function()
            SelectTab(tabIndex)
        end)
    end

    if #AR.registeredModules > 0 then
        SelectTab(1)
    end

    settingsFrame = f
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
        AR:CreateSettingsWindow()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_ANDEREMINDERS1 = "/ar"
SLASH_ANDEREMINDERS2 = "/andereminders"
SlashCmdList["ANDEREMINDERS"] = function(msg)
    if msg == "anchors" then
        AR:ToggleAnchors()
    else
        AR:ToggleSettings()
    end
end
