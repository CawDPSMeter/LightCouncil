-- Light Council – Hauptfenster, Seite: Einstellungen
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI
local pages, CW = U.pages, U.CW
local Card, PageHeader, Tip, AcceptLinks = U.Card, U.PageHeader, U.Tip, U.AcceptLinks
local SetupStatus, Segmented, ChipBar, SourceButton = U.SetupStatus, U.Segmented, U.ChipBar, U.SourceButton
local ReserveRaids, IdsFromText, ItemIcons = U.ReserveRaids, U.IdsFromText, U.ItemIcons
local ITEM_ROW, BOSS_W = U.ITEM_ROW, U.BOSS_W
local function SelectTab(key) return U.SelectTab(key) end

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
    l:SetWidth(width)          -- nie in das Nachbarfeld laufen (lange Übersetzungen werden gekürzt)
    l:SetWordWrap(false)
    local e = T:Input(card, width, 28)
    e:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -5)
    return e
end

-- Tooltip für Eingabefelder (T:Input zeigt tooltipTitle nicht selbst an)
local function InputTip(e, title, text)
    e:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    e:HookScript("OnLeave", GameTooltip_Hide)
end

local function CreateSettingsPage(p)
    local y = PageHeader(p, L["Einstellungen"], L["Leitung und Council sollten dieselben Council-Namen eintragen."])

    -- SPRACHE: Knopf oben rechts, Klick öffnet die Auswahl --------------
    local function LangLabel(key)
        for _, l in ipairs(LC.LANGUAGES) do
            if l.key == key then return (key == "auto") and L["Automatisch"] or l.label end
        end
        return key
    end
    local menu = Card(p)
    menu:SetFrameStrata("DIALOG")
    menu:SetWidth(180)
    menu:SetHeight(#LC.LANGUAGES * 30 + 12)
    menu:Hide()
    p.langBtn = T:Button(p, "", 180, 26, "default", function() menu:SetShown(not menu:IsShown()) end)
    p.langBtn:SetPoint("TOPRIGHT", 0, 0)
    -- Schließen bei Klick daneben, beim Seitenwechsel und mit Esc (Esc schließt das Hauptfenster samt Menü)
    menu:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not MouseIsOver(self) and not MouseIsOver(p.langBtn) then
            self:Hide()
        end
    end)
    p:HookScript("OnHide", function() menu:Hide() end)
    Tip(p.langBtn, L["Sprache"], L["Sprache des Addons. „Automatisch“ nimmt die Sprache deines Spielclients. Nach dem Wechsel wird die Oberfläche neu geladen."])
    menu:SetPoint("TOPRIGHT", p.langBtn, "BOTTOMRIGHT", 0, -2)
    for i, l in ipairs(LC.LANGUAGES) do
        local b = T:Button(menu, LangLabel(l.key), 164, 28, "ghost", function()
            menu:Hide()
            if (LC.db.config.language or "auto") == l.key then return end
            LC.db.config.language = l.key
            StaticPopupDialogs["LIGHTCOUNCIL_RELOAD_LANGUAGE"] = {
                text = L["Light Council: Die Sprache wird nach dem Neuladen der Oberfläche übernommen."],
                button1 = L["Jetzt neu laden"], button2 = L["Später"],
                OnAccept = function() ReloadUI() end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            StaticPopup_Show("LIGHTCOUNCIL_RELOAD_LANGUAGE")
            p.langBtn:SetText(L["Sprache: "] .. LangLabel(l.key))
        end)
        b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 30)
    end
    p.langBtn:SetText(L["Sprache: "] .. LangLabel(LC.db.config.language or "auto"))

    -- COUNCIL ----------------------------------------------------------
    -- Eine eigene Zeile für die Größe (3 oder 5), darunter ein Feld pro Person.
    local SIZE_ROW, ROW1, ROW2 = 46, 98, 156
    local H3, H5 = ROW1 + 58 + 6, ROW2 + 58 + 6
    local c1 = Section(p, L["Council"], y, H3, L["Ein Feld pro Person – Vor- und Nachname, kein Komma nötig."])
    p.councilCard = c1
    p.councilFields, p.councilExtra = {}, {}
    p.size = 3

    local sizeLabel = T:Text(c1, 12, C.text)
    sizeLabel:SetPoint("TOPLEFT", 16, -(SIZE_ROW + 8))
    sizeLabel:SetText(L["Anzahl Mitglieder"])
    p.sizeButtons = {}
    local prev
    for _, n in ipairs({ 3, 5 }) do
        local b = T:Button(c1, n .. L[" Mitglieder"], 130, 32, "default", function()
            p.size = n
            p:UpdateCouncilSize()
        end)
        -- erster Knopf direkt hinter der Beschriftung (deren Länge hängt von der Sprache ab)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("LEFT", sizeLabel, "RIGHT", 14, 0) end
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
        label:SetText(L["Mitglied "] .. i)
        -- Feld möglichst breit (Vor- und Nachname), "Ziel"-Knopf schmal, 12 px Abstand zur nächsten Spalte
        local field = T:Input(c1, colW - 54 - 6 - 12, 30)
        field:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
        field:SetPlaceholder(L["Vorname Nachname"])
        local target = T:Button(c1, L["Ziel"], 54, 30, "default", function()
            local name = LC:UnitFullName("target")
            if not name or not UnitIsPlayer("target") then
                p.msg:SetText(H.bad .. L["Bitte zuerst einen Spieler anvisieren.|r"])
                return
            end
            for j, other in ipairs(p.councilFields) do
                if j ~= i and LC:NamesMatch(other:GetText(), name) then
                    p.msg:SetText(name .. L[" steht schon in Feld "] .. j .. ".")
                    return
                end
            end
            field:SetText(name)
            p.msg:SetText(name .. L[" eingetragen – zum Übernehmen „Speichern“ klicken."])
        end)
        target:SetPoint("LEFT", field, "RIGHT", 6, 0)
        Tip(target, L["Ziel eintragen"], L["Spieler anvisieren und klicken – trägt ihn mit Vor- und Nachnamen in dieses Feld ein."])
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
        self.majority:SetText(L["Entscheidung mit Mehrheit: "] .. H.accentLt .. (math.floor(self.size / 2) + 1) .. L[" von "] .. self.size .. "|r")
    end

    -- REGELN & SCORE ---------------------------------------------------
    local c2 = Section(p, L["Regeln & Score"], c1, 166)
    local fw = math.floor((CW - 32) / 4) - 20
    local step = fw + 20
    p.voteTimeout = LabeledInput(c2, L["Abstimmung (Sek.)"], fw, 16, 46)
    p.rollTimeout = LabeledInput(c2, L["Würfeln (Sek.)"], fw, 16 + step, 46)
    p.cooldown = LabeledInput(c2, L["Loot-Cooldown (Wochen)"], fw, 16 + 2 * step, 46)
    p.attWeeks = LabeledInput(c2, L["Anwesenheit (Wochen)"], fw, 16 + 3 * step, 46)
    InputTip(p.cooldown, L["Loot-Cooldown (Wochen)"], L["Wer ein Council-Item gewinnt, ist in dieser Woche und den folgenden so vielen Wochen bei Council-Items gesperrt. 0 = kein Cooldown."])
    InputTip(p.attWeeks, L["Anwesenheit (Wochen)"], L["Zeitraum für die Anwesenheit im Score (1–20 Wochen). Genau diesen Zeitraum gleicht der Council untereinander ab."])
    p.wAtt = LabeledInput(c2, L["Score: Anwesenheit %"], fw, 16, 104)
    p.wParse = LabeledInput(c2, L["Score: Parse %"], fw, 16 + step, 104)
    p.wEng = LabeledInput(c2, L["Score: Engagement %"], fw, 16 + 2 * step, 104)
    p.maxRes = LabeledInput(c2, L["Reservierungen pro Raider"], fw, 16 + 3 * step, 104)
    p.wSum = T:Text(c2, 12, C.muted, "RIGHT")
    p.wSum:SetPoint("TOPRIGHT", -16, -16)

    -- Regeln speichern sofort, sobald ein Feld verlassen oder Enter gedrückt wird
    -- (bis 0.19.5 nur über „Speichern“ – nach einem Tabwechsel waren Änderungen dann verloren)
    local function Num(box, min, max, default)
        local v = tonumber(box:GetText())
        if not v then return default end
        return math.max(min, math.min(max, math.floor(v + 0.5)))
    end
    function p:ShowRules()
        local cfg = LC.db.config
        self.voteTimeout:SetText(tostring(cfg.voteTimeout))
        self.rollTimeout:SetText(tostring(cfg.rollTimeout))
        self.cooldown:SetText(tostring(cfg.cooldownWeeks))
        self.attWeeks:SetText(tostring(cfg.attendanceWeeks))
        self.wAtt:SetText(tostring(cfg.weights.attendance))
        self.wParse:SetText(tostring(cfg.weights.parse))
        self.wEng:SetText(tostring(cfg.weights.engagement))
        self.maxRes:SetText(tostring(cfg.maxReserves or 2))
        local sum = cfg.weights.attendance + cfg.weights.parse + cfg.weights.engagement
        self.wSum:SetText(L["Summe: "] .. (sum == 100 and H.good or H.warn) .. sum .. " %|r")
    end
    function p:SaveRules()
        local cfg = LC.db.config
        local oldMax = cfg.maxReserves
        cfg.voteTimeout = Num(self.voteTimeout, 10, 120, cfg.voteTimeout or 30)
        cfg.rollTimeout = Num(self.rollTimeout, 5, 120, cfg.rollTimeout or 20)
        cfg.cooldownWeeks = Num(self.cooldown, 0, 10, cfg.cooldownWeeks or 2)
        cfg.attendanceWeeks = Num(self.attWeeks, 1, 20, cfg.attendanceWeeks or 8)
        cfg.weights.attendance = Num(self.wAtt, 0, 100, cfg.weights.attendance or 40)
        cfg.weights.parse = Num(self.wParse, 0, 100, cfg.weights.parse or 40)
        cfg.weights.engagement = Num(self.wEng, 0, 100, cfg.weights.engagement or 20)
        cfg.maxReserves = Num(self.maxRes, 1, 5, cfg.maxReserves or 2)
        if cfg.maxReserves ~= oldMax then LC:BroadcastCouncilInfo() end   -- Raider bekommen die Höchstzahl
        self:ShowRules()   -- korrigierte Werte (Grenzen) und Summe anzeigen
    end
    for _, box in ipairs({ p.voteTimeout, p.rollTimeout, p.cooldown, p.attWeeks, p.wAtt, p.wParse, p.wEng, p.maxRes }) do
        box:HookScript("OnEditFocusLost", function()
            p:SaveRules()
            p.msg:SetText(H.good .. L["Gespeichert.|r"])
        end)
        box:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end

    -- OPTIONEN ---------------------------------------------------------
    local c4 = Section(p, L["Optionen"], c2, 108)
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
    p.raidWarning = T:Check(c4, L["Raidwarnungen (Council & Gewinner)"])
    p.raidWarning:SetPoint("TOPLEFT", 16, -48)
    CheckTip(p.raidWarning, L["Raidwarnung"], L["Council-Items, die Entscheidung des Councils, freies Würfeln und jeder Gewinner werden als Raidwarnung angesagt. Braucht Raidleitung oder Assistent, sonst normaler Raidchat."])
    p.autoStart = T:Check(c4, L["Council automatisch starten"])
    p.autoStart:SetPoint("TOPLEFT", 16, -76)
    CheckTip(p.autoStart, L["Automatisch starten"], L["Liegt ein Council-Item im Loot, startet die Abstimmung von selbst, sobald du als Plündermeister die Leiche öffnest."])
    -- Häkchen speichern sofort (wie Minimap und Loot-Fenster)
    p.raidWarning:SetScript("OnClick", function(self) LC.db.config.raidWarning = self:GetChecked() and true or false end)
    p.autoStart:SetScript("OnClick", function(self) LC.db.config.autoStart = self:GetChecked() and true or false end)
    p.minimap = T:Check(c4, L["Minimap-Button anzeigen"])
    p.minimap:SetPoint("TOPLEFT", half, -48)
    p.minimap:SetScript("OnClick", function(self)
        LC.db.config.minimap.hide = not self:GetChecked()
        LC:UpdateMinimapButton()
    end)
    p.raiderWindow = T:Check(c4, L["Loot-Fenster für Raider anzeigen"])
    p.raiderWindow:SetPoint("TOPLEFT", half, -76)
    CheckTip(p.raiderWindow, L["Loot-Fenster für Raider"], L["Öffnet sich, wenn Loot droppt: zeigt Items, Reservierungen und einen Würfel-Knopf für Berechtigte."])
    p.raiderWindow:SetScript("OnClick", function(self)
        LC.db.config.raiderWindow = self:GetChecked() and true or false
    end)

    p.msg = T:Text(p, 12, C.muted)
    p.msg:SetPoint("BOTTOMLEFT", 156, 10)
    p.msg:SetWidth(CW - 156)
    p.msg:SetWordWrap(false)

    local save = T:Button(p, L["Speichern"], 140, 34, "primary", function()
        local cfg = LC.db.config
        local council = {}
        for i, field in ipairs(p.councilFields) do
            local n = strtrim(field:GetText() or ""):gsub("%s+", " ")
            if i <= p.size and n ~= "" then council[#council + 1] = n end
        end
        cfg.councilSize = p.size
        cfg.council = council
        p:SaveRules()
        LC:BroadcastCouncilInfo()   -- Raider bekommen Council-Liste und Höchstzahl
        local msg = H.good .. L["Gespeichert.|r"]
        if #council ~= p.size then msg = msg .. "  " .. H.warn .. L["Bitte alle "] .. p.size .. L[" Council-Felder ausfüllen.|r"] end
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
    p:ShowRules()
    p.autoStart:SetChecked(cfg.autoStart)
    p.raidWarning:SetChecked(cfg.raidWarning)
    p.minimap:SetChecked(not cfg.minimap.hide)
    p.raiderWindow:SetChecked(cfg.raiderWindow)
end


U.CreateSettingsPage, U.RefreshSettings = CreateSettingsPage, RefreshSettings
