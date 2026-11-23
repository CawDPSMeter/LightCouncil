-- Light Council – Gear-Sets: Raider stellen sich ein oder mehrere Sets zusammen
--
-- Ein Set ist eine Liste von Items in Prio-Reihenfolge (1 = am wichtigsten). Mehrere Items für denselben
-- Slot sind erlaubt (z. B. Alternativen je nach Biom). Ob man ein Item schon hat, erkennt das Addon selbst
-- (angelegt, Taschen, Bank). Das aktive Set wird an alle Addon-Nutzer verteilt – so sieht jeder (und der
-- Council bei der Abstimmung), wo ein Spieler im Gear steht und was ihm am wichtigsten ist.
--
-- Nachrichten:
--   GS~setname~id:h,id:h,…   alle -> Gilde/Raid (bzw. Whisper als Antwort): mein aktives Set (h = 1: habe ich)
--   GQ                       alle -> Gilde/Raid: bitte aktive Sets schicken
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { GS = true, GQ = true }
local MAX_ITEMS = 24          -- passt in eine Nachricht
local MAX_OTHERS = 300
local KEEP_OTHERS = 60 * 86400

------------------------------------------------------------------------
-- Slots
------------------------------------------------------------------------
-- Reihenfolge der Slots wie im Charakterfenster; Beschriftung kommt lokalisiert vom Spiel (_G[equipLoc])
local SLOT_ORDER = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WRIST = 6, INVTYPE_HAND = 7, INVTYPE_WAIST = 8,
    INVTYPE_LEGS = 9, INVTYPE_FEET = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 12,
    INVTYPE_WEAPON = 13, INVTYPE_2HWEAPON = 13, INVTYPE_WEAPONMAINHAND = 13,
    INVTYPE_WEAPONOFFHAND = 14, INVTYPE_SHIELD = 14, INVTYPE_HOLDABLE = 14,
    INVTYPE_RANGED = 15, INVTYPE_RANGEDRIGHT = 15, INVTYPE_THROWN = 15, INVTYPE_RELIC = 15,
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

-- Slot-Name und Sortierposition eines Items (unbekannt: "?" / 99)
function LC:ItemSlot(itemID)
    local loc = EquipLoc(itemID)
    if not loc or loc == "" then return L["Sonstiges"], 99 end
    return _G[loc] or loc, SLOT_ORDER[loc] or 98
end

-- Habe ich das Item? (angelegt, Taschen oder Bank)
function LC:HaveItem(itemID)
    if not itemID then return false end
    for slot = 1, 19 do
        if GetInventoryItemID("player", slot) == itemID then return true end
    end
    local count = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(itemID, true) or GetItemCount(itemID, true)
    return (count or 0) > 0
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
local function MyData()
    local key = LC:NameKey(LC:PlayerName()) or "?"
    LC.db.gearSets = LC.db.gearSets or {}
    local d = LC.db.gearSets[key]
    if not d then
        d = { order = {}, sets = {} }
        LC.db.gearSets[key] = d
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

function LC:CreateGearSet(name)
    local d = MyData()
    name = CleanSetName(name)
    if name == "" then return false, L["Bitte einen Namen eingeben."] end
    if d.sets[name] then return false, L["Ein Set mit diesem Namen gibt es schon."] end
    if #d.order >= 10 then return false, L["Höchstens 10 Sets."] end
    d.sets[name] = { items = {} }
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

-- Items ans Ende des aktiven Sets anhängen (legt bei Bedarf „Set 1“ an)
function LC:AddToGearSet(ids)
    local set, name = self:GetActiveSet()
    if not set then
        self:CreateGearSet(L["Set 1"])
        set, name = self:GetActiveSet()
    end
    local have = {}
    for _, id in ipairs(set.items) do have[id] = true end
    local added = 0
    for _, id in ipairs(ids or {}) do
        id = tonumber(id)
        if id and not have[id] then
            if #set.items >= MAX_ITEMS then
                if added > 0 then self:GearSetChanged() end
                return added > 0, L("Höchstens %d Items pro Set.", MAX_ITEMS)
            end
            set.items[#set.items + 1] = id
            have[id] = true
            added = added + 1
            self:ItemLink(id)
        end
    end
    if added > 0 then self:GearSetChanged() end
    return added > 0, (added > 0) and L("%d Item(s) zu „%s“ hinzugefügt.", added, name) or L["Schon im Set."]
end

function LC:IsInMySet(itemID)
    local set = self:GetActiveSet()
    if not set then return nil end
    for i, id in ipairs(set.items) do if id == itemID then return i end end
    return nil
end

function LC:RemoveFromGearSet(index)
    local set = self:GetActiveSet()
    if set and set.items[index] then
        table.remove(set.items, index)
        self:GearSetChanged()
    end
end

-- Eintrag in der Prio nach oben (-1) oder unten (+1) schieben
function LC:MoveInGearSet(index, delta)
    local set = self:GetActiveSet()
    if not set then return end
    local j = index + delta
    if not set.items[index] or not set.items[j] then return end
    set.items[index], set.items[j] = set.items[j], set.items[index]
    self:GearSetChanged()
end

-- Fehlende Items des aktiven Sets, die in diesem Raid droppen (in Prio-Reihenfolge)
function LC:GearSetItemsForRaid(raid)
    local set = self:GetActiveSet()
    if not set or not raid then return {} end
    local inRaid = {}
    for _, boss in ipairs(raid.bosses or {}) do
        for _, id in ipairs(boss.items or {}) do inRaid[id] = true end
    end
    local out = {}
    for _, id in ipairs(set.items) do
        if inRaid[id] and not self:HaveItem(id) then out[#out + 1] = id end
    end
    return out
end

------------------------------------------------------------------------
-- Sets anderer Spieler und Auswertung (auch für den Council)
------------------------------------------------------------------------
-- Aktives Set eines Spielers als { name, set, items = { { id, have } } } – auch für mich selbst
function LC:GetPlayerGearSet(name)
    if self:IsMe(name) then
        local set, setName = self:GetActiveSet()
        if not set then return nil end
        local items = {}
        for _, id in ipairs(set.items) do items[#items + 1] = { id = id, have = self:HaveItem(id) } end
        return { name = self:PlayerName(), set = setName, items = items, time = time() }
    end
    return (self:FindByName(self.db.otherSets or {}, name))
end

-- Platz eines Items im Set eines Spielers: Rang unter den fehlenden Items, Anzahl, schon vorhanden
function LC:GearSetRank(name, itemID)
    local s = self:GetPlayerGearSet(name)
    if not s then return nil end
    local rank, missing, have = nil, 0, 0
    for _, it in ipairs(s.items) do
        if it.have then
            have = have + 1
        else
            missing = missing + 1
            if it.id == itemID then rank = missing end
        end
    end
    return { rank = rank, missing = missing, have = have, total = #s.items, set = s.set,
        owned = (function() for _, it in ipairs(s.items) do if it.id == itemID and it.have then return true end end end)() }
end

-- Kurztext für Listen: "#2 von 7" (Platz unter den fehlenden Items), "hat es", "nicht im Set" oder "kein Set"
function LC:GearSetRankText(name, itemID)
    local H = self.T.HEX
    local info = self:GearSetRank(name, itemID)
    if not info then return H.muted .. L["kein Set"] .. "|r" end
    if info.owned then return H.muted .. L["hat es"] .. "|r" end
    if not info.rank then return H.muted .. L["nicht im Set"] .. "|r" end
    local color = (info.rank <= 2) and H.good or ((info.rank <= 5) and H.accentLt or "")
    return color .. L("#%d von %d", info.rank, info.missing) .. ((color ~= "") and "|r" or "")
end

-- Zeilen für einen Tooltip: Set-Name, Stand und Platz eines Items
function LC:AddGearSetTooltip(tooltip, name, itemID)
    local s = self:GetPlayerGearSet(name)
    if not s then return end
    local info = self:GearSetRank(name, itemID)
    tooltip:AddLine(L("Gear-Set „%s“: %d von %d Items", s.set, info.have, info.total), 0.82, 0.71, 1)
    if itemID and info.rank then
        tooltip:AddLine(L("Dieses Item: Prio #%d der fehlenden Items", info.rank), 0.8, 0.8, 0.8)
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
    if not set or #set.items == 0 then return strjoin(SEP, "GS", "", "") end
    local parts = {}
    for _, id in ipairs(set.items) do
        parts[#parts + 1] = id .. ":" .. (LC:HaveItem(id) and "1" or "0")
    end
    return strjoin(SEP, "GS", name, table.concat(parts, ","))
end

local lastSentSig
function LC:BroadcastGearSet(force)
    local msg = EncodeMine()
    if not force and msg == lastSentSig then return end
    lastSentSig = msg
    if IsInGuild() then self:SendLow(msg, "GUILD") end
    if IsInRaid() then self:SendLow(msg, "RAID")
    elseif IsInGroup() then self:SendLow(msg, "PARTY") end
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
    for id, h in payload:gmatch("(%d+):([01])") do
        if #items >= MAX_ITEMS then break end
        items[#items + 1] = { id = tonumber(id), have = (h == "1") }
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

local answered = {}
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~?(.*)$")
    if cmd and CMDS[cmd] then
        if self:IsMe(sender) then return end
        if cmd == "GQ" then
            local key = self:NameKey(sender)
            local set = self:GetActiveSet()
            if key and set and #set.items > 0 and (GetTime() - (answered[key] or -999)) >= 60 then
                answered[key] = GetTime()
                C_Timer.After(1 + math.random() * 4, function() LC:SendLow(EncodeMine(), "WHISPER", sender) end)
            end
        else
            local setName, payload = rest:match("^([^~]*)~?(.*)$")
            Receive(sender, setName, payload)
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
-- Neues Item bekommen: „habe ich“ ändert sich -> Set neu verteilen (gesammelt)
local function HaveChanged()
    if not LC.db then return end
    local set = LC:GetActiveSet()
    if set and #set.items > 0 then LC:GearSetChanged() end
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
