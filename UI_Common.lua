-- Light Council – Hauptfenster: gemeinsame Bausteine aller Seiten (Konstanten, Karten, Umschalter …)
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
LC.UI = LC.UI or {}
local U = LC.UI

U.W, U.HGT = 1000, 740
U.SIDEBAR = 200
U.PAD = 18
U.CW = U.W - U.SIDEBAR - 2 * U.PAD - 2   -- Inhaltsbreite
U.ITEM_ROW = 50
U.BOSS_W = 230
U.pages = {}
local CW, pages = U.CW, U.pages
function U.SelectTab() end   -- wird von UI_Main.lua gesetzt

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------
local function Card(parent, height)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T:Skin(f, C.panel)
    if height then f:SetHeight(height) end
    return f
end

local function PageHeader(p, title, desc)
    local t = T:Text(p, 22, C.text, "LEFT", nil, true)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(title)
    local d = T:Text(p, 12, C.muted)
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
    d:SetWidth(CW - 190)   -- rechts bleibt Platz für einen Knopf neben der Überschrift
    d:SetText(desc or "")
    -- Höhe passend zur Beschreibung (ein- oder zweizeilig), damit nichts überlappt
    return math.ceil(t:GetStringHeight() + 5 + d:GetStringHeight() + 16), t, d
end

local function Tip(widget, title, text)
    widget.tooltipTitle = title
    widget.tooltip = text
end

-- Shift-Klick auf ein Item fügt den Link in unsere Eingabefelder ein
local linkHooked = false
local function AcceptLinks(editBox)
    editBox.lcAcceptLinks = true
    if linkHooked or not ChatEdit_InsertLink then return end
    linkHooked = true
    hooksecurefunc("ChatEdit_InsertLink", function(text)
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if text and focus and focus.lcAcceptLinks then focus:Insert(text) end
    end)
end

------------------------------------------------------------------------
-- Status der Vorbereitung (für Startseite und Hinweise)
------------------------------------------------------------------------
local function SetupStatus()
    local db = LC.db
    local s = {}
    local nCouncil = #db.config.council
    local size = LC:GetCouncilSize()
    local list = LC:GetCouncilList()
    nCouncil = #list
    s.council = { ok = nCouncil == size, text = (nCouncil == 0) and L["Noch niemand eingetragen"]
        or (nCouncil .. L[" von "] .. size .. L[" eingetragen: "] .. table.concat(list, ", ")) }
    -- Reservierungen im Addon: wie viele Spieler haben (bestätigt) reserviert?
    local players, pending = 0, 0
    for _, R in pairs(db.reserves or {}) do
        for _, rec in pairs(R.players) do
            if (rec.rev or 0) > 0 then players = players + 1 end
            if rec.pending then pending = pending + 1 end
        end
    end
    s.softres = { ok = players > 0, pending = pending,
        text = (players > 0) and (players .. L[" Reservierungen bestätigt"] .. ((pending > 0) and (" · " .. pending .. L[" Änderungsantrag/-anträge offen"]) or ""))
            or L["Noch keine Reservierungen – Raider reservieren unter „Meine Reservierung“"] }
    local ci = 0
    for _ in pairs(db.councilItems) do ci = ci + 1 end
    s.items = { ok = ci > 0, text = (ci > 0) and (ci .. L[" Items markiert"]) or L["Noch keine Items markiert"] }
    if LC:IsMasterLooter() then
        s.ml = { ok = true, text = L["Du bist Plündermeister – alles bereit."] }
    elseif IsInRaid() then
        s.ml = { ok = false, text = L["Im Raid die Plündermethode auf „Plündermeister“ stellen (Rechtsklick auf dein Porträt)."] }
    else
        s.ml = { ok = false, text = L["Wird im Raid geprüft. Plündermethode: Plündermeister."] }
    end
    return s
end

-- Umschalter aus mehreren Knöpfen (eine Auswahl aktiv)
local function Segmented(parent, entries, onSelect)
    local seg = { buttons = {} }
    local prev
    for _, e in ipairs(entries) do
        local b = T:Button(parent, e.label, e.width or 160, 32, "default", function() onSelect(e.key) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else seg.first = b end
        seg.buttons[e.key] = b
        prev = b
    end
    function seg:Set(key)
        for k, b in pairs(self.buttons) do
            b.selected = (k == key)
            if b.selected then
                b:SetBackdropColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
                T:SetBorder(b, C.accent)
            else
                b.Paint(false)
            end
        end
    end
    return seg
end

-- Leiste mit Instanz-Knöpfen: höchstens zwei Zeilen, bei vielen Einträgen blättern („Mehr 1/3“)
local function ChipBar(parent, maxRows)
    maxRows = maxRows or 2
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(CW, 1)
    bar.buttons, bar.page, bar.pages, bar.count = {}, 1, 1, 0
    -- Gut sichtbar: lila gefüllt wie die Hauptknöpfe
    bar.pager = T:Button(bar, L["Mehr"], 124, 30, "primary", function()
        bar.page = bar.page % bar.pages + 1
        bar:Layout()
    end)
    bar.pager:SetPoint("TOPRIGHT", 0, 0)
    bar.pager.tooltipTitle = L["Weitere Einträge"]
    bar.pager.tooltip = L["Blättert zur nächsten Seite der Liste."]

    function bar:SetItems(labels, selected, onClick)
        self.onClick = onClick
        local maxW = CW - 136
        local x, row, page = 0, 0, 1
        for i, label in ipairs(labels) do
            local b = self.buttons[i]
            if not b then
                b = T:Button(self, "", 10, 30, "default", function(btn) if self.onClick then self.onClick(btn.index) end end)
                self.buttons[i] = b
            end
            b.index = i
            b:SetText(label)
            local w = math.ceil(b:GetFontString():GetStringWidth()) + 30
            b:SetWidth(w)
            if x > 0 and x + w > maxW then
                x, row = 0, row + 1
                if row >= maxRows then page, row = page + 1, 0 end
            end
            b.pg, b.row, b.x = page, row, x
            x = x + w + 6
            b.selected = (i == selected)
            if b.selected then
                b:SetBackdropColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
                T:SetBorder(b, C.accent)
            else
                b.Paint(false)
            end
        end
        for i = #labels + 1, #self.buttons do
            self.buttons[i].pg = nil
            self.buttons[i]:Hide()
        end
        self.count, self.pages = #labels, page
        -- Bei neuer Liste auf die Seite mit der Auswahl springen
        local sig = table.concat(labels, "|")
        if sig ~= self.sig then
            self.sig = sig
            local sb = self.buttons[selected or 1]
            self.page = (sb and sb.pg) or 1
        end
        self.page = math.min(self.page, self.pages)
        self:Layout()
    end

    function bar:Layout()
        local maxRow = 0
        for i = 1, self.count do
            local b = self.buttons[i]
            if b.pg == self.page then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", b.x, -b.row * 36)
                b:Show()
                if b.row > maxRow then maxRow = b.row end
            else
                b:Hide()
            end
        end
        self.pager:SetShown(self.pages > 1)
        self.pager:SetText(L["Mehr  "] .. self.page .. "/" .. self.pages .. "  >>")
        self:SetHeight(self.count > 0 and (maxRow * 36 + 30) or 1)
    end
    return bar
end

-- Knopf „Quelle: …“ – Klick wechselt zur nächsten installierten Loot-Quelle
local function SourceButton(parent)
    local b = T:Button(parent, "", 200, 30, "default", function() LC:CycleLootSource() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Loot-Quelle"], 1, 1, 1)
        GameTooltip:AddLine(L["Klicken wechselt die Quelle. „Automatisch“ führt alle installierten zusammen."], nil, nil, nil, true)
        GameTooltip:AddLine(" ")
        local cur = LC:GetLootSource()
        for _, s in ipairs(LC.LOOT_SOURCES) do
            local avail = LC:LootSourceAvailable(s.key)
            local mark = (s.key == cur) and "> " or "   "
            if avail then
                local c = (s.key == cur) and C.accentLt or C.text
                GameTooltip:AddLine(mark .. L[s.label], c[1], c[2], c[3])
            else
                GameTooltip:AddLine(mark .. L[s.label] .. L["  (nicht installiert)"], 0.45, 0.45, 0.48)
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:Update()
        self:SetText(L["Quelle: "] .. LC:GetLootSourceLabel(LC:GetLootSource()))
    end
    return b
end

------------------------------------------------------------------------
-- Gemeinsame Bausteine für die Reservierungs-Seiten
------------------------------------------------------------------------
-- Raids für die Reservierung aus der gewählten Loot-Quelle.
-- Raids mit gespeicherten Reservierungen, die nicht in der Liste sind, werden angehängt.
local function ReserveRaids()
    local list = LC:GetLootDB()
    local out, known = {}, {}
    for _, r in ipairs(list or {}) do
        out[#out + 1] = r
        known[r.key] = true
    end
    for key, R in pairs(LC.db.reserves or {}) do
        if not known[key] and next(R.players or {}) then
            out[#out + 1] = { key = key, name = (key == "custom") and L["Raid (ohne Loot-Quelle)"] or key, bosses = {}, itemCount = 0 }
            known[key] = true
        end
    end
    if #out == 0 then out[1] = { key = "custom", name = L["Raid (ohne Loot-Quelle)"], bosses = {}, itemCount = 0 } end
    return out, list ~= nil and #list > 0
end

-- Item-IDs aus Itemlinks (Shift-Klick) oder eingetippten Zahlen
local function IdsFromText(text)
    text = text or ""
    local ids, seen = {}, {}
    for id in text:gmatch("item:(%d+)") do
        id = tonumber(id)
        if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end
    end
    if #ids > 0 then return ids end
    return LC.ParseItemList(text)
end

local function ItemIcons(items, size)
    local t = {}
    for _, id in ipairs(items or {}) do
        local icon = LC:ItemIcon(id)
        t[#t + 1] = string.format("|T%s:%d:%d:0:0|t %s", tostring(icon), size or 16, size or 16, LC:ItemLink(id))
    end
    return (#t > 0) and table.concat(t, "    ") or (H.muted .. L["–|r"])
end


U.Card, U.PageHeader, U.Tip, U.AcceptLinks = Card, PageHeader, Tip, AcceptLinks
U.SetupStatus, U.Segmented, U.ChipBar, U.SourceButton = SetupStatus, Segmented, ChipBar, SourceButton
U.ReserveRaids, U.IdsFromText, U.ItemIcons = ReserveRaids, IdsFromText, ItemIcons
