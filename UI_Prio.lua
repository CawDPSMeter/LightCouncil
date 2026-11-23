-- Light Council – Prio-Editor: Spieler anklicken = in Reihenfolge übernehmen
local _, LC = ...
local T = LC.T
local C = T.C
local H = T.HEX

local W, HGT = 640, 540
local PAD = 16
local ROW = 32
local frame
local leftRows, rightRows = {}, {}

-- Mögliche Spieler: Reservierer dieses Items zuerst, dann Raid, dann alle bekannten Spieler
local function Candidates(itemID, filter, exclude)
    local out, seen = {}, {}
    local function Add(name, tag)
        local key = LC:NameKey(name)
        if not key or seen[key] or exclude[key] then return end
        if filter ~= "" and not key:find(filter, 1, true) then return end
        seen[key] = true
        out[#out + 1] = { name = name, tag = tag }
    end
    for _, r in ipairs(LC:GetReservers(itemID)) do Add(r.name, "SR") end
    for _, m in pairs(LC:GetGroupMembers()) do Add(m.name, IsInRaid() and "Raid" or nil) end
    for _, n in ipairs(LC:GetKnownPlayers()) do Add(n, nil) end
    return out
end

local function RowButton(parent, width)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, ROW - 4)
    T:Skin(b, C.panel, { 0, 0, 0, 0 })
    b.text = T:Text(b, 13, C.text)
    b.text:SetPoint("LEFT", 12, 0)
    b.text:SetWordWrap(false)
    b.tag = T:Text(b, 11, C.accentLt, "RIGHT")
    b.tag:SetPoint("RIGHT", -10, 0)
    return b
end

local function Refresh()
    local s = frame.state
    -- rechte Seite: Reihenfolge
    local exclude = {}
    for i, name in ipairs(s.order) do
        exclude[LC:NameKey(name)] = true
        local r = rightRows[i]
        if not r then
            r = RowButton(frame.rightList, frame.colW - 12)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            r.text:SetPoint("RIGHT", -110, 0)
            r.up = T:Button(r, "↑", 28, 24, "ghost", function() LC:PrioMove(r.index, -1) end)
            r.down = T:Button(r, "↓", 28, 24, "ghost", function() LC:PrioMove(r.index, 1) end)
            r.del = T:Button(r, "×", 28, 24, "ghost", function() LC:PrioMove(r.index, 0) end)
            r.del:SetPoint("RIGHT", -4, 0)
            r.down:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
            r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
            r.del.tooltipTitle, r.del.tooltip = "Entfernen", "Spieler aus der Prio nehmen."
            rightRows[i] = r
        end
        r.index = i
        r.text:SetText(H.accentLt .. i .. ".|r  " .. name)
        r.up:SetEnabled(i > 1)
        r.down:SetEnabled(i < #s.order)
        r:Show()
    end
    for i = #s.order + 1, #rightRows do rightRows[i]:Hide() end
    frame.rightList:SetHeight(math.max(1, #s.order * ROW))
    frame.rightEmpty:SetShown(#s.order == 0)

    -- linke Seite: verfügbare Spieler
    local filter = (frame.search:GetText() or ""):lower()
    local list = Candidates(s.itemID, filter, exclude)
    for i, c in ipairs(list) do
        local r = leftRows[i]
        if not r then
            r = RowButton(frame.leftList, frame.colW - 12)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            r.text:SetPoint("RIGHT", -50, 0)
            r:SetScript("OnClick", function(self)
                table.insert(frame.state.order, self.playerName)
                Refresh()
            end)
            r:SetScript("OnEnter", function(self) self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.18) end)
            r:SetScript("OnLeave", function(self) self:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1) end)
            leftRows[i] = r
        end
        r.playerName = c.name
        r.text:SetText(c.name)
        r.tag:SetText(c.tag == "SR" and "SR" or (c.tag and (H.muted .. c.tag .. "|r") or ""))
        r:Show()
    end
    for i = #list + 1, #leftRows do leftRows[i]:Hide() end
    frame.leftList:SetHeight(math.max(1, #list * ROW))
    frame.leftEmpty:SetShown(#list == 0)
end

function LC:PrioMove(index, dir)
    local order = frame.state.order
    if dir == 0 then
        table.remove(order, index)
    else
        local j = index + dir
        if j >= 1 and j <= #order then order[index], order[j] = order[j], order[index] end
    end
    Refresh()
end

local function CreateFrame_()
    frame = T:Window("LightCouncilPrioFrame", W, HGT, "Prio festlegen", "Spieler anklicken – die Reihenfolge ist die Prio", 40)
    frame:SetFrameStrata("DIALOG")

    frame.icon = T:Icon(frame, 40)
    frame.icon:SetPoint("TOPLEFT", PAD, -56)
    frame.item = T:Text(frame, 15, C.text, "LEFT", nil, true)
    frame.item:SetPoint("LEFT", frame.icon, "RIGHT", 12, 6)
    frame.item:SetWidth(W - 100)
    frame.item:SetWordWrap(false)
    frame.info = T:Text(frame, 11, C.muted)
    frame.info:SetPoint("TOPLEFT", frame.item, "BOTTOMLEFT", 0, -4)
    frame.info:SetText("SR = hat das Item im Addon reserviert")

    frame.colW = math.floor((W - 2 * PAD - 14) / 2)
    local top = 112

    -- linke Spalte: Spieler
    local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    T:Skin(left, C.bgDark)
    left:SetPoint("TOPLEFT", PAD, -top)
    left:SetPoint("BOTTOMLEFT", PAD, 62)
    left:SetWidth(frame.colW)
    local lt = T:Text(left, 13, C.text, "LEFT", nil, true)
    lt:SetPoint("TOPLEFT", 12, -12)
    lt:SetText("Spieler")
    frame.search = T:Input(left, frame.colW - 24, 28)
    frame.search:SetPoint("TOPLEFT", 12, -36)
    frame.search:SetPlaceholder("Suchen …")
    frame.search:HookScript("OnTextChanged", function() if frame.state then Refresh() end end)
    local lsf, lcontent = T:Scroll(left)
    lsf:SetPoint("TOPLEFT", 6, -74)
    lsf:SetPoint("BOTTOMRIGHT", -14, 8)
    frame.leftList = lcontent
    frame.leftEmpty = T:Text(left, 12, C.muted, "CENTER")
    frame.leftEmpty:SetPoint("TOP", lsf, "TOP", 0, -20)
    frame.leftEmpty:SetWidth(frame.colW - 30)
    frame.leftEmpty:SetText("Keine weiteren Spieler.\nSpieler erscheinen, sobald sie reservieren, im Raid oder nach dem ersten Boss-Kill.")

    -- rechte Spalte: Reihenfolge
    local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    T:Skin(right, C.bgDark)
    right:SetPoint("TOPRIGHT", -PAD, -top)
    right:SetPoint("BOTTOMRIGHT", -PAD, 62)
    right:SetWidth(frame.colW)
    local rt = T:Text(right, 13, C.text, "LEFT", nil, true)
    rt:SetPoint("TOPLEFT", 12, -12)
    rt:SetText("Prio-Reihenfolge")
    local rsf, rcontent = T:Scroll(right)
    rsf:SetPoint("TOPLEFT", 6, -40)
    rsf:SetPoint("BOTTOMRIGHT", -14, 8)
    frame.rightList = rcontent
    frame.rightEmpty = T:Text(right, 12, C.muted, "CENTER")
    frame.rightEmpty:SetPoint("TOP", rsf, "TOP", 0, -20)
    frame.rightEmpty:SetWidth(frame.colW - 30)
    frame.rightEmpty:SetText("Noch keine Prio.\nLinks Spieler anklicken – der erste hat die höchste Prio.")

    -- Knöpfe
    local save = T:Button(frame, "Speichern", 140, 34, "primary", function()
        LC:SetPrio(frame.state.itemID, frame.state.order)
        frame:Hide()
        LC:RefreshUI()
    end)
    save:SetPoint("BOTTOMRIGHT", -PAD, 16)
    local cancel = T:Button(frame, "Abbrechen", 120, 34, "ghost", function() frame:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    local clear = T:Button(frame, "Prio löschen", 130, 34, "danger", function()
        wipe(frame.state.order)
        Refresh()
    end)
    clear:SetPoint("BOTTOMLEFT", PAD, 16)
end

function LC:OpenPrioEditor(itemID)
    if not itemID then return end
    if not frame then CreateFrame_() end
    local current = self:GetPrio(itemID) or {}
    local order = {}
    for i, n in ipairs(current) do order[i] = n end
    frame.state = { itemID = itemID, order = order }
    frame.icon.tex:SetTexture(self:ItemIcon(itemID))
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = getInfo(itemID)
    local qc = T:QualityColor(quality)
    frame.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
    frame.item:SetText(self:ItemLink(itemID))
    frame.search:SetText("")
    frame:Show()
    Refresh()
end
