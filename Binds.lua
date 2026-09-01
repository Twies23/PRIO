-- Binds.lua --------------------------------------------------------------------
-- A gentle keybind nudge. Lots of people never bind every ability, so when PRIO
-- recommends one they have to eyeball their bars to find it. This scans the
-- abilities the active spec can recommend and flags any the player KNOWS but has
-- no key for -- then shows a small panel so each row turns green as they bind it.
--
-- Unlike Setup (which is version-keyed -- required auras don't change until an
-- update), keybinds are dynamic (respec, alts, rebinding), so this keys off the
-- actual unbound set: auto-opens once per session when something's unbound, and
-- is muteable per spec. Re-openable any time with /prio binds.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local UI  = PRIO.UI
local C   = UI.C
local Binds = {}
PRIO.Binds = Binds

local win, body, introFS, elapsed = nil, nil, nil, 0
local rows, pool, builtKey = {}, {}, nil

--------------------------------------------------------------------------------
-- The candidate set: distinct abilities the spec can recommend, in order of first
-- appearance across the CURRENT hero variant's priority lists. Mirrors Setup's
-- priorityAbilities so the two agree on "what PRIO might tell you to press".
--------------------------------------------------------------------------------
local function recommendableAbilities(spec)
    local out, seen = {}, {}
    if not spec then return out end
    local function walk(list)
        if type(list) ~= "table" then return end
        for _, e in ipairs(list) do
            local id = (type(e.spell) == "number") and e.spell or (spec.spells and spec.spells[e.spell])
            if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    if spec.priorityByVariant then
        local v = spec.priorityVariants and spec.priorityVariants[1] and spec.priorityVariants[1].key
        local lists = v and spec.priorityByVariant[v]
        if lists then walk(lists.st); walk(lists.aoe); walk(lists.cleave) end
    elseif type(spec.priority) == "table" then
        walk(spec.priority.st); walk(spec.priority.aoe); walk(spec.priority.cleave)
    end
    return out
end

-- Best-effort passive check: passives never sit on an action bar, so without this
-- they'd read as "unbound" forever. Unknown -> treat as castable (don't hide it).
local function isPassive(id)
    if C_Spell and C_Spell.IsSpellPassive then
        local ok, p = pcall(C_Spell.IsSpellPassive, id)
        if ok and p then return true end
    end
    if IsPassiveSpell then
        local ok, p = pcall(IsPassiveSpell, id)
        if ok and p then return true end
    end
    return false
end

-- The key for a spell, honouring the spec's override aliases (e.g. Moonlight
-- Chakram is cast on the Trueshot button, so it "shares" that bind). Returns "".
local function bindFor(spec, id)
    local kb = API.Keybind(id)
    if (kb == nil or kb == "") and spec and spec.keybindAlias and spec.keybindAlias[id] then
        kb = API.Keybind(spec.keybindAlias[id])
    end
    return kb or ""
end

local function ignoredSet(spec)
    local db = PRIO.db
    local key = spec and spec.key or "none"
    return (db and db.bindsIgnore and db.bindsIgnore[key]) or nil
end

-- The abilities to actually nudge about: known, castable (not passive), named, not
-- ignored, and with no key. Returns { {id=, name=} , ... } in priority order.
local function computeUnbound(spec)
    local out = {}
    if not spec then return out end
    local ignored = ignoredSet(spec)
    for _, id in ipairs(recommendableAbilities(spec)) do
        if not (ignored and ignored[id]) and API.IsKnown(id) and not isPassive(id) then
            local nm = API.SpellName(id)
            if nm and nm ~= "" and not nm:find("^Spell ") then
                if bindFor(spec, id) == "" then
                    out[#out + 1] = { id = id, name = nm }
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Row pool: icon + name + live status + a small "Ignore" (for macro users).
--------------------------------------------------------------------------------
local function acquireRow()
    for _, f in ipairs(pool) do if not f._used then f._used = true; f:Show(); return f end end
    local f = CreateFrame("Frame", nil, body)
    f:SetSize(430, 30)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(24, 24); f.icon:SetPoint("LEFT", 2, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the default border

    f.name = UI.Font(f, 13.5, C.head); f.name:SetPoint("LEFT", 34, 0)
    f.name:SetJustifyH("LEFT")

    -- Ignore button (right of the row): silences a false positive (spell on a macro,
    -- or one you deliberately don't bind) for this spec.
    local ig = CreateFrame("Button", nil, f)
    ig:SetSize(52, 20); ig:SetPoint("RIGHT", -2, 0)
    local igbg = UI.Solid(ig, "BACKGROUND", C.control, 0.10); igbg:SetAllPoints()
    local igt = UI.Font(ig, 11, C.muted); igt:SetPoint("CENTER"); igt:SetText("Ignore")
    ig:SetScript("OnEnter", function() igbg:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.24) end)
    ig:SetScript("OnLeave", function() igbg:SetColorTexture(C.control[1], C.control[2], C.control[3], 0.10) end)
    f.ignore = ig

    f.state = UI.Font(f, 12, C.muted); f.state:SetPoint("RIGHT", ig, "LEFT", -10, 0)
    f.state:SetJustifyH("RIGHT")

    f._used = true; pool[#pool + 1] = f
    return f
end

function Binds:Rebuild(spec)
    for _, f in ipairs(pool) do f._used = false; f:Hide() end
    wipe(rows)

    local list = computeUnbound(spec)
    local y = 62 + math.ceil((introFS and introFS:GetStringHeight()) or 34) + 14

    for _, item in ipairs(list) do
        local r = acquireRow()
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -y)
        r.icon:SetTexture(API.SpellTexture(item.id))
        r.name:SetText(item.name)
        r.ignore:SetScript("OnClick", function()
            local db = PRIO.db
            db.bindsIgnore = db.bindsIgnore or {}
            local key = spec and spec.key or "none"
            db.bindsIgnore[key] = db.bindsIgnore[key] or {}
            db.bindsIgnore[key][item.id] = true
            Binds:Rebuild(spec)
        end)
        rows[#rows + 1] = { frame = r, item = item }
        y = y + 34
    end

    if #list == 0 then
        local r = acquireRow()
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -y)
        r.icon:Hide(); r.ignore:Hide()
        r.name:SetText("Every ability PRIO can recommend is bound. Nice.")
        r.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        r.state:SetText("")
        rows[#rows + 1] = { frame = r, item = nil }
        y = y + 34
    end

    builtKey = spec and spec.key or "none"
    if win then win:SetHeight(y + 66) end
end

function Binds:Update()
    if not (win and win:IsShown()) then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]
    if (spec and spec.key or "none") ~= builtKey then self:Rebuild(spec) end

    for _, row in ipairs(rows) do
        local it = row.item
        if it then
            local kb = bindFor(spec, it.id)
            if kb ~= "" then
                row.frame.state:SetText("bound: " .. kb)
                row.frame.state:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
                row.frame.name:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
            else
                row.frame.state:SetText("not bound")
                row.frame.state:SetTextColor(0.88, 0.41, 0.35, 1)
                row.frame.name:SetTextColor(C.head[1], C.head[2], C.head[3], 1)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
function Binds:Build()
    if win then return end
    win = UI.Window("PRIOBinds", 470, 300, "PRIO  Keybinds",
        "Bind the abilities PRIO can recommend")
    win:SetFrameStrata("DIALOG")
    body = CreateFrame("Frame", nil, win); body:SetAllPoints(win)

    local intro = UI.Font(body, 12.5, C.muted)
    intro:SetPoint("TOPLEFT", 20, -62); intro:SetPoint("RIGHT", body, "RIGHT", -20, 0)
    intro:SetJustifyH("LEFT"); intro:SetWordWrap(true)
    intro:SetText("These abilities have no key, so you'd have to click them. Bind each on your bars and it turns green here. |cff8a959fCast one from a macro? Hit Ignore.|r")
    introFS = intro

    local function mkButton(text, w, onClick, filled)
        local b = CreateFrame("Button", nil, win)
        b:SetSize(w, 28)
        local col = filled and C.accent or C.control
        local a0 = filled and 0.16 or 0.10
        local bg = UI.Solid(b, "BACKGROUND", col, a0); bg:SetAllPoints()
        local t = UI.Font(b, 13, filled and C.accent or C.text); t:SetPoint("CENTER"); t:SetText(text)
        b:SetScript("OnEnter", function() bg:SetColorTexture(col[1], col[2], col[3], a0 + 0.14) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(col[1], col[2], col[3], a0) end)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- Best-effort: open Blizzard's key-binding UI. Guarded across client variants.
    local function openKeybindings()
        if InCombatLockdown() then return end
        if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
            if pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID) then return end
        end
        if KeyBindingFrame_LoadUI then pcall(KeyBindingFrame_LoadUI) end
        if _G.KeyBindingFrame and ShowUIPanel then pcall(ShowUIPanel, _G.KeyBindingFrame) end
    end

    local openKB = mkButton("Open Key Bindings", 170, openKeybindings, true)
    local mute = mkButton("Don't remind me", 150, function()
        local db = PRIO.db
        local specID = API.GetSpecID()
        local spec = specID and PRIO.specs and PRIO.specs[specID]
        db.bindsMuted = db.bindsMuted or {}
        db.bindsMuted[spec and spec.key or "none"] = true
        win:Hide()
    end)
    local done = mkButton("Done", 90, function() win:Hide() end)

    openKB:SetPoint("BOTTOMLEFT", 20, 16)
    done:SetPoint("BOTTOMRIGHT", -20, 16)
    mute:SetPoint("RIGHT", done, "LEFT", -10, 0)

    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.25 then elapsed = 0; Binds:Update() end
    end)
end

function Binds:Open()
    self:Build()
    local specID = API.GetSpecID()
    self:Rebuild(specID and PRIO.specs and PRIO.specs[specID])
    win:Show(); self:Update()
end

function Binds:Toggle()
    self:Build()
    if win:IsShown() then win:Hide() else self:Open() end
end

--------------------------------------------------------------------------------
-- Auto-open: once per session, only when the active spec has unbound recommendable
-- abilities and hasn't been muted. Defers behind the changelog / setup windows so
-- they don't stack up on login.
--------------------------------------------------------------------------------
function Binds:MaybeAutoOpen()
    if self._promptedThisSession then return end
    local db = PRIO.db
    if not db then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]
    if not spec then return end
    if db.bindsMuted and db.bindsMuted[spec.key] then return end
    if #computeUnbound(spec) == 0 then return end

    self._promptedThisSession = true

    -- If another PRIO dialog is up (changelog / setup), wait for it to close.
    local function blockingWindow()
        for _, name in ipairs({ "PRIOChangelog", "PRIOSetup" }) do
            local w = _G[name]
            if w and w:IsShown() then return w end
        end
        return nil
    end
    local function openWhenClear(tries)
        local w = blockingWindow()
        if not w then self:Open(); return end
        if tries <= 0 then return end
        C_Timer.After(1, function() openWhenClear(tries - 1) end)
    end
    openWhenClear(30)
end
