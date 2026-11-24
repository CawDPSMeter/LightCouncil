-- Light Council – Raider-Ansicht: Loot-Fenster für alle Addon-Nutzer, Würfeln per Knopf,
-- anonymer Hinweis an ausgeschlossene Spieler.
--
-- Nachrichten der Leitung an den Raid (Felder getrennt durch "~"):
--   LS~lid~anzahl                         neue Lootliste
--   LI~lid~idx~itemID~council~namen       Item mit Reservierern (Namen mit Komma)
--   LR~lid~idx~namen                      weitere Reservierer
--   LE~lid                                Liste vollständig -> Fenster öffnen
--   CS~lid~idx                            Council entscheidet
--   RS~lid~idx~sek~namen|*                Würfelrunde: berechtigte Spieler (* = alle)
--   RL~lid~idx~namen                      weitere Berechtigte
--   RG~lid~idx                            Würfeln freigegeben
--   RW~lid~idx~gewinner~wurf              Gewinner
--   RN~lid~idx                            niemand hat gewürfelt
--   RC~lid~idx                            abgebrochen
--   RA~lid~idx~gewinner                   vergeben
-- Whisper der Leitung an einen ausgeschlossenen Spieler:
--   X~itemID~art~begründung               art: SKIP, LIMIT, CD, SIT
local _, LC = ...

local SEP = "~"
local RAID_CMDS = {
    LS = true, LI = true, LR = true, LP = true, LE = true, CS = true, RS = true, RL = true,
    RG = true, RW = true, RN = true, RC = true, RA = true, X = true,
}

------------------------------------------------------------------------
-- Senden (Leitung)
------------------------------------------------------------------------
-- An den Raid senden und gleichzeitig selbst verarbeiten (die Leitung sieht die Raider-Ansicht auch)
function LC:Broadcast(test, ...)
    local msg = strjoin(SEP, ...)
    self:OnComm(msg, self:PlayerName(), "RAID")
    if not test and IsInGroup() then
        self:Send(msg, IsInRaid() and "RAID" or "PARTY")
    end
end

local function Chunks(names, maxLen)
    local chunks, cur = {}, ""
    for _, n in ipairs(names) do
        if cur ~= "" and #cur + #n + 1 > maxLen then
            chunks[#chunks + 1] = cur
            cur = n
        else
            cur = (cur == "") and n or (cur .. "," .. n)
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    return chunks
end

local lootIds, lootNext, lootCounter = {}, {}, 0

-- Kurze Prüfsumme des eigenen Namens (macht die Loot-ID zwischen Plündermeistern eindeutig)
local function NameHash(name)
    local h = 0
    for i = 1, #(name or "") do h = (h * 31 + name:byte(i)) % 4096 end
    return h
end

function LC:NetLoot(entries, test)
    if #entries == 0 then return end
    -- gleiche Leiche = gleiche Liste (Status bleibt beim erneuten Öffnen erhalten); Tests immer neu
    local key = entries[1].key or "?"
    local src = entries[1].test and key or (key:match("^(.-):") or key)
    local lid = lootIds[src]
    if not lid then
        -- eindeutig: volle Serverzeit, Zähler dieser Sitzung und Plündermeister
        lootCounter = lootCounter + 1
        lid = string.format("%d-%d-%03x", time(), lootCounter, NameHash(self:NameKey(self:PlayerName()) or ""))
        lootIds[src] = lid
        lootNext[lid] = 0
    end
    -- Jedes Item behält seine Nummer, auch wenn die Leiche erneut geöffnet wird und Slots aufrücken
    for _, e in ipairs(entries) do
        if e.lid ~= lid or not e.idx then
            lootNext[lid] = lootNext[lid] + 1
            e.lid, e.idx = lid, lootNext[lid]
        end
    end
    self:Broadcast(test, "LS", lid, tostring(lootNext[lid]))
    for _, e in ipairs(entries) do
        local i = e.idx
        local res = e.test and e.testReservers or self:GetReservers(e.itemID)
        local names = {}
        for _, r in ipairs(res) do names[#names + 1] = self:CleanText(r.name, 40) end
        local chunks = Chunks(names, 180)
        self:Broadcast(test, "LI", lid, tostring(i), tostring(e.itemID), e.isCouncil and "1" or "0", chunks[1] or "")
        for c = 2, #chunks do self:Broadcast(test, "LR", lid, tostring(i), chunks[c]) end
    end
    self:Broadcast(test, "LE", lid)
end

function LC:NetItem(entry, cmd, ...)
    if not entry or not entry.lid then return end
    self:Broadcast(entry.test, cmd, entry.lid, tostring(entry.idx), ...)
end

function LC:NetRollStart(entry, rollers, seconds)
    if not entry or not entry.lid then return end
    if not rollers then
        self:NetItem(entry, "RS", tostring(seconds), "*")
    else
        local names = {}
        for _, n in ipairs(rollers) do names[#names + 1] = self:CleanText(n, 40) end
        local chunks = Chunks(names, 180)
        self:NetItem(entry, "RS", tostring(seconds), chunks[1] or "")
        for c = 2, #chunks do self:NetItem(entry, "RL", chunks[c]) end
    end
    self:NetItem(entry, "RG")
end

-- Ausgeschlossene Spieler persönlich und anonym informieren
-- notices: { { name = "...", kind = "SKIP"|"LIMIT"|"CD"|"SIT", reason = "..." } }
function LC:NotifyExcluded(entry, notices)
    if not notices or #notices == 0 then return end
    local members = self:GetGroupMembers()
    for _, n in ipairs(notices) do
        local reason = self:CleanText(n.reason or "", 150)
        if entry.test then
            if self:IsMe(n.name) then
                self:OnComm(strjoin(SEP, "X", tostring(entry.itemID), n.kind, reason), self:PlayerName(), "WHISPER")
            end
        else
            local m = self:FindByName(members, n.name)
            if m and m.online then
                self:SendTo(m.fullName, "X", tostring(entry.itemID), n.kind, reason)
            end
        end
    end
end

------------------------------------------------------------------------
-- Empfangen (alle)
------------------------------------------------------------------------
local function SplitNames(s, into)
    into = into or {}
    for n in (s or ""):gmatch("[^,]+") do
        n = strtrim(n)
        if n ~= "" then into[#into + 1] = n end
    end
    return into
end

function LC:OnRaidComm(cmd, p, sender)
    if not RAID_CMDS[cmd] then return false end
    if not self:IsTrustedLeader(sender) then return true end

    if cmd == "X" then
        self:ShowExcludedNotice(tonumber(p[2]), p[3], self:SafeText(p[4], 150))
        return true
    end

    local lid, idx = p[2], tonumber(p[3])
    local R = self.raid

    if cmd == "LS" then
        if not R or R.lid ~= lid then
            self.raid = { lid = lid, owner = sender, items = {}, count = tonumber(p[3]) or 0 }
        end
        return true
    end
    if not R or R.lid ~= lid then return true end
    -- Änderungen an einer Lootliste nur von dem, der sie angelegt hat
    if R.owner and not self:SameName(R.owner, sender) then return true end

    if cmd == "LE" then
        if self.db.config.raiderWindow then self:ShowRaidFrame() end
        self:RefreshRaidFrame()
        return true
    end

    local it = idx and R.items[idx]
    if cmd == "LI" then
        -- Neues Item (oder unter dieser Nummer liegt jetzt ein anderes): frisch anlegen
        local newID = tonumber(p[4])
        if not it or it.itemID ~= newID then
            it = { itemID = newID, state = "wait", rolls = {} }
            R.items[idx] = it
        end
        it.council = (p[5] == "1")
        it.reservers = SplitNames(p[6])
        self:ItemLink(it.itemID)
    elseif not it then
        return true
    elseif cmd == "LR" then
        SplitNames(p[4], it.reservers)
    elseif cmd == "CS" then
        it.state = "council"
    elseif cmd == "RS" then
        it.state = "prep"
        it.rolls, it.myRoll, it.winner, it.winRoll = {}, nil, nil, nil
        it.myOS, it.winOS = nil, nil
        it.seconds = tonumber(p[4]) or 20
        if p[5] == "*" then
            it.allowed = "*"
        else
            it.allowed = {}
            for _, n in ipairs(SplitNames(p[5])) do it.allowed[self:NameKey(n)] = n end
        end
    elseif cmd == "RL" then
        if type(it.allowed) == "table" then
            for _, n in ipairs(SplitNames(p[4])) do it.allowed[self:NameKey(n)] = n end
        end
    elseif cmd == "RG" then
        it.state = "roll"
        it.endsAt = GetTime() + (it.seconds or 20)
        R.activeIdx = idx
        if self.db.config.raiderWindow then self:ShowRaidFrame() end
        if self:RaidCanRoll(it) and SOUNDKIT and SOUNDKIT.READY_CHECK then
            pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
        end
    elseif cmd == "RW" then
        it.state = "done"
        it.winner, it.winRoll = p[4], tonumber(p[5])
        it.winOS = (p[6] == "1") or nil
        if R.activeIdx == idx then R.activeIdx = nil end
    elseif cmd == "RN" then
        it.state = "none"
        if R.activeIdx == idx then R.activeIdx = nil end
    elseif cmd == "RC" then
        it.state = "wait"
        if R.activeIdx == idx then R.activeIdx = nil end
    elseif cmd == "RA" then
        -- Wurf/Off Spec nur übernehmen, wenn der Würfelgewinner das Item auch bekommen hat
        local sameWinner = it.winner and self:NamesMatch(it.winner, p[4] or "")
        it.state = "awarded"
        it.winner = p[4]
        if not sameWinner then it.winRoll, it.winOS = nil, nil end
        if p[5] == "1" then it.winOS = true end
        if R.activeIdx == idx then R.activeIdx = nil end
        -- Historie: die Leitung trägt selbst ein (auch Tests kommen nur lokal an und werden so übersprungen).
        -- Nur vom Council oder vom Plündermeister übernehmen, nicht von jedem Raid-Assistenten.
        local sm = self:FindExact(self:GetGroupMembers(), sender)
        if not self:IsMe(sender) and (self:IsTrustedCouncil(sender) or (sm and sm.isML)) then
            self:AddHistory({
                id = lid .. "#" .. idx, itemID = it.itemID, winner = it.winner, roll = it.winRoll,
                council = it.council or nil, offspec = it.winOS,
                reserved = self:WasReserved(it.itemID, it.winner, it.reservers) or nil,
            })
        end
    end
    self:RefreshRaidFrame()
    return true
end

-- Darf ich bei diesem Item würfeln?
function LC:RaidIsAllowed(it, name)
    if not it.allowed then return false end
    if it.allowed == "*" then return true end
    return self:FindByName(it.allowed, name or self:PlayerName()) ~= nil
end

function LC:RaidCanRoll(it)
    return it.state == "roll" and not it.myRoll and self:RaidIsAllowed(it)
end

-- Freies Würfeln (jeder darf): Main Spec und Off Spec möglich
function LC:RaidIsFree(it)
    return it.allowed == "*"
end

-- offspec = true: /roll 99 (Off Spec), nur beim freien Würfeln
function LC:RaidRoll(idx, offspec)
    local R = self.raid
    local it = R and R.items[idx]
    if not it or not self:RaidCanRoll(it) then return end
    local max = (offspec and self:RaidIsFree(it)) and 99 or 100
    it.rollPending = true
    if RandomRoll then
        RandomRoll(1, max)
    elseif C_RandomRoll and C_RandomRoll.RandomRoll then
        C_RandomRoll.RandomRoll(1, max)
    end
    self:RefreshRaidFrame()
end

-- Würfe aus dem Systemchat für die Raider-Ansicht mitschreiben
LC:On("CHAT_MSG_SYSTEM", function(self, msg)
    local R = self.raid
    if not R or not R.activeIdx then return end
    local it = R.items[R.activeIdx]
    if not it or it.state ~= "roll" then return end
    local name, roll, minRoll, maxRoll = self:ParseRoll(msg)
    if not name or minRoll ~= 1 then return end
    local offspec = (maxRoll == 99 and self:RaidIsFree(it))
    if maxRoll ~= 100 and not offspec then return end
    local key = self:NameKey(name)
    if it.rolls[key] then return end
    it.rolls[key] = { name = self:ShortName(name), roll = roll, valid = self:RaidIsAllowed(it, name), os = offspec or nil }
    if self:IsMe(name) then
        it.myRoll = roll
        it.myOS = offspec or nil
        it.rollPending = nil
    end
    self:RefreshRaidFrame()
end)
