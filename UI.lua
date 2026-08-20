-- UI.lua -----------------------------------------------------------------------
-- Shared visual language + hand-built widgets, matching the EllesmereUI-style
-- mockup: dark #0D1217 panels, #0CD29D accent, custom toggles / sliders /
-- segmented controls. Used by both Options.lua and Debug.lua.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local UI = {}
PRIO.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

UI.C = {
    panel     = { 0.051, 0.071, 0.090 },
    sidebar   = { 0.031, 0.043, 0.057 },
    surface   = { 0.086, 0.110, 0.141 },
    control   = { 0.102, 0.122, 0.161 },
    accent    = { 0.047, 0.824, 0.616 },
    accentDim = { 0.035, 0.42,  0.32  },
    gold      = { 1.0,   0.886, 0.29  },
    text      = { 0.79,  0.83,  0.86  },
    head      = { 0.93,  0.957, 0.973 },
    muted     = { 0.518, 0.58,  0.631 },
    faint     = { 0.353, 0.416, 0.463 },
    slate     = { 0.42,  0.47,  0.52  },
}
local C = UI.C

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------
function UI.Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

function UI.Font(parent, size, c, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, flags)
    c = c or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

-- A filled rounded-ish panel (flat; WoW can't round corners without masks).
function UI.Card(parent, c, borderA)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    c = c or C.surface
    f:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    f:SetBackdropBorderColor(1, 1, 1, borderA or 0.08)
    return f
end

--------------------------------------------------------------------------------
-- Toggle switch
--------------------------------------------------------------------------------
function UI.Toggle(parent, get, set, onChange)
    local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
    t:SetSize(40, 21)
    t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local knob = t:CreateTexture(nil, "OVERLAY")
    knob:SetSize(15, 15)
    local function paint()
        if get() then
            t:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.28)
            t:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
            knob:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            knob:ClearAllPoints(); knob:SetPoint("RIGHT", -3, 0)
        else
            t:SetBackdropColor(C.control[1], C.control[2], C.control[3], 1)
            t:SetBackdropBorderColor(1, 1, 1, 0.10)
            knob:SetColorTexture(C.slate[1], C.slate[2], C.slate[3], 1)
            knob:ClearAllPoints(); knob:SetPoint("LEFT", 3, 0)
        end
    end
    t:SetScript("OnClick", function() set(not get()); paint(); if onChange then onChange() end end)
    t.Update = paint
    paint()
    return t
end

--------------------------------------------------------------------------------
-- Slider: track + accent fill + draggable thumb + numeric value
--------------------------------------------------------------------------------
function UI.Slider(parent, width, minV, maxV, step, get, set, onChange, suffix)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 22)

    local valW = 46
    local track = CreateFrame("Frame", nil, row, "BackdropTemplate")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", -valW, 0)
    track:SetHeight(5)
    track:SetBackdrop({ bgFile = WHITE })
    track:SetBackdropColor(C.control[1], C.control[2], C.control[3], 1)

    local fill = UI.Solid(track, "ARTWORK", C.accent)
    fill:SetPoint("LEFT", 0, 0); fill:SetPoint("TOP", 0, 0); fill:SetPoint("BOTTOM", 0, 0)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(14, 14)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.92, 1, 0.97, 1)

    local val = UI.Font(row, 12, C.muted)
    val:SetPoint("RIGHT", 0, 0)
    val:SetJustifyH("RIGHT")

    local function frac() return (maxV > minV) and ((get() - minV) / (maxV - minV)) or 0 end
    local function redraw()
        local w = track:GetWidth()
        if not w or w <= 0 then w = width - valW end
        local f = math.max(0, math.min(1, frac()))
        fill:SetWidth(math.max(1, w * f))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", w * f, 0)
        val:SetText(tostring(get()) .. (suffix or ""))
    end

    local function setFromCursor()
        local left, w = track:GetLeft(), track:GetWidth()
        local scale = track:GetEffectiveScale()
        if not left or not w or w <= 0 or not scale or scale == 0 then return end
        local mx = GetCursorPosition() / scale
        local f = math.max(0, math.min(1, (mx - left) / w))
        local raw = minV + f * (maxV - minV)
        local snapped = math.floor((raw - minV) / step + 0.5) * step + minV
        snapped = math.max(minV, math.min(maxV, snapped))
        set(snapped); redraw(); if onChange then onChange() end
    end

    local dragging = false
    thumb:SetScript("OnMouseDown", function() dragging = true end)
    thumb:SetScript("OnMouseUp",   function() dragging = false end)
    thumb:SetScript("OnUpdate", function() if dragging then setFromCursor() end end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function() setFromCursor() end)

    row.Update = redraw
    row.thumb = thumb
    C_Timer.After(0, redraw)   -- track width valid next frame
    return row
end

--------------------------------------------------------------------------------
-- Segmented control
--------------------------------------------------------------------------------
function UI.Segmented(parent, choices, get, set, onChange)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    row:SetBackdropColor(C.control[1], C.control[2], C.control[3], 1)
    row:SetBackdropBorderColor(1, 1, 1, 0.08)

    local btns, n = {}, #choices
    local segW = 74
    row:SetSize(segW * n + 6, 28)
    for i, ch in ipairs(choices) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(segW, 22)
        b:SetPoint("LEFT", 3 + (i - 1) * segW, 0)
        local hl = UI.Solid(b, "BACKGROUND", C.accent); hl:SetAllPoints(); hl:Hide()
        b.hl = hl
        local fs = UI.Font(b, 12, C.muted); fs:SetPoint("CENTER"); fs:SetText(ch.text)
        b.fs = fs
        b:SetScript("OnClick", function() set(ch.value); row.Update(); if onChange then onChange() end end)
        btns[i] = b
    end
    row.Update = function()
        for i, ch in ipairs(choices) do
            local on = get() == ch.value
            btns[i].hl:SetShown(on)
            if on then btns[i].fs:SetTextColor(0.02, 0.13, 0.10)
            else btns[i].fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        end
    end
    row.Update()
    return row
end

--------------------------------------------------------------------------------
-- Window shell: movable, styled, with a header band + accent underline.
--------------------------------------------------------------------------------
function UI.Window(name, w, h, titleText, subText)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.98)
    f:SetBackdropBorderColor(1, 1, 1, 0.12)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if name then tinsert(UISpecialFrames, name) end

    local title = UI.Font(f, 22, C.accent)
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText(titleText or "")
    f.title = title

    if subText then
        local sub = UI.Font(f, 12, C.faint)
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
        sub:SetText(subText)
        f.sub = sub
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    f:Hide()   -- start hidden so :Toggle() opens on the FIRST call, not the second
    return f
end

--------------------------------------------------------------------------------
-- Shared popup menu (used by dropdowns). Closes on selection or click-outside.
--------------------------------------------------------------------------------
local menu, catcher, menuScroll, menuContent
local MENU_MAXH = 380
function UI.OpenMenu(anchor, options, onPick, width)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:Hide()
        catcher:SetScript("OnClick", function() menu:Hide() end)
        menu = UI.Card(UIParent, C.sidebar, 0.25)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:Hide()
        menu.buttons = {}
        menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
        menuScroll = CreateFrame("ScrollFrame", nil, menu)
        menuScroll:SetPoint("TOPLEFT", 4, -4)
        menuScroll:SetPoint("BOTTOMRIGHT", -4, 4)
        menuContent = CreateFrame("Frame", nil, menuScroll)
        menuScroll:SetScrollChild(menuContent)
        menuScroll:EnableMouseWheel(true)
        menuScroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            local cur = self:GetVerticalScroll()
            self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 34)))
        end)
    end
    if menu:IsShown() and menu.owner == anchor then menu:Hide(); return end
    for _, b in ipairs(menu.buttons) do b:Hide() end
    wipe(menu.buttons)

    local W = width or math.max(anchor:GetWidth(), 120)
    local RH, y = 22, 2
    for _, o in ipairs(options) do
        local b = CreateFrame("Button", nil, menuContent)
        b:SetSize(W - 10, RH); b:SetPoint("TOPLEFT", 0, -y); y = y + RH
        local hl = UI.Solid(b, "BACKGROUND", C.accent, 0.16); hl:SetAllPoints(); hl:Hide()
        b:SetScript("OnEnter", function() hl:Show() end)
        b:SetScript("OnLeave", function() hl:Hide() end)
        local xoff = 8
        if o.icon then
            local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(16, 16); ic:SetPoint("LEFT", 4, 0)
            ic:SetTexture(o.icon); ic:SetTexCoord(0.1, 0.9, 0.1, 0.9); xoff = 24
        end
        local fs = UI.Font(b, 12, C.text); fs:SetPoint("LEFT", xoff, 0)
        fs:SetPoint("RIGHT", -4, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false); fs:SetText(o.text)
        b:SetScript("OnClick", function() menu:Hide(); onPick(o.value) end)
        menu.buttons[#menu.buttons + 1] = b
    end

    local visH = math.min(y + 2, MENU_MAXH)
    menuContent:SetSize(W - 8, y)
    menu:SetSize(W, visH + 8)
    menuScroll:SetVerticalScroll(0)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu.owner = anchor
    catcher:Show()
    menu:Show()
    menu:Raise()
end

--------------------------------------------------------------------------------
-- Dropdown: a button showing the current option; opens a menu on click.
--------------------------------------------------------------------------------
function UI.Dropdown(parent, width, options, get, set, onChange)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(width, 24)
    dd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    dd:SetBackdropColor(C.control[1], C.control[2], C.control[3], 1)
    dd:SetBackdropBorderColor(1, 1, 1, 0.10)
    local fs = UI.Font(dd, 12, C.text)
    fs:SetPoint("LEFT", 8, 0); fs:SetPoint("RIGHT", -18, 0); fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    local car = UI.Font(dd, 9, C.muted); car:SetPoint("RIGHT", -6, 0); car:SetText("\226\150\188")
    local function labelFor(v)
        for _, o in ipairs(options) do if o.value == v then return o.text end end
        return "\226\128\148"
    end
    dd.Update = function() fs:SetText(labelFor(get())) end
    dd:SetScript("OnClick", function()
        UI.OpenMenu(dd, options, function(v) set(v); dd.Update(); if onChange then onChange() end end, width)
    end)
    dd.Update()
    return dd
end

--------------------------------------------------------------------------------
-- Compact -/+ stepper.
--------------------------------------------------------------------------------
function UI.Stepper(parent, w, minV, maxV, get, set, onChange)
    local f = UI.Card(parent, C.control, 0.08); f:SetSize(w, 24)
    local val = UI.Font(f, 12, C.head); val:SetPoint("CENTER")
    local function upd() val:SetText(tostring(get() or minV)) end
    local function mk(sym, dir, anchor)
        local b = CreateFrame("Button", nil, f); b:SetSize(20, 24); b:SetPoint(anchor)
        local t = UI.Font(b, 13, C.accent); t:SetPoint("CENTER"); t:SetText(sym)
        b:SetScript("OnClick", function()
            local v = math.min(maxV, math.max(minV, (get() or minV) + dir))
            set(v); upd(); if onChange then onChange() end
        end)
    end
    mk("-", -1, "LEFT"); mk("+", 1, "RIGHT")
    f.Update = upd; upd()
    return f
end

return UI
