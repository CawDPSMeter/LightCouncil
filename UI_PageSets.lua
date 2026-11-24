-- Light Council – Hauptfenster, Seite: Gear-Sets
--   „Mein Set“    : eigene Sets, nach Slots geordnet (ein Item pro Slot, ★ = wichtig)
--   „Items“       : alle Raids → Bosse → Items zum Anhaken (Council/Leitung: Council-Item)
--   „Alle Sets“   : die aktiven Sets aller Addon-Nutzer in Gilde und Raid
--   „Council-Items“ (nur Council/Leitung): Liste der Council-Items
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI
local pages, CW = U.pages, U.CW
local Card, PageHeader, Tip, AcceptLinks = U.Card, U.PageHeader, U.Tip, U.AcceptLinks
local Segmented, ChipBar, IdsFromText, SourceButton = U.Segmented, U.ChipBar, U.IdsFromText, U.SourceButton
local AttachItemSearch = U.AttachItemSearch

local SLOT_ROW, GROUP_ROW = 32, 30
local PLAYER_ROW = 44
local slotRows, groupRows, playerRows = {}, {}, {}
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local STAR_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

-- Spalten der Slot-Liste (x-Position)
local X_SLOT, X_ICON, X_NAME, X_SRC, X_STATE, X_RES = 12, 104, 132, 340, 500, 566

local function ItemQualityBorder(icon, id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(id)
    local qc = T:QualityColor(quality)
    icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
end

-- Nur Symbole (für die Reservierungsleiste)
local function IconRow(ids)
    local t = {}
    for _, id in ipairs(ids or {}) do t[#t + 1] = "|T" .. tostring(LC:ItemIcon(id)) .. ":16:16:0:0|t" end
    return table.concat(t, " ")
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
local function SetMsg(text)
    pages.sets.msgText = text
end

local function CreateSetsPage(p)
    DefineDialogs()
    local _, ht, hd = PageHeader(p, L["Gear-Sets"], L["Stell dir pro Slot dein Wunsch-Item zusammen und markiere, was dir wichtig ist. Dein aktives Set sehen alle – so weiß der Council, wo du im Gear stehst."])
    hd:SetWidth(CW - 220)   -- rechts sitzt „Quelle“
    local y = math.ceil(ht:GetStringHeight() + 5 + hd:GetStringHeight() + 16)
    p.view = "mine"

    p.sourceBtn = SourceButton(p)
    p.sourceBtn:SetPoint("TOPRIGHT", 0, 0)

    p.seg = Segmented(p, {
        { key = "mine", label = L["Mein Set"], width = 120 },
        { key = "items", label = L["Items"], width = 100 },
        { key = "raid", label = L["Alle Sets"], width = 110 },
        { key = "council", label = L["Council-Items"], width = 150 },
    }, function(key)
        p.view = key
        p.msgText = nil
        if key == "raid" then LC:RequestGearSets() end
        LC:RefreshUI()
    end)
    p.seg.first:SetPoint("TOPLEFT", 0, -y)
    y = y + 32 + 14

    local function View()
        local v = CreateFrame("Frame", nil, p)
        v:SetPoint("TOPLEFT", 0, -y)
        v:SetPoint("BOTTOMRIGHT")
        return v
    end

    -- Meldungen ganz unten (für alle Ansichten)
    p.msg = T:Text(p, 12, C.muted, "LEFT")
    p.msg:SetPoint("BOTTOMLEFT", 0, 4)
    p.msg:SetWidth(CW)
    p.msg:SetWordWrap(false)

    ------------------------------------------------------------ Mein Set
    local mine = View()
    p.mine = mine

    mine.chips = ChipBar(mine)
    mine.chips:SetPoint("TOPLEFT", 0, 0)

    local bar = CreateFrame("Frame", nil, mine)
    bar:SetSize(CW, 30)
    bar:SetPoint("TOPLEFT", mine.chips, "BOTTOMLEFT", 0, -10)
    local newBtn = T:Button(bar, L["Neues Set"], 110, 30, "primary", function() StaticPopup_Show("LIGHTCOUNCIL_NEW_SET") end)
    newBtn:SetPoint("LEFT", 0, 0)
    mine.renameBtn = T:Button(bar, L["Umbenennen"], 110, 30, "default", function()
        local _, name = LC:GetActiveSet()
        if name then
            local d = StaticPopup_Show("LIGHTCOUNCIL_RENAME_SET", name, nil, name)
            if d then d.data = name end
        end
    end)
    mine.renameBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
    mine.deleteBtn = T:Button(bar, L["Löschen"], 90, 30, "danger", function()
        local _, name = LC:GetActiveSet()
        if name then
            local d = StaticPopup_Show("LIGHTCOUNCIL_DELETE_SET", name, nil, name)
            if d then d.data = name end
        end
    end)
    mine.deleteBtn:SetPoint("LEFT", mine.renameBtn, "RIGHT", 8, 0)

    -- Hinzufügen: Name oder ID tippen (Suche), Shift-Klick oder ID + Enter
    mine.input = T:Input(bar, CW - 340 - 12, 30)
    mine.input:SetPoint("RIGHT", 0, 0)
    mine.input:SetPlaceholder(L["Item hinzufügen: Name, Item-ID oder Shift-Klick"])
    AcceptLinks(mine.input)
    mine.input:SetScript("OnEnterPressed", function(self)
        local ok, msg = LC:AddToGearSet(IdsFromText(self:GetText()))
        self:SetText("")
        self:ClearFocus()
        SetMsg(msg and ((ok and H.good or H.warn) .. msg .. "|r") or nil)
        LC:RefreshUI()
    end)
    AttachItemSearch(mine.input, function(res)
        local ok, msg = LC:AddToGearSet({ res.id })
        SetMsg(msg and ((ok and H.good or H.warn) .. msg .. "|r") or nil)
        LC:RefreshUI()
    end)

    mine.summary = T:Text(mine, 12, C.muted, "LEFT")
    mine.summary:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
    mine.summary:SetWidth(CW)
    mine.summary:SetWordWrap(false)

    local sf, content = T:Scroll(mine)
    sf:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -34)
    sf:SetPoint("BOTTOMRIGHT", -10, 64)
    mine.list = content

    -- Reservierung: Stand für einen Raid + Speichern (Auswahl ist dieselbe wie unter „Meine Reservierung“)
    local rb = Card(mine, 36)
    rb:SetPoint("BOTTOMLEFT", 0, 22)
    rb:SetWidth(CW)
    mine.resBar = rb
    mine.resText = T:Text(rb, 12, C.text, "LEFT")
    mine.resText:SetPoint("LEFT", 12, 0)
    mine.resText:SetWidth(CW - 340)
    mine.resText:SetWordWrap(false)
    mine.resSave = T:Button(rb, L["Reservierung speichern"], 190, 26, "primary", function()
        local key = mine.resKey
        if not key then return end
        local _, locked = U.ResState(key)
        if locked then
            -- Änderung braucht eine Begründung – die steht unter „Meine Reservierung“
            LC:OpenReservation(key)
        else
            U.ResConfirm(key, "sets")
        end
    end)
    mine.resSave:SetPoint("RIGHT", -6, 0)
    mine.resOpen = T:Button(rb, L["Meine Reservierung"], 130, 26, "ghost", function()
        LC:OpenReservation(mine.resKey)
    end)
    mine.resOpen:SetPoint("RIGHT", mine.resSave, "LEFT", -6, 0)

    ------------------------------------------------------------ Items
    p.items = View()
    U.CreateItemsView(p.items, SetMsg)

    ------------------------------------------------------------ Alle Sets
    local raid = View()
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
    rsf:SetPoint("BOTTOMRIGHT", -10, 24)
    raid.list = rcontent
    raid.empty = T:Text(raid, 13, C.muted, "CENTER")
    raid.empty:SetPoint("TOP", rsf, "TOP", 0, -40)
    raid.empty:SetWidth(CW - 80)

    ------------------------------------------------------------ Council-Items
    p.council = View()
    U.CreateCouncilView(p.council, SetMsg)
end

------------------------------------------------------------------------
-- Zeilen „Mein Set“
------------------------------------------------------------------------
local function GetGroupRow(parent, g)
    local r = groupRows[g]
    if r then return r end
    r = CreateFrame("Frame", nil, parent)
    r:SetSize(CW - 14, GROUP_ROW)
    r.title = T:Text(r, 11, C.accentLt, "LEFT", nil, true)
    r.title:SetPoint("BOTTOMLEFT", 4, 7)
    r.count = T:Text(r, 11, C.muted, "LEFT")
    r.count:SetPoint("LEFT", r.title, "RIGHT", 10, 0)
    groupRows[g] = r
    return r
end

local function GetSlotRow(parent, i)
    local r = slotRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(CW - 14, SLOT_ROW - 2)
    T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
    -- Grüner Streifen links: hast du schon
    r.stripe = r:CreateTexture(nil, "ARTWORK")
    r.stripe:SetTexture(T.WHITE)
    r.stripe:SetVertexColor(unpack(C.good))
    r.stripe:SetPoint("TOPLEFT")
    r.stripe:SetPoint("BOTTOMLEFT")
    r.stripe:SetWidth(3)
    r.slot = T:Text(r, 12, C.muted)
    r.slot:SetPoint("LEFT", X_SLOT, 0)
    r.slot:SetWidth(X_ICON - X_SLOT - 6)
    r.slot:SetWordWrap(false)
    r.icon = T:Icon(r, 24)
    r.icon:SetPoint("LEFT", X_ICON, 0)
    r.name = T:Text(r, 13, C.text)
    r.name:SetPoint("LEFT", X_NAME, 0)
    r.name:SetWidth(X_SRC - X_NAME - 8)
    r.name:SetWordWrap(false)
    r.src = T:Text(r, 12, C.muted)
    r.src:SetPoint("LEFT", X_SRC, 0)
    r.src:SetWidth(X_STATE - X_SRC - 8)
    r.src:SetWordWrap(false)
    r.state = T:Text(r, 12, C.text)
    r.state:SetPoint("LEFT", X_STATE, 0)
    r.state:SetWidth(X_RES - X_STATE - 6)
    r.state:SetWordWrap(false)

    -- Reservieren für den Raid, in dem das Item droppt (gleiche Auswahl wie unter „Meine Reservierung“)
    r.res = T:Check(r, L["Reservieren"])
    r.res:SetPoint("LEFT", X_RES, 0)
    r.res.label:SetWidth(86)
    r.res.label:SetWordWrap(false)
    r.res:SetScript("OnClick", function(self)
        local ok, msg = U.ResToggle(r.raidKey, r.itemID, self:GetChecked())
        pages.sets.mine.resKey = r.raidKey
        if not ok then self:SetChecked(false) end
        SetMsg(msg)
        LC:RefreshUI()
    end)
    r.res:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Reservieren"], 1, 1, 1)
        if r.raidName then
            GameTooltip:AddLine(L("Für „%s“ reservieren. Gespeichert wird unten mit „Reservierung speichern“ – wie unter „Meine Reservierung“.", r.raidName), nil, nil, nil, true)
        else
            GameTooltip:AddLine(L["Dieses Item droppt in keinem Raid der Loot-Quelle – reservieren geht hier nicht."], nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    r.res:HookScript("OnLeave", GameTooltip_Hide)

    -- ★ wichtig
    r.star = CreateFrame("Button", nil, r)
    r.star:SetSize(22, 22)
    r.star:SetPoint("RIGHT", -40, 0)
    r.star.tex = r.star:CreateTexture(nil, "ARTWORK")
    r.star.tex:SetAllPoints()
    r.star.tex:SetTexture(STAR_TEX)
    r.star:SetScript("OnClick", function() LC:ToggleGearSetImportant(r.itemID) end)
    r.star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Wichtig"], 1, 1, 1)
        GameTooltip:AddLine(L["Markiert Items, die dir besonders wichtig sind. Der Council sieht das bei der Abstimmung."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    r.star:SetScript("OnLeave", GameTooltip_Hide)

    r.del = T:Button(r, "×", 26, 24, "ghost", function() LC:RemoveFromGearSet(r.itemID) end)
    r.del:SetPoint("RIGHT", -8, 0)
    r.del.tooltipTitle, r.del.tooltip = L["Aus dem Set entfernen"], " "

    r:SetScript("OnClick", function(self)
        -- Leerer Slot: zur Item-Übersicht
        if not self.itemID then
            pages.sets.view = "items"
            LC:RefreshUI()
        end
    end)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.panelAlt[1], C.panelAlt[2], C.panelAlt[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
        else
            GameTooltip:SetText(self.slotLabel or "", 1, 1, 1)
            GameTooltip:AddLine(L["Noch kein Item. Klick öffnet die Item-Übersicht – oder oben Name bzw. ID eintippen."], nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        local bg = (self.index % 2 == 0) and C.panel or C.bg
        self:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        GameTooltip:Hide()
    end)
    slotRows[i] = r
    return r
end

------------------------------------------------------------------------
-- Zeilen „Alle Sets“
------------------------------------------------------------------------
-- Tooltip mit dem ganzen Set eines Spielers (✓ = hat er, ★ = wichtig)
local function SetTooltip(owner, s)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(s.name .. "  ·  " .. s.set, 1, 1, 1)
    for _, it in ipairs(s.items) do
        local mark = it.have and CHECK or (it.important and LC.STAR or (it.upgrade and LC.UPGRADE) or "     ")
        GameTooltip:AddDoubleLine(mark .. " " .. LC:ItemLink(it.id), (LC:ItemSlot(it.id)), 1, 1, 1, 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(CHECK .. " " .. L["hat es"] .. "    " .. LC.STAR .. " " .. L["wichtig"] .. "    " .. LC.UPGRADE .. L["Upgrade"], 0.6, 0.6, 0.6)
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
    for k = 1, 8 do
        local ic = T:Icon(r, 26)
        ic:SetPoint("LEFT", 440 + (k - 1) * 32, 0)
        ic.star = ic:CreateTexture(nil, "OVERLAY")
        ic.star:SetTexture(STAR_TEX)
        ic.star:SetSize(12, 12)
        ic.star:SetPoint("TOPRIGHT", 4, 4)
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
    local slots = set and set.slots or {}
    local important = set and set.important or {}
    local y, filled, have, stars = 0, 0, 0, 0
    local raidsInSet = {}
    local groupStats = {}
    for _, s in ipairs(LC.GEAR_SLOTS) do
        local g = groupStats[s.group] or { total = 0, have = 0 }
        groupStats[s.group] = g
        g.total = g.total + 1
        local id = slots[s.key]
        if id and LC:HaveItem(id) then g.have = g.have + 1 end
    end

    -- Zeile für ein Upgrade füllen (wie ein Slot, aber ohne Stern; reservieren geht genauso)
    local function FillUpgrade(r, id, order)
        r.itemID = id
        r.slotLabel = LC:GearSlotLabel(LC.GEAR_SLOTS[order].key) .. " – " .. L["Upgrade"]
        r.slot:SetText("   " .. LC.UPGRADE .. H.warn .. L["Upgrade"] .. "|r")
        local owned = LC:HaveItem(id)
        r.icon.tex:SetTexture(LC:ItemIcon(id))
        ItemQualityBorder(r.icon, id)
        r.icon:Show()
        r.name:SetText(LC:ItemLink(id))
        r.src:SetText(SourceText(id))
        r.state:SetText(owned and (H.good .. L["Hast du"] .. "|r") or (H.warn .. L["Fehlt"] .. "|r"))
        r.stripe:SetShown(owned)
        r.star:Hide()
        r.del:Show()
        local src = LC:ItemSource(id)
        r.raidKey = src and src.raid.key or nil
        r.raidName = src and src.raid.name or nil
        if r.raidKey then
            raidsInSet[r.raidKey] = raidsInSet[r.raidKey] or { key = r.raidKey, name = r.raidName, order = order }
            local on = U.ResSelected(r.raidKey, id)
            r.res:SetChecked(on)
            r.res:SetEnabled(on or #U.ResSel(r.raidKey) < LC:MaxReserves())
            local rec = LC:GetReservation(r.raidKey)
            local saved = false
            for _, x in ipairs(rec and rec.items or {}) do if x == id then saved = true end end
            local lc = saved and C.good or C.text
            r.res.label:SetTextColor(lc[1], lc[2], lc[3])
        else
            r.res:SetChecked(false)
            r.res:SetEnabled(false)
        end
        r.res:Show()
    end

    local lastGroup
    for i, s in ipairs(LC.GEAR_SLOTS) do
        if s.group ~= lastGroup then
            lastGroup = s.group
            local gr = GetGroupRow(mine.list, s.group)
            gr:ClearAllPoints()
            gr:SetPoint("TOPLEFT", 0, -y)
            gr.title:SetText(L[LC.GEAR_GROUPS[s.group]])
            local st = groupStats[s.group]
            gr.count:SetText(L("%d von %d hast du", st.have, st.total))
            gr:Show()
            y = y + GROUP_ROW
        end
        local r = GetSlotRow(mine.list, i)
        r.index = i
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        y = y + SLOT_ROW
        local id = slots[s.key]
        r.itemID = id
        r.slotLabel = LC:GearSlotLabel(s.key)
        r.slot:SetText(r.slotLabel)
        if id then
            filled = filled + 1
            local owned = LC:HaveItem(id)
            if owned then have = have + 1 end
            local imp = important[id] == true
            if imp then stars = stars + 1 end
            r.icon.tex:SetTexture(LC:ItemIcon(id))
            ItemQualityBorder(r.icon, id)
            r.icon:Show()
            r.name:SetText(LC:ItemLink(id))
            r.src:SetText(SourceText(id))
            r.state:SetText(owned and (H.good .. L["Hast du"] .. "|r") or (H.warn .. L["Fehlt"] .. "|r"))
            r.stripe:SetShown(owned)
            r.star:Show()
            r.star.tex:SetDesaturated(not imp)
            r.star:SetAlpha(imp and 1 or 0.3)
            r.del:Show()
            -- Reservieren: Raid, in dem das Item droppt
            local src = LC:ItemSource(id)
            r.raidKey = src and src.raid.key or nil
            r.raidName = src and src.raid.name or nil
            if r.raidKey then
                raidsInSet[r.raidKey] = raidsInSet[r.raidKey] or { key = r.raidKey, name = r.raidName, order = i }
                local on = U.ResSelected(r.raidKey, id)
                r.res:SetChecked(on)
                r.res:SetEnabled(on or #U.ResSel(r.raidKey) < LC:MaxReserves())
                local rec = LC:GetReservation(r.raidKey)
                local saved = false
                for _, x in ipairs(rec and rec.items or {}) do if x == id then saved = true end end
                local lc = saved and C.good or C.text
                r.res.label:SetTextColor(lc[1], lc[2], lc[3])
            else
                r.res:SetChecked(false)
                r.res:SetEnabled(false)
            end
            r.res:Show()
        else
            r.icon:Hide()
            r.name:SetText(H.muted .. L["– frei –"] .. "|r")
            r.src:SetText("")
            r.state:SetText("")
            r.stripe:Hide()
            r.star:Hide()
            r.del:Hide()
            r.res:Hide()
            r.raidKey, r.raidName = nil, nil
        end
        r:Show()

        -- Upgrade (zweite Wahl) direkt unter dem Slot
        local up = set and set.upgrades and set.upgrades[s.key]
        local u = slotRows[100 + i]
        if up then
            u = GetSlotRow(mine.list, 100 + i)
            u.index = i
            u:ClearAllPoints()
            u:SetPoint("TOPLEFT", 0, -y)
            y = y + SLOT_ROW
            FillUpgrade(u, up, i)
            u:Show()
        elseif u then
            u.itemID = nil
            u:Hide()
        end
    end
    mine.list:SetHeight(math.max(1, y))

    if #order == 0 then
        mine.summary:SetText(L["Noch kein Set. Klick auf „Neues Set“ – oder füge direkt ein Item hinzu, dann entsteht „Set 1“."])
    else
        mine.summary:SetText(L("%d von %d Slots belegt  ·  %d hast du  ·  %d wichtig", filled, #LC.GEAR_SLOTS, have, stars)
            .. "   " .. H.muted .. L["(Klick auf einen freien Slot öffnet die Item-Übersicht)"] .. "|r")
    end

    -- Leiste „Reservierung“: zuletzt angeklickter Raid, sonst einer mit ungespeicherter Auswahl,
    -- sonst der aktuelle Raid, sonst der erste Raid mit Items aus dem Set
    local list = {}
    for _, info in pairs(raidsInSet) do list[#list + 1] = info end
    table.sort(list, function(a, b) return a.order < b.order end)
    local key = mine.resKey
    if key and not raidsInSet[key] and not (U.ResState(key)) then key = nil end
    if not key then
        for _, info in ipairs(list) do
            if U.ResState(info.key) then key = info.key break end
        end
    end
    if not key then
        local cur = LC:GetCurrentRaid()
        if cur and raidsInSet[cur.key] then key = cur.key end
    end
    if not key and list[1] then key = list[1].key end
    mine.resKey = key
    mine.resBar:SetShown(key ~= nil)
    if key then
        local changed, locked, pending = U.ResState(key)
        local name = raidsInSet[key] and raidsInSet[key].name
        if not name then
            for _, r in ipairs(LC:GetLootDB() or {}) do if r.key == key then name = r.name end end
        end
        local sel = U.ResSel(key)
        local state
        if pending then state = H.warn .. L["Änderung beantragt – wartet auf den Council"] .. "|r"
        elseif changed then state = H.warn .. L["nicht gespeichert"] .. "|r"
        elseif locked then state = H.good .. L["gespeichert"] .. "|r"
        elseif #sel > 0 then state = H.warn .. L["wartet auf Bestätigung"] .. "|r"
        else state = H.muted .. L["Häkchen „Reservieren“ setzen"] .. "|r" end
        local others = 0
        for _, info in ipairs(list) do
            if info.key ~= key and U.ResState(info.key) then others = others + 1 end
        end
        mine.resText:SetText(L("Reservierung %s: %d von %d", name or key, #sel, LC:MaxReserves())
            .. "  " .. IconRow(sel) .. "   " .. state
            .. ((others > 0) and (H.warn .. "   " .. L("(+%d Raid(s) nicht gespeichert)", others) .. "|r") or ""))
        mine.resSave:SetText(locked and L["Änderung beantragen"] or L["Reservierung speichern"])
        mine.resSave:SetEnabled(changed and not pending and (#sel > 0 or locked))
    end
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
            -- Als Nächstes: fehlende Items, wichtige zuerst
            local total = 0
            for _, it in ipairs(s.items) do if not it.upgrade then total = total + 1 end end
            local have, first, rest = 0, {}, {}
            for _, it in ipairs(s.items) do
                if it.upgrade then -- Upgrades zählen nicht zum Fortschritt
                elseif it.have then have = have + 1
                elseif it.important then first[#first + 1] = it
                else rest[#rest + 1] = it end
            end
            for _, it in ipairs(rest) do first[#first + 1] = it end
            local pc = (total > 0 and have == total) and H.good or ""
            r.progress:SetText(pc .. have .. " / " .. total .. ((pc ~= "") and "|r" or ""))
            for k, ic in ipairs(r.icons) do
                local it = first[k]
                if it then
                    ic.tex:SetTexture(LC:ItemIcon(it.id))
                    ItemQualityBorder(ic, it.id)
                    ic.star:SetShown(it.important == true)
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

-- Hinweis unten, wenn keine Meldung ansteht
local HINTS = {
    mine = "Pro Slot ein Item, darunter optional ein Upgrade (zweite Wahl). Der Stern markiert, was dir wichtig ist.",
    items = "„Set“: bestes Item für den Slot (ein neues ersetzt das alte). „Upgrade“: zweite Wahl, besser als dein jetziges.",
    raid = "",
    council = "Nur bei Council-Items entscheidet der Council, wer würfeln darf. Sie gelten beim Plündermeister.",
}

local function RefreshSets()
    local p = pages.sets
    local manage = LC:CanManageLoot()
    p.seg.buttons.council:SetShown(manage)
    if p.view == "council" and not manage then p.view = "mine" end
    if LC.wantSetsView then
        p.view = LC.wantSetsView
        LC.wantSetsView = nil
    end
    if manage then
        local n = 0
        for _ in pairs(LC.db.councilItems) do n = n + 1 end
        p.seg.buttons.council:SetText(L["Council-Items ("] .. n .. ")")
    end
    p.seg:Set(p.view)
    p.sourceBtn:Update()
    p.sourceBtn:SetShown(p.view == "items" or p.view == "mine")
    p.mine:SetShown(p.view == "mine")
    p.items:SetShown(p.view == "items")
    p.raid:SetShown(p.view == "raid")
    p.council:SetShown(p.view == "council")
    if p.view == "mine" then RefreshMine(p)
    elseif p.view == "items" then U.RefreshItemsView(p.items)
    elseif p.view == "raid" then RefreshRaid(p)
    else U.RefreshCouncilView(p.council) end
    local hint = HINTS[p.view]
    p.msg:SetText(p.msgText or ((hint and hint ~= "") and (H.muted .. L[hint] .. "|r") or ""))
end

U.CreateSetsPage, U.RefreshSets = CreateSetsPage, RefreshSets
