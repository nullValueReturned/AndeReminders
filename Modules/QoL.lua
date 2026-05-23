local AR = AndeReminders

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

local function getVaultData()
    local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()
    if not activities then return {}, {}, {}, nil end

    local raidData, mplusData, delveData = {}, {}, {}
    local highest

    for i = 1, 9 do
        local entry = activities[i]
        local id = entry and entry.id or 0
        local itemLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(id)
        if itemLink then
            local ilvl = GetDetailedItemLevelInfo(itemLink)
            if ilvl then
                if not highest or ilvl > highest then highest = ilvl end
                if i < 4 then
                    table.insert(delveData, ilvl)
                elseif i < 7 then
                    table.insert(raidData, ilvl)
                else
                    table.insert(mplusData, ilvl)
                end
            end
        end
    end

    return raidData, mplusData, delveData, highest
end

local function formatLine(data)
    local function cell(v)
        if v then return ITEM_COLOR .. v .. "|r" end
        return "xxx"
    end
    return string.format("%s || %s || %s", cell(data[1]), cell(data[2]), cell(data[3]))
end

local function constructTooltip(tooltip)
    local raidData, mplusData, delveData, highest = getVaultData()

    tooltip:ClearLines()
    tooltip:AddDoubleLine("Great Vault", ITEM_COLOR .. (highest or "") .. "|r")
    tooltip:AddLine(" ")

    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
        tooltip:AddLine(ITEM_COLOR .. "Vault rewards available!|r")
        tooltip:AddLine(" ")
    end

    tooltip:AddLine("|cFFa20506Raids|r     " .. formatLine(raidData))
    tooltip:AddLine("|cFF555ACDMythic+|r  " .. formatLine(mplusData))
    tooltip:AddLine("|cFFE1A18CDelves|r   " .. formatLine(delveData))
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffff9922Click|r to open/close the Great Vault.")
end

local function CurrentIcon()
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
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
end

-- ---------------------------------------------------------------------------
-- Settings UI
-- ---------------------------------------------------------------------------

function QoLModule:BuildUI(parent, db)
    local COL_NAME_X = 12

    local sectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, -10)
    sectionTitle:SetText("Quality of Life")
    sectionTitle:SetTextColor(1, 0.82, 0)

    local y = -36

    local cbVault = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbVault:SetSize(24, 24)
    cbVault:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X, y + 3)
    cbVault:SetChecked(not db.qol.greatVault.hide)
    cbVault:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if LDBIcon then
            if show then LDBIcon:Show(LDB_NAME) else LDBIcon:Hide(LDB_NAME) end
        else
            db.qol.greatVault.hide = not show
        end
    end)

    local vaultLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vaultLabel:SetPoint("LEFT", cbVault, "RIGHT", 6, 0)
    vaultLabel:SetText("Show Great Vault minimap button")

    y = y - 20

    local vaultNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vaultNote:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_NAME_X + 30, y)
    vaultNote:SetText("Drag the button around the minimap to reposition.")
    vaultNote:SetTextColor(0.5, 0.5, 0.5)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("WEEKLY_REWARDS_HIDE")
events:RegisterEvent("WEEKLY_REWARDS_UPDATE")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
events:SetScript("OnEvent", function()
    RecheckIcon()
end)

AR:RegisterModule("QoL", QoLModule)
