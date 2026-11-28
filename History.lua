-- Light Council – Loot-Historie: Abgleich zwischen allen Addon-Nutzern und Export
--
-- Nachrichten:
--   HQ~seit                 alle -> Gilde/Raid: bitte Einträge ab Zeitpunkt "seit" schicken
--   HE~eintrag;eintrag;…    Council -> Anfragender (Whisper) bzw. Gilde (neu vergebenes Item)
--     eintrag = id^itemID^gewinner^zeit^raid^wurf^flags^instanzID   (flags: c = Council-Item, r = reserviert, o = Off Spec)
--   HD~id;id;…              Council -> Gilde/Anfragender: diese Einträge wurden gelöscht
--   HN~zeit                 Council -> Anfragender: es gibt noch mehr Einträge ab „zeit“ (nächste Seite)
--   HQ~seit~p               Anfragender -> Council (Whisper): nächste Seite abholen
--
-- Nur Einträge von Council-Mitgliedern werden übernommen, damit niemand die Historie fälschen kann.
-- Der Abgleich läuft nachrangig: während Abstimmungen und Würfelrunden wird nichts davon gesendet.
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { HQ = true, HE = true, HD = true, HN = true }
local DELETED_KEEP = 180 * 86400  -- gelöschte Kennungen so lange merken

-- Kennungen in Nachrichten unter 240 Zeichen packen
local function PackIds(ids)
    local msgs, cur = {}, ""
    for _, id in ipairs(ids) do
        id = LC:CleanText(id, 80)
        if id ~= "" then
            if cur ~= "" and #cur + #id + 1 > 236 then
                msgs[#msgs + 1] = cur
                cur = id
            else
                cur = (cur == "") and id or (cur .. ";" .. id)
            end
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = cur end
    return msgs
end
local LOOKBACK = 21 * 86400   -- verpasste Raids der letzten 3 Wochen vor dem neuesten eigenen Eintrag
local MAX_SEND = 90           -- höchstens so viele Einträge pro Anfrage

local function Field(s)
    return (LC:CleanText(s or "", 40):gsub("%^", ""))
end

local function Encode(e)
    local flags = (e.council and "c" or "") .. (e.reserved and "r" or "") .. (e.offspec and "o" or "")
    return table.concat({ Field(e.id), tostring(e.itemID), Field(e.winner), tostring(e.time or 0),
        Field(e.raid), e.roll and tostring(e.roll) or "", flags, e.instID and tostring(e.instID) or "" }, "^")
end

local function Decode(s)
    local id, itemID, winner, t, raid, roll, flags, instID = strsplit("^", s)
    itemID, t = tonumber(itemID), tonumber(t)
    if not id or id == "" or not itemID or not winner or winner == "" or not t then return nil end
    flags = flags or ""
    winner, raid = LC:SafeText(winner, 60), LC:SafeText(raid, 60)
    return {
        id = LC:SafeText(id, 80), itemID = itemID, winner = winner, time = t, raid = (raid ~= "") and raid or nil,
        roll = tonumber(roll), council = flags:find("c") and true or nil, reserved = flags:find("r") and true or nil,
        offspec = flags:find("o") and true or nil, instID = tonumber(instID),
    }
end

-- Einträge in möglichst wenige Nachrichten packen
local function Pack(entries)
    local msgs, cur = {}, ""
    for _, e in ipairs(entries) do
        local s = Encode(e)
        if cur ~= "" and #cur + #s + 1 > 240 then
            msgs[#msgs + 1] = cur
            cur = s
        else
            cur = (cur == "") and s or (cur .. ";" .. s)
        end
    end
    if cur ~= "" then msgs[#msgs + 1] = cur end
    return msgs
end

------------------------------------------------------------------------
-- Anfragen und Antworten
------------------------------------------------------------------------
function LC:RequestHistorySync(manual)
    local h = self.db.history
    local since = 0
    if #h > 0 then since = math.max(0, (h[#h].time or 0) - LOOKBACK) end
    local msg = strjoin(SEP, "HQ", tostring(since))
    local sent = false
    if IsInGuild() then self:SendLow(msg, "GUILD") sent = true end
    if IsInRaid() then self:SendLow(msg, "RAID") sent = true
    elseif IsInGroup() then self:SendLow(msg, "PARTY") sent = true end
    self.historySyncAt = time()
    if manual then
        if sent then
            self:Print(L["Loot-Historie: Abgleich angefragt – fehlende Einträge kommen vom Council, sobald jemand online ist."])
        else
            self:Print(L["Loot-Historie: Kein Abgleich möglich – du bist in keiner Gilde oder Gruppe."])
        end
    end
    return sent
end

local answered, answeredPage = {}, {}   -- [Anfragender] = Zeit, damit Mehrfach-Anfragen nicht mehrfach beantwortet werden

-- Schickt ab „since“ die ÄLTESTEN Einträge (höchstens MAX_SEND). Gibt es mehr, folgt „HN“ mit dem Zeitpunkt
-- für die nächste Seite – so kommen auch große Lücken nach und nach an.
local function Answer(requester, since, paged)
    if not LC:AmICouncil() then return end
    local key = LC:NameKey(requester)
    local seen = paged and answeredPage or answered
    if seen[key] and time() - seen[key] < (paged and 5 or 60) then return end
    seen[key] = time()
    local list, more = {}, false
    local h = LC.db.history   -- nach Zeit aufsteigend sortiert
    for i = 1, #h do
        local e = h[i]
        if (e.time or 0) >= since and e.id then
            if #list >= MAX_SEND then more = true break end
            list[#list + 1] = e
        end
    end
    -- Gelöschte Einträge im selben Zeitraum mitschicken (zuerst, damit sie nicht neu angelegt werden)
    local ids = {}
    for id, t in pairs(LC.db.historyDeleted or {}) do
        if t >= since then ids[#ids + 1] = id end
        if #ids >= MAX_SEND then break end
    end
    for _, m in ipairs(PackIds(ids)) do
        LC:SendLow(strjoin(SEP, "HD", m), "WHISPER", requester)
    end
    if #list == 0 then return end
    for _, m in ipairs(Pack(list)) do
        LC:SendLow(strjoin(SEP, "HE", m), "WHISPER", requester)
    end
    if more then
        LC:SendLow(strjoin(SEP, "HN", tostring(list[#list].time or since)), "WHISPER", requester)
    end
end

-- Gelöschte Einträge an alle weitergeben (nur Council – nur dessen Löschungen werden übernommen)
function LC:ShareHistoryDelete(ids)
    if not ids or #ids == 0 or not self:AmICouncil() then return end
    local channel = IsInGuild() and "GUILD" or (IsInRaid() and "RAID") or nil
    if not channel then return end
    for _, m in ipairs(PackIds(ids)) do
        self:SendLow(strjoin(SEP, "HD", m), channel)
    end
end

local function ReceiveDelete(sender, payload)
    if not LC:IsTrustedCouncil(sender) then return end
    local changed = false
    for id in (payload or ""):gmatch("[^;]+") do
        if LC:DeleteHistoryById(LC:SafeText(id, 80)) then changed = true end
    end
    if changed then LC:RefreshUI() end
end

-- Neu vergebenes Item an die Gilde (für Council-Mitglieder und Raider, die gerade nicht im Raid sind)
function LC:ShareHistoryEntry(e)
    if not e or not self:AmICouncil() or not IsInGuild() then return end
    self:SendLow(strjoin(SEP, "HE", Encode(e)), "GUILD")
end

local function Receive(sender, payload)
    if not LC:IsTrustedCouncil(sender) then return end
    local added = 0
    for s in (payload or ""):gmatch("[^;]+") do
        local e = Decode(s)
        if e and LC:AddHistory(e, true) then added = added + 1 end
    end
    if added > 0 then LC:RefreshUI() end
end

------------------------------------------------------------------------
-- Export (Tabelle oder Discord)
------------------------------------------------------------------------
local function HowText(e)
    if e.council then return L["Council"] end
    if e.reserved then return L["Reserviert"] end
    return e.offspec and L["Frei gewürfelt (Off Spec)"] or L["Frei gewürfelt (Main Spec)"]
end

-- list = Einträge (neueste zuerst), format = "csv" oder "discord"
function LC:HistoryExportText(list, format)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local lines = {}
    if format == "csv" then
        lines[1] = L["Datum;Raid;Item;Item-ID;Spieler;Vergabe;Wurf"]
    end
    for _, e in ipairs(list) do
        local itemName = getInfo(e.itemID) or (L["Item "] .. e.itemID)
        if format == "csv" then
            lines[#lines + 1] = table.concat({ date("%d.%m.%Y", e.time), e.raid or "", itemName, tostring(e.itemID),
                e.winner or "", HowText(e), e.roll and tostring(e.roll) or "" }, ";")
        else
            lines[#lines + 1] = string.format("%s · %s · **%s** → %s (%s%s)", date("%d.%m.", e.time), e.raid or "?",
                itemName, e.winner or "?", HowText(e), e.roll and (L[", Wurf "] .. e.roll) or "")
        end
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Einklinken
------------------------------------------------------------------------
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~(.*)$")
    if cmd and CMDS[cmd] then
        if self:IsMe(sender) then return end
        if cmd == "HQ" then
            local sinceText, flag = strsplit(SEP, rest)
            local since = tonumber(sinceText) or 0
            if flag == "p" then
                Answer(sender, since, true)   -- nächste Seite: sofort, nur an den, der gefragt hat
            else
                C_Timer.After(2 + math.random() * 6, function() Answer(sender, since) end)
            end
        elseif cmd == "HN" then
            -- Der Council hat noch mehr: nächste Seite bei genau diesem Council-Mitglied abholen
            local t = tonumber(rest)
            if t and LC:IsTrustedCouncil(sender) then
                LC:SendLow(strjoin(SEP, "HQ", tostring(t), "p"), "WHISPER", sender)
            end
        elseif cmd == "HD" then
            ReceiveDelete(sender, rest)
        else
            Receive(sender, rest)
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

LC:On("PLAYER_LOGIN", function(self)
    -- Alte Lösch-Kennungen aufräumen
    local now = time()
    for id, t in pairs(self.db.historyDeleted or {}) do
        if now - (t or 0) > DELETED_KEEP then self.db.historyDeleted[id] = nil end
    end
    C_Timer.After(20, function() LC:RequestHistorySync(false) end)
end)
