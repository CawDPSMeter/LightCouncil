-- Light Council – angelegte Ausrüstung
--
-- Der Council soll bei der Abstimmung sehen, was ein Kandidat im Slot des Items gerade trägt.
-- Spieler mit Addon schicken ihre angelegten Items an die Gruppe. Für Spieler ohne Addon schaut der
-- Council bzw. die Raidleitung im Hintergrund per Inspect nach (nur außerhalb des Kampfes, in Reichweite).
--
-- Daten (nur im Speicher, nicht gespeichert): equipped[nameKey] = { time, src = "addon"|"inspect", items = { [invSlot] = itemID } }
--
-- Nachrichten:
--   EQ~slot:id,…   alle -> Raid/Gruppe: meine angelegten Items (nur belegte Slots)
--   EQQ            alle -> Raid/Gruppe: bitte angelegte Items schicken (Antwort als EQ an die Gruppe)
local _, LC = ...
local L = LC.L

local SEP = "~"
local STALE = 30 * 60           -- Inspect-Daten älter als 30 Min. bzw. Addon-Daten von Spielern, die nicht mehr in der Gruppe sind: veraltet
local INSPECT_AGE = 10 * 60     -- Inspect-Daten frühestens nach 10 Min. erneuern
local MAX_ENTRIES = 80
-- Inventar-Slots, die zählen (ohne Hemd 4 und Wappenrock 19)
local INV_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local VALID_SLOT = {}
for _, s in ipairs(INV_SLOTS) do VALID_SLOT[s] = true end
-- Set-Slot (GearSets.lua) -> Inventar-Slot
local KEY_INV = {
    HEAD = 1, NECK = 2, SHOULDER = 3, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9, HANDS = 10,
    FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15,
    MAINHAND = 16, OFFHAND = 17, RANGED = 18,
}

local equipped = {}
LC.equipped = equipped

------------------------------------------------------------------------
-- Eigene Ausrüstung senden
------------------------------------------------------------------------
local function EncodeMine()
    local parts = {}
    for _, s in ipairs(INV_SLOTS) do
        local id = GetInventoryItemID("player", s)
        if id then parts[#parts + 1] = s .. ":" .. id end
    end
    return strjoin(SEP, "EQ", table.concat(parts, ","))   -- höchstens 17 × 10 Zeichen, passt in eine Nachricht
end

local function GroupChannel()
    if IsInRaid() then return "RAID" elseif IsInGroup() then return "PARTY" end
end

local lastSent, lastSentAt = nil, -999
function LC:BroadcastEquipped(force)
    local ch = GroupChannel()
    if not ch then return end
    local msg = EncodeMine()
    if not force and msg == lastSent then return end
    lastSent, lastSentAt = msg, GetTime()
    self:SendLow(msg, ch)
end

local pending
local function EquipChanged()
    if pending or not GroupChannel() then return end
    pending = true
    C_Timer.After(10, function()
        pending = nil
        LC:BroadcastEquipped()
    end)
end

------------------------------------------------------------------------
-- Empfangen
------------------------------------------------------------------------
local function Store(key, name, items, src)
    equipped[key] = { name = name, time = time(), src = src, items = items }
    -- Speicher begrenzen: ältesten Eintrag entfernen
    local n, oldestKey, oldestTime = 0, nil, math.huge
    for k, e in pairs(equipped) do
        n = n + 1
        if e.time < oldestTime then oldestKey, oldestTime = k, e.time end
    end
    if n > MAX_ENTRIES and oldestKey then equipped[oldestKey] = nil end
end

local function Receive(sender, payload)
    local key = LC:NameKey(sender)
    if not key then return end
    local items, n = {}, 0
    for slot, id in (payload or ""):gmatch("(%d+):(%d+)") do
        slot, id = tonumber(slot), tonumber(id)
        if VALID_SLOT[slot] and id and id > 0 and id < 10000000 and not items[slot] then
            items[slot] = id
            n = n + 1
            if n >= #INV_SLOTS then break end
        end
    end
    Store(key, LC:ShortName(sender), items, "addon")
    LC:RefreshVoteEquipped()
end

local answeredAt = -999
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~?(.*)$")
    if cmd == "EQ" or cmd == "EQQ" then
        if self:IsMe(sender) then return end
        if channel ~= "RAID" and channel ~= "PARTY" then return end
        if cmd == "EQQ" then
            -- Eine Antwort an die ganze Gruppe pro Minute reicht für alle, die gerade fragen
            if GetTime() - answeredAt >= 60 and GetTime() - lastSentAt >= 20 then
                answeredAt = GetTime()
                C_Timer.After(2 + math.random() * 6, function() LC:BroadcastEquipped(true) end)
            end
        else
            Receive(sender, rest)
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

------------------------------------------------------------------------
-- Abfragen
------------------------------------------------------------------------
local function Find(name)
    return (LC:FindExact(equipped, name))   -- exakt, sonst eindeutiger Vornamen-Treffer
end

-- Eigene Ausrüstung direkt lesen (immer aktuell)
local function Mine()
    local items = {}
    for _, s in ipairs(INV_SLOTS) do items[s] = GetInventoryItemID("player", s) end
    return { name = LC:PlayerName(), time = time(), src = "addon", items = items }
end

-- Inventar-Slots, in die das Item passt (nil: kein Ausrüstungsitem, z. B. Token)
function LC:EquipSlotsFor(itemID)
    local keys = itemID and self:GearSlotsFor(itemID)
    if not keys then return nil end
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = KEY_INV[k] end
    return out
end

function LC:ItemLevelOf(itemID)
    if not itemID then return nil end
    if GetDetailedItemLevelInfo then
        local ok, lvl = pcall(GetDetailedItemLevelInfo, itemID)
        if ok and lvl and lvl > 0 then return lvl end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local lvl = select(4, getInfo(itemID))
    if (not lvl) and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    return lvl
end

-- Was trägt der Spieler im Slot des Items?
-- Rückgabe: nil (Item hat keinen Slot), sonst { known, stale, time, src, items = { { slot, id } } }
function LC:GetEquippedFor(name, itemID)
    local slots = self:EquipSlotsFor(itemID)
    if not slots then return nil end
    local e = self:IsMe(name) and Mine() or Find(name)
    local out = { known = e ~= nil, items = {} }
    if not e then return out end
    out.time, out.src = e.time, e.src
    -- Addon-Nutzer melden jede Änderung selbst: aktuell, solange sie in der Gruppe sind
    local inGroup = self:IsMe(name) or self:FindExact(self:GetGroupMembers(), name) ~= nil
    out.stale = (time() - e.time) > STALE and not (e.src == "addon" and inGroup)
    for _, s in ipairs(slots) do
        out.items[#out.items + 1] = { slot = s, id = e.items[s] }
    end
    return out
end

local function AgeText(t)
    local min = math.floor((time() - (t or 0)) / 60)
    if min < 1 then return L["gerade eben"] end
    if min < 120 then return L("vor %d Min.", min) end
    return L("vor %d Std.", math.floor(min / 60))
end
LC.EquippedAgeText = AgeText

-- Zeilen für Tooltips: „Angelegt: [Item] (ilvl 120)“
function LC:AddEquippedTooltip(tooltip, name, itemID)
    local info = self:GetEquippedFor(name, itemID)
    if not info then return end
    if not info.known then
        tooltip:AddLine(L["Angelegt: unbekannt (kein Addon, nicht in Inspect-Reichweite)"], 0.6, 0.6, 0.6, true)
        return
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for _, it in ipairs(info.items) do
        if it.id then
            local itemName, link = getInfo(it.id)
            local lvl = self:ItemLevelOf(it.id)
            tooltip:AddLine(L["Angelegt: "] .. (link or itemName or (L["Item #"] .. it.id))
                .. (lvl and ("  |cff999999" .. L["ilvl"] .. " " .. lvl .. "|r") or ""), 1, 1, 1)
        else
            tooltip:AddLine(L["Angelegt: "] .. L["Slot leer"], 0.6, 0.6, 0.6)
        end
    end
    local when = AgeText(info.time) .. ((info.src == "inspect") and (" · " .. L["per Inspect"]) or "")
    if info.stale then
        tooltip:AddLine(L["veraltet"] .. " (" .. when .. ")", 1, 0.6, 0.3)
    else
        tooltip:AddLine(when, 0.6, 0.6, 0.6)
    end
end

------------------------------------------------------------------------
-- Inspect für Spieler ohne Addon (nur Council / Raidleitung, außerhalb des Kampfes)
------------------------------------------------------------------------
local inspecting   -- { guid, unit, key, name, at }

local function MayInspect()
    if not IsInRaid() and not IsInGroup() then return false end
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    if not NotifyInspect or not CanInspect or not UnitGUID then return false end
    if InspectFrame and InspectFrame:IsShown() then return false end   -- der Spieler schaut selbst jemanden an
    return LC:AmICouncil() or LC:IsMasterLooter() or (UnitIsGroupLeader and UnitIsGroupLeader("player"))
end

local function NextTarget()
    local now = time()
    for key, m in pairs(LC:GetGroupMembers()) do
        local unit = m.unit
        if unit and m.online and not UnitIsUnit(unit, "player") then
            local e = equipped[key]
            local fresh = e and (e.src == "addon" or now - e.time < INSPECT_AGE)
            if not fresh and CanInspect(unit) and (not CheckInteractDistance or CheckInteractDistance(unit, 1)) then
                return unit, key, m.name
            end
        end
    end
end

local function InspectTick()
    if inspecting and GetTime() - inspecting.at > 5 then inspecting = nil end   -- keine Antwort
    if inspecting or not MayInspect() then return end
    local unit, key, name = NextTarget()
    if not unit then return end
    inspecting = { guid = UnitGUID(unit), unit = unit, key = key, name = name, at = GetTime() }
    NotifyInspect(unit)
end

LC:On("INSPECT_READY", function(self, guid)
    local job = inspecting
    if not job or guid ~= job.guid then return end
    inspecting = nil
    if UnitGUID(job.unit) ~= guid then return end   -- Gruppe hat sich umsortiert
    local items, n = {}, 0
    for _, s in ipairs(INV_SLOTS) do
        local id = GetInventoryItemID(job.unit, s)
        if id then items[s] = id n = n + 1 end
    end
    if not (InspectFrame and InspectFrame:IsShown()) and ClearInspectPlayer then ClearInspectPlayer() end
    if n == 0 then return end   -- Daten noch nicht geladen – später nochmal
    local e = equipped[job.key]
    if e and e.src == "addon" then return end   -- Addon-Daten haben Vorrang
    Store(job.key, job.name, items, "inspect")
    self:RefreshVoteEquipped()
end)

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
LC:On("PLAYER_EQUIPMENT_CHANGED", EquipChanged)

local wasInGroup = false
LC:On("GROUP_ROSTER_UPDATE", function(self)
    local inGroup = IsInGroup()
    if inGroup and not wasInGroup then
        C_Timer.After(10 + math.random() * 8, function()
            if IsInGroup() then
                LC:BroadcastEquipped(true)
                local ch = GroupChannel()
                if ch then LC:SendLow("EQQ", ch) end
            end
        end)
    end
    wasInGroup = inGroup
end)

LC:On("PLAYER_LOGIN", function(self)
    wasInGroup = IsInGroup()
    C_Timer.After(40 + math.random() * 10, function()
        LC:BroadcastEquipped(true)
        local ch = GroupChannel()   -- nach /reload in der Gruppe: die anderen fragen
        if ch then LC:SendLow("EQQ", ch) end
    end)
    if C_Timer.NewTicker then C_Timer.NewTicker(4, InspectTick) end
end)
