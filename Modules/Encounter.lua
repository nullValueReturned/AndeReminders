local AR = AndeReminders

local EncounterModule = {}
local combatTextFrame = nil

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

local DEFAULT_FONT_SIZE = 28
local ENTER_DEFAULT = { r = 245/255, g = 103/255, b = 93/255  }  -- #f5675d
local LEAVE_DEFAULT = { r = 109/255, g = 173/255, b = 252/255 }  -- #6dadfc

local MIDNIGHT_FALLS_ENCOUNTER_ID = 3183

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function EncounterModule:InitDB(db)
    if not db.encounter then db.encounter = {} end
    if not db.encounter.combatText then db.encounter.combatText = {} end
    if db.encounter.combatText.enabled  == nil then db.encounter.combatText.enabled  = false end
    if db.encounter.combatText.fontSize == nil then db.encounter.combatText.fontSize = DEFAULT_FONT_SIZE end
    if db.encounter.combatText.fontName == nil then db.encounter.combatText.fontName = DEFAULT_FONT_NAME end

    if not db.encounter.enterText then db.encounter.enterText = {} end
    if db.encounter.enterText.r == nil then db.encounter.enterText.r = ENTER_DEFAULT.r end
    if db.encounter.enterText.g == nil then db.encounter.enterText.g = ENTER_DEFAULT.g end
    if db.encounter.enterText.b == nil then db.encounter.enterText.b = ENTER_DEFAULT.b end

    if not db.encounter.leaveText then db.encounter.leaveText = {} end
    if db.encounter.leaveText.r == nil then db.encounter.leaveText.r = LEAVE_DEFAULT.r end
    if db.encounter.leaveText.g == nil then db.encounter.leaveText.g = LEAVE_DEFAULT.g end
    if db.encounter.leaveText.b == nil then db.encounter.leaveText.b = LEAVE_DEFAULT.b end

    if not db.encounter.midnightFalls then db.encounter.midnightFalls = {} end
    if db.encounter.midnightFalls.particleDensity   == nil then db.encounter.midnightFalls.particleDensity   = false end
    if db.encounter.midnightFalls.projectedTextures == nil then db.encounter.midnightFalls.projectedTextures = false end
    -- midnightFalls.pendingRestore is populated at ENCOUNTER_START with the
    -- previous CVar values and cleared at ENCOUNTER_END; it persists across
    -- reloads so a mid-fight /reload or DC can still restore the originals.
end

-- ---------------------------------------------------------------------------
-- Combat text flash (full-screen non-interactive frame, text at anchor position)
-- ---------------------------------------------------------------------------

local function GetCombatTextFrame()
    if combatTextFrame then return combatTextFrame end

    local f = CreateFrame("Frame", "AndeRemindersCombatText", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(2, -2)
    fs:SetJustifyH("CENTER")
    f.text = fs

    local ag = fs:CreateAnimationGroup()
    local translate = ag:CreateAnimation("Translation")
    translate:SetOffset(0, 150)
    translate:SetDuration(2)
    translate:SetSmoothing("OUT")
    f.anim = ag

    f:Hide()
    combatTextFrame = f
    return combatTextFrame
end

function EncounterModule:ShowCombatText(kind)
    local enc = AR.db and AR.db.encounter
    if not enc then return end

    local color, label
    if kind == "enter" then
        color = enc.enterText
        label = "+Combat"
    else
        color = enc.leaveText
        label = "-Combat"
    end

    local shared   = enc.combatText
    local fontSize = (shared and shared.fontSize) or DEFAULT_FONT_SIZE
    local fontName = (shared and shared.fontName) or DEFAULT_FONT_NAME

    local ctf = GetCombatTextFrame()
    ctf.text:ClearAllPoints()
    local anchor = AR.anchorFrames and AR.anchorFrames["encounter"]
    if anchor then
        ctf.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        ctf.text:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end

    ctf.text:SetFont(ResolveFontPath(fontName), fontSize, "OUTLINE")
    ctf.text:SetTextColor(color.r, color.g, color.b)
    ctf.text:SetText(label)

    ctf:Show()
    if ctf.anim then
        ctf.anim:Stop()
        ctf.anim:Play()
    end
    if ctf.hideTimer then ctf.hideTimer:Cancel() end
    ctf.hideTimer = C_Timer.NewTimer(2, function()
        if ctf.anim then ctf.anim:Stop() end
        ctf:Hide()
        ctf.hideTimer = nil
    end)
end

-- Stub so the module registry's RunCheck contract is satisfied.
function EncounterModule:RunCheck() end

-- ---------------------------------------------------------------------------
-- Midnight Falls CVar overrides
-- ---------------------------------------------------------------------------

local function ApplyMidnightFallsOverrides()
    local mf = AR.db and AR.db.encounter and AR.db.encounter.midnightFalls
    if not mf then return end
    if not mf.particleDensity and not mf.projectedTextures then return end

    local restore = {}
    if mf.particleDensity then
        restore.graphicsParticleDensity     = GetCVar("graphicsParticleDensity")
        restore.RaidGraphicsParticleDensity = GetCVar("RaidGraphicsParticleDensity")
        SetCVar("graphicsParticleDensity",     0)
        SetCVar("RaidGraphicsParticleDensity", 0)
    end
    if mf.projectedTextures then
        restore.graphicsProjectedTextures     = GetCVar("graphicsProjectedTextures")
        restore.RaidGraphicsProjectedTextures = GetCVar("RaidGraphicsProjectedTextures")
        SetCVar("graphicsProjectedTextures",     0)
        SetCVar("RaidGraphicsProjectedTextures", 0)
    end
    mf.pendingRestore = restore
end

local function RestoreMidnightFallsOverrides()
    local mf = AR.db and AR.db.encounter and AR.db.encounter.midnightFalls
    if not mf or not mf.pendingRestore then return end

    local r = mf.pendingRestore
    if r.graphicsParticleDensity     then SetCVar("graphicsParticleDensity",     r.graphicsParticleDensity)     end
    if r.RaidGraphicsParticleDensity then SetCVar("RaidGraphicsParticleDensity", r.RaidGraphicsParticleDensity) end
    if r.graphicsProjectedTextures     then SetCVar("graphicsProjectedTextures",     r.graphicsProjectedTextures)     end
    if r.RaidGraphicsProjectedTextures then SetCVar("RaidGraphicsProjectedTextures", r.RaidGraphicsProjectedTextures) end

    mf.pendingRestore = nil
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:RegisterEvent("ENCOUNTER_START")
combatEvents:RegisterEvent("ENCOUNTER_END")
combatEvents:RegisterEvent("PLAYER_LOGIN")
combatEvents:SetScript("OnEvent", function(self, event, ...)
    local enc = AR.db and AR.db.encounter
    if not enc then return end

    if event == "PLAYER_REGEN_DISABLED" then
        if enc.combatText and enc.combatText.enabled then
            EncounterModule:ShowCombatText("enter")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if enc.combatText and enc.combatText.enabled then
            EncounterModule:ShowCombatText("leave")
        end
    elseif event == "ENCOUNTER_START" then
        local encounterID = ...
        if encounterID == MIDNIGHT_FALLS_ENCOUNTER_ID then
            ApplyMidnightFallsOverrides()
        end
    elseif event == "ENCOUNTER_END" then
        local encounterID = ...
        if encounterID == MIDNIGHT_FALLS_ENCOUNTER_ID then
            RestoreMidnightFallsOverrides()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Recover from a mid-encounter reload / disconnect.
        RestoreMidnightFallsOverrides()
    end
end)

-- ---------------------------------------------------------------------------
-- Settings UI helpers
-- ---------------------------------------------------------------------------

local function BuildColorSwatch(parent, cfg)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(22, 22)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 1)

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    tex:SetColorTexture(cfg.r, cfg.g, cfg.b)

    swatch:SetScript("OnClick", function()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cfg.r, g = cfg.g, b = cfg.b,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                cfg.r, cfg.g, cfg.b = r, g, b
                tex:SetColorTexture(r, g, b)
            end,
            cancelFunc = function(prev)
                cfg.r, cfg.g, cfg.b = prev.r, prev.g, prev.b
                tex:SetColorTexture(prev.r, prev.g, prev.b)
            end,
        })
    end)

    return swatch
end

local function BuildFontDropdown(parent, db, anchorTo)
    local fontNames = GetFontNames()
    local fontIndex = 1
    for i, name in ipairs(fontNames) do
        if name == db.encounter.combatText.fontName then fontIndex = i; break end
    end

    local ITEM_HEIGHT  = 20
    local POPUP_WIDTH  = 180
    local MAX_LIST_H   = 300
    local SCROLLBAR_W  = 14

    local totalH       = #fontNames * ITEM_HEIGHT
    local visibleH     = math.min(totalH, MAX_LIST_H)
    local maxScroll    = math.max(0, totalH - visibleH)
    local hasScrollbar = maxScroll > 0

    local dropBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dropBtn:SetSize(POPUP_WIDTH, 22)
    dropBtn:SetPoint("LEFT", anchorTo, "RIGHT", 6, 0)
    local bfs = dropBtn:GetFontString(); bfs:ClearAllPoints(); bfs:SetPoint("LEFT",dropBtn,"LEFT",8,0); bfs:SetPoint("RIGHT",dropBtn,"RIGHT",-18,0); bfs:SetJustifyH("LEFT")
    local arrowFs = dropBtn:CreateFontString(nil,"OVERLAY","GameFontNormal"); arrowFs:SetPoint("RIGHT",dropBtn,"RIGHT",-5,0); arrowFs:SetText("▼")
    dropBtn:SetText(fontNames[fontIndex])

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

    local scrollRightOffset = hasScrollbar and -(SCROLLBAR_W + 4) or -2
    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",     2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", scrollRightOffset, 2)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(POPUP_WIDTH - (hasScrollbar and (SCROLLBAR_W + 6) or 4))
    content:SetHeight(math.max(totalH, 1))
    scrollFrame:SetScrollChild(content)

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
        lbl:SetFont(ResolveFontPath(name), 12, "")

        btn:SetScript("OnClick", function()
            if itemBtns[fontIndex] then itemBtns[fontIndex].selTex:Hide() end
            fontIndex = i
            db.encounter.combatText.fontName = name
            dropBtn:SetText(name)
            btn.selTex:Show()
            popup:Hide()
        end)

        itemBtns[i] = btn
    end

    if hasScrollbar then
        local scrollBar = CreateFrame("Slider", nil, popup)
        scrollBar:SetOrientation("VERTICAL")
        scrollBar:SetWidth(SCROLLBAR_W)
        scrollBar:SetPoint("TOPRIGHT",    popup, "TOPRIGHT",    -2, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -2,  18)
        local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture("Interface/Buttons/UI-ScrollBar-Knob")
        thumb:SetSize(14, 14)
        scrollBar:SetThumbTexture(thumb)
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
            local mn, mx = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(mn, math.min(mx, cur - delta * ITEM_HEIGHT * 3)))
        end)

        dropBtn:SetScript("OnClick", function()
            if popup:IsShown() then
                popup:Hide()
            else
                popup:Show()
                scrollBar:SetValue(math.min((fontIndex - 1) * ITEM_HEIGHT, maxScroll))
            end
        end)
    else
        dropBtn:SetScript("OnClick", function()
            if popup:IsShown() then popup:Hide() else popup:Show() end
        end)
    end

    parent:HookScript("OnHide", function() popup:Hide() end)

    return dropBtn
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function EncounterModule:BuildUI(parent, db)
    local COL_NAME_X = 12

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Encounter Utilities")
    sectionTitle:SetTextColor(1, 0.82, 0)

    local y = -40

    local rowLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    rowLabel:SetText("Combat in/out text:")
    rowLabel:SetTextColor(0.7, 0.7, 0.7)

    y = y - 22

    -- 1. Enable checkbox
    local cbEnable = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbEnable:SetSize(24, 24)
    cbEnable:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbEnable:SetChecked(db.encounter.combatText.enabled)
    cbEnable:SetScript("OnClick", function(self)
        db.encounter.combatText.enabled = self:GetChecked()
    end)

    local enableLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLabel:SetPoint("LEFT", cbEnable, "RIGHT", 4, 0)
    enableLabel:SetText("Enabled")

    -- 2. Enter combat color
    local enterLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enterLabel:SetPoint("LEFT", enableLabel, "RIGHT", 16, 0)
    enterLabel:SetText("+Combat:")

    local enterSwatch = BuildColorSwatch(parent, db.encounter.enterText)
    enterSwatch:SetPoint("LEFT", enterLabel, "RIGHT", 6, 0)

    -- 3. Leave combat color
    local leaveLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leaveLabel:SetPoint("LEFT", enterSwatch, "RIGHT", 12, 0)
    leaveLabel:SetText("-Combat:")

    local leaveSwatch = BuildColorSwatch(parent, db.encounter.leaveText)
    leaveSwatch:SetPoint("LEFT", leaveLabel, "RIGHT", 6, 0)

    -- 4. Shared font size
    local sizeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("LEFT", leaveSwatch, "RIGHT", 14, 0)
    sizeLabel:SetText("Size:")

    local sizeInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    sizeInput:SetSize(40, 20)
    sizeInput:SetPoint("LEFT", sizeLabel, "RIGHT", 6, -1)
    sizeInput:SetAutoFocus(false)
    sizeInput:SetNumeric(true)
    sizeInput:SetMaxLetters(3)
    sizeInput:SetText(tostring(db.encounter.combatText.fontSize or DEFAULT_FONT_SIZE))

    local function SaveSize(self)
        local v = tonumber(self:GetText()) or DEFAULT_FONT_SIZE
        if v < 6 then v = 6 elseif v > 200 then v = 200 end
        db.encounter.combatText.fontSize = v
        self:SetText(tostring(v))
    end
    sizeInput:SetScript("OnEnterPressed",  function(self) SaveSize(self); self:ClearFocus() end)
    sizeInput:SetScript("OnEditFocusLost", SaveSize)

    -- 5. Font dropdown (shared)
    local fontLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("LEFT", sizeInput, "RIGHT", 14, 1)
    fontLabel:SetText("Font:")

    BuildFontDropdown(parent, db, fontLabel)

    y = y - 36

    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

    y = y - 14

    local mfHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mfHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    mfHeader:SetText("Midnight Falls (Encounter 3183):")
    mfHeader:SetTextColor(0.9, 0.9, 0.9)

    y = y - 24

    local cbParticles = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbParticles:SetSize(24, 24)
    cbParticles:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 18, y + 3)
    cbParticles:SetChecked(db.encounter.midnightFalls.particleDensity)
    cbParticles:SetScript("OnClick", function(self)
        db.encounter.midnightFalls.particleDensity = self:GetChecked()
    end)

    local cbParticlesLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbParticlesLabel:SetPoint("LEFT", cbParticles, "RIGHT", 6, 0)
    cbParticlesLabel:SetText("Disable particle density during encounter (restores after)")

    y = y - 24

    local cbTextures = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbTextures:SetSize(24, 24)
    cbTextures:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 18, y + 3)
    cbTextures:SetChecked(db.encounter.midnightFalls.projectedTextures)
    cbTextures:SetScript("OnClick", function(self)
        db.encounter.midnightFalls.projectedTextures = self:GetChecked()
    end)

    local cbTexturesLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbTexturesLabel:SetPoint("LEFT", cbTextures, "RIGHT", 6, 0)
    cbTexturesLabel:SetText("Disable projected textures during encounter (restores after)")
end

AR:RegisterModule("Encounter util", EncounterModule)
