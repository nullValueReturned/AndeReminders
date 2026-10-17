local AR    = AndeReminders
local Util  = AR.Util
local Fonts = AR.Fonts

local TalentModule = {}
local buildTextFrame = nil

local STARTER_BUILD_NAME = TALENT_FRAME_DROP_DOWN_STARTER_BUILD or "Starter Build"

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function TalentModule:InitDB(db)
    if not db.talents then db.talents = {} end
    if not db.talents.checks then db.talents.checks = {} end
    if db.talents.checks.showActiveBuild == nil then db.talents.checks.showActiveBuild = true end
    if not db.talents.buildText then db.talents.buildText = {} end
    if not db.talents.buildText.fontName then db.talents.buildText.fontName = Fonts.DEFAULT_NAME end
    if db.talents.buildText.fontSize == nil then db.talents.buildText.fontSize = 36 end
    if db.talents.buildText.r == nil then db.talents.buildText.r = 1   end
    if db.talents.buildText.g == nil then db.talents.buildText.g = 0.8 end
    if db.talents.buildText.b == nil then db.talents.buildText.b = 0   end
end

-- ---------------------------------------------------------------------------
-- Build text flash (full-screen non-interactive frame, text at anchor position)
-- ---------------------------------------------------------------------------

local function GetBuildTextFrame()
    if buildTextFrame then return buildTextFrame end

    local f = CreateFrame("Frame", "AndeRemindersBuildText", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(2, -2)
    fs:SetJustifyH("CENTER")
    f.text = fs

    f:Hide()
    buildTextFrame = f
    return buildTextFrame
end

function TalentModule:ShowBuildText(name, icon)
    local btf = GetBuildTextFrame()
    local cfg = AR.db and AR.db.talents and AR.db.talents.buildText
    local fontName = (cfg and cfg.fontName) or Fonts.DEFAULT_NAME
    local fontSize = (cfg and cfg.fontSize) or 36
    local r = (cfg and cfg.r) or 1
    local g = (cfg and cfg.g) or 0.8
    local b = (cfg and cfg.b) or 0

    btf.text:ClearAllPoints()
    local anchor = AR.anchorFrames and AR.anchorFrames["talents"]
    if anchor then
        btf.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        btf.text:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end

    Fonts.Apply(btf.text, fontName, fontSize, "OUTLINE")
    btf.text:SetTextColor(r, g, b)

    local displayText
    if icon then
        if type(icon) == "string" then
            displayText = string.format("|A:%s:%d:%d|a %s", icon, fontSize, fontSize, name)
        else
            displayText = string.format("|T%d:%d:%d|t %s", icon, fontSize, fontSize, name)
        end
    else
        displayText = name
    end

    btf.text:SetText(displayText)
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

local function GetActiveLoadoutInfo()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
        C_AddOns.LoadAddOn("TalentLoadoutEx")
    end

    if TLX and TLX.GetLoadedData then
        local data = TLX.GetLoadedData()
        if data and data.name then
            return data.name, data.icon
        end
    end

    local _, specID = Util.GetSpec()
    if not specID then return nil, nil end

    -- Until the starter build is edited it is the active loadout and has no saved config.
    if C_ClassTalents.GetStarterBuildActive() then
        return STARTER_BUILD_NAME, nil
    end

    local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if configID then
        local info = C_Traits.GetConfigInfo(configID)
        if info and info.name and info.name ~= "" then
            return info.name, nil
        end
    end

    return nil, nil
end

function TalentModule:RunCheck(isReadyCheck)
    if not AR.db then return end
    if InCombatLockdown() then return end
    local db = AR.db
    if db.talents.checks.showActiveBuild and isReadyCheck then
        local name, icon = GetActiveLoadoutInfo()
        self:ShowBuildText(name or "unknown talent loadout", icon)
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local tlxInitDone = false

local talentEvents = CreateFrame("Frame")
talentEvents:RegisterEvent("READY_CHECK")
talentEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
talentEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
talentEvents:SetScript("OnEvent", function(self, event)
    if event == "READY_CHECK" then
        TalentModule:RunCheck(true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if buildTextFrame then buildTextFrame:Hide() end
    elseif event == "PLAYER_ENTERING_WORLD" and not tlxInitDone then
        tlxInitDone = true
        -- TalentLoadoutEx only has data once the talent frame has been shown once, so flash it
        -- open and shut shortly after login. Skipped in combat: it is a managed UI panel.
        C_Timer.After(2, function()
            if InCombatLockdown() then
                tlxInitDone = false  -- try again at the next loading screen
                return
            end
            if C_AddOns and C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
                C_AddOns.LoadAddOn("TalentLoadoutEx")
            end
            if PlayerSpellsFrame and not PlayerSpellsFrame:IsShown() then
                PlayerSpellsFrame:Show()
                PlayerSpellsFrame:Hide()
            end
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

function TalentModule:BuildUI(parent, db)
    local COL_NAME_X = 16
    local ROW_HEIGHT = 36

    AR.UI.Title(parent, "Talent Reminders", COL_NAME_X, -16)

    local y = -52

    local cbActiveBuild = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbActiveBuild:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
    cbActiveBuild:SetChecked(db.talents.checks.showActiveBuild)
    cbActiveBuild:SetScript("OnClick", function(self)
        db.talents.checks.showActiveBuild = self:GetChecked()
    end)

    local activeBuildLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeBuildLabel:SetPoint("LEFT", cbActiveBuild, "RIGHT", 6, 0)
    activeBuildLabel:SetText("Show active talent build on ready check")

    y = y - 26

    local tleNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tleNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 44, y)
    tleNote:SetText("Uses TalentLoadoutEx names if the addon is loaded.")

    y = y - 26
    AR.UI.Divider(parent, y, COL_NAME_X - 4)

    y = y - 18

    local fontSectionLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSectionLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    fontSectionLabel:SetText("BUILD TEXT APPEARANCE")

    y = y - ROW_HEIGHT + 4

    local fontLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    fontLabel:SetText("Font")

    local dropBtn = AR.UI.Dropdown(parent, 210, Fonts.List(),
        function() return db.talents.buildText.fontName end,
        function(name) db.talents.buildText.fontName = name end,
        { kind = "font", maxHeight = 300 })
    dropBtn:SetPoint("LEFT", fontLabel, "RIGHT", 12, 0)

    -- ---- Color picker ----
    local colorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("LEFT", dropBtn, "RIGHT", 24, 0)
    colorLabel:SetText("Color")

    local swatch = AR.UI.ColorSwatch(parent,
        function()
            local cfg = db.talents.buildText
            return cfg.r, cfg.g, cfg.b
        end,
        function(r, g, b)
            local cfg = db.talents.buildText
            cfg.r, cfg.g, cfg.b = r, g, b
        end, 24)
    swatch:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)

    -- ---- Font size input (same row as font/color) ----
    local sizeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("LEFT", swatch, "RIGHT", 24, 0)
    sizeLabel:SetText("Size")

    local sizeInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    sizeInput:SetSize(50, 24)
    sizeInput:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    sizeInput:SetAutoFocus(false)
    sizeInput:SetNumeric(true)
    sizeInput:SetMaxLetters(3)
    sizeInput:SetText(tostring(db.talents.buildText.fontSize or 36))

    local function SaveFontSize(self)
        local v = tonumber(self:GetText()) or 36
        if v < 6 then v = 6 elseif v > 200 then v = 200 end
        db.talents.buildText.fontSize = v
        self:SetText(tostring(v))
    end
    sizeInput:SetScript("OnEnterPressed",   function(self) SaveFontSize(self); self:ClearFocus() end)
    sizeInput:SetScript("OnEditFocusLost",  SaveFontSize)

    -- ---- Preview button (same row as font/color) ----
    local previewBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    previewBtn:SetSize(110, 24)
    previewBtn:SetPoint("LEFT", sizeInput, "RIGHT", 20, 0)
    previewBtn:SetText("Preview")

    local previewing = false

    local function HidePreview()
        local btf = GetBuildTextFrame()
        if btf.hideTimer then btf.hideTimer:Cancel(); btf.hideTimer = nil end
        btf:Hide()
        previewing = false
        previewBtn:SetText("Preview")
    end

    previewBtn:SetScript("OnClick", function()
        if GetBuildTextFrame():IsShown() then
            HidePreview()
        else
            local name, icon = GetActiveLoadoutInfo()
            TalentModule:ShowBuildText(name or "Your Talent Build", icon)
            local btf = GetBuildTextFrame()
            if btf.hideTimer then btf.hideTimer:Cancel(); btf.hideTimer = nil end
            previewing = true
            previewBtn:SetText("Hide Preview")
        end
    end)

    -- Leaving the tab (or closing the window) dismisses a preview this tab started.
    parent:HookScript("OnHide", function()
        if previewing then
            HidePreview()
        else
            previewBtn:SetText("Preview")
        end
    end)
end

AR:RegisterModule("Talents", TalentModule)
