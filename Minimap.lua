-- Minimap.lua ------------------------------------------------------------------
-- A lightweight minimap button (no LibDBIcon dependency). Left-click opens the
-- options window, right-click toggles the debug window. Drag it around the ring.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local C   = PRIO.UI and PRIO.UI.C or {}
local ACCENT = C.accent or { 0.047, 0.824, 0.616 }
local PANEL  = C.panel  or { 0.051, 0.071, 0.090 }
local FONT   = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local btn = CreateFrame("Button", "PRIOMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetMovable(true)

-- Branded logo built from primitives (no external art): an accent ring around a
-- dark disc with a bold accent "P", in the EllesmereUI palette.
local function roundDisc(size, color, layer)
    local t = btn:CreateTexture(nil, layer or "BACKGROUND")
    t:SetSize(size, size)
    t:SetPoint("CENTER", 0, 1)
    t:SetColorTexture(color[1], color[2], color[3], 1)
    local mask = btn:CreateMaskTexture()
    mask:SetAllPoints(t)
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:AddMaskTexture(mask)
    return t
end

local ring = roundDisc(23, ACCENT, "BACKGROUND")          -- accent ring (outer)
local disc = roundDisc(19, PANEL, "BORDER")               -- dark disc (inner)

local logo = btn:CreateFontString(nil, "ARTWORK")
logo:SetFont(FONT, 15, "OUTLINE")
logo:SetPoint("CENTER", 0, 1)
logo:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
logo:SetText("P")

-- Brighten the "P" to white on hover for a bit of life.
local function setGlow(on)
    if on then logo:SetTextColor(1, 1, 1, 1)
    else logo:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
end

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
    setGlow(true)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff0cd29fPRIO|r")
    GameTooltip:AddLine("Left-click: options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: debug window", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() setGlow(false); GameTooltip:Hide() end)

function PRIO.UpdateMinimapButton()
    if PRIO.db and PRIO.db.minimapShow == false then
        btn:Hide()
    else
        btn:Show()
        UpdatePosition()
    end
end

PRIO:On("PLAYER_ENTERING_WORLD", function() PRIO.UpdateMinimapButton() end)
