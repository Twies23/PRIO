-- Setup.lua --------------------------------------------------------------------
-- A per-spec first-time setup checklist. Shows what the active spec needs for PRIO
-- to read the game correctly (nameplates, tracked auras, optional pandemic alerts),
-- with a LIVE status per item so the user watches each turn green as they fix it.
-- Auto-opens once per spec; re-openable with /prio setup.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local UI  = PRIO.UI
local C   = UI.C
local Setup = {}
PRIO.Setup = Setup

Setup.confirmed = {}          -- [spell] = true once a pandemic window is seen this session
local win, body, elapsed = nil, nil, 0
local rows, pool, builtKey = {}, {}, nil

--------------------------------------------------------------------------------
-- Auto-derive the auras the rotation ACTUALLY gates on, so the checklist can never
-- silently miss one. We collect the spell IDs from every aura-PRESENCE clause across
-- all of the spec's priority lists (every hero variant + mode), its alerts, and any
-- named presets those reference. Cooldown / charge / glow / predicted clauses need no
-- Cooldown-Manager tracking, so they're intentionally excluded.
--------------------------------------------------------------------------------
local AURA_CLAUSES = {
    buffActive = true, buffMissing = true, refreshable = true,
    stacksMin = true, stacksMax = true, stacksEq = true,
    auraRemainMin = true, auraRemainMax = true,
}

local function presetClause(spec, t)
    local key = type(t) == "string" and t:match("^preset:(.+)$")
    if not (key and spec.condPresets) then return nil end
    for _, p in ipairs(spec.condPresets) do if p.key == key then return p.clause end end
    return nil
end

local function collectFromCond(cond, out, spec, depth)
    depth = depth or 0
    if type(cond) ~= "table" or depth > 8 then return end
    if cond.clauses then
        for _, c in ipairs(cond.clauses) do collectFromCond(c, out, spec, depth + 1) end
        return
    end
    local t = cond.type
    if type(t) == "string" and t:find("^preset:") then
        collectFromCond(presetClause(spec, t), out, spec, depth + 1)
    elseif t and AURA_CLAUSES[t] and type(cond.spell) == "number" then
        out[cond.spell] = true
    end
end

local function requiredAuras(spec)
    local out = {}
    if not spec then return out end
    local function walk(list)
        if type(list) ~= "table" then return end
        for _, e in ipairs(list) do collectFromCond(e.cond, out, spec) end
    end
    if spec.priorityByVariant then
        for _, lists in pairs(spec.priorityByVariant) do
            for _, list in pairs(lists) do walk(list) end
        end
    elseif type(spec.priority) == "table" then
        for _, list in pairs(spec.priority) do walk(list) end
    end
    if spec.alerts then
        for _, a in ipairs(spec.alerts) do collectFromCond(a.when, out, spec) end
    end
    return out
end

--------------------------------------------------------------------------------
-- Checklist items for the active spec = global checks + spec.setup metadata +
-- any auto-derived tracked auras the spec.setup list didn't already cover.
--------------------------------------------------------------------------------
local function itemsFor(spec)
    local list = {
        { kind = "cdm", label = "Cooldown Manager active",
          hint = "PRIO reads your buffs and debuffs from Blizzard's Cooldown Manager -- without it, it's blind to them in combat. Enable it in Edit Mode (Cooldown Manager) and add the spells below." },
        { kind = "nameplates", label = "Enemy nameplates",
          hint = "Needed to count targets for Cleave/AoE. PRIO turns these on for you." },
    }
    local covered = {}
    if spec and spec.setup then
        for _, it in ipairs(spec.setup) do
            list[#list + 1] = it
            if it.kind == "trackedAura" and it.spell then covered[it.spell] = true end
        end
    end
    -- Auto-derived: every aura the rotation checks that isn't already listed.
    if spec then
        local ids = {}
        for id in pairs(requiredAuras(spec)) do if not covered[id] then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local nm = API.SpellName(id)
            if nm and nm ~= "" then
                list[#list + 1] = { kind = "trackedAura", spell = id, derived = true,
                    label = nm .. " tracked",
                    hint = "The rotation checks this buff -- add it to your Cooldown Manager so PRIO can read it in combat." }
            end
        end
    end
    return list
end

-- Returns "ok" / "bad" / "warn" and a short status word.
local function statusOf(it)
    if it.kind == "cdm" then
        local ok, t = pcall(API.EnumerateTracked)
        return (ok and type(t) == "table" and #t > 0) and "ok" or "bad"
    elseif it.kind == "nameplates" then
        return API.NameplatesEnabled() and "ok" or "bad"
    elseif it.kind == "trackedAura" then
        return API.IsTracked(it.spell) and "ok" or "bad"
    elseif it.kind == "pandemic" then
        if API.InPandemic and API.InPandemic(it.spell) == true then Setup.confirmed[it.spell] = true end
        return Setup.confirmed[it.spell] and "ok" or "warn"
    elseif it.kind == "info" then
        return "info"
    end
    return "warn"
end

local STATE = {
    ok   = { txt = "Ready",         col = { 0.047, 0.824, 0.616 } },
    bad  = { txt = "Action needed", col = { 0.88,  0.41,  0.35  } },
    warn = { txt = "Optional",      col = { 0.878, 0.627, 0.227 } },
    info = { txt = "Automatic",     col = { 0.62,  0.72,  0.82  } },
}

--------------------------------------------------------------------------------
-- Row pool (rebuilt when the spec changes)
--------------------------------------------------------------------------------
local function acquireRow()
    for _, f in ipairs(pool) do if not f._used then f._used = true; f:Show(); return f end end
    local f = CreateFrame("Frame", nil, body)
    f:SetSize(452, 44)
    f.dot = UI.Solid(f, "ARTWORK", C.accent); f.dot:SetSize(10, 10)
    f.dot:SetPoint("TOPLEFT", 2, -6)
    f.name = UI.Font(f, 14, C.head);  f.name:SetPoint("TOPLEFT", 22, -3)
    f.state = UI.Font(f, 12, C.muted); f.state:SetPoint("TOPRIGHT", -2, -4); f.state:SetJustifyH("RIGHT")
    f.hint = UI.Font(f, 11.5, C.muted); f.hint:SetPoint("TOPLEFT", 22, -22)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -8, 0); f.hint:SetJustifyH("LEFT"); f.hint:SetWordWrap(true)
    f._used = true
    pool[#pool + 1] = f
    return f
end

function Setup:Rebuild(spec)
    for _, f in ipairs(pool) do f._used = false; f:Hide() end
    wipe(rows)
    local y = 96
    for _, it in ipairs(itemsFor(spec)) do
        local r = acquireRow()
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 22, -y)
        r.name:SetText(it.label or "?")
        r.hint:SetText(it.hint or "")
        rows[#rows + 1] = { frame = r, item = it }
        y = y + 46
    end
    builtKey = spec and spec.key or "none"
    if win then win:SetHeight(y + 58) end
end

function Setup:Build()
    if win then return end
    win = UI.Window("PRIOSetup", 500, 400, "PRIO  Setup", "Get this spec reading the game correctly")
    win:SetFrameStrata("DIALOG")
    body = CreateFrame("Frame", nil, win); body:SetAllPoints(win)

    local intro = UI.Font(body, 12.5, C.muted)
    intro:SetPoint("TOPLEFT", 22, -68); intro:SetPoint("RIGHT", body, "RIGHT", -22, 0)
    intro:SetJustifyH("LEFT"); intro:SetWordWrap(true)
    intro:SetText("Each item turns green once it's set. \"Action needed\" items are required; \"Optional\" ones improve accuracy.")

    -- Footer buttons.
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

    local apply = mkButton("Apply recommended settings", 210, function()
        PRIO:ApplyPreset("Recommended")
    end, true)
    local custom = mkButton("Customize\226\128\166", 120, function()
        if PRIO.Options then PRIO.Options:Toggle() end
    end)
    local done = mkButton("Done", 90, function() win:Hide() end)

    apply:SetPoint("BOTTOMLEFT", 22, 16)
    done:SetPoint("BOTTOMRIGHT", -22, 16)
    custom:SetPoint("RIGHT", done, "LEFT", -10, 0)

    win:SetScript("OnUpdate", function(_, dt2)
        elapsed = elapsed + dt2
        if elapsed >= 0.2 then elapsed = 0; Setup:Update() end
    end)
end

function Setup:Update()
    if not (win and win:IsShown()) then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]
    if (spec and spec.key or "none") ~= builtKey then self:Rebuild(spec) end
    for _, row in ipairs(rows) do
        local st = STATE[statusOf(row.item)] or STATE.warn
        row.frame.dot:SetColorTexture(st.col[1], st.col[2], st.col[3], 1)
        row.frame.state:SetText(st.txt)
        row.frame.state:SetTextColor(st.col[1], st.col[2], st.col[3], 1)
    end
end

function Setup:Open()
    self:Build()
    self:Rebuild(API.GetSpecID() and PRIO.specs[API.GetSpecID()])
    win:Show(); self:Update()
end

function Setup:Toggle()
    self:Build()
    if win:IsShown() then win:Hide() else self:Open() end
end

-- Auto-open once per spec (tracked in saved vars).
function Setup:MaybeAutoOpen()
    local db = PRIO.db
    if not db then return end
    db.setupSeen = db.setupSeen or {}
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]
    if not spec then return end
    if db.setupSeen[spec.key] then return end
    db.setupSeen[spec.key] = true
    self:Open()
end
