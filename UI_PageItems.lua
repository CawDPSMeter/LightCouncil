-- Light Council – Item-Übersicht (im Tab „Gear-Sets“): Raids → Bosse → Items
--
-- Alle wählen hier per Häkchen Items für ihr aktives Gear-Set. Council und Raidleitung sehen zusätzlich
-- das Häkchen „Council“; für sie gibt es außerdem die Ansicht „Council-Items“.
-- (Bis 0.18 war das der eigene Tab „Raid-Loot“.)
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI
local CW = U.CW
local Card, Tip, AcceptLinks, ChipBar = U.Card, U.Tip, U.AcceptLinks, U.ChipBar
local AttachItemSearch, ScrollToRow = U.AttachItemSearch, U.ScrollToRow
local FilterItems, FavItems, FavStar = U.FilterItems, U.FavItems, U.FavStar
local ITEM_ROW, BOSS_W = U.ITEM_ROW, U.BOSS_W

local browseRows, markedRows, bossButtons = {}, {}, {}

-- Darf ich Council-Items markieren?
-- Council, Raidleitung, Plündermeister – und wer selbst eine Council-Liste eingetragen hat (Leitung beim Einrichten).
-- Council-Items gelten nur beim Plündermeister; für alle anderen sind sie nur eine Anzeige.
function LC:CanManageLoot()
    if self:AmICouncil() or self:IsMasterLooter() then return true end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    return #self:GetCouncilList() > 0
end

------------------------------------------------------------------------
-- Item-Zeile
------------------------------------------------------------------------
-- marked = Zeile der Liste „Council-Items“ (mit „Entfernen“), sonst Übersicht (Set-Häkchen, Council)
local function CreateItemRow(parent, width, marked, setMsg)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(width, ITEM_ROW - 6)
    T:Skin(r, C.panel)
    r.width = width
    r.icon = T:Icon(r, 34)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.name:SetPoint("TOPLEFT", 50, -6)
    r.name:SetWordWrap(false)
    r.sub = T:Text(r, 11, C.muted)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetWordWrap(false)
    -- Favorit: Stern mit Beschriftung in der Leiste rechts (Position in FillItemRow)
    r.star = FavStar(r)

    if marked then
        r.remove = T:Button(r, L["Entfernen"], 96, 28, "ghost", function()
            LC:SetCouncilItem(r.itemID, false)
            LC:RefreshUI()
        end)
        r.remove:SetPoint("RIGHT", -8, 0)
    else
        r.council = T:Check(r, L["Council"])
        r.council:SetPoint("RIGHT", -76, 0)
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

        -- Ins aktive Gear-Set (ein Item pro Slot – ein neues ersetzt das alte)
        r.set = T:Check(r, L["Set"])
        r.set:SetScript("OnClick", function(self)
            if self:GetChecked() then
                local ok, msg = LC:AddToGearSet({ r.itemID })
                if msg then setMsg((ok and H.good or H.warn) .. msg .. "|r") end
            else
                LC:RemoveFromGearSet(r.itemID)
                setMsg(nil)
            end
            LC:RefreshUI()
        end)
        r.set:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Gear-Set"], 1, 1, 1)
            GameTooltip:AddLine(L["Angehakt: Das Item ist in deinem aktiven Set. Pro Slot ein Item – ein neues ersetzt das bisherige."], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        r.set:HookScript("OnLeave", GameTooltip_Hide)

        -- Als Upgrade (zweite Wahl) für den Slot: nicht das beste Item, aber besser als das jetzige
        r.upgrade = T:Check(r, L["Upgrade"])
        r.upgrade:SetPoint("RIGHT", r.set, "LEFT", -78, 0)
        r.upgrade:SetScript("OnClick", function(self)
            if self:GetChecked() then
                local ok, msg = LC:AddToGearSet({ r.itemID }, true)
                if msg then setMsg((ok and H.good or H.warn) .. msg .. "|r") end
            else
                LC:RemoveFromGearSet(r.itemID)
                setMsg(nil)
            end
            LC:RefreshUI()
        end)
        r.upgrade:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Upgrade"], 1, 1, 1)
            GameTooltip:AddLine(L["Angehakt: zweite Wahl für diesen Slot – nicht so gut wie das beste Item im Set, aber besser als dein jetziges. Pro Slot ein Upgrade (Ringe und Schmuck: zwei)."], nil, nil, nil, true)
            GameTooltip:Show()
        end)
        r.upgrade:HookScript("OnLeave", GameTooltip_Hide)
    end

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

-- bossName: nur in der Favoriten-Liste (dort stehen Items mehrerer Bosse)
local function FillItemRow(r, itemID, chance, bossName)
    r.itemID = itemID
    r.star:Update(itemID)
    r.icon.tex:SetTexture(LC:ItemIcon(itemID))
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(itemID)
    local qc = T:QualityColor(quality)
    r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
    r.name:SetText(LC:ItemLink(itemID))

    local manage = LC:CanManageLoot()
    local nRes = #LC:GetReservers(itemID)
    local parts = {}
    local slots = LC:GearSlotsFor(itemID)
    if bossName then parts[#parts + 1] = H.muted .. bossName .. "|r" end
    if slots then parts[#parts + 1] = (LC:ItemSlot(itemID)) end
    if chance then parts[#parts + 1] = H.good .. chance .. L[" %|r Drop"] end
    if LC:IsCouncilItem(itemID) and not r.remove then parts[#parts + 1] = H.accent .. L["Council-Item|r"] end
    if nRes > 0 then parts[#parts + 1] = nRes .. (nRes == 1 and L[" Reservierung"] or L[" Reservierungen"]) end
    r.sub:SetText(table.concat(parts, "   ·   "))

    local right   -- Breite der Knöpfe rechts
    r.star:ClearAllPoints()
    if r.remove then
        right = 8 + 96 + 8
        r.star:SetPoint("RIGHT", r.remove, "LEFT", -16, 0)
    else
        r.council:SetChecked(LC:IsCouncilItem(itemID))
        r.council:SetShown(manage)
        r.set:ClearAllPoints()
        if manage then
            r.set:SetPoint("RIGHT", r.council, "LEFT", -46, 0)
            right = 76 + 18 + 46 + 18 + 78 + 30
        else
            r.set:SetPoint("RIGHT", -46, 0)
            right = 46 + 18 + 78 + 30
        end
        r.set:SetChecked(LC:IsInMySet(itemID) ~= nil)
        r.set:SetEnabled(slots ~= nil)
        r.upgrade:SetChecked(LC:IsUpgradeInMySet(itemID) ~= nil)
        r.upgrade:SetEnabled(slots ~= nil)
        r.star:SetPoint("RIGHT", r.upgrade, "LEFT", -16, 0)
    end
    right = right + 16 + r.star:GetWidth()
    local textW = r.width - 50 - right
    r.name:SetWidth(textW)
    r.sub:SetWidth(textW)
end

------------------------------------------------------------------------
-- Ansicht „Items“: Raids durchsuchen
------------------------------------------------------------------------
local function GetBossButton(v, i)
    local b = bossButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, v.bossList)
    b:SetSize(BOSS_W - 14, 32)
    b:SetPoint("TOPLEFT", 0, -i * 32)   -- Platz 0 = „Favoriten“
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
        v.bossIdx = self.index
        LC:RefreshUI()
    end)
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetVertexColor(0, 0, 0, 0) end end)
    bossButtons[i] = b
    return b
end

-- v = leerer Rahmen in der Größe des Inhaltsbereichs; setMsg(text) zeigt eine Meldung der Seite
function U.CreateItemsView(v, setMsg)
    v.setMsg = setMsg
    v.chips = ChipBar(v)
    v.chips:SetPoint("TOPLEFT")

    v.dbError = Card(v, 120)
    v.dbError:SetPoint("TOPLEFT")
    v.dbError:SetWidth(CW)
    v.dbError.text = T:Text(v.dbError, 12, C.text)
    v.dbError.text:SetPoint("TOPLEFT", 18, -18)
    v.dbError.text:SetWidth(CW - 36)
    v.dbError.text:SetSpacing(3)

    local bossCol = Card(v)
    bossCol:SetPoint("TOPLEFT", v.chips, "BOTTOMLEFT", 0, -14)
    bossCol:SetPoint("BOTTOMLEFT", 0, 24)
    bossCol:SetWidth(BOSS_W)
    T:Skin(bossCol, C.bgDark)
    -- Itemsuche über alle Raids (Name oder Item-ID)
    v.search = T:Input(bossCol, BOSS_W - 24, 28)
    v.search:SetPoint("TOPLEFT", 12, -10)
    v.search:SetPlaceholder(L["Item suchen (Name oder ID)"])
    v.classBtn = U.ClassFilterButton(bossCol, BOSS_W - 24)
    v.classBtn:SetPoint("TOPLEFT", 12, -44)
    local bsf, bcontent = T:Scroll(bossCol)
    bsf:SetPoint("TOPLEFT", 0, -78)
    bsf:SetPoint("BOTTOMRIGHT", -12, 8)
    v.bossCol, v.bossList = bossCol, bcontent

    local isf, icontent = T:Scroll(v)
    isf:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    isf:SetPoint("BOTTOMRIGHT", -10, 24)
    v.itemScroll, v.itemList = isf, icontent
    v.itemsW = CW - BOSS_W - 14 - 12

    -- Hinweis, wenn die Loot-Quelle für einen Boss noch keinen Loot hat (neue Forever-Raids)
    v.itemsEmpty = Card(v, 120)
    v.itemsEmpty:SetPoint("TOPLEFT", bossCol, "TOPRIGHT", 14, 0)
    v.itemsEmpty:SetWidth(v.itemsW)
    local ie = T:Text(v.itemsEmpty, 14, C.text, "LEFT", nil, true)
    ie:SetPoint("TOPLEFT", 18, -18)
    ie:SetText(L["Loot folgt"])
    v.emptyTitle = ie
    local ies = T:Text(v.itemsEmpty, 12, C.muted)
    ies:SetPoint("TOPLEFT", ie, "BOTTOMLEFT", 0, -8)
    ies:SetWidth(v.itemsW - 36)
    ies:SetSpacing(3)
    v.emptyText = ies
    ies:SetText(L["Die Loot-Quelle hat für diesen Boss noch keine Items eingetragen. Sobald sie aktualisiert wird, erscheinen sie hier automatisch. Bis dahin: Items per Suche, Item-ID oder Shift-Klick hinzufügen."])

    -- Suche: „Zeigen“ springt zu Raid und Boss und hebt das Item hervor; „Set“/„Upgrade“ übernehmen direkt
    local function Show(res)
        if res.raidIdx then
            v.raidIdx, v.bossIdx = res.raidIdx, res.bossIdx
            v.highlight, v.scrollTo = res.id, true
        else
            local ok, msg = LC:AddToGearSet({ res.id })
            if msg then setMsg((ok and H.good or H.warn) .. msg .. "|r") end
        end
        LC:RefreshUI()
    end
    local function Add(res, asUpgrade)
        local ok, msg = LC:AddToGearSet({ res.id }, asUpgrade)
        if msg then setMsg((ok and H.good or H.warn) .. msg .. "|r") end
        if res.raidIdx then
            v.raidIdx, v.bossIdx, v.highlight, v.scrollTo = res.raidIdx, res.bossIdx, res.id, true
        end
        LC:RefreshUI()
    end
    AttachItemSearch(v.search, nil, 420, {
        { label = "Zeigen", tip = "Springt zum Boss und hebt das Item hervor.", func = Show },
        { label = "Set", tip = "Als bestes Item für den Slot ins Set (ein neues ersetzt das alte).", func = function(res) Add(res, false) end },
        { label = "Upgrade", tip = "Nur als Upgrade markieren: zweite Wahl, besser als dein jetziges Item.", func = function(res) Add(res, true) end },
    })
end

function U.RefreshItemsView(v)
    local raids, err = LC:GetLootDB()
    if raids and #raids == 0 then
        raids, err = nil, L["Die gewählte Quelle enthält keine Raids."]
    end
    v.dbError:SetShown(raids == nil)
    v.bossCol:SetShown(raids ~= nil)
    v.itemScroll:SetShown(raids ~= nil)
    if v.itemScroll.bar and raids == nil then v.itemScroll.bar:Hide() end
    if not raids then
        v.itemsEmpty:Hide()
        v.chips:SetItems({}, nil, nil)
        v.dbError.text:SetText(H.warn .. (err or L["Keine Loot-Quelle gefunden."]) .. "|r\n\n"
            .. L["Oben rechts unter „Quelle“ eine andere Quelle wählen – oder Items unter „Mein Set“ per Shift-Klick bzw. Item-ID hinzufügen."])
        return
    end
    -- Im Raid: einmal automatisch diesen Raid zeigen
    local current = LC:GetCurrentRaid()
    if current and v.autoRaid ~= current.key then
        v.autoRaid = current.key
        for i, r in ipairs(raids) do
            if r.key == current.key then v.raidIdx, v.bossIdx = i, 1 break end
        end
    end
    v.raidIdx = math.min(v.raidIdx or 1, #raids)
    local labels = {}
    for i, r in ipairs(raids) do
        labels[i] = r.name .. (((r.itemCount or 0) == 0) and ("  " .. H.muted .. L["(Loot folgt)|r"]) or "")
    end
    v.chips:SetItems(labels, v.raidIdx, function(i)
        v.raidIdx, v.bossIdx = i, 1
        LC:RefreshUI()
    end)

    local manage = LC:CanManageLoot()
    local raid = raids[v.raidIdx]
    -- bossIdx 0 = Favoriten dieses Raids
    v.bossIdx = (v.bossIdx == 0) and 0 or math.min(v.bossIdx or 1, math.max(1, #raid.bosses))
    local favList, favFrom = FavItems(raid)
    local fb = GetBossButton(v, 0)
    fb.index = 0
    fb.selected = (v.bossIdx == 0)
    fb.text:SetText(LC.STAR .. " " .. L["Favoriten"])
    fb.count:SetText((#favList > 0) and tostring(#favList) or "")
    fb.bar:SetShown(fb.selected)
    fb.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], fb.selected and 0.16 or 0)
    local fc = fb.selected and C.text or C.muted
    fb.text:SetTextColor(fc[1], fc[2], fc[3])
    fb:Show()
    for i = 1, math.max(#raid.bosses, #bossButtons) do
        local boss = raid.bosses[i]
        if boss then
            local b = GetBossButton(v, i)
            b.index = i
            b.selected = (i == v.bossIdx)
            b.text:SetText(boss.name)
            -- Zähler: Items in meinem Set (für Council/Leitung zusätzlich Council-Items)
            local nSet, nCouncil = 0, 0
            for _, id in ipairs(boss.items) do
                if LC:IsInMySet(id) then nSet = nSet + 1 end
                if LC:IsCouncilItem(id) then nCouncil = nCouncil + 1 end
            end
            local count = (nSet > 0) and (H.good .. nSet .. "|r") or ""
            if manage and nCouncil > 0 then count = count .. ((count ~= "") and " " or "") .. nCouncil end
            b.count:SetText(count)
            b.bar:SetShown(b.selected)
            b.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], b.selected and 0.16 or 0)
            local tc = b.selected and C.text or C.muted
            b.text:SetTextColor(tc[1], tc[2], tc[3])
            b:Show()
        elseif bossButtons[i] then
            bossButtons[i]:Hide()
        end
    end
    v.bossList:SetHeight((#raid.bosses + 1) * 32)

    local fav = (v.bossIdx == 0)
    local boss = raid.bosses[v.bossIdx]
    local items, hidden = FilterItems(fav and favList or (boss and boss.items) or {})
    v.classBtn:Update(hidden)
    for i = 1, math.max(#items, #browseRows) do
        local id = items[i]
        local r = browseRows[i]
        if id then
            if not r then
                r = CreateItemRow(v.itemList, v.itemsW, false, v.setMsg)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
                browseRows[i] = r
            end
            local from = fav and favFrom[id] or boss
            FillItemRow(r, id, LC:GetDropChance(from, id), fav and from and from.name or nil)
            T:SetBorder(r, (id == v.highlight) and C.accent or C.border)
            if id == v.highlight and v.scrollTo then
                v.scrollTo = nil
                ScrollToRow(v.itemScroll, i, ITEM_ROW)
            end
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    v.itemList:SetHeight(math.max(1, #items * ITEM_ROW))
    v.itemsEmpty:SetShown(#items == 0)
    if #items == 0 then
        if fav and #favList == 0 then
            v.emptyTitle:SetText(L["Noch keine Favoriten"])
            v.emptyText:SetText(L["Klick auf den Stern am Item-Icon, um ein Item vorzumerken. Hier stehen dann alle Favoriten dieses Raids."])
        elseif hidden > 0 then
            v.emptyTitle:SetText(L["Nichts für diese Klasse"])
            v.emptyText:SetText(L("%d Items ausgeblendet. Oben links unter „Klasse“ den Filter ändern.", hidden))
        else
            v.emptyTitle:SetText(L["Loot folgt"])
            v.emptyText:SetText(L["Die Loot-Quelle hat für diesen Boss noch keine Items eingetragen. Sobald sie aktualisiert wird, erscheinen sie hier automatisch. Bis dahin: Items per Suche, Item-ID oder Shift-Klick hinzufügen."])
        end
    end
end

------------------------------------------------------------------------
-- Ansicht „Council-Items“ (Council und Raidleitung)
------------------------------------------------------------------------
function U.CreateCouncilView(v, setMsg)
    local add = Card(v, 76)
    add:SetPoint("TOPLEFT")
    add:SetWidth(CW)
    local al = T:Text(add, 12, C.text, "LEFT", nil, true)
    al:SetPoint("TOPLEFT", 16, -12)
    al:SetText(L["Item manuell hinzufügen"])
    v.input = T:Input(add, CW - 170, 30)
    v.input:SetPoint("TOPLEFT", al, "BOTTOMLEFT", 0, -8)
    v.input:SetPlaceholder(L["Shift-Klick auf ein Item, Item-ID oder Namen eintippen"])
    AcceptLinks(v.input)
    local function DoAdd()
        local ok, msg = LC:AddCouncilItems(v.input:GetText())
        setMsg((ok and H.good or H.bad) .. msg .. "|r")
        if ok then v.input:SetText("") end
        LC:RefreshUI()
    end
    v.input:SetScript("OnEnterPressed", function(self) DoAdd() self:ClearFocus() end)
    local addBtn = T:Button(add, L["Hinzufügen"], 120, 30, "primary", DoAdd)
    addBtn:SetPoint("LEFT", v.input, "RIGHT", 10, 0)
    -- Treffer der Suche direkt als Council-Item übernehmen
    AttachItemSearch(v.input, function(res)
        local ok, msg = LC:AddCouncilItems(tostring(res.id))
        setMsg((ok and H.good or H.bad) .. msg .. "|r")
        LC:RefreshUI()
    end)

    local msf, mcontent = T:Scroll(v)
    msf:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -14)
    msf:SetPoint("BOTTOMRIGHT", -10, 62)
    v.markedList = mcontent
    v.markedEmpty = T:Text(v, 12, C.muted, "CENTER")
    v.markedEmpty:SetPoint("TOP", msf, "TOP", 0, -30)
    v.markedEmpty:SetWidth(CW - 60)
    v.markedEmpty:SetText(L["Noch keine Council-Items.\nUnter „Items“ einfach das Häkchen „Council“ beim Item setzen."])

    local clear = T:Button(v, L["Alle entfernen"], 140, 32, "danger", function() StaticPopup_Show("LIGHTCOUNCIL_CLEAR_ITEMS") end)
    clear:SetPoint("BOTTOMRIGHT", 0, 24)
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

function U.RefreshCouncilView(v)
    local list = LC:GetCouncilItemList()
    v.markedEmpty:SetShown(#list == 0)
    for i = 1, math.max(#list, #markedRows) do
        local it = list[i]
        local r = markedRows[i]
        if it then
            if not r then
                r = CreateItemRow(v.markedList, CW - 12, true)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW)
                markedRows[i] = r
            end
            FillItemRow(r, it.id)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    v.markedList:SetHeight(math.max(1, #list * ITEM_ROW))
end
