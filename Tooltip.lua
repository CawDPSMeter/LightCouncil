-- Light Council – Item-Tooltips: Council-Item, Prio und Reservierer überall anzeigen
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
    if tooltip.lcItemID == itemID then return end   -- nicht doppelt eintragen
    local council = LC:IsCouncilItem(itemID)
    local prio = LC:GetPrio(itemID)
    local reservers = {}
    for _, r in ipairs(LC:GetReservers(itemID)) do reservers[#reservers + 1] = r.name end
    if not council and not (prio and #prio > 0) and #reservers == 0 then return end
    tooltip.lcItemID = itemID
    tooltip:AddLine(" ")
    tooltip:AddLine(LC.COLOR .. "Light Council|r" .. (council and ("  ·  " .. L["Council-Item"]) or ""), 1, 1, 1)
    if prio and #prio > 0 then
        tooltip:AddLine(L["Prio:|r "]:gsub("|r", "") .. table.concat(prio, " > "), 0.82, 0.71, 1, true)
    end
    if #reservers > 0 then
        tooltip:AddLine(L("Reserviert (%d): %s", #reservers, NameList(reservers)), 0.8, 0.8, 0.8, true)
    end
    tooltip:Show()
end

local function OnSetItem(tooltip)
    if not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    AddInfo(tooltip, LC:ItemIDFromLink(link))
end

local function OnClear(tooltip)
    tooltip.lcItemID = nil
end

LC:On("PLAYER_LOGIN", function(self)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        -- Neuere Clients
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip and tooltip.AddLine then AddInfo(tooltip, data and data.id) end
        end)
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
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
