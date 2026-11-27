-- Light Council – Winterdeko: fallende Schneeflocken und eine bunte Lichterkette am Fensterrand
-- Rein optisch, fängt keine Mausklicks ab. Läuft nur, solange das Fenster offen ist.
local _, LC = ...
local T = LC.T
local L = LC.L

local ROUND = T.MEDIA .. "Dot"     -- weißer, weich gerandeter Punkt
local GLOW  = T.MEDIA .. "Glow"    -- weicher Lichtschein
local FLAKES = 42
local SPACING = 34          -- Abstand der Lämpchen
local STEP = 1 / 30         -- höchstens 30 Bilder pro Sekunde

-- Lämpchenfarben: rot, grün, gold, blau, lila (Akzent)
local COLORS = {
    { 1.00, 0.25, 0.25 }, { 0.30, 0.95, 0.40 }, { 1.00, 0.80, 0.25 },
    { 0.35, 0.65, 1.00 }, { 0.70, 0.45, 1.00 },
}

T.FESTIVE_MODES = { "auto", "on", "off" }

-- „auto“: vom 20. November bis zum 6. Januar
function T:FestiveActive()
    local mode = (LC.db and LC.db.config and LC.db.config.festive) or "auto"
    if mode == "on" then return true end
    if mode == "off" then return false end
    local d = date("*t")
    return (d.month == 11 and d.day >= 20) or d.month == 12 or (d.month == 1 and d.day <= 6)
end

local function NewFlake(fx, w, h, anywhere)
    fx.x = math.random() * w
    fx.y = anywhere and math.random() * h or -math.random() * 30
    fx.speed = 14 + math.random() * 26
    fx.drift = 6 + math.random() * 14
    fx.freq = 0.4 + math.random() * 0.9
    fx.phase = math.random() * 6.28
    local s = 2 + math.random() * 3.5
    fx.tex:SetSize(s, s)
    fx.tex:SetAlpha(0.25 + math.random() * 0.35)
end

-- Lämpchen entlang des Rands verteilen (im Uhrzeigersinn), abwechselnd leicht nach innen/außen,
-- damit sich die Kette schlängelt; das Kabel hängt zwischen zwei Lämpchen etwas durch.
local function Layout(o)
    local w, h = o:GetWidth(), o:GetHeight()
    if not w or w < 50 or not h or h < 50 then return end
    local pts = {}
    local function Edge(x1, y1, x2, y2, nx, ny)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local n = math.max(1, math.floor(len / SPACING + 0.5))
        for i = 0, n - 1 do
            local t = i / n
            pts[#pts + 1] = { x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, nx, ny }
        end
    end
    -- Koordinaten von oben links aus, y nach unten negativ
    Edge(0, 0, w, 0, 0, -1)        -- oben, „innen“ = nach unten
    Edge(w, 0, w, -h, -1, 0)       -- rechts
    Edge(w, -h, 0, -h, 0, 1)       -- unten
    Edge(0, -h, 0, 0, 1, 0)        -- links

    o.bulbs = o.bulbs or {}
    o.wires = o.wires or {}
    local canLine = o.CreateLine ~= nil
    for i, p in ipairs(pts) do
        local b = o.bulbs[i]
        if not b then
            b = {}
            b.glow = o:CreateTexture(nil, "ARTWORK")
            b.glow:SetTexture(GLOW)
            b.glow:SetBlendMode("ADD")
            b.glow:SetSize(22, 22)
            b.dot = o:CreateTexture(nil, "OVERLAY")
            b.dot:SetTexture(ROUND)
            b.dot:SetSize(6, 6)
            b.cap = o:CreateTexture(nil, "OVERLAY", nil, 1)
            b.cap:SetTexture(T.WHITE)
            b.cap:SetVertexColor(0.08, 0.10, 0.08, 1)
            b.cap:SetSize(3, 2)
            b.color = COLORS[(i - 1) % #COLORS + 1]
            b.phase = math.random() * 6.28
            b.speed = 1.2 + math.random() * 1.6
            b.dot:SetVertexColor(b.color[1], b.color[2], b.color[3])
            b.glow:SetVertexColor(b.color[1], b.color[2], b.color[3])
            o.bulbs[i] = b
        end
        local off = (i % 2 == 0) and 3 or -1
        local x, y = p[1] + p[3] * off, p[2] + p[4] * off
        b.x, b.y = x, y
        b.dot:ClearAllPoints(); b.dot:SetPoint("CENTER", o, "TOPLEFT", x, y)
        b.glow:ClearAllPoints(); b.glow:SetPoint("CENTER", o, "TOPLEFT", x, y)
        b.cap:ClearAllPoints(); b.cap:SetPoint("CENTER", o, "TOPLEFT", x - p[3] * 3, y - p[4] * 3)
        b.dot:Show(); b.glow:Show(); b.cap:Show()
    end
    for i = #pts + 1, #o.bulbs do
        local b = o.bulbs[i]
        b.dot:Hide(); b.glow:Hide(); b.cap:Hide()
    end

    -- Kabel: zwei Teilstücke pro Lücke, die Mitte hängt nach innen durch
    if canLine then
        local n = #pts
        for i = 1, n do
            local a, c = o.bulbs[i], o.bulbs[i % n + 1]
            local p = pts[i]
            local mx, my = (a.x + c.x) / 2 + p[3] * 4, (a.y + c.y) / 2 + p[4] * 4
            for k = 1, 2 do
                local idx = (i - 1) * 2 + k
                local ln = o.wires[idx]
                if not ln then
                    ln = o:CreateLine(nil, "BORDER")
                    ln:SetColorTexture(0.10, 0.16, 0.10, 0.9)
                    ln:SetThickness(1.2)
                    o.wires[idx] = ln
                end
                if k == 1 then
                    ln:SetStartPoint("TOPLEFT", o, a.x, a.y); ln:SetEndPoint("TOPLEFT", o, mx, my)
                else
                    ln:SetStartPoint("TOPLEFT", o, mx, my); ln:SetEndPoint("TOPLEFT", o, c.x, c.y)
                end
                ln:Show()
            end
        end
        for i = n * 2 + 1, #o.wires do o.wires[i]:Hide() end
    end
    o.nBulbs = #pts
end

local function Update(o, elapsed)
    o.acc = (o.acc or 0) + elapsed
    if o.acc < STEP then return end
    -- im Kampf pausieren (spart Leistung, Deko bleibt stehen)
    if InCombatLockdown() then o.acc = 0 return end
    local dt = o.acc
    o.acc = 0
    o.t = (o.t or 0) + dt
    local t = o.t
    local w, h = o:GetWidth(), o:GetHeight()
    local top = o.top or 0

    for _, fx in ipairs(o.flakes) do
        fx.y = fx.y + fx.speed * dt
        if fx.y > h - top then NewFlake(fx, w, h - top) end
        local x = fx.x + math.sin(t * fx.freq + fx.phase) * fx.drift
        if x < 2 then x = 2 elseif x > w - 2 then x = w - 2 end
        fx.tex:SetPoint("CENTER", o, "TOPLEFT", x, -(top + fx.y))
        fx.tex:SetShown(fx.y >= 0)   -- nicht über die Titelleiste schneien
    end

    -- Funkeln plus eine langsame Lauflicht-Welle (nur alle 0,1 s – reicht fürs Auge)
    o.lacc = (o.lacc or 0) + dt
    if o.lacc < 0.1 then return end
    o.lacc = 0
    for i = 1, o.nBulbs or 0 do
        local b = o.bulbs[i]
        local v = 0.55 + 0.30 * math.sin(t * b.speed + b.phase) + 0.15 * math.sin(t * 2.2 - i * 0.6)
        b.dot:SetAlpha(0.55 + 0.45 * v)
        b.glow:SetAlpha(0.15 + 0.55 * v)
    end
end

-- Deko an ein Fenster hängen. top = Höhe der Titelleiste (dort fällt kein Schnee).
function T:Festive(f, top)
    if f.festive then return f.festive end
    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints()
    o:SetFrameLevel(f:GetFrameLevel() + 40)   -- über dem Inhalt, Schnee ist durchscheinend
    o:EnableMouse(false)
    o.top = top or 0
    o.flakes = {}
    for i = 1, FLAKES do
        local fx = { tex = o:CreateTexture(nil, "OVERLAY") }
        fx.tex:SetTexture(ROUND)
        fx.tex:SetVertexColor(0.92, 0.96, 1)
        o.flakes[i] = fx
    end
    f.festive = o

    local function Start()
        local w, h = o:GetWidth(), o:GetHeight()
        for _, fx in ipairs(o.flakes) do NewFlake(fx, w, h - o.top, true) end
        Layout(o)
    end
    o:SetScript("OnSizeChanged", function() if o:IsShown() then Layout(o) end end)
    o:SetScript("OnShow", Start)
    o:SetScript("OnUpdate", Update)
    o:SetShown(T:FestiveActive())
    if o:IsShown() then Start() end
    -- beim Öffnen des Fensters prüfen (Datum oder Einstellung kann sich geändert haben)
    f:HookScript("OnShow", function() o:SetShown(T:FestiveActive()) end)
    return o
end

function T:RefreshFestive()
    for _, name in ipairs({ "LightCouncilMainFrame", "LightCouncilVoteFrame", "LightCouncilRaidFrame" }) do
        local f = _G[name]
        if f and f.festive then f.festive:SetShown(T:FestiveActive()) end
    end
end

function T:FestiveText()
    local mode = (LC.db and LC.db.config and LC.db.config.festive) or "auto"
    local names = { auto = L["Auto"], on = L["An"], off = L["Aus"] }
    return L("Winterdeko: %s", names[mode] or names.auto)
end
