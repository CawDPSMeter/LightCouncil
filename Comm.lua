-- Light Council – Kommunikation zwischen Raidleitung und Council (Addon-Nachrichten)
--
-- Nachrichten (Felder getrennt durch "~"):
--   S~sid~timeout~recused~link          Leitung -> Council (Whisper): neue Abstimmung
--   C~sid~name:score:att:parse:eng:flag;...   Leitung -> Council: Kandidaten (mehrere Nachrichten möglich)
--   G~sid                               Leitung -> Council: Popup anzeigen
--   V~sid~DECISION~name,name~reason     Council -> Leitung (Whisper): Stimme
--   E~sid~text                          Leitung -> Council: Abstimmung beendet
--   D~P|E~name~value                    Council/Leitung -> Raid/Gilde: Parse/Engagement-Sync
local _, LC = ...

local SEP = "~"
local sendQueue = {}
local lowQueue = {}   -- nachrangig (Historie-Abgleich): nur wenn sonst nichts ansteht
local tokens, maxTokens, lastRefill = 8, 8, 0
local ticker

local function RawSend(msg, channel, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(LC.prefix, msg, channel, target)
    else
        SendAddonMessage(LC.prefix, msg, channel, target)
    end
end

-- Einfache Drosselung, damit bei vielen Kandidaten keine Nachrichten verloren gehen
local function Pump()
    local now = GetTime()
    tokens = math.min(maxTokens, tokens + (now - lastRefill))
    lastRefill = now
    while #sendQueue > 0 and tokens >= 1 do
        local m = table.remove(sendQueue, 1)
        RawSend(m.msg, m.channel, m.target)
        tokens = tokens - 1
    end
    -- Nachrangiges nur senden, solange keine Abstimmung/Würfelrunde läuft und Reserve bleibt
    while #sendQueue == 0 and #lowQueue > 0 and tokens >= 4 and not LC.active and not LC.roll do
        local m = table.remove(lowQueue, 1)
        RawSend(m.msg, m.channel, m.target)
        tokens = tokens - 1
    end
    if #sendQueue == 0 and #lowQueue == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Nachrichten an sich selbst: in einer Warteschlange und in Sende-Reihenfolge zustellen.
-- (Ein eigener Timer pro Nachricht garantiert keine Reihenfolge – dann kam z. B. „Popup anzeigen“
-- vor der Spielerliste an und das Abstimmungsfenster blieb leer.)
local localQueue = {}
local function FlushLocal()
    local q = localQueue
    localQueue = {}
    local me = LC:PlayerName()
    for _, msg in ipairs(q) do
        local ok, err = pcall(LC.OnComm, LC, msg, me, "WHISPER")
        if not ok then geterrorhandler()(err) end
    end
end

function LC:Send(msg, channel, target)
    -- An sich selbst: direkt verarbeiten (Testmodus / Leitung ist selbst im Council)
    if channel == "WHISPER" and target and self:IsMe(target) then
        if #localQueue == 0 then C_Timer.After(0.05, FlushLocal) end
        localQueue[#localQueue + 1] = msg
        return
    end
    if #msg > 250 then msg = self:Utf8Cut(msg, 250) end
    table.insert(sendQueue, { msg = msg, channel = channel, target = target })
    Pump()
    if #sendQueue > 0 and not ticker then
        ticker = C_Timer.NewTicker(0.3, Pump)
    end
end

-- Nachrangig senden (große Datenmengen, z. B. Historie-Abgleich)
function LC:SendLow(msg, channel, target)
    if #msg > 250 then msg = self:Utf8Cut(msg, 250) end
    table.insert(lowQueue, { msg = msg, channel = channel, target = target })
    Pump()
    if (#sendQueue > 0 or #lowQueue > 0) and not ticker then
        ticker = C_Timer.NewTicker(0.3, Pump)
    end
end

-- Wie viele Nachrichten noch auf das Senden warten (ca. 1 pro Sekunde)
function LC:SendBacklog()
    return #sendQueue
end

function LC:SendTo(target, ...)
    self:Send(strjoin(SEP, ...), "WHISPER", target)
end

-- Online-Empfänger für vertrauliche Daten: Council-Mitglieder und Raidleiter.
-- Liefert die Namen so, wie der Server sie zum Flüstern braucht (aus Raid- bzw. Gildenliste).
function LC:GetPrivateTargets()
    local targets, seen = {}, {}
    local council = self:GetCouncilList()
    local function Wanted(...)
        for i = 1, select("#", ...) do
            local n = select(i, ...)
            if n then
                for _, c in ipairs(council) do
                    if self:SameName(c, n) then return true end
                end
            end
        end
        return false
    end
    local function Add(target)
        local key = self:NameKey(target)
        if key and not seen[key] and not self:IsMe(target) then
            seen[key] = true
            targets[#targets + 1] = target
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local rosterName, rank, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if rosterName and online then
                local full = self.isForever and self:UnitFullName("raid" .. i) or nil
                if rank == 2 or Wanted(rosterName, full) then
                    Add(rosterName)
                    if full then seen[self:NameKey(full)] = true end
                end
            end
        end
    end
    if IsInGuild() and GetGuildRosterInfo and GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            local gName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if gName and online and not seen[self:NameKey(gName)] and Wanted(gName) then Add(gName) end
        end
    end
    return targets
end

-- Parse/Engagement nur per Flüstern an Council und Raidleiter (nicht mehr an Raid oder Gilde,
-- sonst könnte jeder mit einem kleinen Skript die Bewertungen mitlesen)
function LC:BroadcastData(kind, name, value)
    local msg = strjoin(SEP, "D", kind, name, tostring(value))
    for _, target in ipairs(self:GetPrivateTargets()) do
        self:Send(msg, "WHISPER", target)
    end
end

------------------------------------------------------------------------
-- Empfang
------------------------------------------------------------------------
function LC:OnComm(msg, sender, channel)
    local parts = { strsplit(SEP, msg) }
    local cmd = parts[1]

    -- Raider-Ansicht (Lootliste, Würfelrunden, Hinweise) – siehe Raider.lua
    if self.OnRaidComm and self:OnRaidComm(cmd, parts, sender) then return end

    if cmd == "S" then
        if not self:IsTrustedLeader(sender) then return end
        self:VoteSessionBegin(sender, parts[2], tonumber(parts[3]) or 30, parts[4] == "1", parts[5],
            tonumber(parts[6]) or 2, tonumber(parts[7]) or 3)
    elseif cmd == "C" then
        self:VoteSessionCandidates(sender, parts[2], parts[3])
    elseif cmd == "G" then
        self:VoteSessionShow(sender, parts[2])
    elseif cmd == "E" then
        self:VoteSessionEnd(sender, parts[2], parts[3])
    elseif cmd == "V" then
        local names = {}
        if parts[4] and parts[4] ~= "" then
            for n in parts[4]:gmatch("[^,]+") do
                n = self:CleanText(n, 40)
                if n ~= "" then names[#names + 1] = n end
            end
        end
        self:OnVote(sender, parts[2], parts[3], names, parts[5] or "")
    elseif cmd == "D" then
        if self:IsMe(sender) then return end
        -- Vom Council oder von der eigenen Raidleitung (die ohne Council-Sitz auch Werte einträgt) –
        -- nur aus der eigenen Gilde, sonst könnte der Leiter eines fremden Raids die Bewertungen ändern
        if not (self:IsCouncilMember(sender) or (self:IsTrustedLeader(sender) and self:IsGuildMember(sender))) then return end
        local who = self:CleanText(parts[3] or "", 40)
        if who == "" then return end
        if parts[2] == "P" then self:SetParse(who, parts[4], false)
        elseif parts[2] == "E" then self:SetEngagement(who, parts[4], false) end
        self:RefreshUI()
    end
end

LC:On("CHAT_MSG_ADDON", function(self, prefix, msg, channel, sender)
    if prefix ~= self.prefix then return end
    -- Eigene Whisper werden lokal verarbeitet; eigene Raid-Nachrichten ignorieren
    if self:IsMe(sender) then return end
    self:OnComm(msg, sender, channel)
end)

LC:On("PLAYER_LOGIN", function(self)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.prefix)
    end
end)
