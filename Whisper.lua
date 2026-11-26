-- Light Council – Reservieren per Flüstern für Spieler ohne Addon
--
-- Ein Spieler flüstert einem Council-Mitglied:
--   !lc                 seine Reservierungen und die Befehle
--   !lc [Item] [Item]   Items zur Reservierung des Raids hinzufügen, in dem sie droppen
--   !lc - [Item]        Items aus der Reservierung entfernen
--
-- Es gelten dieselben Regeln wie im Addon: Höchstzahl pro Raid, nur Items aus einer Loot-Quelle.
-- Ist die Reservierung schon gesperrt, wird daraus ein Änderungsantrag, über den der Council entscheidet.
-- Nur Council-Mitglieder verarbeiten die Befehle; die Raidleitung ohne Council-Sitz verweist auf den Council.
-- Absender müssen in der Gruppe oder in der Gilde sein. Die Befehle und Antworten werden im Chat ausgeblendet.
local _, LC = ...
local L = LC.L

local TAG = "[LC] "             -- Kennung unserer Antworten (für den Chatfilter)
local REASON = "!lc"            -- Begründung von Änderungsanträgen per Flüstern (sprachunabhängig)
local MIN_GAP = 3               -- Sekunden zwischen zwei Befehlen desselben Absenders
local MAX_PER_MIN = 20          -- Befehle insgesamt pro Minute
local MAX_LEN = 250

local function Enabled()
    return LC.db and LC.db.config.whisperReserve ~= false
end

-- Bin ich zuständig? "council" = verarbeiten, "lead" = nur auf den Council verweisen, nil = ignorieren
local function Role()
    if not Enabled() then return nil end
    if LC:AmICouncil() then return "council" end
    if LC:IsMasterLooter() or (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return "lead" end
end

local function IsCommand(msg)
    return type(msg) == "string" and msg:match("^%s*![lL][cC]%f[%A]") ~= nil
end

------------------------------------------------------------------------
-- Antworten
------------------------------------------------------------------------
local function Whisper(target, text)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, "WHISPER", nil, target)
    else
        SendChatMessage(text, "WHISPER", nil, target)
    end
end

-- Teile zu Nachrichten bis 250 Zeichen zusammenfassen (Itemlinks nie zerschneiden)
local function Reply(target, parts)
    if type(parts) == "string" then parts = { parts } end
    local line = TAG
    for _, part in ipairs(parts) do
        if #line + #part + 1 > MAX_LEN and line ~= TAG then
            Whisper(target, line)
            line = TAG
        end
        line = (line == TAG) and (line .. part) or (line .. " " .. part)
    end
    if line ~= TAG then Whisper(target, line) end
end
LC.WhisperReply = Reply

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------
local function RaidName(key)
    for _, r in ipairs(LC:GetLootDB() or {}) do
        if r.key == key then return r.name end
    end
    return key
end

local function RaidHas(raid, id)
    for _, b in ipairs(raid.bosses or {}) do
        for _, x in ipairs(b.items or {}) do
            if x == id then return true end
        end
    end
    return false
end

-- Raid-Schlüssel eines Items: der aktuelle Raid, wenn es dort droppt, sonst der erste Fundort
local function RaidFor(id)
    local cur = LC:GetCurrentRaid()
    if cur and RaidHas(cur, id) then return cur.key end
    local src = LC:ItemSource(id)
    return src and src.raid.key
end

local function ItemIDs(msg)
    local out, seen = {}, {}
    for id in msg:gmatch("|Hitem:(%d+)") do
        id = tonumber(id)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local function Links(items)
    local t = {}
    for i, id in ipairs(items or {}) do t[i] = LC:ItemLink(id) end
    return t
end

local function Join(items)
    local t = {}
    for i, id in ipairs(items or {}) do t[i] = tostring(id) end
    return table.concat(t, ",")
end

local function Contains(list, id)
    for _, x in ipairs(list or {}) do if x == id then return true end end
    return false
end

-- Absender auflösen: in der Gruppe der volle Name aus dem Roster, sonst Gildenmitglied.
-- Kurz gecacht: Chatfilter (pro Chatfenster) und Ereignis fragen für dieselbe Nachricht mehrfach.
local resolved, nResolved = {}, 0
local function Resolve(sender)
    if nResolved > 200 then wipe(resolved) nResolved = 0 end
    local c = resolved[sender]
    if c and GetTime() - c.at < 10 then return c.name end
    local name
    local m = LC:FindExact(LC:GetGroupMembers(), sender)
    if m then name = m.fullName or m.name
    elseif LC:IsGuildMember(sender) then name = LC:CleanText(sender, 40) end
    if not resolved[sender] then nResolved = nResolved + 1 end
    resolved[sender] = { name = name, at = GetTime() }
    return name
end
-- Gruppe geändert: neu auflösen, damit ein frisch Eingeladener nicht 10 Sek. als „unbekannt“ gilt
LC:On("GROUP_ROSTER_UPDATE", function() wipe(resolved) nResolved = 0 end)

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------
local function Status(sender, name)
    local parts = {}
    for key, R in pairs(LC.db.reserves or {}) do
        local rec = LC:FindExact(R.players, name)
        if rec and #(rec.items or {}) > 0 then
            parts[#parts + 1] = RaidName(key) .. ":"
            for _, l in ipairs(Links(rec.items)) do parts[#parts + 1] = l end
            if rec.pending then parts[#parts + 1] = L["(Änderung beantragt)"] end
            parts[#parts + 1] = "·"
        end
    end
    if #parts == 0 then
        parts[1] = L["Du hast noch nichts reserviert."]
    else
        table.remove(parts)   -- letztes „·“
        table.insert(parts, 1, L["Deine Reservierungen:"])
    end
    Reply(sender, parts)
    Reply(sender, string.format(L["Reservieren: !lc [Item] · Entfernen: !lc - [Item] · bis zu %d Items pro Raid"], LC:MaxReserves()))
end

local function Change(sender, name, ids, remove)
    -- Alle Items müssen aus demselben Raid einer Loot-Quelle stammen
    local raid
    for _, id in ipairs(ids) do
        local r = RaidFor(id)
        if not r then
            Reply(sender, { LC:ItemLink(id), L["droppt in keinem bekannten Raid – nicht reservierbar."] })
            return
        end
        if raid and r ~= raid then
            Reply(sender, L["Bitte nur Items aus einem Raid in einer Nachricht."])
            return
        end
        raid = r
    end

    local R = LC:ResRaid(raid)
    local rec = LC:FindExact(R.players, name)
    local locked = rec and (rec.rev or 0) > 0
    -- Ein offener Antrag wird erst entschieden – sonst hätten die Council-Mitglieder verschiedene Stände
    if locked and rec.pending then
        Reply(sender, L["Es ist schon ein Änderungsantrag offen – warte, bis der Council entschieden hat."])
        return
    end
    local base = (rec and rec.items) or {}
    local new = {}
    for _, id in ipairs(base) do new[#new + 1] = id end

    if remove then
        local kept, removed = {}, false
        for _, id in ipairs(new) do
            if Contains(ids, id) then removed = true else kept[#kept + 1] = id end
        end
        if not removed then
            Reply(sender, L["Diese Items hast du in dem Raid nicht reserviert."])
            return
        end
        new = kept
    else
        local added = false
        for _, id in ipairs(ids) do
            if not Contains(new, id) then new[#new + 1] = id added = true end
        end
        if not added then
            Reply(sender, L["Diese Items hast du bereits reserviert."])
            return
        end
        local max = LC:MaxReserves()
        if #new > max then
            Reply(sender, string.format(L["Höchstens %d Items pro Raid (%s). Entferne zuerst eins mit !lc - [Item]."], max, RaidName(raid)))
            return
        end
    end

    if not locked then
        local ok, err = LC:CouncilSetReservation(raid, name, new)
        if not ok then
            Reply(sender, err or L["Fehler"])
            return
        end
        if #new == 0 then
            Reply(sender, string.format(L["Reservierung für %s gelöscht."], RaidName(raid)))
        else
            local parts = { string.format(L["Reserviert (%s):"], RaidName(raid)) }
            for _, l in ipairs(Links(new)) do parts[#parts + 1] = l end
            Reply(sender, parts)
        end
        LC:Print(string.format(L["%s hat per Flüstern reserviert (%s): %s"], name, RaidName(raid), LC:ItemListText(new)))
        return
    end

    -- Gesperrt: Änderungsantrag für den Council
    rec.pending = { items = new, reason = REASON, time = time() }
    LC:ResSend("YP", raid, tostring(R.epoch or 0), rec.name, Join(new), REASON)
    LC:RebuildReservers()
    LC:RefreshUI()
    local parts = { L["Deine Reservierung ist gesperrt. Änderungsantrag gestellt – der Council entscheidet:"] }
    for _, l in ipairs(Links(new)) do parts[#parts + 1] = l end
    if #new == 0 then parts[#parts + 1] = L["(keine Items)"] end
    Reply(sender, parts)
    LC:Print(string.format(L["%s beantragt per Flüstern eine Änderung (%s): %s. Entscheiden unter „Reservierungen“."], rec.name, RaidName(raid), LC:ItemListText(new)))
end

------------------------------------------------------------------------
-- Empfang
------------------------------------------------------------------------
local lastBy, recent = {}, {}

local function Throttled(key)
    local now = GetTime()
    if now - (lastBy[key] or -999) < MIN_GAP then return true end
    -- gleitendes Fenster: höchstens MAX_PER_MIN Befehle pro Minute insgesamt
    while recent[1] and now - recent[1] > 60 do table.remove(recent, 1) end
    if #recent >= MAX_PER_MIN then return true end
    lastBy[key] = now
    recent[#recent + 1] = now
    return false
end

LC:On("CHAT_MSG_WHISPER", function(self, msg, sender)
    if not IsCommand(msg) or not sender or self:IsMe(sender) then return end
    local role = Role()
    if not role then return end
    local name = Resolve(sender)
    if not name then return end   -- weder Gruppe noch Gilde
    local key = self:NameKey(name)
    if not key or Throttled(key) then return end

    if role == "lead" then
        local council = self:GetCouncilList()
        Reply(sender, (#council > 0)
            and (L["Reservierungen trägt der Council ein – bitte einem von ihnen flüstern: "] .. table.concat(council, ", "))
            or L["Reservierungen trägt der Council ein – es ist noch kein Council eingestellt."])
        return
    end

    local rest = strtrim((msg:gsub("^%s*![lL][cC]", "", 1)))
    local remove = rest:match("^%-") ~= nil
    local ids = ItemIDs(rest)
    if #ids == 0 then
        local word = rest:lower()
        if word ~= "" and word ~= "?" and word ~= "help" and word ~= "hilfe" then
            Reply(sender, L["Kein Item erkannt. Shift-Klick auf ein Item fügt den Link ein."])
        end
        Status(sender, name)
        return
    end
    Change(sender, name, ids, remove)
end)

-- Nach einer Entscheidung über einen Antrag per Flüstern: dem Spieler Bescheid geben
local baseDecide = LC.DecideChange
function LC:DecideChange(raid, name, approve)
    local R = self.db.reserves and self.db.reserves[raid]
    local p = R and self:FindByName(R.players, name)
    local viaWhisper = p and p.pending and p.pending.reason == REASON
    local target = p and p.name
    local ok, msg = baseDecide(self, raid, name, approve)
    if ok and viaWhisper and target then
        local parts = { approve and string.format(L["Deine Änderung (%s) wurde freigegeben:"], RaidName(raid))
            or string.format(L["Deine Änderung (%s) wurde abgelehnt – die Reservierung bleibt:"], RaidName(raid)) }
        for _, l in ipairs(Links(p.items)) do parts[#parts + 1] = l end
        Reply(target, parts)
    end
    return ok, msg
end

------------------------------------------------------------------------
-- Chatfilter: Befehle und Antworten nicht im Chat anzeigen
------------------------------------------------------------------------
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", function(_, _, msg, sender)
        if IsCommand(msg) and Role() then
            local ok, name = pcall(Resolve, sender)
            if ok and name then return true end
        end
        return false
    end)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(_, _, msg)
        return Enabled() and type(msg) == "string" and msg:sub(1, #TAG) == TAG
    end)
end
