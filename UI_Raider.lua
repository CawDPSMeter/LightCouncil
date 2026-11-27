-- Light Council – Fenster für Raider: Loot-Übersicht mit Würfel-Knopf und Hinweis bei Ausschluss
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX

local W = 680
local PAD = 12
local ROW_H = 74
local STATE_W = 170                            -- Zustand oben rechts ("vergeben", "Dein Wurf: 87")
local TEXT_W = W - 2 * PAD - 50 - STATE_W - 20   -- Itemname und Reservierer, laufen nie in den Zustand
local frame, notice
local rows = {}

------------------------------------------------------------------------
-- Loot-Fenster
------------------------------------------------------------------------
local function CreateRaidFrame()
    frame = T:Window("LightCouncilRaidFrame", W, 200, L["Loot"], L["Würfeln per Knopfdruck · alle sehen die Ergebnisse"])
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -220, 40)
    frame:SetFrameStrata("MEDIUM")

    frame.hint = T:Text(frame, 10, C.muted)
    frame.hint:SetPoint("BOTTOMLEFT", PAD, 10)
    frame.hint:SetWidth(W - 2 * PAD)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.25 then return end
        self.acc = 0
        local R = LC.raid
        if R and R.activeIdx then LC:RefreshRaidFrame() end
    end)
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    r:SetSize(W - 2 * PAD, ROW_H - 6)
    T:Skin(r, C.panel)

    r.icon = T:Icon(r, 36)
    r.icon:SetPoint("TOPLEFT", 6, -6)

    r.linkBtn = CreateFrame("Button", nil, r)
    r.linkBtn:SetPoint("TOPLEFT", 50, -7)
    r.linkBtn:SetSize(TEXT_W, 34)   -- deckt Itemname und Reservierer-Zeile ab (Tooltip)
    r.link = T:Text(r.linkBtn, 12, C.text)
    r.link:SetPoint("TOPLEFT")
    r.link:SetWidth(TEXT_W)
    r.link:SetWordWrap(false)
    r.linkBtn:SetScript("OnEnter", function(self)
        if r.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(r.itemID)
            -- Alle Reservierer, falls die Zeile zu kurz ist
            local it = r.it
            if it and it.reservers and #it.reservers > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Reserviert ("] .. #it.reservers .. "):", 0.7, 0.55, 1)
                GameTooltip:AddLine(table.concat(it.reservers, ", "), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    r.linkBtn:SetScript("OnLeave", GameTooltip_Hide)

    r.who = T:Text(r, 10, C.muted)
    r.who:SetPoint("TOPLEFT", 50, -26)
    r.who:SetWidth(TEXT_W)
    r.who:SetWordWrap(false)

    r.rolls = T:Text(r, 10, C.text)
    r.rolls:SetPoint("BOTTOMLEFT", 50, 8)
    r.rolls:SetWidth(W - 2 * PAD - 60)
    r.rolls:SetWordWrap(false)

    r.btn = T:Button(r, L["Würfeln"], 96, 28, "primary", function() LC:RaidRoll(r.idx) end)
    r.btn:SetPoint("TOPRIGHT", -8, -8)
    -- Beim freien Würfeln: zweiter Knopf für Off Spec (/roll 99) unter "Main Spec"
    r.btnOS = T:Button(r, L["Off Spec"], 96, 24, "default", function() LC:RaidRoll(r.idx, true) end)
    r.btnOS:SetPoint("TOPRIGHT", r.btn, "BOTTOMRIGHT", 0, -4)
    r.btnOS.tooltipTitle = L["Off Spec"]
    r.btnOS.tooltip = L["Würfelt /roll 99. Off Spec zählt nur, wenn niemand für Main Spec würfelt."]
    r.btnOS:Hide()
    r.state = T:Text(r, 11, C.muted, "RIGHT")
    r.state:SetPoint("TOPRIGHT", -10, -9)
    r.state:SetWidth(STATE_W)
    r.state:SetWordWrap(false)

    r.timer = T:Bar(r, 3)
    r.timer:SetPoint("BOTTOMLEFT", 1, 1)
    r.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    r.timer:SetBackdropBorderColor(0, 0, 0, 0)

    rows[i] = r
    return r
end

local function RollsText(it)
    local list = {}
    for _, x in pairs(it.rolls) do list[#list + 1] = x end
    table.sort(list, function(a, b)
        if a.valid ~= b.valid then return a.valid end
        if (a.os and 1 or 0) ~= (b.os and 1 or 0) then return not a.os end   -- Main Spec vor Off Spec
        return a.roll > b.roll
    end)
    local parts = {}
    for i = 1, math.min(8, #list) do
        local x = list[i]
        local col = (not x.valid) and H.muted or ((i == 1) and H.accentLt or "")
        local txt = col .. (x.name:match("^(%S+)") or x.name) .. " " .. x.roll .. (x.os and " OS" or "") .. ((col ~= "") and "|r" or "")
        if not x.valid then txt = txt .. H.muted .. "*|r" end
        parts[#parts + 1] = txt
    end
    return table.concat(parts, "  ·  ")
end

function LC:RefreshRaidFrame()
    if not frame or not frame:IsShown() then return end
    local R = self.raid
    local n = 0
    if R then
        for idx in pairs(R.items) do n = math.max(n, idx) end
    end
    local shown = 0
    for i = 1, math.max(n, #rows) do
        local it = R and R.items[i]
        local r = rows[i]
        if it then
            r = GetRow(i)
            shown = shown + 1
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -44 - (shown - 1) * ROW_H)
            r.idx, r.itemID, r.it = i, it.itemID, it
            r.icon.tex:SetTexture(self:ItemIcon(it.itemID))
            local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local _, _, quality = getInfo(it.itemID)
            local qc = T:QualityColor(quality)
            r.icon:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
            r.link:SetText(self:ItemLink(it.itemID) .. (it.council and ("  " .. H.accent .. L["Council|r"]) or ""))

            -- Wer hat reserviert?
            local who
            if it.reservers and #it.reservers > 0 then
                who = H.accentLt .. L["Reserviert:|r "] .. table.concat(it.reservers, ", ")
            else
                who = H.good .. L["Keine Reservierung – jeder darf würfeln|r"]
            end
            -- In meinem Gear-Set? Dann vorne anzeigen (★ = wichtig)
            local mineInfo = (self:IsInMySet(it.itemID) or self:IsUpgradeInMySet(it.itemID)) and self:GearSetRank(self:PlayerName(), it.itemID)
            if mineInfo and mineInfo.inSet then
                who = (mineInfo.important and (self.STAR .. " ") or (mineInfo.upgrade and self.UPGRADE) or "") .. H.good
                    .. (mineInfo.upgrade and L["Upgrade in deinem Set"] or L["In deinem Set"]) .. "|r   " .. who
            end
            r.who:SetText(who)

            -- Zustand
            local canRoll = self:RaidCanRoll(it)
            local free = self:RaidIsFree(it)
            r.btn:SetShown(canRoll)
            r.btnOS:SetShown(canRoll and free)
            r.rolls:SetWidth(W - 2 * PAD - ((canRoll and free) and 160 or 60))   -- nicht unter den Off-Spec-Knopf laufen
            r.btn.tooltipTitle = free and L["Main Spec"] or L["Würfeln"]
            r.btn.tooltip = free and L["Würfelt /roll 100 für deine Hauptspezialisierung. Main Spec geht vor Off Spec."] or nil
            r.state:SetShown(not canRoll)
            local st, sc = "", C.muted
            if it.state == "wait" then
                st = L["wartet"]
            elseif it.state == "council" then
                st, sc = L["Council entscheidet …"], C.accentLt
            elseif it.state == "prep" or it.state == "roll" then
                if it.myRoll then
                    st, sc = L["Dein Wurf: "] .. it.myRoll .. (it.myOS and " (OS)" or ""), C.accentLt
                elseif it.rollPending then
                    st = L["würfelt …"]
                elseif not self:RaidIsAllowed(it) then
                    st = L["nur Berechtigte"]
                end
            elseif it.state == "done" then
                -- Der Name steht unten bei "Gewinner: …" – hier nur der Zustand, damit nichts abgeschnitten wird
                if it.giveFailed and it.winner and self:IsMe(it.winner) then
                    st, sc = L["Taschen prüfen!"], C.bad
                elseif it.winner and self:IsMe(it.winner) then
                    st, sc = L["Gewonnen!"], C.good
                else
                    st, sc = L["entschieden"], C.text
                end
            elseif it.state == "awarded" then
                if it.winner and self:IsMe(it.winner) then
                    st, sc = L["Gehört dir!"], C.good
                else
                    st, sc = L["vergeben"], C.good
                end
            elseif it.state == "none" then
                st = L["niemand gewürfelt"]
            end
            r.state:SetText(st)
            r.state:SetTextColor(sc[1], sc[2], sc[3])

            if it.state == "roll" and it.endsAt then
                local left = math.max(0, it.endsAt - GetTime())
                r.timer.bar:SetMinMaxValues(0, it.seconds or 20)
                r.timer.bar:SetValue(left)
                r.timer:Show()
                if canRoll then r.btn:SetText(string.format(free and L["Main Spec  %d"] or L["Würfeln  %d"], math.ceil(left))) end
            else
                r.timer:Hide()
            end

            -- Würfe (für alle sichtbar)
            local rt = RollsText(it)
            if it.state == "done" or it.state == "awarded" then
                rt = H.good .. L["Gewinner: "] .. (it.winner or "?") .. (it.winRoll and (" (" .. it.winRoll .. (it.winOS and " OS" or "") .. ")") or "") .. "|r" .. ((rt ~= "") and ("   " .. rt) or "")
            elseif rt == "" then
                if it.state == "roll" then
                    if type(it.allowed) == "table" then
                        local l = {}
                        for _, nm in pairs(it.allowed) do l[#l + 1] = nm:match("^(%S+)") end
                        table.sort(l)
                        rt = H.muted .. L["Würfeln dürfen: "] .. table.concat(l, ", ") .. "|r"
                    else
                        rt = H.muted .. L["Alle dürfen würfeln · Main Spec vor Off Spec|r"]
                    end
                else
                    rt = ""
                end
            end
            r.rolls:SetText(rt)
            -- Hervorheben, wenn ich gerade würfeln darf
            if canRoll then T:SetBorder(r, C.accent) else T:SetBorder(r, C.border) end
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    frame.hint:SetText(shown == 0 and L["Noch kein Loot."] or (H.muted .. L["* = nicht berechtigt, Wurf zählt nicht.  Fenster: /lc loot|r"]))
    frame:SetHeight(44 + math.max(1, shown) * ROW_H + 28)
end

function LC:ShowRaidFrame()
    if not frame then CreateRaidFrame() end
    frame:Show()
    self:RefreshRaidFrame()
end

function LC:ToggleRaidFrame()
    if frame and frame:IsShown() then frame:Hide() else self:ShowRaidFrame() end
end

LC:On("GET_ITEM_INFO_RECEIVED", function(self)
    if frame and frame:IsShown() then self:RefreshRaidFrame() end
end)

------------------------------------------------------------------------
-- Hinweis bei Ausschluss (anonym)
------------------------------------------------------------------------
local KIND_TEXT = {
    SKIP = "Der Council hat entschieden, dass du bei diesem Item diese Woche aussetzt.",
    LIMIT = "Der Council hat die Würfelrunde für dieses Item auf andere Spieler eingegrenzt.",
    CD = "Du hast vor kurzem ein Council-Item gewonnen. Deshalb setzt du bei Council-Items gerade aus (Loot-Cooldown).",
    SIT = "Bei diesem Item setzt du diese Woche bereits aus – so wurde es zuvor vom Council entschieden.",
}

local function CreateNotice()
    notice = T:Window("LightCouncilNoticeFrame", 420, 240, L["Council-Entscheidung"], L["Persönlicher Hinweis – nur du siehst das"])
    notice:ClearAllPoints()
    notice:SetPoint("TOP", UIParent, "TOP", 0, -160)
    notice:SetFrameStrata("DIALOG")

    notice.icon = T:Icon(notice, 40)
    notice.icon:SetPoint("TOPLEFT", 16, -48)
    notice.item = T:Text(notice, 13, C.text)
    notice.item:SetPoint("TOPLEFT", notice.icon, "TOPRIGHT", 12, -2)
    notice.item:SetWidth(330)
    notice.item:SetWordWrap(false)
    notice.head = T:Text(notice, 12, C.warn)
    notice.head:SetPoint("TOPLEFT", notice.item, "BOTTOMLEFT", 0, -5)
    notice.head:SetText(L["Diesmal würfelst du nicht mit."])

    notice.body = T:Text(notice, 12, C.text)
    notice.body:SetPoint("TOPLEFT", 16, -100)
    notice.body:SetWidth(388)

    notice.reasonBox = CreateFrame("Frame", nil, notice, "BackdropTemplate")
    T:Skin(notice.reasonBox, C.bgDark)
    notice.reasonBox:SetPoint("LEFT", 16, 0)
    notice.reasonBox:SetPoint("RIGHT", -16, 0)
    local stripe = notice.reasonBox:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture(T.WHITE)
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    stripe:SetVertexColor(unpack(C.accent))
    notice.reasonLabel = T:Text(notice.reasonBox, 10, C.accentLt)
    notice.reasonLabel:SetPoint("TOPLEFT", 12, -8)
    notice.reasonLabel:SetText(L["BEGRÜNDUNG DES COUNCILS"])
    notice.reason = T:Text(notice.reasonBox, 12, C.text)
    notice.reason:SetPoint("TOPLEFT", notice.reasonLabel, "BOTTOMLEFT", 0, -4)
    notice.reason:SetWidth(360)

    notice.foot = T:Text(notice, 10, C.muted)
    notice.foot:SetWidth(388)
    notice.foot:SetText(L["Die Abstimmung ist anonym – du siehst nicht, wer wie gestimmt hat. Bei Fragen wende dich an die Raidleitung."])

    notice.ok = T:Button(notice, L["Verstanden"], 120, 26, "primary", function() notice:Hide() end)
end

function LC:ShowExcludedNotice(itemID, kind, reason)
    if not notice then CreateNotice() end
    notice.icon.tex:SetTexture(self:ItemIcon(itemID))
    notice.item:SetText(self:ItemLink(itemID))
    notice.body:SetText(KIND_TEXT[kind] and L[KIND_TEXT[kind]] or L["Du bist bei diesem Item nicht berechtigt zu würfeln."])

    local y = 100 + notice.body:GetStringHeight() + 12
    local hasReason = reason and reason ~= ""
    notice.reason:SetText(hasReason and ("„" .. reason .. "“") or (H.muted .. L["Der Council hat keine Begründung angegeben.|r"]))
    notice.reasonBox:ClearAllPoints()
    notice.reasonBox:SetPoint("TOPLEFT", 16, -y)
    notice.reasonBox:SetPoint("TOPRIGHT", -16, -y)
    local boxH = 30 + notice.reason:GetStringHeight()
    notice.reasonBox:SetHeight(boxH)
    y = y + boxH + 12
    notice.foot:ClearAllPoints()
    notice.foot:SetPoint("TOPLEFT", 16, -y)
    y = y + notice.foot:GetStringHeight() + 12
    notice.ok:ClearAllPoints()
    notice.ok:SetPoint("TOP", notice, "TOP", 0, -y)
    notice:SetHeight(y + 26 + 16)
    notice:Show()
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end
