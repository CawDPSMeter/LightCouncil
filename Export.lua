-- Light Council – JSON-Export aller Daten (für eine spätere Website oder eigene Auswertungen)
--
-- Zwei Wege:
--   * /lc json oder Loot-Historie → Exportieren → „JSON“: Text markiert, Strg+C kopiert
--   * Beim Ausloggen / /reload schreibt das Addon den JSON-Text zusätzlich in die
--     SavedVariables (LightCouncilExport.json) – ein Upload-Programm kann ihn dort abholen.
--     Abschalten mit /lc json auto.
--
-- Schema (schema = 1), alle Zeiten als Unix-Zeitstempel (Sekunden, Serverzeit):
--   format, schema, addonVersion, exported, exportedBy, guild, council[], settings{},
--   history[], historyDeleted[], attendance[], sitouts[], players[], councilItems[], prio[],
--   reserves[], gearSets{ mine[], others[] }, log[]
local _, LC = ...
local L = LC.L

local SCHEMA = 1

------------------------------------------------------------------------
-- JSON-Encoder (Lua 5.1)
------------------------------------------------------------------------
local ARRAY = {}   -- Markierung: Tabelle immer als Liste ausgeben (auch leer)
local function Arr(t) return setmetatable(t or {}, ARRAY) end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function EscapeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function IsArray(t)
    if getmetatable(t) == ARRAY then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n > 0 and n == #t
end

local Encode
local function EncodeValue(v, out, depth)
    local tv = type(v)
    if tv == "string" then
        out[#out + 1] = EscapeString(v)
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = "null"
        elseif v % 1 == 0 and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = string.format("%.0f", v)   -- nicht %d: unter Windows nur 32 Bit
        else
            out[#out + 1] = string.format("%.14g", v)
        end
    elseif tv == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif tv == "table" then
        Encode(v, out, depth + 1)
    else
        out[#out + 1] = "null"
    end
end

function Encode(t, out, depth)
    if depth > 20 then out[#out + 1] = "null" return end
    if IsArray(t) then
        out[#out + 1] = "["
        for i = 1, #t do
            if i > 1 then out[#out + 1] = "," end
            EncodeValue(t[i], out, depth)
        end
        out[#out + 1] = "]"
        return
    end
    -- Schlüssel sortiert, damit der Export stabil ist (gut für Vergleiche / Git)
    local keys = {}
    for k, v in pairs(t) do
        local tk = type(k)
        if (tk == "string" or tk == "number") and type(v) ~= "function" then keys[#keys + 1] = tostring(k) end
    end
    table.sort(keys)
    out[#out + 1] = "{"
    for i, k in ipairs(keys) do
        local v = t[k]
        if v == nil then v = t[tonumber(k)] end
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = EscapeString(k)
        out[#out + 1] = ":"
        EncodeValue(v, out, depth)
    end
    out[#out + 1] = "}"
end

function LC:ToJSON(value)
    local out = {}
    EncodeValue(value, out, 0)
    return table.concat(out)
end

------------------------------------------------------------------------
-- Daten zusammenstellen
------------------------------------------------------------------------
local function ItemName(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = id and getInfo(id)
    return name
end

-- WoW-Steuercodes entfernen (Farben, Item-Links, Texturen) – eine Website bekommt reinen Text
local function Plain(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("||", "\1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|n", " "):gsub("\1", "|")
    return text
end

local function HowKey(e)
    if e.council then return "council" end
    if e.reserved then return "reserved" end
    return e.offspec and "offspec" or "mainspec"
end

local function SortedNames(map)
    local list = Arr()
    for _, name in pairs(map or {}) do
        if type(name) == "string" then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end

local function IdList(t)
    local list = Arr()
    for _, id in ipairs(t or {}) do
        if tonumber(id) then list[#list + 1] = tonumber(id) end
    end
    return list
end

local function BuildHistory(db)
    local list = Arr()
    for _, e in ipairs(db.history or {}) do
        list[#list + 1] = {
            id = e.id, time = e.time, week = e.week, raid = e.raid,
            itemID = e.itemID, item = ItemName(e.itemID),
            winner = e.winner, how = HowKey(e), roll = e.roll,
        }
    end
    local deleted = Arr()
    for id, t in pairs(db.historyDeleted or {}) do deleted[#deleted + 1] = { id = id, time = t } end
    table.sort(deleted, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return list, deleted
end

local function BuildAttendance(db)
    local list = Arr()
    for week, names in pairs(db.attendance or {}) do
        if tonumber(week) then
            list[#list + 1] = { week = tonumber(week), players = SortedNames(names) }
        end
    end
    table.sort(list, function(a, b) return a.week < b.week end)
    local sitouts = Arr()
    for week, items in pairs(db.sitouts or {}) do
        for itemID, names in pairs(items) do
            sitouts[#sitouts + 1] = { week = tonumber(week), itemID = tonumber(itemID), item = ItemName(itemID), players = SortedNames(names) }
        end
    end
    table.sort(sitouts, function(a, b)
        if a.week ~= b.week then return (a.week or 0) < (b.week or 0) end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
    return list, sitouts
end

-- Parse und Engagement sind vertraulich: nur im Export eines Council-Mitglieds
local function BuildPlayers(db, isCouncil)
    local list = Arr()
    for _, p in pairs(db.players or {}) do
        local wins = Arr()
        for _, w in ipairs(p.wins or {}) do
            wins[#wins + 1] = { week = w.week, itemID = w.itemID, item = ItemName(w.itemID), time = w.time }
        end
        list[#list + 1] = {
            name = p.name, wins = wins,
            parse = isCouncil and p.parse or nil,
            engagement = isCouncil and p.engagement or nil,
        }
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

local function BuildItems(db)
    local council = Arr()
    for id, on in pairs(db.councilItems or {}) do
        if on and tonumber(id) then council[#council + 1] = tonumber(id) end
    end
    table.sort(council)
    local prio = Arr()
    for id, names in pairs(db.prio or {}) do
        if tonumber(id) and type(names) == "table" then
            local p = Arr()
            for _, n in ipairs(names) do p[#p + 1] = n end
            prio[#prio + 1] = { itemID = tonumber(id), item = ItemName(id), players = p }
        end
    end
    table.sort(prio, function(a, b) return a.itemID < b.itemID end)
    return council, prio
end

local function BuildReserves(db)
    local list = Arr()
    for raid, r in pairs(db.reserves or {}) do
        local players = Arr()
        for _, p in pairs(r.players or {}) do
            local entry = { name = p.name, items = IdList(p.items), locked = (p.rev or 0) > 0, time = p.time }
            if p.pending then
                entry.pending = { items = IdList(p.pending.items), reason = Plain(p.pending.reason), time = p.pending.time }
            end
            players[#players + 1] = entry
        end
        table.sort(players, function(a, b) return tostring(a.name) < tostring(b.name) end)
        list[#list + 1] = { raid = raid, round = r.epoch, players = players }
    end
    table.sort(list, function(a, b) return tostring(a.raid) < tostring(b.raid) end)
    return list
end

local function BuildGearSets(db)
    local mine = Arr()
    for char, g in pairs(db.gearSets or {}) do
        local sets = Arr()
        for _, name in ipairs(g.order or {}) do
            local s = g.sets and g.sets[name]
            if s then sets[#sets + 1] = { name = name, active = (g.active == name), items = IdList(s.items) } end
        end
        mine[#mine + 1] = { character = char, sets = sets }
    end
    table.sort(mine, function(a, b) return tostring(a.character) < tostring(b.character) end)
    local others = Arr()
    for _, o in pairs(db.otherSets or {}) do
        local items = Arr()
        for _, it in ipairs(o.items or {}) do
            items[#items + 1] = { itemID = it.id, have = it.have and true or false }
        end
        others[#others + 1] = { name = o.name, set = o.set, time = o.time, items = items }
    end
    table.sort(others, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return mine, others
end

-- Protokoll ohne Testläufe; Stimmen anonym (nur Entscheidung und Begründung, keine Namen)
local function BuildLog(db)
    local list = Arr()
    for _, e in ipairs(db.log or {}) do
        if not e.test then
            local votes
            if type(e.votes) == "table" then
                votes = Arr()
                for _, v in ipairs(e.votes) do
                    if type(v) == "table" then votes[#votes + 1] = { decision = v.decision, reason = Plain(v.reason) } end
                end
            end
            list[#list + 1] = {
                time = e.time, week = e.week, kind = e.kind or "loot", council = e.council and true or nil,
                itemID = e.itemID, item = ItemName(e.itemID), result = Plain(e.result), votes = votes,
            }
        end
    end
    return list
end

function LC:BuildExport()
    local db = self.db
    local cfg = db.config
    local isCouncil = self:AmICouncil()
    local history, deleted = BuildHistory(db)
    local attendance, sitouts = BuildAttendance(db)
    local councilItems, prio = BuildItems(db)
    local mine, others = BuildGearSets(db)
    local council = Arr()
    for _, n in ipairs(self:GetTrustedCouncil()) do council[#council + 1] = n end
    local raidDays = Arr()
    for _, d in ipairs(cfg.raidDays or {}) do raidDays[#raidDays + 1] = d end
    return {
        format = "LightCouncil", schema = SCHEMA, addonVersion = self.version,
        exported = GetServerTime(), exportedBy = self:PlayerName(),
        exportedByCouncil = isCouncil, guild = GetGuildInfo("player"),
        council = council,
        settings = {
            councilSize = cfg.councilSize, maxReserves = self:MaxReserves(), raidDays = raidDays,
            cooldownWeeks = cfg.cooldownWeeks, attendanceWeeks = cfg.attendanceWeeks,
            setReserve = self.SetReserveEnabled and self:SetReserveEnabled() or false,
        },
        history = history, historyDeleted = deleted,
        attendance = attendance, sitouts = sitouts,
        players = BuildPlayers(db, isCouncil),
        councilItems = councilItems, prio = prio,
        reserves = BuildReserves(db),
        gearSets = { mine = mine, others = others },
        log = isCouncil and BuildLog(db) or Arr(),
    }
end

function LC:ExportJSON()
    return self:ToJSON(self:BuildExport())
end

------------------------------------------------------------------------
-- Beim Ausloggen in die SavedVariables schreiben
------------------------------------------------------------------------
LC:On("PLAYER_LOGOUT", function(self)
    if self.db and self.db.config.jsonOnLogout ~= false then
        local ok, json = pcall(self.ExportJSON, self)
        if ok then
            LightCouncilExport = { schema = SCHEMA, time = GetServerTime(), json = json }
        end
    else
        LightCouncilExport = nil
    end
end)
