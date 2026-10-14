local AR    = AndeReminders
local Fonts = AR.Fonts

local EncounterModule = {}
local combatTextFrame = nil

local DEFAULT_FONT_SIZE = 28
local ENTER_DEFAULT = { r = 245/255, g = 103/255, b = 93/255  }  -- #f5675d
local LEAVE_DEFAULT = { r = 109/255, g = 173/255, b = 252/255 }  -- #6dadfc

local MIDNIGHT_FALLS_ENCOUNTER_ID = 3183

-- Settings option -> the CVars it lowers to 0 for the duration of the fight.
local MIDNIGHT_FALLS_CVARS = {
    particleDensity   = { "graphicsParticleDensity",   "RaidGraphicsParticleDensity"   },
    projectedTextures = { "graphicsProjectedTextures", "RaidGraphicsProjectedTextures" },
}

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function EncounterModule:InitDB(db)
    if not db.encounter then db.encounter = {} end
    if not db.encounter.combatText then db.encounter.combatText = {} end
    if db.encounter.combatText.enabled  == nil then db.encounter.combatText.enabled  = false end
    if db.encounter.combatText.fontSize == nil then db.encounter.combatText.fontSize = DEFAULT_FONT_SIZE end
    if db.encounter.combatText.fontName == nil then db.encounter.combatText.fontName = Fonts.DEFAULT_NAME end

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
    local fontName = (shared and shared.fontName) or Fonts.DEFAULT_NAME

    local ctf = GetCombatTextFrame()
    ctf.text:ClearAllPoints()
    local anchor = AR.anchorFrames and AR.anchorFrames["encounter"]
    if anchor then
        ctf.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        ctf.text:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end

    Fonts.Apply(ctf.text, fontName, fontSize, "OUTLINE")
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

    -- Never re-read a CVar this module has already lowered: if an earlier override was not
    -- restored yet, the current value is our own 0 and the saved original must survive.
    local restore = mf.pendingRestore or {}
    for option, cvars in pairs(MIDNIGHT_FALLS_CVARS) do
        if mf[option] then
            for _, cvar in ipairs(cvars) do
                local current = GetCVar(cvar)
                if current ~= nil then  -- skip CVars this client does not have
                    if restore[cvar] == nil then restore[cvar] = current end
                    SetCVar(cvar, 0)
                end
            end
        end
    end

    if next(restore) ~= nil then mf.pendingRestore = restore end
end

local function RestoreMidnightFallsOverrides()
    local mf = AR.db and AR.db.encounter and AR.db.encounter.midnightFalls
    if not mf or not mf.pendingRestore then return end

    for cvar, value in pairs(mf.pendingRestore) do
        SetCVar(cvar, value)
    end

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

    -- Swatch bound to an { r, g, b } config table.
    local function ColorSwatchFor(cfg)
        return AR.UI.ColorSwatch(parent,
            function() return cfg.r, cfg.g, cfg.b end,
            function(r, g, b) cfg.r, cfg.g, cfg.b = r, g, b end)
    end

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

    local enterSwatch = ColorSwatchFor(db.encounter.enterText)
    enterSwatch:SetPoint("LEFT", enterLabel, "RIGHT", 6, 0)

    -- 3. Leave combat color
    local leaveLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leaveLabel:SetPoint("LEFT", enterSwatch, "RIGHT", 12, 0)
    leaveLabel:SetText("-Combat:")

    local leaveSwatch = ColorSwatchFor(db.encounter.leaveText)
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

    local fontDropdown = AR.UI.Dropdown(parent, 180, Fonts.List(),
        function() return db.encounter.combatText.fontName end,
        function(name) db.encounter.combatText.fontName = name end,
        { kind = "font", maxHeight = 300 })
    fontDropdown:SetPoint("LEFT", fontLabel, "RIGHT", 6, 0)

    y = y - 36

    AR.UI.Divider(parent, y)

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
