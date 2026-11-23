-- Light Council – Hauptfenster, Seite: Loot-Historie
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
-- Seite: Loot-Historie (für alle)
------------------------------------------------------------------------
local HIST_ROW = 44
local HCOLS = { 0, 130, 450, 620 }   -- Datum/Raid, Item, Spieler, Vergabe
local historyRows = {}

local function CreateHistoryPage(p)
    local y = PageHeader(p, L["Loot-Historie"], L["Wer hat wann welches Item bekommen. Jedes vergebene Item wird automatisch eingetragen – bei allen, die Light Council im Raid haben."])
    p.mode = "all"
    p.seg = Segmented(p, {
        { key = "all", label = L["Alle"], width = 90 },
        { key = "mine", label = L["Meine Items"], width = 130 },
    }, function(key)
        p.mode = key
        LC:RefreshUI()
    end)
    p.seg.first:SetPoint("TOPLEFT", 0, -y)
    p.search = T:Input(p, 250, 30)
    p.search:SetPoint("LEFT", p.seg.buttons.mine, "RIGHT", 14, 0)
    p.search:SetPlaceholder(L["Spieler, Item oder Raid suchen"])
    p.search:HookScript("OnTextChanged", function() LC:RefreshUI() end)
    p.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    p.count = T:Text(p, 12, C.muted, "RIGHT")
    p.count:SetPoint("TOPRIGHT", 0, -6)

    local export = T:Button(p, L["Exportieren"], 120, 30, "default", function() LC:ShowHistoryExport(p.lastList or {}) end)
    export:SetPoint("TOPRIGHT", 0, -y)
    Tip(export, L["Exportieren"], L["Die angezeigte Liste als Text – für eine Tabelle (Excel, Google Sheets) oder zum Posten in Discord."])
    local sync = T:Button(p, L["Abgleichen"], 110, 30, "ghost", function() LC:RequestHistorySync(true) end)
    sync:SetPoint("RIGHT", export, "LEFT", -8, 0)
    Tip(sync, L["Abgleichen"], L["Holt fehlende Einträge vom Council – z. B. aus Raids, bei denen du nicht dabei warst. Passiert beim Einloggen auch automatisch."])
    y = y + 32 + 16

    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 0, -y)
    head:SetSize(CW, 18)
    for i, label in ipairs({ L["DATUM / RAID"], L["ITEM"], L["SPIELER"], L["VERGABE"] }) do
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
        text = L["Light Council: Diesen Eintrag aus der Loot-Historie löschen?\n\n%s"],
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
                GameTooltip:AddLine(L["Rechtsklick: Eintrag löschen"], 0.6, 0.6, 0.6)
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
    p.count:SetText((#list == total) and (total .. (total == 1 and L[" Item"] or L[" Items"]))
        or (#list .. L[" von "] .. total .. L[" Items"]))
    if total == 0 then
        p.empty:SetText(L["Noch keine Einträge.\nSobald der Plündermeister ein Item über Light Council vergibt, steht es hier – mit Datum, Raid und Spieler."])
    else
        p.empty:SetText(L["Nichts gefunden."])
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
                how = H.accentLt .. L["Council|r"]
            elseif e.reserved then
                how = L["Reserviert"]
            elseif e.offspec then
                how = L["Off Spec"]
            else
                how = L["Main Spec"]
            end
            if e.roll then how = how .. H.muted .. L["  ·  Wurf "] .. e.roll .. "|r" end
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
        local f = T:Window("LightCouncilExportFrame", 680, 480, L["Loot-Historie exportieren"], L["Strg+C kopiert den markierten Text"])
        f:SetFrameStrata("DIALOG")
        f.format = "csv"
        f.seg = Segmented(f, {
            { key = "csv", label = L["Tabelle (Excel / Sheets)"], width = 220 },
            { key = "discord", label = L["Discord"], width = 110 },
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
    f.hint:SetText(#list .. ((#list == 1) and L[" Eintrag"] or L[" Einträge"])
        .. ((f.format == "csv") and L["  ·  In eine leere Tabelle einfügen (Trennzeichen: Semikolon)"] or L["  ·  Direkt in Discord einfügen"]))
    f.edit:SetText(#list > 0 and self:HistoryExportText(list, f.format) or L["Keine Einträge."])
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end


U.CreateHistoryPage, U.RefreshHistory = CreateHistoryPage, RefreshHistory
