-- Light Council – Hauptfenster, Seite: Spieler
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
-- Seite: Spieler
------------------------------------------------------------------------
local playerRows = {}
local P_ROW = 26
local COLS = { 0, 200, 300, 370, 470, 560, 650 }   -- Name, Anw., Parse, Eng., Score, Items, Status

local function CreatePlayersPage(p)
    local y = PageHeader(p, L["Spieler"], L["Score 0–100 aus Anwesenheit, Parse und Engagement. Nur Leitung und Council sehen ihn. Zeile anklicken zum Bearbeiten, Maus drüber zeigt die letzten Items."])

    local head = CreateFrame("Frame", nil, p)
    head:SetPoint("TOPLEFT", 0, -y)
    head:SetSize(CW, 18)
    for i, label in ipairs({ L["NAME"], L["ANWESENHEIT"], L["PARSE"], L["ENGAGEMENT"], L["SCORE"], L["ITEMS"], L["STATUS"] }) do
        local t = T:Text(head, 10, C.muted)
        t:SetPoint("LEFT", COLS[i] + 10, 0)
        t:SetText(label)
    end
    local line = T:Line(p, C.line)
    line:SetPoint("TOPLEFT", 0, -y - 20)
    line:SetWidth(CW)
    y = y + 24

    local sf, content = T:Scroll(p)
    sf:SetPoint("TOPLEFT", 0, -y)
    sf:SetPoint("BOTTOMRIGHT", -10, 74)
    p.list = content
    p.empty = T:Text(p, 11, C.muted, "CENTER")
    p.empty:SetPoint("TOP", sf, "TOP", 0, -30)
    p.empty:SetWidth(CW - 60)
    p.empty:SetText(L["Noch keine Spieler. Sie erscheinen, sobald sie reservieren oder nach dem ersten Boss-Kill."])

    local edit = Card(p, 62)
    edit:SetPoint("BOTTOMLEFT", 0, 0)
    edit:SetWidth(CW)
    local function Field(label, width, anchor)
        local l = T:Text(edit, 10, C.muted)
        l:SetText(label)
        local e = T:Input(edit, width, 24)
        if anchor then e:SetPoint("LEFT", anchor, "RIGHT", 10, 0) else e:SetPoint("BOTTOMLEFT", 10, 10) end
        l:SetPoint("BOTTOMLEFT", e, "TOPLEFT", 0, 4)
        return e
    end
    p.name = Field(L["NAME"], 230)
    p.name:SetPlaceholder(L["Vor- und Nachname"])
    p.parse = Field(L["Ø PARSE (0–100)"], 90, p.name)
    p.parse:SetPlaceholder("z. B. 85")
    p.eng = Field(L["ENGAGEMENT (1–5)"], 100, p.parse)
    p.eng:SetPlaceholder(L["1 bis 5"])
    Tip(p.eng, L["Engagement"], L["Gildenaktivität, Hilfsbereitschaft, Vorbereitung (Consumables) und Pünktlichkeit."])
    local save = T:Button(edit, L["Speichern"], 90, 24, "primary", function()
        local name = strtrim(p.name:GetText() or "")
        if name == "" then p.msg:SetText(H.bad .. L["Bitte einen Namen eingeben.|r"]) return end
        local msgs = {}
        local pv, ev = strtrim(p.parse:GetText() or ""), strtrim(p.eng:GetText() or "")
        if pv ~= "" then
            local ok, err = LC:SetParse(name, pv, true)
            msgs[#msgs + 1] = ok and (H.good .. L["Parse gespeichert|r"]) or (H.bad .. err .. "|r")
        end
        if ev ~= "" then
            local ok, err = LC:SetEngagement(name, ev, true)
            msgs[#msgs + 1] = ok and (H.good .. L["Engagement gespeichert|r"]) or (H.bad .. err .. "|r")
        end
        if #msgs == 0 then msgs[1] = H.warn .. L["Parse oder Engagement eintragen.|r"] end
        p.msg:SetText(table.concat(msgs, "  ·  "))
        LC:RefreshUI()
    end)
    save:SetPoint("LEFT", p.eng, "RIGHT", 10, 0)
    -- Anwesenheit erfassen: oben rechts neben der Überschrift, damit nichts überlappt
    local att = T:Button(p, L["Anwesenheit erfassen"], 170, 26, "default", function()
        local n = LC:RecordAttendance(true)
        local synced = LC:RequestAttendanceSync(false)
        p.msg:SetText(n .. L[" Spieler für diese Woche erfasst."] .. (synced and L[" Abgleich mit dem Council läuft."] or ""))
        LC:RefreshUI()
    end)
    att:SetPoint("TOPRIGHT", 0, 0)
    Tip(att, L["Anwesenheit erfassen"], L["Markiert alle Online-Raidmitglieder für diese Woche als anwesend. Passiert bei jedem Boss-Kill automatisch.\n\nDie Anwesenheit wird mit allen Council-Mitgliedern abgeglichen (beim Einloggen und bei jeder Erfassung). Wochen, in denen du selbst nicht dabei warst, kommen so trotzdem an."])
    p.msg = T:Text(edit, 11, C.muted, "LEFT")
    p.msg:SetPoint("LEFT", save, "RIGHT", 14, 0)
    p.msg:SetPoint("RIGHT", edit, "RIGHT", -10, 0)
    p.msg:SetWordWrap(false)
end

local function RefreshPlayers()
    local p = pages.players
    local names = LC:GetKnownPlayers()
    p.empty:SetShown(#names == 0)
    for i = 1, math.max(#names, #playerRows) do
        local name = names[i]
        local r = playerRows[i]
        if name then
            if not r then
                r = CreateFrame("Button", nil, p.list, "BackdropTemplate")
                r:SetSize(CW - 10, P_ROW)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * P_ROW)
                T:Skin(r, (i % 2 == 0) and C.panel or C.bg, { 0, 0, 0, 0 })
                r.cols = {}
                for c = 1, 7 do
                    local fs = T:Text(r, 11, C.text)
                    fs:SetPoint("LEFT", COLS[c] + 10, 0)
                    fs:SetWordWrap(false)
                    fs:SetWidth(((COLS[c + 1] or (CW - 10)) - COLS[c]) - 14)
                    r.cols[c] = fs
                end
                r.scoreBar = T:Bar(r, 4)
                r.scoreBar:SetPoint("LEFT", COLS[5] + 40, 0)
                r.scoreBar:SetWidth(40)
                r.scoreBar.bar:SetMinMaxValues(0, 100)
                r:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.playerName, 1, 1, 1)
                    LC:AddLootTooltip(GameTooltip, self.playerName, 8)
                    GameTooltip:Show()
                end)
                r:SetScript("OnLeave", function(self)
                    local c = (self.index % 2 == 0) and C.panel or C.bg
                    self:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
                    GameTooltip_Hide()
                end)
                r:SetScript("OnClick", function(self)
                    local pl = LC:GetPlayer(self.playerName)
                    p.name:SetText(self.playerName)
                    p.parse:SetText(pl and pl.parse and tostring(pl.parse) or "")
                    p.eng:SetText(pl and pl.engagement and tostring(pl.engagement) or "")
                    p.parse:SetFocus()
                end)
                playerRows[i] = r
            end
            r.index = i
            r.playerName = name
            local score, att, parse, eng = LC:GetScore(name)
            local cd, untilWeek = LC:IsOnCooldown(name)
            local dash = H.muted .. L["–|r"]
            r.cols[1]:SetText(name)
            r.cols[2]:SetText(att and (att .. " %") or dash)
            r.cols[3]:SetText(parse and tostring(parse) or dash)
            r.cols[4]:SetText(eng and (eng .. " / 5") or dash)
            local sc = T:ScoreColor(score)
            r.cols[5]:SetText(score and tostring(score) or dash)
            r.cols[5]:SetTextColor(sc[1], sc[2], sc[3])
            r.scoreBar:SetShown(score ~= nil)
            r.scoreBar.bar:SetValue(score or 0)
            r.scoreBar.bar:SetStatusBarColor(sc[1], sc[2], sc[3])
            -- Items der letzten Wochen (gleicher Zeitraum wie die Anwesenheit)
            local loot, councilN = LC:GetPlayerLoot(name, LC.db.config.attendanceWeeks or 8)
            if #loot == 0 then
                r.cols[6]:SetText(dash)
            else
                r.cols[6]:SetText(#loot .. ((councilN > 0) and (H.accentLt .. "  (" .. councilN .. " C)|r") or ""))
            end
            if cd then
                local weeksLeft = untilWeek - LC:CurrentWeek()
                r.cols[7]:SetText(H.warn .. L["Loot-CD|r "] .. H.muted .. (weeksLeft == 0 and L["diese Wo."] or (L["noch "] .. weeksLeft .. L[" Wo."])) .. "|r")
            else
                r.cols[7]:SetText("")
            end
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    p.list:SetHeight(math.max(1, #names * P_ROW))
end


U.CreatePlayersPage, U.RefreshPlayers = CreatePlayersPage, RefreshPlayers
