-- Light Council – Core: Namespace, SavedVariables, Hilfsfunktionen, Events, Slash-Befehle
local ADDON, LC = ...
local L = LC.L
_G.LightCouncil = LC

-- Versionsnummer nur an einer Stelle pflegen: in der .toc
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    LC.version = (getMeta and getMeta(ADDON, "Version")) or "0"
end
LC.prefix = "LCouncil"
LC.COLOR = "|cffb48cff"

------------------------------------------------------------------------
-- Standardwerte
------------------------------------------------------------------------
local DEFAULTS = {
    config = {
        council = {},           -- Namen der Council-Mitglieder (Vor- und Nachname)
        councilSize = 3,        -- 3 oder 5 Mitglieder (größere Gilden)
        voteTimeout = 30,       -- Sekunden für die Council-Abstimmung
        rollTimeout = 20,       -- Sekunden zum Würfeln
        cooldownWeeks = 2,      -- Loot-Cooldown nach Gewinn eines Council-Items
        attendanceWeeks = 8,    -- Zeitraum für die Anwesenheit
        weights = { attendance = 40, parse = 40, engagement = 20 },
        autoStart = true,       -- Council automatisch starten, wenn ein Council-Item im Loot liegt
        minimap = { angle = 200, hide = false },
        raidWarning = true,     -- Council-Items und Entscheidungen zusätzlich als Raidwarnung
        raiderWindow = true,    -- Loot-Fenster für Raider anzeigen, wenn Loot droppt
        autoAward = true,       -- Gewinner bekommt das Item automatisch (Plündermeister)
        raidDays = {},          -- Raidtage als Wochentag (1 = Sonntag … 7 = Samstag) – Erinnerung zum Reservieren
        reminderRaid = "",      -- Raid (Schlüssel), an den erinnert wird; "" = irgendein Raid
        maxReserves = 2,        -- Reservierungen pro Raider und Raid
        lootSource = "auto",    -- Loot-Quelle: auto / atlas / naowh (nur Raids)
        setReserve = false,     -- Raider dürfen aus ihrem Gear-Set reservieren (Council-Einstellung)
        tooltip = true,         -- Council-Item und Reservierer im Item-Tooltip anzeigen
        language = "auto",      -- Sprache: auto (Spielclient) / deDE / enUS / frFR / esES / ruRU
        jsonOnLogout = true,    -- JSON-Export beim Ausloggen in die SavedVariables schreiben (LightCouncilExport)
    },
    reserves = {},      -- Reservierungen im Addon (siehe Reserve.lua)
    knownCouncil = {},  -- vom Council übermittelte Council-Liste (für Raider ohne eigene Einstellung)
    softres = {},       -- [itemID] = { { name = "Anna", note = "" }, ... } – wird aus den Reservierungen erzeugt
    softresMeta = {},   -- { time = ..., count = ... }
    councilItems = {},  -- [itemID] = true
    players = {},       -- [key] = { name, parse, engagement, wins = { { week, itemID, time } } }
    attendance = {},    -- [week] = { [key] = "Name" }
    sitouts = {},       -- [week] = { [itemID] = { [key] = "Name" } }
    log = {},           -- Protokoll aller Entscheidungen
    history = {},       -- Loot-Historie: { id, itemID, winner, time, week, raid, roll, council, reserved }
    gearSets = {},      -- [Charakter] = { active = "Name", order = { "Name", … }, sets = { [Name] = { items = { itemID, … } } } }
    otherSets = {},     -- aktive Sets anderer Spieler: [key] = { name, set, items = { { id, have } }, time }
    historyDeleted = {}, -- [Eintrags-ID] = Zeitpunkt des Löschens (damit der Abgleich nichts zurückholt)
}

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            -- Nur bei "config" Unterwerte auffüllen, Datentabellen bleiben wie gespeichert
            if k == "config" or k == "weights" or k == "minimap" then ApplyDefaults(target[k], v) end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------
function LC:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage(LC.COLOR .. L["Light Council:|r "] .. msg)
end

-- WoW Forever: Charaktere haben Vor- und Nachnamen ("Anna Müller"), keine Realm-Endung.
-- Nachnamen dürfen deshalb nie abgeschnitten werden (auch nicht an einem Bindestrich).
LC.isForever = (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled())
    or (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18))
    or false

local function NormalizeSpaces(name)
    return (strtrim(tostring(name)):gsub("%s+", " "))
end

-- Name für Anzeige (außerhalb von Forever ohne Realm)
function LC:ShortName(name)
    if not name or name == "" then return name end
    name = NormalizeSpaces(name)
    if self.isForever then return name end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

-- Vergleichsschlüssel (kleingeschrieben, Leerzeichen vereinheitlicht)
function LC:NameKey(name)
    if not name then return nil end
    name = NormalizeSpaces(name)
    if name == "" then return nil end
    if not self.isForever then name = name:gsub("%-.*$", "") end
    return name:lower()
end

-- Vollständiger Name einer Einheit ("Vorname Nachname" in Forever)
function LC:UnitFullName(unit)
    if not UnitExists(unit) then return nil end
    if self.isForever and UnitNameUnmodified then
        local first, last = UnitNameUnmodified(unit)
        if first and last and last ~= "" then return first .. " " .. last end
    end
    if GetUnitName then
        local n = GetUnitName(unit, false)
        if n and n ~= "" then return n end
    end
    return (UnitName(unit))
end

function LC:PlayerName()
    if not self._playerName then
        local n = self:UnitFullName("player")
        -- Nur cachen, wenn der Name vollständig geladen ist
        if n and n ~= UNKNOWNOBJECT then self._playerName = n end
        return n
    end
    return self._playerName
end

-- Zwei Namen gelten als gleich, wenn sie identisch sind oder einer nur der Vorname des anderen ist
-- (der Council kann für Spieler ohne Addon auch nur den Vornamen eintragen).
-- Nur für eingetippte Namen und die Anzeige – Berechtigungen prüfen mit SameName/FindExact.
function LC:NamesMatch(a, b)
    local ka, kb = self:NameKey(a), self:NameKey(b)
    if not ka or not kb then return false end
    if ka == kb then return true end
    -- Ohne Leerzeichen eingetippt: "ShockBrown" soll "Shock Brown" finden
    if ka:gsub(" ", "") == kb:gsub(" ", "") then return true end
    if not ka:find(" ") and kb:find(" ") then return kb:match("^(%S+)") == ka end
    if not kb:find(" ") and ka:find(" ") then return ka:match("^(%S+)") == kb end
    return false
end

function LC:IsMe(name)
    return self:SameName(name, self:PlayerName())
end

-- Sucht einen Namen in einer Tabelle [key] = { name = ... }: erst exakt, dann eindeutiger Vornamen-Treffer
function LC:FindByName(tbl, name)
    local key = self:NameKey(name)
    if not key then return nil end
    if tbl[key] then return tbl[key], key end
    local found, foundKey
    for k, v in pairs(tbl) do
        if self:NamesMatch(k, key) then
            if found then return nil end -- mehrdeutig
            found, foundKey = v, k
        end
    end
    return found, foundKey
end

-- Für Berechtigungen und Absender von Nachrichten: gleicher Name (Groß-/Kleinschreibung und Leerzeichen
-- vereinheitlicht). Anders als NamesMatch ohne den Vergleich „ohne Leerzeichen“ – sonst könnte sich
-- „Ann Amüller“ als „Anna Müller“ ausgeben. Die Vornamen-Regel greift nur, wenn ein Name gar keinen
-- Nachnamen hat (z. B. von Hand eingetragen); in Forever hat jeder Charakter einen.
local function SameKey(ka, kb)
    if not ka or not kb then return false end
    if ka == kb then return true end
    if not ka:find(" ") and kb:find(" ") then return kb:match("^(%S+)") == ka end
    if not kb:find(" ") and ka:find(" ") then return ka:match("^(%S+)") == kb end
    return false
end

function LC:SameName(a, b)
    return SameKey(self:NameKey(a), self:NameKey(b))
end

-- Eintrag in einer Tabelle [NameKey] = …: exakt, sonst ein eindeutiger Treffer nach SameName
function LC:FindExact(tbl, name)
    local key = self:NameKey(name)
    if not key or not tbl then return nil end
    if tbl[key] then return tbl[key], key end
    local found, foundKey
    for k, v in pairs(tbl) do
        if SameKey(k, key) then
            if found then return nil end   -- mehrdeutig
            found, foundKey = v, k
        end
    end
    return found, foundKey
end

function LC:ItemIDFromLink(link)
    if not link then return nil end
    local id = tostring(link):match("item:(%d+)")
    return id and tonumber(id)
end

function LC:ItemLink(itemID)
    if not itemID then return "?" end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = getInfo(itemID)
    if link then return link end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return L["Item #"] .. itemID
end

function LC:ItemIcon(itemID)
    if not itemID then return 134400 end
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID) or 134400
    end
    return GetItemIcon and GetItemIcon(itemID) or 134400
end

function LC:JoinNames(list, lastSep)
    local n = #list
    if n == 0 then return "-" end
    if n == 1 then return list[1] end
    lastSep = lastSep or L[" und "]
    return table.concat(list, ", ", 1, n - 1) .. lastSep .. list[n]
end

-- Kürzt auf höchstens maxBytes Bytes, ohne ein Umlaut-/UTF-8-Zeichen in der Mitte zu zerschneiden
function LC:Utf8Cut(text, maxBytes)
    if #text <= maxBytes then return text end
    text = text:sub(1, maxBytes)
    local k = 0   -- Folgebytes (10xxxxxx) am Ende
    while k < 3 and k < #text do
        local b = text:byte(#text - k)
        if b < 0x80 or b >= 0xC0 then break end
        k = k + 1
    end
    local lead = text:byte(#text - k)
    if lead and lead >= 0xC0 then
        local need = (lead >= 0xF0 and 4) or (lead >= 0xE0 and 3) or 2
        if k + 1 < need then text = text:sub(1, #text - k - 1) end
    end
    return text
end

-- Für empfangene Texte, die angezeigt werden: keine Farb-, Link- oder Texturcodes von anderen zulassen
function LC:SafeText(text, maxLen)
    text = tostring(text or ""):gsub("|", "/"):gsub("[\n\r]", " ")
    if maxLen and #text > maxLen then text = self:Utf8Cut(text, maxLen) end
    return text
end

function LC:CleanText(text, maxLen)
    text = tostring(text or ""):gsub("[~;:|\n\r]", " ")
    text = strtrim(text)
    if maxLen and #text > maxLen then text = self:Utf8Cut(text, maxLen) end
    return text
end

-- Woche: Schlüssel = Zeitpunkt des nächsten Weekly-Resets / 604800
function LC:CurrentWeek()
    local now = GetServerTime()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if untilReset and untilReset > 0 then
        return math.floor((now + untilReset) / 604800)
    end
    -- Fallback: EU-Reset Mittwoch 05:00 UTC
    local ref = 6 * 86400 + 5 * 3600
    return math.floor((now - ref) / 604800) + 1
end

------------------------------------------------------------------------
-- Gruppe / Raid
------------------------------------------------------------------------
-- Liefert [key] = { name, online, rank, isML, unit }
function LC:GetGroupMembers()
    local members = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local rosterName, rank, _, _, _, _, _, online, _, _, isML = GetRaidRosterInfo(i)
            local unit = "raid" .. i
            local name = (self.isForever and self:UnitFullName(unit)) or rosterName
            if name then
                members[self:NameKey(name)] = {
                    name = self:ShortName(name), fullName = name, online = online,
                    rank = rank, isML = isML, unit = unit,
                }
            end
        end
    elseif IsInGroup() then
        local units = { "player", "party1", "party2", "party3", "party4" }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local full
                if self.isForever then
                    full = self:UnitFullName(unit)
                else
                    local name, realm = UnitName(unit)
                    full = (realm and realm ~= "") and (name .. "-" .. realm) or name
                end
                if full then
                    members[self:NameKey(full)] = {
                        name = self:ShortName(full), fullName = full, online = UnitIsConnected(unit),
                        rank = UnitIsGroupLeader(unit) and 2 or 0, unit = unit,
                    }
                end
            end
        end
    else
        local me = self:PlayerName()
        members[self:NameKey(me)] = { name = me, fullName = me, online = true, rank = 2, unit = "player" }
    end
    return members
end

function LC:IsMasterLooter()
    if not IsInGroup() then return false end
    local method, partyID, raidID
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        method, partyID, raidID = C_PartyInfo.GetLootMethod()
    elseif GetLootMethod then
        method, partyID, raidID = GetLootMethod()
    end
    local isMaster = (method == "master")
    if not isMaster and Enum and Enum.LootMethod then
        isMaster = (method ~= nil) and (method == Enum.LootMethod.Masterlooter or method == Enum.LootMethod.MasterLooter)
    end
    if not isMaster then return false end
    if raidID then return UnitIsUnit("raid" .. raidID, "player") end
    return partyID == 0
end

-- Darf dieser Absender eine Council-Abstimmung starten? (Leitung, Assistent oder Plündermeister)
-- Wer Abstimmungen starten und das Loot-Fenster der Raider steuern darf: nur Raidleiter oder Plündermeister.
-- (Nicht jeder Assistent – in vielen Raids haben alle Assist, und eine gefälschte Abstimmung
-- würde die Stimmen des Councils an den Fälscher schicken.)
function LC:IsTrustedLeader(sender)
    if self:IsMe(sender) then return true end
    local m = self:FindExact(self:GetGroupMembers(), sender)
    return m ~= nil and ((m.rank or 0) >= 2 or m.isML == true)
end

function LC:GetCouncilSize()
    return (self.db.config.councilSize == 5) and 5 or 3
end

-- Aktive Council-Mitglieder (höchstens so viele wie die gewählte Größe)
function LC:GetCouncilList()
    local out = {}
    for i, n in ipairs(self.db.config.council) do
        if i > self:GetCouncilSize() then break end
        out[#out + 1] = n
    end
    return out
end

-- Nötige Stimmen: einfache Mehrheit der Council-Größe (3 -> 2, 5 -> 3).
-- Befangene zählen nicht mit; bleiben zu wenige übrig, wird normal gewürfelt.
function LC:CouncilMajority()
    return math.floor(self:GetCouncilSize() / 2) + 1
end

function LC:IsCouncilMember(name)
    for _, n in ipairs(self:GetCouncilList()) do
        if self:SameName(n, name) then return true end
    end
    return false
end

-- Version 0.1.0 hat Namen an Leerzeichen getrennt ("Shock Brown" -> "Shock", "Brown").
-- In Forever hat jeder Charakter einen Nachnamen: einzelne Wörter paarweise wieder zusammensetzen.
function LC:MigrateCouncilNames()
    local list = self.db.config.council
    if not self.isForever or #list < 2 or #list % 2 ~= 0 then return end
    for _, n in ipairs(list) do
        if n:find(" ") then return end
    end
    local merged = {}
    for i = 1, #list, 2 do merged[#merged + 1] = list[i] .. " " .. list[i + 1] end
    self.db.config.council = merged
end

-- Ansage im Raidchat (oder lokal, wenn nicht in Gruppe / Testmodus)
-- warning = true: zusätzlich als Raidwarnung (braucht Leitung oder Assistent, sonst normaler Raidchat)
-- Raidwarnung nur auf dem eigenen Bildschirm (Testmodus) – niemand sonst sieht sie
local function LocalRaidWarning(msg)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.28, b = 0 })
    end
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end

local warnedNoAssist = false

function LC:Announce(msg, test, warning)
    warning = warning and self.db.config.raidWarning
    if test or not IsInGroup() then
        self:Print((warning and L["|cffff4040[Raidwarnung]|r "] or L["|cffff7f00[Raid]|r "]) .. msg)
        if warning then LocalRaidWarning(msg) end
        return
    end
    local channel = IsInRaid() and "RAID" or "PARTY"
    if warning and IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            channel = "RAID_WARNING"
        else
            -- Ohne Leitung/Assistent geht es in den Raidchat; einmal darauf hinweisen und lokal anzeigen
            LocalRaidWarning(msg)
            if not warnedNoAssist then
                warnedNoAssist = true
                self:Print(L["Für Raidwarnungen brauchst du Raidleitung oder Assistent – die Ansage geht deshalb in den Raidchat."])
            end
        end
    end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, channel)
    else
        SendChatMessage(msg, channel)
    end
end

-- Ansage mit Namensliste, bei Bedarf auf mehrere Nachrichten verteilt (max. 255 Zeichen)
function LC:AnnounceList(prefixText, names, test)
    local line = prefixText
    local first = true
    for _, n in ipairs(names) do
        local add = (first and " " or ", ") .. n
        if #line + #add > 240 then
            self:Announce(line, test)
            line = "  ..." .. n
        else
            line = line .. add
        end
        first = false
    end
    self:Announce(line, test)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
LC.eventFrame = frame
local handlers = {}

function LC:On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, LC, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

LC:On("ADDON_LOADED", function(self, name)
    if name ~= ADDON then return end
    LightCouncilDB = LightCouncilDB or {}
    ApplyDefaults(LightCouncilDB, DEFAULTS)
    self.db = LightCouncilDB
    self:SetLanguage(self.db.config.language)
    self:MigrateCouncilNames()
    self.db.prio = nil   -- alte, nicht mehr genutzte Daten entfernen
    if self.OnInitialize then self:OnInitialize() end
end)

------------------------------------------------------------------------
-- Slash-Befehle
------------------------------------------------------------------------
local function ShowHelp()
    LC:Print(L["Befehle:"])
    print(L["  /lc – Hauptfenster öffnen"])
    print(L["  /lc test [Itemlink] – Council-Ablauf lokal testen"])
    print(L["  /lc ci [Itemlink] – Item als Council-Item markieren/entfernen"])
    print(L["  /lc parse <Name> <0-100> – Ø Parse-% eintragen"])
    print(L["  /lc eng <Name> <1-5> – Engagement-Bewertung eintragen"])
    print(L["  /lc anw – Anwesenheit des aktuellen Raids jetzt erfassen"])
    print(L["  /lc log – letzte Entscheidungen im Chat anzeigen"])
    print(L["  /lc abbruch – laufende Abstimmung/Würfelrunde abbrechen"])
    print(L["  /lc minimap – Minimap-Button ein-/ausblenden"])
    print(L["  /lc loot – Loot-Fenster für Raider öffnen/schließen"])
    print(L["  /lc councilreset – gespeicherte Council-Liste vergessen und neu anfragen"])
    print(L["  /lc lang <auto|de|en|fr|es|ru> – Sprache wechseln"])
    print(L["  /lc check – zeigt, wer im Raid Light Council in welcher Version hat"])
    print(L["  /lc tooltip – Infos im Item-Tooltip ein-/ausschalten"])
    print(L["  /lc json – alle Daten als JSON exportieren (für eine Website)"])
    print(L["  /lc json auto – JSON-Datei beim Ausloggen ein-/ausschalten"])
end

SLASH_LIGHTCOUNCIL1 = "/lc"
SLASH_LIGHTCOUNCIL2 = "/lightcouncil"
SlashCmdList["LIGHTCOUNCIL"] = function(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "show" then
        LC:ToggleMainFrame()
    elseif cmd == "help" or cmd == "hilfe" then
        ShowHelp()
    elseif cmd == "sprache" or cmd == "lang" or cmd == "language" then
        local want = (rest or ""):lower()
        local found
        for _, l in ipairs(LC.LANGUAGES) do
            if l.key:lower() == want or l.key:sub(1, 2):lower() == want then found = l.key end
        end
        if not found then
            LC:Print(L["Sprachen: auto, de, en, fr, es, ru – z. B. /lc lang en"])
        else
            LC.db.config.language = found
            LC:Print(L["Sprache gespeichert. Mit /reload wird sie übernommen."])
        end
    elseif cmd == "check" or cmd == "version" then
        LC:CheckRaidVersions()
    elseif cmd == "tooltip" then
        LC.db.config.tooltip = not LC.db.config.tooltip
        LC:Print(LC.db.config.tooltip and L["Item-Tooltips: an."] or L["Item-Tooltips: aus."])
    elseif cmd == "json" then
        if (rest or ""):lower() == "auto" then
            LC.db.config.jsonOnLogout = (LC.db.config.jsonOnLogout == false)
            LC:Print(LC.db.config.jsonOnLogout and L["JSON-Datei beim Ausloggen: an."] or L["JSON-Datei beim Ausloggen: aus."])
        else
            LC:ShowHistoryExport(nil, "json")
        end
    elseif cmd == "councilreset" then
        LC:ResetKnownCouncil()
        LC:Print(L["Gespeicherte Council-Liste gelöscht. Sie wird neu angenommen, sobald Raidleitung, Gildenleitung oder zwei Council-Mitglieder sie schicken."])
    elseif cmd == "test" then
        LC:StartTest(rest)
    elseif cmd == "ci" or cmd == "council" then
        local id = LC:ItemIDFromLink(rest) or tonumber(rest)
        if not id then LC:Print(L["Bitte Itemlink oder Item-ID angeben."]) return end
        if LC.db.councilItems[id] then
            LC.db.councilItems[id] = nil
            LC:Print(LC:ItemLink(id), L["ist kein Council-Item mehr."])
        else
            LC.db.councilItems[id] = true
            LC:Print(LC:ItemLink(id), L["ist jetzt ein Council-Item."])
        end
        LC:RefreshUI()
    elseif cmd == "parse" or cmd == "eng" then
        local name, value = rest:match("^(.-)%s+(%S+)$")
        value = tonumber(value)
        if not name or not value then LC:Print(L["Syntax: /lc "] .. cmd .. L[" <Name> <Wert>"]) return end
        local ok, err
        if cmd == "parse" then ok, err = LC:SetParse(name, value, true)
        else ok, err = LC:SetEngagement(name, value, true) end
        if ok then LC:Print(L["Gespeichert:"], name, cmd, value) else LC:Print(err) end
        LC:RefreshUI()
    elseif cmd == "anw" then
        local n = LC:RecordAttendance(true)
        LC:Print(n .. L[" Spieler für diese Woche als anwesend erfasst."])
        LC:RequestAttendanceSync(true)
        LC:RefreshUI()
    elseif cmd == "log" then
        LC:PrintLog(10)
    elseif cmd == "abbruch" or cmd == "cancel" then
        LC:CancelAll()
    elseif cmd == "loot" or cmd == "raid" then
        LC:ToggleRaidFrame()
    elseif cmd == "minimap" or cmd == "mm" then
        LC:ToggleMinimapButton()
        LC:RefreshUI()
    else
        ShowHelp()
    end
end
