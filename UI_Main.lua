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
local CreateItemsPage, RefreshItems = U.CreateItemsPage, U.RefreshItems
local CreateMyResPage, RefreshMyRes = U.CreateMyResPage, U.RefreshMyRes
local CreateReservesPage, RefreshReserves = U.CreateReservesPage, U.RefreshReserves
local CreatePlayersPage, RefreshPlayers = U.CreatePlayersPage, U.RefreshPlayers
local CreateHistoryPage, RefreshHistory = U.CreateHistoryPage, U.RefreshHistory
local CreateLogPage, RefreshLog = U.CreateLogPage, U.RefreshLog
local CreateSettingsPage, RefreshSettings = U.CreateSettingsPage, U.RefreshSettings

------------------------------------------------------------------------
-- Fenster & Navigation
------------------------------------------------------------------------
local TABS = {
    { key = "start", label = "Erste Schritte", create = CreateStartPage, refresh = RefreshStart, group = "ÜBERSICHT" },
    { key = "loot", label = "Loot", create = CreateLootPage, refresh = RefreshLoot },
    { key = "myres", label = "Meine Reservierung", create = CreateMyResPage, refresh = RefreshMyRes },
    { key = "history", label = "Loot-Historie", create = CreateHistoryPage, refresh = RefreshHistory },
    { key = "items", label = "Raid-Loot", create = CreateItemsPage, refresh = RefreshItems, group = "VORBEREITUNG" },
    { key = "reserves", label = "Reservierungen", create = CreateReservesPage, refresh = RefreshReserves },
    { key = "players", label = "Spieler", create = CreatePlayersPage, refresh = RefreshPlayers, group = "COUNCIL" },
    { key = "log", label = "Protokoll", create = CreateLogPage, refresh = RefreshLog },
    { key = "settings", label = "Einstellungen", create = CreateSettingsPage, refresh = RefreshSettings, group = "ADDON" },
}

function SelectTab(key)
    currentTab = key
    if key == "settings" then pages.settings.needsLoad = true end
    for _, t in ipairs(TABS) do
        pages[t.key]:SetShown(t.key == key)
        nav[t.key]:SetSelected(t.key == key)
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
    Tip(main.btnRaid, L["Raider-Ansicht"], L["Öffnet das Loot-Fenster, das Raider sehen: Items, Prio und Würfel-Knopf."])
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

    -- Menü: nur klickbare Einträge; Gruppen werden durch eine feine Linie getrennt
    local y = 14
    for i, t in ipairs(TABS) do
        if t.group and i > 1 then
            local div = T:Line(side, C.line)
            div:SetPoint("TOPLEFT", 16, -(y + 6))
            div:SetPoint("TOPRIGHT", -16, -(y + 6))
            y = y + 13
        end
        local b = T:NavButton(side, L[t.label], SIDEBAR - 1, function() SelectTab(t.key) end)
        b:SetPoint("TOPLEFT", 0, -y)
        nav[t.key] = b
        y = y + 38
    end

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
    -- Raider ohne besondere Rolle landen direkt bei ihrer Reservierung
    if not LC:AmICouncil() and not LC:IsMasterLooter() then return "myres" end
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
    for _, t in ipairs(TABS) do
        if t.key == currentTab then t.refresh() end
    end
    local n = #self.lootItems
    nav.loot.badge:SetText(n > 0 and tostring(n) or "")
    local ci = 0
    for _ in pairs(self.db.councilItems) do ci = ci + 1 end
    nav.items.badge:SetText(ci > 0 and tostring(ci) or "")
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
