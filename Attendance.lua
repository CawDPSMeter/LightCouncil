-- Light Council – Anwesenheit: Abgleich zwischen Council und Leitung
--
-- Bisher hat jeder nur selbst gezählt: Wer eine Woche nicht im Raid war, hatte diese Woche gar nicht
-- und dadurch andere Prozente als der Rest. Jetzt wird die Anwesenheit zusammengeführt
-- (wer von irgendeinem Council-Mitglied als anwesend erfasst wurde, gilt als anwesend).
--
-- Nachrichten:
--   AQ~abWoche~digest        Anfrage: digest = o:n:s,o:n:s,… (o = Woche - abWoche, n = Anzahl, s = Prüfsumme)
--   AE~woche~Name,Name,…     Council -> Anfragender (Whisper) bzw. Gilde (neu erfasste Spieler)
--
-- Nur Einträge von Council-Mitgliedern werden übernommen. Der Abgleich läuft nachrangig.
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { AQ = true, AE = true }
local SYNC_WEEKS = 20    -- so viele Wochen werden höchstens abgeglichen

local function Field(name)
    return (LC:CleanText(name or "", 40):gsub(",", ""))
end

-- Reihenfolgeunabhängige Prüfsumme über die Spieler einer Woche (16 Bit, damit 20 Wochen in eine Nachricht passen)
local function WeekSum(list)
    local n, s = 0, 0
    for key in pairs(list or {}) do
        n = n + 1
        local h = 0
        for i = 1, #key do h = (h * 31 + key:byte(i)) % 16777213 end
        s = (s + h) % 16777213
    end
    return n, s % 65521
end

local function SyncFrom()
    local weeks = math.min(math.max(LC.db.config.attendanceWeeks or 8, 1), SYNC_WEEKS)
    return LC:CurrentWeek() - weeks + 1
end

local function Digest(from)
    -- Von der neuesten Woche rückwärts, höchstens ~220 Zeichen (Addon-Nachrichten haben maximal 255 Byte).
    -- Fehlt eine alte Woche im Digest, schickt der Council sie einfach mit.
    local parts, len = {}, 0
    for w = LC:CurrentWeek(), from, -1 do
        local list = LC.db.attendance[w]
        if list and next(list) then
            local n, s = WeekSum(list)
            local part = string.format("%d:%d:%x", w - from, n, s)
            if len + #part + 1 > 220 then break end
            table.insert(parts, 1, part)
            len = len + #part + 1
        end
    end
    return table.concat(parts, ",")
end

local function ParseDigest(from, text)
    local out = {}
    for o, n, s in (text or ""):gmatch("(%d+):(%d+):(%x+)") do
        out[from + tonumber(o)] = tonumber(n) .. ":" .. tonumber(s, 16)
    end
    return out
end

-- Namen einer Woche in Nachrichten unter 240 Zeichen packen
local function SendWeek(week, names, channel, target)
    local head = "AE" .. SEP .. week .. SEP
    local cur = ""
    for _, name in ipairs(names) do
        local f = Field(name)
        if f ~= "" then
            if cur ~= "" and #head + #cur + #f + 1 > 240 then
                LC:SendLow(head .. cur, channel, target)
                cur = f
            else
                cur = (cur == "") and f or (cur .. "," .. f)
            end
        end
    end
    if cur ~= "" then LC:SendLow(head .. cur, channel, target) end
end

local function WeekNames(list)
    local names = {}
    for _, name in pairs(list or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

------------------------------------------------------------------------
-- Anfragen
------------------------------------------------------------------------
-- Den Score brauchen nur Council und Leitung (wer selbst eine Council-Liste eingetragen hat).
local function NeedsAttendance()
    return LC:AmICouncil() or LC:HasOwnCouncilSetup()
end

local function BuildRequest()
    local from = SyncFrom()
    return strjoin(SEP, "AQ", tostring(from), Digest(from))
end

function LC:RequestAttendanceSync(manual)
    if not manual and not NeedsAttendance() then return false end
    local msg = BuildRequest()
    local sent = false
    if IsInGuild() then self:SendLow(msg, "GUILD") sent = true end
    if IsInRaid() then self:SendLow(msg, "RAID") sent = true
    elseif IsInGroup() then self:SendLow(msg, "PARTY") sent = true end
    if manual then
        if sent then
            self:Print(L["Anwesenheit: Abgleich angefragt – fehlende Wochen kommen vom Council, sobald jemand online ist."])
        else
            self:Print(L["Anwesenheit: Kein Abgleich möglich – du bist in keiner Gilde oder Gruppe."])
        end
    end
    return sent
end

local answered, askedBack = {}, {}

local function Answer(requester, from, digestText)
    if not LC:AmICouncil() then return end
    local key = LC:NameKey(requester)
    if answered[key] and time() - answered[key] < 60 then return end
    answered[key] = time()

    local current = LC:CurrentWeek()
    from = math.max(from, current - SYNC_WEEKS + 1)
    local theirs = ParseDigest(from, digestText)
    local theyHaveMore = false
    for w = from, current do
        local list = LC.db.attendance[w]
        local mine
        if list and next(list) then
            local n, s = WeekSum(list)
            mine = n .. ":" .. s
            if theirs[w] ~= mine then SendWeek(w, WeekNames(list), "WHISPER", requester) end
        end
        if theirs[w] and theirs[w] ~= mine then theyHaveMore = true end
    end

    -- Hat ein anderes Council-Mitglied Wochen, die bei mir fehlen oder abweichen: selbst nachfragen
    if theyHaveMore and LC:IsTrustedCouncil(requester)
        and not (askedBack[key] and time() - askedBack[key] < 120) then
        askedBack[key] = time()
        LC:SendLow(BuildRequest(), "WHISPER", requester)
    end
end

------------------------------------------------------------------------
-- Empfang und Weitergabe
------------------------------------------------------------------------
local function Receive(sender, week, payload)
    if not LC:IsTrustedCouncil(sender) then return end
    week = tonumber(week)
    local current = LC:CurrentWeek()
    if not week or week > current + 1 or week < current - 52 then return end
    local list = LC.db.attendance[week] or {}
    local added = 0
    for name in (payload or ""):gmatch("[^,]+") do
        name = strtrim(name)
        local key = LC:NameKey(name)
        if key and not list[key] then
            list[key] = name
            added = added + 1
        end
    end
    if next(list) then LC.db.attendance[week] = list end
    if added > 0 then LC:RefreshUI() end
end

-- Neu erfasste Spieler an die Gilde, damit Council-Mitglieder außerhalb des Raids sie auch haben
function LC:ShareAttendance(week, names)
    if not names or #names == 0 or not self:AmICouncil() then return end
    if IsInGuild() then
        SendWeek(week, names, "GUILD")
    elseif IsInRaid() then
        SendWeek(week, names, "RAID")
    end
end

------------------------------------------------------------------------
-- Einklinken
------------------------------------------------------------------------
local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~(.*)$")
    if cmd and CMDS[cmd] then
        if self:IsMe(sender) then return end
        local a, b = rest:match("^([^~]*)~?(.*)$")
        if cmd == "AQ" then
            local from = tonumber(a)
            if from then
                C_Timer.After(2 + math.random() * 6, function() Answer(sender, from, b) end)
            end
        else
            Receive(sender, a, b)
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

LC:On("PLAYER_LOGIN", function(self)
    C_Timer.After(30, function() LC:RequestAttendanceSync(false) end)
end)
