local AR = AndeReminders
local BossModModule = {}

-- =============================================================================
-- LibSharedMedia helpers
-- =============================================================================

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local BFONT_NAMES = { "Friz Quadrata TT", "Morpheus", "Skurri", "Arial Narrow" }
local BFONT_PATHS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.ttf",
    ["Skurri"]           = "Fonts\\skurri.ttf",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
}
local BTEX_NAMES = { "Blizzard", "Blizzard Raid" }
local BTEX_PATHS = {
    ["Blizzard"]      = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Blizzard Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}

local function GetFontList() return LSM and LSM:List("font") or BFONT_NAMES end
local function GetFontPath(n)
    if LSM then return LSM:Fetch("font", n) or "Fonts\\FRIZQT__.TTF" end
    return BFONT_PATHS[n] or "Fonts\\FRIZQT__.TTF"
end
local function GetTexList() return LSM and LSM:List("statusbar") or BTEX_NAMES end
local function GetTexPath(n)
    if LSM then return LSM:Fetch("statusbar", n) or "Interface\\TargetingFrame\\UI-StatusBar" end
    return BTEX_PATHS[n] or "Interface\\TargetingFrame\\UI-StatusBar"
end
local function GetSoundList() return LSM and LSM:List("sound") or {} end
local function GetSoundPath(n) return LSM and LSM:Fetch("sound", n) end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- =============================================================================
-- Entry defaults
-- =============================================================================

local EDEFS = {
    name         = "New Entry",  anchorX = 0,  anchorY = 200,
    iconEnabled  = true,         iconSize = 32,   iconOverrideId = "", iconSwipe = false, durationOverride = "",
    fontName     = nil,          fontSize = 14,
    tcR=1, tcG=1, tcB=1, tcA=1,
    textPosition = "RIGHT",
    displayText  = "",           -- format template: %m=message %c=count %t=time(bars)
    barTexName   = nil,
    bcR=0.2, bcG=0.8, bcB=0.2, bcA=1,
    barWidth=220,  barHeight=22,  barHideTimer=false,
    barFontName  = nil,          barFontSize=12,
    btcR=1, btcG=1, btcB=1, btcA=1,
    barTextPos   = "CENTER",
    growthDir    = "DOWN",       spacing=4,
    triggerType  = "announce",
    annSpellId="", annText="",  annTextOp="find", annCount="", annDuration=5,
    tmrSpellId="", tmrText="",  tmrTextOp="find", tmrCount="", tmrRemaining="",
    trigStage    = "",
    loadClass="", loadEncId="", loadDiff="", loadRole="",
    loadZoneId="",
}

local function ApplyDefs(e)
    for k, v in pairs(EDEFS) do if e[k] == nil then e[k] = v end end
    if e.children == nil then e.children = {} end
end

-- =============================================================================
-- DB init
-- =============================================================================

function BossModModule:InitDB(db)
    if not db.bossmods then db.bossmods = {} end
    local bm = db.bossmods
    if not bm.entries  then bm.entries  = {} end
    if not bm.topLevel then bm.topLevel = {} end
    if bm.nextId == nil then bm.nextId  = 1  end
    for _, e in pairs(bm.entries) do ApplyDefs(e) end
end

-- =============================================================================
-- Module-scope: entry management
-- =============================================================================

local entryFrames = {}

local function NewEntry(etype, groupId)
    local db = AR.db.bossmods
    local id = db.nextId; db.nextId = id + 1
    local e = { id = id, type = etype, groupId = groupId }
    ApplyDefs(e)
    -- Progress bars default to timer trigger; icon+text entries to announce
    if etype == "bar"  then e.triggerType = "timer" end
    if etype == "text" then e.iconEnabled = false end
    db.entries[id] = e
    return e
end

local function DeleteEntry(id)
    local db = AR.db.bossmods
    local e = db.entries[id]; if not e then return end
    for i, tid in ipairs(db.topLevel) do
        if tid == id then table.remove(db.topLevel, i); break end
    end
    if e.groupId then
        local pg = db.entries[e.groupId]
        if pg then
            for i, cid in ipairs(pg.children) do
                if cid == id then table.remove(pg.children, i); break end
            end
        end
    end
    if e.type == "group" then
        for _, cid in ipairs(e.children) do
            db.entries[cid] = nil
            if entryFrames[cid] then entryFrames[cid]:Hide(); entryFrames[cid] = nil end
        end
    end
    db.entries[id] = nil
    if entryFrames[id] then entryFrames[id]:Hide(); entryFrames[id] = nil end
end

-- =============================================================================
-- Forward declarations (mutual recursion)
-- =============================================================================

local HandleAnnounce, HandleTimerStart, HandleTimerStop
local ShowEntryFrame, HideEntryFrame, RefreshGroupLayout
local FireConditionAction

-- =============================================================================
-- Runtime state
-- =============================================================================

local currentEncId      = 0
local bwStage           = 0
local dbmStage          = 0
local bwBars            = {}  -- [text]    = barData
local dbmBars           = {}  -- [timerId] = barData
local activeBars        = {}  -- [entryId] = barData
local annTimers         = {}  -- [entryId] = C_Timer handle
local schedShows        = {}  -- [entryId] = C_Timer handle
local groupActiveKids   = {}  -- [groupId] = ordered list of visible child ids
local condFired         = {}  -- [entryId] = { [condIdx] = true }  reset on ShowEntryFrame
local condCleanup       = {}  -- [entryId] = list of cleanup fns    called on HideEntryFrame

local function GetStage() return BigWigsLoader and bwStage or dbmStage end

-- =============================================================================
-- Matching helpers
-- =============================================================================

local function Mtxt(hay, needle, op)
    if not needle or needle == "" then return true end
    if not hay    or hay    == "" then return false end
    hay    = hay:lower()
    needle = needle:lower()
    if op == "==" then return hay == needle end
    if op == "match" then
        local ok, res = pcall(string.match, hay, needle)
        return ok and res ~= nil
    end
    return hay:find(needle, 1, true) ~= nil
end

local function PassesLoad(e)
    if e.loadClass ~= "" then
        local _, cls = UnitClass("player")
        if cls ~= e.loadClass then return false end
    end
    if e.loadEncId ~= "" and tostring(currentEncId) ~= e.loadEncId then return false end
    if e.loadDiff  ~= "" then
        local diff = select(3, GetInstanceInfo())
        if tostring(diff) ~= e.loadDiff then return false end
    end
    if e.loadRole ~= "" then
        local role = UnitGroupRolesAssigned("player")
        if role == "NONE" then role = GetSpecializationRole(GetSpecialization()) end
        if role ~= e.loadRole then return false end
    end
    if e.loadZoneId ~= "" then
        local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local val   = e.loadZoneId
        if val:sub(1,1) == "g" then
            local groupId = mapId and C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupID(mapId)
            if tostring(groupId) ~= val:sub(2) then return false end
        else
            if tostring(mapId) ~= val then return false end
        end
    end
    return true
end

local function MatchAnn(e, d)
    if e.type == "group" or e.triggerType ~= "announce" then return false end
    if e.annSpellId ~= "" and d.spellId ~= e.annSpellId then return false end
    if not Mtxt(d.text, e.annText, e.annTextOp) then return false end
    if e.annCount   ~= "" and d.count ~= e.annCount   then return false end
    if e.trigStage  ~= "" and tostring(GetStage()) ~= e.trigStage then return false end
    return true
end

local function MatchTmr(e, d)
    if e.type == "group" or e.triggerType ~= "timer" then return false end
    if e.tmrSpellId ~= "" and d.spellId ~= e.tmrSpellId then return false end
    if not Mtxt(d.text, e.tmrText, e.tmrTextOp) then return false end
    if e.tmrCount   ~= "" and d.count ~= e.tmrCount   then return false end
    if e.trigStage  ~= "" and tostring(GetStage()) ~= e.trigStage then return false end
    return true
end

-- =============================================================================
-- Announce handler
-- =============================================================================

HandleAnnounce = function(data)
    local db = AR.db; if not db or not db.bossmods then return end
    for id, e in pairs(db.bossmods.entries) do
        if MatchAnn(e, data) and PassesLoad(e) then
            local dur = (e.annDuration and e.annDuration > 0) and e.annDuration or 5
            -- Build a per-entry data copy with duration/expirationTime so bar frames
            -- can count down using annDuration and %t resolves correctly.
            local annData = {
                source         = data.source,
                spellId        = data.spellId,
                text           = data.text,
                icon           = data.icon,
                count          = data.count,
                duration       = dur,
                expirationTime = GetTime() + dur,
            }
            ShowEntryFrame(e, annData)
            if annTimers[id] then annTimers[id]:Cancel() end
            annTimers[id] = C_Timer.NewTimer(dur, function()
                annTimers[id] = nil; HideEntryFrame(id)
            end)
        end
    end
end

-- =============================================================================
-- Timer handlers
-- =============================================================================

HandleTimerStart = function(data)
    local db = AR.db; if not db or not db.bossmods then return end
    for id, e in pairs(db.bossmods.entries) do
        if MatchTmr(e, data) and PassesLoad(e) then
            local rem = tonumber(e.tmrRemaining) or 0
            activeBars[id] = data
            if rem > 0 and data.duration > rem then
                if schedShows[id] then schedShows[id]:Cancel() end
                -- Hide immediately: the new bar is above the threshold so the
                -- entry should not be visible yet. schedShows will re-show it.
                HideEntryFrame(id)
                local delay = data.duration - rem
                schedShows[id] = C_Timer.NewTimer(delay, function()
                    schedShows[id] = nil
                    if activeBars[id] then ShowEntryFrame(e, activeBars[id]) end
                end)
            else
                ShowEntryFrame(e, data)
            end
        end
    end
end

HandleTimerStop = function(key)
    local db = AR.db; if not db or not db.bossmods then return end
    local now = GetTime()
    for id, e in pairs(db.bossmods.entries) do
        if e.triggerType == "timer" then
            local bar = activeBars[id]
            if bar and (bar.text == key or bar.timerId == key) then
                -- Only fully clear tracking if this stop event is for the bar
                -- currently in activeBars (its expiry is imminent). If a newer
                -- bar has already replaced it (far-future expiry), preserve
                -- the new bar's tracking so the entry reappears at its threshold.
                if bar.expirationTime <= now + 1 then
                    activeBars[id] = nil
                    if schedShows[id] then schedShows[id]:Cancel(); schedShows[id] = nil end
                end
                HideEntryFrame(id)
            end
        end
    end
end

-- =============================================================================
-- BigWigs integration
-- =============================================================================

local BM_CB  = {}
local bwReg  = false

-- BigWigsLoader.RegisterMessage fires (event, arg1, arg2, ...) with no handler
-- prepended — event name is the first arg, BigWigs payload follows directly.

local function OnBWTimer(event, addon, spellId, duration, _, text, count, icon)
    local now = GetTime()
    local d = { source="bw", spellId=tostring(spellId or ""), text=text or "",
        duration=duration or 0, expirationTime=now+(duration or 0),
        icon=icon, count=tostring(count or "0") }
    bwBars[text or ""] = d
    HandleTimerStart(d)
end

local function OnBWStopBar(_, _, text)
    -- event, addon, text
    bwBars[text or ""] = nil; HandleTimerStop(text or "")
end

local function OnBWStopBars()
    for t in pairs(bwBars) do bwBars[t] = nil; HandleTimerStop(t) end
end

local function OnBWMessage(_, _, spellId, text, _, icon)
    -- event, addon, spellId, text, type, icon
    local count = (text and (text:match("%((%d+)%)") or text:match("（(%d+)）"))) or "0"
    HandleAnnounce({ source="bw", spellId=tostring(spellId or ""),
        text=text or "", icon=icon, count=count })
end

local function OnBWSetStage(_, _, stage) bwStage = stage or 0 end
local function OnBWWipe()               bwStage = 0 end

local function RegisterBW()
    if bwReg or not BigWigsLoader then return end
    bwReg = true
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_Timer",        OnBWTimer)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_CastTimer",    OnBWTimer)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_TargetTimer",  OnBWTimer)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_StartPull", function(ev, ad, dur, _, txt, ic)
        -- event, addon, duration, _, text, icon
        OnBWTimer(ev, ad, -2, dur, nil, txt or "Pull", 0, ic or 136116)
    end)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_StopBar",      OnBWStopBar)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_StopBars",     OnBWStopBars)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_OnBossDisable",OnBWStopBars)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_Message",      OnBWMessage)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_SetStage",     OnBWSetStage)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_OnBossWipe",   OnBWWipe)
    BigWigsLoader.RegisterMessage(BM_CB, "BigWigs_OnBossWin",    OnBWWipe)
end

-- =============================================================================
-- DBM integration
-- =============================================================================

local dbmReg = false

local function RegisterDBM()
    if dbmReg or not DBM then return end
    dbmReg = true
    DBM:RegisterCallback("DBM_Announce", function(_, msg, icon, _, spellId, _, _, count)
        HandleAnnounce({ source="dbm", spellId=tostring(spellId or ""),
            text=msg or "", icon=icon, count=tostring(count or "0") })
    end)
    DBM:RegisterCallback("DBM_TimerBegin", function(_, timerId, msg, dur, icon, _,
        spellId, _, _, _, _, _, _, count)
        local now = GetTime()
        local d = { source="dbm", spellId=tostring(spellId or ""), text=msg or "",
            timerId=timerId, duration=dur or 0, expirationTime=now+(dur or 0),
            icon=icon, count=tostring(count or "0") }
        dbmBars[timerId] = d; HandleTimerStart(d)
    end)
    DBM:RegisterCallback("DBM_TimerStop", function(_, timerId)
        dbmBars[timerId] = nil; HandleTimerStop(timerId)
    end)
    local function DBMStage()
        if DBM and DBM.GetStage then dbmStage = DBM:GetStage() or 0 end
    end
    DBM:RegisterCallback("DBM_SetStage", DBMStage)
    DBM:RegisterCallback("DBM_Pull",     DBMStage)
    DBM:RegisterCallback("DBM_Wipe",  function() dbmStage = 0 end)
    DBM:RegisterCallback("DBM_Kill",  function() dbmStage = 0 end)
end

-- =============================================================================
-- Encounter tracking + late-load BW/DBM
-- =============================================================================

do
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("ENCOUNTER_START")
    ef:RegisterEvent("ENCOUNTER_END")
    ef:RegisterEvent("ADDON_LOADED")
    ef:SetScript("OnEvent", function(_, ev, a1)
        if     ev == "ENCOUNTER_START" then currentEncId = a1
        elseif ev == "ENCOUNTER_END" then
            currentEncId = 0
            -- Cancel pending announce timers and hide any entries still on screen
            for id, t in pairs(annTimers) do
                if t then t:Cancel() end
                annTimers[id] = nil
                HideEntryFrame(id)
            end
            -- Cancel pending threshold-delayed shows for timer entries
            for id, t in pairs(schedShows) do
                if t then t:Cancel() end
                schedShows[id] = nil
            end
            -- Hide any timer entries still showing and clear active bar state
            for id in pairs(activeBars) do HideEntryFrame(id) end
            wipe(activeBars)
            wipe(bwBars)
            wipe(dbmBars)
        elseif ev == "ADDON_LOADED" then
            if a1 == "BigWigsLoader" then RegisterBW()  end
            if a1 == "DBM-Core"      then RegisterDBM() end
        end
    end)
end

-- =============================================================================
-- Display text formatter (%m=bossmod message, %c=count, %t=time remaining)
-- =============================================================================

local function FmtDisplay(tmpl, rawText, count, rem)
    if not tmpl or tmpl == "" then return rawText end
    local s = tmpl
    s = s:gsub("%%t", ("%.1f"):format(math.max(0, rem or 0)))
    s = s:gsub("%%c", tostring(count or ""))
    s = s:gsub("%%m", tostring(rawText or ""))
    return s
end

-- =============================================================================
-- Display frames: Icon + Text
-- =============================================================================

local function MakeIconFrame(id)
    local f = CreateFrame("Frame", "ARBossE" .. id, UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
    f.icon  = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    f.cooldown:SetHideCountdownNumbers(true)
    f.cooldown:Hide()
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Live-update label when displayTmpl contains %t
    f:SetScript("OnUpdate", function(self)
        if not self.expTime then return end
        local rem = math.max(0, self.expTime - GetTime())
        if self.displayTmpl and self.displayTmpl:find("%%t") then
            self.label:SetText(FmtDisplay(self.displayTmpl, self.lastMsg or "", self.lastCount or "", rem))
        end
        local e = AR.db and AR.db.bossmods and AR.db.bossmods.entries[id]
        if e and e.conditions then
            if not condFired[id] then condFired[id] = {} end
            for ci, cond in ipairs(e.conditions) do
                if cond.trigger == "time" and not condFired[id][ci] then
                    local tval = cond.timeVal or 0
                    local met  = (cond.timeOp == "eq" and math.abs(rem - tval) < 0.15)
                              or (cond.timeOp == "lt" and rem < tval)
                              or (cond.timeOp == "gt" and rem > tval)
                    if met then condFired[id][ci] = true; FireConditionAction(id, cond) end
                end
            end
        end
    end)
    f:Hide(); return f
end

local function LayoutIconFrame(f, e, data)
    local isz = e.iconSize or 32
    local fsz = e.fontSize or 14
    local fp  = GetFontPath(e.fontName or GetFontList()[1])
    f.label:SetFont(fp, fsz, "OUTLINE")
    f.label:SetTextColor(e.tcR, e.tcG, e.tcB, e.tcA)
    local rawText = (data.text and data.text ~= "") and data.text or (e.name or "")
    f.displayTmpl = e.displayText or ""
    f.lastMsg     = rawText
    f.lastCount   = data.count or ""
    f.expTime     = data.expirationTime
    local initRem = data.expirationTime and math.max(0, data.expirationTime - GetTime()) or 0
    f.label:SetText(FmtDisplay(f.displayTmpl, rawText, f.lastCount, initRem))
    f.icon:ClearAllPoints(); f.label:ClearAllPoints()
    local resolvedIcon = data.icon
    if e.iconOverrideId and e.iconOverrideId ~= "" then
        resolvedIcon = tonumber(e.iconOverrideId) or e.iconOverrideId
    end
    local showIcon = e.iconEnabled and resolvedIcon
    if showIcon then
        f.icon:SetTexture(resolvedIcon); f.icon:SetSize(isz, isz); f.icon:Show()
        local lw  = f.label:GetStringWidth() + 2
        local gap = 4
        local tp  = e.textPosition or "RIGHT"
        if     tp == "RIGHT"  then f:SetSize(isz+gap+lw, isz); f.icon:SetPoint("LEFT",f,"LEFT"); f.label:SetPoint("LEFT",f.icon,"RIGHT",gap,0)
        elseif tp == "LEFT"   then f:SetSize(lw+gap+isz, isz); f.label:SetPoint("LEFT",f,"LEFT"); f.icon:SetPoint("LEFT",f.label,"RIGHT",gap,0)
        elseif tp == "TOP"    then local w=math.max(isz,lw); f:SetSize(w,fsz+gap+isz); f.label:SetPoint("TOP",f,"TOP"); f.icon:SetPoint("TOP",f.label,"BOTTOM",0,-gap)
        elseif tp == "BOTTOM" then local w=math.max(isz,lw); f:SetSize(w,isz+gap+fsz); f.icon:SetPoint("TOP",f,"TOP"); f.label:SetPoint("TOP",f.icon,"BOTTOM",0,-gap) end
    else
        f.icon:Hide()
        local lw = math.max(20, f.label:GetStringWidth() + 4)
        f:SetSize(lw, fsz + 4); f.label:SetPoint("CENTER", f, "CENTER")
    end
    if f.cooldown then
        if showIcon and e.iconSwipe and data.expirationTime and (data.duration or 0) > 0 then
            local effDur = (e.durationOverride ~= "" and tonumber(e.durationOverride)) or data.duration
            f.cooldown:ClearAllPoints()
            f.cooldown:SetAllPoints(f.icon)
            f.cooldown:SetCooldown(data.expirationTime - effDur, effDur)
            f.cooldown:Show()
        else
            f.cooldown:SetCooldown(0, 0)
            f.cooldown:Hide()
        end
    end
end

-- =============================================================================
-- Display frames: Progress Bar
-- =============================================================================

local function MakeBarFrame(id)
    local f  = CreateFrame("Frame", "ARBossE" .. id, UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sb:SetMinMaxValues(0, 1); sb:SetValue(1); f.bar = sb
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb); bg:SetColorTexture(0, 0, 0, 0.5); f.barBg = bg
    f.icon      = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.iconCooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.iconCooldown:SetSwipeColor(0, 0, 0, 0.8)
    f.iconCooldown:SetHideCountdownNumbers(true)
    f.iconCooldown:Hide()
    -- Labels are children of sb so they render above the bar fill texture
    f.label     = sb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.timeLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetScript("OnUpdate", function(self)
        if not self.expTime then return end
        local rem = self.expTime - GetTime()
        local e = AR.db and AR.db.bossmods and AR.db.bossmods.entries[id]
        if e and e.conditions then
            local rclamp = math.max(0, rem)
            if not condFired[id] then condFired[id] = {} end
            for ci, cond in ipairs(e.conditions) do
                if cond.trigger == "time" and not condFired[id][ci] then
                    local tval = cond.timeVal or 0
                    local met  = (cond.timeOp == "eq" and math.abs(rclamp - tval) < 0.15)
                              or (cond.timeOp == "lt" and rclamp < tval)
                              or (cond.timeOp == "gt" and rclamp > tval)
                    if met then condFired[id][ci] = true; FireConditionAction(id, cond) end
                end
            end
        end
        if rem <= 0 then self:Hide(); return end
        self.bar:SetValue(self.dur > 0 and rem/self.dur or 0)
        if not self.hideTimer then
            self.timeLabel:SetText(("%.1f"):format(rem))
        end
        if self.displayTmpl and self.displayTmpl ~= "" then
            self.label:SetText(FmtDisplay(self.displayTmpl, self.lastMsg or "", self.lastCount or "", rem))
        end
    end)
    f:Hide(); return f
end

local function LayoutBarFrame(f, e, data)
    local bw  = e.barWidth   or 220
    local bh  = e.barHeight  or 22
    local fsz = e.barFontSize or 12
    local fp  = GetFontPath(e.barFontName or GetFontList()[1])
    local tp  = GetTexPath(e.barTexName   or GetTexList()[1])
    f.bar:SetStatusBarTexture(tp)
    f.bar:SetStatusBarColor(e.bcR, e.bcG, e.bcB, e.bcA)
    for _, fs in ipairs({ f.label, f.timeLabel }) do
        fs:SetFont(fp, fsz, "OUTLINE")
        fs:SetTextColor(e.btcR, e.btcG, e.btcB, e.btcA)
    end
    local rawText = (data.text and data.text ~= "") and data.text or (e.name or "")
    f.displayTmpl = e.displayText or ""
    f.lastMsg     = rawText
    f.lastCount   = data.count or ""
    f.hideTimer   = e.barHideTimer or false
    f.timeLabel:SetShown(not f.hideTimer)
    f.expTime = data.expirationTime
    f.dur = (e.durationOverride ~= "" and tonumber(e.durationOverride)) or data.duration or 0
    local initRem = (data.expirationTime or GetTime()) - GetTime()
    f.label:SetText(FmtDisplay(f.displayTmpl, rawText, f.lastCount, initRem))
    local isz = bh
    local resolvedBarIcon = data.icon
    if e.iconOverrideId and e.iconOverrideId ~= "" then
        resolvedBarIcon = tonumber(e.iconOverrideId) or e.iconOverrideId
    end
    local showIcon = e.iconEnabled and resolvedBarIcon
    f.bar:ClearAllPoints(); f.icon:ClearAllPoints()
    if showIcon then
        f.icon:SetTexture(resolvedBarIcon); f.icon:SetSize(isz, isz); f.icon:Show()
        f.icon:SetPoint("LEFT", f, "LEFT")
        f.bar:SetPoint("LEFT", f.icon, "RIGHT", 0, 0)
        f.bar:SetSize(bw - isz, bh)
    else
        f.icon:Hide()
        f.bar:SetPoint("LEFT", f, "LEFT"); f.bar:SetSize(bw, bh)
    end
    f:SetSize(bw, bh)
    f.label:ClearAllPoints(); f.timeLabel:ClearAllPoints()
    local tp2 = e.barTextPos or "CENTER"
    if     tp2 == "LEFT"   then f.label:SetPoint("LEFT",f.bar,"LEFT",4,0);    f.timeLabel:SetPoint("RIGHT",f.bar,"RIGHT",-4,0)
    elseif tp2 == "RIGHT"  then f.label:SetPoint("RIGHT",f.bar,"RIGHT",-4,0); f.timeLabel:SetPoint("LEFT",f.bar,"LEFT",4,0)
    else                        f.label:SetPoint("CENTER",f.bar,"CENTER",0,0); f.timeLabel:SetPoint("RIGHT",f.bar,"RIGHT",-4,0) end
    if f.iconCooldown then
        if showIcon and e.iconSwipe and data.expirationTime and f.dur > 0 then
            f.iconCooldown:ClearAllPoints()
            f.iconCooldown:SetPoint("LEFT", f, "LEFT", 0, 0)
            f.iconCooldown:SetSize(isz, isz)
            f.iconCooldown:SetCooldown(data.expirationTime - f.dur, f.dur)
            f.iconCooldown:Show()
        else
            f.iconCooldown:SetCooldown(0, 0)
            f.iconCooldown:Hide()
        end
    end
end

-- =============================================================================
-- Display frames: Group anchor
-- =============================================================================

local function MakeGroupFrame(id)
    local f = CreateFrame("Frame", "ARBossG" .. id, UIParent, "BackdropTemplate")
    f:SetSize(1, 1); f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(false); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter(); local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local e = AR.db.bossmods.entries[id]
            if e then e.anchorX = math.floor(cx-ux+0.5); e.anchorY = math.floor(cy-uy+0.5) end
        end
    end)
    -- Backdrop and label visible only during settings preview, invisible at runtime
    f:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 })
    f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER"); lbl:SetText("Group Anchor"); lbl:SetTextColor(0.8, 0.9, 1); lbl:Hide()
    f.anchorLabel = lbl
    f:Hide(); return f
end

-- =============================================================================
-- Group layout
-- =============================================================================

RefreshGroupLayout = function(gid)
    local db = AR.db; if not db or not db.bossmods then return end
    local g  = db.bossmods.entries[gid]; if not g or g.type ~= "group" then return end
    local gf = entryFrames[gid];         if not gf then return end
    local active = groupActiveKids[gid] or {}
    local dir = g.growthDir or "DOWN"; local sp = g.spacing or 4
    local prev = nil
    for _, cid in ipairs(active) do
        local cf = entryFrames[cid]
        if cf and cf:IsShown() then
            cf:ClearAllPoints()
            if not prev then
                local pt = (dir=="UP") and "BOTTOM" or (dir=="DOWN") and "TOP" or (dir=="LEFT") and "RIGHT" or "LEFT"
                cf:SetPoint(pt, gf, pt)
            else
                if     dir=="DOWN"  then cf:SetPoint("TOP",   prev, "BOTTOM", 0,-sp)
                elseif dir=="UP"    then cf:SetPoint("BOTTOM",prev, "TOP",    0, sp)
                elseif dir=="RIGHT" then cf:SetPoint("LEFT",  prev, "RIGHT",  sp, 0)
                elseif dir=="LEFT"  then cf:SetPoint("RIGHT", prev, "LEFT",  -sp, 0) end
            end
            prev = cf
        end
    end
end

-- =============================================================================
-- Condition action executor
-- =============================================================================

FireConditionAction = function(entryId, cond)
    local f = entryFrames[entryId]; if not f then return end
    local action = cond.action or "glow"

    if action == "glow" then
        if LCG then
            local key = "arcond" .. entryId
            local gt  = cond.glowType or "pixel"
            if     gt == "pixel"    then LCG.PixelGlow_Start(f, nil, nil, nil, nil, nil, 0, 0, false, key)
            elseif gt == "proc"     then LCG.ProcGlow_Start(f, {}, key)
            elseif gt == "autocast" then LCG.AutoCastGlow_Start(f, nil, nil, nil, nil, 0, 0, key)
            end
            if not condCleanup[entryId] then condCleanup[entryId] = {} end
            local gt2 = gt
            table.insert(condCleanup[entryId], function()
                if not LCG then return end
                if     gt2 == "pixel"    then LCG.PixelGlow_Stop(f, key)
                elseif gt2 == "proc"     then LCG.ProcGlow_Stop(f, key)
                elseif gt2 == "autocast" then LCG.AutoCastGlow_Stop(f, key)
                end
            end)
        end

    elseif action == "sound" then
        local path = GetSoundPath(cond.soundName or "")
        if path then PlaySoundFile(path, "Master") end

    elseif action == "scale" then
        f:SetScale(cond.scaleVal or 1.5)
        if not condCleanup[entryId] then condCleanup[entryId] = {} end
        table.insert(condCleanup[entryId], function() f:SetScale(1.0) end)

    elseif action == "barColor" then
        if f.bar then
            f.bar:SetStatusBarColor(cond.bcR or 1, cond.bcG or 0, cond.bcB or 0, cond.bcA or 1)
        end

    elseif action == "fontColor" then
        if f.label     then f.label:SetTextColor(    cond.fcR or 1, cond.fcG or 1, cond.fcB or 0, cond.fcA or 1) end
        if f.timeLabel then f.timeLabel:SetTextColor(cond.fcR or 1, cond.fcG or 1, cond.fcB or 0, cond.fcA or 1) end

    elseif action == "flash" then
        local count = 0
        C_Timer.NewTicker(0.1, function(ticker)
            count = count + 1
            if f:IsShown() then f:SetAlpha(count % 2 == 0 and 1.0 or 0.15) end
            if count >= 8 then ticker:Cancel(); if f:IsShown() then f:SetAlpha(1.0) end end
        end)
    end
end

-- =============================================================================
-- GetFrame / ShowEntryFrame / HideEntryFrame
-- =============================================================================

local function GetFrame(e)
    if entryFrames[e.id] then return entryFrames[e.id] end
    local f
    if     e.type == "icon"  then f = MakeIconFrame(e.id)
    elseif e.type == "text"  then f = MakeIconFrame(e.id)
    elseif e.type == "bar"   then f = MakeBarFrame(e.id)
    elseif e.type == "group" then f = MakeGroupFrame(e.id) end
    if f then
        f:SetPoint("CENTER", UIParent, "CENTER", e.anchorX or 0, e.anchorY or 200)
        entryFrames[e.id] = f
    end
    return f
end

local function AddToGroup(e, data)
    local gid = e.groupId
    if not groupActiveKids[gid] then groupActiveKids[gid] = {} end
    local found = false
    for _, cid in ipairs(groupActiveKids[gid]) do if cid == e.id then found = true; break end end
    if not found then table.insert(groupActiveKids[gid], e.id) end
    local gf = GetFrame(AR.db.bossmods.entries[gid])
    if gf and not gf:IsShown() then gf:Show() end
end

local function RemoveFromGroup(id)
    local db = AR.db; if not db or not db.bossmods then return end
    local e = db.bossmods.entries[id]; if not e or not e.groupId then return end
    local active = groupActiveKids[e.groupId]
    if active then
        for i, cid in ipairs(active) do if cid == id then table.remove(active, i); break end end
        RefreshGroupLayout(e.groupId)
        if #active == 0 then local gf = entryFrames[e.groupId]; if gf then gf:Hide() end end
    end
end

ShowEntryFrame = function(e, data)
    if not e or e.type == "group" then return end
    local f = GetFrame(e); if not f then return end
    if     e.type == "icon" or e.type == "text" then LayoutIconFrame(f, e, data)
    elseif e.type == "bar"  then LayoutBarFrame(f, e, data) end
    if e.groupId then
        AddToGroup(e, data); f:Show(); RefreshGroupLayout(e.groupId)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", e.anchorX or 0, e.anchorY or 200)
        f:Show()
    end
    -- Reset per-activation state then fire "show" conditions
    condFired[e.id]   = {}
    condCleanup[e.id] = {}
    if e.conditions then
        for ci, cond in ipairs(e.conditions) do
            if cond.trigger == "show" then
                condFired[e.id][ci] = true
                FireConditionAction(e.id, cond)
            end
        end
    end
end

HideEntryFrame = function(id)
    -- Fire "hide" conditions before hiding
    local hdb = AR.db
    if hdb and hdb.bossmods then
        local he = hdb.bossmods.entries[id]
        if he and he.conditions then
            for _, cond in ipairs(he.conditions) do
                if cond.trigger == "hide" then FireConditionAction(id, cond) end
            end
        end
    end
    -- Run cleanup (stop glows, reset scale)
    if condCleanup[id] then
        for _, fn in ipairs(condCleanup[id]) do fn() end
        condCleanup[id] = nil
    end
    condFired[id] = nil
    local f = entryFrames[id]; if f then f:Hide() end
    RemoveFromGroup(id)
end

-- =============================================================================
-- Settings UI helpers
-- =============================================================================

local function Swatch(parent, getR, getG, getB, getA, setColor)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(); border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    tex:SetColorTexture(getR(), getG(), getB(), 1)
    btn.tex = tex
    btn:SetScript("OnClick", function()
        local sr, sg, sb, sa = getR(), getG(), getB(), getA()
        ColorPickerFrame:SetupColorPickerAndShow({
            r=sr, g=sg, b=sb, hasOpacity=false,
            swatchFunc=function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                setColor(nr, ng, nb, sa); tex:SetColorTexture(nr, ng, nb, 1)
            end,
            cancelFunc=function(prev)
                setColor(prev.r, prev.g, prev.b, sa); tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
            end,
        })
    end)
    btn.Refresh = function() tex:SetColorTexture(getR(), getG(), getB(), 1) end
    return btn
end

-- Compact scrollable dropdown. opts = array of strings or {label,value} tables.
local function ScrollDrop(parent, w, opts, getter, setter, kind)
    -- Snapshot opts: LSM:List() returns its internal mutable array; if other addons
    -- register fonts after this dropdown is built, opts would grow but selTex wouldn't.
    local snap = {}; for i = 1, #opts do snap[i] = opts[i] end; opts = snap
    local ITEM_H = 20; local MAX_H = 200; local SW = 14
    local totalH = #opts * ITEM_H
    local visH   = math.min(totalH, MAX_H)
    local maxSc  = math.max(0, totalH - visH)
    local hasSc  = maxSc > 0
    local function Label(o) return type(o)=="table" and o.label or tostring(o) end
    local function Val(o)   return type(o)=="table" and o.value or o end

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 22)
    local bfs = btn:GetFontString(); bfs:ClearAllPoints(); bfs:SetPoint("LEFT",btn,"LEFT",8,0); bfs:SetPoint("RIGHT",btn,"RIGHT",-18,0); bfs:SetJustifyH("LEFT")
    local arrowFs = btn:CreateFontString(nil,"OVERLAY","GameFontNormal"); arrowFs:SetPoint("RIGHT",btn,"RIGHT",-5,0); arrowFs:SetText("v")

    local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    popup:SetSize(w, visH + 4)
    popup:SetFrameLevel(parent:GetFrameLevel() + 50)
    popup:SetBackdrop({ bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1,
        tile=true, tileSize=32, insets={left=2,right=2,top=2,bottom=2} })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2); popup:Hide()

    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -2)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", hasSc and -(SW+4) or -2, 2)
    local ct = CreateFrame("Frame", nil, sf)
    ct:SetWidth(w - (hasSc and (SW+6) or 4)); ct:SetHeight(math.max(totalH, 1))
    sf:SetScrollChild(ct)

    local selTex = {}
    local function Refresh()
        local cur = getter()
        for i, o in ipairs(opts) do selTex[i]:SetShown(Val(o) == cur) end
        for _, o in ipairs(opts) do
            if Val(o) == cur then btn:SetText(Label(o)); return end
        end
        if opts[1] then btn:SetText(Label(opts[1])) end
    end

    for i, o in ipairs(opts) do
        local row = CreateFrame("Button", nil, ct)
        row:SetHeight(ITEM_H)
        row:SetPoint("TOPLEFT",  ct, "TOPLEFT",  0, -(i-1)*ITEM_H)
        row:SetPoint("TOPRIGHT", ct, "TOPRIGHT", 0, -(i-1)*ITEM_H)
        if kind == "texture" then
            local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetDrawLayer("BACKGROUND", -1); bg:SetAllPoints(); bg:SetTexture(GetTexPath(Val(o))); bg:SetVertexColor(0.55, 0.55, 0.55, 1)
        end
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.1)
        local st = row:CreateTexture(nil, "BACKGROUND"); st:SetAllPoints(); st:SetColorTexture(0.2,0.4,0.8,0.25); selTex[i] = st
        local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormal"); lbl:SetPoint("LEFT",row,"LEFT",6,0); lbl:SetJustifyH("LEFT"); lbl:SetText(Label(o))
        if kind == "font" then lbl:SetFont(GetFontPath(Val(o)), 12, "") end
        local val = Val(o)
        row:SetScript("OnClick", function() setter(val); popup:Hide(); Refresh() end)
    end

    if hasSc then
        local sb = CreateFrame("Slider", nil, popup); sb:SetOrientation("VERTICAL"); sb:SetWidth(SW)
        sb:SetPoint("TOPRIGHT",popup,"TOPRIGHT",-2,-18); sb:SetPoint("BOTTOMRIGHT",popup,"BOTTOMRIGHT",-2,18)
        local th = sb:CreateTexture(nil,"OVERLAY"); th:SetTexture("Interface/Buttons/UI-ScrollBar-Knob"); th:SetSize(14,14); sb:SetThumbTexture(th)
        sb:SetMinMaxValues(0, maxSc); sb:SetValue(0); sb:SetValueStep(ITEM_H); sb:SetObeyStepOnDrag(true)
        sb:SetScript("OnValueChanged", function(s,v) sf:SetVerticalScroll(v) end)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(_,d) local mn,mx=sb:GetMinMaxValues(); sb:SetValue(math.max(mn,math.min(mx,sb:GetValue()-d*ITEM_H*3))) end)
    end

    btn:SetScript("OnClick", function() if popup:IsShown() then popup:Hide() else popup:Show() end end)
    parent:HookScript("OnHide", function() popup:Hide() end)
    Refresh(); btn.Refresh = Refresh; return btn
end

local function MakeEB(parent, x, y, w, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 20); eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    if numeric then eb:SetNumeric(true) end
    return eb
end

local function Label(parent, x, y, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); fs:SetText(text); return fs
end

local function Divider(parent, y)
    local d = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    d:SetHeight(1); d:SetBackdrop({bgFile="Interface/Buttons/WHITE8x8"})
    d:SetBackdropColor(0.25, 0.25, 0.25, 1)
    d:SetPoint("TOPLEFT",  parent, "TOPLEFT",  4, y)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    return d
end

-- =============================================================================
-- Icon Picker
-- =============================================================================

local iconPickerFrame = nil
local iconPickerCb    = nil
local allIconPaths    = nil  -- cached; built once on first open

local IC_SIZE     = 36
local IC_CELL     = 40   -- icon + 2px margin each side
local IC_COLS     = 13
local IC_ROWS_VIS = 11
local IC_POOL     = IC_COLS * (IC_ROWS_VIS + 2)
local IC_GRID_H   = IC_ROWS_VIS * IC_CELL  -- used for max-scroll calculation

local function BuildIconPicker()
    local W, H = 600, 520
    local f = CreateFrame("Frame", "ARIconPickerFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H); f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        edgeSize = 24, tile = true, tileSize = 32,
        insets   = { left=6, right=6, top=6, bottom=6 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14); title:SetText("Choose Icon")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local searchLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -44); searchLbl:SetText("Search:")
    local searchEB = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchEB:SetSize(280, 20); searchEB:SetPoint("LEFT", searchLbl, "RIGHT", 6, 0)
    searchEB:SetAutoFocus(false)

    local statusLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusLbl:SetPoint("LEFT", searchEB, "RIGHT", 12, 0)
    statusLbl:SetTextColor(0.6, 0.6, 0.6)

    -- Grid area (clipped so icons outside bounds are invisible)
    local gridFrame = CreateFrame("Frame", nil, f)
    gridFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",      8, -70)
    gridFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26,   8)
    gridFrame:SetClipsChildren(true)

    -- Scrollbar
    local sb = CreateFrame("Slider", nil, f)
    sb:SetOrientation("VERTICAL"); sb:SetWidth(16)
    sb:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -6, -70)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6,   8)
    local sbBg = sb:CreateTexture(nil, "BACKGROUND"); sbBg:SetAllPoints(); sbBg:SetColorTexture(0,0,0,0.3)
    local sbTh = sb:CreateTexture(nil, "OVERLAY")
    sbTh:SetTexture("Interface/Buttons/UI-ScrollBar-Knob"); sbTh:SetSize(16,16)
    sb:SetThumbTexture(sbTh); sb:SetMinMaxValues(0,0); sb:SetValue(0)

    -- Button pool (only visible rows are positioned + shown)
    local pool = {}
    for i = 1, IC_POOL do
        local btn = CreateFrame("Button", nil, gridFrame)
        btn:SetSize(IC_SIZE, IC_SIZE)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); btn.tex = tex
        local hl  = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)
        local sel = btn:CreateTexture(nil, "OVERLAY")
        sel:SetAllPoints(); sel:SetColorTexture(1, 0.8, 0, 0.4); sel:Hide(); btn.selTex = sel
        btn:Hide(); pool[i] = btn
    end

    local filteredIcons = {}
    local scrollOffset  = 0
    local selectedPath  = nil

    local function UpdateGrid()
        for i = 1, #pool do pool[i]:Hide() end
        local firstRow = math.floor(scrollOffset / IC_CELL)
        local lastRow  = firstRow + IC_ROWS_VIS + 1
        local pi = 0
        for iconIdx = firstRow * IC_COLS + 1, math.min((lastRow + 1) * IC_COLS, #filteredIcons) do
            pi = pi + 1; if pi > #pool then break end
            local btn = pool[pi]
            local row = math.floor((iconIdx - 1) / IC_COLS)
            local col = (iconIdx - 1) % IC_COLS
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", col * IC_CELL, -(row * IC_CELL - scrollOffset))
            btn.iconPath = filteredIcons[iconIdx]
            btn.tex:SetTexture(filteredIcons[iconIdx])
            btn.selTex:SetShown(filteredIcons[iconIdx] == selectedPath)
            btn:Show()
        end
    end

    local searchTimer = nil
    local function RebuildFiltered(query)
        filteredIcons = {}
        query = query and query:lower() or ""
        if allIconPaths then
            if query == "" then
                for _, v in ipairs(allIconPaths) do filteredIcons[#filteredIcons+1] = v end
            else
                for _, v in ipairs(allIconPaths) do
                    if v:lower():find(query, 1, true) then filteredIcons[#filteredIcons+1] = v end
                end
            end
        end
        local totalH    = math.ceil(#filteredIcons / IC_COLS) * IC_CELL
        local maxScroll = math.max(0, totalH - IC_GRID_H)
        sb:SetMinMaxValues(0, maxScroll); sb:SetValue(0)
        scrollOffset = 0
        statusLbl:SetText(#filteredIcons .. " icons")
        UpdateGrid()
    end

    sb:SetScript("OnValueChanged", function(_, v) scrollOffset = v; UpdateGrid() end)
    gridFrame:EnableMouseWheel(true)
    gridFrame:SetScript("OnMouseWheel", function(_, d)
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(mn, math.min(mx, sb:GetValue() - d * IC_CELL * 3)))
    end)

    for i = 1, #pool do
        pool[i]:SetScript("OnClick", function(self)
            if self.iconPath and iconPickerCb then
                iconPickerCb(self.iconPath)
                selectedPath = self.iconPath
                UpdateGrid()
            end
        end)
        pool[i]:SetScript("OnEnter", function(self)
            if self.iconPath then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local name = self.iconPath:match("[^\\/]+$") or self.iconPath
                GameTooltip:SetText(name, 1, 1, 1, 1, true); GameTooltip:Show()
            end
        end)
        pool[i]:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    searchEB:SetScript("OnTextChanged", function(self)
        if searchTimer then searchTimer:Cancel(); searchTimer = nil end
        searchTimer = C_Timer.NewTimer(0.3, function()
            searchTimer = nil; RebuildFiltered(self:GetText())
        end)
    end)

    f.Reopen = function(currentPath)
        selectedPath = currentPath
        if not allIconPaths then
            allIconPaths = {}
            local seen = {}
            -- GetMacroIconInfo returns (path/fileID, isAtlas). Atlas icons need
            -- SetAtlas, not SetTexture, so we skip them here.
            local n = GetNumMacroIcons and GetNumMacroIcons() or 0
            for i = 1, n do
                local p, isAtlas = GetMacroIconInfo and GetMacroIconInfo(i)
                if p and p ~= "" and not isAtlas then
                    if not seen[p] then seen[p] = true; allIconPaths[#allIconPaths+1] = p end
                end
            end
            -- Fallback: derive icons from spell textures if the macro API gave nothing
            -- (happens when all macro icons are atlas-based in this client version).
            if #allIconPaths == 0 then
                for spellId = 1, 50000 do
                    local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
                             or (GetSpellTexture and GetSpellTexture(spellId))
                    if tex and not seen[tex] then
                        seen[tex] = true; allIconPaths[#allIconPaths+1] = tex
                    end
                end
            end
        end
        searchEB:SetText(""); searchEB:SetFocus()
        RebuildFiltered("")
    end

    f:Hide()
    iconPickerFrame = f
end

local function ShowIconPicker(callback, currentPath)
    iconPickerCb = callback
    if not iconPickerFrame then BuildIconPicker() end
    iconPickerFrame.Reopen(currentPath)
    iconPickerFrame:Show()
end

-- =============================================================================
-- BuildUI
-- =============================================================================

function BossModModule:BuildUI(parent, db)
    RegisterBW(); RegisterDBM()

    local SelectEntry    -- forward-declared so all closures below capture the same upvalue
    local RefreshSidebar -- forward-declared
    local RefreshPreview -- forward-declared
    local ShowCtxMenu    -- forward-declared

    local SB_W    = 220
    local ROW_H   = 44
    local INDENT  = 14

    -- -------------------------------------------------------------------------
    -- Sidebar
    -- -------------------------------------------------------------------------
    local sbBg = parent:CreateTexture(nil, "BACKGROUND")
    sbBg:SetColorTexture(0.05, 0.05, 0.05, 1)
    sbBg:SetPoint("TOPLEFT", parent, "TOPLEFT")
    sbBg:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    sbBg:SetWidth(SB_W)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(SB_W - 10, 22)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    addBtn:SetText("+ Add New")

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     addBtn,  "BOTTOMLEFT",  0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent,  "BOTTOMLEFT",  SB_W - 20, -4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(SB_W - 22)
    scrollFrame:SetScrollChild(scrollChild)

    -- Separator
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.3, 1); sep:SetWidth(1)
    sep:SetPoint("TOPLEFT",    parent, "TOPLEFT",    SB_W, 0)
    sep:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", SB_W, 0)

    -- -------------------------------------------------------------------------
    -- Right panel
    -- -------------------------------------------------------------------------
    local rp = CreateFrame("Frame", nil, parent)
    rp:SetPoint("TOPLEFT",     parent, "TOPLEFT",     SB_W + 4, 0)
    rp:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    -- Placeholder
    local placeholder = rp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER", rp, "CENTER")
    placeholder:SetText('Select an entry or click  "+ Add New"')
    placeholder:SetTextColor(0.5, 0.5, 0.5)

    -- -------------------------------------------------------------------------
    -- Type picker
    -- -------------------------------------------------------------------------
    local typePicker = CreateFrame("Frame", nil, rp)
    typePicker:SetAllPoints(rp); typePicker:Hide()
    do
        local hdr = typePicker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOP", typePicker, "TOP", 0, -20); hdr:SetText("Choose Entry Type")
        local types = {
            { label="Icon",         typ="icon",  desc="Spell icon with configurable text label" },
            { label="Text",         typ="text",  desc="Text label only, no icon" },
            { label="Progress Bar", typ="bar",   desc="Countdown bar synced to boss mod timer" },
            { label="Group",        typ="group", desc="Container: positions entries in a stack" },
        }
        for i, t in ipairs(types) do
            local tb = CreateFrame("Button", nil, typePicker, "BackdropTemplate")
            tb:SetSize(480, 40)
            tb:SetPoint("TOP", typePicker, "TOP", 0, -40 - (i-1) * 50)
            tb:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 })
            tb:SetBackdropColor(0.1, 0.18, 0.4, 1); tb:SetBackdropBorderColor(0.35, 0.55, 1, 1)
            local tl = tb:CreateFontString(nil,"OVERLAY","GameFontNormal")
            tl:SetPoint("LEFT", tb, "LEFT", 14, 0); tl:SetText(t.label)
            local td = tb:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            td:SetPoint("LEFT", tl, "RIGHT", 10, 0); td:SetText("— " .. t.desc); td:SetTextColor(0.7,0.7,0.7)
            tb:SetScript("OnEnter", function(s) s:SetBackdropColor(0.15,0.28,0.6,1) end)
            tb:SetScript("OnLeave", function(s) s:SetBackdropColor(0.1,0.18,0.4,1) end)
            local et = t.typ
            tb:SetScript("OnClick", function()
                local e = NewEntry(et)
                table.insert(db.bossmods.topLevel, 1, e.id)
                typePicker:Hide()
                SelectEntry(e)
                RefreshSidebar()
            end)
        end
    end

    -- -------------------------------------------------------------------------
    -- Settings panel scaffold
    -- -------------------------------------------------------------------------
    local sp = CreateFrame("Frame", nil, rp)
    sp:SetAllPoints(rp); sp:Hide()

    -- Name row
    local nameLabel = sp:CreateFontString(nil,"OVERLAY","GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", sp, "TOPLEFT", 4, -8); nameLabel:SetText("Name:")
    local nameEB = CreateFrame("EditBox", nil, sp, "InputBoxTemplate")
    nameEB:SetSize(220, 20); nameEB:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0); nameEB:SetAutoFocus(false)
    local delBtn = CreateFrame("Button", nil, sp, "UIPanelButtonTemplate")
    delBtn:SetSize(64, 20); delBtn:SetPoint("LEFT", nameEB, "RIGHT", 8, 0); delBtn:SetText("Delete")

    -- Sub-tabs: Display | Trigger | Load | Conditions
    local SUB_NAMES = { "Display", "Trigger", "Load", "Conditions" }
    local subBtns, subConts = {}, {}
    local activeSub = 1

    local function PickSub(idx)
        activeSub = idx
        for i = 1, #subBtns do
            subConts[i]:SetShown(i == idx)
            subBtns[i]:SetBackdropColor(i==idx and 0.12 or 0.05, i==idx and 0.26 or 0.05, i==idx and 0.6 or 0.05, 1)
        end
    end

    for i, n in ipairs(SUB_NAMES) do
        local bt = CreateFrame("Button", nil, sp, "BackdropTemplate")
        bt:SetSize(82, 22); bt:SetPoint("TOPLEFT", sp, "TOPLEFT", (i-1)*86 + 4, -36)
        bt:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 })
        bt:SetBackdropColor(0.05, 0.05, 0.05, 1); bt:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        local bfs = bt:CreateFontString(nil,"OVERLAY","GameFontNormal"); bfs:SetAllPoints(); bfs:SetJustifyH("CENTER"); bfs:SetText(n)
        local ii = i
        bt:SetScript("OnEnter", function(s) if activeSub ~= ii then s:SetBackdropColor(0.09,0.12,0.28,1) end end)
        bt:SetScript("OnLeave", function(s) if activeSub ~= ii then s:SetBackdropColor(0.05,0.05,0.05,1) end end)
        bt:SetScript("OnClick", function() PickSub(ii) end)
        subBtns[i] = bt

        local sc = CreateFrame("Frame", nil, sp)
        sc:SetPoint("TOPLEFT",     sp, "TOPLEFT",     4, -62)
        sc:SetPoint("BOTTOMRIGHT", sp, "BOTTOMRIGHT", -4, 0)
        sc:Hide(); subConts[i] = sc
    end

    local displayCont = subConts[1]
    local trigCont    = subConts[2]
    local loadCont    = subConts[3]
    local condCont    = subConts[4]

    -- =============================================
    -- Shared entry reference pointer
    -- =============================================
    local ref = {}  -- ref.e = current entry; all widget callbacks close over ref

    -- =============================================
    -- Context menu frames (created once, reused)
    -- =============================================
    local CTX_W, CTX_ITEM_H = 200, 22
    local ctxBD = { bgFile="Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1,
        tile=true, tileSize=32, insets={left=2,right=2,top=2,bottom=2} }

    -- Transparent full-screen capture frame — closes menus on outside click
    local ctxCapture = CreateFrame("Frame", nil, UIParent)
    ctxCapture:SetAllPoints(UIParent); ctxCapture:EnableMouse(true)
    ctxCapture:SetFrameStrata("FULLSCREEN"); ctxCapture:Hide()

    local ctxMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ctxMenu:SetFrameStrata("FULLSCREEN_DIALOG"); ctxMenu:SetWidth(CTX_W)
    ctxMenu:SetBackdrop(ctxBD)
    ctxMenu:SetBackdropColor(0.08,0.08,0.08,0.97); ctxMenu:SetBackdropBorderColor(0.45,0.45,0.45,1)
    ctxMenu:Hide()

    local ctxSub = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ctxSub:SetFrameStrata("FULLSCREEN_DIALOG"); ctxSub:SetWidth(CTX_W)
    ctxSub:SetFrameLevel(ctxMenu:GetFrameLevel() + 1)
    ctxSub:SetBackdrop(ctxBD)
    ctxSub:SetBackdropColor(0.08,0.08,0.08,0.97); ctxSub:SetBackdropBorderColor(0.45,0.45,0.45,1)
    ctxSub:Hide()
    ctxSub:SetScript("OnLeave", function(self) self:Hide() end)

    ctxCapture:SetScript("OnMouseDown", function()
        ctxMenu:Hide(); ctxSub:Hide(); ctxCapture:Hide()
    end)

    -- Pre-build button pools
    local function MakeMenuBtn(parent, i)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(CTX_ITEM_H)
        btn:SetPoint("TOPLEFT",  parent, "TOPLEFT",  2, -(i-1)*CTX_ITEM_H - 2)
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -(i-1)*CTX_ITEM_H - 2)
        local hl = btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.1)
        local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontNormal")
        lbl:SetPoint("LEFT",btn,"LEFT",8,0); lbl:SetPoint("RIGHT",btn,"RIGHT",-8,0)
        lbl:SetJustifyH("LEFT"); btn.lbl = lbl; btn:Hide()
        return btn
    end
    local cmBtns = {}; for i=1,5  do cmBtns[i] = MakeMenuBtn(ctxMenu, i) end
    local smBtns = {}; for i=1,20 do smBtns[i] = MakeMenuBtn(ctxSub,  i) end

    -- =============================================
    -- DISPLAY TAB
    -- =============================================

    -- Section frames (one per type, swapped in/out)
    local iconSec  = CreateFrame("Frame", nil, displayCont); iconSec:SetAllPoints(displayCont)
    local textSec  = CreateFrame("Frame", nil, displayCont); textSec:SetAllPoints(displayCont)
    local barSec   = CreateFrame("Frame", nil, displayCont); barSec:SetAllPoints(displayCont)
    local grpSec   = CreateFrame("Frame", nil, displayCont); grpSec:SetAllPoints(displayCont)

    -- ---- Icon section widgets ----
    do
        local y = -4
        Label(iconSec, 4, y, "Icon", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(iconSec, 4, y-1, "Size:"); local isizeEB = MakeEB(iconSec, 40, y+2, 44, true)
        isizeEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.iconSize = tonumber(s:GetText()) or 32 end; s:ClearFocus(); RefreshPreview() end)
        isizeEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.iconSize = tonumber(s:GetText()) or 32 end; RefreshPreview() end)
        y = y - 30

        local cbSwipe = CreateFrame("CheckButton", nil, iconSec, "UICheckButtonTemplate")
        cbSwipe:SetSize(24, 24); cbSwipe:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 4, y+3)
        local cbSwipeL = iconSec:CreateFontString(nil,"OVERLAY","GameFontNormal")
        cbSwipeL:SetPoint("LEFT", cbSwipe, "RIGHT", 4, 0); cbSwipeL:SetText("Progress swipe")
        cbSwipe:SetScript("OnClick", function(s) if ref.e then ref.e.iconSwipe = s:GetChecked() end end)
        y = y - 28

        Label(iconSec, 4, y-3, "Duration override:")
        local swipeDurEB = MakeEB(iconSec, 134, y, 56)
        swipeDurEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.durationOverride = s:GetText() end; s:ClearFocus() end)
        swipeDurEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.durationOverride = s:GetText() end end)
        local swipeDurHint = iconSec:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        swipeDurHint:SetPoint("LEFT", swipeDurEB, "RIGHT", 4, 0)
        swipeDurHint:SetText("s  (blank = trigger / event)"); swipeDurHint:SetTextColor(0.5, 0.5, 0.5)
        y = y - 26

        Label(iconSec, 4, y-3, "Override icon:")
        local ovrTex = iconSec:CreateTexture(nil, "ARTWORK")
        ovrTex:SetSize(20, 20); ovrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ovrTex:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 100, y-1); ovrTex:SetAlpha(0.2)
        local ovrEB = MakeEB(iconSec, 124, y, 120)
        local ovrChooseBtn = CreateFrame("Button", nil, iconSec, "UIPanelButtonTemplate")
        ovrChooseBtn:SetSize(60, 20); ovrChooseBtn:SetPoint("LEFT", ovrEB, "RIGHT", 4, 0); ovrChooseBtn:SetText("Choose")
        local ovrClearBtn = CreateFrame("Button", nil, iconSec, "UIPanelButtonTemplate")
        ovrClearBtn:SetSize(48, 20); ovrClearBtn:SetPoint("LEFT", ovrChooseBtn, "RIGHT", 4, 0); ovrClearBtn:SetText("Clear")
        local ovrHint = iconSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ovrHint:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 4, y - 22)
        ovrHint:SetText("Icon file ID (number) or blank to use the BW/DBM icon")
        ovrHint:SetTextColor(0.5, 0.5, 0.5)
        local function ApplyOvrInput()
            if not ref.e then return end
            local txt = ovrEB:GetText()
            ref.e.iconOverrideId = txt
            if txt == "" then
                ovrTex:SetTexture(nil); ovrTex:SetAlpha(0.2)
            else
                local texVal = tonumber(txt) or txt
                ovrTex:SetTexture(texVal); ovrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93); ovrTex:SetAlpha(1)
            end
            RefreshPreview()
        end
        ovrEB:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ApplyOvrInput() end)
        ovrEB:SetScript("OnEditFocusLost", ApplyOvrInput)
        ovrChooseBtn:SetScript("OnClick", function()
            if not ref.e then return end
            ShowIconPicker(function(path)
                ref.e.iconOverrideId = path
                ovrEB:SetText(path)
                ovrTex:SetTexture(path); ovrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93); ovrTex:SetAlpha(1)
                RefreshPreview()
            end, ref.e.iconOverrideId)
        end)
        ovrClearBtn:SetScript("OnClick", function() ovrEB:SetText(""); ApplyOvrInput() end)
        y = y - 44

        Divider(iconSec, y); y = y - 14
        Label(iconSec, 4, y, "Text", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(iconSec, 4, y-4, "Font:")
        local fontOpts = GetFontList()
        local fontDD = ScrollDrop(iconSec, 180, fontOpts,
            function() return ref.e and ref.e.fontName or fontOpts[1] end,
            function(v) if ref.e then ref.e.fontName = v; RefreshPreview() end end, "font")
        fontDD:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 40, y)
        Label(iconSec, 228, y-3, "Size:")
        local fsEB = MakeEB(iconSec, 260, y, 44, true)
        fsEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.fontSize = tonumber(s:GetText()) or 14 end; s:ClearFocus(); RefreshPreview() end)
        fsEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.fontSize = tonumber(s:GetText()) or 14 end; RefreshPreview() end)
        y = y - 28

        Label(iconSec, 4, y-3, "Text color:")
        local tcSwatch = Swatch(iconSec,
            function() return ref.e and ref.e.tcR or 1 end,
            function() return ref.e and ref.e.tcG or 1 end,
            function() return ref.e and ref.e.tcB or 1 end,
            function() return ref.e and ref.e.tcA or 1 end,
            function(r,g,b,a) if ref.e then ref.e.tcR,ref.e.tcG,ref.e.tcB,ref.e.tcA=r,g,b,a; RefreshPreview() end end)
        tcSwatch:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 82, y)

        Label(iconSec, 116, y-4, "Position:")
        local posOpts = {{label="Right",value="RIGHT"},{label="Left",value="LEFT"},{label="Top",value="TOP"},{label="Bottom",value="BOTTOM"}}
        local posDD = ScrollDrop(iconSec, 90, posOpts,
            function() return ref.e and ref.e.textPosition or "RIGHT" end,
            function(v) if ref.e then ref.e.textPosition = v; RefreshPreview() end end)
        posDD:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 172, y)
        y = y - 28

        Label(iconSec, 4, y-3, "Display text:")
        local dispEB = MakeEB(iconSec, 92, y, 300)
        dispEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.displayText = s:GetText() end; s:ClearFocus(); RefreshPreview() end)
        dispEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.displayText = s:GetText() end; RefreshPreview() end)
        local dispHint = iconSec:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        dispHint:SetPoint("TOPLEFT", iconSec, "TOPLEFT", 4, y - 22)
        dispHint:SetText("Leave blank to show the boss mod message.  %m = message  |  %c = count")
        dispHint:SetTextColor(0.5, 0.5, 0.5)

        -- populate for icon section
        iconSec.Populate = function(e)
            isizeEB:SetText(tostring(e.iconSize or 32))
            cbSwipe:SetChecked(e.iconSwipe or false)
            swipeDurEB:SetText(e.durationOverride or "")
            ovrEB:SetText(e.iconOverrideId or "")
            if e.iconOverrideId and e.iconOverrideId ~= "" then
                local texVal = tonumber(e.iconOverrideId) or e.iconOverrideId
                ovrTex:SetTexture(texVal); ovrTex:SetTexCoord(0.07,0.93,0.07,0.93); ovrTex:SetAlpha(1)
            else
                ovrTex:SetTexture(nil); ovrTex:SetAlpha(0.2)
            end
            fontDD.Refresh()
            fsEB:SetText(tostring(e.fontSize or 14))
            tcSwatch.Refresh()
            posDD.Refresh()
            dispEB:SetText(e.displayText or "")
        end
    end

    -- ---- Text section widgets ----
    do
        local y = -4
        Label(textSec, 4, y, "Text", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(textSec, 4, y-4, "Font:")
        local fontOpts = GetFontList()
        local fontDD = ScrollDrop(textSec, 180, fontOpts,
            function() return ref.e and ref.e.fontName or fontOpts[1] end,
            function(v) if ref.e then ref.e.fontName = v; RefreshPreview() end end, "font")
        fontDD:SetPoint("TOPLEFT", textSec, "TOPLEFT", 40, y)
        Label(textSec, 228, y-3, "Size:")
        local fsEB = MakeEB(textSec, 260, y, 44, true)
        fsEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.fontSize = tonumber(s:GetText()) or 14 end; s:ClearFocus(); RefreshPreview() end)
        fsEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.fontSize = tonumber(s:GetText()) or 14 end; RefreshPreview() end)
        y = y - 28

        Label(textSec, 4, y-3, "Text color:")
        local tcSwatch = Swatch(textSec,
            function() return ref.e and ref.e.tcR or 1 end,
            function() return ref.e and ref.e.tcG or 1 end,
            function() return ref.e and ref.e.tcB or 1 end,
            function() return ref.e and ref.e.tcA or 1 end,
            function(r,g,b,a) if ref.e then ref.e.tcR,ref.e.tcG,ref.e.tcB,ref.e.tcA=r,g,b,a; RefreshPreview() end end)
        tcSwatch:SetPoint("TOPLEFT", textSec, "TOPLEFT", 82, y)
        y = y - 28

        Label(textSec, 4, y-3, "Display text:")
        local dispEB = MakeEB(textSec, 92, y, 300)
        dispEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.displayText = s:GetText() end; s:ClearFocus(); RefreshPreview() end)
        dispEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.displayText = s:GetText() end; RefreshPreview() end)
        local dispHint = textSec:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        dispHint:SetPoint("TOPLEFT", textSec, "TOPLEFT", 4, y - 22)
        dispHint:SetText("Leave blank to show the boss mod message.  %m = message  |  %c = count")
        dispHint:SetTextColor(0.5, 0.5, 0.5)

        textSec.Populate = function(e)
            fontDD.Refresh()
            fsEB:SetText(tostring(e.fontSize or 14))
            tcSwatch.Refresh()
            dispEB:SetText(e.displayText or "")
        end
    end

    -- ---- Bar section widgets ----
    do
        local y = -4
        Label(barSec, 4, y, "Bar", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(barSec, 4, y-4, "Texture:")
        local texOpts = GetTexList()
        local texDD = ScrollDrop(barSec, 180, texOpts,
            function() return ref.e and ref.e.barTexName or texOpts[1] end,
            function(v) if ref.e then ref.e.barTexName = v; RefreshPreview() end end, "texture")
        texDD:SetPoint("TOPLEFT", barSec, "TOPLEFT", 60, y)
        y = y - 28

        Label(barSec, 4, y-3, "Bar color:")
        local bcSwatch = Swatch(barSec,
            function() return ref.e and ref.e.bcR or 0.2 end,
            function() return ref.e and ref.e.bcG or 0.8 end,
            function() return ref.e and ref.e.bcB or 0.2 end,
            function() return ref.e and ref.e.bcA or 1   end,
            function(r,g,b,a) if ref.e then ref.e.bcR,ref.e.bcG,ref.e.bcB,ref.e.bcA=r,g,b,a; RefreshPreview() end end)
        bcSwatch:SetPoint("TOPLEFT", barSec, "TOPLEFT", 68, y)

        Label(barSec, 100, y-3, "Width:")
        local bwEB = MakeEB(barSec, 138, y, 52, true)
        bwEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.barWidth = tonumber(s:GetText()) or 220 end; s:ClearFocus(); RefreshPreview() end)
        bwEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.barWidth = tonumber(s:GetText()) or 220 end; RefreshPreview() end)
        Label(barSec, 198, y-3, "Height:")
        local bhEB = MakeEB(barSec, 242, y, 44, true)
        bhEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.barHeight = tonumber(s:GetText()) or 22 end; s:ClearFocus(); RefreshPreview() end)
        bhEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.barHeight = tonumber(s:GetText()) or 22 end; RefreshPreview() end)
        y = y - 28

        local cbBI = CreateFrame("CheckButton", nil, barSec, "UICheckButtonTemplate")
        cbBI:SetSize(24, 24); cbBI:SetPoint("TOPLEFT", barSec, "TOPLEFT", 4, y+3)
        local cbBIL = barSec:CreateFontString(nil,"OVERLAY","GameFontNormal"); cbBIL:SetPoint("LEFT",cbBI,"RIGHT",4,0); cbBIL:SetText("Enable icon")
        cbBI:SetScript("OnClick", function(s) if ref.e then ref.e.iconEnabled = s:GetChecked(); RefreshPreview() end end)

        local cbHT = CreateFrame("CheckButton", nil, barSec, "UICheckButtonTemplate")
        cbHT:SetSize(24, 24); cbHT:SetPoint("LEFT", cbBIL, "RIGHT", 24, 0)
        local cbHTL = barSec:CreateFontString(nil,"OVERLAY","GameFontNormal"); cbHTL:SetPoint("LEFT",cbHT,"RIGHT",4,0); cbHTL:SetText("Hide timer text")
        cbHT:SetScript("OnClick", function(s) if ref.e then ref.e.barHideTimer = s:GetChecked(); RefreshPreview() end end)
        y = y - 28

        local cbBarSwipe = CreateFrame("CheckButton", nil, barSec, "UICheckButtonTemplate")
        cbBarSwipe:SetSize(24, 24); cbBarSwipe:SetPoint("TOPLEFT", barSec, "TOPLEFT", 4, y+3)
        local cbBarSwipeL = barSec:CreateFontString(nil,"OVERLAY","GameFontNormal")
        cbBarSwipeL:SetPoint("LEFT", cbBarSwipe, "RIGHT", 4, 0); cbBarSwipeL:SetText("Progress swipe on icon")
        cbBarSwipe:SetScript("OnClick", function(s) if ref.e then ref.e.iconSwipe = s:GetChecked() end end)
        y = y - 28

        Label(barSec, 4, y-3, "Duration override:")
        local barDurOvrEB = MakeEB(barSec, 134, y, 56)
        barDurOvrEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.durationOverride = s:GetText() end; s:ClearFocus() end)
        barDurOvrEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.durationOverride = s:GetText() end end)
        local barDurOvrHint = barSec:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        barDurOvrHint:SetPoint("LEFT", barDurOvrEB, "RIGHT", 4, 0)
        barDurOvrHint:SetText("s  (blank = trigger / event)"); barDurOvrHint:SetTextColor(0.5, 0.5, 0.5)
        y = y - 26

        Label(barSec, 4, y-3, "Override icon:")
        local barOvrTex = barSec:CreateTexture(nil, "ARTWORK")
        barOvrTex:SetSize(20, 20); barOvrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        barOvrTex:SetPoint("TOPLEFT", barSec, "TOPLEFT", 100, y-1); barOvrTex:SetAlpha(0.2)
        local barOvrEB = MakeEB(barSec, 124, y, 120)
        local barOvrChooseBtn = CreateFrame("Button", nil, barSec, "UIPanelButtonTemplate")
        barOvrChooseBtn:SetSize(60, 20); barOvrChooseBtn:SetPoint("LEFT", barOvrEB, "RIGHT", 4, 0); barOvrChooseBtn:SetText("Choose")
        local barOvrClearBtn = CreateFrame("Button", nil, barSec, "UIPanelButtonTemplate")
        barOvrClearBtn:SetSize(48, 20); barOvrClearBtn:SetPoint("LEFT", barOvrChooseBtn, "RIGHT", 4, 0); barOvrClearBtn:SetText("Clear")
        local barOvrHint = barSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        barOvrHint:SetPoint("TOPLEFT", barSec, "TOPLEFT", 4, y - 22)
        barOvrHint:SetText("Icon file ID (number) or blank to use the BW/DBM icon")
        barOvrHint:SetTextColor(0.5, 0.5, 0.5)
        local function ApplyBarOvrInput()
            if not ref.e then return end
            local txt = barOvrEB:GetText()
            ref.e.iconOverrideId = txt
            if txt == "" then
                barOvrTex:SetTexture(nil); barOvrTex:SetAlpha(0.2)
            else
                local texVal = tonumber(txt) or txt
                barOvrTex:SetTexture(texVal); barOvrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93); barOvrTex:SetAlpha(1)
            end
            RefreshPreview()
        end
        barOvrEB:SetScript("OnEnterPressed", function(s) s:ClearFocus(); ApplyBarOvrInput() end)
        barOvrEB:SetScript("OnEditFocusLost", ApplyBarOvrInput)
        barOvrChooseBtn:SetScript("OnClick", function()
            if not ref.e then return end
            ShowIconPicker(function(path)
                ref.e.iconOverrideId = path
                barOvrEB:SetText(path)
                barOvrTex:SetTexture(path); barOvrTex:SetTexCoord(0.07, 0.93, 0.07, 0.93); barOvrTex:SetAlpha(1)
                RefreshPreview()
            end, ref.e.iconOverrideId)
        end)
        barOvrClearBtn:SetScript("OnClick", function() barOvrEB:SetText(""); ApplyBarOvrInput() end)
        y = y - 44

        Divider(barSec, y); y = y - 14
        Label(barSec, 4, y, "Text", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(barSec, 4, y-4, "Font:")
        local bfOpts = GetFontList()
        local bfDD = ScrollDrop(barSec, 180, bfOpts,
            function() return ref.e and ref.e.barFontName or bfOpts[1] end,
            function(v) if ref.e then ref.e.barFontName = v; RefreshPreview() end end, "font")
        bfDD:SetPoint("TOPLEFT", barSec, "TOPLEFT", 40, y)
        Label(barSec, 228, y-3, "Size:")
        local bfsEB = MakeEB(barSec, 260, y, 44, true)
        bfsEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.barFontSize = tonumber(s:GetText()) or 12 end; s:ClearFocus(); RefreshPreview() end)
        bfsEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.barFontSize = tonumber(s:GetText()) or 12 end; RefreshPreview() end)
        y = y - 28

        Label(barSec, 4, y-3, "Text color:")
        local btcSwatch = Swatch(barSec,
            function() return ref.e and ref.e.btcR or 1 end,
            function() return ref.e and ref.e.btcG or 1 end,
            function() return ref.e and ref.e.btcB or 1 end,
            function() return ref.e and ref.e.btcA or 1 end,
            function(r,g,b,a) if ref.e then ref.e.btcR,ref.e.btcG,ref.e.btcB,ref.e.btcA=r,g,b,a; RefreshPreview() end end)
        btcSwatch:SetPoint("TOPLEFT", barSec, "TOPLEFT", 74, y)

        Label(barSec, 106, y-4, "Position:")
        local btpOpts = {{label="Center",value="CENTER"},{label="Left",value="LEFT"},{label="Right",value="RIGHT"}}
        local btpDD = ScrollDrop(barSec, 90, btpOpts,
            function() return ref.e and ref.e.barTextPos or "CENTER" end,
            function(v) if ref.e then ref.e.barTextPos = v; RefreshPreview() end end)
        btpDD:SetPoint("TOPLEFT", barSec, "TOPLEFT", 162, y)
        y = y - 28

        Label(barSec, 4, y-3, "Display text:")
        local bDispEB = MakeEB(barSec, 92, y, 300)
        bDispEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.displayText = s:GetText() end; s:ClearFocus(); RefreshPreview() end)
        bDispEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.displayText = s:GetText() end; RefreshPreview() end)
        local bDispHint = barSec:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        bDispHint:SetPoint("TOPLEFT", barSec, "TOPLEFT", 4, y - 22)
        bDispHint:SetText("Leave blank to show the boss mod message.  %m = message  |  %c = count  |  %t = time left")
        bDispHint:SetTextColor(0.5, 0.5, 0.5)

        barSec.Populate = function(e)
            texDD.Refresh(); bcSwatch.Refresh()
            bwEB:SetText(tostring(e.barWidth or 220))
            bhEB:SetText(tostring(e.barHeight or 22))
            cbBI:SetChecked(e.iconEnabled)
            cbHT:SetChecked(e.barHideTimer or false)
            cbBarSwipe:SetChecked(e.iconSwipe or false)
            barDurOvrEB:SetText(e.durationOverride or "")
            barOvrEB:SetText(e.iconOverrideId or "")
            if e.iconOverrideId and e.iconOverrideId ~= "" then
                local texVal = tonumber(e.iconOverrideId) or e.iconOverrideId
                barOvrTex:SetTexture(texVal); barOvrTex:SetTexCoord(0.07,0.93,0.07,0.93); barOvrTex:SetAlpha(1)
            else
                barOvrTex:SetTexture(nil); barOvrTex:SetAlpha(0.2)
            end
            bfDD.Refresh()
            bfsEB:SetText(tostring(e.barFontSize or 12))
            btcSwatch.Refresh(); btpDD.Refresh()
            bDispEB:SetText(e.displayText or "")
        end
    end

    -- ---- Group section widgets ----
    do
        local y = -4
        Label(grpSec, 4, y, "Group Layout", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        Label(grpSec, 4, y-4, "Growth direction:")
        local gdOpts = {{label="Down",value="DOWN"},{label="Up",value="UP"},{label="Right",value="RIGHT"},{label="Left",value="LEFT"}}
        local gdDD = ScrollDrop(grpSec, 100, gdOpts,
            function() return ref.e and ref.e.growthDir or "DOWN" end,
            function(v) if ref.e then ref.e.growthDir = v; RefreshPreview() end end)
        gdDD:SetPoint("TOPLEFT", grpSec, "TOPLEFT", 124, y)
        y = y - 28

        Label(grpSec, 4, y-3, "Spacing:")
        local spEB = MakeEB(grpSec, 64, y, 44, true)
        spEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.spacing = tonumber(s:GetText()) or 4 end; s:ClearFocus(); RefreshPreview() end)
        spEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.spacing = tonumber(s:GetText()) or 4 end; RefreshPreview() end)
        y = y - 28

        Divider(grpSec, y); y = y - 14
        local memHdr = Label(grpSec, 4, y, "Members:", "GameFontNormal"); y = y - 24

        -- Member list (rebuilt on populate)
        local memberContainer = CreateFrame("Frame", nil, grpSec)
        memberContainer:SetPoint("TOPLEFT",     grpSec, "TOPLEFT",     4, y)
        memberContainer:SetPoint("BOTTOMRIGHT", grpSec, "BOTTOMRIGHT", -4, 30)

        local addMemberBtn = CreateFrame("Button", nil, grpSec, "UIPanelButtonTemplate")
        addMemberBtn:SetSize(100, 20)
        addMemberBtn:SetPoint("BOTTOMLEFT", grpSec, "BOTTOMLEFT", 4, 4)
        addMemberBtn:SetText("Add member")

        -- Popup for member picker
        local memberPickerPopup = CreateFrame("Frame", nil, grpSec, "BackdropTemplate")
        memberPickerPopup:SetSize(200, 160)
        memberPickerPopup:SetFrameLevel(grpSec:GetFrameLevel() + 60)
        memberPickerPopup:SetBackdrop({ bgFile="Interface/DialogFrame/UI-DialogBox-Background",
            edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1, tile=true, tileSize=32,
            insets={left=2,right=2,top=2,bottom=2} })
        memberPickerPopup:SetBackdropColor(0.08,0.08,0.08,0.97)
        memberPickerPopup:SetBackdropBorderColor(0.5,0.5,0.5,1)
        memberPickerPopup:SetPoint("BOTTOMLEFT", addMemberBtn, "TOPLEFT", 0, 2)
        memberPickerPopup:Hide()

        addMemberBtn:SetScript("OnClick", function()
            if memberPickerPopup:IsShown() then memberPickerPopup:Hide(); return end
            -- Rebuild picker list
            for _, c in ipairs({ memberPickerPopup:GetChildren() }) do c:Hide() end
            local lh = 22
            local candidates = {}
            for id, e in pairs(db.bossmods.entries) do
                if e.type ~= "group" and (not e.groupId) then
                    table.insert(candidates, e)
                end
            end
            table.sort(candidates, function(a,b) return a.id < b.id end)
            memberPickerPopup:SetHeight(math.max(40, #candidates * lh + 8))
            local py = -4
            for _, cand in ipairs(candidates) do
                local row = CreateFrame("Button", nil, memberPickerPopup)
                row:SetSize(196, lh)
                row:SetPoint("TOPLEFT", memberPickerPopup, "TOPLEFT", 2, py)
                local hl = row:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.1)
                local lbl2 = row:CreateFontString(nil,"OVERLAY","GameFontNormal"); lbl2:SetPoint("LEFT",row,"LEFT",6,0); lbl2:SetText(cand.name or "?")
                local cid = cand.id
                row:SetScript("OnClick", function()
                    if not ref.e or ref.e.type ~= "group" then return end
                    cand.groupId = ref.e.id
                    table.insert(ref.e.children, cid)
                    -- Remove from topLevel
                    for i, tid in ipairs(db.bossmods.topLevel) do
                        if tid == cid then table.remove(db.bossmods.topLevel, i); break end
                    end
                    memberPickerPopup:Hide()
                    grpSec.Populate(ref.e)
                    RefreshSidebar()
                end)
                py = py - lh
            end
            if #candidates == 0 then
                local nl = memberPickerPopup:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                nl:SetPoint("CENTER", memberPickerPopup, "CENTER"); nl:SetText("No ungrouped entries"); nl:SetTextColor(0.6,0.6,0.6)
            end
            memberPickerPopup:Show()
        end)
        grpSec:HookScript("OnHide", function() memberPickerPopup:Hide() end)

        grpSec.Populate = function(e)
            gdDD.Refresh()
            spEB:SetText(tostring(e.spacing or 4))
            -- Rebuild member list
            for _, c in ipairs({ memberContainer:GetChildren() }) do c:Hide() end
            local mh = 20
            local my = 0
            for _, cid in ipairs(e.children) do
                local ce = db.bossmods.entries[cid]
                if ce then
                    local mrow = CreateFrame("Button", nil, memberContainer)
                    mrow:SetSize(memberContainer:GetWidth() - 80, mh)
                    mrow:SetPoint("TOPLEFT", memberContainer, "TOPLEFT", 0, -my)
                    local ml = mrow:CreateFontString(nil,"OVERLAY","GameFontNormal")
                    ml:SetPoint("LEFT",mrow,"LEFT"); ml:SetText(ce.name or "?")
                    local rmBtn = CreateFrame("Button", nil, memberContainer, "UIPanelButtonTemplate")
                    rmBtn:SetSize(60, mh); rmBtn:SetPoint("LEFT", mrow, "RIGHT", 4, 0); rmBtn:SetText("Remove")
                    local rcid = cid
                    rmBtn:SetScript("OnClick", function()
                        ce.groupId = nil
                        table.insert(db.bossmods.topLevel, rcid)
                        for i, c2 in ipairs(e.children) do
                            if c2 == rcid then table.remove(e.children, i); break end
                        end
                        grpSec.Populate(e)
                        RefreshSidebar()
                    end)
                    my = my + mh + 2
                end
            end
        end
    end

    -- =============================================
    -- TRIGGER TAB
    -- =============================================
    do
        local y = -4
        Label(trigCont, 4, y, "Trigger Type", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 22

        local rbTmr = CreateFrame("CheckButton", nil, trigCont, "UIRadioButtonTemplate")
        rbTmr:SetSize(24, 24); rbTmr:SetPoint("TOPLEFT", trigCont, "TOPLEFT", 4, y+3)
        local rbTmrL = trigCont:CreateFontString(nil,"OVERLAY","GameFontNormal"); rbTmrL:SetPoint("LEFT",rbTmr,"RIGHT",2,0); rbTmrL:SetText("Timer (countdown bar)")
        local rbAnn = CreateFrame("CheckButton", nil, trigCont, "UIRadioButtonTemplate")
        rbAnn:SetSize(24, 24); rbAnn:SetPoint("LEFT", rbTmrL, "RIGHT", 20, 0)
        local rbAnnL = trigCont:CreateFontString(nil,"OVERLAY","GameFontNormal"); rbAnnL:SetPoint("LEFT",rbAnn,"RIGHT",2,0); rbAnnL:SetText("Announce (message)")
        y = y - 28

        Divider(trigCont, y); y = y - 10

        -- Announce section
        local annSec = CreateFrame("Frame", nil, trigCont)
        annSec:SetPoint("TOPLEFT",  trigCont, "TOPLEFT", 0, y)
        annSec:SetPoint("TOPRIGHT", trigCont, "TOPRIGHT", 0, y)
        annSec:SetHeight(120)
        do
            local ay = -4
            Label(annSec, 4, ay, "Announce Filters", "GameFontNormal"):SetTextColor(0.8,0.8,0.8); ay = ay - 22
            Label(annSec, 4, ay-3, "Spell ID (blank=any):")
            local annSI = MakeEB(annSec, 148, ay, 80)
            local annSpellIcon = CreateFrame("Button", nil, annSec)
            annSpellIcon:SetSize(22, 22); annSpellIcon:SetPoint("LEFT", annSI, "RIGHT", 4, 0); annSpellIcon:EnableMouse(true)
            local annSITex = annSpellIcon:CreateTexture(nil, "ARTWORK"); annSITex:SetAllPoints(); annSITex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            annSpellIcon:Hide()
            local function UpdateAnnSpellIcon(sid)
                sid = tonumber(sid)
                if not sid or sid == 0 then annSpellIcon:Hide(); return end
                local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
                         or (GetSpellTexture and GetSpellTexture(sid))
                if tex then annSITex:SetTexture(tex); annSpellIcon.spellId = sid; annSpellIcon:Show()
                else annSpellIcon:Hide() end
            end
            annSpellIcon:SetScript("OnEnter", function(self)
                if self.spellId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(self.spellId)
                    GameTooltip:Show()
                end
            end)
            annSpellIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            annSI:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.annSpellId = s:GetText() end; s:ClearFocus(); UpdateAnnSpellIcon(s:GetText()) end)
            annSI:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.annSpellId = s:GetText() end; UpdateAnnSpellIcon(s:GetText()) end)
            ay = ay - 26
            Label(annSec, 4, ay-3, "Message:")
            local annTxt = MakeEB(annSec, 64, ay, 200)
            annTxt:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.annText = s:GetText() end; s:ClearFocus() end)
            annTxt:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.annText = s:GetText() end end)
            local opOpts = {{label="Contains",value="find"},{label="Equals",value="=="},{label="Pattern",value="match"}}
            local annOpDD = ScrollDrop(annSec, 90, opOpts,
                function() return ref.e and ref.e.annTextOp or "find" end,
                function(v) if ref.e then ref.e.annTextOp = v end end)
            annOpDD:SetPoint("TOPLEFT", annSec, "TOPLEFT", 272, ay)
            ay = ay - 26
            Label(annSec, 4, ay-3, "Count (blank=any):")
            local annCnt = MakeEB(annSec, 140, ay, 60)
            annCnt:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.annCount = s:GetText() end; s:ClearFocus() end)
            annCnt:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.annCount = s:GetText() end end)
            Label(annSec, 210, ay-3, "Display for:")
            local annDur = MakeEB(annSec, 284, ay, 44, true)
            annDur:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.annDuration = tonumber(s:GetText()) or 5 end; s:ClearFocus() end)
            annDur:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.annDuration = tonumber(s:GetText()) or 5 end end)
            Label(annSec, 334, ay-3, "seconds")
            annSec.Populate = function(e)
                annSI:SetText(e.annSpellId or "")
                UpdateAnnSpellIcon(e.annSpellId or "")
                annTxt:SetText(e.annText or "")
                annOpDD.Refresh()
                annCnt:SetText(e.annCount or "")
                annDur:SetText(tostring(e.annDuration or 5))
            end
        end

        -- Timer section
        local tmrSec = CreateFrame("Frame", nil, trigCont)
        tmrSec:SetPoint("TOPLEFT",  trigCont, "TOPLEFT", 0, y)
        tmrSec:SetPoint("TOPRIGHT", trigCont, "TOPRIGHT", 0, y)
        tmrSec:SetHeight(130)
        do
            local ty = -4
            Label(tmrSec, 4, ty, "Timer Filters", "GameFontNormal"):SetTextColor(0.8,0.8,0.8); ty = ty - 22
            Label(tmrSec, 4, ty-3, "Spell ID (blank=any):")
            local tmrSI = MakeEB(tmrSec, 148, ty, 80)
            local tmrSpellIcon = CreateFrame("Button", nil, tmrSec)
            tmrSpellIcon:SetSize(22, 22); tmrSpellIcon:SetPoint("LEFT", tmrSI, "RIGHT", 4, 0); tmrSpellIcon:EnableMouse(true)
            local tmrSITex = tmrSpellIcon:CreateTexture(nil, "ARTWORK"); tmrSITex:SetAllPoints(); tmrSITex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            tmrSpellIcon:Hide()
            local function UpdateTmrSpellIcon(sid)
                sid = tonumber(sid)
                if not sid or sid == 0 then tmrSpellIcon:Hide(); return end
                local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
                         or (GetSpellTexture and GetSpellTexture(sid))
                if tex then tmrSITex:SetTexture(tex); tmrSpellIcon.spellId = sid; tmrSpellIcon:Show()
                else tmrSpellIcon:Hide() end
            end
            tmrSpellIcon:SetScript("OnEnter", function(self)
                if self.spellId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(self.spellId)
                    GameTooltip:Show()
                end
            end)
            tmrSpellIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tmrSI:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.tmrSpellId = s:GetText() end; s:ClearFocus(); UpdateTmrSpellIcon(s:GetText()) end)
            tmrSI:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.tmrSpellId = s:GetText() end; UpdateTmrSpellIcon(s:GetText()) end)
            ty = ty - 26
            Label(tmrSec, 4, ty-3, "Bar text:")
            local tmrTxt = MakeEB(tmrSec, 66, ty, 200)
            tmrTxt:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.tmrText = s:GetText() end; s:ClearFocus() end)
            tmrTxt:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.tmrText = s:GetText() end end)
            local topOpts = {{label="Contains",value="find"},{label="Equals",value="=="},{label="Pattern",value="match"}}
            local tmrOpDD = ScrollDrop(tmrSec, 90, topOpts,
                function() return ref.e and ref.e.tmrTextOp or "find" end,
                function(v) if ref.e then ref.e.tmrTextOp = v end end)
            tmrOpDD:SetPoint("TOPLEFT", tmrSec, "TOPLEFT", 274, ty)
            ty = ty - 26
            Label(tmrSec, 4, ty-3, "Count (blank=any):")
            local tmrCnt = MakeEB(tmrSec, 140, ty, 60)
            tmrCnt:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.tmrCount = s:GetText() end; s:ClearFocus() end)
            tmrCnt:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.tmrCount = s:GetText() end end)
            ty = ty - 26
            Label(tmrSec, 4, ty-3, "Show when < ")
            local tmrRem = MakeEB(tmrSec, 100, ty, 52)
            tmrRem:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.tmrRemaining = s:GetText() end; s:ClearFocus() end)
            tmrRem:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.tmrRemaining = s:GetText() end end)
            Label(tmrSec, 158, ty-3, "s remain  (blank = show on start)")
            tmrSec.Populate = function(e)
                tmrSI:SetText(e.tmrSpellId or "")
                UpdateTmrSpellIcon(e.tmrSpellId or "")
                tmrTxt:SetText(e.tmrText or "")
                tmrOpDD.Refresh()
                tmrCnt:SetText(e.tmrCount or "")
                tmrRem:SetText(e.tmrRemaining or "")
            end
        end

        -- Common filters
        local comY = y - 140
        Divider(trigCont, comY); comY = comY - 12
        Label(trigCont, 4, comY-3, "Boss stage (blank=any):")
        local stgEB = MakeEB(trigCont, 162, comY, 60)
        stgEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.trigStage = s:GetText() end; s:ClearFocus() end)
        stgEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.trigStage = s:GetText() end end)

        -- Radio logic
        local function SetTrigType(t)
            if ref.e then ref.e.triggerType = t end
            rbAnn:SetChecked(t == "announce")
            rbTmr:SetChecked(t == "timer")
            annSec:SetShown(t == "announce")
            tmrSec:SetShown(t == "timer")
        end
        rbAnn:SetScript("OnClick", function() SetTrigType("announce") end)
        rbTmr:SetScript("OnClick", function() SetTrigType("timer") end)

        trigCont.Populate = function(e)
            SetTrigType(e.triggerType or "announce")
            annSec.Populate(e)
            tmrSec.Populate(e)
            stgEB:SetText(e.trigStage or "")
        end
    end

    -- =============================================
    -- LOAD TAB
    -- =============================================
    do
        local y = -4
        Label(loadCont, 4, y, "Load Conditions", "GameFontNormalLarge"):SetTextColor(1,0.82,0); y = y - 24

        local note = loadCont:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        note:SetPoint("TOPLEFT", loadCont, "TOPLEFT", 4, y)
        note:SetText("Entry will not show if any condition below is set and not met.")
        note:SetTextColor(0.6,0.6,0.6); y = y - 22

        Label(loadCont, 4, y-4, "Class:")
        local classes = { {label="Any",value=""}, {label="WARRIOR",value="WARRIOR"}, {label="PALADIN",value="PALADIN"},
            {label="HUNTER",value="HUNTER"}, {label="ROGUE",value="ROGUE"}, {label="PRIEST",value="PRIEST"},
            {label="DEATHKNIGHT",value="DEATHKNIGHT"}, {label="SHAMAN",value="SHAMAN"}, {label="MAGE",value="MAGE"},
            {label="WARLOCK",value="WARLOCK"}, {label="MONK",value="MONK"}, {label="DRUID",value="DRUID"},
            {label="DEMONHUNTER",value="DEMONHUNTER"}, {label="EVOKER",value="EVOKER"} }
        local clsDD = ScrollDrop(loadCont, 140, classes,
            function() return ref.e and ref.e.loadClass or "" end,
            function(v) if ref.e then ref.e.loadClass = v end end)
        clsDD:SetPoint("TOPLEFT", loadCont, "TOPLEFT", 48, y); y = y - 28

        Label(loadCont, 4, y-3, "Encounter ID (blank=any):")
        local encEB = MakeEB(loadCont, 178, y, 90)
        encEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.loadEncId = s:GetText() end; s:ClearFocus() end)
        encEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.loadEncId = s:GetText() end end)
        encEB:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Midnight Season 1 Encounter IDs", 1, 0.82, 0)
            GameTooltip:AddLine("|cffffd100The Voidspire|r")
            GameTooltip:AddDoubleLine("  Imperator Averzian",   "3176", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Vorasius",              "3177", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Vaelgor & Ezzorak",     "3178", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Fallen-King Salhadaar", "3179", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Lightblinded Vanguard", "3180", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Crown of the Cosmos",   "3181", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddLine("|cffffd100March on Quel'Danas|r")
            GameTooltip:AddDoubleLine("  Belo'ren, Child of Al'ar", "3182", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddDoubleLine("  Midnight Falls",            "3183", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddLine("|cffffd100Sporefall|r")
            GameTooltip:AddDoubleLine("  Rotmire",   "3159", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:AddLine("|cffffd100The Dreamrift|r")
            GameTooltip:AddDoubleLine("  Chimaerus", "3306", 0.8,0.8,0.8, 1,1,1)
            GameTooltip:Show()
        end)
        encEB:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - 28

        -- Lazily built from the Encounter Journal on first hover; shared by both zone tooltips.
        local zoneListCache = nil
        local function GetZoneList()
            if zoneListCache then return zoneListCache end
            local dungeons, raids = {}, {}
            if EJ_GetNumTiers then
                local numTiers  = EJ_GetNumTiers()
                local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or numTiers
                EJ_SelectTier(numTiers)
                for pass = 1, 2 do
                    local inRaid = pass == 2
                    local target = inRaid and raids or dungeons
                    local idx    = 1
                    local id     = EJ_GetInstanceByIndex(idx, inRaid)
                    while id do
                        EJ_SelectInstance(id)
                        local name, _, _, _, _, _, areaMapId = EJ_GetInstanceInfo(id)
                        if name and areaMapId and areaMapId ~= 0 then
                            local groupId = C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupID(areaMapId)
                            target[#target+1] = { name=name, zoneId=areaMapId, groupId=groupId }
                        end
                        idx = idx + 1
                        id  = EJ_GetInstanceByIndex(idx, inRaid)
                    end
                end
                EJ_SelectTier(savedTier)
            end
            zoneListCache = { dungeons=dungeons, raids=raids }
            return zoneListCache
        end

        Label(loadCont, 4, y-3, "Zone ID (blank=any):")
        local zoneIdEB = MakeEB(loadCont, 148, y, 90)
        zoneIdEB:SetScript("OnEnterPressed",  function(s) if ref.e then ref.e.loadZoneId = s:GetText() end; s:ClearFocus() end)
        zoneIdEB:SetScript("OnEditFocusLost", function(s) if ref.e then ref.e.loadZoneId = s:GetText() end end)
        zoneIdEB:SetScript("OnEnter", function(self)
            local mapId   = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local groupId = mapId and C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupID(mapId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Zone ID  (prefix g for group ID)", 1, 0.82, 0)
            GameTooltip:AddLine("Plain number = specific zone.  |cffffffffg|r prefix = group (any sub-zone).", 0.8,0.8,0.8, true)
            GameTooltip:AddLine(" ")
            if mapId then
                local cur = "zone " .. tostring(mapId)
                if groupId then cur = cur .. "   |cffffffffg|r" .. tostring(groupId) end
                GameTooltip:AddLine("|cff00ff00Current: " .. cur .. "|r")
                GameTooltip:AddLine(" ")
            end
            local zl = GetZoneList()
            for pass = 1, 2 do
                local list   = pass == 1 and zl.raids    or zl.dungeons
                local header = pass == 1 and "Season 1 Raids" or "Season 1 Dungeons"
                if #list > 0 then
                    GameTooltip:AddLine("|cffffd100" .. header .. "|r")
                    for _, entry in ipairs(list) do
                        local id = entry.groupId and ("|cffffffffg|r" .. tostring(entry.groupId))
                                                  or tostring(entry.zoneId)
                        GameTooltip:AddDoubleLine("  " .. entry.name, id, 0.8,0.8,0.8, 1,1,1)
                    end
                    GameTooltip:AddLine(" ")
                end
            end
            if not mapId then
                GameTooltip:AddLine("|cff888888Enter an instance to see current IDs.|r", 0.5,0.5,0.5)
            end
            GameTooltip:Show()
        end)
        zoneIdEB:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - 28

        Label(loadCont, 4, y-4, "Difficulty:")
        local diffs = { {label="Any",value=""}, {label="Normal Raid (14)",value="14"}, {label="Heroic Raid (15)",value="15"},
            {label="Mythic Raid (16)",value="16"}, {label="LFR (17)",value="17"},
            {label="Mythic+ (8)",value="8"}, {label="Normal Dungeon (1)",value="1"},
            {label="Heroic Dungeon (2)",value="2"}, {label="Mythic Dungeon (23)",value="23"} }
        local diffDD = ScrollDrop(loadCont, 180, diffs,
            function() return ref.e and ref.e.loadDiff or "" end,
            function(v) if ref.e then ref.e.loadDiff = v end end)
        diffDD:SetPoint("TOPLEFT", loadCont, "TOPLEFT", 72, y); y = y - 28

        Label(loadCont, 4, y-4, "Role:")
        local roles = {
            {label="Any",    value=""},
            {label="Tank",   value="TANK"},
            {label="Healer", value="HEALER"},
            {label="DPS",    value="DAMAGER"},
        }
        local roleDD = ScrollDrop(loadCont, 120, roles,
            function() return ref.e and ref.e.loadRole or "" end,
            function(v) if ref.e then ref.e.loadRole = v end end)
        roleDD:SetPoint("TOPLEFT", loadCont, "TOPLEFT", 40, y)

        loadCont.Populate = function(e)
            clsDD.Refresh(); encEB:SetText(e.loadEncId or "")
            zoneIdEB:SetText(e.loadZoneId or "")
            diffDD.Refresh(); roleDD.Refresh()
        end
    end

    -- =============================================
    -- CONDITIONS TAB
    -- =============================================
    do
        local RULE_H   = 62
        local RULE_GAP = 4

        local addRuleBtn = CreateFrame("Button", nil, condCont, "UIPanelButtonTemplate")
        addRuleBtn:SetSize(100, 22)
        addRuleBtn:SetPoint("TOPLEFT", condCont, "TOPLEFT", 4, -4)
        addRuleBtn:SetText("+ Add rule")

        local rulesScroll = CreateFrame("ScrollFrame", nil, condCont, "UIPanelScrollFrameTemplate")
        rulesScroll:SetPoint("TOPLEFT",     addRuleBtn, "BOTTOMLEFT",  0, -4)
        rulesScroll:SetPoint("BOTTOMRIGHT", condCont,   "BOTTOMRIGHT", -20, 4)

        local rulesChild = CreateFrame("Frame", nil, rulesScroll)
        rulesChild:SetHeight(1)
        rulesScroll:SetScrollChild(rulesChild)

        local TRIG_OPTS = {
            { label="On show",        value="show" },
            { label="On hide",        value="hide" },
            { label="Remaining time", value="time" },
        }
        local ACT_OPTS = {
            { label="Glow",       value="glow"      },
            { label="Play sound", value="sound"     },
            { label="Scale",      value="scale"     },
            { label="Bar color",  value="barColor"  },
            { label="Font color", value="fontColor" },
            { label="Flash",      value="flash"     },
        }
        local GLOW_OPTS = {
            { label="Pixel",     value="pixel"    },
            { label="Proc",      value="proc"     },
            { label="Auto-cast", value="autocast" },
        }
        local TIME_OP_OPTS = {
            { label="less than",    value="lt" },
            { label="equals",       value="eq" },
            { label="greater than", value="gt" },
        }

        local RebuildRules  -- forward-declare for use in rule row closures

        local function MakeRuleRow(parent, cond, onRemove, rw)
            local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            row:SetSize(rw, RULE_H)
            row:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 })
            row:SetBackdropColor(0.08, 0.08, 0.08, 1)
            row:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

            -- Forward-declare UpdateVis so setter closures below can capture it
            local UpdateVis

            -- ---- IF row ----
            local ifLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            ifLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -8)
            ifLbl:SetText("IF"); ifLbl:SetTextColor(0.8, 0.8, 0.5)

            local trigDD = ScrollDrop(row, 130, TRIG_OPTS,
                function() return cond.trigger or "show" end,
                function(v) cond.trigger = v; UpdateVis() end)
            trigDD:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -4)

            local timeOpDD = ScrollDrop(row, 104, TIME_OP_OPTS,
                function() return cond.timeOp or "lt" end,
                function(v) cond.timeOp = v end)
            timeOpDD:SetPoint("TOPLEFT", row, "TOPLEFT", 174, -4)

            local timeValEB = MakeEB(row, 284, -4, 50, true)
            timeValEB:SetText(tostring(cond.timeVal or 5))
            timeValEB:SetScript("OnEnterPressed",  function(s) cond.timeVal = tonumber(s:GetText()) or 5; s:ClearFocus() end)
            timeValEB:SetScript("OnEditFocusLost", function(s) cond.timeVal = tonumber(s:GetText()) or 5 end)

            local sLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            sLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 340, -8); sLbl:SetText("s")

            -- ---- THEN row ----
            local thenLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            thenLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -36)
            thenLbl:SetText("THEN"); thenLbl:SetTextColor(0.8, 0.8, 0.5)

            local actDD = ScrollDrop(row, 130, ACT_OPTS,
                function() return cond.action or "glow" end,
                function(v) cond.action = v; UpdateVis() end)
            actDD:SetPoint("TOPLEFT", row, "TOPLEFT", 50, -32)

            local glowDD = ScrollDrop(row, 100, GLOW_OPTS,
                function() return cond.glowType or "pixel" end,
                function(v) cond.glowType = v end)
            glowDD:SetPoint("TOPLEFT", row, "TOPLEFT", 188, -32)

            local soundList = GetSoundList()
            local soundDD
            if #soundList > 0 then
                soundDD = ScrollDrop(row, 180, soundList,
                    function() return cond.soundName or soundList[1] end,
                    function(v) cond.soundName = v; local p = GetSoundPath(v); if p then PlaySoundFile(p, "Master") end end)
                soundDD:SetPoint("TOPLEFT", row, "TOPLEFT", 188, -32)
            else
                local noSndLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noSndLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 188, -36)
                noSndLbl:SetText("(no LSM sounds)"); noSndLbl:SetTextColor(0.5, 0.5, 0.5)
                soundDD = { SetShown = function(self, v) if v then noSndLbl:Show() else noSndLbl:Hide() end end }
            end

            local scaleEB = MakeEB(row, 188, -32, 54, false)
            scaleEB:SetText(tostring(cond.scaleVal or 1.5))
            scaleEB:SetScript("OnEnterPressed",  function(s) cond.scaleVal = tonumber(s:GetText()) or 1.5; s:ClearFocus() end)
            scaleEB:SetScript("OnEditFocusLost", function(s) cond.scaleVal = tonumber(s:GetText()) or 1.5 end)
            local scaleLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            scaleLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 248, -36); scaleLbl:SetText("x scale")

            local bcSwatch = Swatch(row,
                function() return cond.bcR or 1 end, function() return cond.bcG or 0 end,
                function() return cond.bcB or 0 end, function() return cond.bcA or 1 end,
                function(r,g,b,a) cond.bcR,cond.bcG,cond.bcB,cond.bcA = r,g,b,a end)
            bcSwatch:SetPoint("TOPLEFT", row, "TOPLEFT", 188, -31)

            local fcSwatch = Swatch(row,
                function() return cond.fcR or 1 end, function() return cond.fcG or 1 end,
                function() return cond.fcB or 0 end, function() return cond.fcA or 1 end,
                function(r,g,b,a) cond.fcR,cond.fcG,cond.fcB,cond.fcA = r,g,b,a end)
            fcSwatch:SetPoint("TOPLEFT", row, "TOPLEFT", 188, -31)

            -- ---- Remove button ----
            local rmBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            rmBtn:SetSize(58, 20); rmBtn:SetText("Remove")
            rmBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
            rmBtn:SetScript("OnClick", onRemove)

            -- ---- Visibility (defined after all widgets so closures above work) ----
            UpdateVis = function()
                local isTime = (cond.trigger or "show") == "time"
                timeOpDD:SetShown(isTime); timeValEB:SetShown(isTime); sLbl:SetShown(isTime)
                local act = cond.action or "glow"
                glowDD:SetShown(act == "glow")
                soundDD:SetShown(act == "sound")
                scaleEB:SetShown(act == "scale"); scaleLbl:SetShown(act == "scale")
                bcSwatch:SetShown(act == "barColor")
                fcSwatch:SetShown(act == "fontColor")
            end
            UpdateVis()

            return row
        end

        RebuildRules = function(e)
            for _, c in ipairs({ rulesChild:GetChildren() }) do c:Hide() end
            if not e or not e.conditions or #e.conditions == 0 then
                rulesChild:SetHeight(1); return
            end
            local rw = math.max(200, condCont:GetWidth() - 24)
            rulesChild:SetWidth(rw)
            for ri, cond in ipairs(e.conditions) do
                local ci = ri
                local row = MakeRuleRow(rulesChild, cond, function()
                    table.remove(e.conditions, ci)
                    RebuildRules(e)
                end, rw)
                row:SetPoint("TOPLEFT", rulesChild, "TOPLEFT", 0, -(ri-1)*(RULE_H+RULE_GAP))
                row:Show()
            end
            rulesChild:SetHeight(#e.conditions * (RULE_H + RULE_GAP))
        end

        condCont.Populate = function(e)
            if not e.conditions then e.conditions = {} end
            RebuildRules(e)
        end

        addRuleBtn:SetScript("OnClick", function()
            if not ref.e then return end
            if not ref.e.conditions then ref.e.conditions = {} end
            table.insert(ref.e.conditions, { trigger="show", action="glow", glowType="pixel", timeOp="lt", timeVal=5 })
            RebuildRules(ref.e)
        end)
    end

    -- =============================================
    -- Entry selection + preview
    -- =============================================

    local groupExpanded = {}
    local previewId     = nil  -- id of currently previewed entry

    local function HidePreview()
        if previewId then
            local pe = AR.db and AR.db.bossmods and AR.db.bossmods.entries[previewId]
            local pf = entryFrames[previewId]
            if pf then
                pf:SetFrameStrata("HIGH")
                pf:EnableMouse(false)
                pf:SetMovable(false)
                pf:SetScript("OnDragStart", nil)
                pf:SetScript("OnDragStop", nil)
                if pe and pe.type == "group" then
                    -- Restore group anchor to invisible runtime state
                    pf:SetSize(1, 1)
                    pf:SetBackdropColor(0, 0, 0, 0)
                    pf:SetBackdropBorderColor(0, 0, 0, 0)
                    if pf.anchorLabel then pf.anchorLabel:Hide() end
                    -- Hide child preview frames and clear group layout state
                    for _, cid in ipairs(pe.children) do
                        local cf = entryFrames[cid]
                        if cf then cf:SetFrameStrata("HIGH"); cf:Hide() end
                    end
                    groupActiveKids[previewId] = nil
                end
                pf:Hide()
            end
            previewId = nil
        end
    end

    local PREVIEW_DATA = { text="Preview Text", icon=134400, spellId="", count="0", duration=30 }

    RefreshPreview = function()
        if not previewId or not ref.e then return end
        local e = ref.e
        local prevDur = (e.triggerType == "announce")
            and ((e.annDuration and e.annDuration > 0) and e.annDuration or 5)
            or 30
        PREVIEW_DATA.duration = prevDur
        PREVIEW_DATA.expirationTime = GetTime() + prevDur
        if e.type == "group" then
            for _, cid in ipairs(e.children) do
                local ce = AR.db.bossmods.entries[cid]
                if ce then
                    local cdur = (ce.triggerType == "announce")
                        and ((ce.annDuration and ce.annDuration > 0) and ce.annDuration or 5)
                        or 30
                    PREVIEW_DATA.duration = cdur
                    PREVIEW_DATA.expirationTime = GetTime() + cdur
                    ShowEntryFrame(ce, PREVIEW_DATA)
                    local cf = entryFrames[cid]
                    if cf then cf:SetFrameStrata("FULLSCREEN") end
                end
            end
            RefreshGroupLayout(e.id)
        else
            ShowEntryFrame(e, PREVIEW_DATA)
            local pf = entryFrames[e.id]
            if pf then pf:SetFrameStrata("FULLSCREEN") end
        end
    end

    SelectEntry = function(e)
        HidePreview()
        ref.e = e
        if not e then
            sp:Hide(); placeholder:Show(); return
        end
        typePicker:Hide(); placeholder:Hide(); sp:Show()
        nameEB:SetText(e.name or "")

        -- Display tab sections
        iconSec:SetShown(e.type == "icon")
        textSec:SetShown(e.type == "text")
        barSec:SetShown(e.type == "bar")
        grpSec:SetShown(e.type == "group")
        if e.type == "icon"  then iconSec.Populate(e) end
        if e.type == "text"  then textSec.Populate(e) end
        if e.type == "bar"   then barSec.Populate(e) end
        if e.type == "group" then
            grpSec.Populate(e)
            local gf = GetFrame(e)
            if gf then
                -- Make anchor box visible for preview (always show even with no children)
                gf:SetSize(110, 26)
                gf:SetBackdropColor(0.1, 0.4, 0.8, 0.35)
                gf:SetBackdropBorderColor(0.4, 0.8, 1, 0.9)
                if gf.anchorLabel then gf.anchorLabel:Show() end
                gf:SetFrameStrata("FULLSCREEN")
                gf:EnableMouse(true)
                gf:SetMovable(true)
                gf:RegisterForDrag("LeftButton")
                gf:SetScript("OnDragStart", gf.StartMoving)
                gf:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing()
                    local cx, cy = self:GetCenter(); local ux, uy = UIParent:GetCenter()
                    if cx and ux then
                        e.anchorX = math.floor(cx - ux + 0.5)
                        e.anchorY = math.floor(cy - uy + 0.5)
                    end
                end)
                gf:Show()
                -- Preview all child entries (each uses its own trigger duration)
                for _, cid in ipairs(e.children) do
                    local ce = AR.db.bossmods.entries[cid]
                    if ce then
                        local cdur = (ce.triggerType == "announce")
                            and ((ce.annDuration and ce.annDuration > 0) and ce.annDuration or 5)
                            or 30
                        PREVIEW_DATA.duration = cdur
                        PREVIEW_DATA.expirationTime = GetTime() + cdur
                        ShowEntryFrame(ce, PREVIEW_DATA)
                        local cf = entryFrames[cid]
                        if cf then cf:SetFrameStrata("FULLSCREEN") end
                    end
                end
            end
            previewId = e.id
        else
            -- Preview display frame — bump to FULLSCREEN so it draws above the DIALOG settings window
            local prevDur = (e.triggerType == "announce")
                and ((e.annDuration and e.annDuration > 0) and e.annDuration or 5)
                or 30
            PREVIEW_DATA.duration = prevDur
            PREVIEW_DATA.expirationTime = GetTime() + prevDur
            ShowEntryFrame(e, PREVIEW_DATA)
            local pf = entryFrames[e.id]
            if pf and not e.groupId then
                pf:SetFrameStrata("FULLSCREEN")
                pf:EnableMouse(true); pf:SetMovable(true)
                pf:RegisterForDrag("LeftButton")
                pf:SetScript("OnDragStart", pf.StartMoving)
                pf:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing()
                    local cx, cy = self:GetCenter(); local ux, uy = UIParent:GetCenter()
                    if cx and ux then
                        e.anchorX = math.floor(cx - ux + 0.5)
                        e.anchorY = math.floor(cy - uy + 0.5)
                    end
                end)
            end
            previewId = e.id
        end

        -- Groups have no trigger, load, or conditions tabs
        local isGroup = e.type == "group"
        subBtns[2]:SetShown(not isGroup)
        subBtns[3]:SetShown(not isGroup)
        subBtns[4]:SetShown(not isGroup)
        if not isGroup then
            trigCont.Populate(e)
            loadCont.Populate(e)
            condCont.Populate(e)
        end
        PickSub(isGroup and 1 or activeSub)
    end

    -- =============================================
    -- Sidebar refresh
    -- =============================================

    local rowPool = {}

    local TYPE_LABELS = { icon="Icon", bar="Progress bar", text="Text", group="" }

    local function GetEntryIcon(e)
        if e.type == "group" then
            return "Interface\\AddOns\\AndeReminders\\Media\\group-icon.tga"
        end
        if e.iconOverrideId and e.iconOverrideId ~= "" then
            return tonumber(e.iconOverrideId) or e.iconOverrideId
        end
        local spellId = (e.annSpellId ~= "" and e.annSpellId) or (e.tmrSpellId ~= "" and e.tmrSpellId)
        if spellId and spellId ~= "" then
            local sid = tonumber(spellId)
            if sid then
                local t = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
                       or (GetSpellTexture and GetSpellTexture(sid))
                if t then return t end
            end
        end
        return "Interface\\Icons\\inv_misc_questionmark"
    end

    RefreshSidebar = function()
        for _, r in ipairs(rowPool) do r:Hide() end
        local idx = 0

        local function AddRow(e, indent)
            idx = idx + 1
            if not rowPool[idx] then
                local r = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
                r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                r:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 })
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(40, 40)
                r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                r.label:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 4, -2)
                r.label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                r.label:SetJustifyH("LEFT")
                r.typeLabel = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                r.typeLabel:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 4, 2)
                r.typeLabel:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                r.typeLabel:SetJustifyH("LEFT")
                r.typeLabel:SetTextColor(0.6, 0.6, 0.6)
                r:SetScript("OnEnter", function(s)
                    if not ref.e or ref.e.id ~= s.eid then
                        s:SetBackdropColor(s.isGroup and 0.14 or 0.1, s.isGroup and 0.14 or 0.1, 0.22, 1)
                    end
                end)
                r:SetScript("OnLeave", function(s)
                    if not ref.e or ref.e.id ~= s.eid then
                        s:SetBackdropColor(s.isGroup and 0.10 or 0.05, s.isGroup and 0.10 or 0.05, s.isGroup and 0.10 or 0.05, 1)
                    end
                end)
                rowPool[idx] = r
            end
            local r = rowPool[idx]
            r.eid    = e.id
            r.isGroup = e.type == "group"
            local py = -(idx-1)*(ROW_H+2) - 2
            r:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  indent, py)
            r:SetWidth(SB_W - 22 - indent)
            r:SetHeight(ROW_H)
            local active   = ref.e and ref.e.id == e.id
            local idleBg   = r.isGroup and 0.10 or 0.05
            r:SetBackdropColor(active and 0.1 or idleBg, active and 0.22 or idleBg, active and 0.55 or idleBg, 1)
            r:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            r.icon:SetTexture(GetEntryIcon(e))
            local namePfx = (e.type == "group") and (groupExpanded[e.id] and "[-] " or "[+] ") or ""
            r.label:SetText(namePfx .. (e.name or "?"))
            r.typeLabel:SetText(TYPE_LABELS[e.type] or "")
            r:Show()
            if e.type == "group" then
                r:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then ShowCtxMenu(e)
                    else groupExpanded[e.id] = not groupExpanded[e.id]; SelectEntry(e); RefreshSidebar() end
                end)
            else
                r:SetScript("OnClick", function(_, btn)
                    if btn == "RightButton" then ShowCtxMenu(e)
                    else SelectEntry(e); RefreshSidebar() end
                end)
            end
        end

        for _, id in ipairs(db.bossmods.topLevel) do
            local e = db.bossmods.entries[id]
            if e then
                AddRow(e, 0)
                if e.type == "group" and groupExpanded[id] then
                    for _, cid in ipairs(e.children) do
                        local ce = db.bossmods.entries[cid]
                        if ce then AddRow(ce, INDENT) end
                    end
                end
            end
        end
        scrollChild:SetHeight(math.max(1, idx * (ROW_H + 2) + 6))
    end

    -- =============================================
    -- Context menu logic
    -- =============================================

    local function CloseCtx() ctxMenu:Hide(); ctxSub:Hide(); ctxCapture:Hide() end

    ShowCtxMenu = function(e)
        -- Reset all buttons
        for _, b in ipairs(cmBtns) do b:Hide() end
        for _, b in ipairs(smBtns) do b:Hide() end
        ctxSub:Hide()

        -- Helpers -------------------------------------------------------
        local function doDelete()
            CloseCtx()
            if ref.e and ref.e.id == e.id then
                HidePreview(); ref.e = nil; sp:Hide(); placeholder:Show()
            end
            DeleteEntry(e.id); RefreshSidebar()
        end

        local function doDuplicate()
            CloseCtx()
            local copy = NewEntry(e.type, nil)
            local SKIP = { id=true, groupId=true, children=true }
            for k, v in pairs(e) do if not SKIP[k] then copy[k] = v end end
            copy.name    = (e.name or "Entry") .. " (copy)"
            copy.children = {}; copy.groupId = nil
            table.insert(db.bossmods.topLevel, 1, copy.id)
            RefreshSidebar()
        end

        -- Build item list -----------------------------------------------
        local defs = {}
        if e.type == "group" then
            defs[1] = { text = "Duplicate",              fn = doDuplicate }
            defs[2] = { text = "Delete group + children", fn = doDelete }
        else
            defs[1] = { text = "Duplicate", fn = doDuplicate }

            if e.groupId then
                defs[2] = { text = "Remove from group", fn = function()
                    CloseCtx()
                    local pg = db.bossmods.entries[e.groupId]
                    if pg then
                        for i, cid in ipairs(pg.children) do
                            if cid == e.id then table.remove(pg.children, i); break end
                        end
                    end
                    e.groupId = nil
                    table.insert(db.bossmods.topLevel, e.id)
                    RefreshSidebar()
                end }
            else
                local groups = {}
                for gid, ge in pairs(db.bossmods.entries) do
                    if ge.type == "group" then table.insert(groups, ge) end
                end
                table.sort(groups, function(a, b) return (a.name or "") < (b.name or "") end)
                if #groups > 0 then
                    defs[2] = { text = "Add to group  >", groups = groups }
                end
            end

            defs[#defs + 1] = { text = "Delete", fn = doDelete }
        end

        -- Wire buttons --------------------------------------------------
        for i, def in ipairs(defs) do
            local btn = cmBtns[i]; btn.lbl:SetText(def.text); btn.lbl:SetTextColor(1,1,1)

            if def.groups then
                local rowIdx = i
                btn:SetScript("OnEnter", function(self)
                    self.lbl:SetTextColor(1,0.82,0)
                    -- Rebuild submenu
                    for _, b in ipairs(smBtns) do b:Hide() end
                    local gs = def.groups
                    for si = 1, math.min(#gs, #smBtns) do
                        local sb = smBtns[si]; local ge = gs[si]
                        sb.lbl:SetText(ge.name or "?"); sb.lbl:SetTextColor(1,1,1)
                        local gid = ge.id
                        sb:SetScript("OnEnter", function(s) s.lbl:SetTextColor(1,0.82,0) end)
                        sb:SetScript("OnLeave", function(s) s.lbl:SetTextColor(1,1,1) end)
                        sb:SetScript("OnClick", function()
                            CloseCtx()
                            for ti, tid in ipairs(db.bossmods.topLevel) do
                                if tid == e.id then table.remove(db.bossmods.topLevel, ti); break end
                            end
                            e.groupId = gid
                            local tg = db.bossmods.entries[gid]
                            if tg then table.insert(tg.children, e.id) end
                            RefreshSidebar()
                        end)
                        sb:Show()
                    end
                    ctxSub:SetHeight(math.min(#gs, #smBtns) * CTX_ITEM_H + 4)
                    ctxSub:ClearAllPoints()
                    ctxSub:SetPoint("TOPLEFT", ctxMenu, "TOPRIGHT", -1, -(rowIdx-1)*CTX_ITEM_H - 2)
                    ctxSub:Show()
                end)
                btn:SetScript("OnLeave", function(self) self.lbl:SetTextColor(1,1,1) end)
                btn:SetScript("OnClick", nil)
            else
                local fn = def.fn
                btn:SetScript("OnEnter", function(self) self.lbl:SetTextColor(1,0.82,0); ctxSub:Hide() end)
                btn:SetScript("OnLeave", function(self) self.lbl:SetTextColor(1,1,1) end)
                btn:SetScript("OnClick", fn)
            end
            btn:Show()
        end

        -- Position at cursor --------------------------------------------
        ctxMenu:SetHeight(#defs * CTX_ITEM_H + 4)
        local cx, cy = GetCursorPosition()
        local s  = UIParent:GetEffectiveScale()
        local mx = cx / s; local my = cy / s
        if mx + CTX_W > UIParent:GetWidth() then mx = mx - CTX_W end
        ctxMenu:ClearAllPoints()
        if my >= ctxMenu:GetHeight() then
            ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx, my)
        else
            ctxMenu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", mx, my)
        end
        ctxMenu:Show(); ctxCapture:Show()
    end

    -- =============================================
    -- Wire callbacks
    -- =============================================

    nameEB:SetScript("OnEnterPressed", function(s)
        if ref.e then ref.e.name = s:GetText() end; s:ClearFocus(); RefreshSidebar()
    end)
    nameEB:SetScript("OnEditFocusLost", function(s)
        if ref.e then ref.e.name = s:GetText() end; RefreshSidebar()
    end)

    delBtn:SetScript("OnClick", function()
        if not ref.e then return end
        local id = ref.e.id
        HidePreview(); ref.e = nil
        DeleteEntry(id)
        sp:Hide(); placeholder:Show()
        RefreshSidebar()
    end)

    addBtn:SetScript("OnClick", function()
        HidePreview(); ref.e = nil
        sp:Hide(); placeholder:Hide(); typePicker:Show()
        RefreshSidebar()
    end)

    -- Hide preview when settings window closes
    local win = parent:GetParent()
    if win then
        win:HookScript("OnHide", function()
            HidePreview(); ref.e = nil
        end)
    end

    PickSub(1)
    RefreshSidebar()
    placeholder:Show()
end

-- =============================================================================
-- Debug slash command  /arbm list | /arbm trigger
-- =============================================================================

SLASH_ARBOSSMODS1 = "/arbm"
SlashCmdList["ARBOSSMODS"] = function(msg)
    local db = AR.db
    if not db or not db.bossmods then
        print("|cFFFF4444[AR BossMods]|r DB not ready — open the settings once first.")
        return
    end
    local bm = db.bossmods
    msg = msg and msg:lower():gsub("^%s+", "") or ""

    if msg == "list" then
        local count = 0
        for id, e in pairs(bm.entries) do
            count = count + 1
            print(string.format("|cFF00AAFF[AR BossMods]|r #%d  %-20s  type=%-5s  trigger=%s",
                id, tostring(e.name), tostring(e.type), tostring(e.triggerType)))
        end
        if count == 0 then print("|cFF00AAFF[AR BossMods]|r No entries found.") end

    elseif msg == "trigger" then
        local d = { source="bw", spellId="0", text="TestBar",
            duration=10, expirationTime=GetTime()+10, icon=134400, count="0" }
        print("|cFF00AAFF[AR BossMods]|r Simulating 10s BigWigs timer (text='TestBar')...")
        local matched = 0
        for id, e in pairs(bm.entries) do
            if MatchTmr(e, d) and PassesLoad(e) then
                matched = matched + 1
                print(string.format("|cFF00FF00[AR BossMods]|r  Matched #%d '%s' (type=%s)",
                    id, tostring(e.name), tostring(e.type)))
            elseif e.triggerType == "timer" then
                -- explain why it didn't match
                local why = PassesLoad(e) and "filter mismatch" or "load condition failed"
                print(string.format("|cFFFF8800[AR BossMods]|r  #%d '%s' has triggerType=timer but skipped: %s",
                    id, tostring(e.name), why))
            end
        end
        if matched == 0 then
            print("|cFFFF4444[AR BossMods]|r No entries matched. Use /arbm list to check trigger types.")
        else
            HandleTimerStart(d)
            print(string.format("|cFF00FF00[AR BossMods]|r %d entry/entries should now be visible.", matched))
        end

    else
        print("|cFF00AAFF[AR BossMods]|r  /arbm list    — show all entries and their trigger types")
        print("|cFF00AAFF[AR BossMods]|r  /arbm trigger — fire a 10s test timer to verify matching")
    end
end

-- =============================================================================
-- Registration
-- =============================================================================

function BossModModule:RunCheck() end  -- triggers are event-driven; stub satisfies module contract

AR:RegisterModule("BossMods", BossModModule)
