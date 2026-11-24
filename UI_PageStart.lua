-- Light Council – Hauptfenster, Seite: Erste Schritte
local _, LC = ...
local L = LC.L
local T = LC.T
local C = T.C
local H = T.HEX
local U = LC.UI
local pages, CW = U.pages, U.CW
local Card, PageHeader, Tip, AcceptLinks = U.Card, U.PageHeader, U.Tip, U.AcceptLinks
local SetupStatus, Segmented, ChipBar, SourceButton = U.SetupStatus, U.Segmented, U.ChipBar, U.SourceButton
local ReserveRaids, IdsFromText, ItemIcons = U.ReserveRaids, U.IdsFromText, U.ItemIcons
local ITEM_ROW, BOSS_W = U.ITEM_ROW, U.BOSS_W
local function SelectTab(key) return U.SelectTab(key) end

------------------------------------------------------------------------
-- Seite: Start
------------------------------------------------------------------------
local STEPS = {
    { key = "council", title = "Council festlegen", tab = "settings", button = "Eintragen", desc = "3 oder 5 Council-Mitglieder mit Vor- und Nachnamen." },
    { key = "softres", title = "Reservierungen sammeln", tab = "reserves", button = "Übersicht", desc = "Raider reservieren selbst im Addon; der Council bestätigt automatisch." },
    { key = "items", title = "Council-Items markieren", tab = "items", button = "Items öffnen", desc = "Unter Gear-Sets → Items per Häkchen „Council“ – nur bei diesen Items entscheidet der Council." },
    { key = "ml", title = "Master Loot aktivieren", desc = "Voraussetzung, damit das Addon den Loot sieht und vergeben kann." },
}

local function CreateStartPage(p)
    -- Begrüßung mit Logo
    local hero = Card(p, 110)
    hero:SetPoint("TOPLEFT")
    hero:SetWidth(CW)
    local glow = hero:CreateTexture(nil, "BORDER")
    glow:SetTexture(T.WHITE)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    T:Gradient(glow, { 0.62, 0.39, 1, 0.14 }, { 0.62, 0.39, 1, 0 })
    local logo = hero:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(T.LOGO)
    logo:SetSize(88, 88)
    logo:SetPoint("TOPLEFT", 14, -12)
    local ht = T:Text(hero, 20, C.text, "LEFT", nil, true)
    ht:SetPoint("TOPLEFT", 118, -20)
    ht:SetText(L["Willkommen bei Light Council"])
    local hs = T:Text(hero, 12, C.muted)
    hs:SetPoint("TOPLEFT", ht, "BOTTOMLEFT", 0, -8)
    hs:SetWidth(CW - 140)
    hs:SetSpacing(3)
    hs:SetText(L["Raider reservieren ihre Items direkt im Addon – einmal gespeichert, ist die Wahl gesperrt und nur mit Freigabe des Councils änderbar. "]
        .. L["Bei markierten Council-Items stimmt der Council (3 oder 5 Personen) kurz ab – "]
        .. L["die Entscheidung wird per Raidwarnung angesagt. Raider mit dem Addon bekommen ein Loot-Fenster mit Würfel-Knopf, "]
        .. L["ohne Addon läuft alles wie gewohnt über den Raidchat."])
    -- Höhe an den Text anpassen, damit nichts gequetscht wird
    local heroH = math.max(112, 20 + ht:GetStringHeight() + 8 + hs:GetStringHeight() + 22)
    hero:SetHeight(heroH)

    -- Checkliste
    local y = heroH + 22
    local lt = T:Text(p, 14, C.text, "LEFT", nil, true)
    lt:SetPoint("TOPLEFT", 0, -y)
    lt:SetText(L["Vor dem Raid"])
    y = y + 28

    p.steps = {}
    for i, step in ipairs(STEPS) do
        local row = Card(p, 62)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(CW)
        row.num = T:Text(row, 16, C.muted, "CENTER", nil, true)
        row.num:SetPoint("LEFT", 10, 0)
        row.num:SetWidth(40)
        row.title = T:Text(row, 14, C.text, "LEFT", nil, true)
        row.title:SetPoint("TOPLEFT", 60, -12)
        row.title:SetText(L[step.title])
        row.sub = T:Text(row, 12, C.muted)
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
        row.sub:SetWidth(CW - 220)
        row.sub:SetWordWrap(false)
        row.stripe = row:CreateTexture(nil, "ARTWORK")
        row.stripe:SetTexture(T.WHITE)
        row.stripe:SetPoint("TOPLEFT", 1, -1)
        row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
        row.stripe:SetWidth(3)
        if step.tab then
            row.btn = T:Button(row, L[step.button], 130, 32, "default", function() SelectTab(step.tab) end)
            row.btn:SetPoint("RIGHT", -14, 0)
        end
        row.step = step
        row.index = i
        p.steps[i] = row
        y = y + 62 + 8
    end

    -- Schnellaktion
    y = y + 14
    local test = T:Button(p, L["Test-Abstimmung starten"], 220, 34, "primary", function() LC:StartTest("") end)
    test:SetPoint("TOPLEFT", 0, -y)
    Tip(test, L["Test-Abstimmung"], L["Spielt den kompletten Ablauf mit Beispiel-Spielern durch: Popup, Abstimmung, Würfeln. Ansagen erscheinen nur in deinem Chat."])
    local tt = T:Text(p, 12, C.muted)
    tt:SetPoint("LEFT", test, "RIGHT", 14, 0)
    tt:SetWidth(CW - 240)
    tt:SetText(L["Probier den Ablauf einmal alleine aus – nichts davon geht in den Raidchat."])
end

local function RefreshStart()
    local p = pages.start
    local st = SetupStatus()
    for _, row in ipairs(p.steps) do
        local s = st[row.step.key]
        row.sub:SetText(s.text)
        if s.ok then
            row.num:SetText(H.good .. "OK|r")
            row.stripe:SetVertexColor(unpack(C.good))
            if row.btn then row.btn:SetText(row.step.button == "Eintragen" and L["Ändern"] or L["Bearbeiten"]) end
        else
            row.num:SetText(H.accentLt .. row.index .. "|r")
            row.stripe:SetVertexColor(unpack(C.accent))
            if row.btn then row.btn:SetText(L[row.step.button]) end
        end
    end
end


U.CreateStartPage, U.RefreshStart = CreateStartPage, RefreshStart
