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
local modeBar

local accent = PRIO.color.accent
local gold   = PRIO.color.gold
local WHITE  = "Interface\\Buttons\\WHITE8x8"

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

    -- "No resource yet" dim: a desaturated copy of the same icon, drawn just above it at
    -- partial alpha so an unaffordable spender reads as SLIGHTLY greyed (~half desaturated)
    -- instead of hidden. Shown/hidden per entry in FillIcon.
    f.desat = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.desat:SetPoint("TOPLEFT", 1, -1)
    f.desat:SetPoint("BOTTOMRIGHT", -1, 1)
    f.desat:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.desat:Hide()

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

    -- Advisory alert banner (gold, pulsing) -- e.g. "Keep It Rolling ready -- check your
    -- roll". Parented to UIParent so it can be dragged to its own spot; while UNLOCKED it
    -- shows a placeholder so you can position it. Purely an indicator; the player decides.
    local alert = CreateFrame("Frame", "PRIOAlert", UIParent, "BackdropTemplate")
    alert:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    alert:SetBackdropColor(0, 0, 0, 0.85)
    alert:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.9)
    alert:SetFrameStrata("HIGH")
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    alert:RegisterForDrag("LeftButton")
    alert:SetScript("OnDragStart", function(self)
        if not PRIO.db.locked then self.isMoving = true; self:StartMoving() end
    end)
    alert:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); self.isMoving = false
        local p, _, rp, x, y = self:GetPoint()
        PRIO.db.alertPoint = { p, rp, x, y }
    end)
    alert.icon = alert:CreateTexture(nil, "ARTWORK")
    alert.icon:SetSize(22, 22); alert.icon:SetPoint("LEFT", 5, 0)
    alert.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Keybind chip on the alert icon (same style as the strip icons).
    alert.kb = alert:CreateFontString(nil, "OVERLAY")
    alert.kb:SetPoint("TOPRIGHT", alert.icon, "TOPRIGHT", 2, 2)
    alert.kb:SetTextColor(gold[1], gold[2], gold[3])
    alert.text = alert:CreateFontString(nil, "OVERLAY")
    alert.text:SetPoint("LEFT", alert.icon, "RIGHT", 6, 0)
    alert.text:SetTextColor(gold[1], gold[2], gold[3])
    alert:SetScript("OnUpdate", function(self)
        if self._placeholder then self:SetAlpha(0.55)     -- steady while positioning
        else self:SetAlpha(0.72 + 0.28 * (0.5 + 0.5 * math.sin(GetTime() * 4))) end
    end)
    alert:Hide()
    container.alert = alert


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
    if container.alert then setf(container.alert.text, db.titleSize); setf(container.alert.kb, db.keybindSize) end
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
    -- Alert banner: while unlocked, show a draggable placeholder so it can be positioned;
    -- when locked it hides again (Render re-shows it only for a real alert).
    self:ShowAlert(nil)
end

-- Anchor the alert banner: a saved custom point if it was dragged, else above the strip.
function Display:PositionAlert()
    if not (container and container.alert) then return end
    local a = container.alert
    if a.isMoving then return end
    a:ClearAllPoints()
    local ap = PRIO.db.alertPoint
    if ap then a:SetPoint(ap[1], UIParent, ap[2], ap[3], ap[4])
    else a:SetPoint("BOTTOM", container, "TOP", 0, 26) end
end

-- Show the alert: a real one when `al` is given, else a drag-me placeholder while
-- unlocked, else hidden. Draggable only when unlocked.
function Display:ShowAlert(al)
    if not (container and container.alert) then return end
    local a = container.alert
    local unlocked = not PRIO.db.locked
    if al and PRIO.db.showAlerts ~= false then
        a._placeholder = false
        a.text:SetText(al.text or "")
        a.kb:SetText(PRIO.db.showKeybinds and al.keybind or "")
        if al.texture then a.icon:SetTexture(al.texture); a.icon:Show() else a.icon:Hide() end
    elseif unlocked and PRIO.db.showAlerts ~= false then
        a._placeholder = true
        a.text:SetText("Alert banner \226\128\148 drag to move")
        a.kb:SetText("")
        a.icon:SetTexture(API.SpellTexture(381989))   -- Keep It Rolling icon
        a.icon:Show()
    else
        a:Hide(); return
    end
    local tw = (a.text:GetStringWidth() or 120) + (a.icon:IsShown() and 33 or 12) + 10
    a:SetSize(tw, 28)
    self:PositionAlert()
    a:EnableMouse(unlocked)
    a:Show()
end

--------------------------------------------------------------------------------
-- Render one evaluation result
--------------------------------------------------------------------------------
local function FillIcon(f, data, isPrimary)
    if not data then f:Hide(); return end
    f.icon:SetTexture(data.texture)
    f.kb:SetText(PRIO.db.showKeybinds and data.keybind or "")
    f.name:SetText(PRIO.db.showNames and data.name or "")

    -- Slight desaturation when you can't yet afford this spell (Focus/Maelstrom): a
    -- greyscale copy over the colored icon at half alpha reads as ~50% desaturated.
    if data.noResource then
        f.desat:SetTexture(data.texture)
        f.desat:SetDesaturated(true)
        f.desat:SetAlpha(0.5)
        f.desat:Show()
    else
        f.desat:Hide()
    end

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

    -- Title (during the opener, show a distinct gold OPENER badge).
    if PRIO.db.showTitle and result.specLabel then
        if result.isOpener then
            container.title:SetText(("|cff0cd29f%s|r  |cff5a6a76·|r  |cffffd200\226\150\182 OPENER|r")
                :format(result.specLabel))
        else
            container.title:SetText(("|cff0cd29f%s|r  |cff5a6a76·|r  |cff9aa7b2%s|r")
                :format(result.specLabel, result.modeLabel or ""))
        end
        container.title:Show()
    else
        container.title:Hide()
    end

    -- Advisory alert banner (first active alert; placeholder when unlocked).
    self:ShowAlert(result.alerts and result.alerts[1])

    -- Optional clickable mode buttons under the strip.
    if PRIO.db.showModeButtons then
        local specID = API.GetSpecID()
        local spec = specID and PRIO.specs and PRIO.specs[specID]
        self:BuildModeButtons(spec)
        self:PositionModeBar()
        self:UpdateModeButtons()
        modeBar:Show()
    elseif modeBar then
        modeBar:Hide()
    end
end

--------------------------------------------------------------------------------
-- Mode buttons: an optional clickable row under the display to hot-swap
-- Auto / ST / AoE (spec-driven; execute variants are auto only). These are plain
-- frames that just set db.mode and re-evaluate -- nothing secure, safe in combat.
--------------------------------------------------------------------------------
local function StyleModeButton(b, active)
    -- Active = accent-filled; inactive = dark. Text stays WHITE either way.
    if active then
        b:SetBackdropColor(accent[1], accent[2], accent[3], 0.9)
        b:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    else
        b:SetBackdropColor(0, 0, 0, 0.7)
        b:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.4)
    end
    b.text:SetTextColor(1, 1, 1, 1)
end

function Display:UpdateModeButtons()
    if not modeBar then return end
    local cur = PRIO.db.mode or "auto"
    for _, b in ipairs(modeBar.buttons) do StyleModeButton(b, b.value == cur) end
end

local function SaveModeBarPoint()
    if not modeBar then return end
    local p, _, rp, x, y = modeBar:GetPoint()
    PRIO.db.modeBarPoint = { p, rp, x, y }
end

-- Anchor the bar: a saved custom point if the user dragged it, else under the strip.
function Display:PositionModeBar()
    if not modeBar or modeBar.isMoving then return end
    modeBar:ClearAllPoints()
    local mp = PRIO.db.modeBarPoint
    if mp then
        modeBar:SetPoint(mp[1], UIParent, mp[2], mp[3], mp[4])
    else
        modeBar:SetPoint("TOP", container, "BOTTOM", 0, -18)
    end
end

function Display:BuildModeButtons(spec)
    if not modeBar then
        modeBar = CreateFrame("Frame", "PRIOModeBar", UIParent)
        modeBar:SetMovable(true)
        modeBar:SetClampedToScreen(true)
        modeBar.buttons = {}
    end
    local key = (spec and spec.key) or "none"
    if modeBar._specKey == key and #modeBar.buttons > 0 then return end
    modeBar._specKey = key
    for _, b in ipairs(modeBar.buttons) do b:Hide(); b:SetParent(nil) end
    wipe(modeBar.buttons)

    -- Auto + the spec's base modes. Drop the AUTO-ONLY variants the engine swaps in on its
    -- own -- execute range (_execute) and phase/form (_meta, e.g. Devourer's Void Meta) --
    -- since you never pick those by hand; that also keeps the bar from overflowing.
    local defs = { { value = "auto", text = "Auto" } }
    local modes = PRIO.Cond and PRIO.Cond.SpecModes and PRIO.Cond.SpecModes(spec) or {}
    for _, m in ipairs(modes) do
        local v = tostring(m.value)
        if not (v:find("_execute") or v:find("_meta")) then defs[#defs + 1] = m end
    end

    local font = PRIO.db.font or "Fonts\\FRIZQT__.TTF"
    local BH, GAP, PAD, MINW = 18, 4, 14, 44
    local x = 0
    for _, d in ipairs(defs) do
        local b = CreateFrame("Button", nil, modeBar, "BackdropTemplate")
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetPoint("CENTER")
        pcall(b.text.SetFont, b.text, font, 11, "OUTLINE"); b.text:SetText(d.text)
        -- Auto-size each button to its label (min width) so longer labels don't clip.
        local bw = math.max(MINW, math.ceil(b.text:GetStringWidth() + 0.5) + PAD)
        b:SetSize(bw, BH); b:SetPoint("LEFT", x, 0)
        b.value = d.value
        b:SetScript("OnClick", function()
            PRIO.db.mode = d.value
            if PRIO.Tick then PRIO:Tick() end
            Display:UpdateModeButtons()
        end)
        -- Drag any button to move the whole bar (only when the display is unlocked).
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function()
            if not PRIO.db.locked then modeBar.isMoving = true; modeBar:StartMoving() end
        end)
        b:SetScript("OnDragStop", function()
            modeBar:StopMovingOrSizing(); modeBar.isMoving = false; SaveModeBarPoint()
        end)
        modeBar.buttons[#modeBar.buttons + 1] = b
        x = x + bw + GAP
    end
    modeBar:SetSize(math.max(1, x - GAP), BH)
    self:PositionModeBar()
end

function Display:Hide()
    if container then container:Hide() end
    if modeBar then modeBar:Hide() end
    -- Keep the alert placeholder up while unlocked so it can still be positioned when the
    -- strip itself is hidden (e.g. out of combat); otherwise hide it.
    if container and container.alert then
        if PRIO.db.locked then container.alert:Hide() else self:ShowAlert(nil) end
    end
end

-- Called by Options when geometry settings change.
function Display:Refresh()
    self:EnsureCreated()
    self:ApplyPoint()
    self:ApplyFonts()
    self:Layout()
    self:ApplyLock()
end
