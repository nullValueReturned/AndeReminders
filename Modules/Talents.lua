local AR = AndeReminders

local TalentModule = {}
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
    if not db.talents.checks then db.talents.checks = {} end
    if db.talents.checks.showActiveBuild == nil then db.talents.checks.showActiveBuild = true end
    if not db.talents.buildText then db.talents.buildText = {} end
    if not db.talents.buildText.fontName then db.talents.buildText.fontName = DEFAULT_FONT_NAME end
    if db.talents.buildText.r       == nil then db.talents.buildText.r       = 1   end
    if db.talents.buildText.g       == nil then db.talents.buildText.g       = 0.8 end
    if db.talents.buildText.b       == nil then db.talents.buildText.b       = 0   end
    if db.talents.buildText.xOffset == nil then db.talents.buildText.xOffset = 0   end
    if db.talents.buildText.yOffset == nil then db.talents.buildText.yOffset = 0   end
end

-- ---------------------------------------------------------------------------
-- Active build flash text (no box, configurable font/color, center screen, 10s)
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
    fs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    f.text = fs

    f:Hide()
    buildTextFrame = f
    return buildTextFrame
end

function TalentModule:ShowBuildText(name, icon)
    local btf = GetBuildTextFrame()
    local cfg = AR.db and AR.db.talents and AR.db.talents.buildText
    local fontName = (cfg and cfg.fontName) or DEFAULT_FONT_NAME
    local r        = (cfg and cfg.r)        or 1
    local g        = (cfg and cfg.g)        or 0.8
    local b        = (cfg and cfg.b)        or 0
    local xOff     = (cfg and cfg.xOffset)  or 0
    local yOff     = (cfg and cfg.yOffset)  or 0
    btf.text:ClearAllPoints()
    btf.text:SetPoint("CENTER", UIParent, "CENTER", xOff, yOff)
    btf.text:SetFont(ResolveFontPath(fontName), 36, "OUTLINE")
    btf.text:SetTextColor(r, g, b)

    local displayText
    if icon then
        if type(icon) == "string" then
            displayText = string.format("|A:%s:36:36|a %s", icon, name)
        else
            displayText = string.format("|T%d:36:36|t %s", icon, name)
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

-- Returns the name and icon of the currently active talent loadout.
-- Uses TLX.GetLoadedData() (TalentLoadoutEx public API) if available, otherwise
-- falls back to the native WoW saved-config name (no icon in that case).
-- icon may be a numeric texture ID or an atlas name string.
local function GetActiveLoadoutInfo()
    -- Ensure TalentLoadoutEx is loaded if it's a demand-loaded addon.
    if not TLX and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("TalentLoadoutEx")
    end

    -- TalentLoadoutEx: TLX.GetLoadedData() returns the first data object whose
    -- talent string matches the current active configuration.
    if TLX and TLX.GetLoadedData then
        local data = TLX.GetLoadedData()
        if data and data.name then
            return data.name, data.icon
        end
    end

    -- Native WoW loadout name (no icon available)
    local specIndex = GetSpecialization()
    if not specIndex then return nil, nil end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then return nil, nil end
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
    local db = AR.db

    -- Show active build as flash text (ready check only)
    if db.talents.checks.showActiveBuild and isReadyCheck then
        local name, icon = GetActiveLoadoutInfo()
        if name then
            self:ShowBuildText(name, icon)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local talentEvents = CreateFrame("Frame")
talentEvents:RegisterEvent("READY_CHECK")
talentEvents:SetScript("OnEvent", function(_, event)
    TalentModule:RunCheck(true)
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

    -- ---- Check rows ----
    local y = -36

    -- Show active build
    local cbActiveBuild = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbActiveBuild:SetSize(24, 24)
    cbActiveBuild:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbActiveBuild:SetChecked(db.talents.checks.showActiveBuild)
    cbActiveBuild:SetScript("OnClick", function(self)
        db.talents.checks.showActiveBuild = self:GetChecked()
    end)

    local activeBuildLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeBuildLabel:SetPoint("LEFT", cbActiveBuild, "RIGHT", 6, 0)
    activeBuildLabel:SetText("Show active talent build on ready check")

    y = y - 20

    local tleNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tleNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 30, y)
    tleNote:SetText("Uses TalentLoadoutEx names if the addon is loaded.")
    tleNote:SetTextColor(0.5, 0.5, 0.5)

    -- ---- Divider before build text appearance options ----
    y = y - 18
    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

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

    local ITEM_HEIGHT  = 20
    local POPUP_WIDTH  = 200
    local MAX_LIST_H   = 300
    local SCROLLBAR_W  = 14

    local totalH      = #fontNames * ITEM_HEIGHT
    local visibleH    = math.min(totalH, MAX_LIST_H)
    local maxScroll   = math.max(0, totalH - visibleH)
    local hasScrollbar = maxScroll > 0

    -- Dropdown trigger button
    local dropBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dropBtn:SetSize(POPUP_WIDTH, 22)
    dropBtn:SetPoint("LEFT", fontLabel, "RIGHT", 10, 0)
    dropBtn:SetText(fontNames[fontIndex])

    -- Popup (child of parent so it rides with the settings window;
    -- elevated frame level so it renders above all sibling content)
    local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    popup:SetSize(POPUP_WIDTH, visibleH + 4)
    popup:SetFrameLevel(parent:GetFrameLevel() + 20)
    popup:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        tile = true, tileSize = 32,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:SetPoint("TOPLEFT", dropBtn, "BOTTOMLEFT", 0, -2)
    popup:Hide()

    -- Scroll frame (leave room on the right for scrollbar when needed)
    local scrollRightOffset = hasScrollbar and -(SCROLLBAR_W + 4) or -2
    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",     2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", scrollRightOffset, 2)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(POPUP_WIDTH - (hasScrollbar and (SCROLLBAR_W + 6) or 4))
    content:SetHeight(math.max(totalH, 1))
    scrollFrame:SetScrollChild(content)

    -- Item buttons
    local itemBtns = {}
    for i, name in ipairs(fontNames) do
        local btn = CreateFrame("Button", nil, content)
        btn:SetHeight(ITEM_HEIGHT)
        btn:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * ITEM_HEIGHT)
        btn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ITEM_HEIGHT)

        local hlTex = btn:CreateTexture(nil, "HIGHLIGHT")
        hlTex:SetAllPoints()
        hlTex:SetColorTexture(1, 1, 1, 0.10)

        local selTex = btn:CreateTexture(nil, "BACKGROUND")
        selTex:SetAllPoints()
        selTex:SetColorTexture(0.2, 0.4, 0.8, 0.25)
        selTex:SetShown(i == fontIndex)
        btn.selTex = selTex

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  btn, "LEFT",  6,  0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(name)

        btn:SetScript("OnClick", function()
            if itemBtns[fontIndex] then itemBtns[fontIndex].selTex:Hide() end
            fontIndex = i
            db.talents.buildText.fontName = name
            dropBtn:SetText(name)
            btn.selTex:Show()
            popup:Hide()
        end)

        itemBtns[i] = btn
    end

    -- Scrollbar
    local scrollBar
    if hasScrollbar then
        scrollBar = CreateFrame("Slider", nil, popup, "UIPanelScrollBarTemplate")
        scrollBar:SetWidth(SCROLLBAR_W)
        scrollBar:SetPoint("TOPRIGHT",    popup, "TOPRIGHT",    -2, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -2,  18)
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(0)
        scrollBar:SetValueStep(ITEM_HEIGHT)
        scrollBar:SetObeyStepOnDrag(true)
        scrollBar:SetScript("OnValueChanged", function(self, value)
            scrollFrame:SetVerticalScroll(value)
        end)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(_, delta)
            local cur = scrollBar:GetValue()
            local min, max = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(min, math.min(max, cur - delta * ITEM_HEIGHT * 3)))
        end)
    end

    -- Toggle popup; on open, scroll to show the selected item
    dropBtn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            popup:Show()
            if scrollBar and maxScroll > 0 then
                scrollBar:SetValue(math.min((fontIndex - 1) * ITEM_HEIGHT, maxScroll))
            end
        end
    end)

    -- Close popup when the settings tab is hidden
    parent:HookScript("OnHide", function() popup:Hide() end)

    -- ---- Color picker ----
    local colorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("LEFT", dropBtn, "RIGHT", 20, 0)
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

    -- ---- Offset inputs ----
    y = y - ROW_HEIGHT

    local xOffLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xOffLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    xOffLabel:SetText("X Offset:")

    local xOffBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    xOffBox:SetSize(55, 20)
    xOffBox:SetPoint("LEFT", xOffLabel, "RIGHT", 6, 0)
    xOffBox:SetAutoFocus(false)
    xOffBox:SetText(tostring(db.talents.buildText.xOffset))

    local yOffLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    yOffLabel:SetPoint("LEFT", xOffBox, "RIGHT", 14, 0)
    yOffLabel:SetText("Y Offset:")

    local yOffBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    yOffBox:SetSize(55, 20)
    yOffBox:SetPoint("LEFT", yOffLabel, "RIGHT", 6, 0)
    yOffBox:SetAutoFocus(false)
    yOffBox:SetText(tostring(db.talents.buildText.yOffset))

    -- Refreshes the text position live while preview is visible
    local function refreshPreviewPosition()
        if buildTextFrame and buildTextFrame:IsShown() then
            buildTextFrame.text:ClearAllPoints()
            buildTextFrame.text:SetPoint("CENTER", UIParent, "CENTER",
                db.talents.buildText.xOffset or 0,
                db.talents.buildText.yOffset or 0)
        end
    end

    local function commitXOff()
        local val = tonumber(xOffBox:GetText())
        if val then
            db.talents.buildText.xOffset = val
            refreshPreviewPosition()
        else
            xOffBox:SetText(tostring(db.talents.buildText.xOffset))
        end
        xOffBox:ClearFocus()
    end
    xOffBox:SetScript("OnEnterPressed", commitXOff)
    xOffBox:SetScript("OnEscapePressed", function()
        xOffBox:SetText(tostring(db.talents.buildText.xOffset))
        xOffBox:ClearFocus()
    end)

    local function commitYOff()
        local val = tonumber(yOffBox:GetText())
        if val then
            db.talents.buildText.yOffset = val
            refreshPreviewPosition()
        else
            yOffBox:SetText(tostring(db.talents.buildText.yOffset))
        end
        yOffBox:ClearFocus()
    end
    yOffBox:SetScript("OnEnterPressed", commitYOff)
    yOffBox:SetScript("OnEscapePressed", function()
        yOffBox:SetText(tostring(db.talents.buildText.yOffset))
        yOffBox:ClearFocus()
    end)

    -- ---- Preview toggle button ----
    local previewBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    previewBtn:SetSize(100, 22)
    previewBtn:SetPoint("LEFT", yOffBox, "RIGHT", 20, 0)
    previewBtn:SetText("Preview")

    previewBtn:SetScript("OnClick", function()
        local btf = GetBuildTextFrame()
        if btf:IsShown() then
            if btf.hideTimer then btf.hideTimer:Cancel(); btf.hideTimer = nil end
            btf:Hide()
            previewBtn:SetText("Preview")
        else
            local name, icon = GetActiveLoadoutInfo()
            TalentModule:ShowBuildText(name or "Your Talent Build", icon)
            -- Cancel the auto-hide so it stays until dismissed
            local btf2 = GetBuildTextFrame()
            if btf2.hideTimer then btf2.hideTimer:Cancel(); btf2.hideTimer = nil end
            previewBtn:SetText("Hide Preview")
        end
    end)

    -- Reset the button label if the settings tab is hidden while preview is up
    parent:HookScript("OnHide", function()
        previewBtn:SetText("Preview")
    end)
end

AR:RegisterModule("Talents", TalentModule)
