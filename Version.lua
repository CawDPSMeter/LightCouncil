-- Light Council – Versionen: Hinweis auf neuere Versionen und /lc check
--
-- Nachrichten:
--   VR~version     alle -> Gilde/Raid: meine Version (beim Einloggen und beim Betreten eines Raids)
--   VQ             Leitung -> Raid/Gruppe: bitte Version melden (/lc check)
--   VA~version     alle -> Raid/Gruppe: Antwort auf VQ
local _, LC = ...
local L = LC.L

local SEP = "~"
local CMDS = { VR = true, VQ = true, VA = true }

LC.versions = {}          -- [key] = { name, version, time }
local notified = false     -- Hinweis auf neuere Version nur einmal pro Sitzung
local lastAnswer = 0
local collecting           -- laufendes /lc check

-- Vergleicht zwei Versionen wie "0.14.1": -1, 0 oder 1
function LC:CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return (x < y) and -1 or 1 end
    end
    return 0
end

local function Remember(sender, version)
    version = LC:SafeText(version, 16)
    if not version:match("^%d+[%.%d]*$") then return end
    local key = LC:NameKey(sender)
    if not key then return end
    LC.versions[key] = { name = LC:ShortName(sender), version = version, time = time() }
    if collecting then collecting[key] = LC.versions[key] end
    -- Hinweis nur, wenn Council oder Raidleitung die neuere Version haben (sonst könnte jeder ihn auslösen)
    if not notified and LC:CompareVersions(LC.version, version) < 0
        and (LC:IsTrustedCouncil(sender) or LC:IsTrustedLeader(sender)) then
        notified = true
        LC:Print(L("Eine neuere Version ist verfügbar: %s (du hast %s). Bitte aktualisieren – ältere Versionen haben bekannte Schwachstellen.", version, LC.version))
    end
end

local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

function LC:BroadcastVersion(channel)
    if channel then self:SendLow(strjoin(SEP, "VR", self.version), channel) end
end

-- /lc check: wer im Raid hat Light Council in welcher Version?
function LC:CheckRaidVersions()
    local channel = GroupChannel()
    if not channel then
        self:Print(L["Du bist in keiner Gruppe."])
        return
    end
    collecting = {}
    collecting[self:NameKey(self:PlayerName())] = { name = self:PlayerName(), version = self.version }
    self:Send("VQ", channel)
    self:Print(L["Frage Versionen ab …"])
    C_Timer.After(5, function()
        local found = collecting
        collecting = nil
        local newest = LC.version
        for _, v in pairs(found) do
            if LC:CompareVersions(v.version, newest) > 0 then newest = v.version end
        end
        local current, old, missing = {}, {}, {}
        for key, m in pairs(LC:GetGroupMembers()) do
            local v = found[key] or (LC:FindByName(found, m.name))
            if not v then
                missing[#missing + 1] = m.name .. (m.online and "" or L[" (offline)"])
            elseif LC:CompareVersions(v.version, newest) < 0 then
                old[#old + 1] = m.name .. " (" .. v.version .. ")"
            else
                current[#current + 1] = m.name
            end
        end
        table.sort(current); table.sort(old); table.sort(missing)
        LC:Print(L("Versionen im Raid (neueste: %s):", newest))
        print("  |cff6ae08f" .. L["Aktuell"] .. " (" .. #current .. "):|r " .. (#current > 0 and table.concat(current, ", ") or "–"))
        print("  |cffffc040" .. L["Veraltet"] .. " (" .. #old .. "):|r " .. (#old > 0 and table.concat(old, ", ") or "–"))
        print("  |cffff6070" .. L["Ohne Addon"] .. " (" .. #missing .. "):|r " .. (#missing > 0 and table.concat(missing, ", ") or "–"))
    end)
end

local baseOnComm = LC.OnComm
function LC:OnComm(msg, sender, channel)
    local cmd, rest = msg:match("^(%u+)~?(.*)$")
    if cmd and CMDS[cmd] then
        if self:IsMe(sender) then return end
        if cmd == "VQ" then
            -- Nur auf Anfragen aus der eigenen Gruppe, höchstens alle 30 Sekunden und leicht verzögert –
            -- sonst könnte jemand den ganzen Raid ständig antworten lassen
            if self:FindExact(self:GetGroupMembers(), sender) and GetTime() - lastAnswer >= 30 then
                lastAnswer = GetTime()
                local ch = GroupChannel()
                if ch then
                    C_Timer.After(math.random() * 2, function() LC:SendLow(strjoin(SEP, "VA", LC.version), ch) end)
                end
            end
        else
            Remember(sender, rest)
        end
        return
    end
    return baseOnComm(self, msg, sender, channel)
end

local wasInRaid = false
LC:On("GROUP_ROSTER_UPDATE", function(self)
    local inRaid = IsInRaid()
    if inRaid and not wasInRaid then
        C_Timer.After(5 + math.random() * 5, function()
            if IsInRaid() then LC:BroadcastVersion("RAID") end
        end)
    end
    wasInRaid = inRaid
end)

LC:On("PLAYER_LOGIN", function(self)
    wasInRaid = IsInRaid()
    C_Timer.After(25 + math.random() * 10, function()
        if IsInGuild() then LC:BroadcastVersion("GUILD") end
        if IsInRaid() then LC:BroadcastVersion("RAID") end
    end)
end)
