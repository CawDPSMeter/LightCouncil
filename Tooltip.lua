-- Light Council – Item-Tooltips: Council-Item, Reservierer und Gear-Sets überall anzeigen
-- (Lootfenster, Taschen, Chat-Links, AtlasLoot …). Abschaltbar mit /lc tooltip.
local _, LC = ...
local L = LC.L

local MAX_NAMES = 8

local function NameList(list)
    local names = {}
    for i, n in ipairs(list) do
        if i > MAX_NAMES then
            names[#names + 1] = L("+%d weitere", #list - MAX_NAMES)
            break
        end
        names[#names + 1] = n
    end
    return table.concat(names, ", ")
end

local function AddInfo(tooltip, itemID)
    if not itemID or not LC.db or LC.db.config.tooltip == false then return end
    -- Nicht doppelt eintragen: nur wenn unser Block noch drinsteht. Wurde der Tooltip inzwischen geleert und
    -- neu gefüllt (Vergleichs-Tooltips melden das Leeren nicht immer), ist er kürzer als nach unserem Eintrag.
    if tooltip.lcItemID == itemID and tooltip.NumLines and tooltip:NumLines() >= (tooltip.lcLines or 0) then return end
    local council = LC:IsCouncilItem(itemID)
    local reservers = {}
    for _, r in ipairs(LC:GetReservers(itemID)) do reservers[#reservers + 1] = r.name end
    -- Wer hat das Item in seinem aktiven Gear-Set (und braucht es noch)? Als wichtig markiert zuerst
    local wanted = {}
    if LC.GetAllGearSets then
        for _, s in ipairs(LC:GetAllGearSets()) do
            local info = LC:GearSetRank(s.name, itemID)
            if info and info.inSet then
                wanted[#wanted + 1] = { name = s.name, important = info.important, upgrade = info.upgrade, rank = info.important and 1 or (info.upgrade and 3 or 2) }
            end
        end
        table.sort(wanted, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.name < b.name
        end)
    end
    if not council and #reservers == 0 and #wanted == 0 then return end
    tooltip.lcItemID = itemID
    tooltip:AddLine(" ")
    tooltip:AddLine(LC.COLOR .. "Light Council|r" .. (council and ("  ·  " .. L["Council-Item"]) or ""), 1, 1, 1)
    if #reservers > 0 then
        tooltip:AddLine(L("Reserviert (%d): %s", #reservers, NameList(reservers)), 0.8, 0.8, 0.8, true)
    end
    if #wanted > 0 then
        local names = {}
        for _, w in ipairs(wanted) do names[#names + 1] = (w.important and (LC.STAR .. w.name)) or (w.upgrade and (LC.UPGRADE .. w.name)) or w.name end
        tooltip:AddLine(L("Im Gear-Set (%d): %s", #wanted, NameList(names)), 0.6, 0.85, 0.6, true)
    end
    tooltip.lcLines = tooltip.NumLines and tooltip:NumLines() or 0
    tooltip:Show()
end

local function OnSetItem(tooltip)
    if not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    AddInfo(tooltip, LC:ItemIDFromLink(link))
end

local function OnClear(tooltip)
    tooltip.lcItemID = nil
    tooltip.lcLines = nil
end

LC:On("PLAYER_LOGIN", function(self)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        -- Neuere Clients
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip and tooltip.AddLine then AddInfo(tooltip, data and data.id) end
        end)
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
            if tt then tt:HookScript("OnTooltipCleared", OnClear) end
        end
    else
        -- Classic: Skript-Hook
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
            if tt then
                tt:HookScript("OnTooltipSetItem", OnSetItem)
                tt:HookScript("OnTooltipCleared", OnClear)
            end
        end
    end
end)
