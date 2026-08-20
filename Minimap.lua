-- Minimap.lua ------------------------------------------------------------------
-- A lightweight minimap button (no LibDBIcon dependency). Left-click opens the
-- options window, right-click toggles the debug window. Drag it around the ring.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API

local btn = CreateFrame("Button", "PRIOMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetMovable(true)

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexture("Interface\\Icons\\spell_shaman_stormkeeper")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function UpdatePosition()
    local angle = math.rad(PRIO.db and PRIO.db.minimapAngle or 205)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(angle), r * math.sin(angle))
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    PRIO.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

btn:SetScript("OnDragStart", function() btn:SetScript("OnUpdate", DragUpdate) end)
btn:SetScript("OnDragStop", function() btn:SetScript("OnUpdate", nil) end)

btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
        if PRIO.Debug then PRIO.Debug:Toggle() end
    else
        if PRIO.Options then PRIO.Options:Toggle() end
    end
end)

btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff0cd29fPRIO|r")
    GameTooltip:AddLine("Left-click: options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: debug window", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function PRIO.UpdateMinimapButton()
    if PRIO.db and PRIO.db.minimapShow == false then
        btn:Hide()
    else
        btn:Show()
        UpdatePosition()
    end
end

PRIO:On("PLAYER_ENTERING_WORLD", function() PRIO.UpdateMinimapButton() end)
