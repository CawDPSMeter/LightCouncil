-- Light Council – Hauptfenster, Seite: Mein Gear
--   „Mein Set“    : Kacheln wie im Charakterfenster (ein Item pro Slot, Würfel = reservieren)
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

local PLAYER_ROW = 44
local playerRows = {}
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local STAR_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

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
    -- Keine Beschreibung: was zu tun ist, sagt der Hinweis „Nächster Schritt“
    local _, ht = PageHeader(p, L["Mein Gear"], "")
    local y = math.ceil(ht:GetStringHeight() + 14)
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

    -- Set-Auswahl als Aufklappmenü (Wechseln, Neu, Umbenennen, Löschen)
    mine.setBtn = T:Button(mine, "", 220, 30, "default", function(self)
        local order, active = LC:GetMySets()
        local entries = {}
        for _, name in ipairs(order) do
            entries[#entries + 1] = { text = name, checked = (name == active), func = function() LC:SetActiveGearSet(name) end }
        end
        if #entries > 0 then entries[#entries + 1] = { text = "-" } end
        entries[#entries + 1] = { text = L["Neues Set …"], func = function() StaticPopup_Show("LIGHTCOUNCIL_NEW_SET") end }
        if active then
            entries[#entries + 1] = { text = L["Umbenennen …"], func = function()
                local d = StaticPopup_Show("LIGHTCOUNCIL_RENAME_SET", active, nil, active)
                if d then d.data = active end
            end }
            entries[#entries + 1] = { text = L["Löschen …"], color = C.bad, func = function()
                local d = StaticPopup_Show("LIGHTCOUNCIL_DELETE_SET", active, nil, active)
                if d then d.data = active end
            end }
        end
        U.ShowMenu(self, entries)
    end)
    mine.setBtn:SetPoint("TOPLEFT", 0, 0)
    Tip(mine.setBtn, L["Dein Set"], L["Wechseln, neues Set anlegen, umbenennen oder löschen. Dein aktives Set sehen alle – so weiß der Council, wo du im Gear stehst."])

    mine.progress = T:Text(mine, 12, C.muted, "LEFT")
    mine.progress:SetPoint("LEFT", mine.setBtn, "RIGHT", 14, 0)

    -- Hinzufügen: Name oder ID tippen (Suche), Shift-Klick oder ID + Enter
    mine.input = T:Input(mine, 300, 30)
    mine.input:SetPoint("TOPRIGHT", 0, 0)
    mine.input:SetPlaceholder(L["Item suchen oder Shift-Klick"])
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

    -- „Nächster Schritt“: ein Satz, was jetzt zu tun ist, und höchstens ein Hauptknopf
    local nb = Card(mine, 48)
    nb:SetPoint("TOPLEFT", 0, -42)
    nb:SetWidth(CW)
    nb:SetBackdropColor(0.115, 0.085, 0.16, 1)
    mine.next = nb
    nb.bar = nb:CreateTexture(nil, "ARTWORK")
    nb.bar:SetTexture(T.WHITE)
    nb.bar:SetPoint("TOPLEFT", 1, -1)
    nb.bar:SetPoint("BOTTOMLEFT", 1, 1)
    nb.bar:SetWidth(3)
    nb.text = T:Text(nb, 13, C.text, "LEFT")
    nb.text:SetPoint("LEFT", 16, 0)
    nb.text:SetWordWrap(true)
    nb.main = T:Button(nb, "", 190, 30, "primary")
    nb.main:SetPoint("RIGHT", -9, 0)
    nb.main:SetScript("OnClick", function() if nb.onMain then nb.onMain() end end)
    nb.alt = T:Button(nb, "", 130, 30, "ghost")
    nb.alt:SetScript("OnClick", function() if nb.onAlt then nb.onAlt() end end)


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
-- „Mein Gear“: links ein Charakterbogen wie im Charakterfenster (3D-Modell + Slots),
-- rechts die Slots als Liste mit Quelle und Würfel zum Reservieren
------------------------------------------------------------------------
local DOLL_W, SLOT, SLOT_GAP = 330, 40, 5
local ROW_H, HEAD_H = 34, 28
local ROW_W = CW - DOLL_W - 10 - 16 - 14
local DICE_TEX = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local ARROW_TEX = "Interface\\Buttons\\Arrow-Up-Up"
local CHECK_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
-- Anordnung wie im Charakterfenster (Hemd und Wappenrock nur als Platzhalter)
local DOLL_LEFT = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST" }
local DOLL_RIGHT = { "HANDS", "WAIST", "LEGS", "FEET", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2" }
local DOLL_BOTTOM = { "MAINHAND", "OFFHAND", "RANGED" }
local INV_NAME = {
    HEAD = "HeadSlot", NECK = "NeckSlot", SHOULDER = "ShoulderSlot", BACK = "BackSlot", CHEST = "ChestSlot",
    SHIRT = "ShirtSlot", TABARD = "TabardSlot", WRIST = "WristSlot", HANDS = "HandsSlot", WAIST = "WaistSlot",
    LEGS = "LegsSlot", FEET = "FeetSlot", FINGER1 = "Finger0Slot", FINGER2 = "Finger1Slot",
    TRINKET1 = "Trinket0Slot", TRINKET2 = "Trinket1Slot", MAINHAND = "MainHandSlot",
    OFFHAND = "SecondaryHandSlot", RANGED = "RangedSlot",
}
local entries = {}   -- [slotKey] = { key, itemID, upID, important, owned, slotLabel, doll, row }

-- Leeres Slot-Bild aus dem Spiel (wie im Charakterfenster)
local emptyTex = {}
local function EmptyTex(key)
    if emptyTex[key] == nil then
        local ok, _, tex = pcall(GetInventorySlotInfo, INV_NAME[key] or "")
        emptyTex[key] = (ok and tex) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
    end
    return emptyTex[key]
end

-- Reservierungs-Stand eines Items: Raid-Schlüssel, Raid-Name, ausgewählt, gespeichert
local function ResInfo(id)
    local src = id and LC:ItemSource(id)
    if not src then return nil end
    local key = src.raid.key
    local rec = LC:GetReservation(key)
    local saved = false
    for _, x in ipairs(rec and rec.items or {}) do if x == id then saved = true end end
    return key, src.raid.name, U.ResSelected(key, id), saved
end

local function ToggleRes(id, raidKey)
    local ok, msg = U.ResToggle(raidKey, id, not U.ResSelected(raidKey, id))
    pages.sets.mine.resKey = raidKey
    SetMsg((not ok) and msg or nil)
    LC:RefreshUI()
end

local function ShowItems()
    pages.sets.view = "items"
    pages.sets.msgText = nil
    LC:RefreshUI()
end

-- Einträge fürs Upgrade eines Slots (Upgrades können nicht „wichtig“ sein)
local function UpgradeEntries(m, e)
    local up = e.upID
    local ukey, uname, uon = ResInfo(up)
    if ukey then m[#m + 1] = { text = L("Upgrade reservieren (%s)", uname), checked = uon, func = function() ToggleRes(up, ukey) end } end
    m[#m + 1] = { text = L["Upgrade entfernen"], func = function() LC:RemoveFromGearSet(up, e.key, true) end }
end

-- Menü eines Slots (Klick)
local function SlotMenu(e)
    local id, up = e.itemID, e.upID
    local m = {}
    if id then
        local key, name, on = ResInfo(id)
        if key then m[#m + 1] = { text = L("Reservieren (%s)", name), checked = on, func = function() ToggleRes(id, key) end } end
        m[#m + 1] = { text = L["Wichtig"], checked = e.important, func = function() LC:ToggleGearSetImportant(id) end }
    end
    if up then
        if id then m[#m + 1] = { text = "-" } end
        UpgradeEntries(m, e)
    end
    m[#m + 1] = { text = L["Anderes Item wählen …"], func = ShowItems }
    if id then
        m[#m + 1] = { text = "-" }
        m[#m + 1] = { text = L["Aus dem Set entfernen"], color = C.bad, func = function() LC:RemoveFromGearSet(id, e.key) end }
    end
    return m
end

local function SlotClick(e, anchor)
    if not e then return end
    if not e.itemID then
        if e.upID then U.ShowMenu(anchor, SlotMenu(e)) else ShowItems() end
        return
    end
    if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
        ChatEdit_InsertLink(LC:ItemLink(e.itemID))
        return
    end
    GameTooltip:Hide()
    U.ShowMenu(anchor, SlotMenu(e))
end

local function SlotTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.itemID then
        GameTooltip:SetItemByID(e.itemID)
        GameTooltip:AddLine(" ")
        if e.owned then GameTooltip:AddLine(CHECK .. " " .. L["Hast du schon."], C.good[1], C.good[2], C.good[3]) end
        if e.important then GameTooltip:AddLine(LC.STAR .. " " .. L["Wichtig"], C.accentLt[1], C.accentLt[2], C.accentLt[3]) end
        if e.upID then GameTooltip:AddLine(LC.UPGRADE .. " " .. L["Upgrade"] .. ": " .. LC:ItemLink(e.upID), C.warn[1], C.warn[2], C.warn[3]) end
        GameTooltip:AddLine(L["Klick: Optionen  ·  Shift-Klick: im Chat verlinken"], C.muted[1], C.muted[2], C.muted[3])
    else
        GameTooltip:SetText(e.slotLabel or "", 1, 1, 1)
        GameTooltip:AddLine(L["Noch kein Item. Klick öffnet die Item-Übersicht – oder oben Name bzw. ID eintippen."], nil, nil, nil, true)
    end
    GameTooltip:Show()
end

-- Slot im Bogen und Zeile in der Liste gemeinsam hervorheben
local function Highlight(e, on)
    if not e then return end
    if e.doll then
        if on then T:SetBorder(e.doll, C.accentLt)
        elseif e.itemID then ItemQualityBorder(e.doll, e.itemID)
        else T:SetBorder(e.doll, C.line) end
    end
    if e.row then
        local bg = on and C.panelAlt or (e.row.alt and C.panel or C.bg)
        e.row:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    end
end

------------------------------------------------------------ Bausteine
local function MakeDice(parent, size)
    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(size, size)
    T:Skin(d, C.bgDark, C.line)
    d.tex = d:CreateTexture(nil, "ARTWORK")
    d.tex:SetTexture(DICE_TEX)
    d.tex:SetSize(size - 6, size - 6)
    d.tex:SetPoint("CENTER")
    d:SetScript("OnClick", function(self) if self.raidKey then ToggleRes(self.itemID, self.raidKey) end end)
    d:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Reservieren für %s", self.raidName or "?"), 1, 1, 1)
        local text
        if self.on and self.saved then text = H.good .. L["Reserviert und gespeichert."] .. "|r"
        elseif self.on then text = H.warn .. L["Ausgewählt – noch nicht gespeichert. Speichern geht oben im Hinweis."] .. "|r"
        else text = L("Klick wählt das Item für deine Reservierung aus (höchstens %d pro Raid).", LC:MaxReserves()) end
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    d:SetScript("OnLeave", GameTooltip_Hide)
    return d
end

local function PaintDice(d, id)
    local key, name, on, saved = ResInfo(id)
    d.itemID, d.raidKey, d.raidName, d.on, d.saved = id, key, name, on, saved
    d:SetShown(key ~= nil)
    if not key then return end
    d.tex:SetDesaturated(not on)
    d.tex:SetAlpha(on and 1 or 0.4)
    T:SetBorder(d, (on and saved) and C.good or (on and C.accent or C.line))
    local bg = on and C.accentDim or C.bgDark
    d:SetBackdropColor(bg[1], bg[2], bg[3], 1)
end

-- Kennzeichen „Upgrade“: Pfeil ohne Kästchen, mit dunklem Schatten – auf jedem Icon gut sichtbar
local function UpgradeBadge(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetFrameLevel(parent:GetFrameLevel() + 4)
    f.shadow = f:CreateTexture(nil, "ARTWORK")
    f.shadow:SetTexture(ARROW_TEX)
    f.shadow:SetVertexColor(0, 0, 0, 1)
    f.shadow:SetSize(size + 4, size + 4)
    f.shadow:SetPoint("CENTER", 1, -1)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetTexture(ARROW_TEX)
    f.tex:SetSize(size, size)
    f.tex:SetPoint("CENTER")
    return f
end

local function MakeUpgradeIcon(parent, size, getID)
    local u = T:Icon(parent, size)
    u:EnableMouse(true)
    u.arrow = UpgradeBadge(u, 18)
    u.arrow:SetPoint("RIGHT", u, "LEFT", -2, 0)   -- Pfeil links neben dem Upgrade-Item
    u:SetScript("OnEnter", function(self)
        local id = getID()
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(LC.UPGRADE .. " " .. L["Upgrade: zweite Wahl für diesen Slot. Zählt nur, solange dir das beste Item darüber fehlt."], C.warn[1], C.warn[2], C.warn[3], true)
        GameTooltip:Show()
    end)
    u:SetScript("OnLeave", GameTooltip_Hide)
    return u
end

-- Slot im Charakterbogen
local function MakeDollSlot(parent, key)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    T:Skin(b, C.bgDark, C.line)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.tex:SetTexture(EmptyTex(key))
    if key == "SHIRT" or key == "TABARD" then
        -- Zählt nicht – nur damit der Bogen aussieht wie im Spiel
        b.tex:SetDesaturated(true)
        b:SetAlpha(0.3)
        b:EnableMouse(false)
        return b
    end
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture(CHECK_TEX)
    b.check:SetSize(15, 15)
    b.check:SetPoint("TOPLEFT", -4, 4)
    b.star = b:CreateTexture(nil, "OVERLAY")
    b.star:SetTexture(STAR_TEX)
    b.star:SetSize(14, 14)
    b.star:SetPoint("TOPRIGHT", 4, 4)
    b.dice = b:CreateTexture(nil, "OVERLAY")
    b.dice:SetTexture(DICE_TEX)
    b.dice:SetSize(17, 17)
    b.dice:SetPoint("BOTTOMLEFT", -4, -4)
    b:SetScript("OnClick", function(self) SlotClick(self.e, self) end)
    b:SetScript("OnEnter", function(self) Highlight(self.e, true) if self.e then SlotTooltip(self, self.e) end end)
    b:SetScript("OnLeave", function(self) Highlight(self.e, false) GameTooltip:Hide() end)
    return b
end

local function PaintDollSlot(b, e)
    if not b.check then return end
    if e.itemID then
        b.tex:SetTexture(LC:ItemIcon(e.itemID))
        ItemQualityBorder(b, e.itemID)
    else
        b.tex:SetTexture(EmptyTex(e.key))
        T:SetBorder(b, C.line)
    end
    b.check:SetShown(e.owned)
    b.star:SetShown(e.important)
    local _, _, on = ResInfo(e.itemID)
    local _, _, uon = ResInfo(e.upID)
    b.dice:SetShown((on or uon) and true or false)
end

-- Zeile in der Liste
local function MakeRow(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetSize(ROW_W, ROW_H - 2)
    T:Skin(r, C.bg, { 0, 0, 0, 0 })
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.stripe = r:CreateTexture(nil, "ARTWORK")
    r.stripe:SetTexture(T.WHITE)
    r.stripe:SetVertexColor(unpack(C.good))
    r.stripe:SetPoint("TOPLEFT")
    r.stripe:SetPoint("BOTTOMLEFT")
    r.stripe:SetWidth(2)
    r.slot = T:Text(r, 12, C.muted, "LEFT")
    r.slot:SetPoint("LEFT", 10, 0)
    r.slot:SetWidth(74)
    r.slot:SetWordWrap(false)
    r.icon = T:Icon(r, 26)
    r.icon:SetPoint("LEFT", 88, 0)
    r.name = T:Text(r, 13, C.text, "LEFT")
    r.name:SetPoint("LEFT", 122, 0)
    r.name:SetWordWrap(false)
    r.src = T:Text(r, 11, C.muted, "RIGHT")
    r.src:SetWordWrap(false)
    r.dice = MakeDice(r, 26)
    r.dice:SetPoint("RIGHT", -4, 0)
    r.up = MakeUpgradeIcon(r, 22, function() return r.e and r.e.upID end)
    -- Klick aufs Upgrade: nur die Upgrade-Optionen (nicht „Wichtig“ des besten Items)
    r.up:SetScript("OnMouseUp", function(self)
        GameTooltip:Hide()
        if r.e and r.e.upID then
            local m = {}
            UpgradeEntries(m, r.e)
            m[#m + 1] = { text = L["Anderes Item wählen …"], func = ShowItems }
            U.ShowMenu(self, m)
        end
    end)
    r:SetScript("OnClick", function(self) SlotClick(self.e, self) end)
    r:SetScript("OnEnter", function(self) Highlight(self.e, true) if self.e then SlotTooltip(self, self.e) end end)
    r:SetScript("OnLeave", function(self) Highlight(self.e, false) GameTooltip:Hide() end)
    return r
end

local function PaintRow(r, e)
    r.stripe:SetShown(e.owned)
    r.slot:SetText(e.slotLabel)
    if e.itemID then
        r.icon.tex:SetTexture(LC:ItemIcon(e.itemID))
        r.icon.tex:Show()
        ItemQualityBorder(r.icon, e.itemID)
        r.icon:Show()
        r.name:SetText(LC:ItemLink(e.itemID))
        local src = LC:ItemSource(e.itemID)
        r.src:SetText(src and src.boss.name or "")
    else
        r.icon:Hide()
        r.name:SetText(H.muted .. L["+ Item wählen"] .. "|r")
        r.src:SetText("")
    end
    PaintDice(r.dice, e.itemID)
    -- Rechts von außen nach innen: Würfel, Upgrade, Quelle
    local x = -4 - (r.dice:IsShown() and 32 or 0)
    r.up:ClearAllPoints()
    if e.upID then
        r.up:SetPoint("RIGHT", x - 2, 0)
        r.up.tex:SetTexture(LC:ItemIcon(e.upID))
        local _, _, uon = ResInfo(e.upID)
        if uon then T:SetBorder(r.up, C.accent) else ItemQualityBorder(r.up, e.upID) end
        r.up:Show()
        x = x - 32 - 20
    else
        r.up:Hide()
    end
    r.src:ClearAllPoints()
    r.src:SetPoint("RIGHT", x - 6, 0)
    local srcW = e.itemID and 110 or 0
    r.src:SetWidth(srcW)
    r.name:SetWidth(ROW_W - 122 + x - 6 - srcW - 8)
    local bg = r.alt and C.panel or C.bg
    r:SetBackdropColor(bg[1], bg[2], bg[3], 1)
end

------------------------------------------------------------ 3D-Modell
local function DressModel(m)
    if not m:IsVisible() then return end
    pcall(m.SetUnit, m, "player")
    m:SetFacing(m.facing or 0)
    if m.SetPortraitZoom then m:SetPortraitZoom(m.zoom or 0) end
    if m.mode ~= "now" then
        local set = LC:GetActiveSet()
        for _, id in pairs(set and set.slots or {}) do pcall(m.TryOn, m, "item:" .. id) end
    end
end

local function MakeModel(parent)
    local m = CreateFrame("DressUpModel", nil, parent)
    m.facing, m.zoom, m.mode = 0, 0, "set"
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    m:SetScript("OnMouseUp", function(self, btn)
        self.dragX = nil
        if btn == "RightButton" then
            self.facing, self.zoom = 0, 0
            self:SetFacing(0)
            if self.SetPortraitZoom then self:SetPortraitZoom(0) end
        end
    end)
    m:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = (self.facing + (x - self.dragX) / 90) % (2 * math.pi)
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    m:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0, math.min(0.8, (self.zoom or 0) + delta * 0.1))
        if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
    end)
    m:SetScript("OnShow", function(self) C_Timer.After(0, function() DressModel(self) end) end)
    return m
end

------------------------------------------------------------ Aufbau
local function BuildMine(mine)
    mine.built = true

    -- Links: Charakterbogen
    local doll = Card(mine)
    doll:SetPoint("TOPLEFT", 0, -98)
    doll:SetPoint("BOTTOMLEFT", 0, 24)
    doll:SetWidth(DOLL_W)
    doll:SetBackdropColor(C.bgDark[1], C.bgDark[2], C.bgDark[3], 1)
    mine.doll = doll
    mine.dollSlots = {}
    for i, key in ipairs(DOLL_LEFT) do
        local b = MakeDollSlot(doll, key)
        b:SetPoint("TOPLEFT", 10, -10 - (i - 1) * (SLOT + SLOT_GAP))
        mine.dollSlots[key] = b
    end
    for i, key in ipairs(DOLL_RIGHT) do
        local b = MakeDollSlot(doll, key)
        b:SetPoint("TOPRIGHT", -10, -10 - (i - 1) * (SLOT + SLOT_GAP))
        mine.dollSlots[key] = b
    end
    local bw = #DOLL_BOTTOM * SLOT + (#DOLL_BOTTOM - 1) * 8
    for i, key in ipairs(DOLL_BOTTOM) do
        local b = MakeDollSlot(doll, key)
        b:SetPoint("BOTTOMLEFT", math.floor((DOLL_W - bw) / 2) + (i - 1) * (SLOT + 8), 10)
        mine.dollSlots[key] = b
    end

    local model = MakeModel(doll)
    model:SetPoint("TOPLEFT", SLOT + 16, -34)
    model:SetPoint("BOTTOMRIGHT", -(SLOT + 16), SLOT + 34)
    mine.model = model

    -- Umschalter über dem Modell: Set anprobieren oder aktuelle Ausrüstung
    local function ModeButton(label, mode)
        local b = T:Button(doll, label, 84, 22, "default", function()
            model.mode = mode
            DressModel(model)
            LC:RefreshUI()
        end)
        b.mode = mode
        return b
    end
    mine.modeSet = ModeButton(L["Dein Set"], "set")
    mine.modeNow = ModeButton(L["Jetzt"], "now")
    mine.modeSet:SetPoint("TOP", doll, "TOP", -42, -8)
    mine.modeNow:SetPoint("LEFT", mine.modeSet, "RIGHT", -1, 0)
    Tip(mine.modeSet, L["Dein Set"], L["Das Modell trägt die Items aus deinem Set."])
    Tip(mine.modeNow, L["Jetzt"], L["Das Modell trägt, was du gerade anhast."])

    local hint = T:Text(doll, 10, C.muted, "CENTER")
    hint:SetPoint("BOTTOM", doll, "BOTTOM", 0, SLOT + 16)
    hint:SetText(L["Ziehen: drehen  ·  Mausrad: zoomen  ·  Rechtsklick: zurück"])

    -- Rechts: Liste
    local right = Card(mine)
    right:SetPoint("TOPLEFT", DOLL_W + 10, -98)
    right:SetPoint("BOTTOMRIGHT", 0, 24)
    local sf, content = T:Scroll(right)
    sf:SetPoint("TOPLEFT", 8, -6)
    sf:SetPoint("BOTTOMRIGHT", -16, 6)
    mine.list = content
    mine.rows, mine.heads = {}, {}
    local y, lastGroup, n = 0, nil, 0
    for _, s in ipairs(LC.GEAR_SLOTS) do
        if s.group ~= lastGroup then
            lastGroup = s.group
            local h = CreateFrame("Frame", nil, content)
            h:SetSize(ROW_W, HEAD_H)
            h:SetPoint("TOPLEFT", 0, -y)
            h.title = T:Text(h, 11, C.accentLt, "LEFT", nil, true)
            h.title:SetPoint("BOTTOMLEFT", 4, 6)
            h.title:SetText(L[LC.GEAR_GROUPS[s.group]])
            h.count = T:Text(h, 11, C.muted, "LEFT")
            h.count:SetPoint("LEFT", h.title, "RIGHT", 10, 0)
            mine.heads[s.group] = h
            y, n = y + HEAD_H, 0
        end
        n = n + 1
        local r = MakeRow(content)
        r.alt = (n % 2 == 0)
        r:SetPoint("TOPLEFT", 0, -y)
        mine.rows[s.key] = r
        y = y + ROW_H
    end
    content:SetHeight(y)
end

-- Bogen und Liste mit dem aktiven Set füllen. Rückgabe: belegt, hast du, irgendwas im Set, Raids
local function PaintMine(mine, set)
    local filled, have, any = 0, 0, false
    local raidsInSet = {}
    local groups = {}
    for i, s in ipairs(LC.GEAR_SLOTS) do
        local e = entries[s.key] or { key = s.key }
        entries[s.key] = e
        local id = set and set.slots[s.key]
        local up = set and set.upgrades and set.upgrades[s.key]
        e.itemID, e.upID = id, up
        e.slotLabel = LC:GearSlotLabel(s.key)
        e.owned = (id and LC:HaveItem(id)) and true or false
        e.important = (id and (set.important or {})[id] == true) and true or false
        e.doll, e.row = mine.dollSlots[s.key], mine.rows[s.key]
        if e.doll then e.doll.e = e PaintDollSlot(e.doll, e) end
        e.row.e = e
        PaintRow(e.row, e)

        local g = groups[s.group] or { total = 0, have = 0 }
        groups[s.group] = g
        g.total = g.total + 1
        if id then
            filled = filled + 1
            if e.owned then have, g.have = have + 1, g.have + 1 end
        end
        for _, x in ipairs({ id or false, up or false }) do
            if x then
                any = true
                local src = LC:ItemSource(x)
                if src and not raidsInSet[src.raid.key] then
                    raidsInSet[src.raid.key] = { key = src.raid.key, name = src.raid.name, order = i }
                end
            end
        end
    end
    for g, h in pairs(mine.heads) do
        local st = groups[g] or { total = 0, have = 0 }
        h.count:SetText(L("%d von %d hast du", st.have, st.total))
    end

    -- Modell: nur neu anziehen, wenn sich das Set geändert hat
    local model = mine.model
    local sig = {}
    for _, s in ipairs(LC.GEAR_SLOTS) do sig[#sig + 1] = tostring(set and set.slots[s.key] or 0) end
    sig = model.mode .. table.concat(sig, ",")
    if sig ~= model.sig then
        model.sig = sig
        DressModel(model)
    end
    for _, b in ipairs({ mine.modeSet, mine.modeNow }) do
        b.selected = (b.mode == model.mode)
        if b.selected then
            b:SetBackdropColor(C.accentDim[1], C.accentDim[2], C.accentDim[3], 1)
            T:SetBorder(b, C.accent)
        else
            b.Paint(false)
        end
    end
    return filled, have, any, raidsInSet
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
    local _, active = LC:GetMySets()
    local set = LC:GetActiveSet()

    mine.setBtn:SetText((active and (L["Set: "] .. active) or L["Noch kein Set"]) .. "   |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-4|t")
    mine.setBtn:SetWidth(math.min(300, math.max(170, math.ceil(mine.setBtn:GetFontString():GetStringWidth()) + 36)))

    if not mine.built then BuildMine(mine) end
    local filled, have, any, raidsInSet = PaintMine(mine, set)
    mine.progress:SetText(any and L("%d von %d Slots  ·  %d hast du", filled, #LC.GEAR_SLOTS, have) or "")

    -- Raid für den Hinweis: zuletzt angeklickter, sonst einer mit ungespeicherter Auswahl,
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

    -- „Nächster Schritt“
    local nb = mine.next
    local text, accent, mainText, onMain, altText, onAlt
    local function Open() LC:OpenReservation(key) end
    if not any then
        text = L["Wähl für jeden Slot dein Wunsch-Item: Klick auf einen freien Slot oder such oben nach dem Namen."]
        accent = C.accent
        mainText, onMain = L["Items durchsuchen"], ShowItems
    elseif not key then
        text = L["Dein Set steht. Droppt ein Item in einem Raid, reservierst du es mit dem Würfel in der Liste."]
        accent = C.accent
        altText, onAlt = L["Meine Reservierung"], Open
    else
        local changed, locked, pending = U.ResState(key)
        local sel = U.ResSel(key)
        local max = LC:MaxReserves()
        local name = raidsInSet[key] and raidsInSet[key].name
        if not name then
            for _, r in ipairs(LC:GetLootDB() or {}) do if r.key == key then name = r.name end end
        end
        name = name or key
        if pending then
            text = H.warn .. L["Änderung beantragt"] .. "|r  " .. L("Der Council entscheidet über deine Reservierung für %s.", name)
            accent = C.warn
            altText, onAlt = L["Ansehen"], Open
        elseif changed and locked then
            text = L("Du hast deine gespeicherte Reservierung für %s geändert. Dafür braucht der Council eine kurze Begründung.", name)
            accent = C.warn
            mainText, onMain = L["Änderung beantragen"], Open
        elseif changed and #sel > 0 then
            text = L("%d von %d gewählt für %s", #sel, max, name) .. "  " .. IconRow(sel)
                .. "\n" .. H.muted .. L["Nach dem Speichern ist deine Wahl gesperrt."] .. "|r"
            accent = C.warn
            mainText = L("Reservierung speichern (%d/%d)", #sel, max)
            onMain = function() U.ResConfirm(key, "sets") end
        elseif locked then
            text = H.good .. L("Reservierung für %s gespeichert", name) .. "|r  " .. IconRow(sel)
            accent = C.good
            altText, onAlt = L["Ansehen"], Open
        elseif #sel > 0 then
            text = L("Reservierung für %s gespeichert", name) .. "  " .. IconRow(sel)
                .. "\n" .. H.muted .. L["Wartet auf Bestätigung durch den Council."] .. "|r"
            accent = C.accent
            altText, onAlt = L["Ansehen"], Open
        else
            text = L("Klick auf den Würfel bei bis zu %d Items aus %s, um sie zu reservieren.", max, name)
            accent = C.accent
            altText, onAlt = L["Ganze Raid-Liste"], Open
        end
        local others = 0
        for _, info in ipairs(list) do
            if info.key ~= key and U.ResState(info.key) then others = others + 1 end
        end
        if others > 0 then text = text .. "  " .. H.warn .. L("(+%d Raid(s) nicht gespeichert)", others) .. "|r" end
    end

    nb.bar:SetVertexColor(accent[1], accent[2], accent[3], 1)
    nb.onMain, nb.onAlt = onMain, onAlt
    nb.main:SetShown(mainText ~= nil)
    if mainText then
        nb.main:SetText(mainText)
        nb.main:SetWidth(math.max(150, math.ceil(nb.main:GetFontString():GetStringWidth()) + 32))
    end
    nb.alt:SetShown(altText ~= nil)
    if altText then
        nb.alt:SetText(altText)
        nb.alt:SetWidth(math.max(100, math.ceil(nb.alt:GetFontString():GetStringWidth()) + 28))
        nb.alt:ClearAllPoints()
        if mainText then nb.alt:SetPoint("RIGHT", nb.main, "LEFT", -6, 0) else nb.alt:SetPoint("RIGHT", -9, 0) end
    end
    local right = 9 + (mainText and (nb.main:GetWidth() + 6) or 0) + (altText and (nb.alt:GetWidth() + 6) or 0)
    nb.text:SetWidth(CW - 16 - right - 6)
    nb.text:SetText(text)
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
    mine = "",
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
    p.sourceBtn:SetShown(p.view == "items")
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

-- Modus „Jetzt“: nach einem Ausrüstungswechsel neu anziehen
LC:On("PLAYER_EQUIPMENT_CHANGED", function()
    local mine = pages.sets and pages.sets.mine
    local m = mine and mine.model
    if m and m.mode == "now" and m:IsVisible() then
        C_Timer.After(0.2, function() DressModel(m) end)
    end
end)
