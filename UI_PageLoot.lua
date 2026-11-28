-- Light Council – Hauptfenster, Seite: Loot
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
-- Seite: Loot
------------------------------------------------------------------------
local lootRows = {}
local ROW_H = 52
local LOOT_LW = CW - 380   -- Breite für Itemname und Reservierer

local function CreateLootPage(p)
    local y = PageHeader(p, L["Loot"], L["Öffnest du als Plündermeister eine Leiche, erscheinen die Items hier. Council-Items starten automatisch."])

    -- Automatisch vergeben: oben rechts neben der Überschrift
    p.autoAward = T:Check(p, L["Automatisch vergeben"])
    p.autoAward:SetPoint("TOPRIGHT", -170, -6)
    p.autoAward:SetScript("OnClick", function(self)
        LC.db.config.autoAward = self:GetChecked() and true or false
    end)
    p.autoAward:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Automatisch vergeben"], 1, 1, 1)
        GameTooltip:AddLine(L["Steht der Gewinner fest, bekommt er das Item sofort – ohne Klick auf „An …“. "]
            .. L["Ist das Lootfenster zu, wird beim nächsten Öffnen der Leiche vergeben. Klappt die Übergabe nicht (z. B. Taschen voll), bekommen du und der Gewinner einen Hinweis."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    p.autoAward:HookScript("OnLeave", GameTooltip_Hide)

    -- Auch normale Items gleich auswürfeln (sonst nur Council-Items automatisch)
    p.autoRollAll = T:Check(p, L["Alles automatisch starten"])
    p.autoRollAll:SetPoint("TOPLEFT", p.autoAward, "BOTTOMLEFT", 0, -4)
    p.autoRollAll:SetScript("OnClick", function(self)
        LC.db.config.autoRollAll = self:GetChecked() and true or false
    end)
    p.autoRollAll:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Alles automatisch starten"], 1, 1, 1)
        GameTooltip:AddLine(L["Beim Öffnen einer Leiche werden auch normale Items sofort ausgewürfelt – ohne Klick auf „Alle starten“. Council-Items gehen wie gewohnt an den Council."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    p.autoRollAll:HookScript("OnLeave", GameTooltip_Hide)

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

    p.btnCancel = T:Button(status, L["Abbrechen"], 96, 26, "danger", function() LC:CancelAll() end)
    p.btnCancel:SetPoint("RIGHT", -12, 0)
    Tip(p.btnCancel, L["Abbrechen"], L["Bricht die laufende Abstimmung oder Würfelrunde ab und leert die Warteschlange."])
    p.btnFinish = T:Button(status, L["Würfeln beenden"], 130, 26, "default", function() LC:FinishRoll() end)
    p.btnFinish:SetPoint("RIGHT", p.btnCancel, "LEFT", -6, 0)
    Tip(p.btnFinish, L["Würfeln beenden"], L["Beendet die Würfelrunde sofort und sagt den Gewinner an, statt auf den Ablauf der Zeit zu warten."])
    p.btnAll = T:Button(status, L["Alle starten"], 140, 26, "primary", function()
        for _, e in ipairs(LC.lootItems) do
            if e.status == "offen" and not e.winner and not e.awarded and not e.looted and not e.belowThreshold and not e.held then LC:Enqueue(e) end
        end
    end)
    p.btnAll:SetPoint("RIGHT", p.btnFinish, "LEFT", -6, 0)
    Tip(p.btnAll, L["Alle starten"], L["Stellt alle offenen Items nacheinander in die Warteschlange: Council-Items gehen an den Council, alle anderen werden direkt ausgewürfelt."])
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
    et:SetText(L["Gerade kein Loot"])
    local es = T:Text(empty, 11, C.muted, "CENTER")
    es:SetPoint("TOP", et, "BOTTOM", 0, -6)
    es:SetWidth(CW - 80)
    es:SetText(L["Dieses Fenster öffnet sich von selbst, sobald du als Plündermeister eine Leiche öffnest."])
    local eb1 = T:Button(empty, L["Erste Schritte"], 130, 26, "default", function() SelectTab("start") end)
    eb1:SetPoint("TOP", es, "BOTTOM", -70, -14)
    local eb2 = T:Button(empty, L["Test-Abstimmung"], 130, 26, "primary", function() LC:StartTest("") end)
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
    -- Maus über die Reservierer: was sie im Slot des Items angelegt haben
    r.infoBtn = CreateFrame("Button", nil, r)
    r.infoBtn:SetPoint("TOPLEFT", r.info, "TOPLEFT", 0, 2)
    r.infoBtn:SetSize(LOOT_LW, 14)
    r.infoBtn:SetScript("OnEnter", function(self)
        local e = r.entry
        if not e or e.test then return end
        local res = LC:GetReservers(e.itemID)
        if #res == 0 or not LC:EquipSlotsFor(e.itemID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Angelegt im Slot"], 1, 1, 1)
        for i, x in ipairs(res) do
            if i > 10 then
                GameTooltip:AddLine(L["… insgesamt "] .. #res, 0.6, 0.6, 0.6)
                break
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(x.name, 0.71, 0.55, 1)
            LC:AddEquippedTooltip(GameTooltip, x.name, e.itemID)
        end
        GameTooltip:Show()
    end)
    r.infoBtn:SetScript("OnLeave", GameTooltip_Hide)

    r.council = T:Check(r, L["Council"], 14)
    r.council:SetPoint("LEFT", 62 + LOOT_LW, 8)
    r.council:SetScript("OnClick", function(self)
        if r.entry and not r.entry.test then
            LC:SetCouncilItem(r.entry.itemID, self:GetChecked())
            LC:RefreshUI()
        end
    end)
    r.council:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Council-Item"], 1, 1, 1)
        GameTooltip:AddLine(L["Angehakt: Der Council entscheidet, wer würfeln darf. Gilt dauerhaft für dieses Item."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    r.council:HookScript("OnLeave", GameTooltip_Hide)
    r.state = T:Text(r, 10, C.muted)
    r.state:SetPoint("LEFT", 62 + LOOT_LW, -10)
    r.state:SetWidth(110)
    r.state:SetWordWrap(false)

    r.btnAward = T:Button(r, L["Vergeben"], 100, 26, "default", function()
        if r.entry then LC:AwardLoot(r.entry) end
    end)
    r.btnAward:SetPoint("RIGHT", -8, 0)
    r.btnAction = T:Button(r, L["Council starten"], 112, 26, "primary", function()
        if not r.entry then return end
        if r.entry.held then LC:RollAnyway(r.entry) else LC:Enqueue(r.entry) end
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
        p.statusTitle:SetText(L["Council stimmt ab:  "] .. a.entry.link)
        p.statusSub:SetText(string.format(L["%d von %d Stimmen%s  ·  noch %d Sek."], #a.voteOrder, a.nVoters,
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
        p.statusTitle:SetText(L["Es wird gewürfelt:  "] .. r.entry.link)
        p.statusSub:SetText(((#parts > 0) and table.concat(parts, "  ·  ") or L["Noch keine Würfe"]) .. L["  ·  noch "] .. math.ceil(left) .. L[" Sek."])
        p.timeBar.bar:SetMinMaxValues(0, self.db.config.rollTimeout)
        p.timeBar.bar:SetValue(left)
        p.timeBar.bar:SetStatusBarColor(unpack(C.warn))
        p.timeBar:Show()
        p.stripe:SetVertexColor(unpack(C.warn))
    else
        local q = #self.queue
        if q > 0 then
            p.statusTitle:SetText(q .. L[" Item(s) warten"])
        elseif #self.lootItems > 0 then
            p.statusTitle:SetText(L["Bereit – nächstes Item auswählen"])
        else
            p.statusTitle:SetText(L["Bereit"])
        end
        if self:IsMasterLooter() then
            p.statusSub:SetText(self.db.config.autoAward and L["„Alle starten“ – Gewinner bekommen ihr Item automatisch."]
                or L["„Alle starten“ → Gewinner steht fest → „An …“ klicken."])
        else
            p.statusSub:SetText(H.warn .. L["Du bist nicht Plündermeister.|r Loot erscheint nur beim Plündermeister."])
        end
        p.timeBar:Hide()
        p.stripe:SetVertexColor(unpack(C.line))
    end
    p.btnCancel:SetEnabled(a ~= nil or r ~= nil or #self.queue > 0)
    p.btnFinish:SetEnabled(r ~= nil)
    local open = 0
    for _, e in ipairs(self.lootItems) do
        if e.status == "offen" and not e.winner and not e.awarded and not e.looted and not e.belowThreshold and not e.held then open = open + 1 end
    end
    p.btnAll:SetEnabled(open > 0)
    p.btnAll:SetText(open > 1 and (L["Alle starten ("] .. open .. ")") or L["Alle starten"])
end

local function RefreshLoot()
    local p = pages.loot
    p.autoAward:SetChecked(LC.db.config.autoAward)
    p.autoRollAll:SetChecked(LC.db.config.autoRollAll)
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
            -- Reservierer mit der Zahl ihrer Items in dieser Raid-ID (Fairness)
            local names = {}
            for _, x in ipairs(res) do
                local n = (not e.test) and LC:RaidLootCount(x.name) or 0
                names[#names + 1] = x.name .. ((n > 0) and (H.muted .. " (" .. n .. ")|r") or "")
            end
            local info = (#names > 0) and (L["Reserviert: "] .. table.concat(names, ", ")) or L["Keine Reservierung – freies Würfeln"]
            r.info:SetText(info)

            r.council:SetChecked(e.isCouncil)
            r.council:SetEnabled(not e.test and not busy and not e.awarded and e.status ~= "wartet")

            local st = e.status or "offen"
            if e.awarded then st = H.good .. "✓ " .. L("bei %s", e.winner or "?") .. "|r"
            elseif e.pending then st = H.warn .. L["wird übergeben …"] .. "|r"
            elseif e.giveFailed and e.bagReady then st = H.warn .. L["Platz frei – erneut übergeben"] .. "|r"
            elseif e.giveFailed then st = H.bad .. "✗ " .. L["Übergabe fehlgeschlagen"] .. "|r"
            elseif e.otherCorpse then st = H.warn .. L["andere Leiche öffnen"] .. "|r"
            elseif e.held then st = H.warn .. L("wartet auf %s", (e.held[1] or "?"):match("^(%S+)") .. ((#e.held > 1) and " …" or "")) .. "|r"
            elseif e.belowThreshold and not e.winner then st = L["unter Plündergrenze"]
            elseif e.looted then st = L["nicht mehr im Loot"]
            elseif e.winner then st = H.accentLt .. L["Gewinner|r"]
            elseif st == "offen" then st = ""
            else st = L[st] end
            r.state:SetText(st)

            local canStart = not busy and not e.awarded and not e.looted and not e.otherCorpse and (e.status == "offen" or e.winner ~= nil)
            if e.held then
                r.btnAction:SetText(L["Trotzdem würfeln"])
                r.btnAction.tooltip = L("Wartet auf %s (offline). Klick: nicht mehr warten und mit den Anwesenden auswürfeln.", table.concat(e.held, ", "))
            elseif e.winner and not e.awarded then
                r.btnAction:SetText(L["Neu starten"])
                r.btnAction.tooltip = L["Startet Abstimmung bzw. Würfeln für dieses Item noch einmal."]
            else
                r.btnAction:SetText(e.isCouncil and L["Council starten"] or L["Würfeln lassen"])
                r.btnAction.tooltip = e.isCouncil
                    and L["Der Council bekommt ein Popup und entscheidet, wer würfeln darf. Danach wird automatisch gewürfelt."]
                    or L["Sagt im Raid an, wer würfeln darf (die Reservierer), und wertet die Würfe aus."]
            end
            r.btnAction.tooltipTitle = r.btnAction:GetText()
            r.btnAction:SetEnabled(canStart)

            -- Voller Name auf dem Knopf, damit bei gleichen Vornamen klar ist, wer das Item bekommt
            if e.awarded or not e.winner then
                r.btnAward:SetText(L["Vergeben"])
            elseif e.giveFailed then
                r.btnAward:SetText(L["Erneut: "] .. e.winner)
            else
                r.btnAward:SetText(L["An "] .. e.winner)
            end
            r.btnAward:SetWidth(math.max(100, math.min(130, math.ceil(r.btnAward:GetFontString():GetStringWidth()) + 24)))
            r.btnAward.tooltipTitle = L["Vergeben"]
            r.btnAward.tooltip = (e.giveFailed and (L("Letzter Versuch: %s.", e.giveFailed) .. " ") or "")
                .. (e.winner and (L["Gibt das Item per Plündermeister direkt an "] .. e.winner .. ".") or L["Wird aktiv, sobald ein Gewinner feststeht."])
            if e.belowThreshold then
                r.btnAward.tooltip = L["Liegt unter der Plündergrenze: Das Spiel lässt es nicht per Plündermeister zuteilen. Der Gewinner plündert es selbst, oder du senkst die Grenze."]
            end
            r.btnAward:SetEnabled(e.winner ~= nil and not e.awarded and not e.looted and not e.pending and not e.otherCorpse and not e.belowThreshold)
            r:Show()
        elseif lootRows[i] then
            lootRows[i].entry = nil
            lootRows[i]:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #items * ROW_H))
    LC:UpdateLootStatus()
end


U.CreateLootPage, U.RefreshLoot = CreateLootPage, RefreshLoot
