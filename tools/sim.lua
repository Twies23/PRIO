-- tools/sim.lua ----------------------------------------------------------------
-- Headless rotation simulator for Assassination Rogue (spec 259).
--
-- This drives the REAL Engine:Evaluate() -- the same code path the addon runs in
-- game -- against a modelled rogue, and reports what the shipped priority list
-- actually produces over a long fight. The point is not a DPS number (we have no
-- damage formulas); it is to check that the list BEHAVES: that it keeps bleeds up,
-- does not overcap combo points, does not stall on energy, cycles Darkest Night, and
-- lands near the cast distribution observed in three real +22 Mythic+ logs.
--
-- Faithful-to-PRIO detail: Assassination sets softPowerUsable, so the engine happily
-- recommends a spender you cannot yet afford (energy regenerates; you press it in a
-- moment). The sim models a player who FOLLOWS PRIO: if the primary is unaffordable it
-- WAITS rather than casting something else. That makes "time idle on energy" a real
-- quality signal for the list rather than an artefact.
--
-- WHAT IS AND IS NOT CALIBRATED -- read this before trusting a number:
--   TRUSTWORTHY: DoT uptimes, combo-point waste, time stalled on energy, Darkest Night
--   cycling, and ANY before/after or Deathstalker-vs-Fatebound comparison, because those
--   are relative and the model is identical on both sides.
--   NOT CALIBRATED: the absolute cast MIX. The sim has no PASSIVE combo-point sources --
--   Implacable Rank 4 hands you 5 free CP after Kingsbane, Deal Fate adds more, Venomous
--   Wounds funds energy -- so it under-generates CP and therefore under-casts finishers.
--   It runs ~2.5 generators per finisher against the reference logs' 1.82, which is why
--   Envenom reads low and Fan of Knives high. Raising the Seal Fate rate does not close
--   this (swept 0.33/0.45/0.55 -> 2.88/2.50/2.35); the missing mechanic is passive CP,
--   so the rate is left at a plausible 0.45 rather than over-fitted to the ratio.
--   ALSO EXPECTED: Mutilate reads ~12 points low in the 5-target run and Crimson Tempest
--   is absent from the 1-target run. The log figure is a whole DUNGEON -- it blends boss
--   single-target with trash AoE -- while each sim run is one fixed target count.
--
-- Not modelled (and so not claimed): damage, haste scaling, Envenom-chaining value,
-- per-target DoT bookkeeping beyond bleed coverage.
--
-- Run it with:  python tools/sim.py
--------------------------------------------------------------------------------

dofile(TESTS_DIR .. "\\harness.lua")

local COMBO = 4
local spec  = PRIO.specs[259]

-- id -> priority-list key, so we can act on whatever the engine hands back.
local nameOf = {}
for k, id in pairs(spec.spells) do nameOf[id] = k end

--------------------------------------------------------------------------------
-- Ability model. cost = Energy, cp = combo points generated (finishers spend all).
--------------------------------------------------------------------------------
local ABIL = {
    Mutilate       = { cost = 50, cp = 2 },
    Garrote        = { cost = 45, cp = 1, cd = 6 },
    FanOfKnives    = { cost = 35, cp = 1 },
    CrimsonTempest = { cost = 60, cp = 1 },
    Shiv           = { cost = 30, cp = 1, cd = 25 },
    Ambush         = { cost = 50, cp = 2, stealthOnly = true },
    Kingsbane      = { cost = 0,  cp = 1, cd = 60 },
    Envenom        = { cost = 35, finisher = true },
    Rupture        = { cost = 25, finisher = true },
    SliceandDice   = { cost = 25, finisher = true },
    Deathmark      = { cost = 0,  cd = 120 },
    Vanish         = { cost = 0,  cd = 120 },
    ThistleTea     = { cost = 0,  cd = 60 },
    Stealth        = { cost = 0 },
}

local ID = {
    GARROTE = 703, RUPTURE = 1943, ENVENOM = 32645, SND = 315496,
    DEATHMARK = 360194, KINGSBANE = 385627, IMPGARROTE = 381632,
    DSMARK = 457052, DARKNIGHT = 457058, SCENT = 381799, MUTILATE = 1329,
    CAUSTIC = 421975, STEALTH = 1784,
}

--------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------
local W = {}

local function newWorld(cfg)
    W = {
        t = 0, gcdUntil = 0,
        energy = 130, energyMax = 130, regen = cfg.regen or 28,
        cp = 0, cpMax = 7,
        targets = cfg.targets or 1,
        hero = cfg.hero,
        expiry = {},        -- auraID -> time it falls off
        cd = {},            -- key -> ready-at
        markStacks = 0,     -- Deathstalker's Mark (3 from Garrote, -1 per 5+ CP finisher)
        casts = {}, cpWasted = 0, energyWasted = 0,
        idle = 0, dnConsumed = 0, dnCpAtConsume = {},
        bleedUp = 0, ruptUp = 0, sndUp = 0, samples = 0,
        sealFateRate = cfg.sealFate or 0.33,
        rng = cfg.seed or 12345,
    }
end

-- Deterministic LCG so runs are reproducible.
local function rand()
    W.rng = (1103515245 * W.rng + 12345) % 2147483648
    return W.rng / 2147483648
end

local function up(id)  return (W.expiry[id] or 0) > W.t end
local function rem(id) return math.max(0, (W.expiry[id] or 0) - W.t) end

--------------------------------------------------------------------------------
-- Bridge the harness mocks to the world, so the ENGINE sees the simulated rogue.
--------------------------------------------------------------------------------
local API = PRIO.API
function API.Power(pt) if pt == COMBO then return W.cp end return nil end   -- Energy stays secret
function API.PowerMax(pt) if pt == COMBO then return W.cpMax end return W.energyMax end
function API.EnemyCount() return W.targets end
function API.IsAuraActive(id)
    if id == ID.DSMARK then return W.markStacks > 0 end   -- the Mark is stacks, not a timer
    return up(id)
end
function API.AuraStackCount(id)
    if id == ID.SCENT then return math.min(20, 4 * math.min(5, W.bleedTargets or 0)) end
    if id == ID.DSMARK then return W.markStacks end
    return up(id) and 1 or 0
end
function API.IsReady(id)
    local k = nameOf[id]; if not k then return true end
    return (W.cd[k] or 0) <= W.t
end
function API.IsUsable(id)
    local k = nameOf[id]; if not k then return true end
    if k == "Stealth" then return false end                       -- in combat
    if ABIL[k] and ABIL[k].stealthOnly then return up(ID.STEALTH) end
    return true
end
function API.UsableOrNoPower(id) return API.IsUsable(id) end       -- softPowerUsable
function API.InsufficientPower(id)
    local k = nameOf[id]; if not (k and ABIL[k]) then return nil end
    return W.energy < (ABIL[k].cost or 0)
end
-- Real pandemic: 30% of the duration we would reapply.
function API.InPandemic(id)
    if not up(id) then return false end
    if id == ID.GARROTE then return rem(id) <= 18 * 0.3 end
    if id == ID.RUPTURE then return rem(id) <= (4 + 4 * math.max(1, W.cp)) * 0.3 end
    return false
end
function API.Stealthed() return up(ID.STEALTH) end
function API.IsKnownStrict(id)
    if W.hero == "deathstalker" then return id == 1293340 end
    return id == 452536
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------
local function spendMark()
    if W.hero ~= "deathstalker" then return end
    if W.markStacks > 0 then
        W.markStacks = W.markStacks - 1
        if W.markStacks == 0 then W.expiry[ID.DARKNIGHT] = W.t + 20 end
    end
end

local function cast(key)
    local a = ABIL[key]; if not a then return end
    W.casts[key] = (W.casts[key] or 0) + 1
    W.energy = W.energy - (a.cost or 0)
    if a.cd then W.cd[key] = W.t + a.cd end

    if a.finisher then
        local spent = W.cp
        if spent >= 5 then spendMark() end
        if key == "Rupture" then
            W.expiry[ID.RUPTURE] = W.t + 4 + 4 * spent
            W.bleedTargets = math.min(W.targets, math.max(W.bleedTargets or 0, 1))
        elseif key == "Envenom" then
            W.expiry[ID.ENVENOM] = W.t + 1 + spent
            W.expiry[ID.SND] = W.t + 30                      -- Cut to the Chase
            W.expiry[ID.CAUSTIC] = W.t + 12
            if up(ID.DARKNIGHT) then                          -- consume Darkest Night
                W.expiry[ID.DARKNIGHT] = 0
                W.dnConsumed = W.dnConsumed + 1
                W.dnCpAtConsume[spent] = (W.dnCpAtConsume[spent] or 0) + 1
                W.markStacks = 3                              -- re-applies the Mark
            end
        elseif key == "SliceandDice" then
            W.expiry[ID.SND] = W.t + 6 + 6 * spent
        end
        W.cp = 0
        return
    end

    -- Generators
    local gain = a.cp or 0
    if gain > 0 then
        -- Seal Fate rolls PER TARGET HIT, so Fan of Knives / Crimson Tempest generate far
        -- more than their listed 1 CP in a pack. Capped at +3 to stay sane.
        local hits = 1
        if key == "FanOfKnives" or key == "CrimsonTempest" then hits = math.min(5, W.targets) end
        local procs = 0
        for _ = 1, hits do if rand() < W.sealFateRate then procs = procs + 1 end end
        gain = gain + math.min(3, procs)
    end
    if key == "Garrote" then
        local dur = up(ID.IMPGARROTE) and 18 or 18
        W.expiry[ID.GARROTE] = W.t + dur
        if W.hero == "deathstalker" and W.markStacks == 0 then W.markStacks = 3 end
    elseif key == "CrimsonTempest" then
        -- Spreads the bleeds you already have to the pack.
        if up(ID.RUPTURE) then W.bleedTargets = math.min(W.targets, (W.bleedTargets or 0) + 2) end
    elseif key == "Kingsbane" then
        W.expiry[ID.KINGSBANE] = W.t + 14
    elseif key == "Deathmark" then
        W.expiry[ID.DEATHMARK] = W.t + 16
        W.energy = math.min(W.energyMax, W.energy + 30)       -- Deathmark restores energy
    elseif key == "Vanish" then
        W.expiry[ID.IMPGARROTE] = W.t + 6
        W.expiry[ID.STEALTH] = W.t + 3
    elseif key == "ThistleTea" then
        W.energy = math.min(W.energyMax, W.energy + 100)
    end
    local before = W.cp
    W.cp = math.min(W.cpMax, W.cp + gain)
    W.cpWasted = W.cpWasted + math.max(0, (before + gain) - W.cpMax)
end

--------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------
local function run(cfg)
    newWorld(cfg)
    W.bleedTargets = 0
    W.packEvery = cfg.packEvery
    local STEP = 0.1
    local duration = cfg.duration or 300

    -- Pre-pull: the opener's first Garrote puts the Mark up.
    if W.hero == "deathstalker" then W.markStacks = 0 end

    while W.t < duration do
        -- Regen (and measure overcap).
        local gainE = W.regen * STEP
        local newE = W.energy + gainE
        if newE > W.energyMax then W.energyWasted = W.energyWasted + (newE - W.energyMax) end
        W.energy = math.min(W.energyMax, newE)

        -- Uptime sampling.
        W.samples = W.samples + 1
        if up(ID.GARROTE) then W.bleedUp = W.bleedUp + 1 end
        if up(ID.RUPTURE) then W.ruptUp = W.ruptUp + 1 end
        if up(ID.SND)     then W.sndUp  = W.sndUp  + 1 end
        if not up(ID.RUPTURE) then W.bleedTargets = 0 end
        if W.packEvery and W.t >= (W.nextPack or W.packEvery) then
            W.nextPack = W.t + W.packEvery          -- pack dies, a fresh one pulls
            W.expiry[ID.RUPTURE] = 0; W.expiry[ID.GARROTE] = 0
            W.bleedTargets = 0; W.packs = (W.packs or 0) + 1
        end

        if W.t >= W.gcdUntil then
            H.S.now = 1000 + W.t
            local ok, r = pcall(function() return PRIO.Engine:Evaluate() end)
            local key = ok and r and r.primary and nameOf[r.primary.id] or nil
            if key and ABIL[key] then
                if W.energy >= (ABIL[key].cost or 0) then
                    cast(key)
                    W.gcdUntil = W.t + 1.0
                else
                    W.idle = W.idle + STEP      -- following PRIO: wait for energy
                end
            else
                W.idle = W.idle + STEP
            end
        end
        W.t = W.t + STEP
    end
    return W
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------
-- Per-minute cast rates observed across the three reference logs (min-max), so the
-- sim can be checked against reality rather than against itself.
local LOGREF = {   -- share of all rotational casts, averaged over the three +22 M+ logs
    Envenom = 29.6, FanOfKnives = 22.2, CrimsonTempest = 15.1, Mutilate = 13.7,
    Garrote = 6.2, Rupture = 4.3, Shiv = 2.5, ThistleTea = 2.3, Kingsbane = 1.9,
    Deathmark = 1.0, Vanish = 0.9,
}

local function report(label, w, cfg)
    local mins = (cfg.duration or 300) / 60
    print(("\n=== %s  (%d target%s, %ds) ==="):format(label, w.targets, w.targets == 1 and "" or "s", cfg.duration))
    print(("  Garrote uptime %5.1f%%   Rupture %5.1f%%   Slice and Dice %5.1f%%")
        :format(w.bleedUp / w.samples * 100, w.ruptUp / w.samples * 100, w.sndUp / w.samples * 100))
    print(("  CP wasted %5.1f   Energy wasted %6.0f   Idle on energy %5.1f%%")
        :format(w.cpWasted, w.energyWasted, w.idle / (cfg.duration or 300) * 100))
    if w.hero == "deathstalker" then
        local at = {}
        for cp, n in pairs(w.dnCpAtConsume) do at[#at + 1] = ("%dcp x%d"):format(cp, n) end
        table.sort(at)
        print(("  Darkest Night consumed %d times (%s)"):format(w.dnConsumed, table.concat(at, ", ")))
    end
    local keys, total = {}, 0
    for k, n in pairs(w.casts) do keys[#keys + 1] = k; total = total + n end
    table.sort(keys, function(a, b) return w.casts[a] > w.casts[b] end)
    -- Share of casts, NOT casts/min. The reference logs are 26-minute DUNGEON runs, so
    -- their absolute rates are diluted by travel/downtime and blend single-target with
    -- AoE -- not comparable to continuous-combat sim. Share is scale-invariant. Only the
    -- 5-target run is compared, since a Mythic+ run is overwhelmingly multi-target trash.
    local FIN = { Envenom = true, Rupture = true, SliceandDice = true }
    local gen, fin = 0, 0
    for k, n in pairs(w.casts) do
        if FIN[k] then fin = fin + n
        elseif (ABIL[k] and (ABIL[k].cp or 0) > 0) then gen = gen + n end
    end
    print(("  generators per finisher %.2f   (reference logs: 1.82)"):format(fin > 0 and gen / fin or 0))
    local cmp = (w.targets >= 5)
    print(("  cast mix          sim%s"):format(cmp and "      log(M+ mix)   delta" or ""))
    for _, k in ipairs(keys) do
        local pct = w.casts[k] / total * 100
        local note = ""
        if cmp and LOGREF[k] then
            local d = pct - LOGREF[k]
            note = ("   %5.1f%%   %+6.1f%s"):format(LOGREF[k], d, math.abs(d) <= 7 and "" or "  <-- off")
        end
        print(("    %-15s %5.1f%%%s"):format(k, pct, note))
    end
end

--------------------------------------------------------------------------------
-- regen 28/s is BACK-COMPUTED from the reference logs (~1875 Energy spent over a
-- 66s window), i.e. base regen plus Venomous Wounds, which funds most of it.
local CFG = { duration = 600, regen = 28, sealFate = 0.45 }
for _, hero in ipairs({ "deathstalker", "fatebound" }) do
    for _, targets in ipairs({ 1, 5 }) do
        local cfg = { duration = CFG.duration, regen = CFG.regen, sealFate = CFG.sealFate,
                      hero = hero, targets = targets, seed = 99,
                      packEvery = (targets > 1) and 35 or nil }   -- M+ trash churns
        H.reset(); H.S.specID = 259
        H.S.tracked = setmetatable({}, { __index = function() return true end })
        H.rebind()
        local w = run(cfg)
        report(hero, w, cfg)
    end
end
print("")
