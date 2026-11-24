-- Light Council – Hauptfenster, Seite: Meine Reservierung
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
local AttachItemSearch, ScrollToRow = U.AttachItemSearch, U.ScrollToRow
local ITEM_ROW, BOSS_W = U.ITEM_ROW, U.BOSS_W
local function SelectTab(key) return U.SelectTab(key) end

------------------------------------------------------------------------
-- Seite: Meine Reservierung (für alle Raider)
------------------------------------------------------------------------
local myBossButtons, myItemRows = {}, {}

------------------------------------------------------------------------
-- Auswahl pro Raid (gemeinsam für „Meine Reservierung“ und „Gear-Sets → Mein Set“)
------------------------------------------------------------------------
U.resSel = U.resSel or {}

-- Aktuelle (noch nicht gespeicherte) Auswahl eines Raids; startet mit der gespeicherten bzw. beantragten Reservierung
local function ResSel(raidKey)
    local sel = U.resSel[raidKey]
    if not sel then
        local rec = LC:GetReservation(raidKey)
        local init = (rec and rec.pending and rec.pending.items) or (rec and rec.items) or {}
        sel = { unpack(init) }
        U.resSel[raidKey] = sel
    end
    return sel
end

local function ResSelected(raidKey, id)
    for _, s in ipairs(ResSel(raidKey)) do if s == id then return true end end
    return false
end

-- Item an-/abwählen. Rückgabe: ok, Meldung (nur bei Problemen)
local function ResToggle(raidKey, id, on)
    local sel = ResSel(raidKey)
    for k, s in ipairs(sel) do
        if s == id then
            if not on then table.remove(sel, k) end
            return true
        end
    end
    if not on then return true end
    if #sel >= LC:MaxReserves() then
        return false, H.warn .. L["Du kannst höchstens "] .. LC:MaxReserves() .. L[" Items pro Raid reservieren.|r"]
    end
    sel[#sel + 1] = id
    return true
end

-- Zustand: changed (Auswahl weicht ab), locked (schon gespeichert), pending (Änderung beantragt)
local function ResState(raidKey)
    local rec = LC:GetReservation(raidKey)
    local sel = ResSel(raidKey)
    local locked = rec and (rec.rev or 0) > 0
    local changed = not (rec and LC.SameItems(rec.items or {}, sel))
    if not rec and #sel == 0 then changed = false end
    return changed, locked, rec and rec.pending ~= nil, rec
end

-- Erstes Speichern: Bestätigungsdialog. from = Seite, auf der die Meldung erscheint
local function ResConfirm(raidKey, from)
    local items = ResSel(raidKey)
    local dlg = StaticPopup_Show("LIGHTCOUNCIL_CONFIRM_RESERVE", LC:ItemListText(items))
    if dlg then dlg.data = { raid = raidKey, items = { unpack(items) }, from = from or "myres" } end
end

U.ResSel, U.ResSelected, U.ResToggle, U.ResState, U.ResConfirm = ResSel, ResSelected, ResToggle, ResState, ResConfirm

local function CreateMyResPage(p)
    local _, title, desc = PageHeader(p, L["Meine Reservierung"], L["Wähle bis zu "] .. LC:MaxReserves() .. L[" Items pro Raid. Nach dem Speichern ist deine Wahl gesperrt – Änderungen nur mit Freigabe des Councils."])
    desc:SetWidth(CW - 420)   -- rechts sitzen „Aus Gear-Set übernehmen“ und „Quelle“
    local y = math.ceil(title:GetStringHeight() + 5 + desc:GetStringHeight() + 16)
    p.desc = desc
    p.sel = U.resSel

    p.sourceBtn = SourceButton(p)
    p.sourceBtn:SetPoint("TOPRIGHT", 0, 0)

    -- Aus dem Gear-Set übernehmen (nur wenn der Council das eingeschaltet hat)
    p.fromSet = T:Button(p, L["Aus Gear-Set übernehmen"], 200, 30, "primary", function()
        local raid = p.raid
        if not raid then return end
        local want = LC:GearSetItemsForRaid(raid)
        if #want == 0 then
            p.msgText = H.warn .. L["In deinem aktiven Gear-Set fehlt dir nichts, was in diesem Raid droppt.|r"]
        else
            local sel = ResSel(raid.key)
            wipe(sel)
            for i = 1, math.min(#want, LC:MaxReserves()) do sel[i] = want[i] end
            p.msgText = H.good .. L["Auswahl aus deinem Gear-Set übernommen (wichtige zuerst). Prüfen und speichern.|r"]
        end
        LC:RefreshUI()
    end)
    p.fromSet:SetPoint("RIGHT", p.sourceBtn, "LEFT", -8, 0)
    Tip(p.fromSet, L["Aus Gear-Set übernehmen"], L["Wählt die wichtigsten Items aus deinem aktiven Gear-Set, die dir noch fehlen und in diesem Raid droppen."])

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
    -- Itemsuche über alle Raids (Name oder Item-ID)
    p.search = T:Input(bossCol, BOSS_W - 24, 28)
    p.search:SetPoint("TOPLEFT", 12, -10)
    p.search:SetPlaceholder(L["Item suchen (Name oder ID)"])
    local bsf, bcontent = T:Scroll(bossCol)
    bsf:SetPoint("TOPLEFT", 0, -48)
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
    p.manualInput:SetPlaceholder(L["Shift-Klick, Item-ID oder Name"])
    AcceptLinks(p.manualInput)
    local addBtn = T:Button(p.manual, L["Auswählen"], 120, 30, "default", function()
        local raid = p.raid
        if not raid then return end
        local sel = ResSel(raid.key)
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
    p.reason:SetPlaceholder(L["Begründung für die Änderung (Pflicht)"])
    p.reason:SetMaxLetters(120)
    p.clearSel = T:Button(p, L["Auswahl leeren"], 130, 34, "ghost", function()
        if p.raid then wipe(ResSel(p.raid.key)) end
        LC:RefreshUI()
    end)
    p.action = T:Button(p, L["Reservierung speichern"], 190, 34, "primary", function()
        local raid = p.raid
        if not raid then return end
        local items = ResSel(raid.key)
        local rec = LC:GetReservation(raid.key)
        if rec and (rec.rev or 0) > 0 then
            local ok, msg = LC:RequestReservationChange(raid.key, items, p.reason:GetText())
            p.msgText = (ok and H.good or H.bad) .. msg .. "|r"
            if ok then p.reason:SetText("") end
            LC:RefreshUI()
        else
            ResConfirm(raid.key, "myres")
        end
    end)
    p.action:SetPoint("BOTTOMRIGHT", 0, 8)
    p.clearSel:SetPoint("RIGHT", p.action, "LEFT", -8, 0)
    p.msg = T:Text(p, 12, C.muted, "RIGHT")
    p.msg:SetPoint("BOTTOMRIGHT", p.action, "TOPRIGHT", 0, 8)
    p.msg:SetWidth(CW)
    p.msg:SetWordWrap(false)

    -- Suche: springt zu Raid und Boss und hebt das Item hervor (Reservieren dann per Häkchen).
    -- Items, die in keiner Loot-Quelle stehen, kommen direkt in die Auswahl des aktuellen Raids.
    local function AddToSelection(id)
        local raid = p.raid
        if not raid then return end
        local sel = ResSel(raid.key)
        for _, s in ipairs(sel) do if s == id then return end end
        if #sel >= LC:MaxReserves() then
            p.msgText = H.warn .. L["Du kannst höchstens "] .. LC:MaxReserves() .. L[" Items pro Raid reservieren.|r"]
        else
            sel[#sel + 1] = id
            p.msgText = H.good .. L("%s ausgewählt – mit „Reservierung speichern“ bestätigen.", LC:ItemLink(id)) .. "|r"
        end
    end
    AttachItemSearch(p.search, function(res)
        if res.raidIdx then
            p.raidIdx, p.bossIdx = res.raidIdx, res.bossIdx
            p.highlight, p.scrollTo = res.id, true
        else
            AddToSelection(res.id)
        end
        LC:RefreshUI()
    end, 420)
    AttachItemSearch(p.manualInput, function(res)
        AddToSelection(res.id)
        LC:RefreshUI()
    end)

    StaticPopupDialogs["LIGHTCOUNCIL_CONFIRM_RESERVE"] = {
        text = L["Light Council: Diese Items reservieren?\n\n%s\n\nDanach ist deine Reservierung gesperrt. Änderungen gehen nur noch mit Freigabe des Councils."],
        button1 = L["Reservieren"], button2 = CANCEL,
        OnAccept = function(self, data)
            local ok, msg = LC:SubmitReservation(data.raid, data.items)
            local pg = pages[data.from or "myres"] or pages.myres
            pg.msgText = (ok and H.good or H.bad) .. msg .. "|r"
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
    r.name:SetWidth(p.itemsW - 290)
    r.name:SetWordWrap(false)
    r.sub = T:Text(r, 11, C.muted)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetWidth(p.itemsW - 290)
    r.sub:SetWordWrap(false)
    r.check = T:Check(r, L["Reservieren"])
    r.check:SetPoint("RIGHT", -190, 0)
    -- Ins aktive Gear-Set aufnehmen bzw. wieder entfernen
    r.setBtn = T:Button(r, L["+ Set"], 76, 26, "ghost", function()
        if LC:IsInMySet(r.itemID) then
            LC:RemoveFromGearSet(r.itemID)
        else
            local ok, msg = LC:AddToGearSet({ r.itemID })
            if msg then p.msgText = (ok and H.good or H.warn) .. msg .. "|r" end
        end
        LC:RefreshUI()
    end)
    r.setBtn:SetPoint("RIGHT", -8, 0)
    r.setBtn.tooltipTitle = L["Gear-Set"]
    r.setBtn.tooltip = L["Angehakt: Das Item ist in deinem aktiven Set. Pro Slot ein Item – ein neues ersetzt das bisherige."]

    -- Nur Council/Leitung: Council-Item (zweite Reihe rechts)
    r.council = T:Check(r, L["Council"])
    r.council:SetScript("OnClick", function(self)
        LC:SetCouncilItem(r.itemID, self:GetChecked())
        LC:RefreshUI()
    end)
    r.council:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Council-Item"], 1, 1, 1)
        GameTooltip:AddLine(L["Angehakt: Bei diesem Item entscheidet der Council, wer würfeln darf."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    r.council:HookScript("OnLeave", GameTooltip_Hide)
    r.check:SetScript("OnClick", function(self)
        local sel = ResSel(p.raid.key)
        if self:GetChecked() then
            if #sel >= LC:MaxReserves() then
                self:SetChecked(false)
                p.msgText = H.warn .. L["Du kannst höchstens "] .. LC:MaxReserves() .. L[" Items pro Raid reservieren.|r"]
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
    p.desc:SetText(L["Wähle bis zu "] .. max .. L[" Items pro Raid. Nach dem Speichern ist deine Wahl gesperrt – Änderungen nur mit Freigabe des Councils."])

    p.sourceBtn:Update()
    p.fromSet:SetShown(LC:SetReserveEnabled() and LC:GetActiveSet() ~= nil)
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
        if mine and #(mine.items or {}) > 0 then tag = L["  |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"] end
        labels[i] = r.name .. tag
    end
    p.chipBar:SetItems(labels, p.raidIdx, function(i) p.raidIdx, p.bossIdx = i, 1 LC:RefreshUI() end)
    local raid = raids[p.raidIdx]
    p.raid = raid

    -- eigene Reservierung + Auswahl
    local rec = LC:GetReservation(raid.key)
    local locked = rec and (rec.rev or 0) > 0
    local sel = ResSel(raid.key)
    local selSet = {}
    for _, id in ipairs(sel) do selSet[id] = true end

    p.stTitle:SetText(L["Deine Reservierung  ·  "] .. raid.name)
    if locked then
        p.stState:SetText(L["GESPERRT"])
        p.stState:SetTextColor(unpack(C.good))
        p.stStripe:SetVertexColor(unpack(C.good))
    elseif rec and #(rec.items or {}) > 0 then
        p.stState:SetText(L["WARTET AUF BESTÄTIGUNG"])
        p.stState:SetTextColor(unpack(C.warn))
        p.stStripe:SetVertexColor(unpack(C.warn))
    else
        p.stState:SetText(L["NOCH NICHTS RESERVIERT"])
        p.stState:SetTextColor(unpack(C.muted))
        p.stStripe:SetVertexColor(unpack(C.accent))
    end
    p.stItems:SetText(ItemIcons(rec and rec.items, 18))
    if rec and rec.pending then
        p.stPending:SetText(H.warn .. L["Änderung beantragt:|r "] .. LC:ItemListText(rec.pending.items) .. H.muted .. L["  – wartet auf den Council|r"])
    elseif locked then
        p.stPending:SetText(L["Ändern: andere Items anhaken, Begründung eintragen und „Änderung beantragen“ klicken."])
    else
        p.stPending:SetText(L["Items unten anhaken und „Reservierung speichern“ klicken."])
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
            local sub = (n > 0) and (n .. (n == 1 and L[" Reservierung"] or L[" Reservierungen"])) or L["Noch nicht reserviert"]
            local chance = LC:GetDropChance(boss, id)
            if chance then sub = H.good .. chance .. L[" %|r Drop   ·   "] .. sub end
            if LC:IsCouncilItem(id) then sub = sub .. "   ·   " .. H.accent .. L["Council-Item|r"] end
            local inSet = LC:IsInMySet(id)
            local isUp = not inSet and LC:IsUpgradeInMySet(id)
            if inSet or isUp then
                local info = LC:GearSetRank(LC:PlayerName(), id)
                local tag = (info and info.owned) and L["Set: hast du"]
                    or ((info and info.important) and (LC.STAR .. " " .. L["Im Set"]))
                    or (isUp and (LC.UPGRADE .. L["Upgrade"]))
                    or L["Im Set"]
                sub = H.good .. tag .. "|r   ·   " .. sub
            end
            r.setBtn:SetText(inSet and L["Im Set"] or L["+ Set"])
            -- Layout: normal eine Reihe; für Council/Leitung zwei (Reservieren + Set / Council)
            local manage = LC:CanManageLoot()
            local dy = manage and 11 or 0
            r.check:ClearAllPoints()
            r.check:SetPoint("RIGHT", -190, dy)
            r.setBtn:ClearAllPoints()
            r.setBtn:SetPoint("RIGHT", -8, dy)
            r.setBtn:SetHeight(manage and 20 or 26)
            r.council:SetShown(manage)
            if manage then
                r.council:ClearAllPoints()
                r.council:SetPoint("RIGHT", -190, -11)
                r.council:SetChecked(LC:IsCouncilItem(id))
            end
            r.sub:SetText(sub)
            r.check:SetChecked(selSet[id] == true)
            r.check:SetEnabled(selSet[id] == true or not full)
            T:SetBorder(r, (id == p.highlight) and C.accent or C.border)
            if id == p.highlight and p.scrollTo then
                p.scrollTo = nil
                ScrollToRow(p.itemScroll, i, ITEM_ROW)
            end
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
            p.manualText:SetText(L["Die gewählte Loot-Quelle liefert hier keine Itemliste. Oben rechts unter „Quelle“ wechseln oder AtlasLoot bzw. Naowh Forever installieren.\nAlternativ: Items per Shift-Klick (z. B. aus dem Chat) oder per Item-ID zu deiner Auswahl hinzufügen."])
        else
            p.manualText:SetText(L["Für diese Instanz ist in der Loot-Quelle noch kein Loot eingetragen (Loot folgt).\nFüge Items per Shift-Klick oder Item-ID zu deiner Auswahl hinzu."])
        end
    end

    -- Fußleiste
    local changed = not (rec and LC.SameItems(rec.items or {}, sel))
    p.counter:SetText(L["Ausgewählt: "] .. (full and H.accentLt or "") .. #sel .. L[" von "] .. max .. (full and "|r" or ""))
    p.reason:SetShown(locked and changed and not (rec and rec.pending))
    if locked then
        p.action:SetText(L["Änderung beantragen"])
        p.action:SetEnabled(changed and #sel > 0 and not rec.pending)
    else
        p.action:SetText(L["Reservierung speichern"])
        p.action:SetEnabled(#sel > 0 and changed)
    end
    p.msg:SetText(p.msgText or "")
end


U.CreateMyResPage, U.RefreshMyRes = CreateMyResPage, RefreshMyRes
