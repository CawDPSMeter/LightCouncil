-- Light Council – Hauptfenster, Seite: Protokoll
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
-- Seite: Protokoll
------------------------------------------------------------------------
local function CreateLogPage(p)
    local y = PageHeader(p, L["Protokoll"], L["Jede Entscheidung mit Stimmen und Begründung – kann bei Fragen offengelegt werden."])
    local box = Card(p)
    box:SetPoint("TOPLEFT", 0, -y)
    box:SetPoint("BOTTOMRIGHT", 0, 40)
    T:Skin(box, C.bgDark)
    local sf, content = T:Scroll(box)
    sf:SetPoint("TOPLEFT", 12, -10)
    sf:SetPoint("BOTTOMRIGHT", -18, 10)
    p.text = T:Text(content, 11, C.text)
    p.text:SetPoint("TOPLEFT", 0, 0)
    p.text:SetWidth(CW - 50)
    p.text:SetSpacing(3)
    p.content = content

    local post = T:Button(p, L["Letzte 10 in den Chat"], 160, 26, "default", function() LC:PrintLog(10) end)
    post:SetPoint("BOTTOMLEFT", 0, 0)
    Tip(post, L["In den Chat"], L["Zeigt die letzten 10 Entscheidungen in deinem Chatfenster (nur für dich sichtbar)."])
    local clear = T:Button(p, L["Protokoll leeren"], 130, 26, "danger", function() StaticPopup_Show("LIGHTCOUNCIL_CLEAR_LOG") end)
    clear:SetPoint("BOTTOMRIGHT", 0, 0)

    StaticPopupDialogs["LIGHTCOUNCIL_CLEAR_LOG"] = {
        text = L["Light Council: Das gesamte Protokoll löschen?"],
        button1 = YES, button2 = NO,
        OnAccept = function() wipe(LC.db.log) LC:RefreshUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

local function RefreshLog()
    local p = pages.log
    local log = LC.db.log
    if #log == 0 then
        p.text:SetText(H.muted .. L["Noch keine Einträge. Jede Council-Entscheidung und jede Würfelrunde landet hier.|r"])
    else
        local parts = {}
        for i = #log, math.max(1, #log - 60), -1 do
            parts[#parts + 1] = LC:FormatLogEntry(log[i])
        end
        p.text:SetText(table.concat(parts, "\n\n"))
    end
    p.content:SetHeight(p.text:GetStringHeight() + 10)
end


U.CreateLogPage, U.RefreshLog = CreateLogPage, RefreshLog
