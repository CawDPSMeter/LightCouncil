-- Light Council – Daten: Council-Items, Score, Anwesenheit, Cooldowns, Protokoll, Loot-Historie
local _, LC = ...
local L = LC.L

------------------------------------------------------------------------
-- Council-Items
------------------------------------------------------------------------
-- Fügt Council-Items hinzu (Text mit Item-IDs und/oder Itemlinks), ohne vorhandene zu löschen
function LC:AddCouncilItems(text)
    text = text or ""
    local ids, added = {}, 0
    for id in text:gmatch("item:(%d+)") do ids[#ids + 1] = tonumber(id) end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h.-|h", ""):gsub("|r", "")
    for id in plain:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
    for _, id in ipairs(ids) do
        if id and id > 0 and not self.db.councilItems[id] then
            self.db.councilItems[id] = true
            self:ItemLink(id)
            added = added + 1
        end
    end
    if #ids == 0 then return false, L["Kein Item erkannt. Item-ID eintippen oder ein Item mit Shift-Klick einfügen."] end
    return true, (added == 1) and L["1 Council-Item hinzugefügt."] or (added .. L[" Council-Items hinzugefügt."])
end

function LC:SetCouncilItem(itemID, on)
    if not itemID then return end
    self.db.councilItems[itemID] = on and true or nil
    for _, e in pairs(self.itemState) do
        if e.itemID == itemID then e.isCouncil = on and true or false end
    end
    for _, e in ipairs(self.lootItems) do
        if e.itemID == itemID and not e.test then e.isCouncil = on and true or false end
    end
end

function LC:GetCouncilItemList()
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local list = {}
    for id in pairs(self.db.councilItems) do
        local name, _, quality = getInfo(id)
        list[#list + 1] = { id = id, name = name, quality = quality }
    end
    table.sort(list, function(a, b)
        if a.name and b.name then return a.name < b.name end
        if a.name or b.name then return a.name ~= nil end
        return a.id < b.id
    end)
    return list
end

function LC:GetReservers(itemID)
    return self.db.softres[itemID] or {}
end

function LC:IsCouncilItem(itemID)
    return itemID and self.db.councilItems[itemID] == true
end

------------------------------------------------------------------------
-- Spielerdaten
------------------------------------------------------------------------
function LC:GetPlayer(name, create)
    local key = self:NameKey(name)
    if not key then return nil end
    local p = self.db.players[key] or self:FindByName(self.db.players, name)
    if not p and create then
        p = { name = self:ShortName(name), wins = {} }
        self.db.players[key] = p
    end
    if p and not p.wins then p.wins = {} end
    return p
end

function LC:SetParse(name, value, broadcast)
    value = tonumber(value)
    if not value or value < 0 or value > 100 then return false, L["Parse muss zwischen 0 und 100 liegen."] end
    local p = self:GetPlayer(name, true)
    p.parse = math.floor(value + 0.5)
    if broadcast then self:BroadcastData("P", p.name, p.parse) end
    return true
end

function LC:SetEngagement(name, value, broadcast)
    value = tonumber(value)
    if not value or value < 1 or value > 5 then return false, L["Engagement muss zwischen 1 und 5 liegen."] end
    local p = self:GetPlayer(name, true)
    p.engagement = math.floor(value + 0.5)
    if broadcast then self:BroadcastData("E", p.name, p.engagement) end
    return true
end

------------------------------------------------------------------------
-- Anwesenheit
------------------------------------------------------------------------
-- Erfasst alle Online-Raidmitglieder für die aktuelle Woche.
function LC:RecordAttendance(force)
    if not IsInRaid() then return 0 end
    if not force then
        local _, instanceType = IsInInstance()
        -- Dungeons, die hier als Raid gelten (Obere Schwarzfelsspitze), zählen auch
        if instanceType ~= "raid" and not (instanceType == "party" and self:GetCurrentRaid()) then return 0 end
    end
    local week = self:CurrentWeek()
    self.db.attendance[week] = self.db.attendance[week] or {}
    local n, added = 0, {}
    for key, m in pairs(self:GetGroupMembers()) do
        if m.online then
            if not self.db.attendance[week][key] then
                n = n + 1
                added[#added + 1] = m.name
            end
            self.db.attendance[week][key] = m.name
        end
    end
    -- Neu erfasste Spieler mit dem restlichen Council abgleichen (Attendance.lua)
    if n > 0 and self.ShareAttendance then self:ShareAttendance(week, added) end
    return n
end

-- Anwesenheit in % über die letzten N Wochen (nur Wochen, in denen geraidet wurde)
function LC:GetAttendance(name)
    local weeks = math.min(self.db.config.attendanceWeeks or 8, 20)   -- wie der Abgleich (Attendance.lua)
    local current = self:CurrentWeek()
    local raided, present = 0, 0
    for w = current - weeks + 1, current do
        local list = self.db.attendance[w]
        if list and next(list) then
            raided = raided + 1
            if self:FindByName(list, name) then present = present + 1 end
        end
    end
    if raided == 0 then return nil end
    return math.floor(present / raided * 100 + 0.5)
end

------------------------------------------------------------------------
-- Score (0–100), nur für den Council sichtbar
------------------------------------------------------------------------
-- Fehlende Faktoren werden ausgelassen und die Gewichtung auf die vorhandenen verteilt.
function LC:GetScore(name)
    local w = self.db.config.weights
    local p = self:GetPlayer(name)
    local att = self:GetAttendance(name)
    local parse = p and p.parse
    local eng = p and p.engagement
    local sum, wsum = 0, 0
    if att then sum = sum + att * w.attendance; wsum = wsum + w.attendance end
    if parse then sum = sum + parse * w.parse; wsum = wsum + w.parse end
    if eng then sum = sum + ((eng - 1) / 4 * 100) * w.engagement; wsum = wsum + w.engagement end
    local score = (wsum > 0) and math.floor(sum / wsum + 0.5) or nil
    return score, att, parse, eng
end

------------------------------------------------------------------------
-- Loot-Cooldown und Aussetzen
------------------------------------------------------------------------
function LC:AddCouncilWin(name, itemID)
    local p = self:GetPlayer(name, true)
    table.insert(p.wins, { week = self:CurrentWeek(), itemID = itemID, time = time() })
end

-- Gibt true und die letzte gesperrte Woche zurück, wenn der Spieler im Loot-Cooldown ist
function LC:IsOnCooldown(name)
    local p = self:GetPlayer(name)
    local week = self:CurrentWeek()
    local cd = self.db.config.cooldownWeeks or 2
    -- 0 = kein Cooldown. Sonst gesperrt: die Gewinnwoche und die folgenden cd Wochen
    if cd <= 0 then return false end
    local untilWeek
    for _, win in ipairs(p and p.wins or {}) do
        if week >= win.week and week <= win.week + cd then
            untilWeek = math.max(untilWeek or 0, win.week + cd)
        end
    end
    -- Zusätzlich aus der Loot-Historie (wird mit dem Council abgeglichen): so gilt der Cooldown
    -- auch, wenn diesmal jemand anderes Plündermeister ist
    local h = self.db.history or {}
    for i = #h, 1, -1 do
        local e = h[i]
        local w = e.time and self:WeekOf(e.time) or e.week
        if w and w < week - cd then break end
        if e.council and w and week >= w and week <= w + cd and self:NamesMatch(e.winner, name) then
            untilWeek = math.max(untilWeek or 0, w + cd)
        end
    end
    return untilWeek ~= nil, untilWeek
end

-- week: nur beim Empfang aus dem Abgleich; sonst diese Woche und an Council + Raidleitung verteilen
-- (damit „Aussetzen“ auch gilt, wenn das Item bei einem anderen Plündermeister droppt)
function LC:AddSitout(name, itemID, week)
    local fromSync = week ~= nil
    week = week or self:CurrentWeek()
    local key = self:NameKey(name)
    if not key or not itemID then return end
    self.db.sitouts[week] = self.db.sitouts[week] or {}
    self.db.sitouts[week][itemID] = self.db.sitouts[week][itemID] or {}
    self.db.sitouts[week][itemID][key] = self:ShortName(name)
    if not fromSync then
        local msg = strjoin("~", "SO", tostring(week), tostring(itemID), self:CleanText(name, 40))
        for _, target in ipairs(self:GetPrivateTargets()) do self:Send(msg, "WHISPER", target) end
    end
end

function LC:IsSittingOut(name, itemID)
    local w = self.db.sitouts[self:CurrentWeek()]
    return w ~= nil and w[itemID] ~= nil and self:FindByName(w[itemID], name) ~= nil
end

------------------------------------------------------------------------
-- Protokoll
------------------------------------------------------------------------
local MAX_LOG = 500

function LC:AddLog(entry)
    entry.time = entry.time or time()
    entry.week = entry.week or self:CurrentWeek()
    table.insert(self.db.log, entry)
    while #self.db.log > MAX_LOG do table.remove(self.db.log, 1) end
    return entry
end

local DECISION_LABEL = {
    OPEN = "Freigeben",
    LIMIT = "Eingrenzen",
    SKIP = "Aussetzen",
}
LC.DECISION_LABEL = DECISION_LABEL

function LC:FormatLogEntry(e)
    local lines = {}
    local head = date("%d.%m. %H:%M", e.time) .. "  " .. (e.link or self:ItemLink(e.itemID))
    if e.test then head = head .. L[" |cff888888(Test)|r"] end
    lines[#lines + 1] = head
    lines[#lines + 1] = L["   Entscheidung: "] .. (e.result or "-")
    if e.votes and #e.votes > 0 then
        for _, v in ipairs(e.votes) do
            local s = "   - " .. v.name .. ": " .. L[DECISION_LABEL[v.decision] or v.decision]
            if v.names and #v.names > 0 then s = s .. " (" .. table.concat(v.names, ", ") .. ")" end
            if v.reason and v.reason ~= "" then s = s .. " – \"" .. v.reason .. "\"" end
            lines[#lines + 1] = s
        end
    end
    if e.recused and #e.recused > 0 then
        lines[#lines + 1] = L["   Befangen (nicht abgestimmt): "] .. table.concat(e.recused, ", ")
    end
    if e.excluded and #e.excluded > 0 then
        lines[#lines + 1] = L["   Automatisch ausgeschlossen: "] .. table.concat(e.excluded, ", ")
    end
    if e.rollers and #e.rollers > 0 then
        lines[#lines + 1] = L["   Würfeln: "] .. table.concat(e.rollers, ", ")
    end
    if e.kind ~= "reserve" then lines[#lines + 1] = L["   Gewinner: "] .. (e.winner or "-") end
    return table.concat(lines, "\n")
end

function LC:PrintLog(n)
    local log = self.db.log
    if #log == 0 then self:Print(L["Protokoll ist leer."]) return end
    self:Print(L["Letzte Entscheidungen:"])
    for i = #log, math.max(1, #log - (n or 10) + 1), -1 do
        for line in (self:FormatLogEntry(log[i]) .. "\n"):gmatch("(.-)\n") do print(line) end
    end
end

------------------------------------------------------------------------
-- Loot-Historie: wer hat wann welches Item bekommen (alle Addon-Nutzer im Raid)
------------------------------------------------------------------------
local MAX_HISTORY = 3000

-- Aktueller Raid (Instanzname), sonst die Zone
function LC:CurrentRaidName()
    local name, instanceType = GetInstanceInfo()
    if instanceType == "raid" and name and name ~= "" then return name end
    if instanceType == "party" then
        local r = self:GetCurrentRaid()
        if r then return r.name end
    end
    return (GetRealZoneText and GetRealZoneText()) or name or "?"
end

function LC:WasReserved(itemID, name, reservers)
    for _, r in ipairs(reservers or self:GetReservers(itemID)) do
        local n = type(r) == "table" and r.name or r
        if self:NamesMatch(n, name) then return true end
    end
    return false
end

-- e = { id, itemID, winner, roll, council, reserved }; doppelte ids werden ignoriert.
-- Die Liste bleibt nach Zeit sortiert (abgeglichene ältere Einträge landen an der richtigen Stelle).
-- quiet = true: keine Oberflächen-Aktualisierung (beim Abgleich vieler Einträge)
function LC:AddHistory(e, quiet)
    if not e or not e.itemID or not e.winner or e.winner == "" then return false end
    local h = self.db.history
    if e.id then
        -- Gelöschte Einträge nicht über den Abgleich wiederbeleben
        if self.db.historyDeleted and self.db.historyDeleted[e.id] then return false end
        for i = #h, 1, -1 do
            if h[i].id == e.id then return false end
        end
    end
    e.time = e.time or time()
    e.week = e.week or self:WeekOf(e.time)   -- aus der Zeit (abgeglichene Einträge kommen evtl. Wochen später)
    if not e.raid then
        e.raid = self:CurrentRaidName()
        local _, itype, _, _, _, _, _, iid = GetInstanceInfo()
        if itype and itype ~= "none" and iid then e.instID = iid end
    end
    e.winner = self:ShortName(e.winner)
    local pos = #h + 1
    while pos > 1 and (h[pos - 1].time or 0) > e.time do pos = pos - 1 end
    table.insert(h, pos, e)
    while #h > MAX_HISTORY do table.remove(h, 1) end
    self.historyVersion = (self.historyVersion or 0) + 1
    self:ItemLink(e.itemID)
    if not quiet then self:RefreshUI() end
    return true
end

-- Items eines Spielers (neueste zuerst); weeks = nur die letzten N Wochen (nil = alle)
-- Rückgabe: Liste, Anzahl Council-Items
function LC:GetPlayerLoot(name, weeks)
    local out, council = {}, 0
    local minWeek = weeks and (self:CurrentWeek() - weeks + 1)
    for i = #self.db.history, 1, -1 do
        local e = self.db.history[i]
        if (not minWeek or (e.week or 0) >= minWeek) and self:NamesMatch(e.winner, name) then
            out[#out + 1] = e
            if e.council then council = council + 1 end
        end
    end
    return out, council
end

-- Items eines Spielers in dieser Raid-ID: diese Woche, im Raid gleich im selben Raid
function LC:RaidLootCount(name)
    if not name then return 0 end
    local week = self:CurrentWeek()
    local raid, iid
    if IsInInstance() then
        raid = self:CurrentRaidName()
        iid = select(8, GetInstanceInfo())
    end
    local h, n = self.db.history or {}, 0
    for i = #h, 1, -1 do
        local e = h[i]
        local w = e.week or (e.time and self:WeekOf(e.time))
        if w and w < week then break end   -- Historie ist nach Zeit sortiert
        -- gleicher Raid: per Instanz-ID (sprachunabhängig), bei älteren Einträgen ohne ID per Name
        local same = not raid or ((e.instID and iid) and e.instID == iid) or (not (e.instID and iid) and e.raid == raid)
        if w == week and same and self:NamesMatch(e.winner, name) then n = n + 1 end
    end
    return n
end

-- "heute", "gestern", "vor 5 Tagen"
function LC:AgoText(t)
    local days = math.floor((time() - (t or 0)) / 86400)
    if days <= 0 then return L["heute"] end
    if days == 1 then return L["gestern"] end
    return L("vor %d Tagen", days)
end

-- Kurze Liste der letzten Items eines Spielers in einen Tooltip schreiben
function LC:AddLootTooltip(tooltip, name, max)
    local list = self:GetPlayerLoot(name)
    tooltip:AddLine(" ")
    if #list == 0 then
        tooltip:AddLine(L["Noch kein Item in der Loot-Historie."], 0.6, 0.6, 0.6)
        return
    end
    tooltip:AddLine(L["Zuletzt erhalten:"], 0.8, 0.7, 1)
    for i = 1, math.min(max or 6, #list) do
        local e = list[i]
        tooltip:AddDoubleLine(self:ItemLink(e.itemID) .. (e.council and L[" |cffb48cff(Council)|r"] or ""),
            self:AgoText(e.time), 1, 1, 1, 0.6, 0.6, 0.6)
    end
    if #list > (max or 6) then
        tooltip:AddLine(L["… insgesamt "] .. #list .. L[" Items"], 0.6, 0.6, 0.6)
    end
end

-- Löscht einen Eintrag. Mit Kennung wird das Löschen gemerkt und (als Council) an alle weitergegeben,
-- sonst käme der Eintrag beim nächsten Abgleich zurück.
function LC:DeleteHistory(entry, fromSync)
    local h = self.db.history
    for i = #h, 1, -1 do
        if h[i] == entry then table.remove(h, i) break end
    end
    self.historyVersion = (self.historyVersion or 0) + 1
    if entry and entry.id then
        self.db.historyDeleted = self.db.historyDeleted or {}
        self.db.historyDeleted[entry.id] = time()
        if not fromSync and self.ShareHistoryDelete then self:ShareHistoryDelete({ entry.id }) end
    end
    self:RefreshUI()
end

-- Löschen per Kennung (vom Abgleich); merkt sich die Kennung auch, wenn der Eintrag hier fehlt
function LC:DeleteHistoryById(id)
    if not id or id == "" then return false end
    self.db.historyDeleted = self.db.historyDeleted or {}
    local isNew = not self.db.historyDeleted[id]
    self.db.historyDeleted[id] = self.db.historyDeleted[id] or time()
    local h = self.db.history
    for i = #h, 1, -1 do
        if h[i].id == id then
            table.remove(h, i)
            self.historyVersion = (self.historyVersion or 0) + 1
            return true
        end
    end
    return isNew
end

-- Gefilterte Historie, neueste zuerst. filter = Text (Spieler, Item oder Raid)
function LC:GetHistory(filter)
    local out = {}
    filter = strtrim(filter or ""):lower()
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for i = #self.db.history, 1, -1 do
        local e = self.db.history[i]
        local ok = filter == ""
        if not ok then
            local itemName = getInfo(e.itemID) or ""
            ok = (e.winner or ""):lower():find(filter, 1, true)
                or itemName:lower():find(filter, 1, true)
                or (e.raid or ""):lower():find(filter, 1, true)
        end
        if ok then out[#out + 1] = e end
    end
    return out
end

-- Alle bekannten Spieler (für die Spielerliste)
function LC:GetKnownPlayers()
    local set = {}
    for key, p in pairs(self.db.players) do set[key] = p.name end
    for _, list in pairs(self.db.attendance) do
        for key, name in pairs(list) do set[key] = set[key] or name end
    end
    for _, list in pairs(self.db.softres) do
        for _, r in ipairs(list) do
            if not self:FindByName(set, r.name) then set[self:NameKey(r.name)] = r.name end
        end
    end
    for _, e in ipairs(self.db.history or {}) do
        if e.winner and not self:FindByName(set, e.winner) then set[self:NameKey(e.winner)] = e.winner end
    end
    local out = {}
    for _, name in pairs(set) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

------------------------------------------------------------------------
-- Anwesenheit automatisch bei Boss-Kills erfassen
------------------------------------------------------------------------
LC:On("ENCOUNTER_END", function(self, _, _, _, _, success)
    if success == 1 or success == true then self:RecordAttendance(false) end
end)
LC:On("BOSS_KILL", function(self)
    self:RecordAttendance(false)
end)
