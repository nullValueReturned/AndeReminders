local AR   = AndeReminders
local Util = AR.Util

local QoLModule = {}

local LDB        -- LibDataBroker-1.1 instance
local LDBIcon    -- LibDBIcon-1.0 instance
local vaultDataObject

local LDB_NAME       = "AndeRemindersGreatVault"
local ICON_AVAILABLE = 3753262
local ICON_PENDING   = 3753264
local ITEM_COLOR     = "|cFFA335EE"  -- epic purple

-- ---------------------------------------------------------------------------
-- Vault data + tooltip
-- ---------------------------------------------------------------------------

-- Returns the example reward item levels for the raid, Mythic+ and delve rows (indexed by slot,
-- so a locked slot leaves a gap) plus the highest one. Rows are told apart by activity type, the
-- same way Blizzard's own vault frame does it, not by their position in the activities list.
local function getVaultData()
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then return {}, {}, {}, nil, {} end

    local threshold = Enum.WeeklyRewardChestThresholdType
    local raidData, mplusData, delveData = {}, {}, {}
    local rowByType = {
        [threshold.Raid]       = raidData,
        [threshold.Activities] = mplusData,
        [threshold.World]      = delveData,
    }
    local highest
    -- progress[row] = { done = progress so far, nextAt = threshold of the next locked slot }
    local progress = {}

    for _, activity in ipairs(activities) do
        local row = rowByType[activity.type]
        if row then
            local p = progress[row] or { done = 0 }
            progress[row] = p
            p.done = math.max(p.done, activity.progress or 0)
            local threshold = activity.threshold or 0
            if (activity.progress or 0) < threshold and (not p.nextAt or threshold < p.nextAt) then
                p.nextAt = threshold
            end
        end
        local itemLink = row and C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
        if itemLink then
            local ilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
            if ilvl then
                row[activity.index] = ilvl
                if not highest or ilvl > highest then highest = ilvl end
            end
        end
    end

    return raidData, mplusData, delveData, highest, progress
end

-- "3/4" towards the next locked slot, or "done" once all three are unlocked.
local function progressText(p)
    if not p then return "" end
    if not p.nextAt then return "  |cFF40FF40done|r" end
    return string.format("  |cFF999999%d/%d|r", p.done, p.nextAt)
end

local function formatLine(data, p)
    local function cell(v)
        if v then return ITEM_COLOR .. v .. "|r" end
        return "xxx"
    end
    return string.format("%s || %s || %s%s", cell(data[1]), cell(data[2]), cell(data[3]), progressText(p))
end

local function constructTooltip(tooltip)
    local raidData, mplusData, delveData, highest, progress = getVaultData()

    tooltip:ClearLines()
    tooltip:AddDoubleLine("Great Vault", ITEM_COLOR .. (highest or "") .. "|r")
    tooltip:AddLine(" ")

    if C_WeeklyRewards.HasAvailableRewards() then
        tooltip:AddLine(ITEM_COLOR .. "Vault rewards available!|r")
        tooltip:AddLine(" ")
    end

    tooltip:AddLine("|cFFa20506Raids|r     " .. formatLine(raidData, progress[raidData]))
    tooltip:AddLine("|cFF555ACDMythic+|r  " .. formatLine(mplusData, progress[mplusData]))
    tooltip:AddLine("|cFFE1A18CDelves|r   " .. formatLine(delveData, progress[delveData]))
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffff9922Click|r to open/close the Great Vault.")
end

local function CurrentIcon()
    if C_WeeklyRewards.HasAvailableRewards() then
        return ICON_AVAILABLE
    end
    return ICON_PENDING
end

local function RecheckIcon()
    if vaultDataObject then
        vaultDataObject.icon = CurrentIcon()
    end
end

-- ---------------------------------------------------------------------------
-- Database / registration
-- ---------------------------------------------------------------------------

function QoLModule:InitDB(db)
    if not db.qol then db.qol = {} end
    if not db.qol.greatVault then db.qol.greatVault = {} end
    -- LibDBIcon manages: hide, minimapPos, lock, radius. Default to shown.
    if db.qol.greatVault.hide == nil then db.qol.greatVault.hide = false end

    if not db.qol.autoRepair then db.qol.autoRepair = {} end
    if db.qol.autoRepair.enabled == nil then db.qol.autoRepair.enabled = false end
    if db.qol.autoRepair.useGuild == nil then db.qol.autoRepair.useGuild = true end

    if not db.qol.autoRelease then db.qol.autoRelease = {} end
    if db.qol.autoRelease.enabled == nil then db.qol.autoRelease.enabled = false end

    if not db.qol.autoAcceptLFG then db.qol.autoAcceptLFG = {} end
    if db.qol.autoAcceptLFG.enabled == nil then db.qol.autoAcceptLFG.enabled = false end

    LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
    LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    RunNextFrame(function()
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
        if WeeklyRewardExpirationWarningDialog then
            WeeklyRewardExpirationWarningDialog:Hide()
        end
        if not tContains(UISpecialFrames, "WeeklyRewardsFrame") then
            tinsert(UISpecialFrames, "WeeklyRewardsFrame")
        end
    end)

    vaultDataObject = LDB:GetDataObjectByName(LDB_NAME) or LDB:NewDataObject(LDB_NAME, {
        type = "launcher",
        text = "Great Vault",
        icon = CurrentIcon(),
        OnClick = function()
            C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
            if WeeklyRewardsFrame and WeeklyRewardsFrame:IsVisible() then
                WeeklyRewardsFrame:Hide()
            elseif WeeklyRewardsFrame then
                WeeklyRewardsFrame:Show()
            end
            RecheckIcon()
        end,
        OnTooltipShow = function(tooltip)
            constructTooltip(tooltip)
            RecheckIcon()
        end,
    })

    if not LDBIcon:IsRegistered(LDB_NAME) then
        LDBIcon:Register(LDB_NAME, vaultDataObject, db.qol.greatVault)
    end
    LDBIcon:Refresh(LDB_NAME, db.qol.greatVault)
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

local CreateFrame = AR.UI.CreateFrame

function QoLModule:BuildUI(parent, db)
    local COL_NAME_X = 16

    AR.UI.Title(parent, "Quality of Life", COL_NAME_X, -16)

    local y = -52

    local cbVault = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbVault:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
    cbVault:SetChecked(not db.qol.greatVault.hide)
    cbVault:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        db.qol.greatVault.hide = not show
        if LDBIcon then
            LDBIcon:Refresh(LDB_NAME, db.qol.greatVault)
        end
    end)

    local vaultLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vaultLabel:SetPoint("LEFT", cbVault, "RIGHT", 6, 0)
    vaultLabel:SetText("Show Great Vault minimap button")

    y = y - 26

    local vaultNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vaultNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 44, y)
    vaultNote:SetText("Drag the button around the minimap to reposition.")

    y = y - 30

    AR.UI.Divider(parent, y, COL_NAME_X - 4)

    y = y - 22

    local cbLFG = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbLFG:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
    cbLFG:SetChecked(db.qol.autoAcceptLFG.enabled)
    cbLFG:SetScript("OnClick", function(self)
        db.qol.autoAcceptLFG.enabled = self:GetChecked()
    end)

    local lfgLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfgLabel:SetPoint("LEFT", cbLFG, "RIGHT", 6, 0)
    lfgLabel:SetText("Auto-accept LFG role checks")

    y = y - 26

    local lfgNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lfgNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 44, y)
    lfgNote:SetText("Uses your currently assigned role, or your spec role if none assigned.")

    y = y - 30
    AR.UI.Divider(parent, y, COL_NAME_X - 4)
    y = y - 22

    -- Checkbox + label bound to a boolean in a db table; returns the label.
    local function AddToggle(tbl, key, text)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X - 2, y + 4)
        cb:SetChecked(tbl[key])
        cb:SetScript("OnClick", function(self) tbl[key] = self:GetChecked() end)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        label:SetText(text)
        return label
    end

    AddToggle(db.qol.autoRepair, "enabled", "Repair automatically at vendors")
    y = y - 26
    AddToggle(db.qol.autoRepair, "useGuild", "Use guild funds first when available")
    y = y - 30
    AR.UI.Divider(parent, y, COL_NAME_X - 4)
    y = y - 22

    AddToggle(db.qol.autoRelease, "enabled", "Release spirit automatically after dying")
    y = y - 26
    local releaseNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    releaseNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 44, y)
    releaseNote:SetText("Only in the open world and battlegrounds, never in dungeons or raids, and never when you can self-resurrect.")
end

-- ---------------------------------------------------------------------------
-- Auto-accept LFG role checks
-- ---------------------------------------------------------------------------

local function AutoAcceptLFGRoleCheck()
    if not AR.db or not AR.db.qol or not AR.db.qol.autoAcceptLFG.enabled then return end

    local role = Util.GetRole()
    if not role then return end  -- no spec chosen yet: leave the choice to the player

    local tank   = role == "TANK"
    local healer = role == "HEALER"
    local dps    = role == "DAMAGER"

    if LFDRoleCheckPopupRoleButtonTank and LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then
        LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank)
    end
    if LFDRoleCheckPopupRoleButtonHealer and LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then
        LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer)
    end
    if LFDRoleCheckPopupRoleButtonDPS and LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then
        LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps)
    end
    if LFDRoleCheckPopupAcceptButton then
        LFDRoleCheckPopupAcceptButton:Enable()
        LFDRoleCheckPopupAcceptButton:Click()
    end
end

-- ---------------------------------------------------------------------------
-- Auto repair / auto release
-- ---------------------------------------------------------------------------

local function CoinText(copper)
    local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
    return fn(copper)
end

local function AutoRepair()
    local cfg = AR.db and AR.db.qol and AR.db.qol.autoRepair
    if not cfg or not cfg.enabled then return end
    if not (CanMerchantRepair and CanMerchantRepair()) then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local useGuild = cfg.useGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
    if useGuild then
        local allowance = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        useGuild = allowance == -1 or allowance >= cost
    end

    if useGuild then
        RepairAllItems(true)
        Util.Print("repaired for " .. CoinText(cost) .. " (guild funds).")
    elseif GetMoney() >= cost then
        RepairAllItems()
        Util.Print("repaired for " .. CoinText(cost) .. ".")
    else
        Util.Print("not enough gold to repair (" .. CoinText(cost) .. ").")
    end
end

local function AutoRelease()
    local cfg = AR.db and AR.db.qol and AR.db.qol.autoRelease
    if not cfg or not cfg.enabled then return end

    -- Dungeons and raids: dying there usually means waiting for a resurrection.
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType ~= "pvp" then return end

    -- Soulstone, reincarnation and the like: let the player choose.
    if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
        local options = C_DeathInfo.GetSelfResurrectOptions()
        if options and #options > 0 then return end
    end

    C_Timer.After(0.5, function()
        if UnitIsDeadOrGhost("player") and not UnitIsGhost("player") then RepopMe() end
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("WEEKLY_REWARDS_UPDATE")
events:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
events:RegisterEvent("LFG_ROLE_CHECK_SHOW")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("PLAYER_DEAD")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        AutoRepair()
    elseif event == "PLAYER_DEAD" then
        AutoRelease()
    elseif event == "LFG_ROLE_CHECK_SHOW" then
        -- Next frame: Blizzard's own handler has to finish populating the popup first.
        RunNextFrame(AutoAcceptLFGRoleCheck)
    else
        RecheckIcon()
    end
end)

AR:RegisterModule("QoL", QoLModule)
