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
--   YL~name;name;…~max~tage~raid~set~zeit   Council: wer gehört zum Council, Höchstzahl, Raidtage (zeit = wann eingestellt)
--   YZ~raid~epoch~open|timer|closed~zeit~von   Council/Raidleitung: Reservierungen schließen (Zeit = Serverzeit)
--   YW~raid~epoch~zeit               Council/Raidleitung -> Raider (Whisper): du hast noch nicht reserviert
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { YR = true, YC = true, YA = true, YP = true, YD = true, YX = true, YQ = true, YL = true, YZ = true, YW = true }

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
        if self:SameName(n, name) then return true end
    end
    return false
end

-- Wer eine ERSTE Council-Liste schicken darf (solange noch keine bekannt ist):
-- Raidleiter aus der eigenen Gilde, Gildenmeister oder Offiziere (Gildenrang 0 oder 1). Sonst könnte jeder
-- Gildenkollege zuerst eine falsche Liste schicken und der echte Council käme nicht mehr durch.
function LC:IsTrustedFirstSource(sender)
    -- Raidleiter nur aus der eigenen Gilde: sonst könnte der Leiter eines fremden Raids eine falsche
    -- Council-Liste setzen, und der echte Council käme danach nicht mehr durch
    local m = self:FindExact(self:GetGroupMembers(), sender)
    if m and (m.rank or 0) >= 2 and self:IsGuildMember(sender) then return true end
    if IsInGuild() and GetGuildRosterInfo and GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name then
                if self:SameName(name, sender) then return (rankIndex or 99) <= 1 end
            end
        end
    end
    return false
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

-- Nachrangig an alle (Abgleich): blockiert keine Abstimmungen und Würfelrunden
function LC:ResSendLow(...)
    local msg = strjoin(SEP, ...)
    if IsInGuild() then self:SendLow(msg, "GUILD") end
    if IsInRaid() then self:SendLow(msg, "RAID")
    elseif IsInGroup() then self:SendLow(msg, "PARTY") end
end

local function Changed()
    LC:RebuildReservers()
    LC:RefreshUI()
end

------------------------------------------------------------------------
-- Raider: reservieren und Änderung beantragen
------------------------------------------------------------------------
function LC:SubmitReservation(raid, items)
    if self:IsResClosed(raid) then return false, L("Die Reservierungen für %s sind geschlossen.", self:RaidDisplayName(raid)) end
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
    if self:IsResClosed(raid) then return false, L("Die Reservierungen für %s sind geschlossen.", self:RaidDisplayName(raid)) end
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
    -- Die eigene gesperrte Reservierung ändert ein anderes Council-Mitglied (wie bei Änderungsanträgen)
    if p and (p.rev or 0) > 0 and self:IsMe(p.name) then
        return false, L["Deine gesperrte Reservierung ändert ein anderes Council-Mitglied – stell einen Änderungsantrag."]
    end
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
        result = L("Vom Council (%s) eingetragen: %s (vorher: %s)", self:PlayerName(), self:ItemListText(items), self:ItemListText(old)),
    })
    Changed()
    return true, L["Reservierung für "] .. p.name .. L[" eingetragen."]
end

function LC:NewReserveRound(raid)
    if not self:AmICouncil() then return false, L["Nur der Council kann eine neue Runde starten."] end
    local R = self:ResRaid(raid)
    R.epoch = (R.epoch or 0) + 1
    wipe(R.players)
    R.close = nil   -- neue Runde: wieder offen
    self:ScheduleResClose(raid)
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
            self:ResSendLow("YR", raid, tostring(R.epoch), "0", ItemsString(rec.items))
        end
    end
end

-- Antwort auf einen Abgleich: Council-Liste, alle Einträge und offene Anträge
-- (nachrangig: ein Abgleich hat viele Nachrichten und darf Stimmen nicht ausbremsen)
function LC:SendResSync(target)
    local function Out(...)
        if target then self:SendLow(strjoin(SEP, ...), "WHISPER", target) else self:ResSendLow(...) end
    end
    local names = {}
    for _, n in ipairs(self:GetCouncilList()) do names[#names + 1] = self:CleanText(n, 40) end
    local days = {}
    for _, d in ipairs(self.db.config.raidDays or {}) do days[#days + 1] = tostring(d) end
    Out("YL", table.concat(names, ";"), tostring(self:MaxReserves()), table.concat(days, ","), self.db.config.reminderRaid or "",
        self.db.config.setReserve and "1" or "0", tostring(self.db.config.raidDaysTime or 0))
    for raid, R in pairs(self.db.reserves or {}) do
        if R.close then
            Out("YZ", raid, tostring(R.epoch), R.close.state, tostring(R.close.at or 0), self:CleanText(R.close.by or "", 40))
        end
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
        R.close = nil
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
        for n in (p[2] or ""):gmatch("[^;]+") do
            n = self:CleanText(n, 40)
            if n ~= "" then list[#list + 1] = n end
        end
        -- Erste Liste nur von Raidleitung/Gildenleitung, danach nur Änderungen vom bekannten Council
        local trusted
        if #self:GetTrustedCouncil() == 0 then
            trusted = self:IsTrustedFirstSource(sender)
            if not trusted and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        else
            trusted = self:IsTrustedCouncil(sender)
        end
        if #list > 0 and trusted then
            self.db.knownCouncil = list
            self.db.knownMax = tonumber(p[3]) or self.db.knownMax
            -- Raidtage und Raid für die Erinnerung (ältere Versionen schicken das nicht mit)
            -- Raidtage, Erinnerungs-Raid und „aus dem Gear-Set“: die zuletzt eingestellte Fassung gewinnt.
            -- Sonst überschreibt ein Council-Mitglied, das nie Raidtage eingestellt hat, die der anderen.
            if p[4] then
                local t = tonumber(p[7])
                local newer
                if t then
                    local mine = self:CanSetRaidDays() and (self.db.config.raidDaysTime or 0) or (self.db.knownRaidDaysTime or -1)
                    newer = t > mine
                else
                    newer = (self.db.knownRaidDaysTime == nil) and not self:CanSetRaidDays()   -- ältere Version ohne Zeit
                end
                if newer then
                    local days = {}
                    for d in p[4]:gmatch("%d") do days[#days + 1] = tonumber(d) end
                    self.db.knownRaidDays = days
                    self.db.knownReminderRaid = p[5] or ""
                    self.db.knownRaidDaysTime = t
                    if p[6] then self.db.knownSetReserve = (p[6] == "1") end
                    if self:AmICouncil() and t then
                        self.db.config.raidDays = days
                        self.db.config.reminderRaid = p[5] or ""
                        if p[6] then self.db.config.setReserve = (p[6] == "1") end
                        self.db.config.raidDaysTime = t
                    end
                    C_Timer.After(3, function() LC:CheckRaidDayReminder() end)
                end
            end
            self:RefreshUI()
        end
        return
    end

    local raid = p[2]
    if not raid or raid == "" or #raid > 60 or raid:find("[|;]") then return end
    -- Neue Raid-Schlüssel nur in Grenzen anlegen (Schutz vor aufgeblähten SavedVariables)
    if not (self.db.reserves and self.db.reserves[raid]) then
        -- Raider: nur Raids, die es in einer Loot-Quelle gibt (ohne Quelle nicht prüfbar – dann nur die Grenze)
        if (cmd == "YR" or cmd == "YC") and self:IsKnownRaidKey(raid) == false then return end
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
        -- Reservierungen geschlossen: nichts mehr annehmen, dem Raider den Stand schicken
        if self:IsResClosed(raid) then
            local c = R.close or {}
            self:SendTo(sender, "YZ", raid, tostring(R.epoch), "closed", tostring(c.at or 0), self:CleanText(c.by or "", 40))
            local old = self:FindExact(R.players, sender)
            if old and (old.rev or 0) > 0 then
                self:SendTo(sender, "YA", raid, tostring(R.epoch), old.name, tostring(old.rev), ItemsString(old.items))
            end
            return
        end
        local items = ParseItems(cmd == "YR" and p[5] or p[4])
        while #items > self:MaxReserves() do table.remove(items) end
        local rec, key = self:FindExact(R.players, sender)
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

    -- Schließen/Erinnern: Council oder Raidleitung (eigene Vertrauensprüfung)
    if cmd == "YZ" or cmd == "YW" then return self:ResCloseHandle(cmd, p, sender, R, raid) end

    -- Ab hier nur Nachrichten des Councils
    if not self:IsTrustedCouncil(sender) then return end

    if cmd == "YX" then
        if (tonumber(p[3]) or 0) > (R.epoch or 0) then
            R.epoch = tonumber(p[3])
            wipe(R.players)
            R.close = nil
            self:ScheduleResClose(raid)
            Changed()
        end
        return
    end

    if not CheckEpoch(R, p[3]) then return end
    local name = self:CleanText(p[4] or "", 40)
    if name == "" then return end
    local rec, key = self:FindByName(R.players, name)

    if cmd == "YA" then
        local rev = tonumber(p[5]) or 0
        local items = ParseItems(p[6])
        -- Gleiche Revision, andere Items (zwei Council-Mitglieder gleichzeitig): fest entscheiden,
        -- damit alle Clients denselben Stand behalten – die „größere“ Itemliste gewinnt
        local accept = not rec or rev > (rec.rev or 0)
        if rec and rev == (rec.rev or 0) then
            accept = SameItems(rec.items, items) or ItemsString(items) > ItemsString(rec.items)
        end
        if accept then
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
        table.concat(days, ","), self.db.config.reminderRaid or "", self.db.config.setReserve and "1" or "0",
        tostring(self.db.config.raidDaysTime or 0))
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

-- Raidtage einstellen: Council – und solange noch gar kein Council bekannt ist (Einrichten durch die Leitung)
function LC:CanSetRaidDays()
    return self:AmICouncil() or #self:GetTrustedCouncil() == 0
end

-- Raidtage und Erinnerungs-Raid: wer sie einstellen darf, nimmt die eigene Einstellung, Raider die vom Council übermittelte
function LC:GetRaidDays()
    if self:CanSetRaidDays() then
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
    if self:AmICouncil() or self:HasOwnCouncilSetup() then return self.db.config.setReserve == true end
    return self.db.knownSetReserve == true
end

function LC:SetRaidDays(days, raidKey, setReserve)
    self.db.config.raidDays = days
    self.db.config.reminderRaid = raidKey or ""
    if setReserve ~= nil then self.db.config.setReserve = setReserve and true or false end
    self.db.config.raidDaysTime = GetServerTime()   -- die neueste Einstellung gewinnt beim Abgleich
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

------------------------------------------------------------------------
-- Reservierungen schließen (Council, Raidleiter oder Plündermeister)
--   R.close = { state = "timer" | "closed", at = Serverzeit (Schließzeitpunkt), by = Name }
--   Wer den Zeitplan gestellt hat, erinnert eine Minute vorher alle ohne Reservierung und schließt dann:
--   Ansage im Raid, Anwesenheit erfassen. Alle anderen werten nur die Uhrzeit aus.
------------------------------------------------------------------------
function LC:RaidDisplayName(raid)
    for _, r in ipairs(self:GetLootDB() or {}) do
        if r.key == raid then return r.name end
    end
    return (raid == "custom") and L["Raid (ohne Loot-Quelle)"] or raid
end

-- "open", "timer" (schließt um c.at) oder "closed"
function LC:ResCloseState(raid)
    local R = self.db.reserves and self.db.reserves[raid]
    local c = R and R.close
    if not c then return "open" end
    if c.state == "closed" or (c.state == "timer" and c.at and GetServerTime() >= c.at) then return "closed", c end
    if c.state == "timer" then return "timer", c end
    return "open"
end

function LC:IsResClosed(raid) return (self:ResCloseState(raid)) == "closed" end

-- Uhrzeit für Texte ("20:15")
function LC:ClockText(t) return date("%H:%M", t or GetServerTime()) end

-- Darf ich schließen? Council, Raidleiter, Plündermeister (genau die, denen die Empfänger glauben)
function LC:CanCloseReserves()
    if self:AmICouncil() then return true end
    if not IsInGroup() then return false end
    return (UnitIsGroupLeader("player") or self:IsMasterLooter()) and true or false
end

-- Wem das Schließen geglaubt wird: Council oder Raidleitung/Plündermeister aus der eigenen Gilde
local function TrustedCloser(sender)
    return LC:IsTrustedCouncil(sender) or (LC:IsTrustedLeader(sender) and LC:IsGuildMember(sender))
end
LC.TrustedCloser = TrustedCloser

-- Raidmitglieder (online) ohne Reservierung für diesen Raid
function LC:MissingReservers(raid)
    local R = self.db.reserves and self.db.reserves[raid]
    local out = {}
    if not IsInRaid() then return out end
    for _, m in pairs(self:GetGroupMembers()) do
        if m.online then
            local rec = R and self:FindByName(R.players, m.fullName or m.name)
            if not (rec and #(rec.items or {}) > 0) then out[#out + 1] = m end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- Alle im Raid ohne Reservierung erinnern: Ansage im Raid, Hinweisfenster (Addon) und Flüstern (ohne Addon)
function LC:WarnMissingReserves(raid)
    local missing = self:MissingReservers(raid)
    if #missing == 0 then return 0 end
    local state, c = self:ResCloseState(raid)
    local name = self:RaidDisplayName(raid)
    local when = (state == "timer" and c and c.at) and self:ClockText(c.at) or nil
    local head = when and L("Reservierungen für %s schließen um %s Uhr – noch nicht reserviert:", name, when)
        or L("Bitte für %s reservieren – noch nicht reserviert:", name)
    local names = {}
    for _, m in ipairs(missing) do names[#names + 1] = m.name end
    self:AnnounceList(head, names)
    local R = self:ResRaid(raid)
    for _, m in ipairs(missing) do
        if not self:IsMe(m.name) then
            local target = m.fullName or m.name
            -- Mit Addon: Hinweisfenster. Die Nachricht geht an alle (ohne Addon wird sie einfach nicht gelesen).
            self:SendTo(target, "YW", raid, tostring(R.epoch), tostring((c and c.at) or 0))
            local key = self:NameKey(m.name)
            if not (self.versions and self.versions[key]) then
                local text = when and L("[Light Council] Du hast für %s noch nichts reserviert – die Reservierungen schließen um %s Uhr. Reservieren: einem Council-Mitglied „!lc [Item]“ flüstern (Shift-Klick auf das Item).", name, when)
                    or L("[Light Council] Du hast für %s noch nichts reserviert. Reservieren: einem Council-Mitglied „!lc [Item]“ flüstern (Shift-Klick auf das Item).", name)
                pcall(SendChatMessage, text, "WHISPER", nil, target)
            end
        end
    end
    return #missing
end

local closeTimers = {}   -- [raid] = { warn = Timer, close = Timer, refresh = Timer }
local function CancelCloseTimers(raid)
    for _, t in pairs(closeTimers[raid] or {}) do t:Cancel() end
    closeTimers[raid] = nil
end

-- Zeitplan einrichten (nach Änderungen und beim Einloggen)
function LC:ScheduleResClose(raid)
    CancelCloseTimers(raid)
    local state, c = self:ResCloseState(raid)
    if state ~= "timer" then return end
    local left = c.at - GetServerTime()
    local t = {}
    if c.by and self:IsMe(c.by) then
        if left > 75 then
            t.warn = C_Timer.NewTimer(left - 60, function()
                if LC:ResCloseState(raid) == "timer" and IsInRaid() then LC:WarnMissingReserves(raid) end
            end)
        end
        t.close = C_Timer.NewTimer(left, function()
            if LC:ResCloseState(raid) ~= "open" then LC:CloseReservesNow(raid) end
        end)
    else
        t.refresh = C_Timer.NewTimer(left + 1, function() LC:RefreshUI() end)
    end
    closeTimers[raid] = t
end

-- Jetzt schließen: an alle senden, im Raid ansagen und die Anwesenheit erfassen
function LC:CloseReservesNow(raid)
    local R = self:ResRaid(raid)
    R.close = { state = "closed", at = GetServerTime(), by = self:PlayerName() }
    CancelCloseTimers(raid)
    self:ResSend("YZ", raid, tostring(R.epoch), "closed", tostring(R.close.at), self:CleanText(self:PlayerName(), 40))
    local name = self:RaidDisplayName(raid)
    local n = 0
    for _, p in pairs(R.players) do if #(p.items or {}) > 0 then n = n + 1 end end
    if IsInRaid() then
        self:Announce(L("Reservierungen für %s sind geschlossen (%d Spieler haben reserviert). Viel Erfolg!", name, n), false, true)
        local added = self:RecordAttendance(true)
        self:Print(L("Anwesenheit erfasst: %d Spieler neu für diese Woche.", added))
    end
    self:AddLog({ kind = "reserve", link = L["Reservierungen "] .. name,
        result = L("Geschlossen von %s (%d Spieler mit Reservierung).", self:PlayerName(), n) })
    Changed()
end

-- mode: "timer" (in minutes Minuten), "now", "open" (wieder öffnen), "remind" (nur erinnern)
function LC:SetResClose(raid, mode, minutes)
    if not raid then return false, L["Kein Raid gewählt."] end
    if not self:CanCloseReserves() then
        return false, L["Nur Council, Raidleiter und Plündermeister können die Reservierungen schließen."]
    end
    local name = self:RaidDisplayName(raid)
    if mode == "remind" then
        if not IsInRaid() then return false, L["Erinnern geht nur im Raid."] end
        local n = self:WarnMissingReserves(raid)
        return true, (n > 0) and L("%d Spieler ohne Reservierung erinnert.", n) or L["Alle im Raid haben reserviert."]
    end
    if mode == "now" then
        self:CloseReservesNow(raid)
        return true, L("Reservierungen für %s geschlossen.", name)
    end
    local R = self:ResRaid(raid)
    if mode == "open" then
        R.close = nil
        CancelCloseTimers(raid)
        self:ResSend("YZ", raid, tostring(R.epoch), "open", "0", "")
        if IsInRaid() then self:Announce(L("Reservierungen für %s sind wieder offen.", name)) end
        self:AddLog({ kind = "reserve", link = L["Reservierungen "] .. name, result = L("Wieder geöffnet von %s.", self:PlayerName()) })
        Changed()
        return true, L("Reservierungen für %s wieder geöffnet.", name)
    end
    minutes = math.max(1, math.min(120, math.floor(tonumber(minutes) or 10)))
    R.close = { state = "timer", at = GetServerTime() + minutes * 60, by = self:PlayerName() }
    self:ResSend("YZ", raid, tostring(R.epoch), "timer", tostring(R.close.at), self:CleanText(self:PlayerName(), 40))
    self:ScheduleResClose(raid)
    if IsInRaid() then
        self:Announce(L("Reservierungen für %s schließen in %d Min. (um %s Uhr).", name, minutes, self:ClockText(R.close.at)), false, true)
        self:WarnMissingReserves(raid)
    end
    Changed()
    return true, L("Reservierungen für %s schließen um %s Uhr.", name, self:ClockText(R.close.at))
end

-- Empfang: YZ (Zustand) und YW (Erinnerung an mich)
function LC:ResCloseHandle(cmd, p, sender, R, raid)
    if not TrustedCloser(sender) then return end
    -- Erinnerung: nur ein Hinweis, die Runde spielt keine Rolle
    if cmd == "YW" then
        if not self:HasReservedFor(raid) and self.ShowRaidDayReminder then
            local at = tonumber(p[4]) or 0
            self:ShowRaidDayReminder(raid, (at > GetServerTime()) and at or nil, true)
        end
        return
    end
    -- Andere Runde: eine neuere nur vom Council übernehmen (eine Raidleitung ohne Council-Sitz darf
    -- die Runde nie verändern, sonst könnte sie alle Reservierungen löschen)
    local epoch = tonumber(p[3]) or -1
    if epoch ~= (R.epoch or 0) then
        if epoch > (R.epoch or 0) and self:IsTrustedCouncil(sender) then CheckEpoch(R, epoch) else return end
    end
    local state, at = p[4], tonumber(p[5]) or 0
    local wasClosed = R.close and R.close.state == "closed"
    if state == "open" then
        R.close = nil
    elseif state == "timer" or state == "closed" then
        local by = self:CleanText(p[6] or "", 40)
        R.close = { state = state, at = at, by = (by ~= "") and by or self:ShortName(sender) }
    else
        return
    end
    -- Gerade geschlossen (nicht aus einem späteren Abgleich): auch der Council erfasst die Anwesenheit –
    -- sonst fehlte sie, wenn eine Raidleitung ohne Council-Sitz schließt
    if state == "closed" and not wasClosed and self:AmICouncil() and IsInRaid() and math.abs(GetServerTime() - at) < 600 then
        self:RecordAttendance(true)
    end
    self:ScheduleResClose(raid)
    Changed()
end

LC:On("PLAYER_LOGIN", function(self)
    C_Timer.After(5, function()
        for raid, R in pairs(LC.db.reserves or {}) do
            local c = R.close
            -- Eigener Zeitplan ist abgelaufen, während ich offline war bzw. neu geladen habe: jetzt nachholen
            if c and c.state == "timer" and c.by and LC:IsMe(c.by) and c.at and GetServerTime() >= c.at
                and GetServerTime() - c.at < 1800 and IsInRaid() then
                LC:CloseReservesNow(raid)
            else
                LC:ScheduleResClose(raid)
            end
        end
    end)
end)
