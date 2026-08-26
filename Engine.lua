-- Engine.lua -------------------------------------------------------------------
-- The priority evaluator + local prediction model.
--
-- Readable signals (cooldown-ready, Maelstrom, enemy count, spell known) are read
-- live each tick. The unreadable layer (procs, buff windows, stacks, Flame Shock
-- timing) is *predicted* from a state table P that is advanced by the player's own
-- UNIT_SPELLCAST_SUCCEEDED events and reset when leaving combat.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local Engine = { P = {} }
PRIO.Engine = Engine

local spec          -- active spec definition (from PRIO.specs[specID])
local idToKey = {}  -- resolved spellID -> spec key (incl. base/override)
local Entry         -- forward decl: builds a display entry from a spellID

--------------------------------------------------------------------------------
-- Shared declarative conditions (used by built-in lists, custom lists, and the
-- options editor).
--
--   cond = nil                                        -> always
--   cond = { op="and"|"or", clauses = { clause... } } -> group
--   cond = <clause>                                    -> single (legacy)
--
-- A clause = { type=, spell=<spellID or nil=self>, v=<number> }. Buff/cooldown
-- clauses can reference ANY spell (cross-spell), so e.g. "Ascendance if
-- Stormkeeper is off cooldown OR Stormkeeper buff is up" is expressible.
-- Everything fails OPEN (unreadable -> passes) so a secret value never blanks
-- the strip.
--------------------------------------------------------------------------------
local Cond = {}
PRIO.Cond = Cond

-- Clause type metadata, in editor-dropdown order.
-- `target` = which option list the spell dropdown draws from: "buff" (auras only),
-- "ability" (castables only), "duration" (only auras with a tracked duration). `tag` =
-- a spec-specific concept; the type only appears when the spec opts in via spec.condTags.
Cond.types = {
    { value = "buffActive",  text = "Has buff",       needsSpell = true, target = "buff" },
    { value = "buffMissing", text = "Missing buff",   needsSpell = true, target = "buff" },
    { value = "debuffActive",  text = "Enemy has debuff",     needsSpell = true, target = "buff" },
    { value = "debuffMissing", text = "Enemy missing debuff", needsSpell = true, target = "buff" },
    { value = "cdReady",     text = "Off cooldown",   needsSpell = true, target = "ability" },
    { value = "cdNotReady",  text = "On cooldown",    needsSpell = true, target = "ability" },
    { value = "talentYes",   text = "Talent selected",     needsTalent = true },
    { value = "talentNo",    text = "Talent not selected", needsTalent = true },
    { value = "lastCast",    text = "Just cast",       needsSpell = true, target = "ability" },
    { value = "lastCastNot", text = "Didn't just cast", needsSpell = true, target = "ability" },
    { value = "refreshable", text = "In pandemic (refreshable)", needsSpell = true, target = "buff" },
    { value = "moteUp",      text = "MotE up",   tag = "ele" },
    { value = "moteDown",    text = "MotE down", tag = "ele" },
    { value = "skStacks",    text = "SK stacks \226\137\165", needsValue = true, min = 1, max = 4, def = 1, tag = "ele" },
    { value = "stacksMin",   text = "Buff stacks \226\137\165", needsSpell = true, needsValue = true, min = 1, max = 10, def = 2, target = "buff" },
    { value = "stacksMax",   text = "Buff stacks \226\137\164", needsSpell = true, needsValue = true, min = 0, max = 10, def = 1, target = "buff" },
    -- NOTE: proc-glow (glowing/notGlowing) and predicted-stack (predStackMin/Max) clause
    -- types are still evaluated below, but are NOT offered as raw picker options -- they
    -- are surfaced only as named spec.condPresets (e.g. "Sudden Death up"), so the user
    -- never has to know "Execute glow == Sudden Death".
    { value = "chargesMin",  text = "Charges \226\137\165", needsValue = true, min = 1, max = 5, def = 2 },
    { value = "chargesMax",  text = "Charges \226\137\164", needsValue = true, min = 0, max = 5, def = 1 },
    { value = "auraRemainMin", text = "Buff time left \226\137\165", needsSpell = true, needsValue = true, min = 0, max = 30, def = 3, target = "duration" },
    { value = "auraRemainMax", text = "Buff time left \226\137\164", needsSpell = true, needsValue = true, min = 0, max = 30, def = 3, target = "duration" },
    { value = "cdRemainMin", text = "Cooldown \226\137\165", needsSpell = true, needsValue = true, min = 0, max = 180, def = 10, target = "ability" },
    { value = "cdRemainMax", text = "Cooldown \226\137\164", needsSpell = true, needsValue = true, min = 0, max = 180, def = 10, target = "ability" },
    { value = "resourceMin", text = "Resource \226\137\165", needsValue = true, min = 0, max = 12, def = 2 },
    { value = "resourceMax", text = "Resource \226\137\164", needsValue = true, min = 0, max = 12, def = 2 },
    { value = "usable",      text = "Usable",       needsSpell = true, target = "ability" },
    { value = "notUsable",   text = "Not usable",   needsSpell = true, target = "ability" },
    { value = "enemiesMin",  text = "Enemies \226\137\165",   needsValue = true, min = 1, max = 10, def = 2 },
    { value = "enemiesMax",  text = "Enemies \226\137\164",   needsValue = true, min = 1, max = 10, def = 1 },
    { value = "energyNearCap",    text = "Energy near cap",     tag = "energy" },
    { value = "energyNotNearCap", text = "Energy not near cap", tag = "energy" },
    { value = "energyPctMin", text = "Energy % \226\137\165", needsValue = true, min = 0, max = 100, def = 80, tag = "energy" },
    { value = "energyPctMax", text = "Energy % \226\137\164", needsValue = true, min = 0, max = 100, def = 20, tag = "energy" },
}

-- A spec.condPresets entry -> a picker option. Presets are NAMED boolean conditions
-- (e.g. "Sudden Death up") that resolve to an underlying clause (a glow or predicted-
-- stack read) the user never has to see. Clause form: { type = "preset:<key>" }.
local function resolvePreset(t)
    if type(t) ~= "string" then return nil end
    local key = t:match("^preset:(.+)$")
    if not (key and spec and spec.condPresets) then return nil end
    for _, p in ipairs(spec.condPresets) do if p.key == key then return p end end
    return nil
end
Cond.ResolvePreset = resolvePreset

-- The condition types a spec should offer: generic ones always, tagged ones only when
-- the spec opts in (spec.condTags[tag]); plus the spec's named presets. Keeps Shaman-
-- only MotE/SK stacks off Monk, etc.
function Cond.TypesForSpec(specArg)
    local tags = specArg and specArg.condTags
    local out = {}
    for _, m in ipairs(Cond.types) do
        if not m.tag or (tags and tags[m.tag]) then out[#out + 1] = m end
    end
    if specArg and specArg.condPresets then
        for _, p in ipairs(specArg.condPresets) do
            out[#out + 1] = { value = "preset:" .. p.key, text = p.label or p.key }
        end
    end
    return out
end
function Cond.TypeMeta(t)
    for _, m in ipairs(Cond.types) do if m.value == t then return m end end
    -- Presets need no spell/value picker (the underlying clause carries them).
    local p = resolvePreset(t)
    if p then return { value = t, text = p.label or p.key } end
end

local function SpellShort(sid)
    if not sid then return "self" end
    return API.SpellName(sid)
end

function Cond.ClauseLabel(cl, selfSid)
    local t = cl.type
    local preset = resolvePreset(t)
    if preset then return preset.label or "?" end
    local name = SpellShort(cl.spell or selfSid)
    if t == "buffActive" then return name .. " buff"
    elseif t == "buffMissing" then return "no " .. name .. " buff"
    elseif t == "debuffActive" then return "enemy " .. name .. " debuff"
    elseif t == "debuffMissing" then return "enemy no " .. name .. " debuff"
    elseif t == "cdReady" then return name .. " ready"
    elseif t == "cdNotReady" then return name .. " on CD"
    elseif t == "talentYes" then return (cl.spell and SpellShort(cl.spell) or "talent") .. " talented"
    elseif t == "talentNo" then return "no " .. (cl.spell and SpellShort(cl.spell) or "talent") .. " talent"
    elseif t == "lastCast" then return "just cast " .. name
    elseif t == "lastCastNot" then return "not just " .. name
    elseif t == "refreshable" then return name .. " in pandemic"
    elseif t == "stacksMin" then return name .. " \226\137\165 " .. (cl.v or 1) .. " stk"
    elseif t == "stacksMax" then return name .. " \226\137\164 " .. (cl.v or 1) .. " stk"
    elseif t == "glowing" then return name .. " glowing"
    elseif t == "notGlowing" then return name .. " not glowing"
    elseif t == "predStackMin" then return name .. " \226\137\165 " .. (cl.v or 1) .. " stk~"
    elseif t == "predStackMax" then return name .. " \226\137\164 " .. (cl.v or 1) .. " stk~"
    elseif t == "chargesMin" then return name .. " \226\137\165 " .. (cl.v or 1) .. " chg"
    elseif t == "chargesMax" then return name .. " \226\137\164 " .. (cl.v or 1) .. " chg"
    elseif t == "auraRemainMin" then return name .. " \226\137\165 " .. (cl.v or 0) .. "s left"
    elseif t == "auraRemainMax" then return name .. " \226\137\164 " .. (cl.v or 0) .. "s left"
    elseif t == "cdRemainMin" then return name .. " CD \226\137\165 " .. (cl.v or 0) .. "s"
    elseif t == "cdRemainMax" then return name .. " CD \226\137\164 " .. (cl.v or 0) .. "s"
    elseif t == "resourceMin" then return (spec and spec.resourceLabel or "resource") .. " \226\137\165 " .. (cl.v or 0)
    elseif t == "resourceMax" then return (spec and spec.resourceLabel or "resource") .. " \226\137\164 " .. (cl.v or 0)
    elseif t == "energyNearCap" then return "Energy near cap"
    elseif t == "energyNotNearCap" then return "Energy not near cap"
    elseif t == "energyPctMin" then return "Energy \226\137\165 " .. (cl.v or 0) .. "%"
    elseif t == "energyPctMax" then return "Energy \226\137\164 " .. (cl.v or 0) .. "%"
    elseif t == "usable" then return name .. " usable"
    elseif t == "notUsable" then return name .. " unusable"
    elseif t == "moteUp" then return "MotE up"
    elseif t == "moteDown" then return "MotE down"
    elseif t == "skStacks" then return "SK \226\137\165 " .. (cl.v or 1)
    elseif t == "enemiesMin" then return "\226\137\165 " .. (cl.v or 1) .. " enemies"
    elseif t == "enemiesMax" then return "\226\137\164 " .. (cl.v or 1) .. " enemies"
    end
    return "?"
end

-- Compact summary for the priority-row chip.
function Cond.Summary(cond, selfSid)
    if not cond then return "always" end
    local cl = cond.clauses
    if not cl then return Cond.ClauseLabel(cond, selfSid) end
    if #cl == 0 then return "always" end
    if #cl == 1 then return Cond.ClauseLabel(cl[1], selfSid) end
    return #cl .. " conditions (" .. (cond.op == "or" and "ANY" or "ALL") .. ")"
end

-- Full readable description (for the text export). Expands every clause.
function Cond.Describe(cond, selfSid)
    if not cond then return "always" end
    local cl = cond.clauses
    if not cl then return Cond.ClauseLabel(cond, selfSid) end
    if #cl == 0 then return "always" end
    if #cl == 1 then return Cond.ClauseLabel(cl[1], selfSid) end
    local parts = {}
    for _, c in ipairs(cl) do parts[#parts + 1] = Cond.ClauseLabel(c, selfSid) end
    local head = (cond.op == "or") and "ANY" or "ALL"
    return head .. "( " .. table.concat(parts, (cond.op == "or") and " OR " or " AND ") .. " )"
end

function Cond.Copy(c)
    if not c then return nil end
    if c.clauses then
        local cl = {}
        for i, x in ipairs(c.clauses) do cl[i] = Cond.Copy(x) end   -- recurse (don't flatten groups to empty)
        return { op = c.op or "and", clauses = cl }
    end
    return { type = c.type, spell = c.spell, v = c.v }
end

-- Did the last cast match a referenced spell? Compares by spec key (override-aware)
-- when both resolve, else by raw spell ID.
local function LastCastMatch(ref, S)
    if not ref then return false end
    local refKey = idToKey[ref]
    if refKey and S.lastCastKey then return refKey == S.lastCastKey end
    return ref == S.lastCastID
end

-- Current charges of a spell: predicted for spec-tracked charge spells, else the
-- readable count. nil when the spell has no charges / can't tell.
-- Effective current charges for conditions and the Debug window. Clean read first
-- (EllesmereUI's method): GetSpellCharges().isActive is false ONLY at max, so at max we
-- know the exact count, and "below max" is a clean fact even while currentCharges is
-- secret -- combined with the usable flag this nails a 2-charge spell (Zenith) to 0/1/2.
-- When the clean count is unknowable (usable secret while recharging), fall back to the
-- spec prediction, clamped by the clean "below max" fact so it can't report full.
function Engine:EffectiveCharges(sid)
    local maxC, cleanCur, belowMax = nil, nil, nil
    if API.ChargeState then maxC, cleanCur, belowMax = API.ChargeState(sid) end
    if cleanCur ~= nil then return cleanCur end
    local pc = self:PredictedCharges(sid)
    if pc ~= nil then
        if belowMax and maxC then pc = math.min(pc, maxC - 1) end
        return pc
    end
    if maxC and belowMax == false then return maxC end
    local _, cur = API.Charges(sid)
    return cur
end

local function ChargeCount(sid)
    return Engine:EffectiveCharges(sid)
end

-- Talent-adjusted Energy cost from a spec entry ({cost,...} probe or {base,...} spender).
local function EnergyCostOf(entry)
    if not entry then return nil end
    local cost = entry.base or entry.cost or 0
    if entry.reduce then
        for tid, amt in pairs(entry.reduce) do if API.IsKnown(tid) then cost = cost - amt end end
    end
    return cost
end

-- CHECKPOINT estimate of current Energy: the highest cost among energy-gated probe
-- abilities that are currently USABLE (clean flag) -- "usable" means Energy >= that
-- cost, so the max gives a safe floor. nil when the spec has no model / nothing clean.
function Engine:EnergyFloor()
    local m = spec and spec.energyModel
    if not (m and m.probes) then return nil end
    local floor
    for _, p in ipairs(m.probes) do
        if API.UsableClean(p.spell) == true then
            local cost = EnergyCostOf(p)
            if cost and (not floor or cost > floor) then floor = cost end
        end
    end
    return floor
end

-- Dead-reckon predicted Energy. The bar is secret in combat, so we integrate the fixed
-- regen (10/sec, +Ascension) against the readable max, re-anchor UP to the usable-flag
-- checkpoint floor, and -- whenever the real value IS readable (some clients out of
-- combat) -- sync to it exactly. Spends are subtracted on cast (UNIT_SPELLCAST_SUCCEEDED).
function Engine:UpdateEnergy(now)
    local m = spec and spec.energyModel
    if not (m and m.power) then return end
    local P = self.P
    local max = API.PowerMax(m.power) or 100
    P.energyMax = max
    local real = API.Power(m.power)                 -- clean number if readable, else nil
    if real ~= nil then
        P.energyEst, P.energyEstTime = math.min(max, real), now
        return
    end
    local rate = m.regenPerSec or 10
    if m.regenTalents then
        for tid, frac in pairs(m.regenTalents) do if API.IsKnown(tid) then rate = rate * (1 + frac) end end
    end
    if m.hasteScaled then rate = rate * (1 + (API.Haste() or 0) / 100) end
    rate = rate * (m.regenBias or 1)   -- lean the estimate high so we spend before capping
    local dt = now - (P.energyEstTime or now); if dt < 0 then dt = 0 end
    P.energyEstTime = now
    P.energyEst = math.min(max, (P.energyEst or max) + rate * dt)
    local floor = self:EnergyFloor()                -- usable => Energy >= that cost
    if floor and P.energyEst < floor then P.energyEst = floor end
end

-- Best absolute Energy estimate (the dead-reckoned prediction).
function Engine:EnergyEstimate()
    if not (spec and spec.energyModel) then return nil end
    return self.P and self.P.energyEst
end

-- Predicted Energy as a percent (0-100), or nil. The near-cap signal.
function Engine:EnergyPercent()
    local est = self:EnergyEstimate()
    local max = self.P and self.P.energyMax
    if est and max and max > 0 then return (est / max) * 100 end
    return nil
end

-- Predicted remaining COOLDOWN seconds, for "cooldown >= / <= N" conditions. Remaining
-- is secret in combat, so we seed a timer on cast (spec.cooldownTrack) and count down,
-- anchored to the clean off-cooldown flag: ready => 0. On cooldown but unseeded (cast
-- before we were watching) -> assume the full base, so "on a long cooldown" reads true.
-- nil only when the spell isn't cooldown-tracked and its readiness is unknown.
function Engine:CooldownRemaining(sid)
    if API.IsReady(sid) then return 0 end
    local e = self.P and self.P.cdExpire and self.P.cdExpire[sid]
    if e then local rem = e - GetTime(); return rem > 0 and rem or 0 end
    local key = idToKey[sid]
    local ct = spec and spec.cooldownTrack and key and spec.cooldownTrack[key]
    if ct then return ct.base or 0 end
    return nil
end

-- Remaining seconds on a buff, for "buff remaining <= / >= N" conditions. Prefers the
-- CLEAN expirationTime read (out of combat); in combat that's secret, so falls back to
-- the cast-seeded predicted timer (spec.auraDurations). nil = not up / unknown.
function Engine:AuraRemaining(sid)
    local r = API.AuraRemaining and API.AuraRemaining(sid)
    if r ~= nil then return r end
    local e = self.P and self.P.auraExpire and self.P.auraExpire[sid]
    if e then
        local rem = e - GetTime()
        if rem > 0 then return rem end
    end
    return nil
end

-- Was this aura just applied by our own cast (short assume window)? Covers the tick
-- or two before the Cooldown Viewer read catches up.
local function Assumed(sid, S)
    local a = Engine.P and Engine.P.assumeActive and Engine.P.assumeActive[sid]
    return a and a > (S.now or GetTime())
end

-- Player Energy percent for energy% conditions (the dead-reckoned prediction).
local function EnergyPct()
    return Engine:EnergyPercent()
end

-- "Near cap": predicted Energy >= the spec's nearCapAt threshold. true/false/nil.
local function EnergyNearCap()
    local m = spec and spec.energyModel
    local thr = m and m.nearCapAt
    local e = Engine:EnergyEstimate()
    if not (thr and e) then return nil end
    return e >= thr
end

-- Predicted stack count for an aura, advanced by our own casts (spec.stackTrack).
-- In the look-ahead sim S._simStacks holds the per-slot advanced copy; live eval
-- reads the real predicted table. nil/absent -> 0.
local function PredStacks(sid, S)
    if S and S._simStacks and S._simStacks[sid] ~= nil then return S._simStacks[sid] end
    return (Engine.P.stacks and Engine.P.stacks[sid]) or 0
end

local function EvalClause(cl, S, selfSid)
    if cl.clauses then return Cond.Eval(cl, S, selfSid) end   -- nested group -> recurse
    local t = cl.type
    -- Named preset -> evaluate its underlying clause (glow / predicted-stack read).
    local preset = resolvePreset(t)
    if preset then
        if preset.clause then return EvalClause(preset.clause, S, selfSid) end
        return true
    end
    -- Debuff variants share the tracked-aura read with their buff counterparts.
    if t == "debuffActive" then t = "buffActive"
    elseif t == "debuffMissing" then t = "buffMissing" end
    local sid = cl.spell or selfSid
    if t == "buffActive" then
        if S._sim and S._sim[sid] ~= nil then return S._sim[sid] end
        if Assumed(sid, S) then return true end
        -- Untracked (no Cooldown Viewer frame) -> we can't confirm the buff, so FAIL
        -- rather than ignore-pass: a proc/buff line you're not specced into (or haven't
        -- tracked) shouldn't silently pass. Tracked auras read a clean bool.
        if not API.IsTracked(sid) then return false end
        local a = API.IsAuraActive(sid); return a == true or a == nil
    elseif t == "buffMissing" then
        if S._sim and S._sim[sid] ~= nil then return not S._sim[sid] end
        if Assumed(sid, S) then return false end             -- just applied -> not missing
        -- Untracked/unreadable -> assume the buff is NOT up, so it IS missing (pass).
        -- Symmetric with "Has buff" (which fails when untracked): a buff you can't have
        -- (no 4pc / talent) reads as missing, which is correct.
        if not API.IsTracked(sid) then return true end
        local a = API.IsAuraActive(sid); return a == false or a == nil
    elseif t == "cdReady" then return API.IsReady(sid) and true or false
    elseif t == "cdNotReady" then return not API.IsReady(sid)
    elseif t == "talentYes" then return API.IsTalentSelected(cl.spell)
    elseif t == "talentNo" then return not API.IsTalentSelected(cl.spell)
    elseif t == "lastCast" then return LastCastMatch(cl.spell or selfSid, S)
    elseif t == "lastCastNot" then return not LastCastMatch(cl.spell or selfSid, S)
    -- Pandemic window read (secret-safe via the Cooldown Viewer). Only true when
    -- Blizzard confirms the DoT is refreshable; nil/false -> not (so it never fires
    -- early, and degrades to "refresh on missing" if the pandemic alert is off).
    elseif t == "refreshable" then return API.InPandemic(sid) == true
    -- Buff stack thresholds (secret-safe via the Cooldown Viewer). Unreadable/untracked
    -- reads as 0 stacks -> below any min, within any max.
    elseif t == "stacksMin" then return (API.AuraStackCount(sid) or 0) >= (cl.v or 1)
    elseif t == "stacksMax" then return (API.AuraStackCount(sid) or 0) <= (cl.v or 1)
    -- Proc glow: clean boolean when readable; nil (API missing) -> treat as not glowing.
    elseif t == "glowing" then return API.SpellGlowing(sid) == true
    elseif t == "notGlowing" then return API.SpellGlowing(sid) == false
    -- Predicted stacks (our own cast counter). Always defined (0 when none).
    elseif t == "predStackMin" then return PredStacks(sid, S) >= (cl.v or 1)
    elseif t == "predStackMax" then return PredStacks(sid, S) <= (cl.v or 1)
    -- Latched execute-range flag (secret-safe: usable-without-proc, debounced).
    elseif t == "inExecuteRange" then
        if S and S.execRange ~= nil then return S.execRange end
        return Engine:InExecuteRange()
    elseif t == "notExecuteRange" then
        if S and S.execRange ~= nil then return not S.execRange end
        return not Engine:InExecuteRange()
    elseif t == "chargesMin" then return (ChargeCount(sid) or 0) >= (cl.v or 1)
    elseif t == "chargesMax" then return (ChargeCount(sid) or 0) <= (cl.v or 1)
    -- Buff time-left (Zenith ending): predicted from the cast, since remaining is secret
    -- in combat. nil (buff not up / unknown) -> the threshold is not met.
    elseif t == "auraRemainMin" then local r = Engine:AuraRemaining(sid); return r ~= nil and r >= (cl.v or 0)
    elseif t == "auraRemainMax" then local r = Engine:AuraRemaining(sid); return r ~= nil and r <= (cl.v or 0)
    -- Predicted cooldown remaining (Xuen). nil -> unknown -> threshold not met.
    elseif t == "cdRemainMin" then local r = Engine:CooldownRemaining(sid); return r ~= nil and r >= (cl.v or 0)
    elseif t == "cdRemainMax" then local r = Engine:CooldownRemaining(sid); return r ~= nil and r <= (cl.v or 0)
    -- Resource threshold on the spec's own power (Chi/Holy Power/... read clean;
    -- secret bars use the predicted value). S.maelstrom is the spec resource amount.
    elseif t == "resourceMin" then return (S.maelstrom or 0) >= (cl.v or 0)
    elseif t == "resourceMax" then return (S.maelstrom or 0) <= (cl.v or 0)
    -- Energy percent (secret-safe via UnitPowerPercent). Unknown -> threshold not met.
    elseif t == "energyNearCap" then return EnergyNearCap() == true
    elseif t == "energyNotNearCap" then return EnergyNearCap() == false
    elseif t == "energyPctMin" then local p = EnergyPct(); return p ~= nil and p >= (cl.v or 0)
    elseif t == "energyPctMax" then local p = EnergyPct(); return p ~= nil and p <= (cl.v or 0)
    elseif t == "usable" then return API.IsUsable(sid) and true or false
    elseif t == "notUsable" then return not API.IsUsable(sid)
    -- MotE is predicted, not readable. Gate on the talent so these are correct on
    -- builds that don't take it (no talent -> never "up", always "down").
    elseif t == "moteUp" then return Engine.hasMote and S.mote and true or false
    elseif t == "moteDown" then return (not Engine.hasMote) or (not S.mote)
    elseif t == "mote" then return (S.mote and true or false) == (cl.v ~= false)   -- legacy compat
    elseif t == "skStacks" then return (S.skStacks or 0) >= (cl.v or 1)
    elseif t == "enemiesMin" then return (S.enemies or 1) >= (cl.v or 1)
    elseif t == "enemiesMax" then return (S.enemies or 1) <= (cl.v or 1)
    end
    return true
end
Cond.EvalClause = EvalClause

function Cond.Eval(cond, S, selfSid)
    if not cond then return true end
    local clauses = cond.clauses
    if not clauses then return EvalClause(cond, S, selfSid) end
    if #clauses == 0 then return true end
    if cond.op == "or" then
        for _, cl in ipairs(clauses) do if EvalClause(cl, S, selfSid) then return true end end
        return false
    end
    for _, cl in ipairs(clauses) do if not EvalClause(cl, S, selfSid) then return false end end
    return true
end

-- Live diagnostic for the editor: "pass" / "fail" / "open" (passes ONLY because
-- the value was unreadable -> the clause is effectively ignored right now).
function Cond.ClauseStatus(cl, S, selfSid)
    local t = cl.type
    local preset = resolvePreset(t)
    if preset and preset.clause then return Cond.ClauseStatus(preset.clause, S, selfSid) end
    if t == "debuffActive" then t = "buffActive"
    elseif t == "debuffMissing" then t = "buffMissing" end
    local sid = cl.spell or selfSid
    if t == "buffActive" then
        if not API.IsTracked(sid) then return "fail" end     -- untracked -> fail, not ignored
        local a = API.IsAuraActive(sid); if a == nil then return "open" end
        return a and "pass" or "fail"
    elseif t == "buffMissing" then
        if not API.IsTracked(sid) then return "pass" end     -- untracked -> assume missing
        local a = API.IsAuraActive(sid); if a == nil then return "open" end
        return (a == false) and "pass" or "fail"
    elseif t == "refreshable" then
        local a = API.InPandemic(sid); if a == nil then return "open" end
        return a and "pass" or "fail"
    elseif t == "stacksMin" or t == "stacksMax" then
        local s = API.AuraStackCount(sid); if s == nil then return "open" end
        local ok = (t == "stacksMin") and (s >= (cl.v or 1)) or (s <= (cl.v or 1))
        return ok and "pass" or "fail"
    elseif t == "glowing" or t == "notGlowing" then
        local g = API.SpellGlowing(sid); if g == nil then return "open" end
        local ok = (t == "glowing") and g or (not g)
        return ok and "pass" or "fail"
    elseif t == "predStackMin" or t == "predStackMax" then
        local s = PredStacks(sid, S)
        local ok = (t == "predStackMin") and (s >= (cl.v or 1)) or (s <= (cl.v or 1))
        return ok and "pass" or "fail"
    elseif t == "chargesMin" or t == "chargesMax" then
        local c = ChargeCount(sid); if c == nil then return "open" end
        local ok = (t == "chargesMin") and (c >= (cl.v or 1)) or (c <= (cl.v or 1))
        return ok and "pass" or "fail"
    elseif t == "auraRemainMin" or t == "auraRemainMax" then
        local r = Engine:AuraRemaining(sid); if r == nil then return "fail" end
        local ok = (t == "auraRemainMin") and (r >= (cl.v or 0)) or (r <= (cl.v or 0))
        return ok and "pass" or "fail"
    elseif t == "cdRemainMin" or t == "cdRemainMax" then
        local r = Engine:CooldownRemaining(sid); if r == nil then return "open" end
        local ok = (t == "cdRemainMin") and (r >= (cl.v or 0)) or (r <= (cl.v or 0))
        return ok and "pass" or "fail"
    elseif t == "resourceMin" or t == "resourceMax" then
        local v = S and S.maelstrom; if v == nil then return "open" end
        local ok = (t == "resourceMin") and (v >= (cl.v or 0)) or (v <= (cl.v or 0))
        return ok and "pass" or "fail"
    elseif t == "energyNearCap" or t == "energyNotNearCap" then
        local n = EnergyNearCap(); if n == nil then return "open" end
        local ok = (t == "energyNearCap") and n or (not n)
        return ok and "pass" or "fail"
    elseif t == "energyPctMin" or t == "energyPctMax" then
        local p = EnergyPct(); if p == nil then return "open" end
        local ok = (t == "energyPctMin") and (p >= (cl.v or 0)) or (p <= (cl.v or 0))
        return ok and "pass" or "fail"
    elseif t == "usable" or t == "notUsable" then
        local u = API.IsUsable(sid); if u == nil then return "open" end
        local ok = (t == "usable") and u or not u
        return ok and "pass" or "fail"
    end
    return EvalClause(cl, S, selfSid) and "pass" or "fail"
end

-- Whole-row status for the priority list dots: "pass" / "fail" / "open". A single
-- clause reports its own open state; groups collapse to pass/fail on the result.
function Cond.RowStatus(cond, S, selfSid)
    if not cond then return "pass" end                      -- no condition = always
    if not cond.clauses then return Cond.ClauseStatus(cond, S, selfSid) end
    if #cond.clauses == 0 then return "pass" end
    return Cond.Eval(cond, S, selfSid) and "pass" or "fail"
end

--------------------------------------------------------------------------------
-- Spec (re)binding
--------------------------------------------------------------------------------
function Engine:OnSpecChanged()
    local id = API.GetSpecID()
    spec = id and PRIO.specs and PRIO.specs[id] or nil
    wipe(idToKey)
    self.P = { fsExpire = 0, mote = false, skStacks = 0, maelstrom = 0, charges = {}, assumeActive = {}, auraExpire = {}, cdExpire = {}, stacks = {}, energyEst = nil, energyEstTime = nil }
    self:ResetExecuteRange()
    if not spec then return end
    if spec.chargeTrack then
        for key, cfg in pairs(spec.chargeTrack) do
            self.P.charges[key] = { cur = cfg.max, rechargeEnd = 0, dur = cfg.recharge }
        end
    end
    API.RefreshTracked()
    self:RefreshTalentFlags()

    for key, spellID in pairs(spec.spells) do
        idToKey[spellID] = key
        -- Map base/override IDs to the same key so cast events resolve.
        if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ovr = pcall(C_Spell.GetOverrideSpell, spellID)
            if ok and ovr and ovr ~= spellID then idToKey[ovr] = key end
        end
        if C_Spell and C_Spell.GetBaseSpell then
            local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
            if ok and base and base ~= spellID then idToKey[base] = key end
        end
    end

    self:MigrateCustom()
end

-- Cache talent-derived flags used by conditions (e.g. Master of the Elements).
-- Prefer a stable spell-ID match (spec.moteTalentID); fall back to the name lookup,
-- which is brittle to localization / node naming.
function Engine:RefreshTalentFlags()
    local byID   = spec and spec.moteTalentID and API.IsTalentSelected(spec.moteTalentID)
    local byName = spec and spec.moteTalent   and API.IsTalentSelectedByName(spec.moteTalent)
    self.hasMote = (byID or byName) and true or false
end
PRIO:On("TRAIT_CONFIG_UPDATED", function() Engine:RefreshTalentFlags() end)
PRIO:On("PLAYER_TALENT_UPDATE", function() Engine:RefreshTalentFlags() end)

--------------------------------------------------------------------------------
-- Hardcoded opener
--------------------------------------------------------------------------------
-- Per-mode opener sequences (ST / AoE). Custom copy in db.customOpeners[specKey][mode]
-- wins; else the spec default (spec.openerAoe for aoe, spec.opener otherwise). A legacy
-- flat array in customOpeners[specKey] is treated as the ST opener.
local function CustomOpener(key, mode)
    local co = PRIO.db.customOpeners and PRIO.db.customOpeners[key]
    if not co then return nil end
    if co[1] ~= nil then return (mode == "st") and co or nil end
    return co[mode]
end
local function DefaultOpener(mode)
    if mode == "aoe" and spec.openerAoe then return spec.openerAoe end
    return spec.opener
end
function Engine:ActiveOpener(mode)
    if not spec then return nil end
    mode = mode or self.openerMode or "st"
    return CustomOpener(spec.key, mode) or DefaultOpener(mode)
end

-- Begin the opener at combat start. Picks the ST/AoE opener from the pull's enemy
-- count, and only plays it when a signature cooldown is ready (ANY by default, or ALL
-- when "require all" is set). Skips leading steps already pre-cast.
function Engine:StartOpener()
    self.openerActive = false
    if not (PRIO.db.useOpener and spec) then return end
    local enemies = API.EnemyCount()
    self.openerMode = (enemies >= self:AoeThreshold(spec)) and "aoe" or "st"
    local op = self:ActiveOpener()
    if not (op and #op > 0) then return end
    -- Fresh-pull gate on the spec's signature cooldowns.
    local ready = spec.openerReady or {}
    local requireAll = PRIO.db.openerRequireAll and PRIO.db.openerRequireAll[spec.key]
    local ok
    if requireAll then
        ok = true
        for _, key in ipairs(ready) do
            local sid = spec.spells[key]
            if sid and API.IsKnown(sid) and not API.IsReady(sid) then ok = false; break end
        end
    else
        ok = false
        for _, key in ipairs(ready) do
            local sid = spec.spells[key]
            if sid and API.IsReady(sid) then ok = true; break end
        end
    end
    if not ok then return end
    local idx = 1
    while idx <= #op do
        local sid = spec.spells[op[idx]]
        if sid and API.IsKnown(sid) and API.IsReady(sid) then break end
        idx = idx + 1
    end
    if idx > #op then return end
    self.openerActive = true
    self.openerIndex  = idx
    self.openerStart  = GetTime()
end

-- Skip opener steps that aren't castable right now (already used / on cooldown),
-- so a long-CD step like Ascendance isn't shown when it's down.
function Engine:SkipOpenerSteps()
    local op = self:ActiveOpener() or {}
    while self.openerActive and self.openerIndex <= #op do
        local sid = spec.spells[op[self.openerIndex]]
        if sid and API.IsKnown(sid) and not API.IsReady(sid) then
            self.openerIndex = self.openerIndex + 1
        else
            break
        end
    end
    if self.openerActive and self.openerIndex > #op then self.openerActive = false end
end

-- Advance/abort the opener as the player casts.
function Engine:AdvanceOpener(key)
    if not self.openerActive then return end
    self:SkipOpenerSteps()
    if not self.openerActive then return end
    local op = self:ActiveOpener() or {}
    if key == op[self.openerIndex] then
        self.openerIndex = self.openerIndex + 1
        if self.openerIndex > #op then self.openerActive = false end
    elseif key then
        self.openerActive = false            -- deviated -> hand off to the priority
    end
end

PRIO:On("PLAYER_REGEN_DISABLED", function() Engine:StartOpener() end)

-- Pre-combat checks: out of combat, recommend the first missing item (weapon
-- imbue, group buff, shield).
function Engine:PrecombatResult(mode)
    if not (spec and spec.precombat and PRIO.db.showPrecombat) then return nil end
    for _, item in ipairs(spec.precombat) do
        local sid = spec.spells[item.spell]
        if sid and API.IsKnown(sid) then
            local missing = false
            if item.imbue then missing = not API.HasMainHandEnchant()
            elseif item.aura then missing = not API.HasAura(item.aura) end
            if missing then
                local e = Entry(sid)
                return {
                    specLabel = spec.label or "", modeLabel = "Pre-combat",
                    title = (spec.label or "") .. "  ·  Pre-combat",
                    primary = e, queue = {},
                    debug = { mode = "precombat", enemies = 0, primary = e.name },
                }
            end
        end
    end
    return nil
end

-- Repair saved custom lists whose stored spell IDs went stale (e.g. an entry
-- frozen at an old Earthquake/Flame Shock ID). If an entry's ID isn't known but
-- a spec spell with the SAME NAME is, remap it to the current ID.
function Engine:MigrateCustom()
    local cp = PRIO.db and PRIO.db.customPriorities
    if not (cp and spec and cp[spec.key]) then return end
    for _, list in pairs(cp[spec.key]) do
        for _, e in ipairs(list) do
            local sid = e.spell
            if type(sid) == "number" and not API.IsKnown(sid) then
                local name = API.SpellName(sid)
                for _, curID in pairs(spec.spells) do
                    if curID ~= sid and API.IsKnown(curID) and API.SpellName(curID) == name then
                        e.spell = curID
                        break
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Prediction: advance P on the player's own casts
--------------------------------------------------------------------------------
PRIO:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not spec then return end
    spellID = API.SafeNum(spellID)
    if not spellID then return end
    local key = idToKey[spellID]
    if not key then return end
    Engine.P.lastCast    = spellID          -- for "previous cast" conditions
    Engine.P.lastCastKey = key
    -- Spend a predicted charge and start its recharge.
    local cc = spec.chargeTrack and spec.chargeTrack[key] and Engine.P.charges[key]
    if cc then
        cc.cur = math.max(0, cc.cur - 1)
        if cc.rechargeEnd == 0 then cc.rechargeEnd = GetTime() + (cc.dur or spec.chargeTrack[key].recharge) end
    end
    -- Advance predicted buff stacks (Executioner's Precision: +1 per Execute, reset on
    -- Mortal Strike) from our own cast.
    if spec.stackTrack then
        Engine.P.stacks = Engine.P.stacks or {}
        Engine:AdvanceStacks(Engine.P.stacks, key)
    end
    if spec.OnCast then
        pcall(spec.OnCast, Engine.P, key, GetTime())
    end
    -- Spend Energy from the predicted pool the instant we cast a spender (before the
    -- next tick's regen integration), so the estimate drops immediately.
    local em = spec.energyModel and spec.energyModel.costs and spec.energyModel.costs[key]
    if em and Engine.P.energyEst then
        Engine.P.energyEst = math.max(0, Engine.P.energyEst - (EnergyCostOf(em) or 0))
    end
    -- Seed a predicted buff-duration timer (Zenith): fixed window, secret in combat, so
    -- we time it from the cast. Duration = base + any talented extensions that are known.
    local ad = spec.auraDurations and spec.auraDurations[key]
    if ad then
        local grants = ad.spell and { ad } or ad   -- single entry or a list of grants
        Engine.P.auraExpire = Engine.P.auraExpire or {}
        for _, g in ipairs(grants) do
            if not g.requires or API.IsKnown(g.requires) or API.IsTalentSelected(g.requires) then
                local dur = g.base or 0
                if g.extend then
                    for tid, sec in pairs(g.extend) do
                        if API.IsKnown(tid) or API.IsTalentSelected(tid) then dur = dur + sec end
                    end
                end
                local asid = g.spell or spellID
                -- max: a fresh grant refreshes UP; a shorter overlapping grant never shortens.
                Engine.P.auraExpire[asid] = math.max(Engine.P.auraExpire[asid] or 0, GetTime() + dur)
            end
        end
    end
    -- Seed a predicted cooldown timer (Invoke Xuen) so "cooldown > N" reads in combat.
    local ct = spec.cooldownTrack and spec.cooldownTrack[key]
    if ct then
        local cd = ct.base or 0
        if ct.reduce then
            for tid, sec in pairs(ct.reduce) do if API.IsKnown(tid) then cd = cd - sec end end
        end
        Engine.P.cdExpire = Engine.P.cdExpire or {}
        Engine.P.cdExpire[spellID] = GetTime() + cd
    end
    -- Assume a just-applied aura is up briefly, since the Cooldown Viewer read can lag
    -- a tick or two after you apply it (e.g. Flame Shock via Voltaic Blaze). The short
    -- window means a genuine immune/miss corrects itself once it expires.
    local ao = spec.assumeOnCast and spec.assumeOnCast[key]
    if ao then
        Engine.P.assumeActive = Engine.P.assumeActive or {}
        Engine.P.assumeActive[ao.aura] = GetTime() + (ao.dur or 4)
    end
    Engine:ApplyMaelstrom(Engine.P, spellID, key)   -- advance predicted Maelstrom
    Engine:AdvanceOpener(key)
end)

PRIO:On("PLAYER_REGEN_ENABLED", function()
    -- Combat ended: clear volatile procs; Maelstrom and charges keep syncing from
    -- the real values now that they're readable again.
    local P = Engine.P
    if P then P.fsExpire = 0; P.mote = false; P.skStacks = 0; if P.auraExpire then wipe(P.auraExpire) end; if P.stacks then wipe(P.stacks) end end
    Engine:ResetExecuteRange()
    Engine.openerActive = false
end)

-- A new target starts at full health -> drop the latched execute-range flag so it
-- can't carry over from the last mob.
PRIO:On("PLAYER_TARGET_CHANGED", function() Engine:ResetExecuteRange() end)

-- Predicted charge tracker. Real current charges are secret in combat, so we model
-- them and clamp to the readable castable state each tick.
function Engine:UpdateCharges(now)
    if not (spec and spec.chargeTrack) then return end
    local P = self.P
    for key, cfg in pairs(spec.chargeTrack) do
        local sid = spec.spells[key]
        local c = P.charges[key]
        if sid and c then
            local maxC, curC, dur = API.ChargeFull(sid)
            local cap = maxC or cfg.max
            if dur and dur > 0 then c.dur = dur end          -- learn real (haste'd) recharge OOC
            if curC ~= nil then                              -- exact when readable (OOC)
                c.cur = curC
                c.rechargeEnd = (curC < cap) and (now + (c.dur or cfg.recharge)) or 0
            else
                -- Recharge over time.
                while c.cur < cap and c.rechargeEnd > 0 and now >= c.rechargeEnd do
                    c.cur = c.cur + 1
                    c.rechargeEnd = (c.cur < cap) and (c.rechargeEnd + (c.dur or cfg.recharge)) or 0
                end
                -- resetAura (Lava Surge) rising edge -> a full charge back.
                if cfg.resetAura then
                    local up = API.IsAuraActive(cfg.resetAura) == true
                    if up and not c.resetPrev then
                        c.cur = math.min(cap, c.cur + 1)
                        c.rechargeEnd = (c.cur < cap) and (now + (c.dur or cfg.recharge)) or 0
                    end
                    c.resetPrev = up
                end
                -- Clamp to the readable castable state.
                if API.IsReady(sid) == false then
                    c.cur = 0
                    if c.rechargeEnd == 0 then c.rechargeEnd = now + (c.dur or cfg.recharge) end
                elseif c.cur < 1 then
                    c.cur = 1
                end
            end
            c.cur = math.max(0, math.min(cap, c.cur))
        end
    end
end

-- Predicted current charges for a charge-tracked spell (else nil).
function Engine:PredictedCharges(sid)
    if not (spec and spec.chargeTrack) then return nil end
    local key = idToKey[sid]
    local cfg = key and spec.chargeTrack[key]
    if cfg then local c = self.P.charges[key]; return c and c.cur or nil end
    return nil
end

-- Sync predicted Maelstrom to the real value whenever it's readable (out of
-- combat / between pulls). In combat it reads secret -> we keep the prediction.
PRIO:On("UNIT_POWER_UPDATE", function(unit)
    if unit ~= "player" or not spec or not spec.resource then return end
    local ms = API.Power(spec.resource)
    if ms ~= nil then Engine.P.maelstrom = ms end
end)

-- Advance predicted Maelstrom for a cast: spend the real cost, add spec generation.
function Engine:ApplyMaelstrom(P, sid, key)
    P.maelstrom = P.maelstrom or 0
    local cap = P.maelstromMax or (spec and spec.maelstromMax) or 150
    if spec and spec.ResourceDelta then
        local ok, delta = pcall(spec.ResourceDelta, spec, key, sid, { maelstrom = P.maelstrom })
        if ok and type(delta) == "number" then
            P.maelstrom = math.max(0, math.min(cap, P.maelstrom + delta))
            return
        end
    end
    local cost = API.PowerCostAmount(sid)
    if cost then P.maelstrom = math.max(0, P.maelstrom - cost) end
    local gen = spec and spec.maelstromGen and key and spec.maelstromGen[key]
    if gen then P.maelstrom = math.min(cap, P.maelstrom + gen) end
end

--------------------------------------------------------------------------------
-- Mode resolution
--------------------------------------------------------------------------------
local MODE_LABEL = {
    st = "Single Target", cleave = "Cleave", aoe = "AoE",
    st_execute = "ST (Execute)", aoe_execute = "AoE (Execute)", cleave_execute = "Cleave (Execute)",
}

-- Per-spec AoE threshold: a user override (db.aoeThreshold[specKey]) wins, else the
-- spec default, else the global. Lets a spec drop the cleave tier and expose "AoE at N".
local function AoeThreshold(specDef)
    local db = PRIO.db
    if specDef and db.aoeThreshold and db.aoeThreshold[specDef.key] then
        return db.aoeThreshold[specDef.key]
    end
    return (specDef and specDef.aoeAt) or db.aoeAt or 4
end
Engine.AoeThreshold = function(_, s) return AoeThreshold(s or spec) end

function Engine:ResolveMode(enemies)
    local db = PRIO.db
    if db.mode ~= "auto" then return db.mode end
    local aoeAt   = AoeThreshold(spec)
    local cleaveAt = (spec and spec.cleaveAt) or db.cleaveAt or 2
    if enemies >= aoeAt then return "aoe" end
    if cleaveAt < aoeAt and enemies >= cleaveAt then return "cleave" end   -- skip when collapsed
    return "st"
end

-- The editor mode tabs a spec offers. spec.modes overrides; default is ST/Cleave/AoE.
function Cond.SpecModes(s)
    if s and s.modes then return s.modes end
    return { { value = "st", text = "ST" }, { value = "cleave", text = "Cleave" }, { value = "aoe", text = "AoE" } }
end

-- Execute-phase detection, LATCHED. Target health is a secret value, so we can't read
-- "< 35%" directly. But an execute ability (spec.executeSpell) becomes usable ONLY in
-- execute range or on a proc -- so "usable AND not glowing (no proc)" means we're
-- genuinely in range. Rage (secret) also gates usability, which makes the raw read
-- flicker, so we LATCH: hold the flag on through brief non-usable dips, drop it after
-- spec.executeHold seconds without a fresh true (or on target change / combat end).
Engine.execLatch = { active = false, lastRaw = 0 }

function Engine:UpdateExecuteRange()
    local L = self.execLatch
    local ex = spec and spec.executeSpell
    if not ex then L.active = false; return false end
    local usable = API.UsableClean(ex)      -- true/false/nil (clean read)
    local glow   = API.SpellGlowing(ex)     -- true = a proc (e.g. Sudden Death) is up
    local raw = (usable == true) and (glow == false)   -- castable for a reason other than a proc
    local now = GetTime()
    if raw then
        L.active = true; L.lastRaw = now
    elseif L.active and (now - L.lastRaw) > (spec.executeHold or 4) then
        L.active = false
    end
    return L.active
end

function Engine:InExecuteRange() return self.execLatch.active end
function Engine:ResetExecuteRange() self.execLatch.active = false; self.execLatch.lastRaw = 0 end

--------------------------------------------------------------------------------
-- State object handed to each priority predicate
--------------------------------------------------------------------------------
local function BuildState(self, mode, enemies)
    local P = self.P
    local now = GetTime()

    -- Maelstrom: sync from the real value when readable (out of combat); otherwise
    -- carry the prediction. S.maelstrom is therefore ALWAYS a number.
    local realMs = spec.resource and API.Power(spec.resource) or nil
    if realMs ~= nil then P.maelstrom = realMs end
    local realMax = spec.resource and API.PowerMax(spec.resource) or nil
    if realMax ~= nil then P.maelstromMax = realMax end

    -- Expire a predicted MotE that was granted but never consumed.
    if P.mote and P.moteExpire and now >= P.moteExpire then P.mote = false end

    -- Anchor the predicted Flame Shock timer to the real Cooldown Viewer state
    -- when it's readable: definitively gone -> clear; up but our timer lapsed ->
    -- reseat it so we don't falsely report "expired".
    local fsID = spec.spells.FlameShock
    local fsActive = fsID and API.IsAuraActive(fsID) or nil
    if fsActive == false then
        P.fsExpire = 0
    elseif fsActive == true and (P.fsExpire or 0) <= now then
        P.fsExpire = now + 18
    end

    return {
        now       = now,
        mode      = mode,
        enemies   = enemies,
        execRange = self:InExecuteRange(),             -- latched flag (refreshed in Evaluate)
        maelstrom = P.maelstrom or 0,                  -- predicted (synced when readable)
        maelstromMax = P.maelstromMax or (spec and spec.maelstromMax) or 0,
        maelstromReadable = realMs ~= nil,
        mote      = P.mote and true or false,
        skStacks  = P.skStacks or 0,
        fsActive  = fsActive,                          -- true/false/nil (real read)
        fsRemaining = (P.fsExpire or 0) > now and (P.fsExpire - now) or 0,
        lastCastKey = P.lastCastKey,                   -- for "previous cast" conditions
        lastCastID  = P.lastCast,
        talent     = function(key) local id = spec.spells[key]; return id and API.IsKnown(id) end,
        ready      = function(key) local id = spec.spells[key]; return id and API.IsReady(id) end,
        auraActive = function(key) local id = spec.spells[key]; return id and API.IsAuraActive(id) end,
    }
end

--------------------------------------------------------------------------------
-- Evaluate: returns { title=, primary=, queue={} }
--------------------------------------------------------------------------------
Entry = function(spellID)
    return {
        id      = spellID,
        texture = API.SpellTexture(spellID),
        name    = API.SpellName(spellID),
        keybind = PRIO.db.showKeybinds and API.Keybind(spellID) or "",
    }
end

-- Resolve an entry's spell to a spellID (custom entries store a number, built-in
-- entries store a spec.spells key).
function Engine:EntrySpellID(e)
    if type(e.spell) == "number" then return e.spell end
    return spec and spec.spells[e.spell]
end

-- The effective list for a spec/mode: the user's custom copy if present, else the
-- built-in default.
local function ActivePriorityVariant(s)
    if not (s and s.priorityVariants and s.activeHero) then return nil end
    local ok, key = pcall(s.activeHero)
    return ok and key or nil
end

local function BuiltInList(s, mode, variantKey)
    if variantKey and s.priorityByVariant and s.priorityByVariant[variantKey] then
        local lists = s.priorityByVariant[variantKey]
        return lists[mode] or lists.st
    end
    return s.priority[mode] or s.priority.st
end

function Engine:EffectiveList(specKey, mode, variantKey)
    local cp = PRIO.db.customPriorities
    local curSpec = spec and spec.key == specKey and spec or nil
    local activeVariant = variantKey or ActivePriorityVariant(curSpec)
    if activeVariant and cp and cp[specKey] and cp[specKey].variants
        and cp[specKey].variants[activeVariant] and cp[specKey].variants[activeVariant][mode] then
        return cp[specKey].variants[activeVariant][mode], true
    end
    if activeVariant and cp and cp[specKey] and cp[specKey][mode] then
        return cp[specKey][mode], true
    end
    if not activeVariant and cp and cp[specKey] and cp[specKey][mode] then
        return cp[specKey][mode], true
    end
    return BuiltInList(curSpec or spec, mode, activeVariant), false
end

-- Current evaluation state (for the condition editor's live status).
function Engine:CurrentState()
    if not spec then return nil end
    local enemies = API.EnemyCount()
    return BuildState(self, self:ResolveMode(enemies), enemies)
end

-- Is this ability allowed to appear more than once in the queue?
--   * a charge spell -> up to its charge count (current if readable, else max), OR
--   * a pure filler: NOT a charge spell, no resource cost, no base cooldown
--     (Lightning Bolt / Chain Lightning) -> repeats freely to fill slots.
local function Repeatable(sid)
    -- Spec-tracked charge spell: use the PREDICTED current charges (Lava Burst).
    local pc = Engine:PredictedCharges(sid)
    if pc then return pc > 1, math.max(1, pc) end

    local maxC, curC = API.Charges(sid)
    if maxC then
        -- Cap at the CURRENT charge count. That's secret in combat, so assume 1
        -- rather than max -- otherwise a 1-charge Lava Burst gets recommended
        -- maxCharges times. The primary re-evaluates each tick and stays correct.
        local limit = (curC and curC > 0) and curC or 1
        return limit > 1, limit
    end
    if spec and spec.fillers and spec.fillers[sid] then
        return true, nil                 -- spec-declared spammable filler
    end
    return false                         -- single-use
end

-- Apply a cast's declared effects to the look-ahead sim: consume/grant auras,
-- and adjust the predicted Master of the Elements / Stormkeeper stacks. This lets
-- the queue reflect a beat ahead (Lava Burst eats Purging Flames, etc.).
-- Advance a predicted stack table (P.stacks live, or the sim copy) for a cast `key`.
-- spec.stackTrack is keyed by the buff's aura ID: gen = cast keys that add a stack
-- (capped at max), reset = cast keys that zero it. reset wins if a key is in both.
function Engine:AdvanceStacks(stacks, key)
    if not (spec and spec.stackTrack and key and stacks) then return end
    for auraID, cfg in pairs(spec.stackTrack) do
        local isReset, isGen = false, false
        for _, k in ipairs(cfg.reset or {}) do if k == key then isReset = true; break end end
        if not isReset then
            for _, k in ipairs(cfg.gen or {}) do if k == key then isGen = true; break end end
        end
        if isReset then
            stacks[auraID] = 0
        elseif isGen then
            stacks[auraID] = math.min(cfg.max or 99, (stacks[auraID] or 0) + 1)
        end
    end
end

local function ApplyEffects(sim, key)
    -- Predicted stacks advance for every cast, independent of spellEffects.
    if sim.stacks then Engine:AdvanceStacks(sim.stacks, key) end
    local fx = spec and spec.spellEffects and key and spec.spellEffects[key]
    if not fx then return end
    if fx.consume then for _, a in ipairs(fx.consume) do sim.aura[a] = false end end
    if fx.grant   then for _, a in ipairs(fx.grant)   do sim.aura[a] = true  end end
    if fx.mote ~= nil then sim.mote = fx.mote end
    if fx.skSet ~= nil then sim.sk = fx.skSet end
    if fx.skDelta then sim.sk = math.max(0, (sim.sk or 0) + fx.skDelta) end
end

local function ResourceCost(key, sid, S)
    if spec and spec.ResourceCost then
        local ok, cost = pcall(spec.ResourceCost, spec, key, sid, S)
        if ok and type(cost) == "number" then return cost end
    end
    return API.PowerCostAmount(sid)
end

-- Spend an Energy spender's cost from the look-ahead floor (no regen -- conservative).
-- Approx Energy regenerated in one look-ahead slot (~1 GCD). For an energy spec the GCD
-- shortens with haste at nearly the same rate Energy regen rises, so per-GCD gain is
-- roughly the un-hasted rate (base * talent * bias) -- no haste term needed.
local function EnergyPerSlot(m)
    local r = m.regenPerSec or 10
    if m.regenTalents then
        for tid, frac in pairs(m.regenTalents) do if API.IsKnown(tid) then r = r * (1 + frac) end end
    end
    return r * (m.regenBias or 1)
end

-- Advance the look-ahead Energy one slot: spend this cast's cost AND add ~1 GCD of regen,
-- so a spender isn't permanently locked out for the rest of the queue.
local function ApplyEnergy(sim, key)
    if sim.energy == nil then return end
    local m = spec and spec.energyModel
    if not m then return end
    local cost = EnergyCostOf(m.costs and m.costs[key]) or 0
    local max  = (Engine.P and Engine.P.energyMax) or 150
    sim.energy = math.max(0, math.min(max, sim.energy - cost + EnergyPerSlot(m)))
end

local function ApplyResourceDelta(sim, key, sid, S)
    if not (spec and spec.ResourceDelta and sim.resource ~= nil) then return end
    S.maelstrom = sim.resource
    local ok, delta = pcall(spec.ResourceDelta, spec, key, sid, S)
    if ok and type(delta) == "number" then
        local cap = S.maelstromMax or (spec and spec.maelstromMax) or 150
        sim.resource = math.max(0, math.min(cap, sim.resource + delta))
    end
end

-- The spec spell the player is currently hard-casting or channeling (nil if instant
-- / not casting / not a rotational spell). Instants never appear here, so this only
-- fires for casts that actually occupy time -- exactly when we want the primary to
-- advance past the spell already in flight. Resolves the cast to a spec KEY by ID
-- first, then by base/override ID, then by name (Farseer/Echo variants can report a
-- spellID that isn't the spec's canonical one).
function Engine:InFlightCast()
    local name, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
    if type(spellID) ~= "number" then
        name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
    end
    if type(spellID) ~= "number" then return nil, nil, nil end

    local key = idToKey[spellID]
    if not key and C_Spell and C_Spell.GetBaseSpell then
        local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
        if ok and base then key = idToKey[base] end
    end
    if not key and spec then                      -- last resort: match by name
        for k, sid in pairs(spec.spells) do
            if API.SpellName(sid) == name then key = k; break end
        end
    end
    return key, spellID, name
end

function Engine:Evaluate()
    if not spec then return nil end

    -- Opener: play the hardcoded sequence until it completes, times out, or the
    -- player deviates.
    if self.openerActive then
        if GetTime() - (self.openerStart or 0) > 15 then self.openerActive = false end
    end
    if self.openerActive then self:SkipOpenerSteps() end
    local openerSeq = self:ActiveOpener()
    if self.openerActive and openerSeq then
        local want2 = 1 + (PRIO.db.numQueue or 3)
        local picks, n = {}, 0
        for i = self.openerIndex, #openerSeq do
            if n >= want2 then break end
            local sid = spec.spells[openerSeq[i]]
            -- Only show steps that are known AND currently castable.
            if sid and API.IsKnown(sid) and API.IsReady(sid) then n = n + 1; picks[n] = Entry(sid) end
        end
        if n > 0 then
            return {
                specLabel = spec.label or "", modeLabel = "Opener", isOpener = true,
                title = (spec.label or "") .. "  ·  Opener",
                primary = picks[1], queue = { unpack(picks, 2) },
                debug = { mode = "opener", enemies = API.EnemyCount(), primary = picks[1].name },
            }
        end
        self.openerActive = false
    end

    local enemies = API.EnemyCount()
    local mode    = self:ResolveMode(enemies)
    -- Execute overlay: refresh the latch, then swap to the mode's execute variant
    -- (st -> st_execute, aoe -> aoe_execute) while we're in execute range.
    self:UpdateExecuteRange()
    local exMode = spec.executeMode and spec.executeMode[mode]
    if exMode and self:InExecuteRange() then mode = exMode end
    local list    = self:EffectiveList(spec.key, mode)
    local S        = BuildState(self, mode, enemies)
    local db       = PRIO.db
    local want     = 1 + (db.numQueue or 3)
    self:UpdateCharges(S.now)
    self:UpdateEnergy(S.now)

    -- Simple, predictable model: walk the list top-to-bottom, take the first entry
    -- that evaluates true as the pick, then EXCLUDE that row and walk again for the
    -- next -- unless the ability is repeatable (charges left, or a no-cooldown
    -- filler), in which case its row stays eligible.
    local picks = {}
    local usedRow, usedCharges, usedSpell = {}, {}, {}

    -- Look-ahead sim: aura overrides + predicted buffs advanced as we pick, so each
    -- queue slot evaluates against the state AFTER the earlier picks "cast".
    local realMote, realSk = S.mote, S.skStacks   -- for the debug window (S is mutated below)
    local sim = {
        aura = {}, mote = S.mote, sk = S.skStacks, resource = S.maelstrom,
        energy = self:EnergyEstimate(),   -- % * max (tracks to cap) or checkpoint floor; spent as we pick
        lastCastKey = S.lastCastKey, lastCastID = S.lastCastID,
        stacks = {},   -- predicted buff-stack counters, advanced per simulated cast
    }
    if Engine.P.stacks then for k, v in pairs(Engine.P.stacks) do sim.stacks[k] = v end end
    S._sim = sim.aura
    S._simStacks = sim.stacks

    -- If the player is mid-cast, treat that cast as already committed: fold its
    -- effects into the sim (so MotE/aura assumptions carry) and exclude it, so the
    -- PRIMARY advances to the next GCD instead of repeating the spell in flight.
    if PRIO.db.advanceWhileCasting ~= false then
        local castKey, castSid = self:InFlightCast()
        if castKey and castSid then
            ApplyEffects(sim, castKey)
            ApplyResourceDelta(sim, castKey, castSid, S)
            ApplyEnergy(sim, castKey)
            sim.lastCastKey, sim.lastCastID = castKey, castSid
            local rep, maxC = Repeatable(castSid)
            if maxC then
                usedCharges[castSid] = (usedCharges[castSid] or 0) + 1   -- one charge spent
            elseif not rep then
                usedSpell[castSid] = true                                -- don't re-show it
            end
        end
    end

    -- Test one list row as a candidate. HARD gates (known, charges, dup, cooldown, usable,
    -- Chi affordability, the row's own condition) are ALWAYS enforced -- we never suggest a
    -- button that can't be pressed or whose condition is false. The two SOFT gates -- Combo
    -- Strikes and the Energy PREDICTION -- are relaxed only in a fallback pass (relaxSoft),
    -- used when the strict walk can't fill a slot. Combo is a preference and the Energy
    -- gate is a guess, so relaxing them to avoid a blank beats leaving the queue short;
    -- Chi and cooldown are real, so they never relax.
    local function tryCandidate(i, relaxSoft)
        local e   = list[i]
        local sid = self:EntrySpellID(e)
        if not (sid and not e.off and API.IsKnown(sid)) then return nil end
        local rep, maxC = Repeatable(sid)
        if maxC and (usedCharges[sid] or 0) >= maxC then return nil end   -- charges spent
        if usedSpell[sid] and not rep and not maxC then return nil end    -- single-use, already picked
        -- Combo Strikes (Windwalker mastery): never cast the same ability twice in a row.
        if not relaxSoft and spec.comboStrikes and sim.lastCastKey and idToKey[sid] == sim.lastCastKey then
            return nil
        end

        local ready = e.ignoreCD or API.IsReady(sid)
        -- Primary-resource (Chi) gate, only when readable (secret combat fails open).
        if ready and S.maelstromReadable and (API.HasPowerCost(sid) or spec.ResourceCost) then
            local cost = ResourceCost(idToKey[sid], sid, S)
            if cost and S.maelstrom < cost then ready = false end
        end
        -- Energy prediction gate (soft): the bar is secret, so this is a dead-reckoned
        -- guess -- enforce it strictly, but relax it in the fallback rather than blank.
        if ready and not relaxSoft and sim.energy ~= nil then
            local em = spec.energyModel and spec.energyModel.costs and spec.energyModel.costs[idToKey[sid]]
            local ecost = EnergyCostOf(em)
            if ecost and sim.energy < ecost then ready = false end
        end
        if not (ready and API.IsUsable(sid)) then return nil end          -- hard: castable now
        if not PRIO.Cond.Eval(e.cond, S, sid) then return nil end
        return { sid = sid, i = i, rep = rep, maxC = maxC }
    end

    for slot = 1, want do
        S.mote        = sim.mote and true or false
        S.skStacks    = sim.sk or 0
        S.maelstrom   = sim.resource or S.maelstrom
        S.lastCastKey = sim.lastCastKey
        S.lastCastID  = sim.lastCastID
        local pick
        -- Strict pass first; if nothing qualifies, a fallback pass relaxes only the soft
        -- gates (Combo Strikes, Energy prediction) so the queue still fills a castable
        -- ability instead of going short.
        for _, relaxSoft in ipairs({ false, true }) do
            for i = 1, #list do
                if not usedRow[i] then
                    pick = tryCandidate(i, relaxSoft)
                    if pick then break end
                end
            end
            if pick then break end
        end
        if not pick then break end
        picks[slot] = Entry(pick.sid)
        -- Proc flash: does this cast fire empowered/instant in the current state?
        local fkey = idToKey[pick.sid]
        local fcond = spec.flash and fkey and spec.flash[fkey]
        picks[slot].flash = fcond and PRIO.Cond.Eval(fcond, S, pick.sid) or false
        ApplyEffects(sim, fkey)                             -- advance the look-ahead
        ApplyResourceDelta(sim, fkey, pick.sid, S)
        ApplyEnergy(sim, fkey)                              -- spend the Energy floor
        sim.lastCastKey, sim.lastCastID = fkey, pick.sid    -- "this slot cast" for the next
        if pick.maxC then                                   -- charge spell
            usedCharges[pick.sid] = (usedCharges[pick.sid] or 0) + 1
            if (usedCharges[pick.sid]) >= pick.maxC then usedRow[pick.i] = true end
        elseif not pick.rep then                            -- single-use
            usedRow[pick.i] = true
            usedSpell[pick.sid] = true                      -- and not again via another row
        end                                                 -- filler -> leave eligible
    end
    S._sim = nil
    S._simStacks = nil

    -- Safety net: never go blank in combat. If nothing qualified (e.g. a custom
    -- list with no valid filler), show a known filler, else any known spell.
    if #picks == 0 then
        local fb
        for i = 1, #list do
            local e = list[i]
            local sid = self:EntrySpellID(e)
            if sid and not e.off and API.IsKnown(sid) then
                fb = fb or sid
                if spec.fillers and spec.fillers[sid] then
                    fb = sid; break     -- prefer a declared filler
                end
            end
        end
        if fb then picks[1] = Entry(fb) end
    end

    if #picks == 0 then return nil end
    return {
        specLabel = spec.label or "",
        modeLabel = MODE_LABEL[mode] or mode,
        title     = (spec.label or "") .. "  ·  " .. (MODE_LABEL[mode] or mode),
        primary   = picks[1],
        queue     = { unpack(picks, 2) },
        debug     = {
            mode        = mode,
            enemies     = enemies,
            maelstrom   = S.maelstrom,
            maelstromMax = S.maelstromMax,
            mote        = realMote,
            skStacks    = realSk,
            fsActive    = S.fsActive,
            fsRemaining = S.fsRemaining,
            primary     = picks[1] and picks[1].name or "-",
        },
    }
end
