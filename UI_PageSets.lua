-- Light Council – Hauptfenster, Seite: Gear-Sets (eigene Sets und die Sets aller im Raid/in der Gilde)
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI
local pages, CW = U.pages, U.CW
local Card, PageHeader, Tip, AcceptLinks = U.Card, U.PageHeader, U.Tip, U.AcceptLinks
local Segmented, ChipBar, IdsFromText = U.Segmented, U.ChipBar, U.IdsFromText

local SET_ROW = 40
local PLAYER_ROW = 44
local setRows, playerRows = {}, {}

-- Spalten der Item-Liste (x-Position)
local X_RANK, X_ICON, X_NAME, X_SLOT, X_SRC, X_STATE, X_BTN = 8, 46, 82, 300, 410, 560, 636
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

local function ItemQualityBorder(icon, id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(id)
    local qc = T:QualityColor(quality)
    icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
end

local function SourceText(id)
    local src = LC:ItemSource(id)
    if not src then return H.muted .. "–|r" end
    return src.raid.name .. H.muted .. " · " .. src.boss.name .. "|r"
end

------------------------------------------------------------------------
-- Dialoge
------------------------------------------------------------------------
local function EditText(dialog)
    local eb = dialog.editBox or dialog.EditBox
    return eb and eb:GetText() or ""
end

local function DefineDialogs()
    StaticPopupDialogs["LIGHTCOUNCIL_NEW_SET"] = {
        text = L["Name für das neue Set (z. B. Biom oder Spec):"],
        button1 = OKAY, button2 = CANCEL, hasEditBox = true, maxLetters = 30,
        OnAccept = function(self)
            local ok, msg = LC:CreateGearSet(EditText(self))
            if not ok and msg then LC:Print(msg) end
        end,
        EditBoxOnEnterPressed = function(self)
            local d = self:GetParent()
            StaticPopupDialogs["LIGHTCOUNCIL_NEW_SET"].OnAccept(d)
            d:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs["LIGHTCOUNCIL_RENAME_SET"] = {
        text = L["Neuer Name für „%s“:"],
        button1 = OKAY, button2 = CANCEL, hasEditBox = true, maxLetters = 30,
        OnShow = function(self, data)
            local eb = self.editBox or self.EditBox
            if eb and data then eb:SetText(data) eb:HighlightText() end
        end,
        OnAccept = function(self, data)
            local ok, msg = LC:RenameGearSet(data, EditText(self))
            if not ok and msg then LC:Print(msg) end
        end,
        EditBoxOnEnterPressed = function(self)
            local d = self:GetParent()
            StaticPopupDialogs["LIGHTCOUNCIL_RENAME_SET"].OnAccept(d, d.data)
            d:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs["LIGHTCOUNCIL_DELETE_SET"] = {
        text = L["Light Council: Set „%s“ löschen?"],
        button1 = YES, button2 = NO,
        OnAccept = function(self, data) LC:DeleteGearSet(data) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

------------------------------------------------------------------------
-- Seite aufbauen
------------------------------------------------------------------------
local function CreateSetsPage(p)
    DefineDialogs()
    local _, ht, hd = PageHeader(p, L["Gear-Sets"], L["Stell dir Sets aus Items zusammen und bring sie in deine Prio-Reihenfolge. Dein aktives Set sehen alle – so weiß der Council, wo du im Gear stehst."])
    hd:SetWidth(CW - 260)   -- rechts sitzt der Umschalter
    local y = math.ceil(ht:GetStringHeight() + 5 + hd:GetStringHeight() + 16)
    p.view = "mine"

    p.seg = Segmented(p, {
        { key = "mine", label = L["Meine Sets"], width = 130 },
        { key = "raid", label = L["Alle Sets"], width = 110 },
    }, function(key)
        p.view = key
        if key == "raid" then LC:RequestGearSets() end
        LC:RefreshUI()
    end)
    p.seg.first:SetPoint("TOPRIGHT", -109, 0)

    ------------------------------------------------------------ Meine Sets
    local mine = CreateFrame("Frame", nil, p)
    mine:SetPoint("TOPLEFT", 0, -y)
    mine:SetPoint("BOTTOMRIGHT")
    p.mine = mine

    mine.chips = ChipBar(mine)
    mine.chips:SetPoint("TOPLEFT", 0, 0)

    local bar = CreateFrame("Frame", nil, mine)
    bar:SetSize(CW, 30)
    bar:SetPoint("TOPLEFT", mine.chips, "BOTTOMLEFT", 0, -10)
    local newBtn = T:Button(bar, L["Neues Set"], 120, 30, "primary", function() StaticPopup_Show("LIGHTCOUNCIL_NEW_SET") end)
    newBtn:SetPoint("LEFT", 0, 0)
    mine.renameBtn = T:Button(bar, L["Umbenennen"], 120, 30, "default", function()
        local _, name = LC:GetActiveSet()
        if name then
            local d = StaticPopup_Show("LIGHTCOUNCIL_RENAME_SET", name, nil, name)
            if d then d.data = name end
        end
    end)
    mine.renameBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
    mine.deleteBtn = T:Button(bar, L["Löschen"], 100, 30, "danger", function()
        local _, name = LC:GetActiveSet()
        if name then
            local d = StaticPopup_Show("LIGHTCOUNCIL_DELETE_SET", name, nil, name)
            if d then d.data = name end
        end
    end)
    mine.deleteBtn:SetPoint("LEFT", mine.renameBtn, "RIGHT", 8, 0)
    mine.summary = T:Text(bar, 12, C.muted, "RIGHT")
    mine.summary:SetPoint("RIGHT", 0, 0)
    mine.summary:SetPoint("LEFT", mine.deleteBtn, "RIGHT", 12, 0)
    mine.summary:SetWordWrap(false)

    -- Hinzufügen
    local add = Card(mine, 52)
    add:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
    add:SetWidth(CW)
    mine.input = T:Input(add, CW - 170, 30)
    mine.input:SetPoint("LEFT", 12, 0)
    mine.input:SetPlaceholder(L["Shift-Klick auf ein Item, Item-ID – oder auf „Meine Reservierung“ „+ Set“ klicken"])
    AcceptLinks(mine.input)
    local addBtn = T:Button(add, L["Hinzufügen"], 130, 30, "default", function()
        local ok, msg = LC:AddToGearSet(IdsFromText(mine.input:GetText()))
        mine.input:SetText("")
        mine.msgText = msg and ((ok and H.good or H.warn) .. msg .. "|r") or nil
        LC:RefreshUI()
    end)
    addBtn:SetPoint("LEFT", mine.input, "RIGHT", 10, 0)
    mine.input:SetScript("OnEnterPressed", function(self) addBtn:Click() self:ClearFocus() end)

    -- Spaltenköpfe
    local head = CreateFrame("Frame", nil, mine)
    head:SetSize(CW, 20)
    head:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -12)
    for _, c in ipairs({ { L["PRIO"], X_RANK }, { L["ITEM"], X_NAME }, { L["SLOT"], X_SLOT }, { L["DROPPT IN"], X_SRC }, { L["STATUS"], X_STATE } }) do
        local t = T:Text(head, 10, C.muted, "LEFT", nil, true)
        t:SetPoint("LEFT", c[2], 0)
        t:SetText(c[1])
    end

    local sf, content = T:Scroll(mine)
    sf:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", -10, 24)
    mine.list = content
    mine.empty = T:Text(mine, 13, C.muted, "CENTER")
    mine.empty:SetPoint("TOP", sf, "TOP", 0, -40)
    mine.empty:SetWidth(CW - 80)
    mine.empty:SetSpacing(4)
    mine.msg = T:Text(mine, 12, C.muted, "LEFT")
    mine.msg:SetPoint("BOTTOMLEFT", 0, 4)
    mine.msg:SetWidth(CW)
    mine.msg:SetWordWrap(false)

    ------------------------------------------------------------ Alle Sets
    local raid = CreateFrame("Frame", nil, p)
    raid:SetPoint("TOPLEFT", 0, -y)
    raid:SetPoint("BOTTOMRIGHT")
    p.raid = raid
    raid.info = T:Text(raid, 12, C.muted, "LEFT")
    raid.info:SetPoint("TOPLEFT", 0, -8)
    raid.info:SetWidth(CW - 160)
    local refresh = T:Button(raid, L["Aktualisieren"], 140, 30, "default", function()
        LC:RequestGearSets()
        raid.info:SetText(L["Sets werden abgefragt …"])
    end)
    refresh:SetPoint("TOPRIGHT", 0, 0)
    Tip(refresh, L["Aktualisieren"], L["Fragt die aktiven Sets aller Addon-Nutzer in Gilde und Raid ab."])
    local rhead = CreateFrame("Frame", nil, raid)
    rhead:SetSize(CW, 20)
    rhead:SetPoint("TOPLEFT", 0, -44)
    for _, c in ipairs({ { L["SPIELER"], 8 }, { L["SET"], 190 }, { L["STAND"], 350 }, { L["ALS NÄCHSTES"], 440 } }) do
        local t = T:Text(rhead, 10, C.muted, "LEFT", nil, true)
        t:SetPoint("LEFT", c[2], 0)
        t:SetText(c[1])
    end
    local rsf, rcontent = T:Scroll(raid)
    rsf:SetPoint("TOPLEFT", rhead, "BOTTOMLEFT", 0, -4)
    rsf:SetPoint("BOTTOMRIGHT", -10, 4)
    raid.list = rcontent
    raid.empty = T:Text(raid, 13, C.muted, "CENTER")
    raid.empty:SetPoint("TOP", rsf, "TOP", 0, -40)
    raid.empty:SetWidth(CW - 80)
end

------------------------------------------------------------------------
-- Zeilen
------------------------------------------------------------------------
local function SmallButton(parent, text, onClick, tip)
    local b = T:Button(parent, text, 26, 26, "ghost", onClick)
    if tip then b.tooltipTitle, b.tooltip = tip, " " end
    return b
end

local function GetSetRow(parent, i)
    local r = setRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(CW - 14, SET_ROW - 4)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * SET_ROW)
    T:Skin(r, C.panel)
    r.rank = T:Text(r, 14, C.accentLt, "LEFT", nil, true)
    r.rank:SetPoint("LEFT", X_RANK, 0)
    r.icon = T:Icon(r, 28)
    r.icon:SetPoint("LEFT", X_ICON, 0)
    r.name = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.name:SetPoint("LEFT", X_NAME, 0)
    r.name:SetWidth(X_SLOT - X_NAME - 10)
    r.name:SetWordWrap(false)
    r.slot = T:Text(r, 12, C.muted)
    r.slot:SetPoint("LEFT", X_SLOT, 0)
    r.slot:SetWidth(X_SRC - X_SLOT - 8)
    r.slot:SetWordWrap(false)
    r.src = T:Text(r, 12, C.text)
    r.src:SetPoint("LEFT", X_SRC, 0)
    r.src:SetWidth(X_STATE - X_SRC - 8)
    r.src:SetWordWrap(false)
    r.state = T:Text(r, 12, C.text)
    r.state:SetPoint("LEFT", X_STATE, 0)
    r.state:SetWidth(X_BTN - X_STATE - 4)
    r.state:SetWordWrap(false)
    r.up = SmallButton(r, "↑", function() LC:MoveInGearSet(r.index, -1) end, L["Höher in der Prio"])
    r.up:SetPoint("LEFT", X_BTN, 0)
    r.down = SmallButton(r, "↓", function() LC:MoveInGearSet(r.index, 1) end, L["Tiefer in der Prio"])
    r.down:SetPoint("LEFT", r.up, "RIGHT", 2, 0)
    r.del = SmallButton(r, "×", function() LC:RemoveFromGearSet(r.index) end, L["Aus dem Set entfernen"])
    r.del:SetPoint("LEFT", r.down, "RIGHT", 2, 0)
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
    setRows[i] = r
    return r
end

-- Tooltip mit dem ganzen Set eines Spielers
local function SetTooltip(owner, s)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.name .. "  ·  " .. s.set, 1, 1, 1)
    local n = 0
    for _, it in ipairs(s.items) do
        local left
        if it.have then
            left = CHECK .. " " .. LC:ItemLink(it.id)
        else
            n = n + 1
            left = H.accentLt .. "#" .. n .. "|r  " .. LC:ItemLink(it.id)
        end
        GameTooltip:AddDoubleLine(left, (LC:ItemSlot(it.id)), 1, 1, 1, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function GetPlayerRow(parent, i)
    local r = playerRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(CW - 14, PLAYER_ROW - 4)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * PLAYER_ROW)
    T:Skin(r, C.panel)
    r.name = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetWidth(175)
    r.name:SetWordWrap(false)
    r.set = T:Text(r, 12, C.muted)
    r.set:SetPoint("LEFT", 190, 0)
    r.set:SetWidth(150)
    r.set:SetWordWrap(false)
    r.progress = T:Text(r, 13, C.text, "LEFT", nil, true)
    r.progress:SetPoint("LEFT", 350, 0)
    r.icons = {}
    for k = 1, 6 do
        local ic = T:Icon(r, 26)
        ic:SetPoint("LEFT", 440 + (k - 1) * 32, 0)
        r.icons[k] = ic
    end
    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.panelAlt[1], C.panelAlt[2], C.panelAlt[3], 1)
        if self.data then SetTooltip(self, self.data) end
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1)
        GameTooltip:Hide()
    end)
    playerRows[i] = r
    return r
end

------------------------------------------------------------------------
-- Aktualisieren
------------------------------------------------------------------------
local function RefreshMine(p)
    local mine = p.mine
    local order, active = LC:GetMySets()
    local labels, sel = {}, 1
    for i, name in ipairs(order) do
        labels[i] = (name == active) and ("» " .. name) or name
        if name == active then sel = i end
    end
    mine.chips:SetItems(labels, sel, function(i) LC:SetActiveGearSet(order[i]) end)
    mine.renameBtn:SetEnabled(active ~= nil)
    mine.deleteBtn:SetEnabled(active ~= nil)

    local set = LC:GetActiveSet()
    local items = set and set.items or {}
    local have, missing = 0, 0
    local rank = 0
    for i = 1, math.max(#items, #setRows) do
        local id = items[i]
        if id then
            local r = GetSetRow(mine.list, i)
            r.index, r.itemID = i, id
            local owned = LC:HaveItem(id)
            if owned then
                have = have + 1
                r.rank:SetText(CHECK)
                r.state:SetText(H.good .. L["Hast du"] .. "|r")
            else
                missing = missing + 1
                rank = rank + 1
                r.rank:SetText("#" .. rank)
                r.state:SetText(H.warn .. L["Fehlt"] .. "|r")
            end
            r.icon.tex:SetTexture(LC:ItemIcon(id))
            ItemQualityBorder(r.icon, id)
            r.name:SetText(LC:ItemLink(id))
            r.slot:SetText((LC:ItemSlot(id)))
            r.src:SetText(SourceText(id))
            r.up:SetEnabled(i > 1)
            r.down:SetEnabled(i < #items)
            r:Show()
        elseif setRows[i] then
            setRows[i]:Hide()
        end
    end
    mine.list:SetHeight(math.max(1, #items * SET_ROW))
    if #order == 0 then
        mine.empty:SetText(L["Noch kein Set.\nKlick auf „Neues Set“ – oder füge direkt ein Item hinzu, dann entsteht „Set 1“."])
    elseif #items == 0 then
        mine.empty:SetText(L["Das Set ist leer.\nItems per Shift-Klick oder Item-ID hinzufügen – oder auf „Meine Reservierung“ bei einem Item „+ Set“ klicken."])
    end
    mine.empty:SetShown(#items == 0)
    mine.summary:SetText(#items > 0 and L("%d Items  ·  %d hast du  ·  %d fehlen", #items, have, missing) or "")
    mine.msg:SetText(mine.msgText or (H.muted .. L["Die Reihenfolge ist deine Prio: oben = am wichtigsten. Items, die du schon hast, zählen nicht mehr mit.|r"]))
end

local function RefreshRaid(p)
    local raid = p.raid
    local list = LC:GetAllGearSets()
    for i = 1, math.max(#list, #playerRows) do
        local s = list[i]
        if s then
            local r = GetPlayerRow(raid.list, i)
            r.data = s
            r.name:SetText(s.name)
            r.set:SetText(s.set)
            local have, nextItems = 0, {}
            for _, it in ipairs(s.items) do
                if it.have then have = have + 1 elseif #nextItems < #r.icons then nextItems[#nextItems + 1] = it.id end
            end
            local pc = (#s.items > 0 and have == #s.items) and H.good or ""
            r.progress:SetText(pc .. have .. " / " .. #s.items .. ((pc ~= "") and "|r" or ""))
            for k, ic in ipairs(r.icons) do
                local id = nextItems[k]
                if id then
                    ic.tex:SetTexture(LC:ItemIcon(id))
                    ItemQualityBorder(ic, id)
                    ic:Show()
                else
                    ic:Hide()
                end
            end
            r:Show()
        elseif playerRows[i] then
            playerRows[i]:Hide()
        end
    end
    raid.list:SetHeight(math.max(1, #list * PLAYER_ROW))
    raid.empty:SetText(L["Noch keine Sets bekannt. Sets kommen von allen mit Light Council in Gilde und Raid – „Aktualisieren“ fragt sie ab."])
    raid.empty:SetShown(#list == 0)
    if #list > 0 then
        raid.info:SetText(L("%d Spieler mit Set  ·  Maus über eine Zeile zeigt das ganze Set", #list))
    end
end

local function RefreshSets()
    local p = pages.sets
    p.seg:Set(p.view)
    p.mine:SetShown(p.view == "mine")
    p.raid:SetShown(p.view == "raid")
    if p.view == "mine" then RefreshMine(p) else RefreshRaid(p) end
end

U.CreateSetsPage, U.RefreshSets = CreateSetsPage, RefreshSets
