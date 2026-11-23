-- Light Council – Minimap-Button (Standard-Look wie LibDBIcon) und Addon-Compartment
local _, LC = ...

local button
local ICON = "Interface\\AddOns\\LightCouncil\\Media\\IconLC"   -- Buchstaben "LC"

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(LC.db.config.minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    LC.db.config.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Light Council", 0.82, 0.71, 1)
    GameTooltip:AddLine("|cffffffffLinksklick:|r Fenster öffnen/schließen", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffRechtsklick:|r Einstellungen", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffZiehen:|r Button verschieben", 0.8, 0.8, 0.8)
    if LC.active then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Council stimmt gerade ab …", 0.82, 0.71, 1)
    elseif LC.roll then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Würfelrunde läuft …", 0.82, 0.71, 1)
    end
    GameTooltip:Show()
end

local function CreateButton()
    -- Gleicher Aufbau wie LibDBIcon, damit der Button zu den anderen an der Minimap passt
    button = CreateFrame("Button", "LightCouncilMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -5)
    button.icon = icon

    button:SetScript("OnMouseDown", function() icon:SetSize(18, 18) icon:SetPoint("TOPLEFT", 8, -6) end)
    button:SetScript("OnMouseUp", function() icon:SetSize(20, 20) icon:SetPoint("TOPLEFT", 7, -5) end)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            LC:ShowMainFrame("settings")
        else
            LC:ToggleMainFrame()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
end

function LC:UpdateMinimapButton()
    if self.db.config.minimap.hide then
        if button then button:Hide() end
        return
    end
    if not button then CreateButton() end
    button:Show()
    UpdatePosition()
end

function LC:ToggleMinimapButton()
    local cfg = self.db.config.minimap
    cfg.hide = not cfg.hide
    self:UpdateMinimapButton()
    self:Print(cfg.hide and "Minimap-Button ausgeblendet (/lc minimap zum Einblenden)." or "Minimap-Button eingeblendet.")
end

LC:On("PLAYER_LOGIN", function(self)
    self:UpdateMinimapButton()
end)

-- Eintrag im Addon-Menü an der Minimap (Addon Compartment), falls der Client es anbietet
function LightCouncil_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then
        LC:ShowMainFrame("settings")
    else
        LC:ToggleMainFrame()
    end
end
