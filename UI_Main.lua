-- Light Council – Hauptfenster
-- Seiten: Start (Checkliste), Loot, Council-Items, Import, Spieler, Protokoll, Einstellungen
local _, LC = ...
local T = LC.T
local C = T.C
local H = T.HEX

local main
local pages = {}
local nav = {}
local currentTab

local W, HGT = 1000, 740
local SIDEBAR = 200
local PAD = 18
local CW = W - SIDEBAR - 2 * PAD - 2   -- Inhaltsbreite

local SelectTab -- vorwärts deklariert

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
    s.council = { ok = nCouncil == size, text = (nCouncil == 0) and "Noch niemand eingetragen"
        or (nCouncil .. " von " .. size .. " eingetragen: " .. table.concat(list, ", ")) }
    -- Reservierungen im Addon: wie viele Spieler haben (bestätigt) reserviert?
    local players, pending = 0, 0
    for _, R in pairs(db.reserves or {}) do
        for _, rec in pairs(R.players) do
            if (rec.rev or 0) > 0 then players = players + 1 end
            if rec.pending then pending = pending + 1 end
        end
    end
    s.softres = { ok = players > 0, pending = pending,
        text = (players > 0) and (players .. " Reservierungen bestätigt" .. ((pending > 0) and (" · " .. pending .. " Änderungsantrag/-anträge offen") or ""))
            or "Noch keine Reservierungen – Raider reservieren unter „Meine Reservierung“" }
    local ci = 0
    for _ in pairs(db.councilItems) do ci = ci + 1 end
    s.items = { ok = ci > 0, text = (ci > 0) and (ci .. " Items markiert") or "Noch keine Items markiert" }
    if LC:IsMasterLooter() then
        s.ml = { ok = true, text = "Du bist Plündermeister – alles bereit." }
    elseif IsInRaid() then
        s.ml = { ok = false, text = "Im Raid die Plündermethode auf „Plündermeister“ stellen (Rechtsklick auf dein Porträt)." }
    else
        s.ml = { ok = false, text = "Wird im Raid geprüft. Plündermethode: Plündermeister." }
    end
    return s
end

------------------------------------------------------------------------
-- Seite: Start
------------------------------------------------------------------------
local STEPS = {
    { key = "council", title = "Council festlegen", tab = "settings", button = "Eintragen", desc = "3 oder 5 Council-Mitglieder mit Vor- und Nachnamen." },
    { key = "softres", title = "Reservierungen sammeln", tab = "reserves", button = "Übersicht", desc = "Raider reservieren selbst im Addon; der Council bestätigt automatisch." },
    { key = "items", title = "Council-Items markieren", tab = "items", button = "Raid-Loot öffnen", desc = "Im Raid-Loot per Häkchen – nur bei diesen Items entscheidet der Council." },
    { key = "ml", title = "Master Loot aktivieren", desc = "Voraussetzung, damit das Addon den Loot sieht und vergeben kann." },
}

local function CreateStartPage(p)
    -- Begrüßung mit Logo
    local hero = Card(p, 110)
    hero:SetPoint("TOPLEFT")
    hero:SetWidth(CW)
    local glow = hero:CreateTexture(nil, "BORDER")
    glow:SetTexture(T.WHITE)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    T:Gradient(glow, { 0.62, 0.39, 1, 0.14 }, { 0.62, 0.39, 1, 0 })
    local logo = hero:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(T.LOGO)
    logo:SetSize(88, 88)
    logo:SetPoint("TOPLEFT", 14, -12)
    local ht = T:Text(hero, 20, C.text, "LEFT", nil, true)
    ht:SetPoint("TOPLEFT", 118, -20)
    ht:SetText("Willkommen bei Light Council")
    local hs = T:Text(hero, 12, C.muted)
    hs:SetPoint("TOPLEFT", ht, "BOTTOMLEFT", 0, -8)
    hs:SetWidth(CW - 140)
    hs:SetSpacing(3)
    hs:SetText("Raider reservieren ihre Items direkt im Addon – einmal gespeichert, ist die Wahl gesperrt und nur mit Freigabe des Councils änderbar. "
        .. "Bei markierten Council-Items stimmt der Council (3 oder 5 Personen) kurz ab – "
        .. "die Entscheidung wird per Raidwarnung angesagt. Raider mit dem Addon bekommen ein Loot-Fenster mit Würfel-Knopf, "
        .. "ohne Addon läuft alles wie gewohnt über den Raidchat.")
    -- Höhe an den Text anpassen, damit nichts gequetscht wird
    local heroH = math.max(112, 20 + ht:GetStringHeight() + 8 + hs:GetStringHeight() + 22)
    hero:SetHeight(heroH)

    -- Checkliste
    local y = heroH + 22
    local lt = T:Text(p, 14, C.text, "LEFT", nil, true)
    lt:SetPoint("TOPLEFT", 0, -y)
    lt:SetText("Vor dem Raid")
    y = y + 28

    p.steps = {}
    for i, step in ipairs(STEPS) do
        local row = Card(p, 62)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(CW)
        row.num = T:Text(row, 16, C.muted, "CENTER", nil, true)
        row.num:SetPoint("LEFT", 10, 0)
        row.num:SetWidth(40)
        row.title = T:Text(row, 14, C.text, "LEFT", nil, true)
        row.title:SetPoint("TOPLEFT", 60, -12)
        row.title:SetText(step.title)
        row.sub = T:Text(row, 12, C.muted)
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
        row.sub:SetWidth(CW - 220)
        row.sub:SetWordWrap(false)
        row.stripe = row:CreateTexture(nil, "ARTWORK")
        row.stripe:SetTexture(T.WHITE)
        row.stripe:SetPoint("TOPLEFT", 1, -1)
        row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
        row.stripe:SetWidth(3)
        if step.tab then
            row.btn = T:Button(row, step.button, 130, 32, "default", function() SelectTab(step.tab) end)
            row.btn:SetPoint("RIGHT", -14, 0)
        end
        row.step = step
        row.index = i
        p.steps[i] = row
        y = y + 62 + 8
    end

    -- Schnellaktion
    y = y + 14
    local test = T:Button(p, "Test-Abstimmung starten", 220, 34, "primary", function() LC:StartTest("") end)
    test:SetPoint("TOPLEFT", 0, -y)
    Tip(test, "Test-Abstimmung", "Spielt den kompletten Ablauf mit Beispiel-Spielern durch: Popup, Abstimmung, Würfeln. Ansagen erscheinen nur in deinem Chat.")
    local tt = T:Text(p, 12, C.muted)
    tt:SetPoint("LEFT", test, "RIGHT", 14, 0)
    tt:SetWidth(CW - 240)
    tt:SetText("Probier den Ablauf einmal alleine aus – nichts davon geht in den Raidchat.")
end

local function RefreshStart()
    local p = pages.start
    local st = SetupStatus()
    for _, row in ipairs(p.steps) do
        local s = st[row.step.key]
        row.sub:SetText(s.text)
        if s.ok then
            row.num:SetText(H.good .. "OK|r")
            row.stripe:SetVertexColor(unpack(C.good))
            if row.btn then row.btn:SetText(row.step.button == "Eintragen" and "Ändern" or "Bearbeiten") end
        else
            row.num:SetText(H.accentLt .. row.index .. "|r")
            row.stripe:SetVertexColor(unpack(C.accent))
            if row.btn then row.btn:SetText(row.step.button) end
        end
    end
end

------------------------------------------------------------------------
-- Seite: Loot
------------------------------------------------------------------------
local lootRows = {}
local ROW_H = 52
local LOOT_LW = CW - 380   -- Breite für Itemname und Reservierer

local function CreateLootPage(p)
    local y = PageHeader(p, "Loot", "Öffnest du als Plündermeister eine Leiche, erscheinen die Items hier. Council-Items starten automatisch.")

    -- Automatisch vergeben: oben rechts neben der Überschrift
    p.autoAward = T:Check(p, "Automatisch vergeben")
    p.autoAward:SetPoint("TOPRIGHT", -170, -6)
    p.autoAward:SetScript("OnClick", function(self)
        LC.db.config.autoAward = self:GetChecked() and true or false
    end)
    p.autoAward:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Automatisch vergeben", 1, 1, 1)
        GameTooltip:AddLine("Steht der Gewinner fest, bekommt er das Item sofort – ohne Klick auf „An …“. "
            .. "Klappt nur, solange das Lootfenster offen ist; sonst kommt ein Hinweis im Chat.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    p.autoAward:HookScript("OnLeave", GameTooltip_Hide)

    -- Statuskarte
    local status = Card(p, 54)
    status:SetPoint("TOPLEFT", 0, -y)
    status:SetWidth(CW)
    local stripe = status:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture(T.WHITE)
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    p.stripe = stripe
    p.statusTitle = T:Text(status, 13, C.text)
    p.statusTitle:SetPoint("TOPLEFT", 14, -9)
    p.statusTitle:SetWidth(CW - 420)
    p.statusTitle:SetWordWrap(false)
    p.statusSub = T:Text(status, 11, C.muted)
    p.statusSub:SetPoint("TOPLEFT", p.statusTitle, "BOTTOMLEFT", 0, -4)
    p.statusSub:SetWidth(CW - 420)
    p.statusSub:SetWordWrap(false)
    p.timeBar = T:Bar(status, 3)
    p.timeBar:SetPoint("BOTTOMLEFT", 4, 1)
    p.timeBar:SetPoint("BOTTOMRIGHT", -1, 1)
    p.timeBar:SetBackdropBorderColor(0, 0, 0, 0)

    p.btnCancel = T:Button(status, "Abbrechen", 96, 26, "danger", function() LC:CancelAll() end)
    p.btnCancel:SetPoint("RIGHT", -12, 0)
    Tip(p.btnCancel, "Abbrechen", "Bricht die laufende Abstimmung oder Würfelrunde ab und leert die Warteschlange.")
    p.btnFinish = T:Button(status, "Würfeln beenden", 130, 26, "default", function() LC:FinishRoll() end)
    p.btnFinish:SetPoint("RIGHT", p.btnCancel, "LEFT", -6, 0)
    Tip(p.btnFinish, "Würfeln beenden", "Beendet die Würfelrunde sofort und sagt den Gewinner an, statt auf den Ablauf der Zeit zu warten.")
    p.btnAll = T:Button(status, "Alle starten", 140, 26, "primary", function()
        for _, e in ipairs(LC.lootItems) do
            if e.status == "offen" and not e.winner and not e.awarded and not e.looted then LC:Enqueue(e) end
        end
    end)
    p.btnAll:SetPoint("RIGHT", p.btnFinish, "LEFT", -6, 0)
    Tip(p.btnAll, "Alle starten", "Stellt alle offenen Items nacheinander in die Warteschlange: Council-Items gehen an den Council, alle anderen werden direkt ausgewürfelt.")
    y = y + 54 + 12

    local sf, content = T:Scroll(p)
    sf:SetPoint("TOPLEFT", 0, -y)
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    p.list = content

    -- Leerer Zustand
    local empty = CreateFrame("Frame", nil, p)
    empty:SetPoint("TOPLEFT", 0, -y - 24)
    empty:SetSize(CW, 200)
    local logo = empty:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(T.LOGO)
    logo:SetSize(72, 72)
    logo:SetPoint("TOP")
    local et = T:Text(empty, 13, C.text, "CENTER")
    et:SetPoint("TOP", logo, "BOTTOM", 0, -12)
    et:SetText("Gerade kein Loot")
    local es = T:Text(empty, 11, C.muted, "CENTER")
    es:SetPoint("TOP", et, "BOTTOM", 0, -6)
    es:SetWidth(CW - 80)
    es:SetText("Dieses Fenster öffnet sich von selbst, sobald du als Plündermeister eine Leiche öffnest.")
    local eb1 = T:Button(empty, "Erste Schritte", 130, 26, "default", function() SelectTab("start") end)
    eb1:SetPoint("TOP", es, "BOTTOM", -70, -14)
    local eb2 = T:Button(empty, "Test-Abstimmung", 130, 26, "primary", function() LC:StartTest("") end)
    eb2:SetPoint("LEFT", eb1, "RIGHT", 10, 0)
    p.empty = empty

    p:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.2 then return end
        self.acc = 0
        LC:UpdateLootStatus()
    end)
end

local function GetLootRow(parent, i)
    if lootRows[i] then return lootRows[i] end
    local r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    r:SetSize(CW - 10, ROW_H - 6)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    T:Skin(r, C.panel)

    r.icon = T:Icon(r, 34)
    r.icon:SetPoint("LEFT", 6, 0)

    r.linkBtn = CreateFrame("Button", nil, r)
    r.linkBtn:SetPoint("TOPLEFT", 50, -7)
    r.linkBtn:SetSize(LOOT_LW, 16)
    r.link = T:Text(r.linkBtn, 12, C.text)
    r.link:SetPoint("LEFT")
    r.link:SetWidth(LOOT_LW)
    r.link:SetWordWrap(false)
    r.linkBtn:SetScript("OnEnter", function(self)
        local e = r.entry
        if e and e.link and e.link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(e.link)
            GameTooltip:Show()
        end
    end)
    r.linkBtn:SetScript("OnLeave", GameTooltip_Hide)

    r.info = T:Text(r, 10, C.muted)
    r.info:SetPoint("TOPLEFT", 50, -27)
    r.info:SetWidth(LOOT_LW)
    r.info:SetWordWrap(false)

    r.council = T:Check(r, "Council", 14)
    r.council:SetPoint("LEFT", 62 + LOOT_LW, 8)
    r.council:SetScript("OnClick", function(self)
        if r.entry and not r.entry.test then
            LC:SetCouncilItem(r.entry.itemID, self:GetChecked())
            LC:RefreshUI()
        end
    end)
    r.council:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Council-Item", 1, 1, 1)
        GameTooltip:AddLine("Angehakt: Der Council entscheidet, wer würfeln darf. Gilt dauerhaft für dieses Item.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    r.council:HookScript("OnLeave", GameTooltip_Hide)
    r.state = T:Text(r, 10, C.muted)
    r.state:SetPoint("LEFT", 62 + LOOT_LW, -10)
    r.state:SetWidth(110)
    r.state:SetWordWrap(false)

    r.btnAward = T:Button(r, "Vergeben", 100, 26, "default", function()
        if r.entry then LC:AwardLoot(r.entry) end
    end)
    r.btnAward:SetPoint("RIGHT", -8, 0)
    r.btnAction = T:Button(r, "Council starten", 112, 26, "primary", function()
        if r.entry then LC:Enqueue(r.entry) end
    end)
    r.btnAction:SetPoint("RIGHT", r.btnAward, "LEFT", -6, 0)

    lootRows[i] = r
    return r
end

function LC:UpdateLootStatus()
    local p = pages.loot
    if not p or not p:IsShown() then return end
    local a, r = self.active, self.roll
    if a then
        local left = math.max(0, a.endsAt - GetTime())
        local names = {}
        for _, v in ipairs(a.voteOrder) do names[#names + 1] = v.name end
        p.statusTitle:SetText("Council stimmt ab:  " .. a.entry.link)
        p.statusSub:SetText(string.format("%d von %d Stimmen%s  ·  noch %d Sek.", #a.voteOrder, a.nVoters,
            (#names > 0) and (" (" .. table.concat(names, ", ") .. ")") or "", math.ceil(left)))
        p.timeBar.bar:SetMinMaxValues(0, self.db.config.voteTimeout)
        p.timeBar.bar:SetValue(left)
        p.timeBar.bar:SetStatusBarColor(unpack(C.accent))
        p.timeBar:Show()
        p.stripe:SetVertexColor(unpack(C.accent))
    elseif r then
        local left = math.max(0, r.endsAt - GetTime())
        local list = {}
        for _, x in pairs(r.rolls) do list[#list + 1] = x end
        -- Main Spec vor Off Spec
        table.sort(list, function(x, y)
            if (x.os and 1 or 0) ~= (y.os and 1 or 0) then return not x.os end
            return x.roll > y.roll
        end)
        local parts = {}
        for i = 1, math.min(6, #list) do
            parts[#parts + 1] = (i == 1 and H.accentLt or "") .. list[i].name .. " " .. list[i].roll
                .. (list[i].os and " OS" or "") .. (i == 1 and "|r" or "")
        end
        p.statusTitle:SetText("Es wird gewürfelt:  " .. r.entry.link)
        p.statusSub:SetText(((#parts > 0) and table.concat(parts, "  ·  ") or "Noch keine Würfe") .. "  ·  noch " .. math.ceil(left) .. " Sek.")
        p.timeBar.bar:SetMinMaxValues(0, self.db.config.rollTimeout)
        p.timeBar.bar:SetValue(left)
        p.timeBar.bar:SetStatusBarColor(unpack(C.warn))
        p.timeBar:Show()
        p.stripe:SetVertexColor(unpack(C.warn))
    else
        local q = #self.queue
        if q > 0 then
            p.statusTitle:SetText(q .. " Item(s) warten")
        elseif #self.lootItems > 0 then
            p.statusTitle:SetText("Bereit – nächstes Item auswählen")
        else
            p.statusTitle:SetText("Bereit")
        end
        if self:IsMasterLooter() then
            p.statusSub:SetText(self.db.config.autoAward and "„Alle starten“ – Gewinner bekommen ihr Item automatisch."
                or "„Alle starten“ → Gewinner steht fest → „An …“ klicken.")
        else
            p.statusSub:SetText(H.warn .. "Du bist nicht Plündermeister.|r Loot erscheint nur beim Plündermeister.")
        end
        p.timeBar:Hide()
        p.stripe:SetVertexColor(unpack(C.line))
    end
    p.btnCancel:SetEnabled(a ~= nil or r ~= nil or #self.queue > 0)
    p.btnFinish:SetEnabled(r ~= nil)
    local open = 0
    for _, e in ipairs(self.lootItems) do
        if e.status == "offen" and not e.winner and not e.awarded and not e.looted then open = open + 1 end
    end
    p.btnAll:SetEnabled(open > 0)
    p.btnAll:SetText(open > 1 and ("Alle starten (" .. open .. ")") or "Alle starten")
end

local function RefreshLoot()
    local p = pages.loot
    p.autoAward:SetChecked(LC.db.config.autoAward)
    local items = LC.lootItems
    p.empty:SetShown(#items == 0)
    local busy = LC.active or LC.roll
    for i = 1, math.max(#items, #lootRows) do
        local e = items[i]
        if e then
            local r = GetLootRow(p.list, i)
            r.entry = e
            r.icon.tex:SetTexture(LC:ItemIcon(e.itemID))
            LC:FixEntryLink(e)
            local quality = e.quality
            if not quality then
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                quality = select(3, getInfo(e.itemID))
            end
            local qc = T:QualityColor(quality)
            r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            r.link:SetText(e.link)

            local res = e.test and e.testReservers or LC:GetReservers(e.itemID)
            local names = {}
            for _, x in ipairs(res) do names[#names + 1] = x.name end
            local info = (#names > 0) and ("Reserviert: " .. table.concat(names, ", ")) or "Keine Reservierung – freies Würfeln"
            local prio = LC:GetPrio(e.itemID)
            if prio then info = H.accentLt .. "Prio:|r " .. table.concat(prio, " > ") .. "   " .. info end
            r.info:SetText(info)

            r.council:SetChecked(e.isCouncil)
            r.council:SetEnabled(not e.test and not busy and not e.awarded and e.status ~= "wartet")

            local st = e.status or "offen"
            if e.awarded then st = H.good .. "vergeben|r"
            elseif e.looted then st = "nicht mehr im Loot"
            elseif e.winner then st = H.accentLt .. "Gewinner|r"
            elseif st == "offen" then st = "" end
            r.state:SetText(st)

            local canStart = not busy and not e.awarded and not e.looted and (e.status == "offen" or e.winner ~= nil)
            if e.winner and not e.awarded then
                r.btnAction:SetText("Neu starten")
                r.btnAction.tooltip = "Startet Abstimmung bzw. Würfeln für dieses Item noch einmal."
            else
                r.btnAction:SetText(e.isCouncil and "Council starten" or "Würfeln lassen")
                r.btnAction.tooltip = e.isCouncil
                    and "Der Council bekommt ein Popup und entscheidet, wer würfeln darf. Danach wird automatisch gewürfelt."
                    or "Sagt im Raid an, wer würfeln darf (die Reservierer), und wertet die Würfe aus."
            end
            r.btnAction.tooltipTitle = r.btnAction:GetText()
            r.btnAction:SetEnabled(canStart)

            if e.awarded then
                r.btnAward:SetText("Vergeben")
            elseif e.winner then
                r.btnAward:SetText("An " .. (e.winner:match("^(%S+)") or e.winner))
            else
                r.btnAward:SetText("Vergeben")
            end
            r.btnAward.tooltipTitle = "Vergeben"
            r.btnAward.tooltip = e.winner and ("Gibt das Item per Plündermeister direkt an " .. e.winner .. ".") or "Wird aktiv, sobald ein Gewinner feststeht."
            r.btnAward:SetEnabled(e.winner ~= nil and not e.awarded and not e.looted)
            r:Show()
        elseif lootRows[i] then
            lootRows[i].entry = nil
            lootRows[i]:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #items * ROW_H))
    LC:UpdateLootStatus()
end

------------------------------------------------------------------------
-- Seite: Raid-Loot – Council-Items und Prio per Klick (Daten aus AtlasLoot)
------------------------------------------------------------------------
local browseRows, markedRows, bossButtons, raidChips = {}, {}, {}, {}
local ITEM_ROW = 50
local BOSS_W = 230

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
    bar.pager = T:Button(bar, "Mehr", 124, 30, "primary", function()
        bar.page = bar.page % bar.pages + 1
        bar:Layout()
    end)
    bar.pager:SetPoint("TOPRIGHT", 0, 0)
    bar.pager.tooltipTitle = "Weitere Einträge"
    bar.pager.tooltip = "Blättert zur nächsten Seite der Liste."

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
        self.pager:SetText("Mehr  " .. self.page .. "/" .. self.pages .. "  >>")
        self:SetHeight(self.count > 0 and (maxRow * 36 + 30) or 1)
    end
    return bar
end

-- Knopf „Quelle: …“ – Klick wechselt zur nächsten installierten Loot-Quelle
local function SourceButton(parent)
    local b = T:Button(parent, "", 200, 30, "default", function() LC:CycleLootSource() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Loot-Quelle", 1, 1, 1)
        GameTooltip:AddLine("Klicken wechselt die Quelle. „Automatisch“ führt alle installierten zusammen.", nil, nil, nil, true)
        GameTooltip:AddLine(" ")
        local cur = LC:GetLootSource()
        for _, s in ipairs(LC.LOOT_SOURCES) do
            local avail = LC:LootSourceAvailable(s.key)
            local mark = (s.key == cur) and "> " or "   "
            if avail then
                local c = (s.key == cur) and C.accentLt or C.text
                GameTooltip:AddLine(mark .. s.label, c[1], c[2], c[3])
            else
                GameTooltip:AddLine(mark .. s.label .. "  (nicht installiert)", 0.45, 0.45, 0.48)
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:Update()
        self:SetText("Quelle: " .. LC:GetLootSourceLabel(LC:GetLootSource()))
    end
    return b
end

-- Item-Zeile: Icon, Name, Prio-Zusammenfassung, Council-Häkchen bzw. Entfernen, Prio-Knopf
local function CreateItemRow(parent, width, withRemove)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(width, ITEM_ROW - 6)
    T:Skin(r, C.panel)
    r.icon = T:Icon(r, 34)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.name:SetPoint("TOPLEFT", 50, -6)
    r.name:SetWordWrap(false)
    r.sub = T:Text(r, 11, C.muted)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetWordWrap(false)

    r.prio = T:Button(r, "Prio festlegen", 120, 30, "default", function() LC:OpenPrioEditor(r.itemID) end)
    r.prio:SetPoint("RIGHT", -8, 0)
    r.prio.tooltipTitle = "Prio festlegen"
    r.prio.tooltip = "Spieler in der gewünschten Reihenfolge anklicken. Die Prio wird im Loot-Fenster angezeigt und beim Würfeln angesagt."
    if withRemove then
        r.remove = T:Button(r, "Entfernen", 96, 30, "ghost", function()
            LC:SetCouncilItem(r.itemID, false)
            LC:RefreshUI()
        end)
        r.remove:SetPoint("RIGHT", r.prio, "LEFT", -6, 0)
    else
        r.council = T:Check(r, "Council")
        r.council:SetPoint("RIGHT", r.prio, "LEFT", -92, 0)
        r.council:SetScript("OnClick", function(self)
            LC:SetCouncilItem(r.itemID, self:GetChecked())
            LC:RefreshUI()
        end)
        r.council:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Council-Item", 1, 1, 1)
            GameTooltip:AddLine("Angehakt: Bei diesem Item entscheidet der Council, wer würfeln darf.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        r.council:HookScript("OnLeave", GameTooltip_Hide)
    end
    local textW = width - 50 - 250
    r.name:SetWidth(textW)
    r.sub:SetWidth(textW)

    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.panelAlt[1], C.panelAlt[2], C.panelAlt[3], 1)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1)
        GameTooltip:Hide()
    end)
    return r
end

local function FillItemRow(r, itemID, chance)
    r.itemID = itemID
    r.icon.tex:SetTexture(LC:ItemIcon(itemID))
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(itemID)
    local qc = T:QualityColor(quality)
    r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
    r.name:SetText(LC:ItemLink(itemID))
    local prio = LC:GetPrio(itemID)
    local nRes = #LC:GetReservers(itemID)
    local parts = {}
    if prio and #prio > 0 then
        parts[#parts + 1] = H.accentLt .. "Prio:|r " .. table.concat(prio, " > ")
    else
        parts[#parts + 1] = "Keine Prio"
    end
    if nRes > 0 then parts[#parts + 1] = nRes .. (nRes == 1 and " Reservierung" or " Reservierungen") end
    if chance then table.insert(parts, 1, H.good .. chance .. " %|r Drop") end
    r.sub:SetText(table.concat(parts, "   ·   "))
    r.prio:SetText((prio and #prio > 0) and "Prio ändern" or "Prio festlegen")
    if r.council then r.council:SetChecked(LC:IsCouncilItem(itemID)) end
end

local function CreateItemsPage(p)
    local y = PageHeader(p, "Raid-Loot", "Council-Items markieren und Prio festlegen – direkt aus AtlasLoot oder Naowh Forever, ohne IDs abzutippen.")
    p.sourceBtn = SourceButton(p)
    p.sourceBtn:SetPoint("TOPRIGHT", 0, 0)
    p.mode = "browse"
    p.seg = Segmented(p, {
        { key = "browse", label = "Loot durchsuchen", width = 180 },
        { key = "marked", label = "Council-Items", width = 170 },
    }, function(key)
        p.mode = key
        LC:RefreshUI()
    end)
    p.seg.first:SetPoint("TOPLEFT", 0, -y)
    p.msg = T:Text(p, 12, C.muted, "LEFT")
    p.msg:SetPoint("LEFT", p.seg.buttons.marked, "RIGHT", 16, 0)
    p.msg:SetWidth(CW - 360 - 20)
    p.msg:SetWordWrap(false)
    y = y + 32 + 16

    ---------------- Ansicht 1: Raids durchsuchen ----------------
    local browse = CreateFrame("Frame", nil, p)
    browse:SetPoint("TOPLEFT", 0, -y)
    browse:SetPoint("BOTTOMRIGHT")
    p.browse = browse

    p.chips = ChipBar(browse)
    p.chips:SetPoint("TOPLEFT")

    p.dbError = Card(browse, 120)
    p.dbError:SetPoint("TOPLEFT")
    p.dbError:SetWidth(CW)
    p.dbError.text = T:Text(p.dbError, 12, C.text)
    p.dbError.text:SetPoint("TOPLEFT", 18, -18)
    p.dbError.text:SetWidth(CW - 36)
    p.dbError.text:SetSpacing(3)

    local bossCol = Card(browse)
    bossCol:SetPoint("TOPLEFT", p.chips, "BOTTOMLEFT", 0, -14)
    bossCol:SetPoint("BOTTOMLEFT")
    bossCol:SetWidth(BOSS_W)
    T:Skin(bossCol, C.bgDark)
    local bt = T:Text(bossCol, 12, C.text, "LEFT", nil, true)
    bt:SetPoint("TOPLEFT", 16, -14)
    bt:SetText("Bosse")
    local bsf, bcontent = T:Scroll(bossCol)
    bsf:SetPoint("TOPLEFT", 0, -40)
    bsf:SetPoint("BOTTOMRIGHT", -12, 8)
    p.bossCol, p.bossList = bossCol, bcontent

    local isf, icontent = T:Scroll(browse)
    isf:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    isf:SetPoint("BOTTOMRIGHT", -10, 0)
    p.itemScroll, p.itemList = isf, icontent
    p.itemsW = CW - BOSS_W - 14 - 12

    -- Hinweis, wenn AtlasLoot für einen Boss noch keinen Loot hat (neue Forever-Raids)
    p.itemsEmpty = Card(browse, 120)
    p.itemsEmpty:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    p.itemsEmpty:SetWidth(p.itemsW)
    local ie = T:Text(p.itemsEmpty, 14, C.text, "LEFT", nil, true)
    ie:SetPoint("TOPLEFT", 18, -18)
    ie:SetText("Loot folgt")
    local ies = T:Text(p.itemsEmpty, 12, C.muted)
    ies:SetPoint("TOPLEFT", ie, "BOTTOMLEFT", 0, -8)
    ies:SetWidth(p.itemsW - 36)
    ies:SetSpacing(3)
    ies:SetText("AtlasLoot hat für diesen Boss noch keine Items eingetragen. Sobald AtlasLoot aktualisiert wird, erscheinen sie hier automatisch.\n"
        .. "Bis dahin: Unter „Council-Items“ ein gedroppetes Item per Shift-Klick hinzufügen.")

    ---------------- Ansicht 2: markierte Council-Items ----------------
    local marked = CreateFrame("Frame", nil, p)
    marked:SetPoint("TOPLEFT", 0, -y)
    marked:SetPoint("BOTTOMRIGHT")
    p.marked = marked

    local add = Card(marked, 76)
    add:SetPoint("TOPLEFT")
    add:SetWidth(CW)
    local al = T:Text(add, 12, C.text, "LEFT", nil, true)
    al:SetPoint("TOPLEFT", 16, -12)
    al:SetText("Item manuell hinzufügen")
    p.input = T:Input(add, CW - 170, 30)
    p.input:SetPoint("TOPLEFT", al, "BOTTOMLEFT", 0, -8)
    p.input:SetPlaceholder("Shift-Klick auf ein Item oder Item-ID eintippen")
    AcceptLinks(p.input)
    local function DoAdd()
        local ok, msg = LC:AddCouncilItems(p.input:GetText())
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        if ok then p.input:SetText("") end
        LC:RefreshUI()
    end
    p.input:SetScript("OnEnterPressed", function(self) DoAdd() self:ClearFocus() end)
    local addBtn = T:Button(add, "Hinzufügen", 120, 30, "primary", DoAdd)
    addBtn:SetPoint("LEFT", p.input, "RIGHT", 10, 0)

    local msf, mcontent = T:Scroll(marked)
    msf:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -14)
    msf:SetPoint("BOTTOMRIGHT", -10, 46)
    p.markedList = mcontent
    p.markedEmpty = T:Text(marked, 12, C.muted, "CENTER")
    p.markedEmpty:SetPoint("TOP", msf, "TOP", 0, -30)
    p.markedEmpty:SetWidth(CW - 60)
    p.markedEmpty:SetText("Noch keine Council-Items.\nIn „Raids durchsuchen“ einfach das Häkchen „Council“ beim Item setzen.")

    local clear = T:Button(marked, "Alle entfernen", 140, 32, "danger", function() StaticPopup_Show("LIGHTCOUNCIL_CLEAR_ITEMS") end)
    clear:SetPoint("BOTTOMRIGHT", 0, 0)
    StaticPopupDialogs["LIGHTCOUNCIL_CLEAR_ITEMS"] = {
        text = "Light Council: Alle Council-Items entfernen?",
        button1 = YES, button2 = NO,
        OnAccept = function()
            for id in pairs(LC.db.councilItems) do LC:SetCouncilItem(id, false) end
            LC:RefreshUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

local function GetBossButton(p, i)
    local b = bossButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, p.bossList)
    b:SetSize(BOSS_W - 14, 32)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetTexture(T.WHITE)
    b.bg:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetTexture(T.WHITE)
    b.bar:SetVertexColor(unpack(C.accent))
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.text = T:Text(b, 13, C.text)
    b.text:SetPoint("LEFT", 16, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetWordWrap(false)
    b.count = T:Text(b, 11, C.accentLt, "RIGHT")
    b.count:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self)
        p.bossIdx = self.index
        LC:RefreshUI()
    end)
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetVertexColor(0, 0, 0, 0) end end)
    bossButtons[i] = b
    return b
end

local function RefreshBrowse(p)
    local raids, err = LC:GetLootDB()
    if raids and #raids == 0 then
        raids, err = nil, "Die gewählte Quelle enthält keine Raids."
    end
    p.dbError:SetShown(raids == nil)
    p.bossCol:SetShown(raids ~= nil)
    p.itemScroll:SetShown(raids ~= nil)
    if p.itemScroll.bar and raids == nil then p.itemScroll.bar:Hide() end
    if not raids then
        p.itemsEmpty:Hide()
        p.chips:SetItems({}, nil, nil)
        p.dbError.text:SetText(H.warn .. (err or "Keine Loot-Quelle gefunden.") .. "|r\n\n"
            .. "Oben rechts unter „Quelle“ eine andere Quelle wählen – oder Council-Items unter „Council-Items“ per Shift-Klick bzw. Item-ID hinzufügen.")
        return
    end
    p.raidIdx = math.min(p.raidIdx or 1, #raids)
    local labels = {}
    for i, r in ipairs(raids) do
        labels[i] = r.name .. (((r.itemCount or 0) == 0) and ("  " .. H.muted .. "(Loot folgt)|r") or "")
    end
    p.chips:SetItems(labels, p.raidIdx, function(i)
        p.raidIdx, p.bossIdx = i, 1
        LC:RefreshUI()
    end)

    local raid = raids[p.raidIdx]
    p.bossIdx = math.min(p.bossIdx or 1, #raid.bosses)
    for i = 1, math.max(#raid.bosses, #bossButtons) do
        local boss = raid.bosses[i]
        if boss then
            local b = GetBossButton(p, i)
            b.index = i
            b.selected = (i == p.bossIdx)
            b.text:SetText(boss.name)
            local n = 0
            for _, id in ipairs(boss.items) do
                if LC:IsCouncilItem(id) then n = n + 1 end
            end
            b.count:SetText(n > 0 and tostring(n) or "")
            b.bar:SetShown(b.selected)
            b.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], b.selected and 0.16 or 0)
            local tc = b.selected and C.text or C.muted
            b.text:SetTextColor(tc[1], tc[2], tc[3])
            b:Show()
        elseif bossButtons[i] then
            bossButtons[i]:Hide()
        end
    end
    p.bossList:SetHeight(math.max(1, #raid.bosses * 32))

    local boss = raid.bosses[p.bossIdx]
    local items = boss and boss.items or {}
    for i = 1, math.max(#items, #browseRows) do
        local id = items[i]
        local r = browseRows[i]
        if id then
            if not r then
                r = CreateItemRow(p.itemList, p.itemsW, false)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
                browseRows[i] = r
            end
            FillItemRow(r, id, LC:GetDropChance(boss, id))
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    p.itemList:SetHeight(math.max(1, #items * ITEM_ROW))
    p.itemsEmpty:SetShown(#items == 0)
end

local function RefreshMarked(p)
    local list = LC:GetCouncilItemList()
    p.markedEmpty:SetShown(#list == 0)
    for i = 1, math.max(#list, #markedRows) do
        local it = list[i]
        local r = markedRows[i]
        if it then
            if not r then
                r = CreateItemRow(p.markedList, CW - 12, true)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
                markedRows[i] = r
            end
            FillItemRow(r, it.id)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    p.markedList:SetHeight(math.max(1, #list * ITEM_ROW))
end

local function RefreshItems()
    local p = pages.items
    p.seg:Set(p.mode)
    p.sourceBtn:Update()
    local n = 0
    for _ in pairs(LC.db.councilItems) do n = n + 1 end
    p.seg.buttons.marked:SetText("Council-Items (" .. n .. ")")
    p.browse:SetShown(p.mode == "browse")
    p.marked:SetShown(p.mode == "marked")
    if p.mode == "browse" then RefreshBrowse(p) else RefreshMarked(p) end
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
            out[#out + 1] = { key = key, name = (key == "custom") and "Raid (ohne Loot-Quelle)" or key, bosses = {}, itemCount = 0 }
            known[key] = true
        end
    end
    if #out == 0 then out[1] = { key = "custom", name = "Raid (ohne Loot-Quelle)", bosses = {}, itemCount = 0 } end
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
    return (#t > 0) and table.concat(t, "    ") or (H.muted .. "–|r")
end

------------------------------------------------------------------------
-- Seite: Meine Reservierung (für alle Raider)
------------------------------------------------------------------------
local myBossButtons, myItemRows = {}, {}

local function CreateMyResPage(p)
    local y, _, desc = PageHeader(p, "Meine Reservierung", "Wähle bis zu " .. LC:MaxReserves() .. " Items pro Raid. Nach dem Speichern ist deine Wahl gesperrt – Änderungen nur mit Freigabe des Councils.")
    p.desc = desc
    p.sel = {}

    p.sourceBtn = SourceButton(p)
    p.sourceBtn:SetPoint("TOPRIGHT", 0, 0)

    p.chipBar = ChipBar(p)
    p.chipBar:SetPoint("TOPLEFT", 0, -y)

    -- Statuskarte
    local st = Card(p, 96)
    st:SetPoint("TOPLEFT", p.chipBar, "BOTTOMLEFT", 0, -14)
    st:SetWidth(CW)
    p.stStripe = st:CreateTexture(nil, "ARTWORK")
    p.stStripe:SetTexture(T.WHITE)
    p.stStripe:SetPoint("TOPLEFT", 1, -1)
    p.stStripe:SetPoint("BOTTOMLEFT", 1, 1)
    p.stStripe:SetWidth(3)
    p.stTitle = T:Text(st, 14, C.text, "LEFT", nil, true)
    p.stTitle:SetPoint("TOPLEFT", 16, -14)
    p.stState = T:Text(st, 12, C.accentLt, "RIGHT", nil, true)
    p.stState:SetPoint("TOPRIGHT", -16, -14)
    p.stItems = T:Text(st, 13, C.text)
    p.stItems:SetPoint("TOPLEFT", p.stTitle, "BOTTOMLEFT", 0, -10)
    p.stItems:SetWidth(CW - 32)
    p.stItems:SetWordWrap(false)
    p.stPending = T:Text(st, 12, C.muted)
    p.stPending:SetPoint("TOPLEFT", p.stItems, "BOTTOMLEFT", 0, -8)
    p.stPending:SetWidth(CW - 32)
    p.stPending:SetWordWrap(false)
    p.statusCard = st

    -- Bosse + Items
    local bossCol = Card(p)
    bossCol:SetPoint("TOPLEFT", st, "BOTTOMLEFT", 0, -14)
    bossCol:SetPoint("BOTTOMLEFT", 0, 58)
    bossCol:SetWidth(BOSS_W)
    T:Skin(bossCol, C.bgDark)
    local bt = T:Text(bossCol, 12, C.text, "LEFT", nil, true)
    bt:SetPoint("TOPLEFT", 16, -14)
    bt:SetText("Bosse")
    local bsf, bcontent = T:Scroll(bossCol)
    bsf:SetPoint("TOPLEFT", 0, -40)
    bsf:SetPoint("BOTTOMRIGHT", -12, 8)
    p.bossCol, p.bossList = bossCol, bcontent

    local isf, icontent = T:Scroll(p)
    isf:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    isf:SetPoint("BOTTOMRIGHT", -10, 58)
    p.itemScroll, p.itemList = isf, icontent
    p.itemsW = CW - BOSS_W - 14 - 12

    -- Ohne AtlasLoot / ohne Loot: manuell per Shift-Klick oder ID
    p.manual = Card(p, 150)
    p.manual:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    p.manual:SetWidth(p.itemsW)
    p.manualText = T:Text(p.manual, 12, C.muted)
    p.manualText:SetPoint("TOPLEFT", 18, -16)
    p.manualText:SetWidth(p.itemsW - 36)
    p.manualText:SetSpacing(3)
    p.manualInput = T:Input(p.manual, p.itemsW - 170, 30)
    p.manualInput:SetPoint("BOTTOMLEFT", 18, 18)
    p.manualInput:SetPlaceholder("Shift-Klick auf ein Item oder Item-ID")
    AcceptLinks(p.manualInput)
    local addBtn = T:Button(p.manual, "Auswählen", 120, 30, "default", function()
        local raid = p.raid
        if not raid then return end
        local sel = p.sel[raid.key]
        for _, id in ipairs(IdsFromText(p.manualInput:GetText())) do
            if #sel < LC:MaxReserves() then
                local dup = false
                for _, s in ipairs(sel) do if s == id then dup = true end end
                if not dup then sel[#sel + 1] = id end
            end
        end
        p.manualInput:SetText("")
        LC:RefreshUI()
    end)
    addBtn:SetPoint("LEFT", p.manualInput, "RIGHT", 10, 0)

    -- Fußleiste: Auswahl, Begründung, Aktion
    p.counter = T:Text(p, 13, C.text, "LEFT", nil, true)
    p.counter:SetPoint("BOTTOMLEFT", 0, 16)
    p.reason = T:Input(p, CW - 520, 32)
    p.reason:SetPoint("BOTTOMLEFT", 190, 8)
    p.reason:SetPlaceholder("Begründung für die Änderung (Pflicht)")
    p.reason:SetMaxLetters(120)
    p.clearSel = T:Button(p, "Auswahl leeren", 130, 34, "ghost", function()
        if p.raid then wipe(p.sel[p.raid.key]) end
        LC:RefreshUI()
    end)
    p.action = T:Button(p, "Reservierung speichern", 190, 34, "primary", function()
        local raid = p.raid
        if not raid then return end
        local items = p.sel[raid.key]
        local rec = LC:GetReservation(raid.key)
        if rec and (rec.rev or 0) > 0 then
            local ok, msg = LC:RequestReservationChange(raid.key, items, p.reason:GetText())
            p.msgText = (ok and H.good or H.bad) .. msg .. "|r"
            if ok then p.reason:SetText("") end
            LC:RefreshUI()
        else
            local dlg = StaticPopup_Show("LIGHTCOUNCIL_CONFIRM_RESERVE", LC:ItemListText(items))
            if dlg then dlg.data = { raid = raid.key, items = { unpack(items) } } end
        end
    end)
    p.action:SetPoint("BOTTOMRIGHT", 0, 8)
    p.clearSel:SetPoint("RIGHT", p.action, "LEFT", -8, 0)
    p.msg = T:Text(p, 12, C.muted, "RIGHT")
    p.msg:SetPoint("BOTTOMRIGHT", p.action, "TOPRIGHT", 0, 8)
    p.msg:SetWidth(CW)
    p.msg:SetWordWrap(false)

    StaticPopupDialogs["LIGHTCOUNCIL_CONFIRM_RESERVE"] = {
        text = "Light Council: Diese Items reservieren?\n\n%s\n\nDanach ist deine Reservierung gesperrt. Änderungen gehen nur noch mit Freigabe des Councils.",
        button1 = "Reservieren", button2 = CANCEL,
        OnAccept = function(self, data)
            local ok, msg = LC:SubmitReservation(data.raid, data.items)
            pages.myres.msgText = (ok and H.good or H.bad) .. msg .. "|r"
            LC:RefreshUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

local function GetMyBossButton(p, i)
    local b = myBossButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, p.bossList)
    b:SetSize(BOSS_W - 14, 32)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetTexture(T.WHITE)
    b.bg:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetTexture(T.WHITE)
    b.bar:SetVertexColor(unpack(C.accent))
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.text = T:Text(b, 13, C.text)
    b.text:SetPoint("LEFT", 16, 0)
    b.text:SetPoint("RIGHT", -30, 0)
    b.text:SetWordWrap(false)
    b.count = T:Text(b, 11, C.accentLt, "RIGHT")
    b.count:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self) p.bossIdx = self.index LC:RefreshUI() end)
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetVertexColor(0, 0, 0, 0) end end)
    myBossButtons[i] = b
    return b
end

local function GetMyItemRow(p, i)
    local r = myItemRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, p.itemList, "BackdropTemplate")
    r:SetSize(p.itemsW, ITEM_ROW - 6)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
    T:Skin(r, C.panel)
    r.icon = T:Icon(r, 34)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.name:SetPoint("TOPLEFT", 50, -6)
    r.name:SetWidth(p.itemsW - 210)
    r.name:SetWordWrap(false)
    r.sub = T:Text(r, 11, C.muted)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetWidth(p.itemsW - 210)
    r.sub:SetWordWrap(false)
    r.check = T:Check(r, "Reservieren")
    r.check:SetPoint("RIGHT", -110, 0)
    r.check:SetScript("OnClick", function(self)
        local sel = p.sel[p.raid.key]
        if self:GetChecked() then
            if #sel >= LC:MaxReserves() then
                self:SetChecked(false)
                p.msgText = H.warn .. "Du kannst höchstens " .. LC:MaxReserves() .. " Items pro Raid reservieren.|r"
            else
                sel[#sel + 1] = r.itemID
            end
        else
            for k, id in ipairs(sel) do if id == r.itemID then table.remove(sel, k) break end end
        end
        LC:RefreshUI()
    end)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.panelAlt[1], C.panelAlt[2], C.panelAlt[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1)
        GameTooltip:Hide()
    end)
    myItemRows[i] = r
    return r
end

local function RefreshMyRes()
    local p = pages.myres
    local max = LC:MaxReserves()
    p.desc:SetText("Wähle bis zu " .. max .. " Items pro Raid. Nach dem Speichern ist deine Wahl gesperrt – Änderungen nur mit Freigabe des Councils.")

    p.sourceBtn:Update()
    local raids, hasDB = ReserveRaids()
    -- Im Raid: automatisch diesen Raid auswählen (einmal pro Raid, danach entscheidet der Spieler)
    local current = LC:GetCurrentRaid()
    if current and p.autoRaid ~= current.key then
        p.autoRaid = current.key
        for i, r in ipairs(raids) do
            if r.key == current.key then p.raidIdx, p.bossIdx = i, 1 break end
        end
    end
    -- Aus der Raidtag-Erinnerung geöffnet: diesen Raid auswählen
    if LC.wantRaid then
        for i, r in ipairs(raids) do
            if r.key == LC.wantRaid then p.raidIdx, p.bossIdx = i, 1 break end
        end
        LC.wantRaid = nil
    end
    p.raidIdx = math.min(p.raidIdx or 1, #raids)
    local labels = {}
    for i, r in ipairs(raids) do
        local mine = LC:GetReservation(r.key)
        local tag = ""
        if mine and #(mine.items or {}) > 0 then tag = "  |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" end
        labels[i] = r.name .. tag
    end
    p.chipBar:SetItems(labels, p.raidIdx, function(i) p.raidIdx, p.bossIdx = i, 1 LC:RefreshUI() end)
    local raid = raids[p.raidIdx]
    p.raid = raid

    -- eigene Reservierung + Auswahl
    local rec = LC:GetReservation(raid.key)
    local locked = rec and (rec.rev or 0) > 0
    if not p.sel[raid.key] then
        local init = (rec and rec.pending and rec.pending.items) or (rec and rec.items) or {}
        p.sel[raid.key] = { unpack(init) }
    end
    local sel = p.sel[raid.key]
    local selSet = {}
    for _, id in ipairs(sel) do selSet[id] = true end

    p.stTitle:SetText("Deine Reservierung  ·  " .. raid.name)
    if locked then
        p.stState:SetText("GESPERRT")
        p.stState:SetTextColor(unpack(C.good))
        p.stStripe:SetVertexColor(unpack(C.good))
    elseif rec and #(rec.items or {}) > 0 then
        p.stState:SetText("WARTET AUF BESTÄTIGUNG")
        p.stState:SetTextColor(unpack(C.warn))
        p.stStripe:SetVertexColor(unpack(C.warn))
    else
        p.stState:SetText("NOCH NICHTS RESERVIERT")
        p.stState:SetTextColor(unpack(C.muted))
        p.stStripe:SetVertexColor(unpack(C.accent))
    end
    p.stItems:SetText(ItemIcons(rec and rec.items, 18))
    if rec and rec.pending then
        p.stPending:SetText(H.warn .. "Änderung beantragt:|r " .. LC:ItemListText(rec.pending.items) .. H.muted .. "  – wartet auf den Council|r")
    elseif locked then
        p.stPending:SetText("Ändern: andere Items anhaken, Begründung eintragen und „Änderung beantragen“ klicken.")
    else
        p.stPending:SetText("Items unten anhaken und „Reservierung speichern“ klicken.")
    end

    -- Bosse
    local bosses = raid.bosses or {}
    local showList = hasDB and #bosses > 0
    p.bossCol:SetShown(showList)
    p.itemScroll:SetShown(showList)
    if not showList and p.itemScroll.bar then p.itemScroll.bar:Hide() end
    p.bossIdx = math.min(p.bossIdx or 1, math.max(1, #bosses))
    for i = 1, math.max(#bosses, #myBossButtons) do
        local boss = bosses[i]
        if boss and showList then
            local b = GetMyBossButton(p, i)
            b.index = i
            b.selected = (i == p.bossIdx)
            b.text:SetText(boss.name)
            local n = 0
            for _, id in ipairs(boss.items) do if selSet[id] then n = n + 1 end end
            b.count:SetText(n > 0 and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" or "")
            b.bar:SetShown(b.selected)
            b.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], b.selected and 0.16 or 0)
            local tc = b.selected and C.text or C.muted
            b.text:SetTextColor(tc[1], tc[2], tc[3])
            b:Show()
        elseif myBossButtons[i] then
            myBossButtons[i]:Hide()
        end
    end
    p.bossList:SetHeight(math.max(1, #bosses * 32))

    local boss = bosses[p.bossIdx]
    local items = (showList and boss and boss.items) or {}
    local full = #sel >= max
    for i = 1, math.max(#items, #myItemRows) do
        local id = items[i]
        if id then
            local r = GetMyItemRow(p, i)
            r.itemID = id
            r.icon.tex:SetTexture(LC:ItemIcon(id))
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local _, _, quality = getInfo(id)
            local qc = T:QualityColor(quality)
            r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            r.name:SetText(LC:ItemLink(id))
            local n = #LC:GetReservers(id)
            local sub = (n > 0) and (n .. (n == 1 and " Reservierung" or " Reservierungen")) or "Noch nicht reserviert"
            local chance = LC:GetDropChance(boss, id)
            if chance then sub = H.good .. chance .. " %|r Drop   ·   " .. sub end
            if LC:IsCouncilItem(id) then sub = sub .. "   ·   " .. H.accent .. "Council-Item|r" end
            local prio = LC:GetPrio(id)
            if prio and #prio > 0 then sub = sub .. "   ·   " .. H.accentLt .. "Prio:|r " .. table.concat(prio, " > ") end
            r.sub:SetText(sub)
            r.check:SetChecked(selSet[id] == true)
            r.check:SetEnabled(selSet[id] == true or not full)
            r:Show()
        elseif myItemRows[i] then
            myItemRows[i]:Hide()
        end
    end
    p.itemList:SetHeight(math.max(1, #items * ITEM_ROW))

    -- Manuelle Auswahl, wenn es keine Liste gibt
    p.manual:SetShown(not showList)
    if not showList then
        if not hasDB then
            p.manualText:SetText("Die gewählte Loot-Quelle liefert hier keine Itemliste. Oben rechts unter „Quelle“ wechseln oder AtlasLoot bzw. Naowh Forever installieren.\nAlternativ: Items per Shift-Klick (z. B. aus dem Chat) oder per Item-ID zu deiner Auswahl hinzufügen.")
        else
            p.manualText:SetText("Für diese Instanz ist in der Loot-Quelle noch kein Loot eingetragen (Loot folgt).\nFüge Items per Shift-Klick oder Item-ID zu deiner Auswahl hinzu.")
        end
    end

    -- Fußleiste
    local changed = not (rec and LC.SameItems(rec.items or {}, sel))
    p.counter:SetText("Ausgewählt: " .. (full and H.accentLt or "") .. #sel .. " von " .. max .. (full and "|r" or ""))
    p.reason:SetShown(locked and changed and not (rec and rec.pending))
    if locked then
        p.action:SetText("Änderung beantragen")
        p.action:SetEnabled(changed and #sel > 0 and not rec.pending)
    else
        p.action:SetText("Reservierung speichern")
        p.action:SetEnabled(#sel > 0 and changed)
    end
    p.msg:SetText(p.msgText or "")
end

------------------------------------------------------------------------
-- Seite: Reservierungen (Übersicht und Verwaltung durch den Council)
------------------------------------------------------------------------
local resRows, pendRows = {}, {}

-- Fenster: Raidtage und Erinnerung einstellen (Council)
local daysFrame
local function ShowRaidDaysFrame()
    if not daysFrame then
        local FW = CW + 32
        local f = T:Window("LightCouncilRaidDaysFrame", FW, 330, "Raidtage & Erinnerung",
            "An Raidtagen werden alle mit Light Council beim Einloggen ans Reservieren erinnert")
        f:SetFrameStrata("DIALOG")
        f.sel = {}

        local l1 = T:Text(f, 13, C.text, "LEFT", nil, true)
        l1:SetPoint("TOPLEFT", 16, -54)
        l1:SetText("An welchen Tagen raidet ihr?")
        f.dayBtns = {}
        local prev
        for _, w in ipairs(LC.WEEKDAYS) do
            local b = T:Button(f, w.short, 64, 34, "default", function(self)
                f.sel[w.wday] = not f.sel[w.wday] or nil
                f:Paint()
            end)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -82) end
            b.tooltipTitle = w.long
            b.tooltip = "Anklicken zum Ein- oder Ausschalten."
            b.wday = w.wday
            f.dayBtns[#f.dayBtns + 1] = b
            prev = b
        end

        local l2 = T:Text(f, 13, C.text, "LEFT", nil, true)
        l2:SetPoint("TOPLEFT", 16, -136)
        l2:SetText("Für welchen Raid sollen sie reservieren?")
        local l2d = T:Text(f, 11, C.muted)
        l2d:SetPoint("LEFT", l2, "RIGHT", 10, -1)
        l2d:SetText("„Jeder Raid“: Erinnerung, solange jemand gar nichts reserviert hat.")
        f.chips = ChipBar(f)
        f.chips:SetPoint("TOPLEFT", 16, -162)

        f.msg = T:Text(f, 12, C.muted)
        f.msg:SetPoint("BOTTOMLEFT", 160, 26)
        f.msg:SetWidth(FW - 180)
        f.msg:SetWordWrap(false)
        local save = T:Button(f, "Speichern", 130, 34, "primary", function()
            local days = {}
            for _, w in ipairs(LC.WEEKDAYS) do
                if f.sel[w.wday] then days[#days + 1] = w.wday end
            end
            LC:SetRaidDays(days, f.raidKey)
            f.msg:SetText(H.good .. "Gespeichert und an alle Addon-Nutzer in Gilde/Raid geschickt.|r")
        end)
        save:SetPoint("BOTTOMLEFT", 16, 16)

        function f:Paint()
            for _, b in ipairs(self.dayBtns) do
                b.selected = self.sel[b.wday] and true or nil   -- Hover übermalt die Auswahl nicht
                if b.selected then
                    b:SetBackdropColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
                    T:SetBorder(b, C.accent)
                else
                    b.Paint(false)
                end
            end
            local raids = LC:GetLootDB() or {}
            local labels, keys, selected = { "Jeder Raid" }, { "" }, 1
            for _, r in ipairs(raids) do
                labels[#labels + 1] = r.name
                keys[#keys + 1] = r.key
                if r.key == self.raidKey then selected = #keys end
            end
            self.chips:SetItems(labels, selected, function(i)
                self.raidKey = keys[i]
                self:Paint()
            end)
        end
        daysFrame = f
    end
    local f = daysFrame
    wipe(f.sel)
    for _, d in ipairs(LC.db.config.raidDays or {}) do f.sel[d] = true end
    f.raidKey = LC.db.config.reminderRaid or ""
    f.msg:SetText("")
    f:Paint()
    f:Show()
end

-- Erinnerung am Raidtag (für alle)
local reminder
function LC:ShowRaidDayReminder(raidKey)
    if not reminder then
        local f = T:Window("LightCouncilReminderFrame", 440, 190, "Heute ist Raidtag!", "Light Council")
        f:ClearAllPoints()
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
        f:SetFrameStrata("DIALOG")
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetTexture(T.LOGO)
        logo:SetSize(56, 56)
        logo:SetPoint("TOPLEFT", 16, -50)
        f.text = T:Text(f, 13, C.text)
        f.text:SetPoint("TOPLEFT", 86, -54)
        f.text:SetWidth(440 - 86 - 16)
        f.text:SetSpacing(3)
        f.go = T:Button(f, "Jetzt reservieren", 160, 32, "primary", function()
            f:Hide()
            LC:OpenReservation(f.raidKey)
        end)
        f.go:SetPoint("BOTTOMRIGHT", -16, 16)
        local later = T:Button(f, "Später", 100, 32, "ghost", function() f:Hide() end)
        later:SetPoint("RIGHT", f.go, "LEFT", -8, 0)
        reminder = f
    end
    local f = reminder
    f.raidKey = raidKey
    local raidName
    if raidKey and raidKey ~= "" then
        for _, r in ipairs(self:GetLootDB() or {}) do
            if r.key == raidKey then raidName = r.name break end
        end
        raidName = raidName or raidKey
    end
    f.text:SetText((raidName and ("Du hast für " .. H.accentLt .. raidName .. "|r noch nichts reserviert.")
        or "Du hast noch keine Items reserviert.")
        .. "\n" .. H.muted .. "Reservier am besten schon jetzt – im Raid wird dann nur noch eingesammelt.|r")
    f:Show()
    if SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
end

local function CreateReservesPage(p)
    local y, ht, hd = PageHeader(p, "Reservierungen", "Alle Reservierungen im Überblick. Der Council bestätigt automatisch, entscheidet über Änderungsanträge und trägt für Spieler ohne Addon ein.")
    -- Beschreibung schmaler, damit die drei Knöpfe oben rechts nicht überlappen
    hd:SetWidth(CW - 420)
    y = math.ceil(ht:GetStringHeight() + 5 + hd:GetStringHeight() + 16)

    p.btnRound = T:Button(p, "Neue Runde", 130, 30, "danger", function()
        if p.raid then
            local dlg = StaticPopup_Show("LIGHTCOUNCIL_NEW_ROUND", p.raid.name)
            if dlg then dlg.data = p.raid.key end
        end
    end)
    p.btnRound:SetPoint("TOPRIGHT", 0, 0)
    p.btnRound.tooltipTitle = "Neue Runde"
    p.btnRound.tooltip = "Löscht alle Reservierungen dieses Raids, z. B. für eine neue Raid-ID. Alle können danach neu reservieren."
    p.btnSync = T:Button(p, "Abgleichen", 120, 30, "default", function()
        LC:RequestResSync(true)
        p.msg:SetText("Abgleich angefordert …")
    end)
    p.btnSync:SetPoint("RIGHT", p.btnRound, "LEFT", -8, 0)
    p.btnSync.tooltipTitle = "Abgleichen"
    p.btnSync.tooltip = "Holt den aktuellen Stand der Reservierungen von den Council-Mitgliedern, die gerade online sind."
    p.btnDays = T:Button(p, "Raidtage", 140, 30, "default", function() ShowRaidDaysFrame() end)
    p.btnDays:SetPoint("RIGHT", p.btnSync, "LEFT", -8, 0)
    p.btnDays.tooltipTitle = "Raidtage & Erinnerung"
    p.btnDays.tooltip = "Lege eure Raidtage fest. An diesen Tagen erinnert das Addon alle beim Einloggen, schon vorab zu reservieren."
    StaticPopupDialogs["LIGHTCOUNCIL_NEW_ROUND"] = {
        text = "Light Council: Neue Runde für %s starten?\n\nAlle Reservierungen dieses Raids werden gelöscht.",
        button1 = YES, button2 = NO,
        OnAccept = function(self, raidKey)
            local ok, msg = LC:NewReserveRound(raidKey)
            pages.reserves.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    p.chipBar = ChipBar(p)
    p.chipBar:SetPoint("TOPLEFT", 0, -y)

    -- Offene Änderungsanträge
    p.pendCard = Card(p, 60)
    p.pendCard:SetPoint("TOPLEFT", p.chipBar, "BOTTOMLEFT", 0, -14)
    p.pendCard:SetWidth(CW)
    local pt = T:Text(p.pendCard, 14, C.text, "LEFT", nil, true)
    pt:SetPoint("TOPLEFT", 16, -14)
    pt:SetText("Offene Änderungsanträge")
    p.pendInfo = T:Text(p.pendCard, 12, C.muted, "RIGHT")
    p.pendInfo:SetPoint("TOPRIGHT", -16, -15)

    -- Tabelle
    p.tableHead = CreateFrame("Frame", nil, p)
    p.tableHead:SetSize(CW, 20)
    for i, label in ipairs({ "SPIELER", "RESERVIERT", "STATUS" }) do
        local t = T:Text(p.tableHead, 10, C.muted)
        t:SetPoint("LEFT", ({ 10, 220, CW - 240 })[i], 0)
        t:SetText(label)
    end
    local sf, content = T:Scroll(p)
    sf:SetPoint("TOPLEFT", p.tableHead, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", -10, 96)
    p.list = content
    p.empty = T:Text(p, 12, C.muted, "CENTER")
    p.empty:SetPoint("TOP", sf, "TOP", 0, -24)
    p.empty:SetWidth(CW - 60)

    -- Für Spieler eintragen (Council)
    local man = Card(p, 84)
    man:SetPoint("BOTTOMLEFT", 0, 0)
    man:SetWidth(CW)
    p.manCard = man
    local mt = T:Text(man, 12, C.text, "LEFT", nil, true)
    mt:SetPoint("TOPLEFT", 16, -12)
    mt:SetText("Für Spieler eintragen oder ändern (Council)")
    p.msg = T:Text(man, 12, C.muted, "RIGHT")
    p.msg:SetPoint("TOPRIGHT", -16, -13)
    p.msg:SetWidth(CW - 360)
    p.msg:SetWordWrap(false)
    p.manName = T:Input(man, 220, 30)
    p.manName:SetPoint("BOTTOMLEFT", 16, 14)
    p.manName:SetPlaceholder("Vorname Nachname")
    p.manItems = T:Input(man, CW - 400, 30)
    p.manItems:SetPoint("LEFT", p.manName, "RIGHT", 8, 0)
    p.manItems:SetPlaceholder("Items per Shift-Klick oder IDs – leer = löschen")
    AcceptLinks(p.manItems)
    p.manBtn = T:Button(man, "Eintragen", 130, 30, "primary", function()
        local raid = p.raid
        if not raid then return end
        local ids = IdsFromText(p.manItems:GetText())
        local ok, msg = LC:CouncilSetReservation(raid.key, p.manName:GetText(), ids)
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        if ok then p.manName:SetText("") p.manItems:SetText("") end
    end)
    p.manBtn:SetPoint("LEFT", p.manItems, "RIGHT", 8, 0)
end

local function GetPendRow(p, i)
    local r = pendRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, p.pendCard, "BackdropTemplate")
    r:SetSize(CW - 24, 40)
    T:Skin(r, C.bgDark, { 0, 0, 0, 0 })
    r.text = T:Text(r, 12, C.text)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -250, 0)
    r.text:SetWordWrap(false)
    r.no = T:Button(r, "Ablehnen", 110, 28, "danger", function()
        local ok, msg = LC:DecideChange(p.raid.key, r.player, false)
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
    end)
    r.no:SetPoint("RIGHT", -8, 0)
    r.yes = T:Button(r, "Freigeben", 110, 28, "primary", function()
        local ok, msg = LC:DecideChange(p.raid.key, r.player, true)
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
    end)
    r.yes:SetPoint("RIGHT", r.no, "LEFT", -6, 0)
    pendRows[i] = r
    return r
end

local function GetResRow(p, i)
    local r = resRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, p.list, "BackdropTemplate")
    r:SetSize(CW - 12, 34)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
    T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
    r.name = T:Text(r, 12, C.text, "LEFT", nil, true)
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetWidth(200)
    r.name:SetWordWrap(false)
    r.items = T:Text(r, 12, C.text)
    r.items:SetPoint("LEFT", 220, 0)
    r.items:SetWidth(CW - 480)
    r.items:SetWordWrap(false)
    r.state = T:Text(r, 11, C.muted)
    r.state:SetPoint("LEFT", CW - 240, 0)
    r.state:SetWidth(140)
    r.state:SetWordWrap(false)
    r.edit = T:Button(r, "Bearbeiten", 100, 26, "ghost", function()
        p.manName:SetText(r.player)
        local links = {}
        for _, id in ipairs(r.itemIDs or {}) do links[#links + 1] = LC:ItemLink(id) end
        p.manItems:SetText(table.concat(links, " "))
        p.manItems:SetFocus()
    end)
    r.edit:SetPoint("RIGHT", -6, 0)
    resRows[i] = r
    return r
end

local function RefreshReserves()
    local p = pages.reserves
    local isCouncil = LC:AmICouncil()
    local raids = ReserveRaids()
    p.raidIdx = math.min(p.raidIdx or 1, #raids)
    local labels = {}
    for i, r in ipairs(raids) do
        local n = 0
        local R = LC.db.reserves and LC.db.reserves[r.key]
        if R then for _ in pairs(R.players) do n = n + 1 end end
        labels[i] = r.name .. (n > 0 and ("  " .. H.accentLt .. n .. "|r") or "")
    end
    p.chipBar:SetItems(labels, p.raidIdx, function(i) p.raidIdx = i LC:RefreshUI() end)
    local raid = raids[p.raidIdx]
    p.raid = raid
    local R = (LC.db.reserves or {})[raid.key] or { players = {} }

    -- Liste der Spieler (sortiert)
    local list, pend = {}, {}
    for _, rec in pairs(R.players) do
        list[#list + 1] = rec
        if rec.pending then pend[#pend + 1] = rec end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(pend, function(a, b) return (a.pending.time or 0) < (b.pending.time or 0) end)

    -- Anträge
    p.pendCard:SetShown(#pend > 0)
    for i = 1, math.max(#pend, #pendRows) do
        local rec = pend[i]
        if rec then
            local r = GetPendRow(p, i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 44)
            r.player = rec.name
            r.text:SetText(H.accentLt .. rec.name .. "|r:  " .. LC:ItemListText(rec.items) .. "  →  " .. LC:ItemListText(rec.pending.items)
                .. "   " .. H.muted .. "„" .. (rec.pending.reason or "") .. "“|r")
            local own = LC:IsMe(rec.name)
            r.yes:SetEnabled(isCouncil and not own)
            r.no:SetEnabled(isCouncil and not own)
            r:Show()
        elseif pendRows[i] then
            pendRows[i]:Hide()
        end
    end
    p.pendCard:SetHeight(40 + #pend * 44 + 4)
    p.pendInfo:SetText(isCouncil and (#pend .. " offen") or "nur der Council entscheidet")
    p.tableHead:ClearAllPoints()
    if #pend > 0 then
        p.tableHead:SetPoint("TOPLEFT", p.pendCard, "BOTTOMLEFT", 0, -14)
    else
        p.tableHead:SetPoint("TOPLEFT", p.chipBar, "BOTTOMLEFT", 0, -14)
    end

    -- Tabelle
    for i = 1, math.max(#list, #resRows) do
        local rec = list[i]
        if rec then
            local r = GetResRow(p, i)
            r.player, r.itemIDs = rec.name, rec.items
            r.name:SetText(rec.name)
            r.items:SetText(ItemIcons(rec.items, 16))
            if rec.pending then
                r.state:SetText(H.warn .. "Antrag offen|r")
            elseif (rec.rev or 0) > 0 then
                r.state:SetText(H.good .. "gesperrt|r" .. ((rec.rev or 0) > 1 and (H.muted .. "  (" .. (rec.rev - 1) .. "× geändert)|r") or ""))
            else
                r.state:SetText(H.warn .. "wartet|r")
            end
            r.edit:SetShown(isCouncil)
            r:Show()
        elseif resRows[i] then
            resRows[i]:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #list * 34))
    p.empty:SetShown(#list == 0)
    p.empty:SetText("Noch keine Reservierungen für " .. raid.name .. ".\nRaider reservieren im Addon unter „Meine Reservierung“.")

    p.manCard:SetShown(isCouncil)
    p.btnRound:SetEnabled(isCouncil)
    p.btnDays:SetEnabled(isCouncil)
    local nDays = #(LC:GetRaidDays())
    p.btnDays:SetText((nDays > 3) and ("Raidtage: " .. nDays .. " Tage") or ("Raidtage: " .. LC:RaidDaysText()))
end

------------------------------------------------------------------------
-- Seite: Spieler
------------------------------------------------------------------------
local playerRows = {}
local P_ROW = 26
local COLS = { 0, 200, 300, 370, 470, 560, 650 }   -- Name, Anw., Parse, Eng., Score, Items, Status

local function CreatePlayersPage(p)
    local y = PageHeader(p, "Spieler", "Score 0–100 aus Anwesenheit, Parse und Engagement. Nur Leitung und Council sehen ihn. Zeile anklicken zum Bearbeiten, Maus drüber zeigt die letzten Items.")

    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 0, -y)
    head:SetSize(CW, 18)
    for i, label in ipairs({ "NAME", "ANWESENHEIT", "PARSE", "ENGAGEMENT", "SCORE", "ITEMS", "STATUS" }) do
        local t = T:Text(head, 10, C.muted)
        t:SetPoint("LEFT", COLS[i] + 10, 0)
        t:SetText(label)
    end
    local line = T:Line(p, C.line)
    line:SetPoint("TOPLEFT", 0, -y - 20)
    line:SetWidth(CW)
    y = y + 24

    local sf, content = T:Scroll(p)
    sf:SetPoint("TOPLEFT", 0, -y)
    sf:SetPoint("BOTTOMRIGHT", -10, 74)
    p.list = content
    p.empty = T:Text(p, 11, C.muted, "CENTER")
    p.empty:SetPoint("TOP", sf, "TOP", 0, -30)
    p.empty:SetWidth(CW - 60)
    p.empty:SetText("Noch keine Spieler. Sie erscheinen, sobald sie reservieren oder nach dem ersten Boss-Kill.")

    local edit = Card(p, 62)
    edit:SetPoint("BOTTOMLEFT", 0, 0)
    edit:SetWidth(CW)
    local function Field(label, width, anchor)
        local l = T:Text(edit, 10, C.muted)
        l:SetText(label)
        local e = T:Input(edit, width, 24)
        if anchor then e:SetPoint("LEFT", anchor, "RIGHT", 10, 0) else e:SetPoint("BOTTOMLEFT", 10, 10) end
        l:SetPoint("BOTTOMLEFT", e, "TOPLEFT", 0, 4)
        return e
    end
    p.name = Field("NAME", 230)
    p.name:SetPlaceholder("Vor- und Nachname")
    p.parse = Field("Ø PARSE (0–100)", 90, p.name)
    p.parse:SetPlaceholder("z. B. 85")
    p.eng = Field("ENGAGEMENT (1–5)", 100, p.parse)
    p.eng:SetPlaceholder("1 bis 5")
    Tip(p.eng, "Engagement", "Gildenaktivität, Hilfsbereitschaft, Vorbereitung (Consumables) und Pünktlichkeit.")
    local save = T:Button(edit, "Speichern", 90, 24, "primary", function()
        local name = strtrim(p.name:GetText() or "")
        if name == "" then p.msg:SetText(H.bad .. "Bitte einen Namen eingeben.|r") return end
        local msgs = {}
        local pv, ev = strtrim(p.parse:GetText() or ""), strtrim(p.eng:GetText() or "")
        if pv ~= "" then
            local ok, err = LC:SetParse(name, pv, true)
            msgs[#msgs + 1] = ok and (H.good .. "Parse gespeichert|r") or (H.bad .. err .. "|r")
        end
        if ev ~= "" then
            local ok, err = LC:SetEngagement(name, ev, true)
            msgs[#msgs + 1] = ok and (H.good .. "Engagement gespeichert|r") or (H.bad .. err .. "|r")
        end
        if #msgs == 0 then msgs[1] = H.warn .. "Parse oder Engagement eintragen.|r" end
        p.msg:SetText(table.concat(msgs, "  ·  "))
        LC:RefreshUI()
    end)
    save:SetPoint("LEFT", p.eng, "RIGHT", 10, 0)
    -- Anwesenheit erfassen: oben rechts neben der Überschrift, damit nichts überlappt
    local att = T:Button(p, "Anwesenheit erfassen", 170, 26, "default", function()
        local n = LC:RecordAttendance(true)
        p.msg:SetText(n .. " Spieler für diese Woche erfasst.")
        LC:RefreshUI()
    end)
    att:SetPoint("TOPRIGHT", 0, 0)
    Tip(att, "Anwesenheit erfassen", "Markiert alle Online-Raidmitglieder für diese Woche als anwesend. Passiert bei jedem Boss-Kill automatisch.")
    p.msg = T:Text(edit, 11, C.muted, "LEFT")
    p.msg:SetPoint("LEFT", save, "RIGHT", 14, 0)
    p.msg:SetPoint("RIGHT", edit, "RIGHT", -10, 0)
    p.msg:SetWordWrap(false)
end

local function RefreshPlayers()
    local p = pages.players
    local names = LC:GetKnownPlayers()
    p.empty:SetShown(#names == 0)
    for i = 1, math.max(#names, #playerRows) do
        local name = names[i]
        local r = playerRows[i]
        if name then
            if not r then
                r = CreateFrame("Button", nil, p.list, "BackdropTemplate")
                r:SetSize(CW - 10, P_ROW)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * P_ROW)
                T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
                r.cols = {}
                for c = 1, 7 do
                    local fs = T:Text(r, 11, C.text)
                    fs:SetPoint("LEFT", COLS[c] + 10, 0)
                    fs:SetWordWrap(false)
                    fs:SetWidth(((COLS[c + 1] or (CW - 10)) - COLS[c]) - 14)
                    r.cols[c] = fs
                end
                r.scoreBar = T:Bar(r, 4)
                r.scoreBar:SetPoint("LEFT", COLS[5] + 40, 0)
                r.scoreBar:SetWidth(40)
                r.scoreBar.bar:SetMinMaxValues(0, 100)
                r:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.playerName, 1, 1, 1)
                    LC:AddLootTooltip(GameTooltip, self.playerName, 8)
                    GameTooltip:Show()
                end)
                r:SetScript("OnLeave", function(self)
                    local c = (self.index % 2 == 0) and C.panel or C.bg
                    self:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
                    GameTooltip_Hide()
                end)
                r:SetScript("OnClick", function(self)
                    local pl = LC:GetPlayer(self.playerName)
                    p.name:SetText(self.playerName)
                    p.parse:SetText(pl and pl.parse and tostring(pl.parse) or "")
                    p.eng:SetText(pl and pl.engagement and tostring(pl.engagement) or "")
                    p.parse:SetFocus()
                end)
                playerRows[i] = r
            end
            r.index = i
            r.playerName = name
            local score, att, parse, eng = LC:GetScore(name)
            local cd, untilWeek = LC:IsOnCooldown(name)
            local dash = H.muted .. "–|r"
            r.cols[1]:SetText(name)
            r.cols[2]:SetText(att and (att .. " %") or dash)
            r.cols[3]:SetText(parse and tostring(parse) or dash)
            r.cols[4]:SetText(eng and (eng .. " / 5") or dash)
            local sc = T:ScoreColor(score)
            r.cols[5]:SetText(score and tostring(score) or dash)
            r.cols[5]:SetTextColor(sc[1], sc[2], sc[3])
            r.scoreBar:SetShown(score ~= nil)
            r.scoreBar.bar:SetValue(score or 0)
            r.scoreBar.bar:SetStatusBarColor(sc[1], sc[2], sc[3])
            -- Items der letzten Wochen (gleicher Zeitraum wie die Anwesenheit)
            local loot, councilN = LC:GetPlayerLoot(name, LC.db.config.attendanceWeeks or 8)
            if #loot == 0 then
                r.cols[6]:SetText(dash)
            else
                r.cols[6]:SetText(#loot .. ((councilN > 0) and (H.accentLt .. "  (" .. councilN .. " C)|r") or ""))
            end
            if cd then
                local weeksLeft = untilWeek - LC:CurrentWeek()
                r.cols[7]:SetText(H.warn .. "Loot-CD|r " .. H.muted .. (weeksLeft == 0 and "diese Wo." or ("noch " .. weeksLeft .. " Wo.")) .. "|r")
            else
                r.cols[7]:SetText("")
            end
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #names * P_ROW))
end

------------------------------------------------------------------------
-- Seite: Loot-Historie (für alle)
------------------------------------------------------------------------
local HIST_ROW = 44
local HCOLS = { 0, 130, 450, 620 }   -- Datum/Raid, Item, Spieler, Vergabe
local historyRows = {}

local function CreateHistoryPage(p)
    local y = PageHeader(p, "Loot-Historie", "Wer hat wann welches Item bekommen. Jedes vergebene Item wird automatisch eingetragen – bei allen, die Light Council im Raid haben.")
    p.mode = "all"
    p.seg = Segmented(p, {
        { key = "all", label = "Alle", width = 90 },
        { key = "mine", label = "Meine Items", width = 130 },
    }, function(key)
        p.mode = key
        LC:RefreshUI()
    end)
    p.seg.first:SetPoint("TOPLEFT", 0, -y)
    p.search = T:Input(p, 250, 30)
    p.search:SetPoint("LEFT", p.seg.buttons.mine, "RIGHT", 14, 0)
    p.search:SetPlaceholder("Spieler, Item oder Raid suchen")
    p.search:HookScript("OnTextChanged", function() LC:RefreshUI() end)
    p.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    p.count = T:Text(p, 12, C.muted, "RIGHT")
    p.count:SetPoint("TOPRIGHT", 0, -6)

    local export = T:Button(p, "Exportieren", 120, 30, "default", function() LC:ShowHistoryExport(p.lastList or {}) end)
    export:SetPoint("TOPRIGHT", 0, -y)
    Tip(export, "Exportieren", "Die angezeigte Liste als Text – für eine Tabelle (Excel, Google Sheets) oder zum Posten in Discord.")
    local sync = T:Button(p, "Abgleichen", 110, 30, "ghost", function() LC:RequestHistorySync(true) end)
    sync:SetPoint("RIGHT", export, "LEFT", -8, 0)
    Tip(sync, "Abgleichen", "Holt fehlende Einträge vom Council – z. B. aus Raids, bei denen du nicht dabei warst. Passiert beim Einloggen auch automatisch.")
    y = y + 32 + 16

    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 0, -y)
    head:SetSize(CW, 18)
    for i, label in ipairs({ "DATUM / RAID", "ITEM", "SPIELER", "VERGABE" }) do
        local t = T:Text(head, 10, C.muted)
        t:SetPoint("LEFT", HCOLS[i] + 10, 0)
        t:SetText(label)
    end
    local line = T:Line(p, C.line)
    line:SetPoint("TOPLEFT", 0, -y - 20)
    line:SetWidth(CW)
    y = y + 24

    local sf, content = T:Scroll(p)
    sf:SetPoint("TOPLEFT", 0, -y)
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    p.list = content
    p.empty = T:Text(p, 12, C.muted, "CENTER")
    p.empty:SetPoint("TOP", sf, "TOP", 0, -40)
    p.empty:SetWidth(CW - 60)

    StaticPopupDialogs["LIGHTCOUNCIL_DELETE_HISTORY"] = {
        text = "Light Council: Diesen Eintrag aus der Loot-Historie löschen?\n\n%s",
        button1 = YES, button2 = NO,
        OnAccept = function(self) if self.data then LC:DeleteHistory(self.data) end end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

local function CreateHistoryRow(i)
    local p = pages.history
    local r = CreateFrame("Button", nil, p.list, "BackdropTemplate")
    r:SetSize(CW - 10, HIST_ROW)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * HIST_ROW)
    T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.date = T:Text(r, 12, C.text)
    r.date:SetPoint("TOPLEFT", HCOLS[1] + 10, -7)
    r.raid = T:Text(r, 10, C.muted)
    r.raid:SetPoint("TOPLEFT", r.date, "BOTTOMLEFT", 0, -3)
    r.raid:SetWidth(HCOLS[2] - 16)
    r.raid:SetWordWrap(false)
    r.icon = T:Icon(r, 28)
    r.icon:SetPoint("LEFT", HCOLS[2] + 10, 0)
    r.item = T:Text(r, 12, C.text, "LEFT", nil, true)
    r.item:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.item:SetWidth(HCOLS[3] - HCOLS[2] - 56)
    r.item:SetWordWrap(false)
    r.winner = T:Text(r, 12, C.text, "LEFT", nil, true)
    r.winner:SetPoint("LEFT", HCOLS[3] + 10, 0)
    r.winner:SetWidth(HCOLS[4] - HCOLS[3] - 16)
    r.winner:SetWordWrap(false)
    r.how = T:Text(r, 11, C.muted)
    r.how:SetPoint("LEFT", HCOLS[4] + 10, 0)
    r.how:SetWidth(CW - HCOLS[4] - 24)
    r.how:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
        if self.entry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.entry.itemID)
            if LC:AmICouncil() or LC:IsMasterLooter() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Rechtsklick: Eintrag löschen", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        local c = (self.index % 2 == 0) and C.panel or C.bg
        self:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
        GameTooltip_Hide()
    end)
    r:SetScript("OnClick", function(self, button)
        if not self.entry then return end
        if button == "RightButton" then
            if LC:AmICouncil() or LC:IsMasterLooter() then
                local e = self.entry
                local dlg = StaticPopup_Show("LIGHTCOUNCIL_DELETE_HISTORY", LC:ItemLink(e.itemID) .. " – " .. (e.winner or "?"))
                if dlg then dlg.data = e end
            end
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(LC:ItemLink(self.entry.itemID))
        end
    end)
    historyRows[i] = r
    return r
end

local function RefreshHistory()
    local p = pages.history
    p.seg:Set(p.mode)
    local list = LC:GetHistory(p.search:GetText())
    if p.mode == "mine" then
        local me = LC:PlayerName()
        local mine = {}
        for _, e in ipairs(list) do
            if LC:NamesMatch(e.winner, me) then mine[#mine + 1] = e end
        end
        list = mine
    end
    p.lastList = list
    local total = #LC.db.history
    p.count:SetText((#list == total) and (total .. (total == 1 and " Item" or " Items"))
        or (#list .. " von " .. total .. " Items"))
    if total == 0 then
        p.empty:SetText("Noch keine Einträge.\nSobald der Plündermeister ein Item über Light Council vergibt, steht es hier – mit Datum, Raid und Spieler.")
    else
        p.empty:SetText("Nichts gefunden.")
    end
    p.empty:SetShown(#list == 0)

    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for i = 1, math.max(#list, #historyRows) do
        local e = list[i]
        local r = historyRows[i]
        if e then
            r = r or CreateHistoryRow(i)
            r.index, r.entry = i, e
            r.date:SetText(date("%d.%m.%y", e.time))
            r.raid:SetText(e.raid or "")
            r.icon.tex:SetTexture(LC:ItemIcon(e.itemID))
            local _, _, quality = getInfo(e.itemID)
            local qc = T:QualityColor(quality)
            r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            r.item:SetText(LC:ItemLink(e.itemID))
            r.winner:SetText(e.winner or "?")
            local how
            if e.council then
                how = H.accentLt .. "Council|r"
            elseif e.reserved then
                how = "Reserviert"
            elseif e.offspec then
                how = "Off Spec"
            else
                how = "Main Spec"
            end
            if e.roll then how = how .. H.muted .. "  ·  Wurf " .. e.roll .. "|r" end
            r.how:SetText(how)
            r:Show()
        elseif r then
            r.entry = nil
            r:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #list * HIST_ROW))
end

-- Export-Fenster: Text markiert, Strg+C kopiert
local exportFrame
function LC:ShowHistoryExport(list)
    if not exportFrame then
        local f = T:Window("LightCouncilExportFrame", 680, 480, "Loot-Historie exportieren", "Strg+C kopiert den markierten Text")
        f:SetFrameStrata("DIALOG")
        f.format = "csv"
        f.seg = Segmented(f, {
            { key = "csv", label = "Tabelle (Excel / Sheets)", width = 220 },
            { key = "discord", label = "Discord", width = 110 },
        }, function(key)
            f.format = key
            LC:ShowHistoryExport(f.list)
        end)
        f.seg.first:SetPoint("TOPLEFT", 16, -50)
        f.hint = T:Text(f, 11, C.muted, "LEFT")
        f.hint:SetPoint("LEFT", f.seg.buttons.discord, "RIGHT", 14, 0)
        f.hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        f.hint:SetWordWrap(false)
        local box, eb = T:MultiLine(f)
        box:SetPoint("TOPLEFT", 16, -92)
        box:SetPoint("BOTTOMRIGHT", -16, 16)
        eb:SetWidth(680 - 32 - 16)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        f.edit = eb
        exportFrame = f
    end
    local f = exportFrame
    f.list = list
    f.seg:Set(f.format)
    f.hint:SetText(#list .. ((#list == 1) and " Eintrag" or " Einträge")
        .. ((f.format == "csv") and "  ·  In eine leere Tabelle einfügen (Trennzeichen: Semikolon)" or "  ·  Direkt in Discord einfügen"))
    f.edit:SetText(#list > 0 and self:HistoryExportText(list, f.format) or "Keine Einträge.")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

------------------------------------------------------------------------
-- Seite: Protokoll
------------------------------------------------------------------------
local function CreateLogPage(p)
    local y = PageHeader(p, "Protokoll", "Jede Entscheidung mit Stimmen und Begründung – kann bei Fragen offengelegt werden.")
    local box = Card(p)
    box:SetPoint("TOPLEFT", 0, -y)
    box:SetPoint("BOTTOMRIGHT", 0, 40)
    T:Skin(box, C.bgDark)
    local sf, content = T:Scroll(box)
    sf:SetPoint("TOPLEFT", 12, -10)
    sf:SetPoint("BOTTOMRIGHT", -18, 10)
    p.text = T:Text(content, 11, C.text)
    p.text:SetPoint("TOPLEFT", 0, 0)
    p.text:SetWidth(CW - 50)
    p.text:SetSpacing(3)
    p.content = content

    local post = T:Button(p, "Letzte 10 in den Chat", 160, 26, "default", function() LC:PrintLog(10) end)
    post:SetPoint("BOTTOMLEFT", 0, 0)
    Tip(post, "In den Chat", "Zeigt die letzten 10 Entscheidungen in deinem Chatfenster (nur für dich sichtbar).")
    local clear = T:Button(p, "Protokoll leeren", 130, 26, "danger", function() StaticPopup_Show("LIGHTCOUNCIL_CLEAR_LOG") end)
    clear:SetPoint("BOTTOMRIGHT", 0, 0)

    StaticPopupDialogs["LIGHTCOUNCIL_CLEAR_LOG"] = {
        text = "Light Council: Das gesamte Protokoll löschen?",
        button1 = YES, button2 = NO,
        OnAccept = function() wipe(LC.db.log) LC:RefreshUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

local function RefreshLog()
    local p = pages.log
    local log = LC.db.log
    if #log == 0 then
        p.text:SetText(H.muted .. "Noch keine Einträge. Jede Council-Entscheidung und jede Würfelrunde landet hier.|r")
    else
        local parts = {}
        for i = #log, math.max(1, #log - 60), -1 do
            parts[#parts + 1] = LC:FormatLogEntry(log[i])
        end
        p.text:SetText(table.concat(parts, "\n\n"))
    end
    p.content:SetHeight(p.text:GetStringHeight() + 10)
end

------------------------------------------------------------------------
-- Seite: Einstellungen
------------------------------------------------------------------------
-- Karte mit Überschrift; "anchor" = vorherige Karte (dann direkt darunter) oder y-Abstand von oben
local function Section(parent, title, anchor, height, desc)
    local card = Card(parent, height)
    if type(anchor) == "number" then
        card:SetPoint("TOPLEFT", 0, -anchor)
    else
        card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    end
    card:SetWidth(CW)
    local bar = card:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(T.WHITE)
    bar:SetVertexColor(unpack(C.accent))
    bar:SetPoint("TOPLEFT", 1, -14)
    bar:SetSize(3, 16)
    local t = T:Text(card, 14, C.text, "LEFT", nil, true)
    t:SetPoint("TOPLEFT", 16, -14)
    t:SetText(title)
    if desc then
        local d = T:Text(card, 11, C.muted)
        d:SetPoint("LEFT", t, "RIGHT", 10, -1)
        d:SetText(desc)
    end
    return card
end

local function LabeledInput(card, label, width, x, y)
    local l = T:Text(card, 11, C.muted)
    l:SetPoint("TOPLEFT", x, -y)
    l:SetText(label)
    local e = T:Input(card, width, 28)
    e:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -5)
    return e
end

local function CreateSettingsPage(p)
    local y = PageHeader(p, "Einstellungen", "Leitung und Council sollten dieselben Council-Namen eintragen.")

    -- COUNCIL ----------------------------------------------------------
    -- Eine eigene Zeile für die Größe (3 oder 5), darunter ein Feld pro Person.
    local SIZE_ROW, ROW1, ROW2 = 46, 98, 156
    local H3, H5 = ROW1 + 58 + 6, ROW2 + 58 + 6
    local c1 = Section(p, "Council", y, H3, "Ein Feld pro Person – Vor- und Nachname, kein Komma nötig.")
    p.councilCard = c1
    p.councilFields, p.councilExtra = {}, {}
    p.size = 3

    local sizeLabel = T:Text(c1, 12, C.text)
    sizeLabel:SetPoint("TOPLEFT", 16, -(SIZE_ROW + 8))
    sizeLabel:SetText("Anzahl Mitglieder")
    p.sizeButtons = {}
    local prev
    for _, n in ipairs({ 3, 5 }) do
        local b = T:Button(c1, n .. " Mitglieder", 130, 32, "default", function()
            p.size = n
            p:UpdateCouncilSize()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("TOPLEFT", 150, -SIZE_ROW) end
        p.sizeButtons[n] = b
        prev = b
    end
    p.majority = T:Text(c1, 12, C.muted)
    p.majority:SetPoint("LEFT", prev, "RIGHT", 18, 0)
    local line = T:Line(c1, C.line)
    line:SetPoint("TOPLEFT", 16, -(SIZE_ROW + 42))
    line:SetPoint("TOPRIGHT", -16, -(SIZE_ROW + 42))

    local colW = math.floor((CW - 32) / 3)
    for i = 1, 5 do
        local col = (i <= 3) and (i - 1) or (i - 4)
        local rowY = (i <= 3) and ROW1 or ROW2
        local label = T:Text(c1, 11, C.muted)
        label:SetPoint("TOPLEFT", 16 + col * colW, -rowY)
        label:SetText("Mitglied " .. i)
        -- Feld möglichst breit (Vor- und Nachname), "Ziel"-Knopf schmal, 12 px Abstand zur nächsten Spalte
        local field = T:Input(c1, colW - 54 - 6 - 12, 30)
        field:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
        field:SetPlaceholder("Vorname Nachname")
        local target = T:Button(c1, "Ziel", 54, 30, "default", function()
            local name = LC:UnitFullName("target")
            if not name or not UnitIsPlayer("target") then
                p.msg:SetText(H.bad .. "Bitte zuerst einen Spieler anvisieren.|r")
                return
            end
            for j, other in ipairs(p.councilFields) do
                if j ~= i and LC:NamesMatch(other:GetText(), name) then
                    p.msg:SetText(name .. " steht schon in Feld " .. j .. ".")
                    return
                end
            end
            field:SetText(name)
            p.msg:SetText(name .. " eingetragen – zum Übernehmen „Speichern“ klicken.")
        end)
        target:SetPoint("LEFT", field, "RIGHT", 6, 0)
        Tip(target, "Ziel eintragen", "Spieler anvisieren und klicken – trägt ihn mit Vor- und Nachnamen in dieses Feld ein.")
        p.councilFields[i] = field
        if i > 3 then p.councilExtra[#p.councilExtra + 1] = { label, field, target } end
    end

    function p:UpdateCouncilSize()
        for n, b in pairs(self.sizeButtons) do
            b.selected = (n == self.size)
            if b.selected then
                b:SetBackdropColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
                T:SetBorder(b, C.accent)
            else
                b.Paint(false)
            end
        end
        for _, parts in ipairs(self.councilExtra) do
            for _, w in ipairs(parts) do w:SetShown(self.size == 5) end
        end
        self.councilCard:SetHeight(self.size == 5 and H5 or H3)
        self.majority:SetText("Entscheidung mit Mehrheit: " .. H.accentLt .. (math.floor(self.size / 2) + 1) .. " von " .. self.size .. "|r")
    end

    -- REGELN & SCORE ---------------------------------------------------
    local c2 = Section(p, "Regeln & Score", c1, 166)
    local fw = math.floor((CW - 32) / 4) - 20
    local step = fw + 20
    p.voteTimeout = LabeledInput(c2, "Abstimmung (Sek.)", fw, 16, 46)
    p.rollTimeout = LabeledInput(c2, "Würfeln (Sek.)", fw, 16 + step, 46)
    p.cooldown = LabeledInput(c2, "Loot-Cooldown (Wochen)", fw, 16 + 2 * step, 46)
    p.attWeeks = LabeledInput(c2, "Anwesenheit (Wochen)", fw, 16 + 3 * step, 46)
    p.wAtt = LabeledInput(c2, "Score: Anwesenheit %", fw, 16, 104)
    p.wParse = LabeledInput(c2, "Score: Leistung (Parse) %", fw, 16 + step, 104)
    p.wEng = LabeledInput(c2, "Score: Engagement %", fw, 16 + 2 * step, 104)
    p.maxRes = LabeledInput(c2, "Reservierungen pro Raider", fw, 16 + 3 * step, 104)
    p.wSum = T:Text(c2, 12, C.muted, "RIGHT")
    p.wSum:SetPoint("TOPRIGHT", -16, -16)

    -- OPTIONEN ---------------------------------------------------------
    local c4 = Section(p, "Optionen", c2, 108)
    local half = math.floor(CW / 2)
    local function CheckTip(cb, title, text)
        cb:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:HookScript("OnLeave", GameTooltip_Hide)
    end
    p.raidWarning = T:Check(c4, "Raidwarnungen (Council & Gewinner)")
    p.raidWarning:SetPoint("TOPLEFT", 16, -48)
    CheckTip(p.raidWarning, "Raidwarnung", "Council-Items, die Entscheidung des Councils, freies Würfeln und jeder Gewinner werden als Raidwarnung angesagt. Braucht Raidleitung oder Assistent, sonst normaler Raidchat.")
    p.autoStart = T:Check(c4, "Council automatisch starten")
    p.autoStart:SetPoint("TOPLEFT", 16, -76)
    CheckTip(p.autoStart, "Automatisch starten", "Liegt ein Council-Item im Loot, startet die Abstimmung von selbst, sobald du als Plündermeister die Leiche öffnest.")
    p.minimap = T:Check(c4, "Minimap-Button anzeigen")
    p.minimap:SetPoint("TOPLEFT", half, -48)
    p.minimap:SetScript("OnClick", function(self)
        LC.db.config.minimap.hide = not self:GetChecked()
        LC:UpdateMinimapButton()
    end)
    p.raiderWindow = T:Check(c4, "Loot-Fenster für Raider anzeigen")
    p.raiderWindow:SetPoint("TOPLEFT", half, -76)
    CheckTip(p.raiderWindow, "Loot-Fenster für Raider", "Öffnet sich, wenn Loot droppt: zeigt Items, Prio und einen Würfel-Knopf für Berechtigte.")
    p.raiderWindow:SetScript("OnClick", function(self)
        LC.db.config.raiderWindow = self:GetChecked() and true or false
    end)

    p.msg = T:Text(p, 12, C.muted)
    p.msg:SetPoint("BOTTOMLEFT", 156, 10)
    p.msg:SetWidth(CW - 156)
    p.msg:SetWordWrap(false)

    local save = T:Button(p, "Speichern", 140, 34, "primary", function()
        local cfg = LC.db.config
        local council = {}
        for i, field in ipairs(p.councilFields) do
            local n = strtrim(field:GetText() or ""):gsub("%s+", " ")
            if i <= p.size and n ~= "" then council[#council + 1] = n end
        end
        cfg.councilSize = p.size
        cfg.council = council
        local function Num(box, min, max, default)
            local v = tonumber(box:GetText())
            if not v then return default end
            return math.max(min, math.min(max, math.floor(v + 0.5)))
        end
        cfg.voteTimeout = Num(p.voteTimeout, 10, 120, 30)
        cfg.rollTimeout = Num(p.rollTimeout, 5, 120, 20)
        cfg.cooldownWeeks = Num(p.cooldown, 0, 10, 2)
        cfg.attendanceWeeks = Num(p.attWeeks, 1, 52, 8)
        cfg.weights.attendance = Num(p.wAtt, 0, 100, 40)
        cfg.weights.parse = Num(p.wParse, 0, 100, 40)
        cfg.weights.engagement = Num(p.wEng, 0, 100, 20)
        cfg.maxReserves = Num(p.maxRes, 1, 5, 2)
        LC:BroadcastCouncilInfo()   -- Raider bekommen Council-Liste und Höchstzahl
        cfg.autoStart = p.autoStart:GetChecked() and true or false
        cfg.raidWarning = p.raidWarning:GetChecked() and true or false
        local msg = H.good .. "Gespeichert.|r"
        if #council ~= p.size then msg = msg .. "  " .. H.warn .. "Bitte alle " .. p.size .. " Council-Felder ausfüllen.|r" end
        p.msg:SetText(msg)
        p.needsLoad = true
        LC:RefreshUI()
    end)
    save:SetPoint("BOTTOMLEFT", 0, 0)
end

local function RefreshSettings()
    local p = pages.settings
    -- Felder nur beim Öffnen der Seite und nach dem Speichern füllen,
    -- damit ungespeicherte Eingaben nicht überschrieben werden
    if not p.needsLoad then return end
    p.needsLoad = false
    local cfg = LC.db.config
    for i, field in ipairs(p.councilFields) do
        field:SetText(cfg.council[i] or "")
    end
    p.size = LC:GetCouncilSize()
    p:UpdateCouncilSize()
    p.voteTimeout:SetText(tostring(cfg.voteTimeout))
    p.rollTimeout:SetText(tostring(cfg.rollTimeout))
    p.cooldown:SetText(tostring(cfg.cooldownWeeks))
    p.attWeeks:SetText(tostring(cfg.attendanceWeeks))
    p.wAtt:SetText(tostring(cfg.weights.attendance))
    p.wParse:SetText(tostring(cfg.weights.parse))
    p.wEng:SetText(tostring(cfg.weights.engagement))
    p.maxRes:SetText(tostring(cfg.maxReserves or 2))
    local sum = cfg.weights.attendance + cfg.weights.parse + cfg.weights.engagement
    p.wSum:SetText("Summe: " .. (sum == 100 and H.good or H.warn) .. sum .. " %|r")
    p.autoStart:SetChecked(cfg.autoStart)
    p.raidWarning:SetChecked(cfg.raidWarning)
    p.minimap:SetChecked(not cfg.minimap.hide)
    p.raiderWindow:SetChecked(cfg.raiderWindow)
end

------------------------------------------------------------------------
-- Fenster & Navigation
------------------------------------------------------------------------
local TABS = {
    { key = "start", label = "Erste Schritte", create = CreateStartPage, refresh = RefreshStart, group = "ÜBERSICHT" },
    { key = "loot", label = "Loot", create = CreateLootPage, refresh = RefreshLoot },
    { key = "myres", label = "Meine Reservierung", create = CreateMyResPage, refresh = RefreshMyRes },
    { key = "history", label = "Loot-Historie", create = CreateHistoryPage, refresh = RefreshHistory },
    { key = "items", label = "Raid-Loot", create = CreateItemsPage, refresh = RefreshItems, group = "VORBEREITUNG" },
    { key = "reserves", label = "Reservierungen", create = CreateReservesPage, refresh = RefreshReserves },
    { key = "players", label = "Spieler", create = CreatePlayersPage, refresh = RefreshPlayers, group = "COUNCIL" },
    { key = "log", label = "Protokoll", create = CreateLogPage, refresh = RefreshLog },
    { key = "settings", label = "Einstellungen", create = CreateSettingsPage, refresh = RefreshSettings, group = "ADDON" },
}

function SelectTab(key)
    currentTab = key
    if key == "settings" then pages.settings.needsLoad = true end
    for _, t in ipairs(TABS) do
        pages[t.key]:SetShown(t.key == key)
        nav[t.key]:SetSelected(t.key == key)
    end
    LC:RefreshUI()
end

local function CreateMainFrame()
    main = T:Window("LightCouncilMainFrame", W, HGT, "Light Council", "Reservierungen + Council · Lootverteilung", 56)
    main:Hide()

    -- Titelleiste nutzen: rechts Status, Rolle und Schnellzugriffe
    local bar = main.titleBar
    local function Pill(parent)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetHeight(30)
        T:Skin(f, C.panel, C.line)
        f.dot = f:CreateTexture(nil, "ARTWORK")
        f.dot:SetTexture(T.WHITE)
        f.dot:SetSize(8, 8)
        f.dot:SetPoint("LEFT", 12, 0)
        f.text = T:Text(f, 12, C.text, "LEFT", nil, true)
        f.text:SetPoint("LEFT", f.dot, "RIGHT", 9, 0)
        f.text:SetWordWrap(false)
        function f:Set(text, color)
            self.text:SetText(text)
            self.dot:SetVertexColor(color[1], color[2], color[3], 1)
            self:SetWidth(self.text:GetStringWidth() + 40)
        end
        return f
    end
    -- Test-Abstimmung gibt es auf "Erste Schritte" und der leeren Loot-Seite – oben nicht doppelt
    main.btnRaid = T:Button(bar, "Raider-Ansicht", 140, 32, "ghost", function() LC:ToggleRaidFrame() end)
    main.btnRaid:SetPoint("RIGHT", main.close, "LEFT", -14, 0)
    Tip(main.btnRaid, "Raider-Ansicht", "Öffnet das Loot-Fenster, das Raider sehen: Items, Prio und Würfel-Knopf.")
    main.rolePill = Pill(bar)
    main.rolePill:SetPoint("RIGHT", main.btnRaid, "LEFT", -18, 0)
    main.statusPill = Pill(bar)
    main.statusPill:SetPoint("RIGHT", main.rolePill, "LEFT", -8, 0)
    -- Erklärung per Maus-Tooltip
    local function PillTip(pill, title, text)
        pill:EnableMouse(true)
        pill:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        pill:SetScript("OnLeave", GameTooltip_Hide)
    end
    PillTip(main.statusPill, "Status", "Was gerade läuft: Nicht im Raid, Bereit (im Raid), Council stimmt ab, Würfelrunde läuft oder wartende Items.")
    PillTip(main.rolePill, "Deine Rolle", "Raidleitung, Plündermeister und/oder Council – davon hängt ab, was du im Addon tun darfst. Ohne besondere Rolle: Raider.")

    -- Seitenleiste
    local side = CreateFrame("Frame", nil, main, "BackdropTemplate")
    side:SetPoint("TOPLEFT", main.titleBar, "BOTTOMLEFT", 0, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR)
    T:Skin(side, C.bgDark, { 0, 0, 0, 0 })
    local sep = T:Line(side, C.border)
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    local sideGlow = side:CreateTexture(nil, "BORDER")
    sideGlow:SetTexture(T.WHITE)
    sideGlow:SetPoint("TOPLEFT")
    sideGlow:SetPoint("TOPRIGHT", -1, 0)
    sideGlow:SetHeight(140)
    T:Gradient(sideGlow, { 0.62, 0.39, 1, 0.08 }, { 0.62, 0.39, 1, 0 })

    -- Menü: nur klickbare Einträge; Gruppen werden durch eine feine Linie getrennt
    local y = 14
    for i, t in ipairs(TABS) do
        if t.group and i > 1 then
            local div = T:Line(side, C.line)
            div:SetPoint("TOPLEFT", 16, -(y + 6))
            div:SetPoint("TOPRIGHT", -16, -(y + 6))
            y = y + 13
        end
        local b = T:NavButton(side, t.label, SIDEBAR - 1, function() SelectTab(t.key) end)
        b:SetPoint("TOPLEFT", 0, -y)
        nav[t.key] = b
        y = y + 38
    end

    local ver = T:Text(side, 10, C.muted)
    ver:SetPoint("BOTTOMLEFT", 16, 14)
    ver:SetText("v" .. LC.version .. "  ·  /lc hilfe")

    for _, t in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, main)
        p:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -PAD)
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        p:Hide()
        pages[t.key] = p
        t.create(p)
    end
    main:SetScript("OnShow", function() LC:RefreshUI() end)
end

-- Startseite, solange die Vorbereitung unvollständig ist, sonst Loot
local function DefaultTab()
    -- Raider ohne besondere Rolle landen direkt bei ihrer Reservierung
    if not LC:AmICouncil() and not LC:IsMasterLooter() then return "myres" end
    local st = SetupStatus()
    if not (st.council.ok and st.softres.ok and st.items.ok) then return "start" end
    return "loot"
end

function LC:ShowMainFrame(tab)
    if not main then CreateMainFrame() end
    main:Show()
    SelectTab(tab or currentTab or DefaultTab())
end

function LC:ToggleMainFrame()
    if main and main:IsShown() then main:Hide() else self:ShowMainFrame() end
end

function LC:RefreshUI()
    if not main or not main:IsShown() then return end
    for _, t in ipairs(TABS) do
        if t.key == currentTab then t.refresh() end
    end
    local n = #self.lootItems
    nav.loot.badge:SetText(n > 0 and tostring(n) or "")
    local ci = 0
    for _ in pairs(self.db.councilItems) do ci = ci + 1 end
    nav.items.badge:SetText(ci > 0 and tostring(ci) or "")
    local st = SetupStatus()
    local open = 0
    for _, k in ipairs({ "council", "softres", "items" }) do
        if not st[k].ok then open = open + 1 end
    end
    nav.start.badge:SetText(open > 0 and (H.warn .. open .. " offen|r") or "")
    nav.reserves.badge:SetText((st.softres.pending or 0) > 0 and (H.warn .. st.softres.pending .. " Antrag|r") or "")

    -- Titelleiste: Status und Rolle
    if self.active then
        main.statusPill:Set("Council stimmt ab", C.accent)
    elseif self.roll then
        main.statusPill:Set("Würfelrunde läuft", C.warn)
    elseif #self.queue > 0 then
        main.statusPill:Set(#self.queue .. " Item(s) warten", C.accentLt)
    elseif IsInRaid() then
        main.statusPill:Set("Bereit", C.good)
    else
        main.statusPill:Set("Nicht im Raid", C.muted)
    end
    local roles = {}
    if self:IsMasterLooter() then roles[#roles + 1] = "Plündermeister" end
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then roles[#roles + 1] = "Raidleitung" end
    if self:IsCouncilMember(self:PlayerName()) then roles[#roles + 1] = "Council" end
    if #roles > 0 then
        main.rolePill:Set(table.concat(roles, " · "), C.accent)
    else
        main.rolePill:Set("Raider", C.muted)
    end
end

-- Titelleiste aktuell halten, wenn sich Gruppe oder Plündermethode ändern
LC:On("GROUP_ROSTER_UPDATE", function(self) self:RefreshUI() end)
LC:On("PARTY_LOOT_METHOD_CHANGED", function(self) self:RefreshUI() end)

LC:On("GET_ITEM_INFO_RECEIVED", function(self)
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.3, function()
        LC._refreshPending = nil
        LC:RefreshUI()
    end)
end)

function LC:OnInitialize()
    self:Print("v" .. self.version .. " geladen – |cffd1b5ff/lc|r öffnet das Fenster.")
end
