-- Light Council – Gear-Sets: Raider stellen sich ein oder mehrere Sets zusammen
--
-- Ein Set hat feste Slots wie das Charakterfenster: ein Item pro Slot, bei Ringen und Schmuckstücken
-- zwei. Einzelne Items kann man als „wichtig“ markieren – das sieht der Council bei der Abstimmung.
-- Ob man ein Item schon hat, erkennt das Addon selbst (angelegt, Taschen, Bank). Das aktive Set wird an
-- alle Addon-Nutzer verteilt – so sieht jeder, wo ein Spieler im Gear steht.
--
-- Daten: set = { slots = { [Slot] = itemID }, important = { [itemID] = true }, upgrades = { [Slot] = itemID } }
--   upgrades: pro Slot eine zweite Wahl – nicht so gut wie das Item im Slot, aber besser als das jetzige.
--   Upgrades zählen nicht beim Fortschritt („4 von 10“) und können nicht als wichtig markiert werden.
--
-- Nachrichten:
--   GS~setname~id:h:w,…   alle -> Gilde/Raid (bzw. Whisper als Antwort): mein aktives Set
--                         (h = 1: habe ich, w = 1: wichtig; ältere Versionen schicken nur id:h)
--   GU~setname~id:h,…     direkt danach: die Upgrades des Sets (ältere Versionen ignorieren das)
--   GQ                    alle -> Gilde/Raid: bitte aktive Sets schicken
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { GS = true, GU = true, GQ = true }
local MAX_ITEMS = 24          -- Obergrenze beim Empfang (ein Set hat höchstens 17 Slots)
local MAX_UPGRADES = 24
local MAX_OTHERS = 300
local KEEP_OTHERS = 60 * 86400

------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------
-- Slots in Anzeige-Reihenfolge; group 1 = Rüstung, 2 = Schmuck, 3 = Waffen.
-- Beschriftung kommt lokalisiert vom Spiel (_G[global]).
local SLOTS = {
    { key = "HEAD",     group = 1, global = "INVTYPE_HEAD" },
    { key = "NECK",     group = 1, global = "INVTYPE_NECK" },
    { key = "SHOULDER", group = 1, global = "INVTYPE_SHOULDER" },
    { key = "BACK",     group = 1, global = "INVTYPE_CLOAK" },
    { key = "CHEST",    group = 1, global = "INVTYPE_CHEST" },
    { key = "WRIST",    group = 1, global = "INVTYPE_WRIST" },
    { key = "HANDS",    group = 1, global = "INVTYPE_HAND" },
    { key = "WAIST",    group = 1, global = "INVTYPE_WAIST" },
    { key = "LEGS",     group = 1, global = "INVTYPE_LEGS" },
    { key = "FEET",     group = 1, global = "INVTYPE_FEET" },
    { key = "FINGER1",  group = 2, global = "INVTYPE_FINGER", num = 1 },
    { key = "FINGER2",  group = 2, global = "INVTYPE_FINGER", num = 2 },
    { key = "TRINKET1", group = 2, global = "INVTYPE_TRINKET", num = 1 },
    { key = "TRINKET2", group = 2, global = "INVTYPE_TRINKET", num = 2 },
    { key = "MAINHAND", group = 3, global = "INVTYPE_WEAPONMAINHAND" },
    { key = "OFFHAND",  group = 3, global = "INVTYPE_WEAPONOFFHAND" },
    { key = "RANGED",   group = 3, global = "INVTYPE_RANGED" },
}
local SLOT_INDEX = {}
for i, s in ipairs(SLOTS) do SLOT_INDEX[s.key] = i end
LC.GEAR_SLOTS = SLOTS
LC.GEAR_GROUPS = { "RÜSTUNG", "SCHMUCK", "WAFFEN" }   -- deutsch, wird bei der Anzeige übersetzt

-- In welche Slots passt ein Item? (Einhandwaffen in Waffen- oder Schildhand)
local LOC_SLOTS = {
    INVTYPE_HEAD = { "HEAD" }, INVTYPE_NECK = { "NECK" }, INVTYPE_SHOULDER = { "SHOULDER" },
    INVTYPE_CLOAK = { "BACK" }, INVTYPE_CHEST = { "CHEST" }, INVTYPE_ROBE = { "CHEST" },
    INVTYPE_WRIST = { "WRIST" }, INVTYPE_HAND = { "HANDS" }, INVTYPE_WAIST = { "WAIST" },
    INVTYPE_LEGS = { "LEGS" }, INVTYPE_FEET = { "FEET" },
    INVTYPE_FINGER = { "FINGER1", "FINGER2" }, INVTYPE_TRINKET = { "TRINKET1", "TRINKET2" },
    INVTYPE_WEAPON = { "MAINHAND", "OFFHAND" }, INVTYPE_2HWEAPON = { "MAINHAND" },
    INVTYPE_WEAPONMAINHAND = { "MAINHAND" }, INVTYPE_WEAPONOFFHAND = { "OFFHAND" },
    INVTYPE_SHIELD = { "OFFHAND" }, INVTYPE_HOLDABLE = { "OFFHAND" },
    INVTYPE_RANGED = { "RANGED" }, INVTYPE_RANGEDRIGHT = { "RANGED" },
    INVTYPE_THROWN = { "RANGED" }, INVTYPE_RELIC = { "RANGED" },
}

local function EquipLoc(itemID)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if getInstant then
        local _, _, _, loc = getInstant(itemID)
        if loc and loc ~= "" then return loc end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local loc = select(9, getInfo(itemID))
    return loc
end

-- Beschriftung eines Set-Slots („Kopf“, „Finger 2“ …)
function LC:GearSlotLabel(key)
    local s = SLOTS[SLOT_INDEX[key] or 0]
    if not s then return key end
    local text = _G[s.global] or s.key
    if s.num then text = text .. " " .. s.num end
    return text
end

-- Slot-Name und Sortierposition eines Items (unbekannt: „Sonstiges“ / 99)
function LC:ItemSlot(itemID)
    local loc = EquipLoc(itemID)
    local slots = loc and LOC_SLOTS[loc]
    if not slots then return L["Sonstiges"], 99 end
    return _G[loc] or loc, SLOT_INDEX[slots[1]]
end

-- Kann das Item in ein Set? (Ausrüstung mit passendem Slot)
function LC:GearSlotsFor(itemID)
    local loc = itemID and EquipLoc(itemID)
    return loc and LOC_SLOTS[loc]
end


-- Habe ich das Item? (angelegt, Taschen oder Bank)
-- Gecacht: Tooltips fragen das sehr oft ab; der Cache wird bei Taschen-/Ausrüstungsänderungen geleert.
local haveCache = {}
function LC:HaveItem(itemID)
    if not itemID then return false end
    local c = haveCache[itemID]
    if c ~= nil then return c end
    local have = false
    for slot = 1, 19 do
        if GetInventoryItemID("player", slot) == itemID then have = true break end
    end
    if not have then
        local count = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(itemID, true) or GetItemCount(itemID, true)
        have = (count or 0) > 0
    end
    haveCache[itemID] = have
    return have
end

-- Laut Loot-Historie erhalten? (Gegenprobe zu den selbst gemeldeten „habe ich“-Angaben anderer)
local wonIndex, wonVersion = {}, -1
local function WonByHistory(name, itemID)
    if wonVersion ~= (LC.historyVersion or 0) then
        wonIndex, wonVersion = {}, LC.historyVersion or 0
        for _, e in ipairs(LC.db.history or {}) do
            local key = LC:NameKey(e.winner)
            if key and e.itemID then
                wonIndex[key] = wonIndex[key] or {}
                wonIndex[key][e.itemID] = true
            end
        end
    end
    local key = LC:NameKey(name)
    return key and wonIndex[key] and wonIndex[key][itemID] or false
end

-- Wo droppt das Item? (Raid und Boss aus der Loot-Quelle; gecacht)
local sourceIndex, sourceFor
function LC:ItemSource(itemID)
    local db = self:GetLootDB()
    if not db then return nil end
    if sourceFor ~= db then
        sourceIndex, sourceFor = {}, db
        for _, raid in ipairs(db) do
            for _, boss in ipairs(raid.bosses or {}) do
                for _, id in ipairs(boss.items or {}) do
                    sourceIndex[id] = sourceIndex[id] or { raid = raid, boss = boss }
                end
            end
        end
    end
    return sourceIndex[itemID]
end


------------------------------------------------------------------------
-- Eigene Sets (pro Charakter)
------------------------------------------------------------------------
-- Ein Item in einen passenden Slot legen: freier Slot zuerst, sonst einen ersetzen
-- (lieber ein nicht wichtiges Item). Rückgabe: Slot, ersetztes Item
local function Place(set, id)
    local cands = LC:GearSlotsFor(id)
    if not cands then return nil end
    for _, key in ipairs(cands) do
        if not set.slots[key] then
            set.slots[key] = id
            return key
        end
    end
    local pick = cands[1]
    for _, key in ipairs(cands) do
        if not set.important[set.slots[key]] then pick = key break end
    end
    local old = set.slots[pick]
    set.important[old] = nil
    set.slots[pick] = id
    return pick, old
end

-- Ein Item als Upgrade in einen passenden Slot legen: freier Upgrade-Platz zuerst, sonst ersetzen
local function PlaceUpgrade(set, id)
    local cands = LC:GearSlotsFor(id)
    if not cands then return nil end
    set.upgrades = set.upgrades or {}
    for _, key in ipairs(cands) do
        if not set.upgrades[key] then
            set.upgrades[key] = id
            return key
        end
    end
    local old = set.upgrades[cands[1]]
    set.upgrades[cands[1]] = id
    return cands[1], old
end

local function RemoveFrom(tbl, id)
    for key, x in pairs(tbl or {}) do
        if x == id then tbl[key] = nil return key end
    end
end

-- Alte Sets (Liste in Reihenfolge, bis 0.18) auf Slots umstellen
local function Migrate(set)
    set.upgrades = set.upgrades or {}
    if set.slots then
        set.important = set.important or {}
        return
    end
    set.slots, set.important = {}, {}
    for _, id in ipairs(set.items or {}) do
        local cands = LC:GearSlotsFor(id)
        if cands then
            for _, key in ipairs(cands) do
                if not set.slots[key] then set.slots[key] = id break end
            end
        end
    end
    set.items = nil
end

local function MyData()
    local key = LC:NameKey(LC:PlayerName()) or "?"
    LC.db.gearSets = LC.db.gearSets or {}
    local d = LC.db.gearSets[key]
    if not d then
        d = { order = {}, sets = {} }
        LC.db.gearSets[key] = d
    end
    if not d.migrated then
        for _, set in pairs(d.sets) do Migrate(set) end
        d.migrated = true
    end
    return d
end

local function CleanSetName(name)
    name = LC:CleanText(name or "", 30):gsub("[,^%%]", "")
    return strtrim(name)
end

function LC:GetMySets()
    local d = MyData()
    return d.order, d.active
end

-- Aktives Set: Tabelle und Name (nil, wenn keins)
function LC:GetActiveSet()
    local d = MyData()
    local set = d.active and d.sets[d.active]
    if not set then
        d.active = d.order[1]
        set = d.active and d.sets[d.active]
    end
    return set, d.active
end

-- Items eines Sets in Slot-Reihenfolge: { { id, slot, important } }
function LC:GearSetList(set)
    local out = {}
    if not set or not set.slots then return out end
    for _, s in ipairs(SLOTS) do
        local id = set.slots[s.key]
        if id then out[#out + 1] = { id = id, slot = s.key, important = set.important[id] == true } end
    end
    return out
end

-- Upgrades eines Sets in Slot-Reihenfolge: { { id, slot, upgrade = true } }
function LC:GearSetUpgradeList(set)
    local out = {}
    if not set or not set.upgrades then return out end
    for _, s in ipairs(SLOTS) do
        local id = set.upgrades[s.key]
        if id then out[#out + 1] = { id = id, slot = s.key, upgrade = true } end
    end
    return out
end

function LC:CreateGearSet(name)
    local d = MyData()
    name = CleanSetName(name)
    if name == "" then return false, L["Bitte einen Namen eingeben."] end
    if d.sets[name] then return false, L["Ein Set mit diesem Namen gibt es schon."] end
    if #d.order >= 10 then return false, L["Höchstens 10 Sets."] end
    d.sets[name] = { slots = {}, important = {}, upgrades = {} }
    d.order[#d.order + 1] = name
    d.active = name
    self:GearSetChanged()
    return true
end

function LC:RenameGearSet(old, new)
    local d = MyData()
    new = CleanSetName(new)
    if not d.sets[old] then return false end
    if new == "" then return false, L["Bitte einen Namen eingeben."] end
    if new ~= old and d.sets[new] then return false, L["Ein Set mit diesem Namen gibt es schon."] end
    d.sets[new], d.sets[old] = d.sets[old], (new == old) and d.sets[old] or nil
    for i, n in ipairs(d.order) do if n == old then d.order[i] = new end end
    if d.active == old then d.active = new end
    self:GearSetChanged()
    return true
end

function LC:DeleteGearSet(name)
    local d = MyData()
    if not d.sets[name] then return end
    d.sets[name] = nil
    for i, n in ipairs(d.order) do if n == name then table.remove(d.order, i) break end end
    if d.active == name then d.active = d.order[1] end
    self:GearSetChanged()
end

function LC:SetActiveGearSet(name)
    local d = MyData()
    if d.sets[name] then
        d.active = name
        self:GearSetChanged()
    end
end

-- Items ins aktive Set legen (legt bei Bedarf „Set 1“ an). Ein Item pro Slot:
-- ein neues Item ersetzt das bisherige im selben Slot.
-- asUpgrade = true: als Upgrade (zweite Wahl) des Slots statt als bestes Item
function LC:AddToGearSet(ids, asUpgrade)
    local set, name = self:GetActiveSet()
    if not set then
        self:CreateGearSet(L["Set 1"])
        set, name = self:GetActiveSet()
    end
    set.upgrades = set.upgrades or {}
    local added, lastText, notGear = 0, nil, 0
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        local already = id and ((asUpgrade and self:IsUpgradeInMySet(id)) or (not asUpgrade and self:IsInMySet(id)))
        if id and not already and self:GearSlotsFor(id) then
            -- Ein Item ist entweder bestes Item oder Upgrade – nie beides
            if asUpgrade then
                RemoveFrom(set.slots, id)
                set.important[id] = nil
            else
                RemoveFrom(set.upgrades, id)
            end
        end
        if id and not already then
            local slot, old
            if asUpgrade then slot, old = PlaceUpgrade(set, id) else slot, old = Place(set, id) end
            if slot then
                added = added + 1
                self:ItemLink(id)
                if old then
                    lastText = L("%s ersetzt %s.", self:ItemLink(id), self:ItemLink(old))
                elseif asUpgrade then
                    lastText = L("%s ist jetzt das Upgrade für „%s“.", self:ItemLink(id), self:GearSlotLabel(slot))
                else
                    lastText = L("%s liegt jetzt im Slot „%s“.", self:ItemLink(id), self:GearSlotLabel(slot))
                end
            else
                notGear = notGear + 1
            end
        end
    end
    if added > 0 then self:GearSetChanged() end
    if added == 0 then
        return false, (notGear > 0) and L["Das ist kein Ausrüstungsteil für einen Set-Slot."] or L["Schon im Set."]
    end
    if added == 1 then return true, lastText end
    return true, L("%d Item(s) zu „%s“ hinzugefügt.", added, name)
end

-- Slot des Items im aktiven Set (nil = nicht drin)
function LC:IsInMySet(itemID)
    local set = self:GetActiveSet()
    if not set or not set.slots then return nil end
    for key, id in pairs(set.slots) do
        if id == itemID then return key end
    end
    return nil
end

-- Upgrade-Slot des Items im aktiven Set (nil = kein Upgrade)
function LC:IsUpgradeInMySet(itemID)
    local set = self:GetActiveSet()
    if not set or not set.upgrades then return nil end
    for key, id in pairs(set.upgrades) do
        if id == itemID then return key end
    end
    return nil
end

-- Entfernt das Item aus dem aktiven Set – als bestes Item und als Upgrade
-- slot (optional): nur aus diesem Slot entfernen; upgrade = true: nur das Upgrade dieses Slots
function LC:RemoveFromGearSet(itemID, slot, upgrade)
    local set = self:GetActiveSet()
    if not set then return end
    local a, b
    if slot then
        local tbl = upgrade and set.upgrades or set.slots
        if tbl and tbl[slot] == itemID then tbl[slot] = nil a = true end
    else
        a = RemoveFrom(set.slots, itemID)
        b = RemoveFrom(set.upgrades, itemID)
    end
    if a or b then
        -- „wichtig“ nur löschen, wenn das Item nirgends mehr im Set steht
        local still = false
        for _, x in pairs(set.slots) do if x == itemID then still = true end end
        for _, x in pairs(set.upgrades or {}) do if x == itemID then still = true end end
        if not still then set.important[itemID] = nil end
        self:GearSetChanged()
    end
end

-- „Wichtig“ an- oder ausschalten
function LC:ToggleGearSetImportant(itemID)
    local set = self:GetActiveSet()
    if not set or not self:IsInMySet(itemID) then return end
    set.important[itemID] = (not set.important[itemID]) or nil
    self:GearSetChanged()
end

-- Fehlende Items des aktiven Sets, die in diesem Raid droppen (wichtige zuerst, dann nach Slot)
function LC:GearSetItemsForRaid(raid)
    local set = self:GetActiveSet()
    if not set or not raid then return {} end
    local inRaid = {}
    for _, boss in ipairs(raid.bosses or {}) do
        for _, id in ipairs(boss.items or {}) do inRaid[id] = true end
    end
    local first, rest, upgrades = {}, {}, {}
    for _, it in ipairs(self:GearSetList(set)) do
        if inRaid[it.id] and not self:HaveItem(it.id) then
            local list = it.important and first or rest
            list[#list + 1] = it.id
        end
    end
    -- Upgrades zuletzt – und nur, wenn das beste Item des Slots noch fehlt
    for _, it in ipairs(self:GearSetUpgradeList(set)) do
        local best = set.slots[it.slot]
        if inRaid[it.id] and not self:HaveItem(it.id) and not (best and self:HaveItem(best)) then
            upgrades[#upgrades + 1] = it.id
        end
    end
    for _, id in ipairs(rest) do first[#first + 1] = id end
    for _, id in ipairs(upgrades) do first[#first + 1] = id end
    return first
end

------------------------------------------------------------------------
-- Sets anderer Spieler und Auswertung (auch für den Council)
------------------------------------------------------------------------
-- Aktives Set eines Spielers als { name, set, items = { { id, have, important } } } – auch für mich selbst
function LC:GetPlayerGearSet(name)
    if self:IsMe(name) then
        local set, setName = self:GetActiveSet()
        if not set then return nil end
        local items = {}
        for _, it in ipairs(self:GearSetList(set)) do
            items[#items + 1] = { id = it.id, have = self:HaveItem(it.id), important = it.important }
        end
        for _, it in ipairs(self:GearSetUpgradeList(set)) do
            items[#items + 1] = { id = it.id, have = self:HaveItem(it.id), upgrade = true }
        end
        return { name = self:PlayerName(), set = setName, items = items, time = time() }
    end
    return (self:FindByName(self.db.otherSets or {}, name))
end

-- Stand eines Items im Set eines Spielers.
-- „Hat er schon“ gilt auch, wenn die Loot-Historie zeigt, dass er das Item bekommen hat –
-- so kann sich niemand bedürftiger machen, indem er ein erhaltenes Item als fehlend meldet.
-- Rückgabe: { inSet (fehlt noch), important, upgrade, owned, have, missing, total, set, time }
-- have/missing/total zählen nur die besten Items, nicht die Upgrades.
function LC:GearSetRank(name, itemID)
    local s = self:GetPlayerGearSet(name)
    if not s then return nil end
    local info = { have = 0, missing = 0, total = 0, set = s.set, time = s.time }
    for _, it in ipairs(s.items) do
        local got = it.have or WonByHistory(s.name, it.id)
        if not it.upgrade then
            info.total = info.total + 1
            if got then info.have = info.have + 1 else info.missing = info.missing + 1 end
        end
        if it.id == itemID and not info.inSet and not info.owned then
            if got then info.owned = true
            else
                info.inSet = true
                info.important = (not it.upgrade and it.important == true) or nil
                info.upgrade = it.upgrade == true or nil
            end
        end
    end
    return info
end

-- Ist das Set eines anderen Spielers älter als 14 Tage? (dann ist es womöglich nicht mehr aktuell)
function LC:GearSetIsOld(info)
    return info and info.time and (time() - info.time) > 14 * 86400
end

LC.STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13|t"
LC.UPGRADE = "|TInterface\\Buttons\\Arrow-Up-Up:13:13:0:-2|t"

-- Kurztext für Listen: „★ wichtig“, „im Set“, „▲ Upgrade“, „hat es“, „nicht im Set“ oder „kein Set“
function LC:GearSetRankText(name, itemID)
    local H = self.T.HEX
    local info = self:GearSetRank(name, itemID)
    if not info then return H.muted .. L["kein Set"] .. "|r" end
    if info.owned then return H.muted .. L["hat es"] .. "|r" end
    if not info.inSet then return H.muted .. L["nicht im Set"] .. "|r" end
    local text
    if info.important then text = self.STAR .. " " .. H.good .. L["wichtig"] .. "|r"
    elseif info.upgrade then text = self.UPGRADE .. H.warn .. L["Upgrade"] .. "|r"
    else text = H.accentLt .. L["im Set"] .. "|r" end
    if self:GearSetIsOld(info) then text = text .. H.muted .. L[" (alt)"] .. "|r" end
    return text
end

-- Zeilen für einen Tooltip: Set-Name, Stand und Stand eines Items
function LC:AddGearSetTooltip(tooltip, name, itemID)
    local s = self:GetPlayerGearSet(name)
    if not s then return end
    local info = self:GearSetRank(name, itemID)
    tooltip:AddLine(L("Gear-Set „%s“: %d von %d Items", s.set, info.have, info.total), 0.82, 0.71, 1)
    if not self:IsMe(name) and s.time then
        local c = self:GearSetIsOld(info) and { 1, 0.75, 0.25 } or { 0.6, 0.6, 0.6 }
        tooltip:AddLine(L("Stand: %s", self:AgoText(s.time)), c[1], c[2], c[3])
    end
    if itemID and info.inSet then
        tooltip:AddLine(info.important and L["Dieses Item: im Set, als wichtig markiert, fehlt noch"]
            or (info.upgrade and L["Dieses Item: Upgrade im Set (nicht das beste, aber besser als das jetzige), fehlt noch"])
            or L["Dieses Item: im Set, fehlt noch"], 0.8, 0.8, 0.8, true)
    elseif itemID and info.owned then
        tooltip:AddLine(L["Dieses Item ist schon vorhanden."], 0.8, 0.8, 0.8)
    elseif itemID then
        tooltip:AddLine(L["Dieses Item ist nicht im Set."], 0.6, 0.6, 0.6)
    end
end

-- Alle bekannten Sets (inkl. eigenem), sortiert nach Name
function LC:GetAllGearSets()
    local out = {}
    local mine = self:GetPlayerGearSet(self:PlayerName())
    if mine then out[#out + 1] = mine end
    for key, s in pairs(self.db.otherSets or {}) do
        if not self:IsMe(s.name) then out[#out + 1] = s end
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

------------------------------------------------------------------------
-- Abgleich
------------------------------------------------------------------------
local function EncodeMine()
    local set, name = LC:GetActiveSet()
    local list = LC:GearSetList(set)
    if #list == 0 then return strjoin(SEP, "GS", "", "") end
    -- Nur so viele Items, wie in eine Nachricht passen (sonst würde das letzte abgeschnitten)
    local head = strjoin(SEP, "GS", name, "")
    local parts, len = {}, #head
    for _, it in ipairs(list) do
        local part = it.id .. ":" .. (LC:HaveItem(it.id) and "1" or "0") .. ":" .. (it.important and "1" or "0")
        if len + #part + 1 > 245 then break end
        parts[#parts + 1] = part
        len = len + #part + 1
    end
    return head .. table.concat(parts, ",")
end

-- Upgrades als eigene Nachricht (nil, wenn das Set keine hat)
local function EncodeUpgrades()
    local set, name = LC:GetActiveSet()
    local list = LC:GearSetUpgradeList(set)
    if #list == 0 then return nil end
    local head = strjoin(SEP, "GU", name, "")
    local parts, len = {}, #head
    for _, it in ipairs(list) do
        local part = it.id .. ":" .. (LC:HaveItem(it.id) and "1" or "0")
        if len + #part + 1 > 245 then break end
        parts[#parts + 1] = part
        len = len + #part + 1
    end
    return head .. table.concat(parts, ",")
end

-- Set (und Upgrades) an ein Ziel schicken; GU immer direkt nach GS, weil GS die Upgrades zurücksetzt
local function SendMine(channel, target)
    LC:SendLow(EncodeMine(), channel, target)
    local up = EncodeUpgrades()
    if up then LC:SendLow(up, channel, target) end
end

local lastSentSig
function LC:BroadcastGearSet(force)
    local sig = EncodeMine() .. "|" .. (EncodeUpgrades() or "")
    if not force and sig == lastSentSig then return end
    lastSentSig = sig
    if IsInGuild() then SendMine("GUILD") end
    if IsInRaid() then SendMine("RAID")
    elseif IsInGroup() then SendMine("PARTY") end
end

-- Änderungen sammeln und nach kurzer Pause einmal senden
local pending
function LC:GearSetChanged()
    self:RefreshUI()
    if pending then return end
    pending = true
    C_Timer.After(5, function()
        pending = nil
        LC:BroadcastGearSet()
    end)
end

function LC:RequestGearSets()
    if IsInGuild() then self:SendLow("GQ", "GUILD") end
    if IsInRaid() then self:SendLow("GQ", "RAID")
    elseif IsInGroup() then self:SendLow("GQ", "PARTY") end
end

local function Receive(sender, setName, payload)
    local key = LC:NameKey(sender)
    if not key then return end
    LC.db.otherSets = LC.db.otherSets or {}
    setName = LC:SafeText(setName, 30)
    if setName == "" or not payload or payload == "" then
        LC.db.otherSets[key] = nil
        LC:RefreshUI()
        return
    end
    local items = {}
    for id, h, w in payload:gmatch("(%d+):([01]):?([01]?)") do
        if #items >= MAX_ITEMS then break end
        items[#items + 1] = { id = tonumber(id), have = (h == "1"), important = (w == "1") or nil }
    end
    LC.db.otherSets[key] = { name = LC:ShortName(sender), set = setName, items = items, time = time() }
    -- Speicher begrenzen
    local n, oldestKey, oldestTime = 0, nil, math.huge
    for k, s in pairs(LC.db.otherSets) do
        n = n + 1
        if (s.time or 0) < oldestTime then oldestKey, oldestTime = k, s.time or 0 end
    end
    if n > MAX_OTHERS and oldestKey then LC.db.otherSets[oldestKey] = nil end
    LC:RefreshUI()
end

-- Upgrades kommen direkt nach dem Set (GS hat sie zurückgesetzt) – nur an ein Set mit gleichem Namen hängen
local function ReceiveUpgrades(sender, setName, payload)
    local key = LC:NameKey(sender)
    local s = key and LC.db.otherSets and LC.db.otherSets[key]
    if not s or s.set ~= LC:SafeText(setName, 30) then return end
    local n = 0
    for _, it in ipairs(s.items) do if it.upgrade then n = n + 1 end end
    for id, h in (payload or ""):gmatch("(%d+):([01])") do
        if n >= MAX_UPGRADES then break end
        id = tonumber(id)
        local dup = false
        for _, it in ipairs(s.items) do if it.id == id then dup = true break end end
        if not dup then
            s.items[#s.items + 1] = { id = id, have = (h == "1"), upgrade = true }
            n = n + 1
        end
    end
    LC:RefreshUI()
end

local answered = {}
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~?(.*)$")
    if cmd and CMDS[cmd] then
        if self:IsMe(sender) then return end
        if cmd == "GQ" then
            local key = self:NameKey(sender)
            local set = self:GetActiveSet()
            if key and set and #LC:GearSetList(set) > 0 and (GetTime() - (answered[key] or -999)) >= 60 then
                answered[key] = GetTime()
                C_Timer.After(1 + math.random() * 4, function() SendMine("WHISPER", sender) end)
            end
        else
            local setName, payload = rest:match("^([^~]*)~?(.*)$")
            if cmd == "GU" then ReceiveUpgrades(sender, setName, payload)
            else Receive(sender, setName, payload) end
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
-- Neues Item bekommen: „habe ich“ ändert sich -> Set neu verteilen (gesammelt)
-- Nur melden, wenn sich bei einem Set-Item wirklich etwas geändert hat (Taschen ändern sich ständig)
local lastHaveSig
local function HaveChanged()
    wipe(haveCache)
    if not LC.db then return end
    local set = LC:GetActiveSet()
    local list = LC:GearSetList(set)
    for _, it in ipairs(LC:GearSetUpgradeList(set)) do list[#list + 1] = it end
    if #list == 0 then return end
    local sig = {}
    for i, it in ipairs(list) do sig[i] = LC:HaveItem(it.id) and "1" or "0" end
    sig = table.concat(sig)
    if sig ~= lastHaveSig then
        lastHaveSig = sig
        LC:GearSetChanged()
    end
end
LC:On("BAG_UPDATE_DELAYED", HaveChanged)
LC:On("PLAYER_EQUIPMENT_CHANGED", HaveChanged)

local wasInRaid = false
LC:On("GROUP_ROSTER_UPDATE", function(self)
    local inRaid = IsInRaid()
    if inRaid and not wasInRaid then
        C_Timer.After(8 + math.random() * 6, function()
            if IsInRaid() then LC:BroadcastGearSet(true) LC:RequestGearSets() end
        end)
    end
    wasInRaid = inRaid
end)

LC:On("PLAYER_LOGIN", function(self)
    wasInRaid = IsInRaid()
    local now = time()
    for k, s in pairs(self.db.otherSets or {}) do
        if now - (s.time or 0) > KEEP_OTHERS then self.db.otherSets[k] = nil end
    end
    C_Timer.After(35 + math.random() * 10, function() LC:BroadcastGearSet(true) end)
end)
