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

-- Modules give their checkboxes an OnClick with SetScript, which throws away the OnClick hook
-- the skins use to follow the checked state. So SetScript("OnClick") is wrapped to re-sync
-- after the module's handler (the button has already toggled by then).
local function SyncAfterClick(btn, Sync)
    local setScript = btn.SetScript
    btn.SetScript = function(self, name, fn)
        if name == "OnClick" and fn then
            local handler = fn
            fn = function(...)
                handler(...)
                Sync(false)
            end
        end
        return setScript(self, name, fn)
    end
end

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
    SyncAfterClick(btn, Sync)
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
    SyncAfterClick(btn, Sync)
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
-- Alert options popup: sound, group-only, auto-hide and a test button for one notify table
-- ---------------------------------------------------------------------------

local optionsPopup

local function GetOptionsPopup()
    if optionsPopup then return optionsPopup end

    local f = NewFrame("Frame", "AndeRemindersAlertOptions", UIParent)
    f:SetSize(400, 196)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    UI.Surface(f, C.popup, { 1, 1, 1, 0.14 })
    f:Hide()
    tinsert(UISpecialFrames, "AndeRemindersAlertOptions")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    title:SetText("ALERT OPTIONS")
    UI.AccentText(title)

    local closeBtn = NewFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local soundLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
    soundLabel:SetText("Sound")

    f.soundDrop = UI.Dropdown(f, 210, AR.Sounds.Options(),
        function() return f.notify and f.notify.sound or "" end,
        function(value) if f.notify then f.notify.sound = (value ~= "") and value or nil end end,
        { maxHeight = 260 })
    f.soundDrop:SetPoint("LEFT", soundLabel, "RIGHT", 14, 0)

    local play = UI.Button(f, "Play", 56, 24)
    play:SetPoint("LEFT", f.soundDrop, "RIGHT", 8, 0)
    play:SetScript("OnClick", function() if f.notify then AR.Sounds.Play(f.notify.sound) end end)

    f.cbGroup = NewFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.cbGroup:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -78)
    f.cbGroup:SetScript("OnClick", function(self)
        if f.notify then f.notify.instanceOnly = self:GetChecked() end
    end)
    local groupLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("LEFT", f.cbGroup, "RIGHT", 6, 0)
    groupLabel:SetText("Only alert in dungeons, raids and groups")

    local hideLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -118)
    hideLabel:SetText("Hide after")

    f.durationBox = NewFrame("EditBox", nil, f, "InputBoxTemplate")
    f.durationBox:SetSize(52, 24)
    f.durationBox:SetPoint("LEFT", hideLabel, "RIGHT", 12, 0)
    f.durationBox:SetAutoFocus(false)
    f.durationBox:SetNumeric(true)
    f.durationBox:SetMaxLetters(3)
    local function SaveDuration(self)
        local v = tonumber(self:GetText()) or 0
        if f.notify then f.notify.duration = v end
        self:SetText(tostring(v))
    end
    f.durationBox:SetScript("OnEnterPressed", function(self) SaveDuration(self); self:ClearFocus() end)
    f.durationBox:SetScript("OnEditFocusLost", SaveDuration)

    local hideUnit = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideUnit:SetPoint("LEFT", f.durationBox, "RIGHT", 8, 0)
    hideUnit:SetText("seconds  (0 = stay until dismissed)")

    f.testBtn = UI.Button(f, "Show example alert", 160, 24)
    f.testBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
    f.testBtn:SetScript("OnClick", function() if f.test then f.test() end end)

    optionsPopup = f
    return f
end

-- "Options..." button that edits notify = { sound, instanceOnly, duration }. test() (optional)
-- shows an example alert so the options can be tried out.
function UI.AlertOptionsButton(parent, notify, test)
    local btn = UI.Button(parent, "Options...", 90, 22)
    btn:SetScript("OnClick", function(self)
        local f = GetOptionsPopup()
        if f:IsShown() and f.notify == notify then
            f:Hide()
            return
        end
        f.notify, f.test = notify, test
        f.soundDrop.Refresh()
        f.cbGroup:SetChecked(notify.instanceOnly)
        f.durationBox:SetText(tostring(notify.duration or 0))
        f.testBtn:SetShown(test ~= nil)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
        f:Show()
    end)
    return btn
end

-- False when notify asks for group content only and the player is soloing in the open world.
function UI.ShouldAlert(notify)
    if notify and notify.instanceOnly and not AR.Util.InGroupContent() then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- "Notify via: [o ] Chat  [o ] On-screen  [Options...]" row
-- ---------------------------------------------------------------------------

-- notify = { chat = bool, screen = bool, sound, instanceOnly, duration }. test() is optional.
-- Returns the "On-screen" label so callers can chain further widgets after it.
function UI.NotifyRow(parent, x, y, notify, test)
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

    local options = UI.AlertOptionsButton(parent, notify, test)
    options:SetPoint("LEFT", screenLabel, "RIGHT", 22, 0)

    return screenLabel
end

-- ---------------------------------------------------------------------------
-- Alert box (accent stripe, header, wrapped body, optional per-item rows, snooze button),
-- anchored to a named anchor. Visible alerts are stacked so they never overlap.
-- ---------------------------------------------------------------------------

local ALERT_ITEM_H = 22
local ALERT_GAP    = 6
local alerts = {}  -- every alert, in creation order: stacking order and /ar unsnooze

local function ShowTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- The first visible alert sits on its own anchor; each further one hangs below the one before.
function UI.LayoutAlerts()
    local prev
    for _, a in ipairs(alerts) do
        local f = a.frame()
        if f and f:IsShown() then
            f:ClearAllPoints()
            if prev then
                f:SetPoint("TOP", prev, "BOTTOM", 0, -ALERT_GAP)
            else
                local anchor = AR.anchorFrames and AR.anchorFrames[a.spec.anchor]
                if anchor then
                    f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
                else
                    f:SetPoint("TOP", UIParent, "TOP", 0, a.spec.fallbackY)
                end
            end
            prev = f
        end
    end
end

-- spec = { name = global frame name, anchor = anchor name, width, fallbackY }
-- The frame is created on first use and only ever shown/hidden afterwards.
--
-- alert:Show(text, items, notify)
--   items (optional) = array of { text = label, onIgnore = function }. Each gets a row with an
--   "Ignore" button; onIgnore is responsible for storing the ignore and re-running the check.
--   notify (optional) = the module's notify table: sound plays when the content changes and
--   duration hides the alert after that many seconds.
-- alert:Preview(text, items, notify) shows an example regardless of snooze, for the test buttons.
-- Every alert has a "Snooze" button: it hides the alert until its content changes or the UI
-- reloads. alert:Reset() hides it and forgets the snooze (call when the problem is fixed).
function UI.CreateAlert(spec)
    local frame
    local alert = { spec = spec }
    local rows = {}
    local snoozedSig, currentSig, shownSig
    local hideTimer

    function alert.frame() return frame end

    local function GetFrame()
        if frame then return frame end

        frame = NewFrame("Frame", spec.name, UIParent)
        frame:SetSize(spec.width, 80)
        frame:EnableMouse(true)
        frame:SetFrameStrata("MEDIUM")
        UI.Surface(frame, { 0.050, 0.054, 0.066, 0.96 }, { 1, 1, 1, 0.09 })
        frame:Hide()
        frame:HookScript("OnHide", UI.LayoutAlerts)

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

        local snooze = UI.Button(frame, "Snooze", 64, 20)
        snooze:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
        snooze:SetScript("OnClick", function()
            snoozedSig = currentSig
            frame:Hide()
        end)
        snooze:SetScript("OnEnter", function(self)
            ShowTip(self, "Hide this until something changes or you reload the UI.\n/ar unsnooze brings it back.")
        end)
        snooze:SetScript("OnLeave", GameTooltip_Hide)

        UI.FadeInOnShow(frame, 12)
        return frame
    end

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local row = NewFrame("Frame", nil, frame)
        row:SetHeight(ALERT_ITEM_H)

        local btn = UI.Button(row, "Ignore", 56, 18)
        btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btn:SetScript("OnEnter", function(self)
            ShowTip(self, "Stop reminding me about this. You can turn it back on in the settings.")
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        row.btn = btn

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "LEFT", -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label

        rows[i] = row
        return row
    end

    -- Fills the frame with text and item rows and shows it (position is UI.LayoutAlerts' job).
    local function Render(text, items)
        local f = GetFrame()
        f.body:SetText(text)
        local bodyH = text ~= "" and (f.body:GetStringHeight() + 4) or 0

        local y = 28 + bodyH
        for i, item in ipairs(items) do
            local row = GetRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -y)
            row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -y)
            row.label:SetText(item.text)
            row.btn:SetShown(item.onIgnore ~= nil)
            row.btn:SetScript("OnClick", function() if item.onIgnore then item.onIgnore() end end)
            row:Show()
            y = y + ALERT_ITEM_H
        end
        for i = #items + 1, #rows do rows[i]:Hide() end

        f:SetHeight(y + 36)
        f:Show()
        UI.LayoutAlerts()
        return f
    end

    local function ArmHideTimer(seconds)
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
        if seconds and seconds > 0 then
            hideTimer = C_Timer.NewTimer(seconds, function()
                hideTimer = nil
                if frame then frame:Hide() end
            end)
        end
    end

    function alert:Show(text, items, notify)
        items = items or {}
        notify = notify or {}
        local sig = text
        for _, item in ipairs(items) do sig = sig .. "\n" .. item.text end
        currentSig = sig
        if snoozedSig == sig then return end
        snoozedSig = nil

        local wasShown = frame ~= nil and frame:IsShown()
        local changed  = shownSig ~= sig
        shownSig = sig
        Render(text, items)

        -- Sound only for new content: a re-check that shows the same alert again stays quiet.
        if changed then AR.Sounds.Play(notify.sound) end
        if changed or not wasShown then ArmHideTimer(notify.duration) end
    end

    function alert:Preview(text, items, notify)
        notify = notify or {}
        currentSig = "\1preview"
        Render(text, items or {})
        AR.Sounds.Play(notify.sound)
        ArmHideTimer(math.max(notify.duration or 0, 8))
    end

    function alert:Hide()
        if frame then frame:Hide() end
    end

    function alert:Reset()
        snoozedSig, currentSig, shownSig = nil, nil, nil
        self:Hide()
    end

    function alert:Unsnooze()
        snoozedSig = nil
    end

    function alert:IsShown()
        return frame ~= nil and frame:IsShown()
    end

    alerts[#alerts + 1] = alert
    return alert
end

function UI.UnsnoozeAlerts()
    for _, a in ipairs(alerts) do a:Unsnooze() end
end

-- ---------------------------------------------------------------------------
-- Prompt / confirm dialog
-- ---------------------------------------------------------------------------

local promptFrame

-- opts = { title, text, input = default string (omit for a plain confirm), accept = button
-- label, onAccept = function(text) }
function UI.Prompt(opts)
    local f = promptFrame
    if not f then
        f = NewFrame("Frame", "AndeRemindersPrompt", UIParent)
        f:SetSize(420, 176)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        UI.Surface(f, C.window, C.border)
        f:Hide()
        tinsert(UISpecialFrames, "AndeRemindersPrompt")

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
        UI.AccentText(f.title)

        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -48)
        f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -48)
        f.text:SetJustifyH("LEFT")
        f.text:SetWordWrap(true)

        f.input = NewFrame("EditBox", nil, f, "InputBoxTemplate")
        f.input:SetHeight(26)
        f.input:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 56)
        f.input:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 56)
        f.input:SetAutoFocus(false)
        f.input:SetMaxLetters(40)

        local function Accept()
            local text, cb = f.input:GetText(), f.onAccept
            f:Hide()
            if cb then cb(text) end
        end
        f.accept = UI.Button(f, "OK", 110, 26)
        f.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
        f.accept:SetScript("OnClick", Accept)
        f.cancel = UI.Button(f, "Cancel", 110, 26)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
        f.cancel:SetScript("OnClick", function() f:Hide() end)
        f.input:SetScript("OnEnterPressed", Accept)
        f.input:SetScript("OnEscapePressed", function() f:Hide() end)
        promptFrame = f
    end

    f.title:SetText(opts.title or "")
    f.text:SetText(opts.text or "")
    f.accept:SetText(opts.accept or "OK")
    f.onAccept = opts.onAccept
    f.input:SetShown(opts.input ~= nil)
    if opts.input ~= nil then
        f.input:SetText(opts.input)
        f:Show()
        f.input:SetFocus()
        f.input:HighlightText()
    else
        f:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Copy dialog: shows a string to copy, or takes one to import
-- ---------------------------------------------------------------------------

local copyFrame

-- opts = { title, text (string to show), hint, import = true to show an Import button,
-- onImport = function(str) -> error message or nil }
function UI.CopyDialog(opts)
    local f = copyFrame
    if not f then
        f = NewFrame("Frame", "AndeRemindersCopyDialog", UIParent)
        f:SetSize(520, 300)
        f:SetPoint("CENTER", UIParent, "CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        UI.Surface(f, C.window, C.border)
        f:Hide()
        tinsert(UISpecialFrames, "AndeRemindersCopyDialog")

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
        UI.AccentText(f.title)

        local closeBtn = NewFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local sf = NewFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -50)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 62)
        UI.Surface(sf, C.input, C.inputBorder)

        f.eb = NewFrame("EditBox", nil, sf)
        f.eb:SetMultiLine(true)
        f.eb:SetFontObject("ChatFontNormal")
        f.eb:SetWidth(470)
        f.eb:SetAutoFocus(false)
        f.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(f.eb)

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 24)

        f.err = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.err:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 42)
        f.err:SetTextColor(1, 0.3, 0.3)

        f.go = UI.Button(f, "Import", 110, 26)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
        f.go:SetScript("OnClick", function()
            local err = f.onImport and f.onImport(f.eb:GetText())
            if err then f.err:SetText(err) else f:Hide() end
        end)
        copyFrame = f
    end

    f.title:SetText(opts.title or "")
    f.hint:SetText(opts.hint or "")
    f.err:SetText("")
    f.onImport = opts.onImport
    f.go:SetShown(opts.import == true)
    f.eb:SetText(opts.text or "")
    f:Show()
    f.eb:SetFocus()
    if opts.text then f.eb:HighlightText() end
end
