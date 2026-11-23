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

function LC:Send(msg, channel, target)
    -- An sich selbst: direkt verarbeiten (Testmodus / Leitung ist selbst im Council)
    if channel == "WHISPER" and target and self:IsMe(target) then
        local me = self:PlayerName()
        C_Timer.After(0.05, function() LC:OnComm(msg, me, "WHISPER") end)
        return
    end
    if #msg > 250 then msg = msg:sub(1, 250) end
    table.insert(sendQueue, { msg = msg, channel = channel, target = target })
    Pump()
    if #sendQueue > 0 and not ticker then
        ticker = C_Timer.NewTicker(0.3, Pump)
    end
end

-- Nachrangig senden (große Datenmengen, z. B. Historie-Abgleich)
function LC:SendLow(msg, channel, target)
    if #msg > 250 then msg = msg:sub(1, 250) end
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

-- Parse/Engagement an andere Addon-Nutzer (Leitung + Council) verteilen
function LC:BroadcastData(kind, name, value)
    local channel
    if IsInRaid() then channel = "RAID"
    elseif IsInGroup() then channel = "PARTY"
    elseif IsInGuild() then channel = "GUILD" end
    if channel then
        self:Send(strjoin(SEP, "D", kind, name, tostring(value)), channel)
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
            for n in parts[4]:gmatch("[^,]+") do names[#names + 1] = n end
        end
        self:OnVote(sender, parts[2], parts[3], names, parts[5] or "")
    elseif cmd == "D" then
        if self:IsMe(sender) then return end
        if not self:IsCouncilMember(sender) then return end
        if parts[2] == "P" then self:SetParse(parts[3], parts[4], false)
        elseif parts[2] == "E" then self:SetEngagement(parts[3], parts[4], false) end
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
