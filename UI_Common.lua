-- Light Council – Hauptfenster: gemeinsame Bausteine aller Seiten (Konstanten, Karten, Umschalter …)
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
LC.UI = LC.UI or {}
local U = LC.UI

U.W, U.HGT = 1080, 740
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

------------------------------------------------------------------------
-- Itemsuche: Liste unter einem Eingabefeld, Treffer nach Name oder Item-ID
--   AttachItemSearch(edit, onPick, width) – onPick(treffer) mit { id, raidKey, raidIdx, bossIdx, … }
--   Pfeiltasten wählen, Enter übernimmt, Escape schließt. Shift-Klick-Links bleiben wie bisher.
------------------------------------------------------------------------
local SEARCH_ROWS, SEARCH_ROW_H = 8, 34
local openSearch          -- gerade offene Suchliste (für nachgeladene Itemnamen)

-- actions (optional): Knöpfe rechts in jeder Trefferzeile, z. B. { { label = "Set", tip = "…", func = function(res) end }, … }.
--   Klick auf die Zeile und Enter lösen den ersten Knopf aus.
local ACTION_W = 74
local function AttachItemSearch(edit, onPick, width, actions)
    width = math.max(width or 0, edit:GetWidth(), actions and (380 + #actions * (ACTION_W + 4)) or 380)
    local textW = width - 52 - (actions and (#actions * (ACTION_W + 4) + 4) or 0)
    local dd = CreateFrame("Frame", nil, edit, "BackdropTemplate")
    T:Skin(dd, C.bgDark, C.accentDim)
    dd:SetFrameStrata("FULLSCREEN_DIALOG")
    dd:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
    dd:SetWidth(width)
    dd:Hide()
    dd.rows, dd.results, dd.sel = {}, {}, 1
    dd.foot = T:Text(dd, 11, C.muted, "LEFT")
    dd.foot:SetPoint("BOTTOMLEFT", 10, 7)
    dd.foot:SetWidth(width - 20)
    dd.foot:SetWordWrap(false)

    local function Paint()
        for i, r in ipairs(dd.rows) do
            local a = (i == dd.sel) and 0.22 or 0
            r.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], a)
        end
    end

    local function Pick(i, action)
        local res = dd.results[i]
        if not res then return end
        dd:Hide()
        edit:SetText("")
        edit:ClearFocus()
        if actions then actions[action or 1].func(res) else onPick(res) end
    end

    local function Row(i)
        local r = dd.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, dd)
        r:SetSize(width - 2, SEARCH_ROW_H)
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * SEARCH_ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetTexture(T.WHITE)
        r.bg:SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", 8, 0)
        r.name = T:Text(r, 12, C.text)
        r.name:SetPoint("TOPLEFT", 40, -3)
        r.name:SetWidth(textW)
        r.name:SetWordWrap(false)
        r.sub = T:Text(r, 10, C.muted)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.sub:SetWidth(textW)
        r.sub:SetWordWrap(false)
        if actions then
            r.acts = {}
            for k = #actions, 1, -1 do
                local a = actions[k]
                local b = T:Button(r, L[a.label], ACTION_W, 22, (k == 1) and "primary" or "default", function() Pick(r.index, k) end)
                if k == #actions then b:SetPoint("RIGHT", -6, 0) else b:SetPoint("RIGHT", r.acts[k + 1], "LEFT", -4, 0) end
                if a.tip then b.tooltipTitle, b.tooltip = L[a.label], L[a.tip] end
                r.acts[k] = b
            end
        end
        r:SetScript("OnEnter", function(self)
            dd.sel = self.index
            Paint()
            GameTooltip:SetOwner(dd, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", dd, "TOPRIGHT", 4, 0)
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:SetScript("OnClick", function(self) Pick(self.index) end)
        dd.rows[i] = r
        return r
    end

    function dd:Run()
        local text = edit:GetText() or ""
        local q = strtrim(text)
        -- Itemlinks (Shift-Klick) und Listen mehrerer IDs gehen den bisherigen Weg
        local idList = q:match("^[%d%s,;]+$") and q:find("[,;%s]")
        if q == "" or text:find("|H") or idList or (#q < 2 and not q:match("^%d+$")) then
            self:Hide()
            return
        end
        local results, total, waiting = LC:SearchItems(q, SEARCH_ROWS)
        self.results = results
        self.sel = math.min(self.sel, math.max(1, #results))
        for i = 1, math.max(#results, #self.rows) do
            local res = results[i]
            if res then
                local r = Row(i)
                r.index, r.itemID = i, res.id
                r.icon:SetTexture(LC:ItemIcon(res.id))
                r.name:SetText(LC:ItemLink(res.id) .. H.muted .. "  #" .. res.id .. "|r")
                if res.raidName then
                    r.sub:SetText(res.raidName .. "  ·  " .. (res.boss or "?"))
                else
                    r.sub:SetText(L["nicht in der Loot-Quelle"])
                end
                r:Show()
            elseif self.rows[i] then
                self.rows[i]:Hide()
            end
        end
        local foot
        if #results == 0 then
            foot = (waiting > 0) and L["Lade Itemnamen …"] or L["Kein Item gefunden."]
        elseif total > #results then
            foot = L("%d weitere Treffer – genauer suchen.", total - #results)
        elseif waiting > 0 then
            foot = L["Lade Itemnamen …"]
        end
        self.foot:SetText(foot or "")
        local h = #results * SEARCH_ROW_H + 2 + (foot and 24 or 0)
        self:SetHeight(math.max(h, 26))
        -- Ragt die Liste rechts aus dem Fenster (Suchfeld rechts oben), rechtsbündig unter das Feld legen
        self:ClearAllPoints()
        local win = _G.LightCouncilMainFrame
        local left, winRight = edit:GetLeft(), win and win:IsShown() and win:GetRight()
        if left and winRight and left + width > winRight then
            self:SetPoint("TOPRIGHT", edit, "BOTTOMRIGHT", 0, -2)
        else
            self:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -2)
        end
        Paint()
        self:Show()
        openSearch = self
    end

    local pending
    edit:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        dd.sel = 1
        if pending then return end
        pending = true
        C_Timer.After(0.15, function()
            pending = nil
            if edit:HasFocus() then dd:Run() end
        end)
    end)
    edit:HookScript("OnEditFocusGained", function() LC:WarmItemNames() end)
    edit:HookScript("OnEditFocusLost", function()
        -- kurz warten, damit ein Klick in die Liste noch ankommt
        C_Timer.After(0.2, function()
            if not edit:HasFocus() and not dd:IsMouseOver() then dd:Hide() end
        end)
    end)
    edit:HookScript("OnEscapePressed", function() dd:Hide() end)
    edit:HookScript("OnHide", function() dd:Hide() end)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    edit:HookScript("OnArrowPressed", function(_, key)
        if not dd:IsShown() or #dd.results == 0 then return end
        if key == "DOWN" then dd.sel = dd.sel % #dd.results + 1
        elseif key == "UP" then dd.sel = (dd.sel - 2) % #dd.results + 1 end
        Paint()
    end)
    -- Enter: Treffer übernehmen, sonst das bisherige Verhalten des Feldes
    local origEnter = edit:GetScript("OnEnterPressed")
    edit:SetScript("OnEnterPressed", function(self)
        if dd:IsShown() and dd.results[dd.sel] then
            Pick(dd.sel)
        elseif origEnter then
            origEnter(self)
        end
    end)
    dd:SetScript("OnHide", function(self) if openSearch == self then openSearch = nil end end)
    edit.searchList = dd
    return dd
end

-- Nachgeladene Itemnamen: offene Suchliste aktualisieren
local rerunPending
LC:On("GET_ITEM_INFO_RECEIVED", function()
    if not openSearch or rerunPending then return end
    rerunPending = true
    C_Timer.After(0.3, function()
        rerunPending = nil
        if openSearch and openSearch:IsShown() then openSearch:Run() end
    end)
end)

-- Zeile in einer Scrollliste sichtbar machen (nach dem Aufbau der Liste)
local function ScrollToRow(sf, index, rowH)
    C_Timer.After(0, function()
        if sf.UpdateRange then sf.UpdateRange() end
        local range = math.max(0, sf:GetVerticalScrollRange())
        local offset = math.max(0, math.min(range, (index - 1) * rowH - rowH))
        sf:SetVerticalScroll(offset)
        if sf.bar then sf.bar:SetValue(offset) end
    end)
end

------------------------------------------------------------------------
-- Aufklappmenü (Set-Auswahl, Klick auf eine Gear-Kachel)
--   entries: { { text = …, func = …, checked = true/false/nil, color = C.bad, disabled = true } }
--   text = "-" ist eine Trennlinie
------------------------------------------------------------------------
local menu
local function ShowMenu(anchor, entries)
    if not menu then
        menu = CreateFrame("Frame", "LightCouncilMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        T:Skin(menu, C.bgDark, C.line)
        menu.rows, menu.lines = {}, {}
        -- Klick daneben schließt das Menü. Bevorzugt per GLOBAL_MOUSE_DOWN, damit der Klick
        -- trotzdem ankommt (Spielwelt, Kamera, andere Knöpfe); sonst unsichtbare Fläche als Rückfall.
        local hasGlobal = pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
        if hasGlobal then
            menu:SetScript("OnEvent", function(self)
                if not self:IsShown() or self:IsMouseOver() then return end
                if self.owner and self.owner:IsMouseOver() then return end   -- Klick aufs Ziel schaltet um
                self:Hide()
            end)
        else
            menu.catcher = CreateFrame("Button", nil, UIParent)
            menu.catcher:SetAllPoints(UIParent)
            menu.catcher:SetFrameStrata("FULLSCREEN")
            menu.catcher:RegisterForClicks("AnyUp")
            menu.catcher:SetScript("OnClick", function() menu:Hide() end)
            menu.catcher:Hide()
            menu:SetScript("OnHide", function() menu.catcher:Hide() end)
        end
        menu:SetScript("OnUpdate", function(self)
            if self.owner and not self.owner:IsVisible() then self:Hide() end
        end)
        tinsert(UISpecialFrames, "LightCouncilMenu")
    end
    -- erneuter Klick auf denselben Knopf schließt das Menü wieder
    if menu:IsShown() and menu.owner == anchor then menu:Hide() return end
    local ROW, SEP = 26, 9
    local width, y, nRow, nLine = 170, 6, 0, 0
    for _, e in ipairs(entries) do
        if e.text == "-" then
            nLine = nLine + 1
            local ln = menu.lines[nLine]
            if not ln then ln = T:Line(menu, C.line) menu.lines[nLine] = ln end
            ln:ClearAllPoints()
            ln:SetPoint("TOPLEFT", 8, -(y + 4))
            ln:SetPoint("TOPRIGHT", -8, -(y + 4))
            ln:Show()
            y = y + SEP
        else
            nRow = nRow + 1
            local r = menu.rows[nRow]
            if not r then
                r = CreateFrame("Button", nil, menu)
                r:SetHeight(ROW)
                r.hl = r:CreateTexture(nil, "BACKGROUND")
                r.hl:SetTexture(T.WHITE)
                r.hl:SetAllPoints()
                r.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0)
                r.check = T:Text(r, 12, C.accentLt, "CENTER", nil, true)
                r.check:SetPoint("LEFT", 8, 0)
                r.check:SetWidth(14)
                r.text = T:Text(r, 12, C.text, "LEFT")
                r.text:SetPoint("LEFT", 28, 0)
                r.text:SetWordWrap(false)
                r:SetScript("OnEnter", function(self)
                    if self:IsEnabled() then self.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.18) end
                end)
                r:SetScript("OnLeave", function(self) self.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0) end)
                r:SetScript("OnClick", function(self)
                    menu:Hide()
                    if self.func then self.func() end
                end)
                menu.rows[nRow] = r
            end
            r.func = e.func
            r.text:SetText(e.text)
            local c = e.disabled and C.muted or (e.color or C.text)
            r.text:SetTextColor(c[1], c[2], c[3])
            r.check:SetText(e.checked and "|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t" or "")
            r:SetEnabled(not e.disabled)
            r.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -y)
            r:SetPoint("TOPRIGHT", -1, -y)
            r:Show()
            width = math.max(width, math.ceil(r.text:GetStringWidth()) + 46)
            y = y + ROW
        end
    end
    for i = nRow + 1, #menu.rows do menu.rows[i]:Hide() end
    for i = nLine + 1, #menu.lines do menu.lines[i]:Hide() end
    menu:SetSize(width, y + 6)
    menu.owner = anchor
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    if menu.catcher then menu.catcher:Show() end
    menu:Show()
end

U.Card, U.PageHeader, U.Tip, U.AcceptLinks = Card, PageHeader, Tip, AcceptLinks
U.ShowMenu = ShowMenu
U.SetupStatus, U.Segmented, U.ChipBar, U.SourceButton = SetupStatus, Segmented, ChipBar, SourceButton
U.ReserveRaids, U.IdsFromText, U.ItemIcons = ReserveRaids, IdsFromText, ItemIcons
U.AttachItemSearch, U.ScrollToRow = AttachItemSearch, ScrollToRow

------------------------------------------------------------------------
-- Favoriten und Klassenfilter in den Loot-Listen (Items, Meine Reservierung)
--   Gelten pro Charakter: db.favorites[char] = { [itemID] = true }, db.classFilter[char] = "MAGE"
------------------------------------------------------------------------
local function CharKey() return LC:NameKey(LC:PlayerName()) or "?" end

function LC:MyFavorites()
    self.db.favorites = self.db.favorites or {}
    local k = CharKey()
    self.db.favorites[k] = self.db.favorites[k] or {}
    return self.db.favorites[k]
end

function LC:IsFavorite(id) return id ~= nil and self:MyFavorites()[id] == true end

function LC:ToggleFavorite(id)
    if not id then return end
    local f = self:MyFavorites()
    if f[id] then f[id] = nil else f[id] = true end
    self:RefreshUI()
end

-- Gewählter Klassenfilter (Klassen-Token wie "MAGE") oder nil = alle Klassen
function LC:GetClassFilter()
    local v = self.db.classFilter and self.db.classFilter[CharKey()]
    return (v and v ~= "") and v or nil
end

function LC:SetClassFilter(class)
    self.db.classFilter = self.db.classFilter or {}
    self.db.classFilter[CharKey()] = class or ""
    self:RefreshUI()
end

-- Was eine Klasse tragen bzw. führen kann (Rüstungs- und Waffen-Unterklassen wie im Spiel)
local ARMOR, WEAPON = 4, 2
local PROF = {
    WARRIOR = { armor = { 1, 2, 3, 4, 6 },    weapon = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
    PALADIN = { armor = { 1, 2, 3, 4, 6, 7 }, weapon = { 0, 1, 4, 5, 6, 7, 8 } },
    HUNTER  = { armor = { 1, 2, 3 },          weapon = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
    ROGUE   = { armor = { 1, 2 },             weapon = { 2, 3, 4, 7, 13, 15, 16, 18 } },
    PRIEST  = { armor = { 1 },                weapon = { 4, 10, 15, 19 } },
    SHAMAN  = { armor = { 1, 2, 3, 6, 9 },    weapon = { 0, 1, 4, 5, 10, 13, 15 } },
    MAGE    = { armor = { 1 },                weapon = { 7, 10, 15, 19 } },
    WARLOCK = { armor = { 1 },                weapon = { 7, 10, 15, 19 } },
    DRUID   = { armor = { 1, 2, 8 },          weapon = { 4, 5, 10, 13, 15 } },
}
for _, p in pairs(PROF) do
    local a, w = {}, {}
    for _, v in ipairs(p.armor) do a[v] = true end
    for _, v in ipairs(p.weapon) do w[v] = true end
    p.armor, p.weapon = a, w
end
LC.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Klassenbeschränkung aus dem Tooltip („Klassen: Magier, Priester“), z. B. Set-Teile und Marken
local scanTip, classPattern, classLineCache = nil, nil, {}
local function AllowedClassesLine(id)
    local cached = classLineCache[id]
    if cached ~= nil then return cached or nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo(id) then return nil end   -- Itemdaten noch nicht geladen: später erneut prüfen
    if not ITEM_CLASSES_ALLOWED then classLineCache[id] = false return nil end
    if not classPattern then
        local p = ITEM_CLASSES_ALLOWED:gsub("%%%d%$s", "%%s")
        p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        classPattern = "^" .. p:gsub("%%s", "(.+)") .. "$"
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "LightCouncilScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetItemByID, scanTip, id)
    local found = false
    local lines = ok and scanTip:NumLines() or 0
    for i = 2, lines do
        local fs = _G["LightCouncilScanTipTextLeft" .. i]
        local list = fs and fs:GetText() and fs:GetText():match(classPattern)
        if list then found = list break end
    end
    scanTip:Hide()
    -- Nur merken, wenn der Tooltip auch Inhalt hatte (sonst beim nächsten Mal erneut prüfen)
    if lines > 1 then classLineCache[id] = found end
    return found or nil
end

-- Kann die Klasse das Item nutzen? (unbekannte Klassen und Nicht-Ausrüstung: ja)
function LC:ItemFitsClass(id, class)
    if not class or not id then return true end
    local list = AllowedClassesLine(id)
    if list then
        local male = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
        local female = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
        for name in list:gmatch("[^,]+") do
            name = strtrim(name)
            if name == male or name == female then return true end
        end
        return false
    end
    local p = PROF[class]
    if not p then return true end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInstant then return true end
    local _, _, _, equipLoc, _, classID, subID = getInstant(id)
    if equipLoc == "INVTYPE_CLOAK" then return true end
    if classID == ARMOR then return subID == 0 or p.armor[subID] == true end
    if classID == WEAPON then return p.weapon[subID] == true end
    return true
end

-- Lokalisierter Klassenname
function LC:ClassName(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- Knopf „Klasse: …“ mit Aufklappmenü
local function ClassFilterButton(parent, width)
    local b = T:Button(parent, "", width, 26, "default")
    b:SetScript("OnClick", function(self)
        local cur = LC:GetClassFilter()
        local _, mine = UnitClass("player")
        local entries = {
            { text = L["Alle Klassen"], checked = cur == nil, func = function() LC:SetClassFilter(nil) end },
        }
        if mine then
            entries[#entries + 1] = { text = L("Meine Klasse (%s)", LC:ClassName(mine)), checked = cur == mine, func = function() LC:SetClassFilter(mine) end }
        end
        entries[#entries + 1] = { text = "-" }
        for _, c in ipairs(LC.CLASS_ORDER) do
            if c ~= mine then
                entries[#entries + 1] = { text = LC:ClassName(c), checked = cur == c, func = function() LC:SetClassFilter(c) end }
            end
        end
        ShowMenu(self, entries)
    end)
    Tip(b, L["Klassenfilter"], L["Zeigt nur Items, die die Klasse tragen bzw. benutzen kann (Rüstungsart, Waffen, Klassen-Items). Gilt für alle Loot-Listen."])
    -- hidden: Zahl der gerade ausgeblendeten Items (wird hinten angezeigt)
    function b:Update(hidden)
        local c = LC:GetClassFilter()
        local text = c and L("Klasse: %s", LC:ClassName(c)) or L["Klasse: alle"]
        if hidden and hidden > 0 then text = text .. H.muted .. "  (-" .. hidden .. ")|r" end
        self:SetText(text)
    end
    return b
end

-- Items einer Liste nach Klasse filtern. Rückgabe: gefilterte Liste, Zahl der ausgeblendeten
local function FilterItems(items)
    local class = LC:GetClassFilter()
    if not class then return items or {}, 0 end
    local out, hidden = {}, 0
    for _, id in ipairs(items or {}) do
        if LC:ItemFitsClass(id, class) then out[#out + 1] = id else hidden = hidden + 1 end
    end
    return out, hidden
end

-- Favoriten eines Raids (in Boss-Reihenfolge). Rückgabe: Itemliste, [itemID] = Boss
local function FavItems(raid)
    local fav = LC:MyFavorites()
    local out, from = {}, {}
    for _, boss in ipairs((raid and raid.bosses) or {}) do
        for _, id in ipairs(boss.items or {}) do
            if fav[id] and not from[id] then
                out[#out + 1] = id
                from[id] = boss
            end
        end
    end
    return out, from
end

-- Stern-Knopf zum Favorisieren (in einer Item-Zeile mit row.itemID)
local STAR_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local function FavStar(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(20, 20)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexture(STAR_TEX)
    b:SetScript("OnClick", function() LC:ToggleFavorite(row.itemID) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Favorit"], 1, 1, 1)
        GameTooltip:AddLine(L["Merkt das Item für dich vor. Alle Favoriten eines Raids stehen oben in der Bossliste unter „Favoriten“."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    function b:Update(id)
        local on = LC:IsFavorite(id)
        self.tex:SetDesaturated(not on)
        self.tex:SetAlpha(on and 1 or 0.35)
    end
    return b
end

U.ClassFilterButton, U.FilterItems, U.FavItems, U.FavStar = ClassFilterButton, FilterItems, FavItems, FavStar
