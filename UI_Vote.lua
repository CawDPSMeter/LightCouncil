-- Light Council – Abstimmungs-Popup für Council-Mitglieder
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX

local frame
local rows = {}
local W = 820
local PAD = 16
local ROW_H = 30
local LIST_TOP = 138
local COL = { name = 34, score = 250, att = 340, parse = 405, eng = 465, set = 525, gear = 610, last = 705 }

local function Val(v, suffix)
    if v == nil then return H.muted .. L["–|r"] end
    return tostring(v) .. (suffix or "")
end

-- Spalte „Angelegt“: was trägt der Kandidat im Slot des Items?
local function SetGear(r, name, itemID)
    local info = LC:GetEquippedFor(name, itemID)
    for _, g in ipairs(r.gear) do g:Hide() g.lvl:SetText("") g.itemID, g.note = nil, nil end
    r.gearText:SetText("")
    if not info then
        r.gearText:SetText(H.muted .. L["–|r"])   -- Item ohne Slot (z. B. Token)
        return
    end
    if not info.known then
        r.gearText:SetText(H.muted .. L["unbekannt"] .. "|r")
        return
    end
    local note = info.stale and (L["veraltet"] .. " (" .. LC.EquippedAgeText(info.time) .. ")") or nil
    for k, it in ipairs(info.items) do
        local g = r.gear[k]
        if not g then break end
        g:Show()
        g.itemID, g.note = it.id, note
        if it.id then
            g.tex:SetTexture(LC:ItemIcon(it.id))
            g.tex:SetDesaturated(info.stale == true)
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local qc = T:QualityColor(select(3, getInfo(it.id)))
            g:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            local lvl = LC:ItemLevelOf(it.id)
            g.lvl:SetText(lvl and tostring(lvl) or "")
            local lc = info.stale and C.muted or C.text
            g.lvl:SetTextColor(lc[1], lc[2], lc[3])
        else
            g.tex:SetTexture(nil)
            g:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
            g.lvl:SetText(H.muted .. L["leer"] .. "|r")
        end
    end
end

-- Neue Ausrüstungsdaten angekommen: nur die Spalte im offenen Fenster neu zeichnen
function LC:RefreshVoteEquipped()
    if not frame or not frame:IsShown() or not self.voteSession then return end
    for _, r in ipairs(rows) do
        if r:IsShown() and r.candidate then SetGear(r, r.candidate.name, self.voteSession.itemID) end
    end
end

local function CreateVoteFrame()
    frame = T:Window("LightCouncilVoteFrame", W, 300, L["Council-Abstimmung"], L["Score nur für den Council sichtbar"])
    frame:SetFrameStrata("DIALOG")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", 0, 140)

    -- Item-Karte
    local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    T:Skin(card, C.panel)
    card:SetPoint("TOPLEFT", PAD, -46)
    card:SetPoint("TOPRIGHT", -PAD, -46)
    card:SetHeight(62)
    frame.card = card

    frame.icon = T:Icon(card, 42)
    frame.icon:SetPoint("LEFT", 10, 0)

    frame.itemBtn = CreateFrame("Button", nil, card)
    frame.itemBtn:SetPoint("TOPLEFT", 62, -12)
    frame.itemBtn:SetSize(W - 2 * PAD - 80, 18)
    frame.itemText = T:Text(frame.itemBtn, 14, C.text)
    frame.itemText:SetPoint("LEFT")
    frame.itemText:SetWordWrap(false)
    frame.itemBtn:SetScript("OnEnter", function(self)
        local s = LC.voteSession
        if s and s.link and s.link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(s.link)
            GameTooltip:Show()
        end
    end)
    frame.itemBtn:SetScript("OnLeave", GameTooltip_Hide)

    frame.timer = T:Bar(card, 6)
    frame.timer:SetPoint("BOTTOMLEFT", 62, 12)
    frame.timer:SetPoint("BOTTOMRIGHT", -90, 12)
    -- Sekunden rechts neben der Leiste, auf gleicher Höhe – überlappt nicht
    frame.timeText = T:Text(card, 11, C.accentLt, "RIGHT")
    frame.timeText:SetPoint("RIGHT", frame.timer, "RIGHT", 78, 0)   -- endet 12 px vor dem Kartenrand
    frame.timeText:SetWidth(70)

    -- Spaltenköpfe
    local function Head(text, x)
        local t = T:Text(frame, 10, C.muted)
        t:SetPoint("TOPLEFT", PAD + x, -120)
        t:SetText(text)
    end
    Head(L["SPIELER"], COL.name)
    Head(L["SCORE"], COL.score)
    Head(L["ANW."], COL.att)
    Head(L["PARSE"], COL.parse)
    Head(L["ENG."], COL.eng)
    Head(L["SET"], COL.set)
    Head(L["ANGELEGT"], COL.gear)
    Head(L["LETZTES ITEM"], COL.last)
    local line = T:Line(frame, C.line)
    line:SetPoint("TOPLEFT", PAD, -LIST_TOP + 4)
    line:SetPoint("TOPRIGHT", -PAD, -LIST_TOP + 4)

    -- Begründung
    frame.reasonLabel = T:Text(frame, 10, C.muted)
    frame.reasonLabel:SetText(L["BEGRÜNDUNG (wird im Protokoll gespeichert)"])
    frame.reason = T:Input(frame, W - 2 * PAD, 26)
    frame.reason:SetMaxLetters(120)

    -- Entscheidungs-Buttons
    local bw = math.floor((W - 2 * PAD - 16) / 3)
    local function Decision(label, tip, decision, style)
        local b = T:Button(frame, label, bw, 30, style, function() LC:VoteButtonClicked(decision) end)
        b.tooltipTitle = label
        b.tooltip = tip
        return b
    end
    frame.btnOpen = Decision(L["Freigeben"], L["Alle berechtigten Reservierer würfeln."], "OPEN", "primary")
    frame.btnLimit = Decision(L["Eingrenzen"], L["Nur die angehakten Spieler würfeln."], "LIMIT", "default")
    frame.btnSkip = Decision(L["Aussetzen"], L["Der angehakte Spieler (genau einer) setzt bei diesem Item diese Woche aus."], "SKIP", "default")

    frame.status = T:Text(frame, 12, C.text, "CENTER")
    frame.status:SetWidth(W - 2 * PAD)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local s = LC.voteSession
        if not s or not s.expires then return end
        local left = math.max(0, s.expires - GetTime())
        self.timer.bar:SetMinMaxValues(0, s.timeout)
        self.timer.bar:SetValue(left)
        local c = (left <= 10 and not s.ended) and C.bad or C.accent
        self.timer.bar:SetStatusBarColor(c[1], c[2], c[3])
        if s.ended then
            self.timeText:SetText(L["beendet"])
        else
            self.timeText:SetText(string.format(L["%d Sek."], math.ceil(left)))
            if left <= 0 and not s.voted and not s.recused and not self.expiredShown then
                self.expiredShown = true
                LC:UpdateVoteFrame()
            end
        end
    end)
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, frame, "BackdropTemplate")
    r:SetSize(W - 2 * PAD, ROW_H - 2)
    T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
    r.check = T:Check(r, nil, 16)
    r.check:SetPoint("LEFT", 10, 0)
    r.name = T:Text(r, 12, C.text)
    r.name:SetPoint("LEFT", COL.name, 0)
    r.name:SetWidth(150)
    r.name:SetWordWrap(false)
    r.badge = T:Badge(r)
    r.badge:SetPoint("LEFT", r.name, "LEFT", 0, 0)
    r.score = T:Text(r, 13, C.text)
    r.score:SetPoint("LEFT", COL.score, 0)
    r.scoreBar = T:Bar(r, 4)
    r.scoreBar:SetPoint("LEFT", COL.score + 30, 0)
    r.scoreBar:SetWidth(46)
    r.scoreBar.bar:SetMinMaxValues(0, 100)
    r.att = T:Text(r, 11, C.text)
    r.att:SetPoint("LEFT", COL.att, 0)
    r.parse = T:Text(r, 11, C.text)
    r.parse:SetPoint("LEFT", COL.parse, 0)
    r.eng = T:Text(r, 11, C.text)
    r.eng:SetPoint("LEFT", COL.eng, 0)
    r.set = T:Text(r, 11, C.text)
    r.set:SetPoint("LEFT", COL.set, 0)
    r.set:SetWidth(COL.gear - COL.set - 6)
    r.set:SetWordWrap(false)
    -- Angelegt: bis zu zwei Items (Ringe, Schmuck, Einhandwaffen) mit Itemlevel, Tooltip beim Drüberfahren
    r.gear = {}
    for k = 1, 2 do
        local g = T:Icon(r, 18)
        g:SetPoint("LEFT", COL.gear + (k - 1) * 46, 0)
        g:EnableMouse(true)
        g.lvl = T:Text(r, 10, C.muted)
        g.lvl:SetPoint("LEFT", g, "RIGHT", 3, 0)
        g:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then
                GameTooltip:SetHyperlink("item:" .. self.itemID)
            else
                GameTooltip:SetText(L["Angelegt"], 1, 1, 1)
            end
            if self.note then GameTooltip:AddLine(self.note, 1, 0.6, 0.3, true) end
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", GameTooltip_Hide)
        r.gear[k] = g
    end
    r.gearText = T:Text(r, 11, C.muted)
    r.gearText:SetPoint("LEFT", COL.gear, 0)
    r.gearText:SetWidth(COL.last - COL.gear - 6)
    r.gearText:SetWordWrap(false)
    r.last = T:Text(r, 11, C.text)
    r.last:SetPoint("LEFT", COL.last, 0)
    r.last:SetWidth(W - 2 * PAD - COL.last - 8)
    r.last:SetWordWrap(false)
    -- Klick auf die Zeile setzt/entfernt das Häkchen
    r:SetScript("OnClick", function(self)
        if self.check:IsEnabled() then self.check:SetChecked(not self.check:GetChecked()) end
    end)
    -- Maus drüber: die letzten Items des Spielers aus der Loot-Historie
    r:SetScript("OnEnter", function(self)
        if not self.candidate then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.candidate.name, 1, 1, 1)
        LC:AddGearSetTooltip(GameTooltip, self.candidate.name, LC.voteSession and LC.voteSession.itemID)
        LC:AddEquippedTooltip(GameTooltip, self.candidate.name, LC.voteSession and LC.voteSession.itemID)
        LC:AddLootTooltip(GameTooltip, self.candidate.name, 6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

-- keep = true: dieselbe Abstimmung nur neu aufbauen (Spielerliste kam später) – Eingaben bleiben erhalten
function LC:ShowVoteFrame(s, keep)
    if not frame then CreateVoteFrame() end
    local keepChecks
    if keep and frame.sid == s.sid and frame:IsShown() then
        keepChecks = {}
        for _, r in ipairs(rows) do
            if r.candidate and r.check:GetChecked() then keepChecks[r.candidate.name] = true end
        end
    else
        frame.expiredShown = nil
        frame.reason:SetText("")
        frame.status:SetText("")
    end
    frame.sid = s.sid
    frame.subtitle:SetText(string.format(L["Mehrheit %d von %d  ·  Score nur für den Council sichtbar"], s.need or 2, s.size or 3))
    local link = s.link or (L["Item #"] .. tostring(s.itemID))
    frame.itemText:SetText(link)
    frame.icon.tex:SetTexture(self:ItemIcon(s.itemID))
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(s.itemID or 0)
    local qc = T:QualityColor(quality)
    frame.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)

    local n = #s.candidates
    for i = 1, math.max(n, #rows) do
        local c = s.candidates[i]
        if c then
            local r = GetRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -LIST_TOP - (i - 1) * ROW_H)
            r.check:SetChecked(keepChecks and keepChecks[c.name] or false)
            local flags = c.flags or ""
            local eligible = flags:find("E") ~= nil
            r.name:SetText(c.name)
            local nc = eligible and C.text or C.muted
            r.name:SetTextColor(nc[1], nc[2], nc[3])
            -- Etikett rechts neben dem Namen
            local tag, tagColor
            if flags:find("A") then tag, tagColor = L["ABWESEND"], { 0.35, 0.12, 0.16 }
            elseif flags:find("S") then tag, tagColor = L["SETZT AUS"], { 0.35, 0.12, 0.16 }
            elseif flags:find("C") then
                if eligible then tag, tagColor = L["CD IGNORIERT"], { 0.40, 0.26, 0.08 }
                else tag, tagColor = L["LOOT-CD"], { 0.40, 0.26, 0.08 } end
            end
            r.badge:ClearAllPoints()
            r.badge:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), 150) + 8, 0)
            r.badge:Set(tag, tagColor)

            local sc = T:ScoreColor(c.score)
            r.score:SetText(Val(c.score))
            r.score:SetTextColor(sc[1], sc[2], sc[3])
            r.scoreBar:SetShown(c.score ~= nil)
            r.scoreBar.bar:SetValue(c.score or 0)
            r.scoreBar.bar:SetStatusBarColor(sc[1], sc[2], sc[3])
            r.att:SetText(Val(c.att, "%"))
            r.parse:SetText(Val(c.parse))
            r.eng:SetText(Val(c.eng, "/5"))
            -- Gear-Set: ist das Item im Set des Spielers (★ = wichtig)?
            r.set:SetText(self:GearSetRankText(c.name, s.itemID))
            SetGear(r, c.name, s.itemID)
            -- Letztes Item: Council-Items lila hervorgehoben
            local loot = self:GetPlayerLoot(c.name)
            local last = loot[1]
            local nRaid = self:RaidLootCount(c.name)
            local raidTxt = (nRaid > 0) and ((nRaid >= (tonumber(self.db.config.fairLimit) or 0) and (tonumber(self.db.config.fairLimit) or 0) > 0 and H.warn or H.accentLt) .. L("%d× Raid-ID", nRaid) .. "|r  ") or ""
            if last then
                r.last:SetText(raidTxt .. (last.council and (H.accentLt .. L["Council|r "]) or "") .. self:AgoText(last.time))
            else
                r.last:SetText(H.muted .. L["noch keins|r"])
            end
            r.candidate = c
            r:SetAlpha(eligible and 1 or 0.6)
            r:Show()
        elseif rows[i] then
            rows[i].candidate = nil
            rows[i]:Hide()
        end
    end

    local y = LIST_TOP + n * ROW_H + 12
    frame.reasonLabel:ClearAllPoints()
    frame.reasonLabel:SetPoint("TOPLEFT", PAD, -y)
    frame.reason:ClearAllPoints()
    frame.reason:SetPoint("TOPLEFT", PAD, -y - 16)
    y = y + 16 + 26 + 12
    frame.btnOpen:ClearAllPoints()
    frame.btnOpen:SetPoint("TOPLEFT", PAD, -y)
    frame.btnLimit:ClearAllPoints()
    frame.btnLimit:SetPoint("LEFT", frame.btnOpen, "RIGHT", 8, 0)
    frame.btnSkip:ClearAllPoints()
    frame.btnSkip:SetPoint("LEFT", frame.btnLimit, "RIGHT", 8, 0)
    y = y + 30 + 12
    frame.status:ClearAllPoints()
    frame.status:SetPoint("TOP", frame, "TOP", 0, -y)
    frame:SetHeight(y + 44)   -- Platz für einen zweizeiligen Hinweis

    frame:Show()
    self:UpdateVoteFrame()
end

function LC:UpdateVoteFrame()
    if not frame or not frame:IsShown() then return end
    local s = self.voteSession
    if not s then return end
    local canVote = not s.voted and not s.recused and not s.ended and (not s.expires or GetTime() <= s.expires)
    frame.btnOpen:SetEnabled(canVote)
    frame.btnLimit:SetEnabled(canVote)
    frame.btnSkip:SetEnabled(canVote)
    frame.reason:SetEnabled(canVote)
    frame.reason:SetAlpha(canVote and 1 or 0.5)
    for _, r in ipairs(rows) do
        if r.candidate then
            r.check:SetEnabled(canVote and (r.candidate.flags or ""):find("E") ~= nil)
        end
    end

    if s.ended then
        frame.status:SetText(H.good .. L["Ergebnis:|r "] .. (s.result or ""))
    elseif s.recused then
        frame.status:SetText(H.warn .. L["Du hast dieses Item selbst reserviert – du stimmst nicht ab.|r"])
    elseif s.voted then
        local v = s.myVote
        local txt = L[self.DECISION_LABEL[v.decision] or v.decision]
        if #v.names > 0 then txt = txt .. " (" .. table.concat(v.names, ", ") .. ")" end
        frame.status:SetText(L["Deine Stimme: "] .. H.accentLt .. txt .. L["|r  ·  warte auf die anderen …"])
    elseif s.expires and GetTime() > s.expires then
        frame.status:SetText(H.bad .. L["Zeit abgelaufen.|r"])
    else
        frame.status:SetText(H.muted .. L["Spieler anhaken für „Eingrenzen“ (mehrere) oder „Aussetzen“ (genau einer). Maus über einen Spieler zeigt seine letzten Items.|r"])
    end
end

function LC:VoteButtonClicked(decision)
    local names = {}
    if decision ~= "OPEN" then
        for _, r in ipairs(rows) do
            if r:IsShown() and r.candidate and r.check:GetChecked() then
                names[#names + 1] = r.candidate.name
            end
        end
    end
    local ok, err = self:SubmitVote(decision, names, frame.reason:GetText())
    if not ok then
        frame.status:SetText(H.bad .. (err or L["Fehler"]) .. "|r")
        return
    end
    frame.reason:ClearFocus()
    self:UpdateVoteFrame()
end

function LC:HideVoteFrame()
    if frame then frame:Hide() end
end
