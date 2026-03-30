local AR = andeReminders

local TalentModule = {}
local checkTimer   = nil
local alertFrame   = nil   -- box for unspent talent points
local buildTextFrame = nil -- loose flash text for active build

-- LibSharedMedia-3.0 integration (optional — falls back to built-in fonts if not present)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FALLBACK_FONT_NAMES = { "Friz Quadrata TT", "Morpheus", "Skurri", "Arial Narrow" }
local FALLBACK_FONT_PATHS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.ttf",
    ["Skurri"]           = "Fonts\\skurri.ttf",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
}
local DEFAULT_FONT_NAME = "Friz Quadrata TT"

local function GetFontNames()
    if LSM then return LSM:List("font") end
    return FALLBACK_FONT_NAMES
end

local function ResolveFontPath(name)
    if LSM then
        local path = LSM:Fetch("font", name)
        if path then return path end
    end
    return FALLBACK_FONT_PATHS[name] or "Fonts\\FRIZQT__.TTF"
end

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function TalentModule:InitDB(db)
    if not db.talents then db.talents = {} end
    if not db.talents.notify then db.talents.notify = {} end
    if db.talents.notify.chat   == nil then db.talents.notify.chat   = true end
    if db.talents.notify.screen == nil then db.talents.notify.screen = true end
    if not db.talents.checks then db.talents.checks = {} end
    if db.talents.checks.unspentPoints   == nil then db.talents.checks.unspentPoints   = true end
    if db.talents.checks.showActiveBuild == nil then db.talents.checks.showActiveBuild = true end
    if not db.talents.buildText then db.talents.buildText = {} end
    if not db.talents.buildText.fontName then db.talents.buildText.fontName = DEFAULT_FONT_NAME end
    if db.talents.buildText.r == nil then db.talents.buildText.r = 1   end
    if db.talents.buildText.g == nil then db.talents.buildText.g = 0.8 end
    if db.talents.buildText.b == nil then db.talents.buildText.b = 0   end
end

-- ---------------------------------------------------------------------------
-- On-screen alert box (unspent points)
-- ---------------------------------------------------------------------------

local function GetAlertFrame()
    if alertFrame then return alertFrame end

    alertFrame = CreateFrame("Frame", "andeRemindersTalentAlert", UIParent, "BackdropTemplate")
    alertFrame:SetSize(360, 80)
    alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -380)
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

function TalentModule:ShowAlert(text)
    local af = GetAlertFrame()
    af.body:SetText(text)
    af:SetHeight(af.body:GetHeight() + 44)
    af:Show()
end

-- ---------------------------------------------------------------------------
-- Active build flash text (no box, configurable font/color, center screen, 10s)
-- ---------------------------------------------------------------------------

local function GetBuildTextFrame()
    if buildTextFrame then return buildTextFrame end

    local f = CreateFrame("Frame", "andeRemindersBuildText", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(2, -2)
    fs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    f.text = fs

    f:Hide()
    buildTextFrame = f
    return buildTextFrame
end

function TalentModule:ShowBuildText(name)
    local btf = GetBuildTextFrame()
    local cfg = AR.db and AR.db.talents and AR.db.talents.buildText
    local fontName = (cfg and cfg.fontName) or DEFAULT_FONT_NAME
    local r        = (cfg and cfg.r)        or 1
    local g        = (cfg and cfg.g)        or 0.8
    local b        = (cfg and cfg.b)        or 0
    btf.text:SetFont(ResolveFontPath(fontName), 36, "OUTLINE")
    btf.text:SetTextColor(r, g, b)
    btf.text:SetText(name)
    btf:Show()
    if btf.hideTimer then btf.hideTimer:Cancel() end
    btf.hideTimer = C_Timer.NewTimer(10, function()
        btf:Hide()
        btf.hideTimer = nil
    end)
end

-- ---------------------------------------------------------------------------
-- Logic
-- ---------------------------------------------------------------------------

-- Returns true if the player has any unspent talent points across all trees.
local function HasUnspentTalentPoints()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return false end
    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return false end
    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.canPurchaseRank then
                    return true
                end
            end
        end
    end
    return false
end

-- TLE zeroes out the hero talent section of the export string (replaces it with A's),
-- while Blizzard's GenerateImportString includes hero talent data.
-- Both strings share the same class/spec talent data at the end.
-- Strip the 4-char header and any leading A's to get the comparable core,
-- then check whether the Blizzard string ends with the TLE core.
local function GetTalentCore(s)
    if not s or #s < 5 then return "" end
    return s:sub(5):match("^A*(.+)") or ""
end

-- Returns the name of the currently active talent loadout.
-- Checks TalentLoadoutEx first (if loaded), then falls back to the native WoW loadout name.
local function GetActiveLoadoutName()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end

    -- TalentLoadoutEx: stored as TalentLoadoutEx[CLASS][specIndex], each entry has .text (export string) and .name
    if TalentLoadoutEx then
        local _, unitClass = UnitClass("player")
        local activeConfigID = C_ClassTalents.GetActiveConfigID()
        if unitClass and activeConfigID and TalentLoadoutEx[unitClass] and TalentLoadoutEx[unitClass][specIndex] then
            local currentString = C_Traits.GenerateImportString(activeConfigID)
            if currentString then
                local blizzCore = GetTalentCore(currentString)
                for _, v in pairs(TalentLoadoutEx[unitClass][specIndex]) do
                    if v.text and v.name then
                        local tleCore = GetTalentCore(v.text)
                        if tleCore ~= "" and #blizzCore >= #tleCore and blizzCore:sub(-#tleCore) == tleCore then
                            return v.name
                        end
                    end
                end
            end
        end
    end

    -- Native WoW loadout name
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then return nil end
    local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if configID then
        local info = C_Traits.GetConfigInfo(configID)
        if info and info.name and info.name ~= "" then
            return info.name
        end
    end

    return nil
end

function TalentModule:RunCheck()
    if not AR.db then return end
    local db = AR.db

    -- Unspent talent points
    if db.talents.checks.unspentPoints then
        if HasUnspentTalentPoints() then
            local notify = db.talents.notify
            if notify.chat then
                print("|cFFFF6600[andeReminders]|r You have unspent talent points!")
            end
            if notify.screen then
                self:ShowAlert("|cFFFFCC00You have unspent talent points!|r")
            end
        else
            if alertFrame and alertFrame:IsShown() then alertFrame:Hide() end
        end
    end

    -- Show active build as flash text
    if db.talents.checks.showActiveBuild then
        local name = GetActiveLoadoutName()
        if name then
            self:ShowBuildText(name)
        end
    end
end

local function ScheduleCheck()
    if checkTimer then checkTimer:Cancel() end
    checkTimer = C_Timer.NewTimer(2, function()
        checkTimer = nil
        TalentModule:RunCheck()
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local talentEvents = CreateFrame("Frame")
talentEvents:RegisterEvent("PLAYER_LOGIN")
talentEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
talentEvents:RegisterEvent("READY_CHECK")
talentEvents:RegisterEvent("PLAYER_TALENT_UPDATE")
talentEvents:SetScript("OnEvent", function(_, event)
    ScheduleCheck()
end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function TalentModule:BuildUI(parent, db)
    local COL_NAME_X = 12
    local ROW_HEIGHT = 32

    -- Section title
    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Talent Reminders")
    sectionTitle:SetTextColor(1, 0.82, 0)

    -- ---- Notification options (for unspent points box/chat) ----
    local notifyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notifyLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -36)
    notifyLabel:SetText("Unspent points notify via:")
    notifyLabel:SetTextColor(0.7, 0.7, 0.7)

    local cbChat = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbChat:SetSize(22, 22)
    cbChat:SetPoint("LEFT", notifyLabel, "RIGHT", 8, 1)
    cbChat:SetChecked(db.talents.notify.chat)
    cbChat:SetScript("OnClick", function(self)
        db.talents.notify.chat = self:GetChecked()
    end)

    local cbChatLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbChatLabel:SetPoint("LEFT", cbChat, "RIGHT", 2, 0)
    cbChatLabel:SetText("Chat")

    local cbScreen = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbScreen:SetSize(22, 22)
    cbScreen:SetPoint("LEFT", cbChatLabel, "RIGHT", 16, 0)
    cbScreen:SetChecked(db.talents.notify.screen)
    cbScreen:SetScript("OnClick", function(self)
        db.talents.notify.screen = self:GetChecked()
    end)

    local cbScreenLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbScreenLabel:SetPoint("LEFT", cbScreen, "RIGHT", 2, 0)
    cbScreenLabel:SetText("On-screen")

    -- Divider
    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, -60)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -60)

    -- ---- Check rows ----
    local y = -72

    -- Row 1: unspent talent points
    local cbUnspent = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbUnspent:SetSize(24, 24)
    cbUnspent:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbUnspent:SetChecked(db.talents.checks.unspentPoints)
    cbUnspent:SetScript("OnClick", function(self)
        db.talents.checks.unspentPoints = self:GetChecked()
    end)

    local unspentLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unspentLabel:SetPoint("LEFT", cbUnspent, "RIGHT", 6, 0)
    unspentLabel:SetText("Warn on unspent talent points")

    y = y - ROW_HEIGHT

    -- Row 2: show active build
    local cbActiveBuild = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbActiveBuild:SetSize(24, 24)
    cbActiveBuild:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbActiveBuild:SetChecked(db.talents.checks.showActiveBuild)
    cbActiveBuild:SetScript("OnClick", function(self)
        db.talents.checks.showActiveBuild = self:GetChecked()
    end)

    local activeBuildLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeBuildLabel:SetPoint("LEFT", cbActiveBuild, "RIGHT", 6, 0)
    activeBuildLabel:SetText("Show active talent build on login / ready check")

    y = y - 20

    local tleNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tleNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 30, y)
    tleNote:SetText("Uses TalentLoadoutEx names if the addon is loaded.")
    tleNote:SetTextColor(0.5, 0.5, 0.5)

    -- ---- Divider before build text appearance options ----
    y = y - 18
    local div2 = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div2:SetHeight(1)
    div2:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div2:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div2:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

    y = y - 14

    -- ---- Font selector ----
    local fontSectionLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSectionLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    fontSectionLabel:SetText("Build text appearance:")
    fontSectionLabel:SetTextColor(0.7, 0.7, 0.7)

    y = y - ROW_HEIGHT + 8

    local fontLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    fontLabel:SetText("Font:")

    -- Build font list (from LSM if available, else fallback)
    local fontNames = GetFontNames()
    local fontIndex = 1
    for i, name in ipairs(fontNames) do
        if name == db.talents.buildText.fontName then fontIndex = i; break end
    end

    local prevBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    prevBtn:SetSize(24, 22)
    prevBtn:SetText("<")
    prevBtn:SetPoint("LEFT", fontLabel, "RIGHT", 10, 0)

    local fontNameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontNameLabel:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
    fontNameLabel:SetWidth(130)
    fontNameLabel:SetJustifyH("CENTER")
    fontNameLabel:SetText(fontNames[fontIndex])

    local nextBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    nextBtn:SetSize(24, 22)
    nextBtn:SetText(">")
    nextBtn:SetPoint("LEFT", fontNameLabel, "RIGHT", 6, 0)

    prevBtn:SetScript("OnClick", function()
        fontIndex = ((fontIndex - 2) % #fontNames) + 1
        db.talents.buildText.fontName = fontNames[fontIndex]
        fontNameLabel:SetText(fontNames[fontIndex])
    end)
    nextBtn:SetScript("OnClick", function()
        fontIndex = (fontIndex % #fontNames) + 1
        db.talents.buildText.fontName = fontNames[fontIndex]
        fontNameLabel:SetText(fontNames[fontIndex])
    end)

    -- ---- Color picker ----
    local colorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("LEFT", nextBtn, "RIGHT", 20, 0)
    colorLabel:SetText("Color:")

    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)

    local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
    swatchBorder:SetAllPoints()
    swatchBorder:SetColorTexture(0.5, 0.5, 0.5, 1)

    local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
    swatchTex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    swatchTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    swatchTex:SetColorTexture(db.talents.buildText.r, db.talents.buildText.g, db.talents.buildText.b)

    swatch:SetScript("OnClick", function()
        local cfg = db.talents.buildText
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cfg.r, g = cfg.g, b = cfg.b,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                cfg.r, cfg.g, cfg.b = r, g, b
                swatchTex:SetColorTexture(r, g, b)
            end,
            cancelFunc = function(prev)
                cfg.r, cfg.g, cfg.b = prev.r, prev.g, prev.b
                swatchTex:SetColorTexture(prev.r, prev.g, prev.b)
            end,
        })
    end)
end

AR:RegisterModule("Talents", TalentModule)
