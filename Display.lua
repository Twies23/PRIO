-- Display.lua ------------------------------------------------------------------
-- The on-screen strip: one primary icon + a queue of upcoming icons. Purely an
-- indicator (no secure/action templates), so there is nothing to taint in combat.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local Display = {}
PRIO.Display = Display

local MAX_ICONS = 6      -- 1 primary + up to 5 queue, created once
local icons = {}
local container

local accent = PRIO.color.accent
local gold   = PRIO.color.gold

--------------------------------------------------------------------------------
-- Icon construction
--------------------------------------------------------------------------------
local function CreateIcon(name)
    local f = CreateFrame("Frame", "PRIOIcon" .. name, container)

    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.bg:SetPoint("TOPLEFT", -2, 2)
    f.bg:SetPoint("BOTTOMRIGHT", 2, -2)
    f.bg:SetColorTexture(0, 0, 0, 0.9)

    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.glow:SetPoint("TOPLEFT", -4, 4)
    f.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    f.glow:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    f.glow:Hide()

    -- Pulse the primary glow and the proc flash via OnUpdate (textures have no
    -- animation groups).
    f:SetScript("OnUpdate", function(self)
        if self.glow:IsShown() then
            self.glow:SetAlpha(0.4 + 0.35 * (0.5 + 0.5 * math.sin(GetTime() * 4)))
        end
        if self.flash:IsShown() then
            self.flash:SetAlpha(0.55 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 6)))
        end
    end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim default border

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(true)

    -- Proc flash: the WoW rotation-helper glow, shown when a cast is empowered
    -- (Lava Surge -> instant Lava Burst, Stormkeeper stack -> instant bolt).
    f.flash = f:CreateTexture(nil, "OVERLAY")
    f.flash:SetPoint("TOPLEFT", -6, 6)
    f.flash:SetPoint("BOTTOMRIGHT", 6, -6)
    f.flash:SetBlendMode("ADD")
    if not pcall(f.flash.SetAtlas, f.flash, "UI-HUD-RotationHelper-ProcAltGlow-2x") then
        f.flash:SetColorTexture(gold[1], gold[2], gold[3], 0.6)
    end
    f.flash:Hide()

    f.kb = f:CreateFontString(nil, "OVERLAY")
    f.kb:SetPoint("TOPRIGHT", 2, 2)
    f.kb:SetTextColor(gold[1], gold[2], gold[3])

    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.name:SetWidth(90)
    f.name:SetWordWrap(false)

    f:Hide()
    return f
end

function Display:EnsureCreated()
    if container then return end
    container = CreateFrame("Frame", "PRIOContainer", UIParent, "BackdropTemplate")
    container:SetClampedToScreen(true)
    container:SetSize(64, 64)

    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    container:SetBackdropColor(0, 0, 0, 0)
    container:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0)

    container:SetMovable(true)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if not PRIO.db.locked then self:StartMoving() end
    end)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        PRIO.db.point = { p, rp, x, y }
    end)

    icons.primary = CreateIcon("Primary")
    icons.primary:SetPoint("CENTER", container, "CENTER", 0, 0)
    for i = 1, MAX_ICONS - 1 do
        icons[i] = CreateIcon("Q" .. i)
    end

    -- Title line above the primary (accent spec name + muted mode), matching the mockup.
    container.title = container:CreateFontString(nil, "OVERLAY")
    container.title:SetPoint("BOTTOM", icons.primary, "TOP", 0, 8)
    container.title:SetJustifyH("CENTER")


    self:ApplyPoint()
    self:ApplyLock()
    self:ApplyFonts()
    self:Layout()
end

--------------------------------------------------------------------------------
-- Layout / geometry
--------------------------------------------------------------------------------
function Display:ApplyPoint()
    if not container then return end
    local p = PRIO.db.point or { "CENTER", "CENTER", 0, -180 }
    container:ClearAllPoints()
    container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    container:SetScale(PRIO.db.scale or 1)
end

local function Anchor(icon, prev, growth, spacing)
    icon:ClearAllPoints()
    if growth == "LEFT" then
        icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
    elseif growth == "UP" then
        icon:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
    elseif growth == "DOWN" then
        icon:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
    else -- RIGHT
        icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
    end
end

function Display:Layout()
    if not container then return end
    local db = PRIO.db
    local ps, qs, sp, growth = db.primarySize, db.queueSize, db.spacing, db.growth

    icons.primary:SetSize(ps, ps)
    container:SetSize(ps, ps)

    local prev = icons.primary
    for i = 1, MAX_ICONS - 1 do
        local f = icons[i]
        f:SetSize(qs, qs)
        Anchor(f, prev, growth, sp)   -- consistent gap primary->queue and queue->queue
        prev = f
    end
end

function Display:ApplyFonts()
    if not container then return end
    local db = PRIO.db
    local font = db.font or "Fonts\\FRIZQT__.TTF"
    local function setf(fs, size)
        if fs then pcall(fs.SetFont, fs, font, size or 12, "OUTLINE") end
    end
    setf(container.title, db.titleSize)
    setf(icons.primary.kb, db.keybindSize)
    setf(icons.primary.name, db.nameSize)
    for i = 1, MAX_ICONS - 1 do
        setf(icons[i].kb, db.keybindSize)
        setf(icons[i].name, db.nameSize)
    end
end

function Display:ApplyLock()
    if not container then return end
    local unlocked = not PRIO.db.locked
    container:EnableMouse(unlocked)
    container:SetBackdropBorderColor(accent[1], accent[2], accent[3], unlocked and 0.8 or 0)
    container:SetBackdropColor(0, 0, 0, unlocked and 0.35 or 0)
end

--------------------------------------------------------------------------------
-- Render one evaluation result
--------------------------------------------------------------------------------
local function FillIcon(f, data, isPrimary)
    if not data then f:Hide(); return end
    f.icon:SetTexture(data.texture)
    f.kb:SetText(PRIO.db.showKeybinds and data.keybind or "")
    f.name:SetText(PRIO.db.showNames and data.name or "")

    -- Cooldown swipe: the primary shows the global cooldown (so it sweeps each
    -- cast); queue icons show any real cooldown they carry.
    if PRIO.db.showCooldown then
        if isPrimary then
            -- Match the real cast time while casting; otherwise the GCD sweep.
            if not API.ApplyCastSwipe(f.cd) then API.ApplyGCDSwipe(f.cd) end
        else
            API.ApplyCooldownSwipe(f.cd, data.id)
        end
    else
        f.cd:Clear()
    end

    if isPrimary and PRIO.db.showGlow then f.glow:Show() else f.glow:Hide() end
    if data.flash and PRIO.db.showFlash then f.flash:Show() else f.flash:Hide() end
    f:Show()
end

function Display:Render(result)
    self:EnsureCreated()
    if not result or not result.primary then
        self:Hide()
        return
    end
    container:Show()
    FillIcon(icons.primary, result.primary, true)

    local q = result.queue or {}
    for i = 1, MAX_ICONS - 1 do
        if i <= (PRIO.db.numQueue or 3) and q[i] then
            FillIcon(icons[i], q[i], false)
        else
            icons[i]:Hide()
        end
    end

    -- Title
    if PRIO.db.showTitle and result.specLabel then
        container.title:SetText(("|cff0cd29f%s|r  |cff5a6a76·|r  |cff9aa7b2%s|r")
            :format(result.specLabel, result.modeLabel or ""))
        container.title:Show()
    else
        container.title:Hide()
    end

end

function Display:Hide()
    if container then container:Hide() end
end

-- Called by Options when geometry settings change.
function Display:Refresh()
    self:EnsureCreated()
    self:ApplyPoint()
    self:ApplyFonts()
    self:Layout()
    self:ApplyLock()
end
