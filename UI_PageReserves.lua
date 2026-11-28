-- Light Council – Hauptfenster, Seite: Reservierungen
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
-- Seite: Reservierungen (Übersicht und Verwaltung durch den Council)
------------------------------------------------------------------------
local resRows, pendRows = {}, {}

-- Fenster: Raidtage und Erinnerung einstellen (Council)
local daysFrame
local function ShowRaidDaysFrame()
    if not daysFrame then
        local FW = CW + 32
        local f = T:Window("LightCouncilRaidDaysFrame", FW, 390, L["Raidtage & Erinnerung"],
            L["An Raidtagen werden alle mit Light Council beim Einloggen ans Reservieren erinnert"])
        f:SetFrameStrata("DIALOG")
        f.sel = {}

        local l1 = T:Text(f, 13, C.text, "LEFT", nil, true)
        l1:SetPoint("TOPLEFT", 16, -54)
        l1:SetText(L["An welchen Tagen raidet ihr?"])
        f.dayBtns = {}
        local prev
        for _, w in ipairs(LC.WEEKDAYS) do
            local b = T:Button(f, L[w.short], 64, 34, "default", function(self)
                f.sel[w.wday] = not f.sel[w.wday] or nil
                f:Paint()
            end)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -82) end
            b.tooltipTitle = L[w.long]
            b.tooltip = L["Anklicken zum Ein- oder Ausschalten."]
            b.wday = w.wday
            f.dayBtns[#f.dayBtns + 1] = b
            prev = b
        end

        local l2 = T:Text(f, 13, C.text, "LEFT", nil, true)
        l2:SetPoint("TOPLEFT", 16, -136)
        l2:SetText(L["Für welchen Raid sollen sie reservieren?"])
        local l2d = T:Text(f, 11, C.muted)
        l2d:SetPoint("LEFT", l2, "RIGHT", 10, -1)
        l2d:SetText(L["„Jeder Raid“: Erinnerung, solange jemand gar nichts reserviert hat."])
        f.chips = ChipBar(f)
        f.chips:SetPoint("TOPLEFT", 16, -162)

        -- Gear-Sets: Reservieren aus dem Set erlauben (Randoms ohne Set reservieren weiter normal)
        f.setReserve = T:Check(f, L["Reservieren aus dem Gear-Set anbieten"])
        f.setReserve:SetPoint("BOTTOMLEFT", 16, 74)
        local srd = T:Text(f, 11, C.muted)
        srd:SetPoint("LEFT", f.setReserve.label, "RIGHT", 10, 0)
        srd:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        srd:SetWordWrap(false)
        srd:SetText(L["Raider bekommen den Knopf „Aus Gear-Set übernehmen“. Wer kein Set hat, reserviert wie gewohnt."])

        f.msg = T:Text(f, 12, C.muted)
        f.msg:SetPoint("BOTTOMLEFT", 160, 26)
        f.msg:SetWidth(FW - 180)
        f.msg:SetWordWrap(false)
        local save = T:Button(f, L["Speichern"], 130, 34, "primary", function()
            local days = {}
            for _, w in ipairs(LC.WEEKDAYS) do
                if f.sel[w.wday] then days[#days + 1] = w.wday end
            end
            LC:SetRaidDays(days, f.raidKey, f.setReserve:GetChecked() and true or false)
            f.msg:SetText(H.good .. L["Gespeichert und an alle Addon-Nutzer in Gilde/Raid geschickt.|r"])
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
            local labels, keys, selected = { L["Jeder Raid"] }, { "" }, 1
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
    f.setReserve:SetChecked(LC.db.config.setReserve == true)
    f.msg:SetText("")
    f:Paint()
    f:Show()
end

-- Erinnerung am Raidtag (für alle). closesAt: Schließzeit; inRaid = Erinnerung der Raidleitung im Raid
local reminder
function LC:ShowRaidDayReminder(raidKey, closesAt, inRaid)
    if not reminder then
        local f = T:Window("LightCouncilReminderFrame", 440, 190, L["Heute ist Raidtag!"], L["Light Council"])
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
        f.go = T:Button(f, L["Jetzt reservieren"], 160, 32, "primary", function()
            f:Hide()
            LC:OpenReservation(f.raidKey)
        end)
        f.go:SetPoint("BOTTOMRIGHT", -16, 16)
        local later = T:Button(f, L["Später"], 100, 32, "ghost", function() f:Hide() end)
        later:SetPoint("RIGHT", f.go, "LEFT", -8, 0)
        reminder = f
    end
    local f = reminder
    f.raidKey = raidKey
    f.title:SetText(inRaid and L["Noch nicht reserviert!"] or L["Heute ist Raidtag!"])
    local raidName
    if raidKey and raidKey ~= "" then
        for _, r in ipairs(self:GetLootDB() or {}) do
            if r.key == raidKey then raidName = r.name break end
        end
        raidName = raidName or raidKey
    end
    f.text:SetText((raidName and (L["Du hast für "] .. H.accentLt .. raidName .. L["|r noch nichts reserviert."])
        or L["Du hast noch keine Items reserviert."])
        .. "\n" .. (closesAt and (H.warn .. L("Die Reservierungen schließen um %s Uhr.", self:ClockText(closesAt)) .. "|r")
            or inRaid and (H.warn .. L["Die Raidleitung bittet dich, jetzt zu reservieren."] .. "|r")
            or (H.muted .. L["Reservier am besten schon jetzt – im Raid wird dann nur noch eingesammelt.|r"])))
    f:Show()
    if inRaid and RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, L("Light Council: Du hast für %s noch nichts reserviert!", raidName or "?"), ChatTypeInfo["RAID_WARNING"])
    end
    if SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
end

local function CreateReservesPage(p)
    local y, ht, hd = PageHeader(p, L["Reservierungen"], L["Alle Reservierungen im Überblick. Der Council bestätigt automatisch, entscheidet über Änderungsanträge und trägt für Spieler ohne Addon ein."])
    -- Beschreibung schmaler, damit die drei Knöpfe oben rechts nicht überlappen
    hd:SetWidth(CW - 420)
    y = math.ceil(ht:GetStringHeight() + 5 + hd:GetStringHeight() + 16)

    p.btnRound = T:Button(p, L["Neue Runde"], 130, 30, "danger", function()
        if p.raid then
            local dlg = StaticPopup_Show("LIGHTCOUNCIL_NEW_ROUND", p.raid.name)
            if dlg then dlg.data = p.raid.key end
        end
    end)
    p.btnRound:SetPoint("TOPRIGHT", 0, 0)
    p.btnRound.tooltipTitle = L["Neue Runde"]
    p.btnRound.tooltip = L["Löscht alle Reservierungen dieses Raids, z. B. für eine neue Raid-ID. Alle können danach neu reservieren."]
    p.btnSync = T:Button(p, L["Abgleichen"], 120, 30, "default", function()
        LC:RequestResSync(true)
        p.msg:SetText(L["Abgleich angefordert …"])
    end)
    p.btnSync:SetPoint("RIGHT", p.btnRound, "LEFT", -8, 0)
    p.btnSync.tooltipTitle = L["Abgleichen"]
    p.btnSync.tooltip = L["Holt den aktuellen Stand der Reservierungen von den Council-Mitgliedern, die gerade online sind."]
    p.btnDays = T:Button(p, L["Raidtage"], 140, 30, "default", function() ShowRaidDaysFrame() end)
    p.btnDays:SetPoint("RIGHT", p.btnSync, "LEFT", -8, 0)
    p.btnDays.tooltipTitle = L["Raidtage & Erinnerung"]
    p.btnDays.tooltip = L["Lege eure Raidtage fest. An diesen Tagen erinnert das Addon alle beim Einloggen, schon vorab zu reservieren."]
    StaticPopupDialogs["LIGHTCOUNCIL_NEW_ROUND"] = {
        text = L["Light Council: Neue Runde für %s starten?\n\nAlle Reservierungen dieses Raids werden gelöscht."],
        button1 = YES, button2 = NO,
        OnAccept = function(self, raidKey)
            local ok, msg = LC:NewReserveRound(raidKey)
            pages.reserves.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }

    p.chipBar = ChipBar(p)
    p.chipBar:SetPoint("TOPLEFT", 0, -y)

    -- Reservierungen schließen (Council, Raidleiter, Plündermeister)
    p.closeCard = Card(p, 44)
    p.closeCard:SetPoint("TOPLEFT", p.chipBar, "BOTTOMLEFT", 0, -14)
    p.closeCard:SetWidth(CW)
    p.closeText = T:Text(p.closeCard, 12, C.text, "LEFT")
    p.closeText:SetPoint("LEFT", 16, 0)
    p.closeText:SetWidth(CW - 200)
    p.closeText:SetWordWrap(false)
    p.btnClose = T:Button(p.closeCard, L["Schließen …"], 160, 30, "primary", function(self)
        local key = p.raid and p.raid.key
        if not key then return end
        local function Do(mode, min)
            local ok, msg = LC:SetResClose(key, mode, min)
            LC:Print((ok and H.good or H.bad) .. msg .. "|r")
            p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        end
        local state = LC:ResCloseState(key)
        local e = {}
        for _, m in ipairs({ 5, 10, 15, 30 }) do
            e[#e + 1] = { text = L("In %d Min. schließen", m), func = function() Do("timer", m) end }
        end
        e[#e + 1] = { text = L["Jetzt schließen"], disabled = (state == "closed"), func = function() Do("now") end }
        e[#e + 1] = { text = L["Wieder öffnen"], disabled = (state == "open"), func = function() Do("open") end }
        e[#e + 1] = { text = "-" }
        e[#e + 1] = { text = L["Fehlende jetzt erinnern"], disabled = not IsInRaid(), func = function() Do("remind") end }
        U.ShowMenu(self, e)
    end)
    p.btnClose:SetPoint("RIGHT", -8, 0)
    Tip(p.btnClose, L["Reservierungen schließen"], L["Mit Zeit: alle im Raid ohne Reservierung werden sofort und eine Minute vorher erinnert. Beim Schließen wird die Anwesenheit erfasst. Danach nimmt der Council keine Reservierungen und Änderungsanträge mehr an (Eintragen durch den Council geht weiter)."])

    -- Offene Änderungsanträge
    p.pendCard = Card(p, 60)
    p.pendCard:SetPoint("TOPLEFT", p.closeCard, "BOTTOMLEFT", 0, -14)
    p.pendCard:SetWidth(CW)
    local pt = T:Text(p.pendCard, 14, C.text, "LEFT", nil, true)
    pt:SetPoint("TOPLEFT", 16, -14)
    pt:SetText(L["Offene Änderungsanträge"])
    p.pendInfo = T:Text(p.pendCard, 12, C.muted, "RIGHT")
    p.pendInfo:SetPoint("TOPRIGHT", -16, -15)

    -- Tabelle
    p.tableHead = CreateFrame("Frame", nil, p)
    p.tableHead:SetSize(CW, 20)
    for i, label in ipairs({ L["SPIELER"], L["RESERVIERT"], L["STATUS"] }) do
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
    mt:SetText(L["Für Spieler eintragen oder ändern (Council)"])
    p.msg = T:Text(man, 12, C.muted, "RIGHT")
    p.msg:SetPoint("TOPRIGHT", -16, -13)
    p.msg:SetWidth(CW - 360)
    p.msg:SetWordWrap(false)
    p.manName = T:Input(man, 220, 30)
    p.manName:SetPoint("BOTTOMLEFT", 16, 14)
    p.manName:SetPlaceholder(L["Vorname Nachname"])
    p.manItems = T:Input(man, CW - 400, 30)
    p.manItems:SetPoint("LEFT", p.manName, "RIGHT", 8, 0)
    p.manItems:SetPlaceholder(L["Items per Shift-Klick oder IDs – leer = löschen"])
    AcceptLinks(p.manItems)
    p.manBtn = T:Button(man, L["Eintragen"], 130, 30, "primary", function()
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
    r.no = T:Button(r, L["Ablehnen"], 110, 28, "danger", function()
        local ok, msg = LC:DecideChange(p.raid.key, r.player, false)
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
    end)
    r.no:SetPoint("RIGHT", -8, 0)
    r.yes = T:Button(r, L["Freigeben"], 110, 28, "primary", function()
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
    r.edit = T:Button(r, L["Bearbeiten"], 100, 26, "ghost", function()
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
                .. "   " .. H.muted .. "„" .. (rec.pending.reason or "") .. L["“|r"])
            local own = LC:IsMe(rec.name)
            r.yes:SetEnabled(isCouncil and not own)
            r.no:SetEnabled(isCouncil and not own)
            r:Show()
        elseif pendRows[i] then
            pendRows[i]:Hide()
        end
    end
    p.pendCard:SetHeight(40 + #pend * 44 + 4)
    p.pendInfo:SetText(isCouncil and (#pend .. L[" offen"]) or L["nur der Council entscheidet"])
    p.tableHead:ClearAllPoints()
    if #pend > 0 then
        p.tableHead:SetPoint("TOPLEFT", p.pendCard, "BOTTOMLEFT", 0, -14)
    else
        p.tableHead:SetPoint("TOPLEFT", p.closeCard, "BOTTOMLEFT", 0, -14)
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
                r.state:SetText(H.warn .. L["Antrag offen|r"])
            elseif (rec.rev or 0) > 0 then
                r.state:SetText(H.good .. L["gesperrt|r"] .. ((rec.rev or 0) > 1 and (H.muted .. "  (" .. (rec.rev - 1) .. L["× geändert)|r"]) or ""))
            else
                r.state:SetText(H.warn .. L["wartet|r"])
            end
            r.edit:SetShown(isCouncil)
            r:Show()
        elseif resRows[i] then
            resRows[i]:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #list * 34))
    p.empty:SetShown(#list == 0)
    p.empty:SetText(L["Noch keine Reservierungen für "] .. raid.name .. L[".\nRaider reservieren im Addon unter „Meine Reservierung“."])

    -- Stand: offen / schließt um / geschlossen, dazu wer im Raid noch nicht reserviert hat
    local cstate, cinfo = LC:ResCloseState(raid.key)
    local st
    if cstate == "closed" then
        st = H.bad .. L["geschlossen"] .. "|r" .. ((cinfo and cinfo.by) and (H.muted .. "  " .. L("(%s, %s Uhr)", cinfo.by, LC:ClockText(cinfo.at)) .. "|r") or "")
    elseif cstate == "timer" then
        st = H.warn .. L("schließen um %s Uhr", LC:ClockText(cinfo.at)) .. "|r"
    else
        st = H.good .. L["offen"] .. "|r"
    end
    if IsInRaid() then
        local miss = LC:MissingReservers(raid.key)
        if #miss == 0 then
            st = st .. H.muted .. "   ·   " .. L["alle im Raid haben reserviert"] .. "|r"
        else
            local names = {}
            for i = 1, math.min(6, #miss) do names[i] = miss[i].name:match("^(%S+)") or miss[i].name end
            st = st .. H.muted .. "   ·   " .. L("%d im Raid ohne Reservierung:", #miss) .. " " .. table.concat(names, ", ") .. ((#miss > 6) and " …" or "") .. "|r"
        end
    end
    p.closeText:SetText(L["Reservierungen: "] .. st)
    p.btnClose:SetEnabled(LC:CanCloseReserves())

    p.manCard:SetShown(isCouncil)
    p.btnRound:SetEnabled(isCouncil)
    p.btnDays:SetEnabled(isCouncil)
    local nDays = #(LC:GetRaidDays())
    p.btnDays:SetText((nDays > 3) and (L["Raidtage: "] .. nDays .. L[" Tage"]) or (L["Raidtage: "] .. LC:RaidDaysText()))
end


U.CreateReservesPage, U.RefreshReserves = CreateReservesPage, RefreshReserves
