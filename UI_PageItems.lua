-- Light Council – Hauptfenster, Seite: Raid-Loot
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
-- Seite: Raid-Loot – Council-Items und Prio per Klick (Daten aus AtlasLoot)
------------------------------------------------------------------------
local browseRows, markedRows, bossButtons, raidChips = {}, {}, {}, {}
local ITEM_ROW = 50
local BOSS_W = 230

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

    r.prio = T:Button(r, L["Prio festlegen"], 120, 30, "default", function() LC:OpenPrioEditor(r.itemID) end)
    r.prio:SetPoint("RIGHT", -8, 0)
    r.prio.tooltipTitle = L["Prio festlegen"]
    r.prio.tooltip = L["Spieler in der gewünschten Reihenfolge anklicken. Die Prio wird im Loot-Fenster angezeigt und beim Würfeln angesagt."]
    if withRemove then
        r.remove = T:Button(r, L["Entfernen"], 96, 30, "ghost", function()
            LC:SetCouncilItem(r.itemID, false)
            LC:RefreshUI()
        end)
        r.remove:SetPoint("RIGHT", r.prio, "LEFT", -6, 0)
    else
        r.council = T:Check(r, L["Council"])
        r.council:SetPoint("RIGHT", r.prio, "LEFT", -92, 0)
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
        parts[#parts + 1] = H.accentLt .. L["Prio:|r "] .. table.concat(prio, " > ")
    else
        parts[#parts + 1] = L["Keine Prio"]
    end
    if nRes > 0 then parts[#parts + 1] = nRes .. (nRes == 1 and L[" Reservierung"] or L[" Reservierungen"]) end
    if chance then table.insert(parts, 1, H.good .. chance .. L[" %|r Drop"]) end
    r.sub:SetText(table.concat(parts, "   ·   "))
    r.prio:SetText((prio and #prio > 0) and L["Prio ändern"] or L["Prio festlegen"])
    if r.council then r.council:SetChecked(LC:IsCouncilItem(itemID)) end
end

local function CreateItemsPage(p)
    local y = PageHeader(p, L["Raid-Loot"], L["Council-Items markieren und Prio festlegen – direkt aus AtlasLoot oder Naowh Forever, ohne IDs abzutippen."])
    p.sourceBtn = SourceButton(p)
    p.sourceBtn:SetPoint("TOPRIGHT", 0, 0)
    p.mode = "browse"
    p.seg = Segmented(p, {
        { key = "browse", label = L["Loot durchsuchen"], width = 180 },
        { key = "marked", label = L["Council-Items"], width = 170 },
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
    bt:SetText(L["Bosse"])
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
    ie:SetText(L["Loot folgt"])
    local ies = T:Text(p.itemsEmpty, 12, C.muted)
    ies:SetPoint("TOPLEFT", ie, "BOTTOMLEFT", 0, -8)
    ies:SetWidth(p.itemsW - 36)
    ies:SetSpacing(3)
    ies:SetText(L["AtlasLoot hat für diesen Boss noch keine Items eingetragen. Sobald AtlasLoot aktualisiert wird, erscheinen sie hier automatisch.\n"]
        .. L["Bis dahin: Unter „Council-Items“ ein gedroppetes Item per Shift-Klick hinzufügen."])

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
    al:SetText(L["Item manuell hinzufügen"])
    p.input = T:Input(add, CW - 170, 30)
    p.input:SetPoint("TOPLEFT", al, "BOTTOMLEFT", 0, -8)
    p.input:SetPlaceholder(L["Shift-Klick auf ein Item oder Item-ID eintippen"])
    AcceptLinks(p.input)
    local function DoAdd()
        local ok, msg = LC:AddCouncilItems(p.input:GetText())
        p.msg:SetText((ok and H.good or H.bad) .. msg .. "|r")
        if ok then p.input:SetText("") end
        LC:RefreshUI()
    end
    p.input:SetScript("OnEnterPressed", function(self) DoAdd() self:ClearFocus() end)
    local addBtn = T:Button(add, L["Hinzufügen"], 120, 30, "primary", DoAdd)
    addBtn:SetPoint("LEFT", p.input, "RIGHT", 10, 0)

    local msf, mcontent = T:Scroll(marked)
    msf:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -14)
    msf:SetPoint("BOTTOMRIGHT", -10, 46)
    p.markedList = mcontent
    p.markedEmpty = T:Text(marked, 12, C.muted, "CENTER")
    p.markedEmpty:SetPoint("TOP", msf, "TOP", 0, -30)
    p.markedEmpty:SetWidth(CW - 60)
    p.markedEmpty:SetText(L["Noch keine Council-Items.\nIn „Raids durchsuchen“ einfach das Häkchen „Council“ beim Item setzen."])

    local clear = T:Button(marked, L["Alle entfernen"], 140, 32, "danger", function() StaticPopup_Show("LIGHTCOUNCIL_CLEAR_ITEMS") end)
    clear:SetPoint("BOTTOMRIGHT", 0, 0)
    StaticPopupDialogs["LIGHTCOUNCIL_CLEAR_ITEMS"] = {
        text = L["Light Council: Alle Council-Items entfernen?"],
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
        raids, err = nil, L["Die gewählte Quelle enthält keine Raids."]
    end
    p.dbError:SetShown(raids == nil)
    p.bossCol:SetShown(raids ~= nil)
    p.itemScroll:SetShown(raids ~= nil)
    if p.itemScroll.bar and raids == nil then p.itemScroll.bar:Hide() end
    if not raids then
        p.itemsEmpty:Hide()
        p.chips:SetItems({}, nil, nil)
        p.dbError.text:SetText(H.warn .. (err or L["Keine Loot-Quelle gefunden."]) .. "|r\n\n"
            .. L["Oben rechts unter „Quelle“ eine andere Quelle wählen – oder Council-Items unter „Council-Items“ per Shift-Klick bzw. Item-ID hinzufügen."])
        return
    end
    p.raidIdx = math.min(p.raidIdx or 1, #raids)
    local labels = {}
    for i, r in ipairs(raids) do
        labels[i] = r.name .. (((r.itemCount or 0) == 0) and ("  " .. H.muted .. L["(Loot folgt)|r"]) or "")
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
    p.seg.buttons.marked:SetText(L["Council-Items ("] .. n .. ")")
    p.browse:SetShown(p.mode == "browse")
    p.marked:SetShown(p.mode == "marked")
    if p.mode == "browse" then RefreshBrowse(p) else RefreshMarked(p) end
end


U.CreateItemsPage, U.RefreshItems = CreateItemsPage, RefreshItems
