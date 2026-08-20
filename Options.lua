-- Options.lua ------------------------------------------------------------------
-- Standalone options window built to the EllesmereUI-style mockup: a grouped
-- sidebar on the left, a header band with an accent underline, and pages of
-- hand-built widgets (from UI.lua) on the right.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local UI  = PRIO.UI
local C   = UI.C
local Options = {}
PRIO.Options = Options

local win, sidebar, header, scroll, content
local navButtons = {}
local kids = {}          -- content widgets, rebuilt per page
local currentPage = "display"

local SIDEBAR_W = 192

local function AfterChange()
    if PRIO.Display then PRIO.Display:Refresh() end
    PRIO:StartTicker(); PRIO:Tick()
end

--------------------------------------------------------------------------------
-- Content layout helpers (a running Y cursor)
--------------------------------------------------------------------------------
local cursorY, contentW

local function Track(f) kids[#kids + 1] = f; return f end

local function Section(text)
    cursorY = cursorY + 10
    local r = Track(CreateFrame("Frame", nil, content))
    r:SetSize(contentW, 20)
    r:SetPoint("TOPLEFT", 0, -cursorY)
    local fs = UI.Font(r, 11, C.faint, "")
    fs:SetPoint("LEFT", 0, 0)
    fs:SetText(text:upper())
    local line = UI.Solid(r, "ARTWORK", { 1, 1, 1 }, 0.06)
    line:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", 0, 0); line:SetHeight(1)
    cursorY = cursorY + 26
end

-- Labeled setting row; build(widgetParent, row) anchors the control to the RIGHT.
local function SettingRow(label, h, build)
    local r = Track(CreateFrame("Frame", nil, content))
    r:SetSize(contentW, h or 30)
    r:SetPoint("TOPLEFT", 0, -cursorY)
    local fs = UI.Font(r, 13, C.text)
    fs:SetPoint("LEFT", 0, 0)
    fs:SetText(label)
    build(r)
    cursorY = cursorY + (h or 30) + 6
    return r
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
local Pages = {}

function Pages.display()
    local db = PRIO.db
    Section("Icons")
    SettingRow("Icons in queue", 26, function(r)
        local s = UI.Slider(r, 200, 0, 5, 1, function() return db.numQueue end,
            function(v) db.numQueue = v end, AfterChange)
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Primary size", 26, function(r)
        local s = UI.Slider(r, 200, 32, 96, 2, function() return db.primarySize end,
            function(v) db.primarySize = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Queue size", 26, function(r)
        local s = UI.Slider(r, 200, 24, 80, 2, function() return db.queueSize end,
            function(v) db.queueSize = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Spacing", 26, function(r)
        local s = UI.Slider(r, 200, 0, 30, 1, function() return db.spacing end,
            function(v) db.spacing = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Growth direction", 30, function(r)
        local seg = UI.Segmented(r, {
            { value = "RIGHT", text = "Right" }, { value = "LEFT", text = "Left" },
            { value = "UP", text = "Up" },       { value = "DOWN", text = "Down" },
        }, function() return db.growth end, function(v) db.growth = v end, AfterChange)
        seg:SetPoint("RIGHT", 0, 0)
    end)

    Section("Text & Style")
    local function tog(label, key)
        SettingRow(label, 24, function(r)
            local t = UI.Toggle(r, function() return db[key] end, function(v) db[key] = v end, AfterChange)
            t:SetPoint("RIGHT", 0, 0)
        end)
    end
    tog("Show keybinds", "showKeybinds")
    tog("Show spell names", "showNames")
    tog("Show title", "showTitle")
    tog("Primary glow", "showGlow")
    tog("Cooldown swipe", "showCooldown")
    tog("Proc flash", "showFlash")

    Section("Fonts")
    SettingRow("Font", 30, function(r)
        local dd = UI.Dropdown(r, 200, {
            { value = "Fonts\\FRIZQT__.TTF", text = "Friz Quadrata" },
            { value = "Fonts\\ARIALN.TTF",   text = "Arial Narrow" },
            { value = "Fonts\\MORPHEUS.TTF", text = "Morpheus" },
            { value = "Fonts\\SKURRI.TTF",   text = "Skurri" },
            { value = "Fonts\\2002.TTF",     text = "2002" },
        }, function() return db.font end, function(v) db.font = v end, AfterChange)
        dd:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Title size", 26, function(r)
        local s = UI.Slider(r, 200, 8, 24, 1, function() return db.titleSize end,
            function(v) db.titleSize = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Keybind size", 26, function(r)
        local s = UI.Slider(r, 200, 8, 28, 1, function() return db.keybindSize end,
            function(v) db.keybindSize = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Name size", 26, function(r)
        local s = UI.Slider(r, 200, 8, 24, 1, function() return db.nameSize end,
            function(v) db.nameSize = v end, AfterChange, " px")
        s:SetPoint("RIGHT", 0, 0)
    end)
end

--------------------------------------------------------------------------------
-- Priority editing helpers
--------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local Cond  = PRIO.Cond
local chipColor = { buff = C.accent, tgt = { 0.54, 0.71, 1 }, res = { 0.88, 0.63, 0.23 } }
local picker

local function CurrentSpec() local id = API.GetSpecID(); return id and PRIO.specs and PRIO.specs[id] end
local function CurrentMode() local m = PRIO.db.mode; return (m ~= "auto") and m or "st" end

local function IsCustom(spec, mode)
    local cp = PRIO.db.customPriorities
    return (cp and cp[spec.key] and cp[spec.key][mode]) and true or false
end

-- Copy-on-write: materialize an editable custom list for spec/mode from the default.
local function EnsureCustom(spec, mode)
    local cp = PRIO.db.customPriorities
    cp[spec.key] = cp[spec.key] or {}
    if not cp[spec.key][mode] then
        local copy = {}
        for i, e in ipairs(spec.priority[mode] or {}) do
            copy[i] = {
                spell    = (type(e.spell) == "number") and e.spell or spec.spells[e.spell],
                cond     = Cond.Copy(e.cond),
                ignoreCD = e.ignoreCD or nil,
            }
        end
        cp[spec.key][mode] = copy
    end
    return cp[spec.key][mode]
end

local function IconButton(parent, glyph, enabled, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 16)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(C.control[1], C.control[2], C.control[3], enabled and 1 or 0.5)
    b:SetBackdropBorderColor(1, 1, 1, 0.08)
    local fs = UI.Font(b, 12, enabled and C.accent or C.faint)
    fs:SetPoint("CENTER"); fs:SetText(glyph)
    if enabled then b:SetScript("OnClick", onClick) end
    return b
end

local function ShowSpellPicker(anchor, spec, onPick)
    if not picker then
        picker = UI.Card(win, C.sidebar, 0.18)
        picker:SetFrameStrata("DIALOG")
        picker.buttons = {}
    end
    for _, b in ipairs(picker.buttons) do b:Hide() end
    wipe(picker.buttons)
    local W, RH, y = 210, 24, 6
    for _, key in ipairs(spec.pickable or {}) do
        local sid = spec.spells[key]
        if sid then
            local b = CreateFrame("Button", nil, picker)
            b:SetSize(W - 8, RH); b:SetPoint("TOPLEFT", 4, -y); y = y + RH
            local hl = UI.Solid(b, "BACKGROUND", C.accent, 0.14); hl:SetAllPoints(); hl:Hide()
            b:SetScript("OnEnter", function() hl:Show() end)
            b:SetScript("OnLeave", function() hl:Hide() end)
            local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("LEFT", 4, 0)
            ic:SetTexture(API.SpellTexture(sid)); ic:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            local nm = UI.Font(b, 12, C.text); nm:SetPoint("LEFT", ic, "RIGHT", 8, 0)
            nm:SetText(API.SpellName(sid))
            b:SetScript("OnClick", function() picker:Hide(); onPick(sid) end)
            picker.buttons[#picker.buttons + 1] = b
        end
    end
    picker:SetSize(W, y + 6)
    picker:ClearAllPoints()
    picker:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    picker:Show()
end

function Pages.rotation()
    local db = PRIO.db
    if picker then picker:Hide() end
    local spec = CurrentSpec()
    local mode = CurrentMode()

    Section("Spec & Mode")
    SettingRow("Specialization", 30, function(r)
        local box = UI.Card(r, C.control, 0.08)
        box:SetSize(200, 26); box:SetPoint("RIGHT", 0, 0)
        local sw = UI.Solid(box, "ARTWORK", { 0.11, 0.44, 0.84 })
        sw:SetSize(16, 16); sw:SetPoint("LEFT", 7, 0)
        local fs = UI.Font(box, 13, C.head)
        fs:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        fs:SetText(spec and (spec.label .. " Shaman") or "Unsupported spec")
    end)
    SettingRow("Mode", 30, function(r)
        local seg = UI.Segmented(r, {
            { value = "auto", text = "Auto" }, { value = "st", text = "ST" },
            { value = "cleave", text = "Cleave" }, { value = "aoe", text = "AoE" },
        }, function() return db.mode end, function(v) db.mode = v end, function()
            AfterChange(); Options:ShowPage("rotation")
        end)
        seg:SetPoint("RIGHT", 0, 0)
    end)

    if not spec then
        Section("Priority")
        local none = Track(UI.Font(content, 13, C.faint))
        none:SetPoint("TOPLEFT", 0, -cursorY)
        none:SetText("Log in on Elemental Shaman to edit the priority list.")
        cursorY = cursorY + 30
        return
    end

    -- Header row: list status + reset
    Section("Priority  ·  " .. mode:upper() .. (IsCustom(spec, mode) and "   (custom)" or "   (default)"))
    if IsCustom(spec, mode) then
        SettingRow("This list is customized", 26, function(r)
            local b = UI.Card(r, C.control, 0.1); b:SetSize(130, 24); b:SetPoint("RIGHT", 0, 0)
            local bb = CreateFrame("Button", nil, b); bb:SetAllPoints()
            local fs = UI.Font(b, 12, C.accent); fs:SetPoint("CENTER"); fs:SetText("Reset to default")
            bb:SetScript("OnClick", function()
                PRIO.db.customPriorities[spec.key][mode] = nil
                AfterChange(); Options:ShowPage("rotation")
            end)
        end)
    end

    local function refresh() AfterChange(); Options:ShowPage("rotation") end
    local list = PRIO.Engine:EffectiveList(spec.key, mode)

    for i, e in ipairs(list) do
        local sid = PRIO.Engine:EntrySpellID(e)
        local row = Track(UI.Card(content, C.surface, 0.07))
        row:SetSize(contentW, 42)
        row:SetPoint("TOPLEFT", 0, -cursorY)
        cursorY = cursorY + 48

        -- reorder up/down (materialize custom on use)
        local up = IconButton(row, "\226\150\178", i > 1, function()
            local L = EnsureCustom(spec, mode); L[i], L[i - 1] = L[i - 1], L[i]; refresh()
        end)
        up:SetPoint("TOPLEFT", 6, -3)
        local dn = IconButton(row, "\226\150\188", i < #list, function()
            local L = EnsureCustom(spec, mode); L[i], L[i + 1] = L[i + 1], L[i]; refresh()
        end)
        dn:SetPoint("BOTTOMLEFT", 6, 3)

        local idx = UI.Font(row, 11, C.faint); idx:SetPoint("LEFT", 30, 0); idx:SetText(tostring(i))

        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(28, 28); ic:SetPoint("LEFT", 44, 0)
        ic:SetTexture(sid and API.SpellTexture(sid)); ic:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        ic:SetDesaturated(e.off and true or false)

        local nm = UI.Font(row, 13, e.off and C.faint or C.head)
        nm:SetPoint("LEFT", ic, "RIGHT", 10, 6); nm:SetWidth(120); nm:SetJustifyH("LEFT")
        nm:SetWordWrap(false); nm:SetText(sid and API.SpellName(sid) or tostring(e.spell))
        local pid = UI.Font(row, 10, C.faint); pid:SetPoint("LEFT", ic, "RIGHT", 10, -8)
        pid:SetText(sid and ("#" .. sid) or "")

        -- remove
        local rm = IconButton(row, "\195\151", true, function()
            local L = EnsureCustom(spec, mode); table.remove(L, i); refresh()
        end)
        rm:SetSize(18, 18); rm:SetPoint("RIGHT", -8, 0)

        -- enable toggle
        local t = UI.Toggle(row, function() return not e.off end, function(v)
            local L = EnsureCustom(spec, mode); L[i].off = (not v) and true or nil
        end, refresh)
        t:SetPoint("RIGHT", rm, "LEFT", -10, 0)

        -- condition chip (click to open the editor)
        local summary = Cond.Summary(e.cond, sid)
        local isAlways = (summary == "always")
        local cc = isAlways and C.muted or C.accent
        local chip = CreateFrame("Button", nil, row, "BackdropTemplate")
        chip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        chip:SetBackdropColor(cc[1], cc[2], cc[3], isAlways and 0.06 or 0.14)
        chip:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.3)
        local ct = UI.Font(chip, 11, cc); ct:SetPoint("CENTER", 0, 0)
        ct:SetWidth(150); ct:SetJustifyH("CENTER"); ct:SetWordWrap(false); ct:SetText(summary)
        chip:SetSize(math.min(164, math.max(50, ct:GetStringWidth() + 18)), 18)
        chip:SetPoint("RIGHT", t, "LEFT", -10, 0)
        chip:SetScript("OnClick", function() Options:OpenCondEditor(spec, mode, i) end)
    end

    -- Add ability
    local addRow = Track(CreateFrame("Button", nil, content, "BackdropTemplate"))
    addRow:SetSize(contentW, 30); addRow:SetPoint("TOPLEFT", 0, -cursorY)
    addRow:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    addRow:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.06)
    addRow:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
    local al = UI.Font(addRow, 13, C.accent); al:SetPoint("CENTER"); al:SetText("+  Add ability")
    addRow:SetScript("OnClick", function()
        ShowSpellPicker(addRow, spec, function(sid)
            local L = EnsureCustom(spec, mode)
            L[#L + 1] = { spell = sid, cond = nil }
            refresh()
        end)
    end)
    cursorY = cursorY + 38
end

--------------------------------------------------------------------------------
-- Condition editor popup: AND/OR groups of clauses, each with dropdowns and an
-- optional spell reference (cross-spell cooldown/buff checks).
--------------------------------------------------------------------------------
local editor
function Options:OpenCondEditor(spec, mode, index)
    local L = EnsureCustom(spec, mode)
    local e = L[index]
    -- Normalize to group form for editing.
    if not e.cond then
        e.cond = { op = "and", clauses = {} }
    elseif not e.cond.clauses then
        e.cond = { op = "and", clauses = { { type = e.cond.type, spell = e.cond.spell, v = e.cond.v } } }
    end
    local cond = e.cond
    local sid  = PRIO.Engine:EntrySpellID(e)

    if not editor then
        editor = UI.Window("PRIOCondEditor", 372, 300, "Conditions", "\226\128\148")
        editor:SetFrameStrata("DIALOG")
        editor.rows = {}
        editor.statusFns = {}
        editor.matchLbl = UI.Font(editor, 12, C.muted)
        editor.matchLbl:SetPoint("TOPLEFT", 20, -64)
        editor.matchLbl:SetText("Match")
        editor.hint = UI.Font(editor, 11, C.faint)
        editor.hint:SetText("\226\151\143 pass   \226\151\143 fail   \226\151\143 not readable (ignored)")
        -- Live status ticker.
        local acc = 0
        editor:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.15 then return end
            acc = 0
            local S = PRIO.Engine and PRIO.Engine:CurrentState()
            for _, fn in ipairs(editor.statusFns) do fn(S) end
        end)
    end
    editor.sub:SetText(sid and API.SpellName(sid) or "")
    -- Colour the hint legend dots (pass / fail / open).
    editor.hint:SetText(
        ("|cff0cd29f\226\151\143|r pass   |cffe0685a\226\151\143|r fail   |cffe0a03a\226\151\143|r not readable (ignored)"))

    -- Spell/aura options for cross-spell reference dropdowns: "Self", the spec's
    -- cast list, and every aura/cooldown the Cooldown Viewer tracks at runtime.
    local spellOpts = { { value = 0, text = "Self (this ability)" } }
    local seen = {}
    for _, key in ipairs(spec.pickable or {}) do
        local s = spec.spells[key]
        if s and not seen[s] then
            seen[s] = true
            spellOpts[#spellOpts + 1] = { value = s, text = API.SpellName(s), icon = API.SpellTexture(s) }
        end
    end
    for _, o in ipairs(API.EnumerateTracked()) do
        if not seen[o.value] then
            seen[o.value] = true
            spellOpts[#spellOpts + 1] = o
        end
    end
    -- Talent options (for "Talent selected / not selected" clauses).
    local talentOpts = { { value = 0, text = "\226\128\148 pick talent \226\128\148" } }
    for _, o in ipairs(API.GetTalentList()) do talentOpts[#talentOpts + 1] = o end

    local function editorChanged()
        AfterChange()
        if currentPage == "rotation" then Options:ShowPage("rotation") end
    end

    -- Match ALL / ANY (rebuilt each open so it captures this cond).
    if editor.seg then editor.seg:Hide() end
    editor.seg = UI.Segmented(editor, {
        { value = "and", text = "ALL" }, { value = "or", text = "ANY" },
    }, function() return cond.op or "and" end, function(v) cond.op = v end, editorChanged)
    editor.seg:SetPoint("TOPLEFT", 72, -60)

    local rebuild
    rebuild = function()
        for _, f in ipairs(editor.rows) do f:Hide() end
        wipe(editor.rows)
        wipe(editor.statusFns)
        local y = 100

        for ci, cl in ipairs(cond.clauses) do
            local rowf = CreateFrame("Frame", nil, editor)
            rowf:SetSize(340, 26); rowf:SetPoint("TOPLEFT", 16, -y); y = y + 32
            editor.rows[#editor.rows + 1] = rowf

            -- live status dot
            local dot = UI.Font(rowf, 12, C.faint); dot:SetPoint("LEFT", 0, 0); dot:SetText("\226\151\143")
            editor.statusFns[#editor.statusFns + 1] = function(S)
                if not S then return end
                local st = Cond.ClauseStatus(cl, S, sid)
                local col = (st == "pass" and C.accent) or (st == "fail" and { 0.88, 0.41, 0.35 }) or { 0.88, 0.63, 0.23 }
                dot:SetTextColor(col[1], col[2], col[3])
            end

            local typeDD = UI.Dropdown(rowf, 120, Cond.types,
                function() return cl.type end,
                function(v)
                    cl.type = v
                    local m = Cond.TypeMeta(v)
                    if m and m.needsValue and not cl.v then cl.v = m.def or 1 end
                    if not (m and m.needsSpell) then cl.spell = nil end
                    rebuild(); editorChanged()
                end)
            typeDD:SetPoint("LEFT", 16, 0)

            local meta = Cond.TypeMeta(cl.type)
            if meta and meta.needsSpell then
                local spDD = UI.Dropdown(rowf, 150, spellOpts,
                    function() return cl.spell or 0 end,
                    function(v) cl.spell = (v ~= 0) and v or nil; editorChanged() end)
                spDD:SetPoint("LEFT", typeDD, "RIGHT", 6, 0)
            elseif meta and meta.needsTalent then
                local tDD = UI.Dropdown(rowf, 150, talentOpts,
                    function() return cl.spell or 0 end,
                    function(v) cl.spell = (v ~= 0) and v or nil; editorChanged() end)
                tDD:SetPoint("LEFT", typeDD, "RIGHT", 6, 0)
            elseif meta and meta.needsValue then
                local st = UI.Stepper(rowf, 74, meta.min or 1, meta.max or 10,
                    function() return cl.v or meta.def or 1 end,
                    function(v) cl.v = v; editorChanged() end)
                st:SetPoint("LEFT", typeDD, "RIGHT", 6, 0)
            end

            local rm = IconButton(rowf, "\195\151", true, function()
                table.remove(cond.clauses, ci); rebuild(); editorChanged()
            end)
            rm:SetSize(18, 18); rm:SetPoint("RIGHT", 0, 0)
        end

        if #cond.clauses == 0 then
            local none = CreateFrame("Frame", nil, editor)
            none:SetSize(332, 22); none:SetPoint("TOPLEFT", 20, -y); y = y + 26
            editor.rows[#editor.rows + 1] = none
            local fs = UI.Font(none, 12, C.faint); fs:SetPoint("LEFT", 0, 0)
            fs:SetText("No conditions \226\128\148 always recommended.")
        end

        local addb = CreateFrame("Button", nil, editor, "BackdropTemplate")
        addb:SetSize(332, 26); addb:SetPoint("TOPLEFT", 20, -y); y = y + 34
        addb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        addb:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.06)
        addb:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
        local af = UI.Font(addb, 12, C.accent); af:SetPoint("CENTER"); af:SetText("+  Add condition")
        addb:SetScript("OnClick", function()
            cond.clauses[#cond.clauses + 1] = { type = "cdReady", spell = nil }
            rebuild(); editorChanged()
        end)
        editor.rows[#editor.rows + 1] = addb

        editor.hint:ClearAllPoints()
        editor.hint:SetPoint("TOPLEFT", 20, -(y + 4))
        editor:SetHeight(y + 40)
    end

    rebuild()
    editor:Show()
    editor:Raise()
end

function Pages.general()
    local db = PRIO.db
    Section("Behavior")
    local function tog(label, key, extra)
        SettingRow(label, 24, function(r)
            local t = UI.Toggle(r, function() return db[key] end, function(v) db[key] = v end,
                function() if extra then extra() end AfterChange() end)
            t:SetPoint("RIGHT", 0, 0)
        end)
    end
    tog("Enabled", "enabled")
    tog("Lock frame", "locked", function() if PRIO.Display then PRIO.Display:ApplyLock() end end)
    tog("Show out of combat", "showOOC")
    tog("Opener at pull", "useOpener")
    tog("Pre-combat reminders", "showPrecombat")
    tog("Minimap button", "minimapShow", function() if PRIO.UpdateMinimapButton then PRIO.UpdateMinimapButton() end end)

    Section("Enemy detection")
    SettingRow("Count method", 30, function(r)
        local seg = UI.Segmented(r, {
            { value = "engaged", text = "Engaged" }, { value = "nameplates", text = "Nameplates" },
        }, function() return db.enemyDetect end, function(v) db.enemyDetect = v end, AfterChange)
        seg:SetPoint("RIGHT", 0, 0)
    end)

    Section("Auto mode thresholds")
    SettingRow("Cleave at (enemies)", 26, function(r)
        local s = UI.Slider(r, 200, 2, 6, 1, function() return db.cleaveAt end,
            function(v) db.cleaveAt = v end, AfterChange)
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("AoE at (enemies)", 26, function(r)
        local s = UI.Slider(r, 200, 3, 10, 1, function() return db.aoeAt end,
            function(v) db.aoeAt = v end, AfterChange)
        s:SetPoint("RIGHT", 0, 0)
    end)

    Section("Update rate")
    SettingRow("In combat", 26, function(r)
        local s = UI.Slider(r, 200, 50, 500, 10,
            function() return math.floor((db.combatRate or 0.15) * 1000 + 0.5) end,
            function(v) db.combatRate = v / 1000 end, AfterChange, " ms")
        s:SetPoint("RIGHT", 0, 0)
    end)
    SettingRow("Out of combat", 26, function(r)
        local s = UI.Slider(r, 200, 100, 1000, 50,
            function() return math.floor((db.idleRate or 0.5) * 1000 + 0.5) end,
            function(v) db.idleRate = v / 1000 end, AfterChange, " ms")
        s:SetPoint("RIGHT", 0, 0)
    end)

    Section("Tools")
    SettingRow("Debug window", 30, function(r)
        local b = UI.Card(r, C.control, 0.1)
        b:SetSize(120, 26); b:SetPoint("RIGHT", 0, 0)
        local bb = CreateFrame("Button", nil, b); bb:SetAllPoints()
        local fs = UI.Font(b, 12, C.accent); fs:SetPoint("CENTER"); fs:SetText("Open")
        bb:SetScript("OnClick", function() if PRIO.Debug then PRIO.Debug:Toggle() end end)
    end)
    SettingRow("Display position", 30, function(r)
        local b = UI.Card(r, C.control, 0.1)
        b:SetSize(120, 26); b:SetPoint("RIGHT", 0, 0)
        local bb = CreateFrame("Button", nil, b); bb:SetAllPoints()
        local fs = UI.Font(b, 12, C.accent); fs:SetPoint("CENTER"); fs:SetText("Reset")
        bb:SetScript("OnClick", function()
            db.point = { "CENTER", "CENTER", 0, -180 }
            if PRIO.Display then PRIO.Display:Refresh() end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Sidebar navigation
--------------------------------------------------------------------------------
local NAV = {
    { header = "DISPLAY",  items = { { label = "Icons & Layout", page = "display" } } },
    { header = "ROTATION", items = { { label = "Priorities",     page = "rotation" } } },
    { header = "GENERAL",  items = { { label = "Behavior",       page = "general" } } },
}

local PAGE_META = {
    display  = { title = "Display",    desc = "Size, layout, and what the strip draws on each icon." },
    rotation = { title = "Priorities", desc = "Order abilities highest to lowest. PRIO shows the first one that's ready and passes its condition." },
    general  = { title = "Behavior",   desc = "Enable, lock, out-of-combat visibility, and auto-mode thresholds." },
}

function Options:ShowPage(key)
    currentPage = key
    -- clear old content (hide; new widgets overlay at the same positions)
    if picker then picker:Hide() end
    if editor and key ~= "rotation" then editor:Hide() end
    for _, f in ipairs(kids) do f:Hide() end
    wipe(kids)

    -- header text
    local meta = PAGE_META[key]
    header.title:SetText(meta.title)
    header.desc:SetText(meta.desc)

    -- nav highlight
    for _, b in ipairs(navButtons) do b:SetActive(b.page == key) end

    -- build
    cursorY = 4
    Pages[key]()
    content:SetHeight(math.max(cursorY + 20, 360))
    scroll:SetVerticalScroll(0)
end

--------------------------------------------------------------------------------
-- Build the window once
--------------------------------------------------------------------------------
function Options:Build()
    if win then return end
    win = UI.Window("PRIOOptions", 720, 524, "PRIO")
    win:HookScript("OnHide", function()
        if picker then picker:Hide() end
        if editor then editor:Hide() end
    end)
    win.title:ClearAllPoints()
    win.title:SetPoint("TOPLEFT", 18, -16)
    local ver = UI.Font(win, 11, C.faint)
    ver:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 1, -1)
    ver:SetText("v" .. PRIO.version)

    -- Sidebar background + divider
    sidebar = UI.Solid(win, "BACKGROUND", C.sidebar)
    sidebar:SetPoint("TOPLEFT", 1, -1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_W)
    local divider = UI.Solid(win, "BORDER", { 1, 1, 1 }, 0.07)
    divider:SetPoint("TOPLEFT", SIDEBAR_W, -1); divider:SetPoint("BOTTOMLEFT", SIDEBAR_W, 1)
    divider:SetWidth(1)

    -- Nav
    local y = 64
    for _, group in ipairs(NAV) do
        local gh = UI.Font(win, 10.5, C.faint)
        gh:SetPoint("TOPLEFT", 18, -y); gh:SetText(group.header)
        y = y + 22
        for _, item in ipairs(group.items) do
            local b = CreateFrame("Button", nil, win)
            b:SetSize(SIDEBAR_W - 8, 30)
            b:SetPoint("TOPLEFT", 0, -y)
            b.page = item.page
            local arrow = UI.Font(b, 12, C.accent)
            arrow:SetPoint("LEFT", 8, 0); arrow:SetText("\226\150\182")  -- ▶
            arrow:Hide()
            local hover = UI.Solid(b, "BACKGROUND", { 1, 1, 1 }, 0.04); hover:SetAllPoints(); hover:Hide()
            local fs = UI.Font(b, 13.5, C.muted); fs:SetPoint("LEFT", 22, 0); fs:SetText(item.label)
            b.SetActive = function(_, on)
                arrow:SetShown(on)
                fs:SetTextColor(on and C.head[1] or C.muted[1],
                                on and C.head[2] or C.muted[2],
                                on and C.head[3] or C.muted[3])
            end
            b:SetScript("OnEnter", function() if b.page ~= currentPage then hover:Show() end end)
            b:SetScript("OnLeave", function() hover:Hide() end)
            b:SetScript("OnClick", function() Options:ShowPage(b.page) end)
            navButtons[#navButtons + 1] = b
            y = y + 32
        end
        y = y + 10
    end

    -- Header band (content side)
    header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", SIDEBAR_W + 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(84)
    header.title = UI.Font(header, 23, C.head)
    header.title:SetPoint("TOPLEFT", 22, -22)
    header.desc = UI.Font(header, 12.5, C.muted)
    header.desc:SetPoint("TOPLEFT", 22, -52)
    header.desc:SetPoint("RIGHT", -22, 0)
    header.desc:SetJustifyH("LEFT")
    local underline = UI.Solid(header, "ARTWORK", C.accent, 0.55)
    underline:SetPoint("BOTTOMLEFT", 22, 0); underline:SetPoint("BOTTOMRIGHT", -22, 0)
    underline:SetHeight(2)

    -- Scroll content
    scroll = CreateFrame("ScrollFrame", "PRIOOptionsScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", SIDEBAR_W + 22, -94)
    scroll:SetPoint("BOTTOMRIGHT", -30, 16)
    content = CreateFrame("Frame", nil, scroll)
    contentW = 720 - SIDEBAR_W - 22 - 30 - 6
    content:SetSize(contentW, 500)
    scroll:SetScrollChild(content)

    -- Resizable + responsive: reflow the current page to the new width.
    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(560, 380, 1200, 1000)
    elseif win.SetMinResize then
        win:SetMinResize(560, 380)
    end
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints(); gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gt:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing() end)

    local resizePending
    local function reflow()
        contentW = math.max(300, math.floor(scroll:GetWidth() - 2))
        content:SetWidth(contentW)
    end
    win:SetScript("OnSizeChanged", function()
        reflow()
        if not resizePending then
            resizePending = true
            C_Timer.After(0.05, function()
                resizePending = false
                if win:IsShown() then Options:ShowPage(currentPage) end
            end)
        end
    end)

    self:ShowPage("display")
    C_Timer.After(0, reflow)   -- capture the real scroll width once laid out
end

function Options:Toggle()
    self:Build()
    if win:IsShown() then win:Hide()
    else win:Show(); self:ShowPage(currentPage) end
end
