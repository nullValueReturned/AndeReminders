local AR   = AndeReminders
local Util = AR.Util

-- Warns when the delve companion Valeera Sanguinar has no combat role assigned.

local DelveModule = {}

local VALEERA_CREATURE_ID = "248567"
local forceNoRole = false  -- /ar norole: pretend she has no role, to try the alert without game state

local delveAlert = AR.UI.CreateAlert({
    name = "AndeRemindersDelveAlert", anchor = "delves", width = 420, fallbackY = -300,
})

local ALERT_TEXT = "|cFFFFCC00Valeera|r has no role assigned. Pick one in her companion settings."

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

function DelveModule:InitDB(db)
    if not db.delves then db.delves = {} end
    if db.delves.enabled == nil then db.delves.enabled = true end
    if not db.delves.notify then db.delves.notify = {} end
    if db.delves.notify.chat   == nil then db.delves.notify.chat   = true end
    if db.delves.notify.screen == nil then db.delves.notify.screen = true end
end

-- ---------------------------------------------------------------------------
-- Check logic
-- ---------------------------------------------------------------------------

local function InDelve()
    return C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress() or false
end

-- The party unit token of Valeera, matched on her creature ID so it works in any locale.
local function FindValeera()
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = Util.SafeString(UnitGUID(unit))
            if select(6, strsplit("-", guid)) == VALEERA_CREATURE_ID then return unit end
        end
    end
end

-- Pure decision, kept separate from the game API so it is easy to test: role is nil or "NONE"
-- when nothing is assigned.
function DelveModule.ShouldWarn(inDelve, valeeraUnit, role)
    return inDelve and valeeraUnit ~= nil and (role == nil or role == "NONE")
end

-- True when Valeera is with the player in a delve and has no role.
function DelveModule:IsRoleMissing()
    local unit = FindValeera()
    local role = unit and Util.SafeString(UnitGroupRolesAssigned(unit))
    if forceNoRole then role = "NONE" end
    return self.ShouldWarn(InDelve(), unit, role)
end

local warnedThisDelve = false  -- chat line only once per delve

function DelveModule:RunCheck()
    if not AR.db or not AR.db.delves.enabled then delveAlert:Reset() return end
    if InCombatLockdown() then return end

    if not InDelve() then
        warnedThisDelve = false
        delveAlert:Reset()
        return
    end

    local notify = AR.db.delves.notify
    if not self:IsRoleMissing() or not AR.UI.ShouldAlert(notify) then
        delveAlert:Reset()
        return
    end

    if notify.chat and not warnedThisDelve then
        Util.Print("Valeera has no role assigned.")
    end
    warnedThisDelve = true
    if notify.screen then delveAlert:Show(ALERT_TEXT, nil, notify) end
end

function DelveModule:TestAlert()
    delveAlert:Preview(ALERT_TEXT, nil, AR.db.delves.notify)
end

-- /ar norole
function DelveModule:DebugNoRole()
    forceNoRole = not forceNoRole
    warnedThisDelve = false
    Util.Print("Valeera role override " .. (forceNoRole and "on" or "off") .. " (only has an effect inside a delve).")
    self:RunCheck()
end

local ScheduleCheck = Util.Debounce(2, function()
    DelveModule:RunCheck()
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- The companion joins a moment after the zone loads, hence the debounce.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        delveAlert:Hide()
    else
        ScheduleCheck()
    end
end)

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

function DelveModule:BuildUI(parent, db)
    local X = 16

    AR.UI.Title(parent, "Delve Reminders", X, -16)
    AR.UI.NotifyRow(parent, X, -48, db.delves.notify, function() DelveModule:TestAlert() end)
    AR.UI.Divider(parent, -80, X - 4)

    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", X - 2, -92)
    cb:SetChecked(db.delves.enabled)
    cb:SetScript("OnClick", function(self)
        db.delves.enabled = self:GetChecked()
        DelveModule:RunCheck()
    end)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    label:SetText("Warn when Valeera Sanguinar has no role assigned")
end

AR:RegisterModule("Delves", DelveModule)
