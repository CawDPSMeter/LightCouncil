-- Light Council – Theme: flaches, dunkles Design mit Lila-Akzenten (angelehnt an ElvUI)
local _, LC = ...

local T = {}
LC.T = T

T.MEDIA = "Interface\\AddOns\\LightCouncil\\Media\\"
T.LOGO = T.MEDIA .. "Logo128"
T.ICON = T.MEDIA .. "Logo64"
local WHITE = "Interface\\Buttons\\WHITE8x8"
T.WHITE = WHITE

-- Farbpalette
T.C = {
    bg        = { 0.060, 0.060, 0.065, 0.95 },  -- Fensterhintergrund (neutrales Schwarz wie ElvUI)
    bgDark    = { 0.030, 0.030, 0.034, 1 },     -- Titelleiste / Seitenleiste / Eingaben
    panel     = { 0.095, 0.095, 0.105, 1 },     -- Karten / Zeilen
    panelAlt  = { 0.130, 0.130, 0.142, 1 },
    border    = { 0, 0, 0, 1 },
    line      = { 0.17, 0.17, 0.19, 1 },
    accent    = { 0.616, 0.388, 1.000, 1 },     -- #9D63FF
    accentDim = { 0.420, 0.240, 0.720, 1 },
    accentLt  = { 0.820, 0.710, 1.000, 1 },     -- #D1B5FF
    text      = { 0.92, 0.92, 0.94, 1 },
    muted     = { 0.56, 0.56, 0.60, 1 },
    good      = { 0.42, 0.88, 0.58, 1 },
    warn      = { 1.00, 0.72, 0.35, 1 },
    bad       = { 1.00, 0.38, 0.45, 1 },
}

local function Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end
T.Hex = Hex
T.HEX = {
    accent = Hex(T.C.accent), accentLt = Hex(T.C.accentLt), muted = Hex(T.C.muted),
    good = Hex(T.C.good), warn = Hex(T.C.warn), bad = Hex(T.C.bad), text = Hex(T.C.text),
}

-- Schriften: Inter (modern, SIL Open Font License) mit Rückfall auf die Standardschrift
local FALLBACK = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
T.FONT = T.MEDIA .. "Fonts\\Inter-Medium.ttf"   -- etwas kräftiger als Regular, besser lesbar
T.FONT_BOLD = T.MEDIA .. "Fonts\\Inter-SemiBold.ttf"
local fonts = {}
function T:Font(size, flags, bold)
    -- Für bessere Lesbarkeit kleine Schriften etwas größer darstellen
    if size <= 11 then size = size + 2 elseif size <= 14 then size = size + 1 end
    local key = size .. (flags or "") .. (bold and "B" or "")
    if not fonts[key] then
        local f = CreateFont("LightCouncilFont" .. key:gsub("%W", ""))
        local ok = f:SetFont(bold and self.FONT_BOLD or self.FONT, size, flags or "")
        if ok == false then f:SetFont(FALLBACK, size, flags or "") end
        f:SetShadowColor(0, 0, 0, 0.8)
        f:SetShadowOffset(1, -1)
        fonts[key] = f
    end
    return fonts[key]
end

function T:Text(parent, size, color, justify, flags, bold)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(self:Font(size or 12, flags, bold))
    local c = color or self.C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(true)
    return fs
end

------------------------------------------------------------------------
-- Rahmen & Hintergründe
------------------------------------------------------------------------
function T:Skin(frame, bg, border)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bg = bg or self.C.panel
    border = border or self.C.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function T:SetBorder(frame, c)
    frame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
end

function T:Line(parent, color, height)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    local c = color or self.C.line
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    t:SetHeight(height or 1)
    return t
end

-- Senkrechter Farbverlauf (für Glanzeffekte)
function T:Gradient(tex, top, bottom)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha("VERTICAL", bottom[1], bottom[2], bottom[3], bottom[4], top[1], top[2], top[3], top[4])
    end
end

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------
function T:CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local x = self:Text(b, 16, self.C.muted, "CENTER")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    b:SetScript("OnEnter", function() x:SetTextColor(unpack(T.C.bad)) end)
    b:SetScript("OnLeave", function() x:SetTextColor(unpack(T.C.muted)) end)
    b:SetScript("OnClick", onClick or function() parent:Hide() end)
    return b
end

local FESTIVE = { LightCouncilMainFrame = true, LightCouncilVoteFrame = true, LightCouncilRaidFrame = true }

-- Fenster mit Titelleiste (Logo, Titel, Schließen-Knopf), verschiebbar
function T:Window(name, width, height, title, subtitle, barHeight)
    barHeight = barHeight or 36
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    self:Skin(f, self.C.bg)
    if name then tinsert(UISpecialFrames, name) end

    -- Schatten
    local shadow = CreateFrame("Frame", nil, f, "BackdropTemplate")
    shadow:SetPoint("TOPLEFT", -5, 5)
    shadow:SetPoint("BOTTOMRIGHT", 5, -5)
    shadow:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    shadow:SetBackdrop({ edgeFile = WHITE, edgeSize = 5 })
    shadow:SetBackdropBorderColor(0, 0, 0, 0.35)

    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(barHeight)
    self:Skin(bar, self.C.bgDark, { 0, 0, 0, 0 })
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.titleBar = bar

    local glow = bar:CreateTexture(nil, "BORDER")
    glow:SetTexture(WHITE)
    glow:SetAllPoints()
    self:Gradient(glow, { 0.62, 0.39, 1, 0.22 }, { 0.62, 0.39, 1, 0 })

    -- Lila Schimmer unter der Titelleiste, der ins Schwarz verläuft
    local fade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    fade:SetTexture(WHITE)
    fade:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    fade:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    fade:SetHeight(70)
    self:Gradient(fade, { 0.62, 0.39, 1, 0.07 }, { 0.62, 0.39, 1, 0 })

    local accent = self:Line(bar, self.C.accent, 1)
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")

    local big = barHeight >= 44
    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(self.LOGO)
    logo:SetSize(barHeight + 2, barHeight + 2)   -- etwas größer als die Leiste, damit der Würfel gut sichtbar ist
    logo:SetPoint("LEFT", big and 8 or 4, 0)
    f.logo = logo

    f.title = self:Text(bar, big and 18 or 14, self.C.text, "LEFT", nil, true)
    f.title:SetPoint("LEFT", logo, "RIGHT", big and 8 or 6, subtitle and (big and 8 or 7) or 0)
    f.title:SetText(title or "")
    if subtitle then
        f.subtitle = self:Text(bar, big and 11 or 10, self.C.muted, "LEFT")
        f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
        f.subtitle:SetText(subtitle)
    end

    f.close = self:CloseButton(bar, function() f:Hide() end)
    f.close:SetPoint("RIGHT", -8, 0)
    f:HookScript("OnShow", function(self) T:ApplyScale(self) end)
    -- Winterdeko (Schnee + Lichterkette) nur für die großen Fenster
    if FESTIVE[name] and self.Festive then self:Festive(f, barHeight) end
    return f
end

-- Fenstergröße aus den Einstellungen (1 = 100 %), aber nie größer als der Bildschirm
T.SCALES = { 1.0, 1.1, 1.2, 1.3 }
function T:ApplyScale(f)
    local s = (LC.db and LC.db.config and LC.db.config.uiScale) or 1.2
    local w, h = f:GetWidth(), f:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    local fit = math.min(UIParent:GetWidth() * 0.96 / w, UIParent:GetHeight() * 0.94 / h)
    f:SetScale(math.max(0.6, math.min(s, fit)))
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
-- style: "primary" (Lila gefüllt), "default", "ghost" (ohne Hintergrund), "danger"
function T:Button(parent, text, width, height, style, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 110, height or 28)
    style = style or "default"
    b.style = style

    local fs = self:Text(b, 13, self.C.text, "CENTER", nil, true)
    fs:SetPoint("CENTER")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetText(text or "")

    local function Paint(hover)
        local C = T.C
        if style == "primary" then
            local c = hover and C.accent or C.accentDim
            b:SetBackdropColor(c[1], c[2], c[3], 1)
            T:SetBorder(b, hover and C.accentLt or C.border)
        elseif style == "danger" then
            b:SetBackdropColor(hover and 0.45 or 0.28, 0.08, 0.14, 1)
            T:SetBorder(b, hover and C.bad or C.border)
        elseif style == "ghost" then
            b:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], hover and 0.15 or 0)
            b:SetBackdropBorderColor(0, 0, 0, 0)
        else
            local c = hover and C.panelAlt or C.panel
            b:SetBackdropColor(c[1], c[2], c[3], 1)
            T:SetBorder(b, hover and C.accent or C.border)
        end
    end
    self:Skin(b)
    Paint(false)
    b.Paint = Paint

    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() and not self.selected then Paint(true) end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltipTitle or self:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then Paint(false) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.4) Paint(false) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then fs:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Navigationseintrag für die Seitenleiste
function T:NavButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 36)
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture(WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(T.C.accent[1], T.C.accent[2], T.C.accent[3], 0)
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(3)
    bar:SetVertexColor(unpack(T.C.accent))
    bar:Hide()
    local fs = self:Text(b, 14, self.C.muted, "LEFT", nil, true)
    fs:SetPoint("LEFT", 18, 0)
    fs:SetText(text)
    b.badge = self:Text(b, 11, self.C.accentLt, "RIGHT")
    b.badge:SetPoint("RIGHT", -14, 0)

    function b:SetSelected(sel)
        self.selected = sel
        bar:SetShown(sel)
        hl:SetVertexColor(T.C.accent[1], T.C.accent[2], T.C.accent[3], sel and 0.16 or 0)
        local c = sel and T.C.text or T.C.muted
        fs:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnter", function(self)
        if not self.selected then hl:SetVertexColor(T.C.accent[1], T.C.accent[2], T.C.accent[3], 0.08) fs:SetTextColor(unpack(T.C.text)) end
    end)
    b:SetScript("OnLeave", function(self) if not self.selected then self:SetSelected(false) end end)
    b:SetScript("OnClick", onClick)
    return b
end

------------------------------------------------------------------------
-- Eingabefelder
------------------------------------------------------------------------
function T:Input(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width or 100, height or 28)
    e:SetAutoFocus(false)
    e:SetFontObject(self:Font(13))
    e:SetTextColor(unpack(self.C.text))
    e:SetTextInsets(8, 8, 0, 0)
    self:Skin(e, self.C.bgDark)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) T:SetBorder(self, T.C.accent) end)
    e:SetScript("OnEditFocusLost", function(self) T:SetBorder(self, T.C.border) self:HighlightText(0, 0) end)
    -- Platzhaltertext, solange das Feld leer ist
    e.placeholder = self:Text(e, 12, self.C.muted)
    e.placeholder:SetPoint("LEFT", 8, 0)
    e.placeholder:SetPoint("RIGHT", -8, 0)
    e.placeholder:SetWordWrap(false)
    e:HookScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    function e:SetPlaceholder(text) self.placeholder:SetText(text or "") self.placeholder:SetShown(self:GetText() == "") end
    return e
end

function T:Check(parent, label, size)
    size = size or 18
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(size, size)
    self:Skin(cb, self.C.bgDark)
    local tick = cb:CreateTexture(nil, "ARTWORK")
    tick:SetTexture(WHITE)
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetVertexColor(unpack(self.C.accent))
    cb:SetCheckedTexture(tick)
    local dis = cb:CreateTexture(nil, "ARTWORK")
    dis:SetTexture(WHITE)
    dis:SetPoint("TOPLEFT", 3, -3)
    dis:SetPoint("BOTTOMRIGHT", -3, 3)
    dis:SetVertexColor(0.4, 0.4, 0.4)
    cb:SetDisabledCheckedTexture(dis)
    cb:SetScript("OnEnter", function(self) if self:IsEnabled() then T:SetBorder(self, T.C.accent) end end)
    cb:SetScript("OnLeave", function(self) T:SetBorder(self, T.C.border) end)
    cb:HookScript("OnDisable", function(self) self:SetAlpha(0.35) end)
    cb:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
    if label then
        cb.label = self:Text(cb, 13, self.C.text, "LEFT")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        cb.label:SetText(label)
    end
    return cb
end

------------------------------------------------------------------------
-- Scrollbereich mit schmalem Scrollbalken
------------------------------------------------------------------------
function T:Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    local bar = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    self:Skin(bar, self.C.bgDark, { 0, 0, 0, 0 })
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(unpack(self.C.accentDim))
    thumb:SetSize(6, 40)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(false)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    bar:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(T.C.accent)) end)
    bar:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(T.C.accentDim)) end)
    sf.bar = bar

    local function UpdateRange()
        local range = math.max(0, sf:GetVerticalScrollRange())
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 1)
        local h = sf:GetHeight()
        if h > 0 then
            thumb:SetHeight(math.max(24, h * h / (h + range)))
        end
        if bar:GetValue() > range then bar:SetValue(range) end
    end
    sf:SetScript("OnScrollRangeChanged", UpdateRange)
    sf:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        UpdateRange()
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local _, max = bar:GetMinMaxValues()
        bar:SetValue(math.max(0, math.min(max, bar:GetValue() - delta * 40)))
    end)
    sf:HookScript("OnVerticalScroll", function(_, offset)
        if math.abs(bar:GetValue() - offset) > 0.5 then bar:SetValue(offset) end
    end)
    sf.UpdateRange = UpdateRange
    return sf, content
end

-- Mehrzeiliges Textfeld in einer Karte
function T:MultiLine(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:Skin(box, self.C.bgDark)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -8, 8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(self:Font(13))
    eb:SetTextColor(unpack(self.C.text))
    eb:SetMaxLetters(0)
    eb:SetWidth(300)
    sf:SetScrollChild(eb)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() T:SetBorder(box, T.C.accent) end)
    eb:SetScript("OnEditFocusLost", function() T:SetBorder(box, T.C.border) end)
    eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
        local top = sf:GetVerticalScroll()
        local height = sf:GetHeight()
        y = -y
        if y < top then
            sf:SetVerticalScroll(y)
        elseif y + h > top + height then
            sf:SetVerticalScroll(math.max(0, y + h - height))
        end
    end)
    sf:SetScript("OnSizeChanged", function(_, w) eb:SetWidth(w) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, sf:GetVerticalScrollRange())
        sf:SetVerticalScroll(math.max(0, math.min(max, sf:GetVerticalScroll() - delta * 40)))
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    box.placeholder = self:Text(box, 11, self.C.muted)
    box.placeholder:SetPoint("TOPLEFT", 10, -10)
    box.placeholder:SetPoint("TOPRIGHT", -10, -10)
    eb:HookScript("OnTextChanged", function(self) box.placeholder:SetShown(self:GetText() == "") end)
    box.edit = eb
    return box, eb
end

------------------------------------------------------------------------
-- Statusbalken
------------------------------------------------------------------------
function T:Bar(parent, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetHeight(height or 8)
    self:Skin(holder, self.C.bgDark)
    local sb = CreateFrame("StatusBar", nil, holder)
    sb:SetPoint("TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", -1, 1)
    sb:SetStatusBarTexture(WHITE)
    sb:SetStatusBarColor(unpack(self.C.accent))
    holder.bar = sb
    holder.text = self:Text(holder, 10, self.C.text, "CENTER")
    holder.text:SetPoint("CENTER", 0, 0)
    sb:SetFrameLevel(holder:GetFrameLevel() + 1)
    holder.text:SetParent(sb)
    return holder
end

-- Kleines farbiges Etikett ("Council", "Loot-CD" …)
function T:Badge(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(10, 16)
    self:Skin(f, self.C.accentDim, { 0, 0, 0, 0 })
    f.text = self:Text(f, 10, self.C.text, "CENTER")
    f.text:SetPoint("CENTER", 0, 0)
    function f:Set(text, color)
        if not text then self:Hide() return end
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 12)
        local c = color or T.C.accentDim
        self:SetBackdropColor(c[1], c[2], c[3], 0.85)
        self:Show()
    end
    return f
end

-- Farbe für Score-Werte
function T:ScoreColor(score)
    if not score then return self.C.muted end
    if score >= 75 then return self.C.good end
    if score >= 50 then return self.C.accentLt end
    return self.C.warn
end

-- Qualitätsfarbe eines Items
function T:QualityColor(quality)
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return { c.r, c.g, c.b, 1 }
    end
    return self.C.accent
end

-- Icon mit Rahmen
function T:Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    self:Skin(f, self.C.bgDark)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return f
end
