local AR = AndeReminders

-- Shared look & widgets used by the settings window, the module tabs and the notification
-- frames. Everything here is flat: solid colour textures, hairline borders, one accent colour
-- that the player can change, and small eased animations on hover / toggle.
--
-- UI.CreateFrame is a drop-in replacement for CreateFrame. A file that does
--     local CreateFrame = AR.UI.CreateFrame
-- keeps its widget code unchanged, but every Blizzard button / checkbox / input / scroll
-- template it asks for comes back in the addon's own skin, and every FontString asked for
-- with a GameFont* template uses the addon's typography.

local UI = {}
AR.UI = UI

-- ---------------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------------

local C = {
    window      = { 0.055, 0.059, 0.070, 0.985 },
    side        = { 0.039, 0.042, 0.051, 1 },
    raised      = { 0.092, 0.098, 0.116, 1 },
    border      = { 1, 1, 1, 0.07 },
    btn         = { 0.108, 0.114, 0.134, 1 },
    btnHover    = { 0.150, 0.158, 0.184, 1 },
    btnBorder   = { 1, 1, 1, 0.10 },
    input       = { 0.028, 0.030, 0.038, 0.9 },
    inputBorder = { 1, 1, 1, 0.09 },
    off         = { 0.215, 0.225, 0.265, 1 },
    popup       = { 0.070, 0.075, 0.090, 0.99 },
}
UI.Colors = C

local accent = { r = 1.00, g = 0.48, b = 0.10 }
UI.accent = accent

local accentListeners = {}

-- fn(r, g, b) runs now and again every time the accent changes.
function UI.OnAccent(fn)
    accentListeners[#accentListeners + 1] = fn
    fn(accent.r, accent.g, accent.b)
end

function UI.SetAccent(r, g, b)
    accent.r, accent.g, accent.b = r, g, b
    for _, fn in ipairs(accentListeners) do fn(r, g, b) end
end

function UI.Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function UI.AccentText(fs)
    UI.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b, 1) end)
end

-- ---------------------------------------------------------------------------
-- Animation: one shared OnUpdate drives every eased value
-- ---------------------------------------------------------------------------

local active = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
    for a in pairs(active) do
        local diff = a.target - a.value
        if math.abs(diff) < 0.004 then
            a.value = a.target
            active[a] = nil
        else
            a.value = a.value + diff * math.min(1, dt * a.speed)
        end
        a.apply(a.value)
    end
    if not next(active) then self:Hide() end
end)

-- apply(value) is called as the value eases towards the target set with anim:To().
local function NewAnim(apply, speed, initial)
    initial = initial or 0
    local a = { value = initial, target = initial, apply = apply, speed = speed or 16 }
    function a:To(target, instant)
        self.target = target
        if instant then
            self.value = target
            active[self] = nil
            self.apply(target)
        else
            active[self] = true
            driver:Show()
        end
    end
    return a
end
UI.NewAnim = NewAnim

local function Lerp(a, b, t) return a + (b - a) * t end

-- Fades a frame in whenever it is shown.
function UI.FadeInOnShow(frame, speed)
    local anim = NewAnim(function(v) frame:SetAlpha(v) end, speed or 14)
    frame:HookScript("OnShow", function()
        anim:To(0, true)
        anim:To(1)
    end)
end

-- ---------------------------------------------------------------------------
-- Typography
-- ---------------------------------------------------------------------------

local locale = GetLocale()
local FONT_PATH = (locale == "koKR" or locale == "zhCN" or locale == "zhTW") and STANDARD_TEXT_FONT
    or "Fonts\\ARIALN.TTF"
UI.FONT_PATH = FONT_PATH

local function MakeFont(name, size, alpha)
    local f = CreateFont(name)
    if f:SetFont(FONT_PATH, size, "") == false then f:SetFont(STANDARD_TEXT_FONT, size, "") end
    f:SetTextColor(1, 1, 1, alpha)
    return f
end

local F = {
    title = MakeFont("AndeRemindersFontTitle", 19, 1),
    body  = MakeFont("AndeRemindersFontBody",  14, 0.90),
    small = MakeFont("AndeRemindersFontSmall", 12, 0.55),
}
UI.Fonts = F

-- Blizzard font templates the modules ask for, and what they get instead.
local FONT_OBJECTS = {
    GameFontNormal         = F.body,
    GameFontHighlight      = F.body,
    GameFontNormalLarge    = F.title,
    GameFontNormalSmall    = F.small,
    GameFontHighlightSmall = F.small,
}

local function WrapFontString(frame)
    local create = frame.CreateFontString
    frame.CreateFontString = function(self, name, layer, template, ...)
        local font = template and FONT_OBJECTS[template]
        if font or not template then
            local fs = create(self, name, layer)
            fs:SetFontObject(font or F.body)
            return fs
        end
        return create(self, name, layer, template, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Surfaces and borders
-- ---------------------------------------------------------------------------

-- One screen pixel expressed in the frame's own units.
local function Px(f)
    local scale = f:GetEffectiveScale()
    if not scale or scale <= 0 then return 1 end
    return PixelUtil.GetNearestPixelSize(1, scale, 1)
end

-- Four hairline edges. Returns an object whose :SetColor(r, g, b, a) recolours all of them.
function UI.Border(f, r, g, b, a)
    local px = Px(f)
    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(px)
    local bottom = f:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(px)
    local left = f:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT"); left:SetWidth(px)
    local right = f:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT"); right:SetWidth(px)

    local border = { top, bottom, left, right }
    function border:SetColor(cr, cg, cb, ca)
        for _, t in ipairs(self) do t:SetColorTexture(cr, cg, cb, ca or 1) end
    end
    border:SetColor(r, g, b, a)
    return border
end

-- Solid background plus hairline border. bg / line are { r, g, b, a } arrays.
-- Sets f.arBg (texture) and f.arBorder.
function UI.Surface(f, bg, line)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    f.arBg = tex
    if line then f.arBorder = UI.Border(f, line[1], line[2], line[3], line[4]) end
    return f
end

local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- A filled circle: colour texture clipped by a round mask.
local function Round(frame, layer, size, sublevel)
    local t = frame:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetSize(size, size)
    t:SetColorTexture(1, 1, 1, 1)
    local m = frame:CreateMaskTexture()
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

-- Hairline rule spanning the parent, y units below its top edge.
function UI.Divider(parent, y, inset)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetHeight(Px(parent))
    d:SetColorTexture(1, 1, 1, 0.07)
    d:SetPoint("TOPLEFT",  parent, "TOPLEFT",  inset or 5, y)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 5), y)
    return d
end

-- Faint zebra band behind a row; i alternates the strength. Returns the texture.
function UI.RowStripe(parent, y, height, i, inset)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.028 or 0.012)
    t:SetHeight(height)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  inset or 4, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 4), y)
    return t
end

-- Accent-coloured section heading.
function UI.Title(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    UI.AccentText(fs)
    return fs
end

-- ---------------------------------------------------------------------------
-- Skinners (applied to plain frames by UI.CreateFrame)
-- ---------------------------------------------------------------------------

local function SkinButton(btn)
    UI.Surface(btn, C.btn, C.btnBorder)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    fs:SetJustifyH("CENTER")
    btn:SetFontString(fs)

    local hover = NewAnim(function(v)
        btn.arBg:SetColorTexture(Lerp(C.btn[1], C.btnHover[1], v), Lerp(C.btn[2], C.btnHover[2], v),
            Lerp(C.btn[3], C.btnHover[3], v), 1)
        btn.arBorder:SetColor(Lerp(1, accent.r, v), Lerp(1, accent.g, v), Lerp(1, accent.b, v), Lerp(0.10, 0.75, v))
        fs:SetTextColor(1, 1, 1, Lerp(0.78, 1, v))
    end, 18)
    hover:To(0, true)
    UI.OnAccent(function() hover.apply(hover.value) end)

    btn:HookScript("OnEnter", function() hover:To(1) end)
    btn:HookScript("OnLeave", function() hover:To(0) end)
    btn:HookScript("OnDisable", function() btn:SetAlpha(0.4) end)
    btn:HookScript("OnEnable",  function() btn:SetAlpha(1) end)
end

local function SkinClose(btn)
    btn:SetSize(28, 28)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 24, "")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 1)
    fs:SetText("\195\151")  -- multiplication sign
    local hover = NewAnim(function(v)
        fs:SetTextColor(Lerp(1, 1, v), Lerp(1, 0.32, v), Lerp(1, 0.32, v), Lerp(0.5, 1, v))
    end, 18)
    hover:To(0, true)
    btn:HookScript("OnEnter", function() hover:To(1) end)
    btn:HookScript("OnLeave", function() hover:To(0) end)
end

-- Checkboxes become pill toggles. The size is fixed so every call site lines up the same way.
local TRACK_W, TRACK_H, KNOB = 30, 16, 12

local function SkinCheck(btn)
    btn:SetSize(36, 22)
    btn.SetSize, btn.SetWidth, btn.SetHeight = function() end, function() end, function() end

    local capL = Round(btn, "ARTWORK", TRACK_H)
    capL:SetPoint("LEFT", btn, "LEFT", 2, 0)
    local capR = Round(btn, "ARTWORK", TRACK_H)
    capR:SetPoint("LEFT", capL, "LEFT", TRACK_W - TRACK_H, 0)
    local mid = btn:CreateTexture(nil, "ARTWORK")
    mid:SetColorTexture(1, 1, 1, 1)
    mid:SetPoint("TOPLEFT", capL, "TOP", 0, 0)
    mid:SetPoint("BOTTOMRIGHT", capR, "BOTTOM", 0, 0)
    local knob = Round(btn, "OVERLAY", KNOB)

    local on, hov
    local function Paint()
        local v, h = on.value, hov.value
        local boost = 0.05 * h
        local r = Lerp(C.off[1], accent.r, v) + boost
        local g = Lerp(C.off[2], accent.g, v) + boost
        local b = Lerp(C.off[3], accent.b, v) + boost
        capL:SetVertexColor(r, g, b, 1); capR:SetVertexColor(r, g, b, 1); mid:SetVertexColor(r, g, b, 1)
        knob:SetVertexColor(1, 1, 1, Lerp(0.6, 1, v))
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", capL, "CENTER", v * (TRACK_W - TRACK_H), 0)
    end
    on  = NewAnim(Paint, 20)
    hov = NewAnim(Paint, 20)
    UI.OnAccent(Paint)

    local function Sync(instant) on:To(btn:GetChecked() and 1 or 0, instant) end
    hooksecurefunc(btn, "SetChecked", function() Sync(false) end)
    btn:HookScript("OnClick", function() Sync(false) end)
    btn:HookScript("OnShow",  function() Sync(true) end)
    btn:HookScript("OnEnter", function() hov:To(1) end)
    btn:HookScript("OnLeave", function() hov:To(0) end)
    btn:HookScript("OnDisable", function() btn:SetAlpha(0.4) end)
    btn:HookScript("OnEnable",  function() btn:SetAlpha(1) end)
end

local function SkinRadio(btn)
    btn:SetSize(22, 22)
    local ring  = Round(btn, "ARTWORK", 16)
    ring:SetPoint("CENTER")
    local inner = Round(btn, "ARTWORK", 14, 1)
    inner:SetPoint("CENTER")
    inner:SetVertexColor(C.input[1], C.input[2], C.input[3], 1)
    local dot   = Round(btn, "OVERLAY", 8)
    dot:SetPoint("CENTER")

    local on = NewAnim(function(v)
        ring:SetVertexColor(Lerp(1, accent.r, v), Lerp(1, accent.g, v), Lerp(1, accent.b, v), Lerp(0.22, 1, v))
        dot:SetVertexColor(accent.r, accent.g, accent.b, v)
    end, 20)
    UI.OnAccent(function() on.apply(on.value) end)

    local function Sync(instant) on:To(btn:GetChecked() and 1 or 0, instant) end
    hooksecurefunc(btn, "SetChecked", function() Sync(false) end)
    btn:HookScript("OnClick", function() Sync(false) end)
    btn:HookScript("OnShow",  function() Sync(true) end)
    Sync(true)
end

local function SkinInput(eb)
    UI.Surface(eb, C.input, C.inputBorder)
    eb:SetFontObject(F.body)
    eb:SetTextInsets(7, 7, 0, 0)
    eb:SetJustifyH("LEFT")

    local focus = NewAnim(function(v)
        eb.arBorder:SetColor(Lerp(1, accent.r, v), Lerp(1, accent.g, v), Lerp(1, accent.b, v), Lerp(0.09, 0.9, v))
    end, 18)
    focus:To(0, true)
    UI.OnAccent(function() focus.apply(focus.value) end)
    eb:HookScript("OnEditFocusGained", function() focus:To(1) end)
    eb:HookScript("OnEditFocusLost",   function() focus:To(0) end)
end

-- Slim accent scrollbar living in the gutter the call site leaves to the right of the frame.
-- Also hands out a thumb-sizing function; used by the dropdown popup as well.
local function AttachScrollBar(sf, gutterX)
    local bar = CreateFrame("Slider", nil, sf)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(5)
    bar:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    gutterX, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", gutterX, 0)

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(5, 40)
    bar:SetThumbTexture(thumb)
    UI.OnAccent(function(r, g, b) thumb:SetColorTexture(r, g, b, 0.6) end)

    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()

    local syncing = false
    bar:SetScript("OnValueChanged", function(_, v)
        if not syncing then sf:SetVerticalScroll(v) end
    end)

    local function Update(yRange)
        yRange = yRange or sf:GetVerticalScrollRange()
        bar:SetMinMaxValues(0, yRange)
        local view = sf:GetHeight()
        if view and view > 0 then
            thumb:SetHeight(math.max(24, view * view / (view + yRange)))
        end
        bar:SetShown(yRange > 1)
    end

    sf:HookScript("OnScrollRangeChanged", function(_, _, yRange) Update(yRange) end)
    sf:HookScript("OnVerticalScroll", function(_, offset)
        syncing = true
        bar:SetValue(offset)
        syncing = false
    end)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48)))
    end)
    return bar
end

local function SkinScroll(sf)
    AttachScrollBar(sf, 7)
end

local SKINNERS = {
    UIPanelButtonTemplate    = SkinButton,
    UICheckButtonTemplate    = SkinCheck,
    UIRadioButtonTemplate    = SkinRadio,
    InputBoxTemplate         = SkinInput,
    UIPanelScrollFrameTemplate = SkinScroll,
    UIPanelCloseButton       = SkinClose,
}

-- CreateFrame with the Blizzard widget templates swapped for the addon's skin.
function UI.CreateFrame(kind, name, parent, template, id)
    local skin = template and SKINNERS[template]
    local f
    if skin then
        f = CreateFrame(kind, name, parent)
        WrapFontString(f)
        skin(f)
    else
        f = CreateFrame(kind, name, parent, template, id)
        -- Leave protected frames alone: they never hold text and must stay untouched.
        if not (template and template:find("Secure", 1, true)) then WrapFontString(f) end
    end
    return f
end

local NewFrame = UI.CreateFrame

function UI.Button(parent, text, width, height)
    local b = NewFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 24)
    if text then b:SetText(text) end
    return b
end

-- ---------------------------------------------------------------------------
-- Color swatch
-- ---------------------------------------------------------------------------

-- get() -> r, g, b    set(r, g, b)    Opens the color picker on click.
function UI.ColorSwatch(parent, get, set, size)
    size = size or 22

    local swatch = NewFrame("Button", nil, parent)
    swatch:SetSize(size, size)
    UI.Surface(swatch, { 0, 0, 0, 1 }, { 1, 1, 1, 0.35 })

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    local px = Px(swatch) * 2
    tex:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     px, -px)
    tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -px, px)

    local function Paint()
        local r, g, b = get()
        tex:SetColorTexture(r, g, b, 1)
    end
    Paint()

    local hover = NewAnim(function(v)
        swatch.arBorder:SetColor(Lerp(1, accent.r, v), Lerp(1, accent.g, v), Lerp(1, accent.b, v), Lerp(0.35, 1, v))
    end, 18)
    hover:To(0, true)
    UI.OnAccent(function() hover.apply(hover.value) end)
    swatch:SetScript("OnEnter", function() hover:To(1) end)
    swatch:SetScript("OnLeave", function() hover:To(0) end)

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

    local ITEM_H    = 24
    local MAX_H     = config.maxHeight or 220
    local PAD       = 4
    local totalH    = #opts * ITEM_H
    local visibleH  = math.min(totalH, MAX_H)
    local maxScroll = math.max(0, totalH - visibleH)
    local hasScroll = maxScroll > 0

    local function Label(o) return type(o) == "table" and o.label or tostring(o) end
    local function Value(o) return type(o) == "table" and o.value or o end

    local btn = NewFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 24)
    local btnText = btn:GetFontString()
    btnText:ClearAllPoints()
    btnText:SetPoint("LEFT",  btn, "LEFT",   9, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetWordWrap(false)
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetRotation(-math.pi / 2)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
    arrow:SetVertexColor(1, 1, 1, 0.6)

    local popup = NewFrame("Frame", nil, parent)
    popup:SetSize(width, visibleH + PAD * 2)
    popup:SetFrameLevel(parent:GetFrameLevel() + 50)
    UI.Surface(popup, C.popup, { 1, 1, 1, 0.14 })
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -3)
    popup:EnableMouse(true)
    popup:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
    scrollFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",     PAD, -PAD)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", hasScroll and -(PAD + 7) or -PAD, PAD)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(width - PAD * 2 - (hasScroll and 7 or 0))
    content:SetHeight(math.max(totalH, 1))
    scrollFrame:SetScrollChild(content)

    local selBars = {}
    local function Refresh()
        local current = getter()
        local shown
        for i, o in ipairs(opts) do
            local isCurrent = Value(o) == current
            selBars[i]:SetShown(isCurrent)
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
        hl:SetColorTexture(1, 1, 1, 0.07)

        -- Current pick: faint accent wash with a bar on its left edge.
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        UI.OnAccent(function(r, g, b) sel:SetColorTexture(r, g, b, 0.14) end)
        local selBar = row:CreateTexture(nil, "ARTWORK")
        selBar:SetPoint("TOPLEFT"); selBar:SetPoint("BOTTOMLEFT"); selBar:SetWidth(2)
        UI.OnAccent(function(r, g, b) selBar:SetColorTexture(r, g, b, 1) end)
        local selGroup = { sel = sel, bar = selBar }
        function selGroup:SetShown(shown) self.sel:SetShown(shown); self.bar:SetShown(shown) end
        selBars[i] = selGroup

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  row, "LEFT",  9, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)  -- rows are one line high: truncate long names instead of wrapping into the next row
        lbl:SetText(Label(o))
        if kind == "font" then AR.Fonts.Apply(lbl, value, 13, "") end

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
        scrollBar:SetWidth(5)
        scrollBar:SetPoint("TOPRIGHT",    popup, "TOPRIGHT",    -4, -PAD)
        scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4,  PAD)
        local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(5, math.max(24, visibleH * visibleH / totalH))
        UI.OnAccent(function(r, g, b) thumb:SetColorTexture(r, g, b, 0.6) end)
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
-- "Notify via: [o ] Chat  [o ] On-screen" row
-- ---------------------------------------------------------------------------

-- notify = { chat = bool, screen = bool }. Returns the "On-screen" label so callers can chain
-- further widgets after it.
function UI.NotifyRow(parent, x, y, notify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    label:SetText("NOTIFY VIA")

    local cbChat = NewFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbChat:SetPoint("LEFT", label, "RIGHT", 12, 0)
    cbChat:SetChecked(notify.chat)
    cbChat:SetScript("OnClick", function(self) notify.chat = self:GetChecked() end)

    local chatLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatLabel:SetPoint("LEFT", cbChat, "RIGHT", 2, 0)
    chatLabel:SetText("Chat")

    local cbScreen = NewFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cbScreen:SetPoint("LEFT", chatLabel, "RIGHT", 18, 0)
    cbScreen:SetChecked(notify.screen)
    cbScreen:SetScript("OnClick", function(self) notify.screen = self:GetChecked() end)

    local screenLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    screenLabel:SetPoint("LEFT", cbScreen, "RIGHT", 2, 0)
    screenLabel:SetText("On-screen")

    return screenLabel
end

-- ---------------------------------------------------------------------------
-- Alert box (accent stripe, header, wrapped body, close button), anchored to a named anchor
-- ---------------------------------------------------------------------------

-- spec = { name = global frame name, anchor = anchor name, width, fallbackY }
-- The frame is created on first use and only ever shown/hidden afterwards.
function UI.CreateAlert(spec)
    local frame
    local alert = {}

    local function GetFrame()
        if frame then return frame end

        frame = NewFrame("Frame", spec.name, UIParent)
        frame:SetSize(spec.width, 80)

        local anchor = AR.anchorFrames and AR.anchorFrames[spec.anchor]
        if anchor then
            frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        else
            frame:SetPoint("TOP", UIParent, "TOP", 0, spec.fallbackY)
        end

        frame:EnableMouse(true)
        frame:SetFrameStrata("MEDIUM")
        UI.Surface(frame, { 0.050, 0.054, 0.066, 0.96 }, { 1, 1, 1, 0.09 })
        frame:Hide()

        local stripe = frame:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT"); stripe:SetPoint("BOTTOMLEFT"); stripe:SetWidth(3)
        UI.OnAccent(function(r, g, b) stripe:SetColorTexture(r, g, b, 1) end)

        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -10)
        header:SetText("ANDEREMINDERS")
        UI.AccentText(header)
        frame.header = header

        local body = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        body:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -28)
        body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -28)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        frame.body = body

        local closeBtn = NewFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetSize(22, 22)
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
        closeBtn:SetScript("OnClick", function() frame:Hide() end)

        UI.FadeInOnShow(frame, 12)
        return frame
    end

    function alert:Show(text)
        local f = GetFrame()
        f.body:SetText(text)
        f:SetHeight(f.body:GetStringHeight() + 46)
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
