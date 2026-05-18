local AR = AndeReminders

local EncounterModule = {}
local combatTextFrame = nil

local FONT_PATH = "Fonts\\FRIZQT__.TTF"

local ENTER_DEFAULT = { fontSize = 18, r = 245/255, g = 103/255, b = 93/255  }  -- #f5675d
local LEAVE_DEFAULT = { fontSize = 18, r = 109/255, g = 173/255, b = 252/255 }  -- #6dadfc

local MIDNIGHT_FALLS_ENCOUNTER_ID = 3183

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function EncounterModule:InitDB(db)
    if not db.encounter then db.encounter = {} end
    if not db.encounter.combatText then db.encounter.combatText = {} end
    if db.encounter.combatText.enabled == nil then db.encounter.combatText.enabled = false end

    if not db.encounter.enterText then db.encounter.enterText = {} end
    if db.encounter.enterText.fontSize == nil then db.encounter.enterText.fontSize = ENTER_DEFAULT.fontSize end
    if db.encounter.enterText.r == nil then db.encounter.enterText.r = ENTER_DEFAULT.r end
    if db.encounter.enterText.g == nil then db.encounter.enterText.g = ENTER_DEFAULT.g end
    if db.encounter.enterText.b == nil then db.encounter.enterText.b = ENTER_DEFAULT.b end

    if not db.encounter.leaveText then db.encounter.leaveText = {} end
    if db.encounter.leaveText.fontSize == nil then db.encounter.leaveText.fontSize = LEAVE_DEFAULT.fontSize end
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

    f:Hide()
    combatTextFrame = f
    return combatTextFrame
end

function EncounterModule:ShowCombatText(kind)
    local enc = AR.db and AR.db.encounter
    if not enc then return end

    local cfg, label
    if kind == "enter" then
        cfg   = enc.enterText
        label = "+Combat"
    else
        cfg   = enc.leaveText
        label = "-Combat"
    end

    local ctf = GetCombatTextFrame()
    ctf.text:ClearAllPoints()
    local anchor = AR.anchorFrames and AR.anchorFrames["encounter"]
    if anchor then
        ctf.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        ctf.text:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
    end

    ctf.text:SetFont(FONT_PATH, cfg.fontSize or 18, "OUTLINE")
    ctf.text:SetTextColor(cfg.r, cfg.g, cfg.b)
    ctf.text:SetText(label)

    ctf:Show()
    if ctf.hideTimer then ctf.hideTimer:Cancel() end
    ctf.hideTimer = C_Timer.NewTimer(2, function()
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
-- Settings UI
-- ---------------------------------------------------------------------------

local function BuildDirectionRow(parent, db, kind, yOffset, COL_NAME_X)
    local cfg = (kind == "enter") and db.encounter.enterText or db.encounter.leaveText
    local headText = (kind == "enter") and "Enter combat (\"+Combat\"):" or "Leave combat (\"-Combat\"):"

    local head = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, yOffset)
    head:SetText(headText)
    head:SetTextColor(0.9, 0.9, 0.9)

    local y = yOffset - 24

    local sizeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 18, y)
    sizeLabel:SetText("Size:")

    local sizeInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    sizeInput:SetSize(44, 20)
    sizeInput:SetPoint("LEFT", sizeLabel, "RIGHT", 6, -1)
    sizeInput:SetAutoFocus(false)
    sizeInput:SetNumeric(true)
    sizeInput:SetMaxLetters(3)
    sizeInput:SetText(tostring(cfg.fontSize or 18))

    local function SaveSize(self)
        local v = tonumber(self:GetText()) or 18
        if v < 6 then v = 6 elseif v > 200 then v = 200 end
        cfg.fontSize = v
        self:SetText(tostring(v))
    end
    sizeInput:SetScript("OnEnterPressed",  function(self) SaveSize(self); self:ClearFocus() end)
    sizeInput:SetScript("OnEditFocusLost", SaveSize)

    local colorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("LEFT", sizeInput, "RIGHT", 18, 1)
    colorLabel:SetText("Color:")

    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)

    local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
    swatchBorder:SetAllPoints()
    swatchBorder:SetColorTexture(0.5, 0.5, 0.5, 1)

    local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
    swatchTex:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    swatchTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    swatchTex:SetColorTexture(cfg.r, cfg.g, cfg.b)

    swatch:SetScript("OnClick", function()
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

    local previewBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    previewBtn:SetSize(100, 22)
    previewBtn:SetPoint("LEFT", swatch, "RIGHT", 18, 1)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        EncounterModule:ShowCombatText(kind)
    end)

    return y - 32
end

function EncounterModule:BuildUI(parent, db)
    local COL_NAME_X = 12

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Encounter Utilities")
    sectionTitle:SetTextColor(1, 0.82, 0)

    local y = -36

    local cbEnable = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbEnable:SetSize(24, 24)
    cbEnable:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbEnable:SetChecked(db.encounter.combatText.enabled)
    cbEnable:SetScript("OnClick", function(self)
        db.encounter.combatText.enabled = self:GetChecked()
    end)

    local enableLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLabel:SetPoint("LEFT", cbEnable, "RIGHT", 6, 0)
    enableLabel:SetText("Show combat in/out text")

    y = y - 28

    local div = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div:SetHeight(1)
    div:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

    y = y - 14

    y = BuildDirectionRow(parent, db, "enter", y, COL_NAME_X)
    y = BuildDirectionRow(parent, db, "leave", y, COL_NAME_X)

    local div2 = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    div2:SetHeight(1)
    div2:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8" })
    div2:SetBackdropColor(0.28, 0.28, 0.28, 1)
    div2:SetPoint("TOPLEFT",  parent, "TOPLEFT",  5, y)
    div2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, y)

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
