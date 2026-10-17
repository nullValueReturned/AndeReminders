local AR    = AndeReminders
local Util  = AR.Util
local Fonts = AR.Fonts

local TalentModule = {}
local buildTextFrame = nil

local STARTER_BUILD_NAME = TALENT_FRAME_DROP_DOWN_STARTER_BUILD or "Starter Build"
local MAX_RULES_PER_SPEC = 10

-- Content a loadout rule can apply to. The most specific matching rule wins (higher rank).
-- Tests take the instanceType and difficultyID from GetInstanceInfo(); "instance" rules
-- instead match the instanceID they were created in.
local SCOPES = {
    { key = "raid",      rank = 1, label = "Any raid",
      test = function(t) return t == "raid" end },
    { key = "raid17",    rank = 2, label = "Raid - LFR",
      test = function(t, d) return t == "raid" and (d == 17 or d == 7) end },
    { key = "raid14",    rank = 2, label = "Raid - Normal",
      test = function(t, d) return t == "raid" and d == 14 end },
    { key = "raid15",    rank = 2, label = "Raid - Heroic",
      test = function(t, d) return t == "raid" and d == 15 end },
    { key = "raid16",    rank = 2, label = "Raid - Mythic",
      test = function(t, d) return t == "raid" and d == 16 end },
    { key = "mplus",     rank = 2, label = "Mythic+ keystone dungeon",
      test = function(t, d) return t == "party" and d == 8 end },
    { key = "dungeon23", rank = 2, label = "Mythic dungeon (no keystone)",
      test = function(t, d) return t == "party" and d == 23 end },
    { key = "dungeon2",  rank = 2, label = "Heroic dungeon",
      test = function(t, d) return t == "party" and d == 2 end },
    { key = "dungeon1",  rank = 2, label = "Normal dungeon",
      test = function(t, d) return t == "party" and d == 1 end },
    { key = "delve",     rank = 2, label = "Delves",
      test = function(_, d) return d == 208 end },
    { key = "instance",  rank = 3, label = "The instance I'm in now (any difficulty)" },
}
local SCOPE_BY_KEY = {}
for _, scope in ipairs(SCOPES) do SCOPE_BY_KEY[scope.key] = scope end

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function TalentModule:InitDB(db)
    if not db.talents then db.talents = {} end
    if db.talents.enabled == nil then db.talents.enabled = true end
    if not db.talents.checks then db.talents.checks = {} end
    if not db.talents.rules then db.talents.rules = {} end  -- expected loadout per content, see SCOPES
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

-- color (optional) = { r, g, b } overriding the configured text color, e.g. for warnings.
function TalentModule:ShowBuildText(name, icon, color)
    local btf = GetBuildTextFrame()
    local cfg = AR.db and AR.db.talents and AR.db.talents.buildText
    local fontName = (cfg and cfg.fontName) or Fonts.DEFAULT_NAME
    local fontSize = (cfg and cfg.fontSize) or 36
    local r = (cfg and cfg.r) or 1
    local g = (cfg and cfg.g) or 0.8
    local b = (cfg and cfg.b) or 0
    if color then r, g, b = color[1], color[2], color[3] end

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

-- The loadout name the player's rules expect for the content they are standing in (and
-- their current spec), or nil when no rule applies.
function TalentModule:GetExpectedLoadout()
    local rules = AR.db and AR.db.talents and AR.db.talents.rules
    local _, specID = Util.GetSpec()
    if not rules or not specID then return nil end

    local _, instType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local bestRank, expected = 0, nil
    for _, rule in ipairs(rules) do
        local scope = SCOPE_BY_KEY[rule.scope]
        if scope and rule.specID == specID and scope.rank > bestRank then
            local hit
            if rule.scope == "instance" then
                hit = rule.instanceID == instanceID
            else
                hit = scope.test(instType, difficultyID)
            end
            if hit then bestRank, expected = scope.rank, rule.loadout end
        end
    end
    return expected
end

function TalentModule:RunCheck(isReadyCheck)
    if not AR.db then return end
    if InCombatLockdown() then return end
    if not isReadyCheck then return end
    local db = AR.db
    if not db.talents.enabled then return end

    local name, icon = GetActiveLoadoutInfo()
    local expected = self:GetExpectedLoadout()
    if expected and expected ~= name then
        local text = "Wrong talent loadout!\nSwitch to: " .. expected
        if name then text = text .. "\n(active: " .. name .. ")" end
        self:ShowBuildText(text, nil, { 1, 0.25, 0.25 })
        Util.Print("wrong talent loadout: expected " .. expected .. ", active " .. (name or "unknown") .. ".")
    elseif db.talents.checks.showActiveBuild then
        self:ShowBuildText(name or "unknown talent loadout", icon)
    end
end

-- Example warning for the Preview button and /ar test.
function TalentModule:TestAlert()
    self:ShowBuildText("Wrong talent loadout!\nSwitch to: Example Loadout\n(active: Current Loadout)", nil, { 1, 0.25, 0.25 })
end

-- Dashboard line: text, ok.
function TalentModule:GetStatus()
    local name = GetActiveLoadoutInfo()
    local expected = self:GetExpectedLoadout()
    if expected and expected ~= name then
        return "Expected " .. expected .. ", active " .. (name or "unknown"), false
    end
    return "Active: " .. (name or "unknown") .. (expected and "  (matches your rule)" or ""), true
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

    local warnBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    warnBtn:SetSize(130, 24)
    warnBtn:SetPoint("LEFT", previewBtn, "RIGHT", 8, 0)
    warnBtn:SetText("Preview warning")
    warnBtn:SetScript("OnClick", function() TalentModule:TestAlert() end)

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

    ---------------------------------------------------------------------------
    -- Expected loadout per content
    ---------------------------------------------------------------------------
    y = y - 40
    AR.UI.Divider(parent, y, COL_NAME_X - 4)

    y = y - 18
    local rulesHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulesHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    rulesHeader:SetText("EXPECTED LOADOUT BY CONTENT")

    y = y - 20
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    hint:SetWidth(760)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetTextColor(1, 1, 1, 0.55)
    hint:SetText("On a ready check you get a red warning if your active loadout is not the one set here for the " ..
        "content you are in. To add one: 1) switch to the loadout you want, 2) pick the content, 3) click Add rule.")

    y = y - 40
    local selectedScope = SCOPES[1].key
    local scopeOptions = {}
    for _, scope in ipairs(SCOPES) do table.insert(scopeOptions, { label = scope.label, value = scope.key }) end

    local scopeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y - 5)
    scopeLabel:SetText("Content")

    local scopeDrop = AR.UI.Dropdown(parent, 280, scopeOptions,
        function() return selectedScope end,
        function(value) selectedScope = value end,
        { maxHeight = 280 })
    scopeDrop:SetPoint("LEFT", scopeLabel, "RIGHT", 12, 0)

    local addBtn = AR.UI.Button(parent, "Add rule for my current loadout", 230, 24)
    addBtn:SetPoint("LEFT", scopeDrop, "RIGHT", 12, 0)

    y = y - 32
    local statusText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    statusText:SetWidth(860)
    statusText:SetJustifyH("LEFT")

    y = y - 28
    local RULE_H   = 24
    local LOADOUT_X, ACTIONS_X = 300, 600
    local colScope = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colScope:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y)
    colScope:SetText("RULES FOR YOUR CURRENT SPEC")
    local colLoadout = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colLoadout:SetPoint("TOPLEFT", parent, "TOPLEFT", LOADOUT_X, y)
    colLoadout:SetText("EXPECTED LOADOUT")

    local LIST_TOP = y - 20
    local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, LIST_TOP - 4)
    emptyText:SetTextColor(1, 1, 1, 0.45)
    emptyText:SetText("No rules for this spec yet.")

    local ruleRows = {}
    local RefreshRules

    local function ScopeText(rule)
        if rule.scope == "instance" then return "Instance: " .. (rule.instanceName or "?") end
        local scope = SCOPE_BY_KEY[rule.scope]
        return scope and scope.label or rule.scope
    end

    local function GetRuleRow(i)
        if ruleRows[i] then return ruleRows[i] end
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(ACTIONS_X + 200, RULE_H)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 4, LIST_TOP - (i - 1) * RULE_H)

        if i % 2 == 1 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.035)
        end

        row.scope = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.scope:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.scope:SetWidth(LOADOUT_X - COL_NAME_X - 12)
        row.scope:SetJustifyH("LEFT")
        row.scope:SetWordWrap(false)

        row.loadout = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.loadout:SetPoint("LEFT", row, "LEFT", LOADOUT_X - COL_NAME_X + 4, 0)
        row.loadout:SetWidth(ACTIONS_X - LOADOUT_X - 12)
        row.loadout:SetJustifyH("LEFT")
        row.loadout:SetWordWrap(false)
        row.loadout:SetTextColor(1, 0.8, 0)

        row.update = AR.UI.Button(row, "Use current", 90, 20)
        row.update:SetPoint("LEFT", row, "LEFT", ACTIONS_X - COL_NAME_X + 4, 0)
        row.update:SetScript("OnClick", function()
            local name = GetActiveLoadoutInfo()
            if not name then Util.Print("no active talent loadout detected."); return end
            row.rule.loadout = name
            RefreshRules()
        end)

        row.delete = AR.UI.Button(row, "Remove", 70, 20)
        row.delete:SetPoint("LEFT", row.update, "RIGHT", 6, 0)
        row.delete:SetScript("OnClick", function()
            for idx, r in ipairs(db.talents.rules) do
                if r == row.rule then table.remove(db.talents.rules, idx) break end
            end
            RefreshRules()
        end)

        ruleRows[i] = row
        return row
    end

    local function RefreshStatus()
        local active = GetActiveLoadoutInfo()
        local instName, instType, _, diffName = GetInstanceInfo()
        local where = (instType == "none" or instName == "") and "the open world"
            or (instName .. ((diffName and diffName ~= "") and (" (" .. diffName .. ")") or ""))
        local text = "Active loadout: |cFFFFCC00" .. (active or "unknown") .. "|r      You are in: |cFFFFFFFF" .. where .. "|r"

        local expected = TalentModule:GetExpectedLoadout()
        if expected and expected == active then
            text = text .. "      |cFF40FF40Matches the rule for here|r"
        elseif expected then
            text = text .. "      |cFFFF4040Rule for here expects: " .. expected .. "|r"
        end
        statusText:SetText(text)
    end

    function RefreshRules()
        local _, specID = Util.GetSpec()
        local shown = 0
        for _, rule in ipairs(db.talents.rules) do
            if rule.specID == specID then
                shown = shown + 1
                local row = GetRuleRow(shown)
                row.rule = rule
                row.scope:SetText(ScopeText(rule))
                row.loadout:SetText(rule.loadout)
                row:Show()
            end
        end
        for i = shown + 1, #ruleRows do ruleRows[i]:Hide() end
        emptyText:SetShown(shown == 0)
        RefreshStatus()
    end

    addBtn:SetScript("OnClick", function()
        local _, specID = Util.GetSpec()
        local loadout = GetActiveLoadoutInfo()
        if not specID or not loadout then
            Util.Print("no active talent loadout detected.")
            return
        end

        local rule = { specID = specID, scope = selectedScope, loadout = loadout }
        if selectedScope == "instance" then
            local name, instType, _, _, _, _, _, instanceID = GetInstanceInfo()
            if instType == "none" then
                Util.Print("enter the dungeon or raid first, then add this rule.")
                return
            end
            rule.instanceID, rule.instanceName = instanceID, name
        end

        -- Same content again just replaces the loadout.
        local count = 0
        for idx, existing in ipairs(db.talents.rules) do
            if existing.specID == specID then
                if existing.scope == rule.scope and existing.instanceID == rule.instanceID then
                    db.talents.rules[idx] = rule
                    RefreshRules()
                    return
                end
                count = count + 1
            end
        end
        if count >= MAX_RULES_PER_SPEC then
            Util.Print("that spec already has " .. MAX_RULES_PER_SPEC .. " rules; remove one first.")
            return
        end
        table.insert(db.talents.rules, rule)
        RefreshRules()
    end)

    -- The loadout, zone and spec can all change while this tab is open: keep it current.
    local sinceRefresh = 0
    parent:HookScript("OnShow", function() sinceRefresh = 0; RefreshRules() end)
    parent:HookScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= 1 and not InCombatLockdown() then
            sinceRefresh = 0
            RefreshRules()
        end
    end)
    RefreshRules()

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
