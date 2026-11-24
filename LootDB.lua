-- Light Council – Raid-Loot-Datenbank (Raids -> Bosse -> Items), nur Raids
--   AtlasLoot Forever : AtlasLoot.ItemDB.Storage["AtlasLootClassic_DungeonsAndRaids"]
--   Naowh Forever     : NaowhForever.Journal.Dungeons()  (mit Drop-Chancen, Raids haben "raid = 10/20/40")
-- Jeder wählt die Quelle selbst (Einstellung lootSource): "auto" = alle installierten zusammengeführt.
local _, LC = ...
local L = LC.L

local ATLAS_DATA = "AtlasLootClassic_DungeonsAndRaids"

local function IsLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function LoadOnDemand(name)
    if C_AddOns and C_AddOns.LoadAddOn then return C_AddOns.LoadAddOn(name) end
    return LoadAddOn(name)
end

local function CleanName(s)
    s = tostring(s or "?")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return strtrim(s)
end

-- Gleiche Instanzen aus verschiedenen Quellen erkennen: "The Barrow Deeps" = "Barrow Deeps",
-- "Onyxia's Lair" = "Onyxias Lair", "Mount Hyjal" = "Hyjal Summit"
local ALIASES = {
    mounthyjal = "hyjalsummit",
    onyxia = "onyxiaslair",
    barrowdeepsraid = "barrowdeeps",
}
local function NormKey(name)
    local s = CleanName(name):lower()
    s = s:gsub("^the%s+", ""):gsub("[^%w]", "")
    return ALIASES[s] or s
end
local function NormBoss(name)
    return (CleanName(name):lower():gsub("^the%s+", ""):gsub("[^%w]", ""))
end

------------------------------------------------------------------------
-- Quellen
------------------------------------------------------------------------
LC.LOOT_SOURCES = {
    { key = "auto",  label = "Automatisch" },
    { key = "atlas", label = "AtlasLoot" },
    { key = "naowh", label = "Naowh Forever" },
}

function LC:LootSourceAvailable(key)
    if key == "auto" then return true end
    if key == "atlas" then return AtlasLoot ~= nil and AtlasLoot.ItemDB ~= nil end
    if key == "naowh" then
        local ns = _G.NaowhForever
        return ns ~= nil and ns.Journal ~= nil and type(ns.Journal.Dungeons) == "function"
    end
    return false
end

function LC:GetLootSource()
    local s = self.db.config.lootSource or "auto"
    if s ~= "auto" and not self:LootSourceAvailable(s) then return "auto" end
    return s
end

function LC:GetLootSourceLabel(key)
    for _, s in ipairs(self.LOOT_SOURCES) do
        if s.key == key then return L[s.label] end
    end
    return key
end

function LC:SetLootSource(key)
    self.db.config.lootSource = key
    self.lootCache = nil
    self:RefreshUI()
end

-- Nächste installierte Quelle (für den Umschalt-Knopf)
function LC:CycleLootSource()
    local list, cur = self.LOOT_SOURCES, self:GetLootSource()
    local idx = 1
    for i, s in ipairs(list) do if s.key == cur then idx = i end end
    for step = 1, #list do
        local s = list[(idx - 1 + step) % #list + 1]
        if self:LootSourceAvailable(s.key) then
            self:SetLootSource(s.key)
            return
        end
    end
end

------------------------------------------------------------------------
-- Sammeln: jede Quelle liefert Instanzen in einheitlicher Form
--   { name, forever, bosses = { { name, items = { id, … }, chance = { [id] = % } } } }  – nur Raids
------------------------------------------------------------------------
local function ReadAtlas(out)
    if not (AtlasLoot and AtlasLoot.ItemDB and AtlasLoot.ItemDB.Storage) then return end
    if not IsLoaded(ATLAS_DATA) then
        local ok = LoadOnDemand(ATLAS_DATA)
        if not ok then return end
    end
    local storage = AtlasLoot.ItemDB.Storage[ATLAS_DATA]
    if not storage then return end
    local ctypes = (storage.GetContentTypes and storage:GetContentTypes()) or {}
    for key, inst in pairs(storage) do
        if type(key) == "string" and key ~= "__atlaslootdata" and type(inst) == "table" and type(inst.items) == "table" and inst.ContentType then
            local ctName = ((ctypes[inst.ContentType] or {})[1] or ""):lower()
            local isDungeon = ctName:find("dungeon") or ctName:find("instanz")
            local isRaid = not isDungeon and (ctName:find("raid") or ctName:find("schlacht") or ctName:find("%d%d"))
            if isRaid then
                -- Schlüssel sprachunabhängig: englischer Name aus den Daten bzw. der Tabellenschlüssel ("MoltenCore").
                -- (Bis 0.19.0 kam er aus dem übersetzten Namen – dann landeten Reservierungen aus Clients
                -- verschiedener Sprachen unter getrennten Raids, kyrillische Namen sogar unter "".)
                local keyName = (type(inst.name) == "string" and inst.name ~= "") and inst.name or nil
                if not keyName then
                    keyName = key:gsub("(%l)(%u)", "%1 %2")
                    keyName = keyName:gsub("(%l)of ", "%1 of "):gsub(" Ahn Qiraj", " Ahn'Qiraj")
                end
                -- Anzeige in der Sprache des Clients
                local display
                if type(inst.GetName) == "function" then
                    local ok, n = pcall(inst.GetName, inst, true)
                    if ok and type(n) == "string" and n ~= "" and n ~= key then display = n end
                end
                local entry = { name = CleanName(keyName), display = CleanName(display or keyName),
                    instanceID = tonumber(inst.InstanceID),
                    forever = ctName:find("forever") ~= nil, bosses = {} }
                for _, boss in ipairs(inst.items) do
                    if type(boss) == "table" then
                        local items, seen = {}, {}
                        for dk, dv in pairs(boss) do
                            if type(dk) == "number" and type(dv) == "table" then
                                for _, e in ipairs(dv) do
                                    local id = type(e) == "table" and e[2]
                                    if type(id) == "number" and id > 0 and not seen[id] then
                                        seen[id] = true
                                        items[#items + 1] = id
                                    end
                                end
                            end
                        end
                        entry.bosses[#entry.bosses + 1] = { name = CleanName(boss.name), items = items, chance = {} }
                    end
                end
                if #entry.bosses > 0 then out[#out + 1] = entry end
            end
        end
    end
end

local function ReadNaowh(out)
    local ns = _G.NaowhForever
    if not (ns and ns.Journal and type(ns.Journal.Dungeons) == "function") then return end
    local ok, list = pcall(ns.Journal.Dungeons)
    if not ok or type(list) ~= "table" then return end
    for _, d in ipairs(list) do
        if type(d) == "table" and d.raid and type(d.wings) == "table" then
            local entry = { name = CleanName(d.english or d.name or d.key), display = CleanName(d.name or d.key),
                forever = d.new == true, bosses = {} }
            for _, wing in ipairs(d.wings) do
                for _, boss in ipairs(wing.bosses or {}) do
                    if type(boss) == "table" and not boss.trash then
                        local items, chance = {}, {}
                        for i, id in ipairs(boss.loot or {}) do
                            if type(id) == "number" and id > 0 then
                                items[#items + 1] = id
                                local c = boss.chance and boss.chance[i]
                                if type(c) == "number" and c > 0 then chance[id] = c end
                            end
                        end
                        entry.bosses[#entry.bosses + 1] = { name = CleanName(boss.name), items = items, chance = chance }
                    end
                end
            end
            if #entry.bosses > 0 then out[#out + 1] = entry end
        end
    end
end

------------------------------------------------------------------------
-- Zusammenführen
------------------------------------------------------------------------
local function Merge(lists)
    local byKey, order = {}, {}
    for _, src in ipairs(lists) do
        for _, inst in ipairs(src.entries) do
            local key = NormKey(inst.name)
            local m = byKey[key]
            if not m then
                m = { key = key, name = inst.display or inst.name, forever = inst.forever,
                    bosses = {}, bossIndex = {}, sources = {}, itemCount = 0, alt = {} }
                byKey[key] = m
                order[#order + 1] = m
            end
            m.sources[src.key] = true
            -- Weitere Schlüssel zum Wiedererkennen: übersetzter Name (aktueller Raid, alte Reservierungen) und Instanz-ID
            local alt = NormKey(inst.display or inst.name)
            if alt ~= "" and alt ~= key then m.alt[alt] = true end
            if inst.instanceID then m.instanceID = inst.instanceID end
            if inst.forever then m.forever = true end
            for _, boss in ipairs(inst.bosses) do
                local bk = NormBoss(boss.name)
                local mb = m.bossIndex[bk]
                if not mb then
                    mb = { name = boss.name, items = {}, chance = {}, seen = {} }
                    m.bossIndex[bk] = mb
                    m.bosses[#m.bosses + 1] = mb
                end
                for _, id in ipairs(boss.items) do
                    if not mb.seen[id] then
                        mb.seen[id] = true
                        mb.items[#mb.items + 1] = id
                        m.itemCount = m.itemCount + 1
                    end
                    if boss.chance[id] then mb.chance[id] = boss.chance[id] end
                end
            end
        end
    end
    table.sort(order, function(a, b)
        if a.forever ~= b.forever then return a.forever end
        return a.name < b.name
    end)
    return order
end

-- Alle Raids der gewählten Quelle(n)
-- Rückgabe: Liste oder nil + Fehlertext
function LC:GetLootDB()
    local source = self:GetLootSource()
    if not self.lootCache or self.lootCache.source ~= source then
        local readers = {
            { key = "naowh", fn = ReadNaowh },   -- zuerst: liefert Drop-Chancen und lokalisierte Namen
            { key = "atlas", fn = ReadAtlas },
        }
        local lists = {}
        for _, r in ipairs(readers) do
            if (source == "auto" or source == r.key) and self:LootSourceAvailable(r.key) then
                local entries = {}
                local ok = pcall(r.fn, entries)
                if ok then lists[#lists + 1] = { key = r.key, entries = entries } end
            end
        end
        self.lootCache = { source = source, all = Merge(lists) }
        self:MigrateRaidKeys(self.lootCache.all)
    end
    if #self.lootCache.all == 0 then
        return nil, L["Keine Loot-Quelle gefunden. Installiere AtlasLoot Forever oder Naowh Forever."]
    end
    return self.lootCache.all
end

-- Raid, in dem ich gerade bin (Eintrag aus der Loot-Datenbank) oder nil
function LC:GetCurrentRaid()
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "raid" or not name or name == "" then return nil end
    local key = NormKey(name)
    for _, r in ipairs(self:GetLootDB() or {}) do
        if (instanceID and r.instanceID == instanceID)
            or (key ~= "" and (r.key == key or NormKey(r.name) == key or (r.alt and r.alt[key]))) then
            return r
        end
    end
    return nil
end

-- Beim Betreten eines Raids: Hinweis, falls ich dort noch nichts reserviert habe
local reminded = {}
LC:On("PLAYER_ENTERING_WORLD", function(self)
    C_Timer.After(6, function()
        local raid = LC:GetCurrentRaid()
        if not raid or reminded[raid.key] then return end
        reminded[raid.key] = true
        local rec = LC:GetReservation(raid.key)
        if not rec or #(rec.items or {}) == 0 then
            LC:Print(L["Du hast für |cffb48cff"] .. raid.name .. L["|r noch nichts reserviert. "]
                .. L["Tippe |cffb48cff/lc|r – die Auswahl öffnet sich direkt für diesen Raid."])
        end
    end)
end)

-- Drop-Chance eines Items in einem Boss (Naowh), sonst nil
function LC:GetDropChance(boss, itemID)
    return boss and boss.chance and boss.chance[itemID]
end

------------------------------------------------------------------------
-- Itemsuche (Name oder Item-ID) über alle Raids der Loot-Quelle
------------------------------------------------------------------------
-- Kleinschreibung auch für Umlaute/Akzente (Latin-1) und Kyrillisch, damit „Ä“ = „ä“ und „Щ“ = „щ“
local function Lower(s)
    s = s:lower()
    s = s:gsub("\195([\128-\158])", function(c)
        local b = c:byte()
        if b ~= 151 then return "\195" .. string.char(b + 32) end   -- 151 = × bleibt
    end)
    s = s:gsub("\208\129", "\209\145")                                -- Ё → ё
    s = s:gsub("\208([\144-\175])", function(c)
        local b = c:byte()
        if b < 160 then return "\208" .. string.char(b + 32) end      -- А–П → а–п
        return "\209" .. string.char(b - 32)                          -- Р–Я → р–я
    end)
    return s
end
LC.LowerText = Lower

local nameCache = {}    -- [itemID] = Name in Kleinbuchstaben
local requested = {}    -- Itemdaten schon beim Server angefragt

local function SearchName(id)
    local n = nameCache[id]
    if n then return n end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = getInfo(id)
    if name then
        n = Lower(name)
        nameCache[id] = n
        return n
    end
    if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

-- Alle Items der Quelle (je Item der erste Fundort): { id, raidKey, raidName, boss, bossIdx, raidIdx }
local function AllItems()
    local raids = LC:GetLootDB()
    local cache = LC.lootCache
    if cache and cache.searchList and cache.searchFor == raids then return cache.searchList end
    local list, seen = {}, {}
    for ri, r in ipairs(raids or {}) do
        for bi, b in ipairs(r.bosses or {}) do
            for _, id in ipairs(b.items or {}) do
                if not seen[id] then
                    seen[id] = true
                    list[#list + 1] = { id = id, raidKey = r.key, raidName = r.name, boss = b.name, raidIdx = ri, bossIdx = bi }
                end
            end
        end
    end
    if cache then cache.searchList, cache.searchFor = list, raids end
    return list
end

-- Namen aller Items vorab anfragen, damit die Suche nach Namen sofort alles findet
function LC:WarmItemNames()
    for _, e in ipairs(AllItems()) do SearchName(e.id) end
end

-- Treffer (höchstens max): exakte ID, dann Namensanfang, dann Rest – jeweils alphabetisch.
-- Rückgabe: Liste, Anzahl aller Treffer, Anzahl Items ohne geladenen Namen
function LC:SearchItems(query, max)
    query = strtrim(query or "")
    max = max or 8
    local out = {}
    if query == "" then return out, 0, 0 end
    local numeric = query:match("^%d+$")
    local q = Lower(query)
    local exact, starts, inside, waiting = {}, {}, {}, 0
    for _, e in ipairs(AllItems()) do
        local name = SearchName(e.id)
        if not name then waiting = waiting + 1 end
        if numeric then
            local s = tostring(e.id)
            if s == query then exact[#exact + 1] = e
            elseif s:sub(1, #query) == query then starts[#starts + 1] = e end
        elseif name then
            local pos = name:find(q, 1, true)
            if pos == 1 then starts[#starts + 1] = e
            elseif pos then inside[#inside + 1] = e end
        end
    end
    -- Eingetippte ID, die in keiner Loot-Quelle steht (z. B. Quest- oder Welt-Item)
    if numeric and #exact == 0 and #query >= 3 then
        local id = tonumber(query)
        local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        if instant and instant(id) then exact[1] = { id = id } end
    end
    local function ByName(a, b)
        local na, nb = nameCache[a.id], nameCache[b.id]
        if na and nb and na ~= nb then return na < nb end
        if (na ~= nil) ~= (nb ~= nil) then return na ~= nil end
        return a.id < b.id
    end
    table.sort(starts, ByName)
    table.sort(inside, ByName)
    local total = #exact + #starts + #inside
    for _, group in ipairs({ exact, starts, inside }) do
        for _, e in ipairs(group) do
            if #out >= max then return out, total, waiting end
            out[#out + 1] = e
        end
    end
    return out, total, waiting
end

------------------------------------------------------------------------
-- Reservierungen unter alten, übersetzten Raid-Schlüsseln (bis 0.19.0) auf den neuen Schlüssel umziehen
------------------------------------------------------------------------
function LC:MigrateRaidKeys(raids)
    local reserves = self.db and self.db.reserves
    if not reserves or not raids then return end
    local known, byAlt = {}, {}
    for _, r in ipairs(raids) do
        known[r.key] = true
        for alt in pairs(r.alt or {}) do byAlt[alt] = r.key end
    end
    local moves = {}
    for oldKey in pairs(reserves) do
        local newKey = not known[oldKey] and byAlt[oldKey]
        if newKey then moves[oldKey] = newKey end
    end
    local moved = false
    for oldKey, newKey in pairs(moves) do
        if not reserves[newKey] then
            reserves[newKey] = reserves[oldKey]
            reserves[oldKey] = nil
            if self.db.config.reminderRaid == oldKey then self.db.config.reminderRaid = newKey end
            moved = true
        end
    end
    if moved and self.RebuildReservers then self:RebuildReservers() end
end

------------------------------------------------------------------------
-- Gibt es diesen Raid-Schlüssel in einer installierten Loot-Quelle? (unabhängig von der gewählten Quelle)
-- true/false – oder nil, wenn keine Quelle installiert ist und sich das nicht prüfen lässt.
-- Der Council nimmt Reservierungen nur für bekannte Raids an: sonst könnte jemand mit erfundenen
-- Raid-Namen die Grenze von 40 Raids füllen, und für neue Raids ginge nichts mehr.
------------------------------------------------------------------------
local knownKeys, knownChecked
function LC:IsKnownRaidKey(key)
    if key == "custom" then return true end
    if not knownChecked then
        knownChecked = true
        local lists = {}
        for _, r in ipairs({ { key = "naowh", fn = ReadNaowh }, { key = "atlas", fn = ReadAtlas } }) do
            if self:LootSourceAvailable(r.key) then
                local entries = {}
                if pcall(r.fn, entries) then lists[#lists + 1] = { key = r.key, entries = entries } end
            end
        end
        local keys = {}
        for _, m in ipairs(Merge(lists)) do keys[m.key] = true end
        knownKeys = next(keys) and keys or nil
    end
    if not knownKeys then return nil end
    return knownKeys[key] == true
end
