local AR   = AndeReminders
local Util = AR.Util

-- The first settings tab: status of every reminder with its on/off switch, profiles, the window
-- scale and the anchor positions. Also hosts /ar check and /ar test.

local GeneralModule = {}

-- ---------------------------------------------------------------------------
-- Reminder status rows
-- ---------------------------------------------------------------------------

local GOOD, BAD, OFF = "|cFF40FF40", "|cFFFF6040", "|cFF777777"

-- One row per reminder: enabled() / setEnabled(v) read and write the module's own switch,
-- status() returns text, ok.
local function StatusRows(db)
    local function Mod(name) return AR.modules[name] end
    return {
        { label = "Talents",
          enabled = function() return db.talents.enabled end,
          setEnabled = function(v) db.talents.enabled = v end,
          status = function() return Mod("Talents"):GetStatus() end },
        { label = "Enchants",
          enabled = function() return db.enchants.enabled end,
          setEnabled = function(v) db.enchants.enabled = v; Mod("Enchants & Gems"):RunCheck(true) end,
          status = function() local text, ok = Mod("Enchants & Gems"):GetStatus() return text, ok end },
        { label = "Gems",
          enabled = function() return db.enchants.gems end,
          setEnabled = function(v) db.enchants.gems = v; Mod("Enchants & Gems"):RunCheck(true) end,
          status = function() local _, _, text, ok = Mod("Enchants & Gems"):GetStatus() return text, ok end },
        { label = "Gear",
          enabled = function() return db.gear.enabled end,
          setEnabled = function(v) db.gear.enabled = v; Mod("Gear"):RunCheck(true) end,
          status = function() local text, ok = Mod("Gear"):GetStatus() return text, ok end },
        { label = "Repair",
          enabled = function() return db.gear.checks.lowDurability end,
          setEnabled = function(v) db.gear.checks.lowDurability = v; Mod("Gear"):RunDurabilityCheck() end,
          status = function() local _, _, text, ok = Mod("Gear"):GetStatus() return text, ok end },
    }
end

-- /ar check: re-run every check (alerts update, chat stays quiet) and print the status of each.
function AR:RunAllChecks()
    local ench, gear, talents = AR.modules["Enchants & Gems"], AR.modules["Gear"], AR.modules["Talents"]
    if ench then ench:RunCheck(true) end
    if gear then gear:RunCheck(true); gear:RunDurabilityCheck() end
    if talents then talents:RunCheck(true) end

    for _, row in ipairs(StatusRows(AR.db)) do
        if row.enabled() then
            local text, ok = row.status()
            Util.Print(row.label .. ": " .. (ok and GOOD or BAD) .. text .. "|r")
        else
            Util.Print(row.label .. ": " .. OFF .. "off|r")
        end
    end
end

-- /ar test: an example of every alert, so positions, sounds and sizes can be checked.
function AR:ShowTestAlerts()
    for _, entry in ipairs(AR.registeredModules) do
        if entry.module.TestAlert then
            local ok, err = pcall(entry.module.TestAlert, entry.module)
            if not ok then geterrorhandler()(err) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

local LEFT_X, RIGHT_X = 16, 500

local function Header(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Label(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Button(parent, x, y, text, width, onClick)
    local b = AR.UI.Button(parent, text, width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildStatus(parent, db)
    Header(parent, LEFT_X, -52, "REMINDERS")

    local rows = StatusRows(db)
    local widgets = {}
    local y = -72
    for i, row in ipairs(rows) do
        AR.UI.RowStripe(parent, y + 4, 28, i, LEFT_X - 4)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_X - 2, y + 4)
        cb:SetScript("OnClick", function(self)
            row.setEnabled(self:GetChecked())
            GeneralModule.RefreshStatus()
        end)

        local name = Label(parent, LEFT_X + 30, y - 1, row.label)
        name:SetWidth(80)
        name:SetJustifyH("LEFT")

        local status = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        status:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_X + 120, y - 1)
        status:SetWidth(340)
        status:SetJustifyH("LEFT")
        status:SetWordWrap(false)

        widgets[i] = { cb = cb, status = status, row = row }
        y = y - 28
    end

    function GeneralModule.RefreshStatus()
        for _, w in ipairs(widgets) do
            local enabled = w.row.enabled()
            w.cb:SetChecked(enabled)
            if enabled then
                local text, ok = w.row.status()
                w.status:SetText((ok and GOOD or BAD) .. text .. "|r")
            else
                w.status:SetText(OFF .. "Off|r")
            end
        end
    end

    Button(parent, LEFT_X, y - 8, "Run checks now", 140, function() AR:RunAllChecks() end)
    Button(parent, LEFT_X + 150, y - 8, "Show example alerts", 170, function() AR:ShowTestAlerts() end)
end

local function BuildProfiles(parent)
    local y = -262
    AR.UI.Divider(parent, y + 12, LEFT_X - 4)
    Header(parent, LEFT_X, y, "PROFILE")

    y = y - 24
    Label(parent, LEFT_X, y - 4, "This character uses")
    local profileDrop = AR.UI.Dropdown(parent, 200, AR:GetProfileNames(),
        function() return AR.profileName end,
        function(name)
            if name == AR.profileName then return end
            AR.UI.Prompt({
                title = "Switch profile", accept = "Switch and reload",
                text = "Switch this character to the profile \"" .. name .. "\"? The UI reloads.",
                onAccept = function() AR:SwitchProfile(name) end,
            })
        end, { maxHeight = 200 })
    profileDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_X + 150, y)

    y = y - 36
    Button(parent, LEFT_X, y, "New profile...", 130, function()
        AR.UI.Prompt({
            title = "New profile", input = "", accept = "Create and switch",
            text = "Name for the new profile. It starts as a copy of \"" .. AR.profileName .. "\".",
            onAccept = function(name)
                name = name:match("^%s*(.-)%s*$")
                local ok, err = AR:CreateProfile(name)
                if ok then AR:SwitchProfile(name) else Util.Print(err) end
            end,
        })
    end)
    Button(parent, LEFT_X + 140, y, "Reset profile", 130, function()
        AR.UI.Prompt({
            title = "Reset profile", accept = "Reset and reload",
            text = "Reset \"" .. AR.profileName .. "\" to the default settings? Every setting, anchor position and BossMods entry in it is lost.",
            onAccept = function() AR:ResetProfile() end,
        })
    end)
    Button(parent, LEFT_X + 280, y, "Delete profile", 130, function()
        if AR.profileName == "Default" then
            Util.Print("the Default profile can't be deleted.")
            return
        end
        AR.UI.Prompt({
            title = "Delete profile", accept = "Delete and reload",
            text = "Delete \"" .. AR.profileName .. "\"? Characters using it go back to the Default profile.",
            onAccept = function() AR:DeleteProfile(AR.profileName) end,
        })
    end)

    y = y - 40
    Label(parent, LEFT_X, y - 4, "Copy settings from")
    local copySource
    for _, name in ipairs(AR:GetProfileNames()) do
        if name ~= AR.profileName then copySource = copySource or name end
    end
    local copyDrop = AR.UI.Dropdown(parent, 200, AR:GetProfileNames(),
        function() return copySource or AR.profileName end,
        function(name) copySource = name end, { maxHeight = 200 })
    copyDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_X + 150, y)
    Button(parent, LEFT_X + 360, y, "Copy", 70, function()
        if not copySource or copySource == AR.profileName then
            Util.Print("pick a different profile to copy from.")
            return
        end
        AR.UI.Prompt({
            title = "Copy settings", accept = "Copy and reload",
            text = "Replace every setting in \"" .. AR.profileName .. "\" with the ones from \"" .. copySource .. "\"? The UI reloads.",
            onAccept = function() AR:CopyProfileFrom(copySource) end,
        })
    end)

    y = y - 40
    Button(parent, LEFT_X, y, "Export profile", 130, function()
        local str, err = AR:ExportProfile()
        if not str then Util.Print(err); return end
        AR.UI.CopyDialog({ title = "Export profile", text = str, hint = "Ctrl+C to copy, then paste it wherever you like." })
    end)
    Button(parent, LEFT_X + 140, y, "Import profile", 130, function()
        AR.UI.CopyDialog({
            title = "Import profile", import = true, hint = "Paste an exported profile string, then click Import.",
            onImport = function(str)
                -- Validate now so a bad string is reported in the dialog, not after naming it.
                local ok, err = AR:ImportProfile(str, "\1check")
                if not ok then return err end
                AR.root.profiles["\1check"] = nil
                AR.UI.Prompt({
                    title = "Import profile", input = "Imported", accept = "Import and switch",
                    text = "Name for the imported profile.",
                    onAccept = function(name)
                        local created, createErr = AR:ImportProfile(str, name)
                        if created then AR:SwitchProfile(name:match("^%s*(.-)%s*$")) else Util.Print(createErr) end
                    end,
                })
            end,
        })
    end)

    y = y - 36
    local note = Header(parent, LEFT_X, y, "A profile holds every setting on every tab. Switching reloads the UI.")
    note:SetTextColor(1, 1, 1, 0.4)
end

local function BuildWindowAndAnchors(parent, db)
    -- Window scale -----------------------------------------------------------
    Header(parent, RIGHT_X, -52, "WINDOW")
    Label(parent, RIGHT_X, -80, "Settings window scale")

    local scaleText
    local function ShowScale()
        scaleText:SetText(math.floor((AR.root.ui.scale or 1) * 100 + 0.5) .. "%")
    end
    Button(parent, RIGHT_X + 190, -76, "-", 28, function()
        AR:SetWindowScale((AR.root.ui.scale or 1) - 0.05); ShowScale()
    end)
    scaleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleText:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X + 226, -80)
    scaleText:SetWidth(50)
    scaleText:SetJustifyH("CENTER")
    Button(parent, RIGHT_X + 282, -76, "+", 28, function()
        AR:SetWindowScale((AR.root.ui.scale or 1) + 0.05); ShowScale()
    end)
    ShowScale()

    -- Anchors ---------------------------------------------------------------
    AR.UI.Divider(parent, -112, RIGHT_X - 4)
    Header(parent, RIGHT_X, -130, "ANCHORS")
    local hint = Header(parent, RIGHT_X, -150, "Show the anchors, click one, then use the arrow keys (Shift = 10) to nudge it.")
    hint:SetTextColor(1, 1, 1, 0.4)

    local cbSnap = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbSnap:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X - 2, -170)
    cbSnap:SetChecked(db.anchorOpts.snap)
    cbSnap:SetScript("OnClick", function(self) db.anchorOpts.snap = self:GetChecked() end)
    local snapLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    snapLabel:SetPoint("LEFT", cbSnap, "RIGHT", 6, 0)
    snapLabel:SetText("Snap dragged anchors to a grid of")

    local gridBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    gridBox:SetSize(48, 24)
    gridBox:SetPoint("LEFT", snapLabel, "RIGHT", 10, 0)
    gridBox:SetAutoFocus(false)
    gridBox:SetNumeric(true)
    gridBox:SetMaxLetters(3)
    gridBox:SetText(tostring(db.anchorOpts.size or 10))
    local function SaveGrid(self)
        local v = math.max(1, tonumber(self:GetText()) or 10)
        db.anchorOpts.size = v
        self:SetText(tostring(v))
    end
    gridBox:SetScript("OnEnterPressed", function(self) SaveGrid(self); self:ClearFocus() end)
    gridBox:SetScript("OnEditFocusLost", SaveGrid)

    local snapUnit = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapUnit:SetPoint("LEFT", gridBox, "RIGHT", 8, 0)
    snapUnit:SetText("units")

    -- Exact positions (offset from the screen centre).
    local y = -214
    Header(parent, RIGHT_X, y, "POSITION (FROM SCREEN CENTRE)")
    y = y - 24

    local boxes = {}
    for i, def in ipairs(AR:GetAnchorDefs()) do
        AR.UI.RowStripe(parent, y + 4, 30, i, RIGHT_X - 4)
        local name = Label(parent, RIGHT_X + 4, y - 3, def.label)
        name:SetWidth(150)
        name:SetJustifyH("LEFT")

        local function MakeBox(x, axis)
            local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            box:SetSize(64, 24)
            box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + 1)
            box:SetAutoFocus(false)
            box:SetMaxLetters(6)
            local function Save(self)
                local v = tonumber(self:GetText())
                local pos = db.anchors[def.name]
                if v then
                    local x2, y2 = pos.x, pos.y
                    if axis == "x" then x2 = v else y2 = v end
                    AR:SetAnchorPosition(def.name, x2, y2)
                end
                self:SetText(tostring(db.anchors[def.name][axis]))
            end
            box:SetScript("OnEnterPressed", function(self) Save(self); self:ClearFocus() end)
            box:SetScript("OnEditFocusLost", Save)
            return box
        end

        local xLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        xLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X + 170, y - 6)
        xLabel:SetText("X")
        local yLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        yLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X + 266, y - 6)
        yLabel:SetText("Y")

        boxes[def.name] = { x = MakeBox(RIGHT_X + 184, "x"), y = MakeBox(RIGHT_X + 280, "y") }
        y = y - 30
    end

    local function RefreshBoxes()
        for name, pair in pairs(boxes) do
            local pos = db.anchors[name]
            if not pair.x:HasFocus() then pair.x:SetText(tostring(pos.x)) end
            if not pair.y:HasFocus() then pair.y:SetText(tostring(pos.y)) end
        end
    end
    AR.OnAnchorMoved = RefreshBoxes
    RefreshBoxes()

    Button(parent, RIGHT_X, y - 10, "Toggle anchors", 140, function() AR:ToggleAnchors() end)
    Button(parent, RIGHT_X + 150, y - 10, "Reset positions", 140, function()
        AR:ResetAnchors()
        RefreshBoxes()
    end)
end

function GeneralModule:BuildUI(parent, db)
    AR.UI.Title(parent, "General", LEFT_X, -16)

    BuildStatus(parent, db)
    BuildProfiles(parent)
    BuildWindowAndAnchors(parent, db)

    -- Statuses change with gear, loadout and zone while this tab is open.
    local since = 0
    parent:HookScript("OnShow", function() since = 0; GeneralModule.RefreshStatus() end)
    parent:HookScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 1 and not InCombatLockdown() then
            since = 0
            GeneralModule.RefreshStatus()
        end
    end)
    GeneralModule.RefreshStatus()
end

AR:RegisterModule("General", GeneralModule)
