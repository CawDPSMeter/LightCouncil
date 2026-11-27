-- Light Council – Hauptfenster: Fenster, Navigation und Aktualisierung
-- Die Seiten liegen in UI_Page*.lua, gemeinsame Bausteine in UI_Common.lua.
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI

local main
local pages = U.pages
local nav = {}
local currentTab
local W, HGT, SIDEBAR, PAD, CW = U.W, U.HGT, U.SIDEBAR, U.PAD, U.CW
local Card, PageHeader, Tip, SetupStatus = U.Card, U.PageHeader, U.Tip, U.SetupStatus
local SelectTab -- vorwärts deklariert

local CreateStartPage, RefreshStart = U.CreateStartPage, U.RefreshStart
local CreateLootPage, RefreshLoot = U.CreateLootPage, U.RefreshLoot
local CreateMyResPage, RefreshMyRes = U.CreateMyResPage, U.RefreshMyRes
local CreateReservesPage, RefreshReserves = U.CreateReservesPage, U.RefreshReserves
local CreatePlayersPage, RefreshPlayers = U.CreatePlayersPage, U.RefreshPlayers
local CreateHistoryPage, RefreshHistory = U.CreateHistoryPage, U.RefreshHistory
local CreateLogPage, RefreshLog = U.CreateLogPage, U.RefreshLog
local CreateSettingsPage, RefreshSettings = U.CreateSettingsPage, U.RefreshSettings

------------------------------------------------------------------------
-- Fenster & Navigation
------------------------------------------------------------------------
-- lead = nur für Council, Plündermeister und Raidleitung sichtbar
-- navParent = Seite ohne eigenen Menüeintrag; markiert wird dann der genannte Eintrag
local TABS = {
    { key = "start", label = "Erste Schritte", create = CreateStartPage, refresh = RefreshStart, group = 1, lead = true },
    { key = "loot", label = "Loot", create = CreateLootPage, refresh = RefreshLoot, group = 1, lead = true },
    { key = "reserves", label = "Reservierungen", create = CreateReservesPage, refresh = RefreshReserves, group = 1, lead = true },
    { key = "players", label = "Spieler", create = CreatePlayersPage, refresh = RefreshPlayers, group = 1, lead = true },
    { key = "log", label = "Protokoll", create = CreateLogPage, refresh = RefreshLog, group = 1, lead = true },
    { key = "sets", label = "Mein Gear", create = U.CreateSetsPage, refresh = U.RefreshSets, group = 2 },
    { key = "myres", label = "Meine Reservierung", create = CreateMyResPage, refresh = RefreshMyRes, group = 2 },
    { key = "history", label = "Loot-Historie", create = CreateHistoryPage, refresh = RefreshHistory, group = 2 },
    { key = "settings", label = "Einstellungen", create = CreateSettingsPage, refresh = RefreshSettings, group = 3 },
}
local TAB = {}
for _, t in ipairs(TABS) do TAB[t.key] = t end

-- Council-Bereich anzeigen? Council, Plündermeister, Raidleitung/Assistenz –
-- und solange noch kein Council eingetragen ist (Einrichten durch die Leitung)
local function IsLeadView()
    if LC:AmICouncil() or LC:IsMasterLooter() then return true end
    if IsInGroup() and (UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))) then return true end
    return #LC:GetCouncilList() == 0
end

local function TabVisible(t)
    return not t.navParent and (not t.lead or IsLeadView())
end

-- Menü neu anordnen: nur sichtbare Einträge, Gruppen durch eine feine Linie getrennt
local function LayoutNav()
    local y, lastGroup = 14, nil
    for g = 1, 3 do if nav["div" .. g] then nav["div" .. g]:Hide() end end
    for _, t in ipairs(TABS) do
        local b = nav[t.key]
        if b then
            if TabVisible(t) then
                if lastGroup and t.group ~= lastGroup then
                    local div = nav["div" .. t.group]
                    div:ClearAllPoints()
                    div:SetPoint("TOPLEFT", 16, -(y + 6))
                    div:SetPoint("TOPRIGHT", -16, -(y + 6))
                    div:Show()
                    y = y + 13
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 0, -y)
                b:Show()
                y = y + 38
                lastGroup = t.group
            else
                b:Hide()
            end
        end
    end
end

function SelectTab(key)
    -- Raid-Loot ist seit 0.19 Teil der Gear-Sets (Ansicht „Items“)
    if key == "items" then key, LC.wantSetsView = "sets", "items" end
    if not TAB[key] then key = "sets" end
    currentTab = key
    if key == "settings" then pages.settings.needsLoad = true end
    local navKey = TAB[key].navParent or key
    for _, t in ipairs(TABS) do
        pages[t.key]:SetShown(t.key == key)
        if nav[t.key] then nav[t.key]:SetSelected(t.key == navKey) end
    end
    LC:RefreshUI()
end

local function CreateMainFrame()
    main = T:Window("LightCouncilMainFrame", W, HGT, L["Light Council"], L["Reservierungen + Council · Lootverteilung"], 56)
    main:Hide()

    -- Titelleiste nutzen: rechts Status, Rolle und Schnellzugriffe
    local bar = main.titleBar
    local function Pill(parent)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetHeight(30)
        T:Skin(f, C.panel, C.line)
        f.dot = f:CreateTexture(nil, "ARTWORK")
        f.dot:SetTexture(T.WHITE)
        f.dot:SetSize(8, 8)
        f.dot:SetPoint("LEFT", 12, 0)
        f.text = T:Text(f, 12, C.text, "LEFT", nil, true)
        f.text:SetPoint("LEFT", f.dot, "RIGHT", 9, 0)
        f.text:SetWordWrap(false)
        function f:Set(text, color)
            self.text:SetText(text)
            self.dot:SetVertexColor(color[1], color[2], color[3], 1)
            self:SetWidth(self.text:GetStringWidth() + 40)
        end
        return f
    end
    -- Test-Abstimmung gibt es auf "Erste Schritte" und der leeren Loot-Seite – oben nicht doppelt
    main.btnRaid = T:Button(bar, L["Raider-Ansicht"], 140, 32, "ghost", function() LC:ToggleRaidFrame() end)
    main.btnRaid:SetPoint("RIGHT", main.close, "LEFT", -14, 0)
    Tip(main.btnRaid, L["Raider-Ansicht"], L["Öffnet das Loot-Fenster, das Raider sehen: Items, Reservierungen und Würfel-Knopf."])
    main.rolePill = Pill(bar)
    main.rolePill:SetPoint("RIGHT", main.btnRaid, "LEFT", -18, 0)
    main.statusPill = Pill(bar)
    main.statusPill:SetPoint("RIGHT", main.rolePill, "LEFT", -8, 0)
    -- Erklärung per Maus-Tooltip
    local function PillTip(pill, title, text)
        pill:EnableMouse(true)
        pill:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(text, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        pill:SetScript("OnLeave", GameTooltip_Hide)
    end
    PillTip(main.statusPill, L["Status"], L["Was gerade läuft: Nicht im Raid, Bereit (im Raid), Council stimmt ab, Würfelrunde läuft oder wartende Items."])
    PillTip(main.rolePill, L["Deine Rolle"], L["Raidleitung, Plündermeister und/oder Council – davon hängt ab, was du im Addon tun darfst. Ohne besondere Rolle: Raider."])

    -- Seitenleiste
    local side = CreateFrame("Frame", nil, main, "BackdropTemplate")
    side:SetPoint("TOPLEFT", main.titleBar, "BOTTOMLEFT", 0, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR)
    T:Skin(side, C.bgDark, { 0, 0, 0, 0 })
    local sep = T:Line(side, C.border)
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    local sideGlow = side:CreateTexture(nil, "BORDER")
    sideGlow:SetTexture(T.WHITE)
    sideGlow:SetPoint("TOPLEFT")
    sideGlow:SetPoint("TOPRIGHT", -1, 0)
    sideGlow:SetHeight(140)
    T:Gradient(sideGlow, { 0.62, 0.39, 1, 0.08 }, { 0.62, 0.39, 1, 0 })

    -- Menü: Einträge je nach Rolle (LayoutNav), Gruppen durch eine feine Linie getrennt
    for g = 1, 3 do nav["div" .. g] = T:Line(side, C.line) end
    for _, t in ipairs(TABS) do
        if not t.navParent then
            nav[t.key] = T:NavButton(side, L[t.label], SIDEBAR - 1, function() SelectTab(t.key) end)
        end
    end
    LayoutNav()

    local ver = T:Text(side, 10, C.muted)
    ver:SetPoint("BOTTOMLEFT", 16, 14)
    ver:SetText("v" .. LC.version .. L["  ·  /lc hilfe"])

    for _, t in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, main)
        p:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -PAD)
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        p:Hide()
        pages[t.key] = p
        t.create(p)
    end
    main:SetScript("OnShow", function() LC:RefreshUI() end)
end

-- Startseite, solange die Vorbereitung unvollständig ist, sonst Loot
local function DefaultTab()
    -- Noch kein Council eingetragen und du leitest die Gruppe: erst einrichten
    if #LC:GetCouncilList() == 0 and IsInGroup()
        and (UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))) then
        return "start"
    end
    -- Raider ohne besondere Rolle landen bei ihrem Gear (Set + Reservierung)
    if not LC:AmICouncil() and not LC:IsMasterLooter() then return "sets" end
    local st = SetupStatus()
    if not (st.council.ok and st.softres.ok and st.items.ok) then return "start" end
    return "loot"
end

function LC:ShowMainFrame(tab)
    if not main then CreateMainFrame() end
    main:Show()
    SelectTab(tab or currentTab or DefaultTab())
end

function LC:ToggleMainFrame()
    if main and main:IsShown() then main:Hide() else self:ShowMainFrame() end
end

function LC:RefreshUI()
    if not main or not main:IsShown() then return end
    -- Rolle kann sich ändern (Council-Liste, Plündermeister, Gruppe): Menü anpassen
    LayoutNav()
    local cur = TAB[currentTab]
    if cur and not TabVisible(cur) and not cur.navParent then return SelectTab("sets") end
    for _, t in ipairs(TABS) do
        if t.key == currentTab then t.refresh() end
    end
    local n = #self.lootItems
    nav.loot.badge:SetText(n > 0 and tostring(n) or "")
    local st = SetupStatus()
    local open = 0
    for _, k in ipairs({ "council", "softres", "items" }) do
        if not st[k].ok then open = open + 1 end
    end
    nav.start.badge:SetText(open > 0 and (H.warn .. open .. L[" offen|r"]) or "")
    nav.reserves.badge:SetText((st.softres.pending or 0) > 0 and (H.warn .. st.softres.pending .. L[" Antrag|r"]) or "")

    -- Titelleiste: Status und Rolle
    if self.active then
        main.statusPill:Set(L["Council stimmt ab"], C.accent)
    elseif self.roll then
        main.statusPill:Set(L["Würfelrunde läuft"], C.warn)
    elseif #self.queue > 0 then
        main.statusPill:Set(#self.queue .. L[" Item(s) warten"], C.accentLt)
    elseif IsInRaid() then
        main.statusPill:Set(L["Bereit"], C.good)
    else
        main.statusPill:Set(L["Nicht im Raid"], C.muted)
    end
    local roles = {}
    if self:IsMasterLooter() then roles[#roles + 1] = L["Plündermeister"] end
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then roles[#roles + 1] = L["Raidleitung"] end
    if self:IsCouncilMember(self:PlayerName()) then roles[#roles + 1] = L["Council"] end
    if #roles > 0 then
        main.rolePill:Set(table.concat(roles, " · "), C.accent)
    else
        main.rolePill:Set(L["Raider"], C.muted)
    end
end

-- Titelleiste aktuell halten, wenn sich Gruppe oder Plündermethode ändern
LC:On("GROUP_ROSTER_UPDATE", function(self) self:RefreshUI() end)
LC:On("PARTY_LOOT_METHOD_CHANGED", function(self) self:RefreshUI() end)

LC:On("GET_ITEM_INFO_RECEIVED", function(self)
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.3, function()
        LC._refreshPending = nil
        LC:RefreshUI()
    end)
end)

function LC:OnInitialize()
    self:Print("v" .. self.version .. L[" geladen – |cffd1b5ff/lc|r öffnet das Fenster."])
end

U.SelectTab = function(key) return SelectTab(key) end
