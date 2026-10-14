local AR = AndeReminders

-- Shared widgets used by the settings tabs and notification frames.

local UI = {}
AR.UI = UI

local WHITE_TEXTURE = "Interface/Buttons/WHITE8x8"

-- ---------------------------------------------------------------------------
-- Divider
-- ---------------------------------------------------------------------------

-- One-pixel horizontal rule spanning the parent, y pixels below its top edge.
function UI.Divider(parent, y, inset, shade)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetHeight(1)
    d:SetColorTexture(shade or 0.28, shade or 0.28, shade or 0.28, 1)
    d:SetPoint("TOPLEFT",  parent, "TOPLEFT",  inset or 5, y)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 5), y)
    return d
end

-- ---------------------------------------------------------------------------
-- Color swatch
-- ---------------------------------------------------------------------------

-- get() -> r, g, b    set(r, g, b)    Opens the color picker on click.
function UI.ColorSwatch(parent, get, set, size)
    size = size or 22

    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(size, size)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 1)

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)

    local function Paint()
        local r, g, b = get()
        tex:SetColorTexture(r, g, b, 1)
    end
    Paint()

    swatch:SetScript("OnClick", function()
        local r, g, b = get()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                set(nr, ng, nb)
                Paint()
            end,
            cancelFunc = function(prev)
                set(prev.r, prev.g, prev.b)
                Paint()
            end,
        })
    end)

    swatch.Refresh = Paint
    return swatch
end

-- ---------------------------------------------------------------------------
-- Scrollable dropdown
-- ---------------------------------------------------------------------------

-- options: array of strings or { label, value } tables. getter() returns the current value,
-- setter(value) stores a pick. config (optional): kind = "font" | "texture", texturePath(value),
-- maxHeight. Returns the button; call btn.Refresh() after changing the underlying value.
function UI.Dropdown(parent, width, options, getter, setter, config)
    config = config or {}
    local kind = config.kind

    -- Snapshot: LSM:List() hands back its internal mutable array, which grows when other
    -- addons register media after this dropdown has been built.
    local opts = {}
    for i = 1, #options do opts[i] = options[i] end

    local ITEM_H      = 20
    local MAX_H       = config.maxHeight or 200
    local SCROLLBAR_W = 14
    local totalH      = #opts * ITEM_H
    local visibleH    = math.min(totalH, MAX_H)
    local maxScroll   = math.max(0, totalH - visibleH)
    local hasScroll   = maxScroll > 0

    local function Label(o) return type(o) == "table" and o.label or tostring(o) end
    local function Value(o) return type(o) == "table" and o.value or o end

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    local btnText = btn:GetFontString()
    btnText:ClearAllPoints()
    btnText:SetPoint("LEFT",  btn, "LEFT",   8, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    btnText:SetJustifyH("LEFT")
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
    arrow:SetText("v")

    local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    popup:SetSize(width, visibleH + 4)
    popup:SetFrameLevel(parent:GetFrameLevel() + 50)
    popup:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
        tile = true, tileSize = 32,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",     2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", hasScroll and -(SCROLLBAR_W + 4) or -2, 2)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(width - (hasScroll and (SCROLLBAR_W + 6) or 4))
    content:SetHeight(math.max(totalH, 1))
    scrollFrame:SetScrollChild(content)

    local selTex = {}
    local function Refresh()
        local current = getter()
        local shown
        for i, o in ipairs(opts) do
            local isCurrent = Value(o) == current
            selTex[i]:SetShown(isCurrent)
            if isCurrent then shown = o end
        end
        shown = shown or opts[1]
        if shown ~= nil then btn:SetText(Label(shown)) end
    end

    for i, o in ipairs(opts) do
        local value = Value(o)
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(ITEM_H)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i - 1) * ITEM_H)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ITEM_H)

        if kind == "texture" and config.texturePath then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetDrawLayer("BACKGROUND", -1)
            bg:SetAllPoints()
            bg:SetTexture(config.texturePath(value))
            bg:SetVertexColor(0.55, 0.55, 0.55, 1)
        end

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.2, 0.4, 0.8, 0.25)
        selTex[i] = sel

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  row, "LEFT",  6, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)  -- rows are one line high: truncate long names instead of wrapping into the next row
        lbl:SetText(Label(o))
        if kind == "font" then AR.Fonts.Apply(lbl, value, 12, "") end

        row:SetScript("OnClick", function()
            setter(value)
            popup:Hide()
            Refresh()
        end)
    end

    local scrollBar
    if hasScroll then
        scrollBar = CreateFrame("Slider", nil, popup)
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
        scrollBar:SetValueStep(ITEM_H)
        scrollBar:SetObeyStepOnDrag(true)
        scrollBar:SetScript("OnValueChanged", function(_, value)
            scrollFrame:SetVerticalScroll(value)
        end)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(_, delta)
            local lo, hi = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(lo, math.min(hi, scrollBar:GetValue() - delta * ITEM_H * 3)))
        end)
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            return
        end
        popup:Show()
        if scrollBar then
            -- Open with the current pick in view.
            local current = getter()
            for i, o in ipairs(opts) do
                if Value(o) == current then
                    scrollBar:SetValue(math.min((i - 1) * ITEM_H, maxScroll))
                    break
                end
            end
        end
    end)

    parent:HookScript("OnHide", function() popup:Hide() end)

    Refresh()
    btn.Refresh = Refresh
    return btn
end

-- ---------------------------------------------------------------------------
-- "Notify via: [ ] Chat  [ ] On-screen" row
-- ---------------------------------------------------------------------------

-- notify = { chat = bool, screen = bool }. Returns the "On-screen" label so callers can chain
-- further widgets after it.
function UI.NotifyRow(parent, x, y, notify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText("Notify via:")
    label:SetTextColor(0.7, 0.7, 0.7)

    local cbChat = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbChat:SetSize(22, 22)
    cbChat:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 60, y + 3)
    cbChat:SetChecked(notify.chat)
    cbChat:SetScript("OnClick", function(self) notify.chat = self:GetChecked() end)

    local chatLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("LEFT", cbChat, "RIGHT", 2, 0)
    chatLabel:SetText("Chat")

    local cbScreen = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbScreen:SetSize(22, 22)
    cbScreen:SetPoint("LEFT", chatLabel, "RIGHT", 16, 0)
    cbScreen:SetChecked(notify.screen)
    cbScreen:SetScript("OnClick", function(self) notify.screen = self:GetChecked() end)

    local screenLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    screenLabel:SetPoint("LEFT", cbScreen, "RIGHT", 2, 0)
    screenLabel:SetText("On-screen")

    return screenLabel
end

-- ---------------------------------------------------------------------------
-- Alert box (backdrop, header, wrapped body, close button), anchored to a named anchor
-- ---------------------------------------------------------------------------

-- spec = { name = global frame name, anchor = anchor name, width, fallbackY }
-- The frame is created on first use and only ever shown/hidden afterwards.
function UI.CreateAlert(spec)
    local frame
    local alert = {}

    local function GetFrame()
        if frame then return frame end

        frame = CreateFrame("Frame", spec.name, UIParent, "BackdropTemplate")
        frame:SetSize(spec.width, 80)

        local anchor = AR.anchorFrames and AR.anchorFrames[spec.anchor]
        if anchor then
            frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        else
            frame:SetPoint("TOP", UIParent, "TOP", 0, spec.fallbackY)
        end

        frame:EnableMouse(true)
        frame:SetFrameStrata("MEDIUM")
        frame:SetBackdrop({
            bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
            tile = true, tileSize = 32,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:Hide()

        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
        header:SetText("|cFFFF6600AR|r")
        frame.header = header

        local body = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  10, -26)
        body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -26)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        frame.body = body

        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
        closeBtn:SetScript("OnClick", function() frame:Hide() end)

        return frame
    end

    function alert:Show(text)
        local f = GetFrame()
        f.body:SetText(text)
        f:SetHeight(f.body:GetStringHeight() + 44)
        f:Show()
    end

    function alert:Hide()
        if frame then frame:Hide() end
    end

    function alert:IsShown()
        return frame ~= nil and frame:IsShown()
    end

    return alert
end
