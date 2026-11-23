-- Light Council – Ablauf: Loot erkennen, Council-Abstimmung (Leitung), Stimmabgabe (Council), Würfeln
local _, LC = ...

LC.lootItems = {}   -- Einträge im aktuell geöffneten Lootfenster
LC.itemState = {}   -- [key] = Eintrag (bleibt erhalten, wenn das Lootfenster erneut geöffnet wird)
LC.queue = {}       -- wartende Items
LC.active = nil     -- laufende Council-Abstimmung (nur Leitung)
LC.roll = nil       -- laufende Würfelrunde (nur Leitung)
LC.voteSession = nil -- Abstimmung, an der ich als Council-Mitglied teilnehme

local sidCounter = 0
local function NewSid()
    sidCounter = sidCounter + 1
    return string.format("%x%d", time() % 1048576, sidCounter)
end

local function NamesOf(list, filter)
    local out = {}
    for _, c in ipairs(list) do
        if not filter or filter(c) then out[#out + 1] = c.name end
    end
    return out
end

------------------------------------------------------------------------
-- Loot erkennen (Plündermeister)
------------------------------------------------------------------------
function LC:ScanLoot()
    wipe(self.lootItems)
    local threshold = (GetLootThreshold and GetLootThreshold()) or 2
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = self:ItemIDFromLink(link)
        if itemID then
            local _, _, _, _, quality = GetLootSlotInfo(slot)
            local relevant = (quality or 0) >= threshold or self:IsCouncilItem(itemID) or #self:GetReservers(itemID) > 0
            if relevant then
                local guid = GetLootSourceInfo and GetLootSourceInfo(slot) or "?"
                local key = tostring(guid) .. ":" .. itemID .. ":" .. slot
                local entry = self.itemState[key] or { key = key, itemID = itemID, status = "offen" }
                entry.link, entry.slot, entry.quality = link, slot, quality
                entry.isCouncil = self:IsCouncilItem(itemID)
                entry.looted = nil
                self.itemState[key] = entry
                table.insert(self.lootItems, entry)
            end
        end
    end
end

LC:On("LOOT_OPENED", function(self)
    if not self:IsMasterLooter() then return end
    self:ScanLoot()
    if #self.lootItems == 0 then return end
    self:ShowMainFrame("loot")
    self:NetLoot(self.lootItems)   -- Raider-Fenster bei allen Addon-Nutzern
    if self.db.config.autoStart then
        for _, entry in ipairs(self.lootItems) do
            if entry.isCouncil and entry.status == "offen" and not entry.autoStarted then
                entry.autoStarted = true
                self:Enqueue(entry)
            end
        end
    end
    self:RefreshUI()
end)

LC:On("LOOT_SLOT_CLEARED", function(self, slot)
    for _, entry in ipairs(self.lootItems) do
        if entry.slot == slot and not entry.test then entry.looted = true end
    end
    self:RefreshUI()
end)

LC:On("LOOT_CLOSED", function(self)
    self:RefreshUI()
end)

-- Platzhalter wie "Item #19019" durch den echten Itemlink ersetzen, sobald die Itemdaten geladen sind
function LC:FixEntryLink(entry)
    if entry and entry.itemID and not (entry.link or ""):find("|H") then
        entry.link = self:ItemLink(entry.itemID)
    end
    return entry and entry.link
end

------------------------------------------------------------------------
-- Warteschlange
------------------------------------------------------------------------
function LC:Enqueue(entry)
    for _, e in ipairs(self.queue) do
        if e == entry then return end
    end
    if self.active and self.active.entry == entry then return end
    if self.roll and self.roll.entry == entry then return end
    entry.status = "wartet"
    entry.winner = nil
    table.insert(self.queue, entry)
    self:ProcessQueue()
end

function LC:ProcessQueue()
    if self.active or self.roll then return end
    local entry = table.remove(self.queue, 1)
    if not entry then self:RefreshUI() return end
    self:FixEntryLink(entry)
    if entry.isCouncil then
        self:StartCouncil(entry)
    else
        self:StartNormal(entry)
    end
    self:RefreshUI()
end

------------------------------------------------------------------------
-- Kandidaten
------------------------------------------------------------------------
function LC:BuildCandidates(entry)
    local test = entry.test
    local members = self:GetGroupMembers()
    local reservers = test and entry.testReservers or self:GetReservers(entry.itemID)
    local list = {}
    for _, r in ipairs(reservers) do
        local m = self:FindByName(members, r.name)
        local c = { name = m and m.name or r.name, note = r.note }
        c.key = self:NameKey(c.name)
        c.present = test or (m ~= nil and m.online)
        if entry.isCouncil then
            if test then
                c.cooldown = r.cooldown
            else
                c.cooldown = self:IsOnCooldown(c.name)
                c.sitout = self:IsSittingOut(c.name, entry.itemID)
            end
        end
        c.score, c.att, c.parse, c.eng = self:GetScore(c.name)
        if test then
            c.att = c.att or r.att
            c.parse = c.parse or r.parse
            c.eng = c.eng or r.eng
            local w = self.db.config.weights
            c.score = c.score or math.floor((c.att * w.attendance + c.parse * w.parse + (c.eng - 1) / 4 * 100 * w.engagement)
                / (w.attendance + w.parse + w.engagement) + 0.5)
        end
        list[#list + 1] = c
    end

    local anyEligible, relaxed = false, false
    for _, c in ipairs(list) do
        c.eligible = c.present and not c.cooldown and not c.sitout
        anyEligible = anyEligible or c.eligible
    end
    if not anyEligible then
        -- Alle Anwesenden im Cooldown: Cooldown ausnahmsweise ignorieren
        for _, c in ipairs(list) do
            c.eligible = c.present and not c.sitout
            if c.eligible and c.cooldown then relaxed = true end
            anyEligible = anyEligible or c.eligible
        end
    end
    if not anyEligible then
        for _, c in ipairs(list) do c.eligible = c.present end
    end
    table.sort(list, function(a, b) return (a.score or -1) > (b.score or -1) end)
    return list, relaxed
end

local function ExcludedText(list)
    local out = {}
    for _, c in ipairs(list) do
        if not c.eligible then
            local why = (not c.present) and "nicht anwesend" or (c.sitout and "setzt diese Woche aus") or (c.cooldown and "Loot-Cooldown") or "ausgeschlossen"
            out[#out + 1] = c.name .. " (" .. why .. ")"
        end
    end
    return out
end

-- Hinweise für Spieler, die durch Regeln (Loot-Cooldown / Aussetzen) ausgeschlossen sind
function LC:RuleNotices(cand)
    local out = {}
    for _, c in ipairs(cand) do
        if c.present and not c.eligible and (c.sitout or c.cooldown) then
            out[#out + 1] = { name = c.name, kind = c.sitout and "SIT" or "CD", reason = "" }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Council-Abstimmung starten (Leitung)
------------------------------------------------------------------------
function LC:StartCouncil(entry)
    local test = entry.test
    local link = entry.link
    local cand, relaxed = self:BuildCandidates(entry)
    local eligible = NamesOf(cand, function(c) return c.eligible end)
    local excluded = ExcludedText(cand)

    if #cand == 0 or #eligible == 0 then
        local why = (#cand == 0) and "keine Reservierung" or "kein Reservierer anwesend"
        self:Announce("Council-Item " .. link .. ": " .. why .. " – freies Würfeln.", test, true)
        local log = self:AddLog({ itemID = entry.itemID, link = link, result = why .. " – freies Würfeln", test = test, excluded = excluded })
        return self:StartRoll(entry, nil, log)
    end

    -- Abstimmende Council-Mitglieder bestimmen (Befangene ausgeschlossen)
    local members = self:GetGroupMembers()
    local councilList = test and { self:PlayerName() } or self:GetCouncilList()
    local voters, recused, nVoters = {}, {}, 0
    for _, n in ipairs(councilList) do
        local m = self:FindByName(members, n)
        local memberName = m and m.name or n
        local reserved = false
        for _, c in ipairs(cand) do
            if self:NamesMatch(c.name, memberName) then reserved = true break end
        end
        if reserved and not test then
            recused[#recused + 1] = { name = memberName, target = m and m.online and m.fullName }
        elseif m and m.online then
            local key = self:NameKey(m.name)
            if not voters[key] then
                voters[key] = { name = m.name, target = m.fullName }
                nVoters = nVoters + 1
            end
        end
    end

    local need = test and 1 or self:CouncilMajority()
    if nVoters < need then
        local text = "Council nicht beschlussfähig – alle Reservierer würfeln normal"
        self:Announce("Council-Item " .. link .. ": " .. text .. ".", test, true)
        local log = self:AddLog({
            itemID = entry.itemID, link = link, result = text, test = test,
            recused = NamesOf(recused), excluded = excluded, rollers = eligible,
        })
        self:NotifyExcluded(entry, self:RuleNotices(cand))
        return self:StartRoll(entry, eligible, log)
    end

    local timeout = self.db.config.voteTimeout or 30
    local sid = NewSid()
    self.active = {
        sid = sid, entry = entry, cand = cand, voters = voters, nVoters = nVoters,
        recused = recused, votes = {}, voteOrder = {}, need = need, test = test,
        excluded = excluded, relaxed = relaxed, endsAt = GetTime() + timeout,
    }
    entry.status = "Council stimmt ab"
    self:NetItem(entry, "CS")

    -- Kandidaten in möglichst wenige Nachrichten packen
    local chunks, cur = {}, ""
    for _, c in ipairs(cand) do
        local flags = (c.eligible and "E" or "") .. (c.cooldown and "C" or "") .. (c.sitout and "S" or "") .. (c.present and "" or "A")
        local s = string.format("%s:%s:%s:%s:%s:%s", c.name, c.score or "-", c.att or "-", c.parse or "-", c.eng or "-", flags)
        if #cur + #s + 1 > 200 then
            chunks[#chunks + 1] = cur
            cur = s
        else
            cur = (cur == "") and s or (cur .. ";" .. s)
        end
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end

    local function SendSession(target, isRecused)
        self:SendTo(target, "S", sid, tostring(timeout), isRecused and "1" or "0", link,
            tostring(need), tostring(test and 1 or self:GetCouncilSize()))
        for _, chunk in ipairs(chunks) do self:SendTo(target, "C", sid, chunk) end
        self:SendTo(target, "G", sid)
    end
    for _, v in pairs(voters) do SendSession(v.target, false) end
    for _, r in ipairs(recused) do
        if r.target then SendSession(r.target, true) end
    end

    self:Announce("Council-Item: " .. link .. " – der Council entscheidet (" .. timeout .. " Sek.)", test, true)
    -- Wartende Nachrichten verzögern das Popup beim Council – die Zeit wird hier draufgerechnet
    local delay = self:SendBacklog()
    self.active.endsAt = self.active.endsAt + delay
    self.active.timer = C_Timer.NewTimer(timeout + 3 + delay, function() LC:ResolveCouncil() end)
    self:RefreshUI()
end

------------------------------------------------------------------------
-- Stimmen sammeln und auswerten (Leitung)
------------------------------------------------------------------------
function LC:OnVote(sender, sid, decision, names, reason)
    local a = self.active
    if not a or a.sid ~= sid then return end
    local voter, key = self:FindByName(a.voters, sender)
    if not voter or a.votes[key] then return end
    if decision ~= "OPEN" and decision ~= "LIMIT" and decision ~= "SKIP" then return end
    if decision ~= "OPEN" and #names == 0 then return end

    local v = { name = a.voters[key].name, decision = decision, names = names, reason = reason }
    a.votes[key] = v
    table.insert(a.voteOrder, v)
    self:RefreshUI()
    if #a.voteOrder >= a.nVoters then
        self:ResolveCouncil()
    end
end

function LC:ResolveCouncil()
    local a = self.active
    if not a then return end
    if a.timer then a.timer:Cancel() end
    self.active = nil

    local entry, test, link = a.entry, a.test, a.entry.link

    -- Stimmen zählen: gleiche Entscheidung + gleiche Spieler = gleiche Stimme
    local tally = {}
    for _, v in ipairs(a.voteOrder) do
        local sig = v.decision
        if v.decision ~= "OPEN" then
            local keys = {}
            for _, n in ipairs(v.names) do keys[#keys + 1] = self:NameKey(n) end
            table.sort(keys)
            sig = sig .. ":" .. table.concat(keys, ",")
        end
        tally[sig] = tally[sig] or { count = 0, vote = v }
        tally[sig].count = tally[sig].count + 1
    end
    local best
    for _, t in pairs(tally) do
        if t.count >= a.need and (not best or t.count > best.count) then best = t end
    end

    local eligible = NamesOf(a.cand, function(c) return c.eligible end)
    local rollers, result = eligible, nil

    if best then
        local v = best.vote
        if v.decision == "OPEN" then
            result = "Freigegeben – alle Reservierer würfeln"
        elseif v.decision == "LIMIT" then
            local allowed = {}
            for _, n in ipairs(v.names) do allowed[self:NameKey(n)] = true end
            rollers = NamesOf(a.cand, function(c) return c.eligible and allowed[c.key] end)
            if #rollers == 0 then
                rollers = eligible
                result = "Eingrenzung ohne berechtigte Spieler – alle Reservierer würfeln"
            else
                result = "Nur " .. self:JoinNames(rollers) .. " würfeln"
            end
        elseif v.decision == "SKIP" then
            local skip = v.names[1]
            local skipKey = self:NameKey(skip)
            if not test then self:AddSitout(skip, entry.itemID) end
            rollers = NamesOf(a.cand, function(c) return c.eligible and c.key ~= skipKey end)
            result = self:ShortName(skip) .. " setzt bei diesem Item diese Woche aus"
            if #rollers == 0 then
                rollers = nil
                result = result .. " – keine weiteren Reservierer, freies Würfeln"
            end
        end
    else
        if #a.voteOrder < a.nVoters then
            result = "Zeit abgelaufen – alle Reservierer würfeln normal"
        else
            result = "Keine Mehrheit – alle Reservierer würfeln normal"
        end
    end

    self:Announce("Council " .. link .. ": " .. result, test, true)
    local announceExcluded = {}
    for _, c in ipairs(a.cand) do
        if c.present and not c.eligible then
            announceExcluded[#announceExcluded + 1] = c.name .. (c.sitout and " (setzt aus)" or " (Loot-Cooldown)")
        end
    end
    if #announceExcluded > 0 then
        self:AnnounceList("Council: nicht berechtigt –", announceExcluded, test)
    end
    if a.relaxed then
        self:Announce("Council: alle Anwesenden sind im Loot-Cooldown – Cooldown wird für dieses Item ignoriert.", test)
    end

    local log = self:AddLog({
        itemID = entry.itemID, link = link, result = result, test = test, council = true,
        votes = a.voteOrder, recused = NamesOf(a.recused), excluded = a.excluded,
        rollers = rollers or {},
    })

    -- Ausgeschlossene Spieler anonym informieren (mit der Begründung der Mehrheit)
    local notices = self:RuleNotices(a.cand)
    if best and rollers then
        local reasons, seen = {}, {}
        for _, v in ipairs(a.voteOrder) do
            if v.decision == best.vote.decision and v.reason and v.reason ~= "" and not seen[v.reason] then
                -- nur Stimmen, die genau dieser Entscheidung entsprechen
                local same = (v.decision == "OPEN")
                if not same then
                    local k1, k2 = {}, {}
                    for _, n in ipairs(v.names) do k1[#k1 + 1] = self:NameKey(n) end
                    for _, n in ipairs(best.vote.names) do k2[#k2 + 1] = self:NameKey(n) end
                    table.sort(k1) table.sort(k2)
                    same = table.concat(k1, ",") == table.concat(k2, ",")
                end
                if same then
                    seen[v.reason] = true
                    reasons[#reasons + 1] = v.reason
                end
            end
        end
        local reasonText = table.concat(reasons, " / ")
        local rollerSet = {}
        for _, n in ipairs(rollers) do rollerSet[self:NameKey(n)] = true end
        for _, c in ipairs(a.cand) do
            if c.present and c.eligible and not rollerSet[c.key] then
                local kind = (best.vote.decision == "SKIP") and "SKIP" or "LIMIT"
                notices[#notices + 1] = { name = c.name, kind = kind, reason = reasonText }
            end
        end
    end
    self:NotifyExcluded(entry, notices)

    local endText = self:CleanText(result, 180)
    for _, v in pairs(a.voters) do self:SendTo(v.target, "E", a.sid, endText) end
    for _, r in ipairs(a.recused) do
        if r.target then self:SendTo(r.target, "E", a.sid, endText) end
    end

    self:StartRoll(entry, rollers, log)
end

------------------------------------------------------------------------
-- Normales SoftRes-Item (Leitung)
------------------------------------------------------------------------
function LC:StartNormal(entry)
    local test = entry.test
    local cand = self:BuildCandidates(entry)
    local rollers = NamesOf(cand, function(c) return c.present end)
    local prio = self:GetPrio(entry.itemID)
    if prio and #prio > 0 then
        self:Announce("Prio für " .. entry.link .. ": " .. table.concat(prio, " > "), test)
    end
    local log = self:AddLog({
        itemID = entry.itemID, link = entry.link, test = test,
        result = (#rollers > 0) and "Reservierer würfeln" or "keine Reservierung – freies Würfeln",
        rollers = rollers,
    })
    self:StartRoll(entry, (#rollers > 0) and rollers or nil, log)
end

------------------------------------------------------------------------
-- Würfeln
------------------------------------------------------------------------
-- offspecTie = true: Stechen zwischen Off-Spec-Würfen (Gewinner bleibt als Off Spec markiert)
function LC:StartRoll(entry, rollers, logEntry, offspecTie)
    local test = entry.test
    local link = entry.link
    if rollers and #rollers == 1 then
        return self:FinishRollWith(entry, rollers[1], nil, logEntry, "einziger Berechtigter")
    end

    local allowed
    if rollers then
        allowed = {}
        for _, n in ipairs(rollers) do allowed[self:NameKey(n)] = n end
    end
    local t = self.db.config.rollTimeout or 20
    -- Freies Würfeln (keine Reservierung/Prio): Main Spec = /roll, Off Spec = /roll 99
    self.roll = { entry = entry, allowed = allowed, rollers = rollers, rolls = {}, count = 0, log = logEntry,
        endsAt = GetTime() + t, free = (rollers == nil), offspecTie = offspecTie or nil }
    entry.status = "Würfeln"

    if rollers then
        self:AnnounceList("Würfelt jetzt (/roll) für " .. link .. " – " .. t .. " Sek.:", rollers, test)
    else
        self:Announce("Freies Würfeln für " .. link .. " – Main Spec: /roll · Off Spec: /roll 99 – " .. t .. " Sek.", test, true)
    end
    self.roll.timer = C_Timer.NewTimer(t, function() LC:FinishRoll() end)
    self:NetRollStart(entry, rollers, t)

    if test and rollers then
        local roll = self.roll
        for _, n in ipairs(rollers) do
            if not self:IsMe(n) then
                C_Timer.After(1 + math.random() * 4, function()
                    if LC.roll == roll then LC:HandleRoll(n, math.random(1, 100), 1, 100) end
                end)
            end
        end
    end
    self:RefreshUI()
end

function LC:HandleRoll(name, roll, minRoll, maxRoll)
    local r = self.roll
    if not r then return end
    if minRoll ~= 1 then return end
    local offspec = false
    if maxRoll == 99 and r.free then
        offspec = true
    elseif maxRoll ~= 100 then
        return
    end
    local key = self:NameKey(name)
    local displayName = self:ShortName(name)
    if r.allowed then
        local allowedName, allowedKey = self:FindByName(r.allowed, name)
        if not allowedName then return end
        key, displayName = allowedKey, allowedName
    end
    if r.rolls[key] then return end
    r.rolls[key] = { name = displayName, roll = roll, os = offspec or nil }
    r.count = r.count + 1
    self:RefreshUI()
    if r.rollers and r.count >= #r.rollers then
        self:FinishRoll()
    end
end

function LC:FinishRoll()
    local r = self.roll
    if not r then return end
    if r.timer then r.timer:Cancel() end
    self.roll = nil
    local entry = r.entry

    -- Main Spec geht vor Off Spec: OS-Würfe zählen nur, wenn niemand für Main Spec gewürfelt hat
    local anyMS = false
    for _, x in pairs(r.rolls) do if not x.os then anyMS = true break end end
    local wantOS = r.free and not anyMS
    local best, tied = -1, {}
    for _, x in pairs(r.rolls) do
        if (x.os and true or false) == wantOS then
            if x.roll > best then
                best, tied = x.roll, { x.name }
            elseif x.roll == best then
                tied[#tied + 1] = x.name
            end
        end
    end
    if best < 0 then
        self:Announce("Niemand hat für " .. entry.link .. " gewürfelt.", entry.test)
        entry.status = "offen"
        self:NetItem(entry, "RN")
        self:RefreshUI()
        if entry.test then C_Timer.After(4, function() LC:RemoveTestEntry(entry) end) end
        C_Timer.After(1.5, function() LC:ProcessQueue() end)
        return
    end
    if #tied > 1 then
        self:Announce("Gleichstand (" .. best .. ") zwischen " .. self:JoinNames(tied) .. " – bitte erneut würfeln (/roll)!", entry.test)
        return self:StartRoll(entry, tied, r.log, wantOS)
    end
    local isOS = wantOS or r.offspecTie
    self:FinishRollWith(entry, tied[1], best, r.log, isOS and "Off Spec" or nil, isOS)
end

-- offspec = true: der Gewinner hat für Off Spec gewürfelt
function LC:FinishRollWith(entry, winner, roll, logEntry, note, offspec)
    winner = self:ShortName(winner)
    entry.winner = winner
    entry.winRoll = roll
    entry.winOS = offspec or nil
    entry.status = "Gewinner: " .. winner
    local msg = entry.link .. " geht an " .. winner
    if roll then msg = msg .. " (" .. roll .. ")" end
    if note then msg = msg .. " – " .. note end
    self:Announce(msg, entry.test, true)   -- Gewinner immer per Raidwarnung
    self:NetItem(entry, "RW", self:CleanText(winner, 40), roll and tostring(roll) or "", offspec and "1" or "")
    if logEntry then logEntry.winner = winner end
    if entry.isCouncil and not entry.test then
        self:AddCouncilWin(winner, entry.itemID)
    end
    self:RefreshUI()
    -- Automatisch vergeben (Einstellung auf der Loot-Seite); klappt nur bei geöffnetem Lootfenster
    if self.db.config.autoAward and (entry.test or self:IsMasterLooter()) then
        C_Timer.After(1, function()
            if entry.winner and not entry.awarded and not entry.looted then LC:AwardLoot(entry, true) end
        end)
    end
    C_Timer.After(1.5, function() LC:ProcessQueue() end)
end

-- Würfelergebnisse aus dem Systemchat lesen (sprachunabhängig über RANDOM_ROLL_RESULT)
local rollPattern
local function GetRollPattern()
    if rollPattern then return rollPattern end
    local p = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
    return rollPattern
end

-- Gibt Name, Wurf, Minimum, Maximum zurück, wenn die Systemnachricht ein /roll-Ergebnis ist
function LC:ParseRoll(msg)
    local name, roll, minRoll, maxRoll = (msg or ""):match(GetRollPattern())
    if not name then return nil end
    return name, tonumber(roll), tonumber(minRoll), tonumber(maxRoll)
end

LC:On("CHAT_MSG_SYSTEM", function(self, msg)
    if not self.roll then return end
    local name, roll, minRoll, maxRoll = msg:match(GetRollPattern())
    if name then
        self:HandleRoll(name, tonumber(roll), tonumber(minRoll), tonumber(maxRoll))
    end
end)

------------------------------------------------------------------------
-- Loot vergeben (Plündermeister)
------------------------------------------------------------------------
-- Test-Einträge aus der Loot-Liste entfernen (außer dem, der gerade läuft)
function LC:RemoveTestEntry(entry)
    if self.active and self.active.entry == entry then return end
    if self.roll and self.roll.entry == entry then return end
    for i = #self.queue, 1, -1 do
        if self.queue[i] == entry then return end
    end
    for i = #self.lootItems, 1, -1 do
        if self.lootItems[i] == entry then table.remove(self.lootItems, i) end
    end
    self:RefreshUI()
end

function LC:ClearTestEntries()
    for i = #self.lootItems, 1, -1 do
        local e = self.lootItems[i]
        if e.test then self:RemoveTestEntry(e) end
    end
end

-- Vergabe abschließen: Status, Historie, Raider informieren
function LC:MarkAwarded(entry, winner)
    winner = self:ShortName(winner)
    entry.winner = entry.winner or winner
    entry.status = "vergeben an " .. winner
    entry.awarded = true
    -- Wurf und Off Spec gehören nur dazu, wenn der Würfelgewinner das Item auch bekommt
    local same = self:NamesMatch(winner, entry.winner)
    local isOS = (same and entry.winOS) and true or nil
    if not entry.test then
        local h = {
            id = (entry.lid or entry.key or "?") .. "#" .. tostring(entry.idx or entry.slot or 0),
            itemID = entry.itemID, winner = winner,
            roll = same and entry.winRoll or nil,
            council = entry.isCouncil and true or nil,
            reserved = self:WasReserved(entry.itemID, winner) or nil,
            offspec = isOS,
        }
        if self:AddHistory(h) then self:ShareHistoryEntry(h) end
    end
    self:NetItem(entry, "RA", self:CleanText(winner, 40), isOS and "1" or "")
    self:RefreshUI()
    -- Test erledigt: nach kurzer Zeit aus der Liste nehmen
    if entry.test then
        C_Timer.After(4, function() LC:RemoveTestEntry(entry) end)
    end
end

-- auto = true: automatische Vergabe direkt nach dem Würfeln (leisere Meldungen)
function LC:AwardLoot(entry, auto)
    if not entry or not entry.winner or entry.awarded then return end
    if entry.test then
        self:Print("Test: " .. entry.link .. " würde " .. (auto and "automatisch " or "") .. "an " .. entry.winner .. " vergeben.")
        self:MarkAwarded(entry, entry.winner)
        return
    end
    local slot
    if entry.slot and GetLootSlotLink(entry.slot) == entry.link then
        slot = entry.slot
    else
        for s = 1, GetNumLootItems() do
            if GetLootSlotLink(s) == entry.link then slot = s break end
        end
    end
    if not slot then
        if auto then
            self:Print(entry.link .. " geht an " .. entry.winner .. " – Lootfenster ist zu. Leiche öffnen und „An …“ klicken.")
        else
            self:Print("Das Item liegt nicht im geöffneten Lootfenster. Bitte die Leiche erneut öffnen.")
        end
        return
    end
    for i = 1, 40 do
        local cand = GetMasterLootCandidate(slot, i)
        if cand and self:NamesMatch(cand, entry.winner) then
            self.awarding = true
            GiveMasterLoot(slot, i)
            self.awarding = nil
            self:MarkAwarded(entry, entry.winner)
            return
        end
    end
    self:Print(entry.winner .. " kann das Item nicht erhalten (nicht in Reichweite oder nicht berechtigt)."
        .. (auto and " Bitte von Hand vergeben." or ""))
end

-- Vergabe am Addon vorbei (Blizzard-Plündermeister-Menü) trotzdem erfassen
if GiveMasterLoot then
    hooksecurefunc("GiveMasterLoot", function(slot, index)
        if LC.awarding or not LC.db then return end
        local cand = GetMasterLootCandidate(slot, index)
        local link = GetLootSlotLink(slot)
        if not cand or not link then return end
        local match
        for _, entry in ipairs(LC.lootItems) do
            if not entry.test and not entry.awarded and entry.link == link then
                if entry.slot == slot then match = entry break end
                match = match or entry
            end
        end
        if match then LC:MarkAwarded(match, cand) end
    end)
end

------------------------------------------------------------------------
-- Abbrechen
------------------------------------------------------------------------
function LC:CancelAll()
    local any = false
    if self.active then
        local a = self.active
        if a.timer then a.timer:Cancel() end
        self.active = nil
        a.entry.status = "offen"
        for _, v in pairs(a.voters) do self:SendTo(v.target, "E", a.sid, "Abstimmung abgebrochen") end
        for _, r in ipairs(a.recused) do
            if r.target then self:SendTo(r.target, "E", a.sid, "Abstimmung abgebrochen") end
        end
        self:Announce("Council-Abstimmung für " .. a.entry.link .. " abgebrochen.", a.test)
        self:NetItem(a.entry, "RC")
        any = true
    end
    if self.roll then
        local r = self.roll
        if r.timer then r.timer:Cancel() end
        self.roll = nil
        r.entry.status = "offen"
        self:Announce("Würfelrunde für " .. r.entry.link .. " abgebrochen.", r.entry.test)
        self:NetItem(r.entry, "RC")
        any = true
    end
    for _, e in ipairs(self.queue) do e.status = "offen" end
    wipe(self.queue)
    self:ClearTestEntries()   -- abgebrochene Tests verschwinden aus der Liste
    if not any then self:Print("Nichts aktiv.") end
    self:RefreshUI()
end

------------------------------------------------------------------------
-- Testmodus
------------------------------------------------------------------------
function LC:StartTest(arg)
    arg = arg or ""
    self:ClearTestEntries()   -- alte, liegengebliebene Tests entfernen
    local itemID = self:ItemIDFromLink(arg) or tonumber(arg) or 19019
    local link = arg:match("|c.-|r") or self:ItemLink(itemID)
    local entry = {
        key = "test:" .. GetTime(), itemID = itemID, link = link, isCouncil = true,
        status = "offen", test = true,
        testReservers = {
            { name = "Anna", att = 100, parse = 82, eng = 5 },
            { name = "Ben",  att = 88,  parse = 64, eng = 4 },
            { name = "Carl", att = 75,  parse = 91, eng = 3, cooldown = true },
            { name = "Dora", att = 50,  parse = 45, eng = 2 },
            { name = self:PlayerName(), att = 63, parse = 70, eng = 3 },   -- du selbst, damit du würfeln kannst
        },
    }
    table.insert(self.lootItems, entry)
    self:Print("Testmodus: Council-Ablauf für " .. link .. " (Ansagen erscheinen nur lokal). "
        .. "Tipp: Stimme mit „Aussetzen“ für dich selbst, um den Hinweis für ausgeschlossene Spieler zu sehen.")
    self:ShowMainFrame("loot")
    self:NetLoot({ entry }, true)
    self:Enqueue(entry)
end

------------------------------------------------------------------------
-- Council-Mitglied: Abstimmung empfangen und Stimme abgeben
------------------------------------------------------------------------
function LC:VoteSessionBegin(sender, sid, timeout, recused, link, need, size)
    self.voteSession = {
        owner = sender, sid = sid, timeout = timeout, recused = recused, link = link,
        itemID = self:ItemIDFromLink(link), candidates = {}, voted = false,
        need = need or 2, size = size or 3,
    }
end

function LC:VoteSessionCandidates(sender, sid, payload)
    local s = self.voteSession
    if not s or s.sid ~= sid or self:NameKey(sender) ~= self:NameKey(s.owner) or not payload then return end
    for item in payload:gmatch("[^;]+") do
        local name, score, att, parse, eng, flags = strsplit(":", item)
        table.insert(s.candidates, {
            name = name, score = tonumber(score), att = tonumber(att),
            parse = tonumber(parse), eng = tonumber(eng), flags = flags or "",
        })
    end
end

function LC:VoteSessionShow(sender, sid)
    local s = self.voteSession
    if not s or s.sid ~= sid or self:NameKey(sender) ~= self:NameKey(s.owner) then return end
    s.expires = GetTime() + s.timeout
    self:ShowVoteFrame(s)
    if SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
    if FlashClientIcon then pcall(FlashClientIcon) end
end

function LC:SubmitVote(decision, names, reason)
    local s = self.voteSession
    if not s or s.voted or s.recused or s.ended then return false, "Keine offene Abstimmung." end
    if s.expires and GetTime() > s.expires then return false, "Die Zeit ist abgelaufen." end
    if decision == "LIMIT" and #names == 0 then return false, "Für „Eingrenzen“ mindestens einen Spieler anhaken." end
    if decision == "SKIP" and #names ~= 1 then return false, "Für „Aussetzen“ genau einen Spieler anhaken." end
    s.voted = true
    s.myVote = { decision = decision, names = names, reason = reason }
    self:SendTo(s.owner, "V", s.sid, decision, table.concat(names, ","), self:CleanText(reason, 120))
    return true
end

function LC:VoteSessionEnd(sender, sid, text)
    local s = self.voteSession
    if not s or s.sid ~= sid or self:NameKey(sender) ~= self:NameKey(s.owner) then return end
    s.ended = true
    s.result = text
    -- Council-Mitglieder führen ein eigenes Protokoll (die Leitung protokolliert selbst ausführlich)
    if not self:IsMe(sender) then
        local votes = {}
        if s.myVote then
            votes[1] = { name = self:PlayerName(), decision = s.myVote.decision, names = s.myVote.names, reason = s.myVote.reason }
        end
        self:AddLog({ itemID = s.itemID, link = s.link, result = text, council = true, votes = votes,
            recused = s.recused and { self:PlayerName() } or nil })
    end
    self:UpdateVoteFrame()
    C_Timer.After(6, function()
        if LC.voteSession == s then LC:HideVoteFrame() end
    end)
end
