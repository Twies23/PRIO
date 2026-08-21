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
Cond.types = {
    { value = "buffActive",  text = "Has buff",       needsSpell = true },
    { value = "buffMissing", text = "Missing buff",   needsSpell = true },
    { value = "cdReady",     text = "Off cooldown",   needsSpell = true },
    { value = "cdNotReady",  text = "On cooldown",    needsSpell = true },
    { value = "talentYes",   text = "Talent selected",     needsTalent = true },
    { value = "talentNo",    text = "Talent not selected", needsTalent = true },
    { value = "lastCast",    text = "Just cast",       needsSpell = true },
    { value = "lastCastNot", text = "Didn't just cast", needsSpell = true },
    { value = "refreshable", text = "In pandemic (refreshable)", needsSpell = true },
    { value = "moteUp",      text = "MotE up" },
    { value = "moteDown",    text = "MotE down" },
    { value = "skStacks",    text = "SK stacks \226\137\165", needsValue = true, min = 1, max = 4, def = 1 },
    { value = "enemiesMin",  text = "Enemies \226\137\165",   needsValue = true, min = 1, max = 10, def = 2 },
    { value = "enemiesMax",  text = "Enemies \226\137\164",   needsValue = true, min = 1, max = 10, def = 1 },
}
function Cond.TypeMeta(t)
    for _, m in ipairs(Cond.types) do if m.value == t then return m end end
end

local function SpellShort(sid)
    if not sid then return "self" end
    return API.SpellName(sid)
end

function Cond.ClauseLabel(cl, selfSid)
    local t = cl.type
    local name = SpellShort(cl.spell or selfSid)
    if t == "buffActive" then return name .. " buff"
    elseif t == "buffMissing" then return "no " .. name .. " buff"
    elseif t == "cdReady" then return name .. " ready"
    elseif t == "cdNotReady" then return name .. " on CD"
    elseif t == "talentYes" then return (cl.spell and SpellShort(cl.spell) or "talent") .. " talented"
    elseif t == "talentNo" then return "no " .. (cl.spell and SpellShort(cl.spell) or "talent") .. " talent"
    elseif t == "lastCast" then return "just cast " .. name
    elseif t == "lastCastNot" then return "not just " .. name
    elseif t == "refreshable" then return name .. " refreshable"
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

function Cond.Copy(c)
    if not c then return nil end
    if c.clauses then
        local cl = {}
        for i, x in ipairs(c.clauses) do cl[i] = { type = x.type, spell = x.spell, v = x.v } end
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

local function EvalClause(cl, S, selfSid)
    local t = cl.type
    local sid = cl.spell or selfSid
    if t == "buffActive" then
        if S._sim and S._sim[sid] ~= nil then return S._sim[sid] end
        local a = API.IsAuraActive(sid); return a == true or a == nil
    elseif t == "buffMissing" then
        if S._sim and S._sim[sid] ~= nil then return not S._sim[sid] end
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
    local sid = cl.spell or selfSid
    if t == "buffActive" then
        local a = API.IsAuraActive(sid); if a == nil then return "open" end
        return a and "pass" or "fail"
    elseif t == "buffMissing" then
        local a = API.IsAuraActive(sid); if a == nil then return "open" end
        return (a == false) and "pass" or "fail"
    elseif t == "refreshable" then
        local a = API.InPandemic(sid); if a == nil then return "open" end
        return a and "pass" or "fail"
    end
    return EvalClause(cl, S, selfSid) and "pass" or "fail"
end

--------------------------------------------------------------------------------
-- Spec (re)binding
--------------------------------------------------------------------------------
function Engine:OnSpecChanged()
    local id = API.GetSpecID()
    spec = id and PRIO.specs and PRIO.specs[id] or nil
    wipe(idToKey)
    self.P = { fsExpire = 0, mote = false, skStacks = 0, maelstrom = 0, charges = {} }
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
-- Begin the opener at combat start, but only on a "fresh" pull (a big cooldown is
-- up). Skips any leading steps already pre-cast (on cooldown / no charge).
function Engine:StartOpener()
    self.openerActive = false
    if not (PRIO.db.useOpener and spec and spec.opener and #spec.opener > 0) then return end
    -- Fresh pull = one of the spec's signature cooldowns is ready.
    local fresh = false
    for _, key in ipairs(spec.openerReady or {}) do
        local sid = spec.spells[key]
        if sid and API.IsReady(sid) then fresh = true; break end
    end
    if not fresh then return end
    local idx = 1
    while idx <= #spec.opener do
        local sid = spec.spells[spec.opener[idx]]
        if sid and API.IsKnown(sid) and API.IsReady(sid) then break end
        idx = idx + 1
    end
    if idx > #spec.opener then return end
    self.openerActive = true
    self.openerIndex  = idx
    self.openerStart  = GetTime()
end

-- Skip opener steps that aren't castable right now (already used / on cooldown),
-- so a long-CD step like Ascendance isn't shown when it's down.
function Engine:SkipOpenerSteps()
    while self.openerActive and self.openerIndex <= #spec.opener do
        local sid = spec.spells[spec.opener[self.openerIndex]]
        if sid and API.IsKnown(sid) and not API.IsReady(sid) then
            self.openerIndex = self.openerIndex + 1
        else
            break
        end
    end
    if self.openerActive and self.openerIndex > #spec.opener then self.openerActive = false end
end

-- Advance/abort the opener as the player casts.
function Engine:AdvanceOpener(key)
    if not self.openerActive then return end
    self:SkipOpenerSteps()
    if not self.openerActive then return end
    if key == spec.opener[self.openerIndex] then
        self.openerIndex = self.openerIndex + 1
        if self.openerIndex > #spec.opener then self.openerActive = false end
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
    if spec.OnCast then
        pcall(spec.OnCast, Engine.P, key, GetTime())
    end
    Engine:ApplyMaelstrom(Engine.P, spellID, key)   -- advance predicted Maelstrom
    Engine:AdvanceOpener(key)
end)

PRIO:On("PLAYER_REGEN_ENABLED", function()
    -- Combat ended: clear volatile procs; Maelstrom and charges keep syncing from
    -- the real values now that they're readable again.
    local P = Engine.P
    if P then P.fsExpire = 0; P.mote = false; P.skStacks = 0 end
    Engine.openerActive = false
end)

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
    local cost = API.PowerCostAmount(sid)
    if cost then P.maelstrom = math.max(0, P.maelstrom - cost) end
    local gen = spec and spec.maelstromGen and key and spec.maelstromGen[key]
    if gen then P.maelstrom = math.min(cap, P.maelstrom + gen) end
end

--------------------------------------------------------------------------------
-- Mode resolution
--------------------------------------------------------------------------------
local MODE_LABEL = { st = "Single Target", cleave = "Cleave", aoe = "AoE" }

function Engine:ResolveMode(enemies)
    local db = PRIO.db
    if db.mode ~= "auto" then return db.mode end
    local aoeAt   = (spec and spec.aoeAt) or db.aoeAt or 4
    local cleaveAt = (spec and spec.cleaveAt) or db.cleaveAt or 2
    if enemies >= aoeAt then return "aoe" end
    if enemies >= cleaveAt then return "cleave" end
    return "st"
end

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
        maelstrom = P.maelstrom or 0,                  -- predicted (synced when readable)
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
function Engine:EffectiveList(specKey, mode)
    local cp = PRIO.db.customPriorities
    if cp and cp[specKey] and cp[specKey][mode] then
        return cp[specKey][mode], true
    end
    return spec.priority[mode] or spec.priority.st, false
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
local function ApplyEffects(sim, key)
    local fx = spec and spec.spellEffects and key and spec.spellEffects[key]
    if not fx then return end
    if fx.consume then for _, a in ipairs(fx.consume) do sim.aura[a] = false end end
    if fx.grant   then for _, a in ipairs(fx.grant)   do sim.aura[a] = true  end end
    if fx.mote ~= nil then sim.mote = fx.mote end
    if fx.skSet ~= nil then sim.sk = fx.skSet end
    if fx.skDelta then sim.sk = math.max(0, (sim.sk or 0) + fx.skDelta) end
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
    if self.openerActive and spec.opener then
        local want2 = 1 + (PRIO.db.numQueue or 3)
        local picks, n = {}, 0
        for i = self.openerIndex, #spec.opener do
            if n >= want2 then break end
            local sid = spec.spells[spec.opener[i]]
            -- Only show steps that are known AND currently castable.
            if sid and API.IsKnown(sid) and API.IsReady(sid) then n = n + 1; picks[n] = Entry(sid) end
        end
        if n > 0 then
            return {
                specLabel = spec.label or "", modeLabel = "Opener",
                title = (spec.label or "") .. "  ·  Opener",
                primary = picks[1], queue = { unpack(picks, 2) },
                debug = { mode = "opener", enemies = API.EnemyCount(), primary = picks[1].name },
            }
        end
        self.openerActive = false
    end

    local enemies = API.EnemyCount()
    local mode    = self:ResolveMode(enemies)
    local list    = self:EffectiveList(spec.key, mode)
    local S        = BuildState(self, mode, enemies)
    local db       = PRIO.db
    local want     = 1 + (db.numQueue or 3)
    self:UpdateCharges(S.now)

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
        aura = {}, mote = S.mote, sk = S.skStacks,
        lastCastKey = S.lastCastKey, lastCastID = S.lastCastID,
    }
    S._sim = sim.aura

    -- If the player is mid-cast, treat that cast as already committed: fold its
    -- effects into the sim (so MotE/aura assumptions carry) and exclude it, so the
    -- PRIMARY advances to the next GCD instead of repeating the spell in flight.
    if PRIO.db.advanceWhileCasting ~= false then
        local castKey, castSid = self:InFlightCast()
        if castKey and castSid then
            ApplyEffects(sim, castKey)
            sim.lastCastKey, sim.lastCastID = castKey, castSid
            local rep, maxC = Repeatable(castSid)
            if maxC then
                usedCharges[castSid] = (usedCharges[castSid] or 0) + 1   -- one charge spent
            elseif not rep then
                usedSpell[castSid] = true                                -- don't re-show it
            end
        end
    end

    for slot = 1, want do
        S.mote        = sim.mote and true or false
        S.skStacks    = sim.sk or 0
        S.lastCastKey = sim.lastCastKey
        S.lastCastID  = sim.lastCastID
        local pick
        for i = 1, #list do
            if not usedRow[i] then
                local e   = list[i]
                local sid = self:EntrySpellID(e)
                if sid and not e.off and API.IsKnown(sid) then
                    local rep, maxC = Repeatable(sid)
                    local chargeOK = not (maxC and (usedCharges[sid] or 0) >= maxC)
                    -- A single-use spell listed in multiple rows (like SimC's
                    -- repeated earthquake/elemental_blast lines) fires only once.
                    local dupBlocked = usedSpell[sid] and not rep and not maxC
                    if chargeOK and not dupBlocked then
                        local ready = e.ignoreCD or API.IsReady(sid)
                        -- Spender gate ONLY when Maelstrom is readable (out of combat).
                        -- In secret combat we can't trust the value, so never let it
                        -- freeze a spender -- fail open and let it fire.
                        if ready and API.HasPowerCost(sid) and S.maelstromReadable then
                            local cost = API.PowerCostAmount(sid)
                            if cost and S.maelstrom < cost then ready = false end
                        end
                        if ready and API.IsUsable(sid) and PRIO.Cond.Eval(e.cond, S, sid) then
                            pick = { sid = sid, i = i, rep = rep, maxC = maxC }
                            break
                        end
                    end
                end
            end
        end
        if not pick then break end
        picks[slot] = Entry(pick.sid)
        -- Proc flash: does this cast fire empowered/instant in the current state?
        local fkey = idToKey[pick.sid]
        local fcond = spec.flash and fkey and spec.flash[fkey]
        picks[slot].flash = fcond and PRIO.Cond.Eval(fcond, S, pick.sid) or false
        ApplyEffects(sim, fkey)                             -- advance the look-ahead
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
