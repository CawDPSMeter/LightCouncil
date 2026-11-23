-- Light Council – Reservierungen im Addon (ersetzt softres.it)
--
-- Regeln:
--   * Jeder Raider reserviert pro Raid bis zu N Items (Einstellung, Standard 2).
--   * Sobald ein Council-Mitglied die Reservierung bestätigt hat, ist sie gesperrt.
--   * Änderungen nur per Antrag; ein Council-Mitglied (nicht der Antragsteller) gibt frei oder lehnt ab.
--   * Der Council kann für Spieler ohne Addon direkt eintragen.
--
-- Datenhaltung (bei jedem Addon-Nutzer, damit auch der Plündermeister alles kennt):
--   db.reserves[raidKey] = { epoch = n, players = { [key] = { name, items = {id,…}, rev, time,
--                                                              pending = { items, reason, time } } } }
--   rev 0 = noch nicht bestätigt (nur eigener Eintrag), ab 1 = vom Council bestätigt und gesperrt.
--   epoch = "Runde"; eine neue Runde löscht alle Reservierungen des Raids.
--
-- Nachrichten (Gilde, im Raid zusätzlich Raid):
--   YR~raid~epoch~rev~items          Raider: meine Reservierung (rev 0 = neu)
--   YC~raid~epoch~items~grund        Raider: Änderungsantrag
--   YA~raid~epoch~spieler~rev~items  Council: verbindlicher Eintrag
--   YP~raid~epoch~spieler~items~grund  Council: offener Antrag (für den Abgleich)
--   YD~raid~epoch~spieler~1|0~rev~items  Council: Antrag freigegeben / abgelehnt
--   YX~raid~epoch                    Council: neue Runde (alles löschen)
--   YQ                               alle: bitte Abgleich schicken
--   YL~name;name;…                   Council: wer gehört zum Council
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { YR = true, YC = true, YA = true, YP = true, YD = true, YX = true, YQ = true, YL = true }

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
function LC:MaxReserves()
    -- Raider übernehmen die Zahl, die der Council eingestellt hat
    local n = self.db.config.maxReserves
    if not self:AmICouncil() and self.db.knownMax then n = self.db.knownMax end
    return math.max(1, math.min(5, tonumber(n) or 2))
end

function LC:ResRaid(raid)
    self.db.reserves = self.db.reserves or {}
    local r = self.db.reserves[raid]
    if not r then
        r = { epoch = 0, players = {} }
        self.db.reserves[raid] = r
    end
    return r
end

function LC:GetReservation(raid, name)
    local r = self.db.reserves and self.db.reserves[raid]
    if not r then return nil end
    return self:FindByName(r.players, name or self:PlayerName())
end

local function ParseItems(s)
    local out, seen = {}, {}
    for id in (s or ""):gmatch("%d+") do
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end
LC.ParseItemList = ParseItems

local function ItemsString(items)
    local t = {}
    for i, id in ipairs(items or {}) do t[i] = tostring(id) end
    return table.concat(t, ",")
end

local function SameItems(a, b)
    if #(a or {}) ~= #(b or {}) then return false end
    local set = {}
    for _, id in ipairs(a) do set[id] = true end
    for _, id in ipairs(b) do if not set[id] then return false end end
    return true
end
LC.SameItems = SameItems

-- Council, dem ich vertraue: eigene Einstellung, sonst die vom Council übermittelte Liste
function LC:GetTrustedCouncil()
    local own = self:GetCouncilList()
    if #own > 0 then return own end
    return self.db.knownCouncil or {}
end

function LC:IsTrustedCouncil(name)
    for _, n in ipairs(self:GetTrustedCouncil()) do
        if self:NamesMatch(n, name) then return true end
    end
    return false
end

-- Wer eine ERSTE Council-Liste schicken darf (solange noch keine bekannt ist):
-- Raidleiter, Gildenmeister oder Offiziere (Gildenrang 0 oder 1). Sonst könnte jeder
-- Gildenkollege zuerst eine falsche Liste schicken und der echte Council käme nicht mehr durch.
function LC:IsTrustedFirstSource(sender)
    local m = self:FindByName(self:GetGroupMembers(), sender)
    if m and (m.rank or 0) >= 2 then return true end
    if IsInGuild() and GetGuildRosterInfo and GetNumGuildMembers then
        local key = self:NameKey(sender)
        local fallback
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name then
                if self:NameKey(name) == key then return (rankIndex or 99) <= 1 end
                if fallback == nil and self:NamesMatch(name, sender) then fallback = (rankIndex or 99) <= 1 end
            end
        end
        if fallback then return true end
    end
    return false
end

-- Alternative für Gilden, in denen der Council nicht aus Offizieren besteht:
-- Zwei verschiedene Council-Mitglieder, die selbst auf der Liste stehen, schicken dieselbe Liste.
local firstSeen = {}   -- [Liste] = { [Absender] = true }
function LC:FirstListConfirmed(list, sender)
    local inList = false
    for _, n in ipairs(list) do
        if self:NamesMatch(n, sender) then inList = true break end
    end
    if not inList then return false end
    local keys = {}
    for i, n in ipairs(list) do keys[i] = self:NameKey(n) or "" end
    table.sort(keys)
    local sig = table.concat(keys, ";")
    firstSeen[sig] = firstSeen[sig] or {}
    firstSeen[sig][self:NameKey(sender)] = true
    local n = 0
    for _ in pairs(firstSeen[sig]) do n = n + 1 end
    return n >= 2
end

-- Gespeicherte Council-Liste vergessen und neu vom Council anfragen (/lc councilreset)
function LC:ResetKnownCouncil()
    self.db.knownCouncil = {}
    self.db.knownRaidDays, self.db.knownReminderRaid = nil, nil
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    self:RequestResSync(true)
    self:RefreshUI()
end

function LC:AmICouncil()
    return self:IsCouncilMember(self:PlayerName())
end

-- Reservierungen -> Liste der Reservierer pro Item (wird vom Loot-Ablauf benutzt)
function LC:RebuildReservers()
    local res, count = {}, 0
    for _, r in pairs(self.db.reserves or {}) do
        for _, p in pairs(r.players) do
            if (p.rev or 0) > 0 then
                for _, id in ipairs(p.items or {}) do
                    res[id] = res[id] or {}
                    table.insert(res[id], { name = p.name, note = "" })
                    count = count + 1
                end
            end
        end
    end
    self.db.softres = res
    self.db.softresMeta = { time = time(), count = count }
end

------------------------------------------------------------------------
-- Senden
------------------------------------------------------------------------
function LC:ResSend(...)
    local msg = strjoin(SEP, ...)
    local sent = false
    if IsInGuild() then self:Send(msg, "GUILD") sent = true end
    if IsInRaid() then self:Send(msg, "RAID") sent = true
    elseif IsInGroup() then self:Send(msg, "PARTY") sent = true end
    return sent
end

local function Changed()
    LC:RebuildReservers()
    LC:RefreshUI()
end

------------------------------------------------------------------------
-- Raider: reservieren und Änderung beantragen
------------------------------------------------------------------------
function LC:SubmitReservation(raid, items)
    local max = self:MaxReserves()
    if #items == 0 then return false, L["Bitte mindestens ein Item auswählen."] end
    if #items > max then return false, L["Höchstens "] .. max .. L[" Items pro Raid."] end
    local current = self:GetReservation(raid)
    if current and (current.rev or 0) > 0 then
        return false, L["Deine Reservierung ist gesperrt. Nutze „Änderung beantragen“."]
    end
    local R = self:ResRaid(raid)
    local me = self:PlayerName()
    R.players[self:NameKey(me)] = { name = me, items = items, rev = 0, time = time() }
    local sent = self:ResSend("YR", raid, tostring(R.epoch), "0", ItemsString(items))
    -- Ist man selbst im Council, sofort verarbeiten
    if self:AmICouncil() then self:ResHandle("YR", { "YR", raid, tostring(R.epoch), "0", ItemsString(items) }, me) end
    Changed()
    if not sent and not self:AmICouncil() then
        return true, L["Gespeichert – aber du bist in keiner Gilde oder Gruppe. Die Reservierung wird übermittelt, sobald du online mit dem Council bist („Abgleichen“)."]
    end
    return true, L["Reservierung gesendet – wartet auf Bestätigung durch den Council."]
end

function LC:RequestReservationChange(raid, items, reason)
    local max = self:MaxReserves()
    if #items == 0 then return false, L["Bitte mindestens ein Item auswählen."] end
    if #items > max then return false, L["Höchstens "] .. max .. L[" Items pro Raid."] end
    local current = self:GetReservation(raid)
    if not current or (current.rev or 0) == 0 then return self:SubmitReservation(raid, items) end
    if SameItems(current.items, items) then return false, L["Das ist bereits deine Reservierung."] end
    reason = self:CleanText(reason or "", 120)
    if reason == "" then return false, L["Bitte kurz begründen, warum du ändern möchtest."] end
    current.pending = { items = items, reason = reason, time = time() }
    local R = self:ResRaid(raid)
    self:ResSend("YC", raid, tostring(R.epoch), ItemsString(items), reason)
    if self:AmICouncil() then
        self:ResHandle("YC", { "YC", raid, tostring(R.epoch), ItemsString(items), reason }, self:PlayerName())
    end
    Changed()
    return true, L["Änderungsantrag gesendet – der Council entscheidet."]
end

------------------------------------------------------------------------
-- Council: bestätigen, entscheiden, manuell eintragen, neue Runde
------------------------------------------------------------------------
local function BroadcastRecord(raid, R, p)
    LC:ResSend("YA", raid, tostring(R.epoch), p.name, tostring(p.rev), ItemsString(p.items))
end

function LC:DecideChange(raid, name, approve)
    if not self:AmICouncil() then return false, L["Nur der Council kann Anträge entscheiden."] end
    local R = self:ResRaid(raid)
    local p = self:FindByName(R.players, name)
    if not p or not p.pending then return false, L["Kein offener Antrag gefunden."] end
    if self:IsMe(p.name) then return false, L["Über deinen eigenen Antrag entscheidet ein anderes Council-Mitglied."] end
    local newItems = p.pending.items
    local oldItems = p.items
    local reason = p.pending.reason
    if approve then
        p.items = newItems
        p.rev = (p.rev or 0) + 1
    end
    p.pending = nil
    p.time = time()
    self:ResSend("YD", raid, tostring(R.epoch), p.name, approve and "1" or "0", tostring(p.rev), ItemsString(p.items))
    self:AddLog({
        kind = "reserve", itemID = newItems[1], link = L["Reservierung "] .. p.name,
        result = string.format(L["Änderung %s von %s: %s → %s. Begründung des Raiders: %s"],
            approve and L["freigegeben"] or L["abgelehnt"], self:PlayerName(), self:ItemListText(oldItems), self:ItemListText(newItems), reason or "-"),
    })
    Changed()
    return true, approve and L["Änderung freigegeben."] or L["Änderung abgelehnt."]
end

function LC:CouncilSetReservation(raid, name, items)
    if not self:AmICouncil() then return false, L["Nur der Council kann für andere eintragen."] end
    name = strtrim(name or ""):gsub("%s+", " ")
    if name == "" then return false, L["Bitte einen Namen eingeben."] end
    if #items > self:MaxReserves() then return false, L["Höchstens "] .. self:MaxReserves() .. L[" Items pro Raid."] end
    local R = self:ResRaid(raid)
    local p, key = self:FindByName(R.players, name)
    if not p then
        key = self:NameKey(name)
        p = { name = name, rev = 0 }
        R.players[key] = p
    end
    local old = p.items
    p.items = items
    p.rev = (p.rev or 0) + 1
    p.pending = nil
    p.time = time()
    if #items == 0 then R.players[key] = nil end
    self:ResSend("YA", raid, tostring(R.epoch), p.name, tostring(p.rev), ItemsString(items))
    self:AddLog({
        kind = "reserve", itemID = items[1], link = L["Reservierung "] .. p.name,
        result = string.format("Vom Council (%s) eingetragen: %s (vorher: %s)", self:PlayerName(), self:ItemListText(items), self:ItemListText(old)),
    })
    Changed()
    return true, L["Reservierung für "] .. p.name .. L[" eingetragen."]
end

function LC:NewReserveRound(raid)
    if not self:AmICouncil() then return false, L["Nur der Council kann eine neue Runde starten."] end
    local R = self:ResRaid(raid)
    R.epoch = (R.epoch or 0) + 1
    wipe(R.players)
    self:ResSend("YX", raid, tostring(R.epoch))
    Changed()
    return true, L["Neue Runde gestartet – alle Reservierungen dieses Raids wurden gelöscht."]
end

local lastSync = 0
function LC:RequestResSync(force)
    if not force and GetTime() - lastSync < 60 then return end
    lastSync = GetTime()
    self:ResSend("YQ")
    -- eigene, noch nicht bestätigte Reservierungen erneut schicken (Council war evtl. offline)
    local me = self:PlayerName()
    for raid, R in pairs(self.db.reserves or {}) do
        local rec = self:FindByName(R.players, me)
        if rec and (rec.rev or 0) == 0 and rec.items and #rec.items > 0 then
            self:ResSend("YR", raid, tostring(R.epoch), "0", ItemsString(rec.items))
        end
    end
end

-- Antwort auf einen Abgleich: Council-Liste, alle Einträge und offene Anträge
function LC:SendResSync(target)
    local function Out(...)
        if target then self:SendTo(target, ...) else self:ResSend(...) end
    end
    local names = {}
    for _, n in ipairs(self:GetCouncilList()) do names[#names + 1] = self:CleanText(n, 40) end
    local days = {}
    for _, d in ipairs(self.db.config.raidDays or {}) do days[#days + 1] = tostring(d) end
    Out("YL", table.concat(names, ";"), tostring(self:MaxReserves()), table.concat(days, ","), self.db.config.reminderRaid or "",
        self.db.config.setReserve and "1" or "0")
    for raid, R in pairs(self.db.reserves or {}) do
        for _, p in pairs(R.players) do
            if (p.rev or 0) > 0 then
                Out("YA", raid, tostring(R.epoch), p.name, tostring(p.rev), ItemsString(p.items))
                if p.pending then
                    Out("YP", raid, tostring(R.epoch), p.name, ItemsString(p.pending.items), p.pending.reason or "")
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Empfang
------------------------------------------------------------------------
-- Prüft die Runde: alte Nachrichten verwerfen, neuere Runde übernehmen
local function CheckEpoch(R, epoch)
    epoch = tonumber(epoch) or 0
    if epoch < (R.epoch or 0) then return false end
    if epoch > (R.epoch or 0) then
        R.epoch = epoch
        wipe(R.players)
    end
    return true
end

function LC:ResHandle(cmd, p, sender)
    if cmd == "YQ" then
        -- Höchstens ein vollständiger Abgleich pro Anfragendem und Minute (sonst verstopft die Sende-Warteschlange
        -- und Abstimmungen kämen verspätet an)
        if self:AmICouncil() and not self:IsMe(sender) then
            local key = self:NameKey(sender)
            self.ysyncAnswered = self.ysyncAnswered or {}
            if key and (GetTime() - (self.ysyncAnswered[key] or -999)) >= 60 then
                self.ysyncAnswered[key] = GetTime()
                self:SendResSync(sender)
            end
        end
        return
    end

    if cmd == "YL" then
        local list = {}
        for n in (p[2] or ""):gmatch("[^;]+") do list[#list + 1] = n end
        -- Erste Liste nur von Raidleitung/Gildenleitung, danach nur Änderungen vom bekannten Council
        local trusted
        if #self:GetTrustedCouncil() == 0 then
            trusted = self:IsTrustedFirstSource(sender) or self:FirstListConfirmed(list, sender)
            if not trusted and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        else
            trusted = self:IsTrustedCouncil(sender)
        end
        if #list > 0 and trusted then
            self.db.knownCouncil = list
            self.db.knownMax = tonumber(p[3]) or self.db.knownMax
            -- Raidtage und Raid für die Erinnerung (ältere Versionen schicken das nicht mit)
            if p[4] then
                local days = {}
                for d in p[4]:gmatch("%d") do days[#days + 1] = tonumber(d) end
                self.db.knownRaidDays = days
                self.db.knownReminderRaid = p[5] or ""
                C_Timer.After(3, function() LC:CheckRaidDayReminder() end)
            end
            -- Reservieren aus dem Gear-Set (ab 0.16.0)
            if p[6] then self.db.knownSetReserve = (p[6] == "1") end
            self:RefreshUI()
        end
        return
    end

    local raid = p[2]
    if not raid or raid == "" or #raid > 60 or raid:find("[|;]") then return end
    -- Neue Raid-Schlüssel nur in Grenzen anlegen (Schutz vor aufgeblähten SavedVariables)
    if not (self.db.reserves and self.db.reserves[raid]) then
        local n = 0
        for _ in pairs(self.db.reserves or {}) do n = n + 1 end
        if n >= 40 then return end
    end
    local R = self:ResRaid(raid)

    if cmd == "YR" or cmd == "YC" then
        if not self:AmICouncil() then return end
        -- Die Runde (epoch) bestimmt nur der Council. Ein Raider darf sie nie hochsetzen –
        -- sonst könnte jeder mit einer gefälschten Nachricht alle Reservierungen löschen.
        local epoch = tonumber(p[3]) or 0
        if epoch ~= (R.epoch or 0) then
            if epoch < (R.epoch or 0) then
                self:SendTo(sender, "YX", raid, tostring(R.epoch))
            else
                -- Raider kennt eine neuere Runde: eigenen Stand beim restlichen Council holen
                self:RequestResSync(false)
            end
            return
        end
        local items = ParseItems(cmd == "YR" and p[5] or p[4])
        while #items > self:MaxReserves() do table.remove(items) end
        local rec, key = self:FindByName(R.players, sender)
        if cmd == "YR" then
            if not rec or (rec.rev or 0) == 0 then
                -- neue Reservierung: bestätigen und sperren
                if not key then key = self:NameKey(sender) end
                rec = { name = self:ShortName(sender), items = items, rev = 1, time = time() }
                R.players[key] = rec
                BroadcastRecord(raid, R, rec)
            else
                -- schon gesperrt: dem Raider den gültigen Stand schicken
                self:SendTo(sender, "YA", raid, tostring(R.epoch), rec.name, tostring(rec.rev), ItemsString(rec.items))
            end
        else
            if not rec or (rec.rev or 0) == 0 then
                if not key then key = self:NameKey(sender) end
                rec = { name = self:ShortName(sender), items = items, rev = 1, time = time() }
                R.players[key] = rec
                BroadcastRecord(raid, R, rec)
            elseif not SameItems(rec.items, items) then
                rec.pending = { items = items, reason = self:CleanText(p[5] or "", 120), time = time() }
                if not self:IsMe(sender) then
                    self:Print(rec.name .. L[" beantragt eine Änderung der Reservierung ("] .. self:ItemListText(items) .. L["). Entscheiden unter „Reservierungen“."])
                end
            end
        end
        Changed()
        return
    end

    -- Ab hier nur Nachrichten des Councils
    if not self:IsTrustedCouncil(sender) then return end

    if cmd == "YX" then
        if (tonumber(p[3]) or 0) > (R.epoch or 0) then
            R.epoch = tonumber(p[3])
            wipe(R.players)
            Changed()
        end
        return
    end

    if not CheckEpoch(R, p[3]) then return end
    local name = p[4]
    if not name or name == "" then return end
    local rec, key = self:FindByName(R.players, name)

    if cmd == "YA" then
        local rev = tonumber(p[5]) or 0
        local items = ParseItems(p[6])
        if not rec or rev >= (rec.rev or 0) then
            if not key then key = self:NameKey(name) end
            local pending = rec and rev == (rec.rev or 0) and rec.pending or nil
            if #items == 0 then
                R.players[key] = nil
            else
                R.players[key] = { name = (rec and rec.name) or name, items = items, rev = rev, time = time(), pending = pending }
            end
            Changed()
        end
    elseif cmd == "YP" then
        if rec and (rec.rev or 0) > 0 and not rec.pending then
            rec.pending = { items = ParseItems(p[5]), reason = self:SafeText(p[6], 120), time = time() }
            Changed()
        end
    elseif cmd == "YD" then
        local ok, rev, items = p[5] == "1", tonumber(p[6]) or 0, ParseItems(p[7])
        if rec and rev >= (rec.rev or 0) then
            if ok then rec.items, rec.rev = items, rev end
            rec.pending = nil
            if self:IsMe(name) then
                self:Print(ok and (L["|cff6ae08fDeine Änderung wurde freigegeben:|r "] .. self:ItemListText(items))
                    or L["|cffff6070Deine Änderung wurde vom Council abgelehnt.|r Deine Reservierung bleibt unverändert."])
            end
            Changed()
        end
    end
end

-- Kurze Itemliste für Texte: "[Item A], [Item B]"
function LC:ItemListText(items)
    if not items or #items == 0 then return "–" end
    local t = {}
    for i, id in ipairs(items) do t[i] = self:ItemLink(id) end
    return table.concat(t, ", ")
end

-- In den Nachrichten-Empfang einklinken
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd = msg:match("^(%u+)~") or msg
    if CMDS[cmd] then
        if self:IsMe(sender) and cmd ~= "YQ" then return end
        self:ResHandle(cmd, { strsplit(SEP, msg) }, sender)
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

-- Council-Liste und Höchstzahl an alle Addon-Nutzer schicken (nur Council)
function LC:BroadcastCouncilInfo()
    if not self:AmICouncil() then return end
    local names = {}
    for _, n in ipairs(self:GetCouncilList()) do names[#names + 1] = self:CleanText(n, 40) end
    local days = {}
    for _, d in ipairs(self.db.config.raidDays or {}) do days[#days + 1] = tostring(d) end
    self:ResSend("YL", table.concat(names, ";"), tostring(self:MaxReserves()),
        table.concat(days, ","), self.db.config.reminderRaid or "", self.db.config.setReserve and "1" or "0")
end

------------------------------------------------------------------------
-- Raidtage: Erinnerung, vorab zu reservieren
------------------------------------------------------------------------
LC.WEEKDAYS = {   -- Reihenfolge Mo–So, Wert = Wochentag wie in date("*t").wday
    { wday = 2, short = "Mo", long = "Montag" },
    { wday = 3, short = "Di", long = "Dienstag" },
    { wday = 4, short = "Mi", long = "Mittwoch" },
    { wday = 5, short = "Do", long = "Donnerstag" },
    { wday = 6, short = "Fr", long = "Freitag" },
    { wday = 7, short = "Sa", long = "Samstag" },
    { wday = 1, short = "So", long = "Sonntag" },
}

-- Raidtage und Erinnerungs-Raid: Council nimmt die eigene Einstellung, Raider die vom Council übermittelte
function LC:GetRaidDays()
    if self:AmICouncil() then
        return self.db.config.raidDays or {}, self.db.config.reminderRaid or ""
    end
    return self.db.knownRaidDays or {}, self.db.knownReminderRaid or ""
end

function LC:IsRaidDay(wday)
    wday = wday or date("*t").wday
    for _, d in ipairs((self:GetRaidDays())) do
        if d == wday then return true end
    end
    return false
end

-- "Di, Do" oder "keine"
function LC:RaidDaysText()
    local days = self:GetRaidDays()
    local set = {}
    for _, d in ipairs(days) do set[d] = true end
    local out = {}
    for _, w in ipairs(self.WEEKDAYS) do
        if set[w.wday] then out[#out + 1] = L[w.short] end
    end
    return (#out > 0) and table.concat(out, ", ") or L["keine"]
end

-- Darf aus dem Gear-Set reserviert werden? (Council-Einstellung, an Raider übermittelt)
function LC:SetReserveEnabled()
    if self:AmICouncil() or #self:GetCouncilList() > 0 then return self.db.config.setReserve == true end
    return self.db.knownSetReserve == true
end

function LC:SetRaidDays(days, raidKey, setReserve)
    self.db.config.raidDays = days
    self.db.config.reminderRaid = raidKey or ""
    if setReserve ~= nil then self.db.config.setReserve = setReserve and true or false end
    self:BroadcastCouncilInfo()
    self:RefreshUI()
end

-- Habe ich (für den Erinnerungs-Raid bzw. irgendeinen Raid) schon reserviert?
function LC:HasReservedFor(raidKey)
    if raidKey and raidKey ~= "" then
        local rec = self:GetReservation(raidKey)
        return rec ~= nil and #(rec.items or {}) > 0
    end
    for key in pairs(self.db.reserves or {}) do
        local rec = self:GetReservation(key)
        if rec and #(rec.items or {}) > 0 then return true end
    end
    return false
end

-- Am Raidtag einmal pro Tag erinnern, wenn noch nicht reserviert
function LC:CheckRaidDayReminder()
    if not self:IsRaidDay() then return end
    local today = date("%Y-%m-%d")
    if self.db.reminderShown == today then return end
    local _, raidKey = self:GetRaidDays()
    if self:HasReservedFor(raidKey) then return end
    self.db.reminderShown = today
    if self.ShowRaidDayReminder then self:ShowRaidDayReminder(raidKey) end
end

-- Reservierungsseite öffnen, auf Wunsch direkt für einen bestimmten Raid
function LC:OpenReservation(raidKey)
    self.wantRaid = (raidKey and raidKey ~= "") and raidKey or nil
    self:ShowMainFrame("myres")
end

-- Nach dem Einloggen Abgleich anfordern und (als Council) die eigene Liste verteilen
LC:On("PLAYER_LOGIN", function(self)
    C_Timer.After(25, function() LC:CheckRaidDayReminder() end)   -- nach dem Abgleich (Raidtage vom Council)
    C_Timer.After(12, function()
        LC:RebuildReservers()
        LC:RequestResSync(true)
        LC:BroadcastCouncilInfo()
    end)
end)
