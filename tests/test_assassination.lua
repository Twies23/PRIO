-- test_assassination.lua -------------------------------------------------------
-- Assassination Rogue (259): hero split, the three 12.1 reworks that break a TWW-era
-- list (Crimson Tempest is a BUILDER, Slice and Dice is opener-only, Shiv is
-- tree-dependent), and the Deathstalker Darkest Night rules.
--
-- NOTE: the harness stubs API.InPandemic -> nil, so `refreshable` is always false
-- here. keepUp(x) therefore reduces to buffDown(x): clear S.auras[x] to make a
-- maintenance line fire, set it to make the DoT "up".
--------------------------------------------------------------------------------

local MUTILATE   = 1329
local GARROTE    = 703
local RUPTURE    = 1943
local ENVENOM    = 32645
local DEATHMARK  = 360194
local KINGSBANE  = 385627
local FOK        = 51723
local CRIMSONT   = 1247227
local SND        = 315496
local SHIV       = 5938
local MARKDEATH  = 1293340
local VANISH     = 1856
local STEALTH    = 1784
local IMPGARROTE = 381632
local DARKNIGHT  = 457058
local HANDOFFATE = 452536
local COMBO      = 4

local assa = H.assaSpec

-- A steady state: all bleeds/buffs already up, nothing on cooldown to chase, single
-- target, Stealth unusable (we are "in combat"). Individual tests poke one thing.
local function setAssa(hero)
    H.reset(); H.S.specID = 259
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 7
    H.S.enemies = 1
    for _, id in ipairs({ GARROTE, RUPTURE, ENVENOM, DEATHMARK, KINGSBANE, SND,
                          IMPGARROTE, DARKNIGHT, MARKDEATH }) do
        H.S.tracked[id] = true
    end
    -- Bleeds + Slice and Dice up, empowered window closed, no Darkest Night.
    H.S.auras[GARROTE] = true
    H.S.auras[RUPTURE] = true
    H.S.auras[SND]     = true
    H.S.auras[IMPGARROTE] = false
    H.S.auras[DARKNIGHT]  = false
    H.S.auras[DEATHMARK]  = false
    H.S.usable[STEALTH] = false        -- in combat
    -- Big cooldowns spent, so the steady-state lines below them get evaluated. Tests
    -- that care about Deathmark/Kingsbane/Vanish re-enable them explicitly.
    H.S.ready[DEATHMARK] = false
    H.S.ready[KINGSBANE] = false
    H.S.ready[VANISH]    = false
    if hero == "deathstalker" then
        H.S.knownStrict[MARKDEATH] = true
    else
        H.S.knownStrict[HANDOFFATE] = true
    end
    H.rebind()
end

-- Is `id` anywhere in the queue (primary or lookahead)?
local function suggests(r, id)
    if r.primary and r.primary.id == id then return true end
    for _, e in ipairs(r.queue or {}) do if e.id == id then return true end end
    return false
end

--------------------------------------------------------------------------------
-- Hero split
--------------------------------------------------------------------------------
test("assa activeHero: Hand of Fate talented -> fatebound", function()
    H.reset()
    H.S.knownStrict[HANDOFFATE] = true
    eq(assa.activeHero(), "fatebound")
end)

test("assa activeHero: Mark for Death (Deathstalker-granted) -> deathstalker", function()
    H.reset()
    H.S.knownStrict[MARKDEATH] = true
    eq(assa.activeHero(), "deathstalker")
end)

test("assa activeHero: neither known -> fatebound (default)", function()
    H.reset()
    eq(assa.activeHero(), "fatebound")
end)

test("assa activeHero: STRICT known -- tracked/loose-known does NOT flip the tree", function()
    H.reset()
    H.S.knownStrict[MARKDEATH] = false
    H.S.tracked[MARKDEATH] = true     -- it is in the Cooldown Manager
    H.S.known[MARKDEATH] = true       -- and loose IsKnown would say yes
    eq(assa.activeHero(), "fatebound", "must stay Fatebound on a strict check")
end)

test("assa spec.priority resolves to the active hero's list", function()
    H.reset(); H.S.knownStrict[MARKDEATH] = true
    eq(assa.priority.st, assa.priorityByVariant.deathstalker.st)
    H.reset(); H.S.knownStrict[HANDOFFATE] = true
    eq(assa.priority.st, assa.priorityByVariant.fatebound.st)
end)

--------------------------------------------------------------------------------
-- 12.1 rework 1: Crimson Tempest is a BUILDER, not a finisher
--------------------------------------------------------------------------------
test("assa: Crimson Tempest is NOT registered as a finisher", function()
    falsy(assa.finishers.CrimsonTempest, "CT must not be cost-clamped as a finisher")
    truthy(assa.finishers.Envenom,  "Envenom is a finisher")
    truthy(assa.finishers.Rupture,  "Rupture is a finisher")
    truthy(assa.finishers.SliceandDice, "Slice and Dice is a finisher")
end)

test("assa: Crimson Tempest is suggested at 0 CP in AoE (it builds, it does not spend)", function()
    setAssa("fatebound")
    H.S.enemies = 4
    H.S.power[COMBO] = 0
    local r = H.Engine:Evaluate()
    truthy(suggests(r, CRIMSONT), "CT should fire at 0 combo points on 4 targets")
end)

test("assa: Crimson Tempest is NOT suggested on a single target", function()
    setAssa("fatebound")
    H.S.enemies = 1
    H.S.power[COMBO] = 0
    local r = H.Engine:Evaluate()
    falsy(suggests(r, CRIMSONT), "CT is an AoE builder only")
end)

--------------------------------------------------------------------------------
-- 12.1 rework 2: Slice and Dice is opener-only (Cut to the Chase maintains it)
--------------------------------------------------------------------------------
test("assa: Slice and Dice fires when its buff is DOWN at 5+ CP", function()
    setAssa("fatebound")
    H.S.auras[SND] = false
    H.S.power[COMBO] = 5
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, SND, "SnD is the top line when the buff has dropped")
end)

test("assa: Slice and Dice is NEVER re-suggested while its buff is up", function()
    setAssa("fatebound")
    H.S.auras[SND] = true
    H.S.power[COMBO] = 7
    local r = H.Engine:Evaluate()
    falsy(suggests(r, SND), "Envenom extends SnD -- it must not be a maintenance line")
end)

--------------------------------------------------------------------------------
-- Finishers / builders
--------------------------------------------------------------------------------
test("assa: Envenom at 5 CP, Mutilate below 5", function()
    setAssa("fatebound")
    H.S.power[COMBO] = 5
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, ENVENOM, "Envenom dumps at 5 CP")

    setAssa("fatebound")
    H.S.power[COMBO] = 4
    local r2 = H.Engine:Evaluate()
    eq(r2.primary and r2.primary.id, MUTILATE, "Mutilate builds below 5 CP")
end)

test("assa: a dropped bleed outranks the finisher", function()
    setAssa("fatebound")
    H.S.power[COMBO] = 7
    H.S.auras[GARROTE] = false
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, GARROTE, "Garrote maintenance beats Envenom at max CP")
end)

test("assa: Garrote is suggested inside the Improved Garrote window", function()
    setAssa("fatebound")
    H.S.auras[GARROTE] = true          -- bleed is up...
    H.S.auras[IMPGARROTE] = true       -- ...but the empowered window is open
    H.S.power[COMBO] = 7
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, GARROTE, "re-Garrote to apply the empowered bleed")
end)

test("assa: Vanish only fires while Deathmark is up", function()
    setAssa("fatebound")
    H.S.ready[VANISH] = true
    H.S.auras[DEATHMARK] = false
    local r = H.Engine:Evaluate()
    falsy(suggests(r, VANISH), "no Vanish outside the burst window")

    setAssa("fatebound")
    H.S.ready[VANISH] = true
    H.S.auras[DEATHMARK] = true
    local r2 = H.Engine:Evaluate()
    truthy(suggests(r2, VANISH), "Vanish syncs to Deathmark to open Improved Garrote")
end)

--------------------------------------------------------------------------------
-- Deathstalker: Darkest Night
--------------------------------------------------------------------------------
test("deathstalker: Darkest Night + 7 CP -> Envenom", function()
    setAssa("deathstalker")
    H.S.auras[DARKNIGHT] = true
    H.S.power[COMBO] = 7
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, ENVENOM, "dump Darkest Night on a max-CP Envenom")
end)

test("deathstalker: Darkest Night at exactly 6 CP -> Shiv bridges to 7", function()
    setAssa("deathstalker")
    H.S.auras[DARKNIGHT] = true
    H.S.power[COMBO] = 6
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, SHIV, "Shiv is the 1-CP bridge from 6 to 7")
end)

test("deathstalker: Rupture is HELD while Darkest Night is up", function()
    setAssa("deathstalker")
    H.S.auras[RUPTURE] = false      -- Rupture has dropped
    H.S.auras[DARKNIGHT] = true     -- but Darkest Night is pending
    H.S.power[COMBO] = 7
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, ENVENOM,
       "Envenom must win -- a Rupture here would eat the Mark stack instead")
end)

test("deathstalker: Rupture resumes once Darkest Night is spent", function()
    setAssa("deathstalker")
    H.S.auras[RUPTURE] = false
    H.S.auras[DARKNIGHT] = false
    H.S.power[COMBO] = 7
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, RUPTURE, "Rupture is back on the menu")
end)

--------------------------------------------------------------------------------
-- Shiv placement differs by tree (log-confirmed: 31 casts DS vs 14-19 FB)
--------------------------------------------------------------------------------
test("deathstalker: Shiv on cooldown single-target, but NOT with adds up", function()
    setAssa("deathstalker")
    H.S.power[COMBO] = 4
    H.S.enemies = 1
    local r = H.Engine:Evaluate()
    truthy(suggests(r, SHIV), "Deathstalker presses Shiv in single target")

    setAssa("deathstalker")
    H.S.power[COMBO] = 4
    H.S.enemies = 4
    local r2 = H.Engine:Evaluate()
    falsy(r2.primary and r2.primary.id == SHIV,
          "never Shiv with adds up -- Fan of Knives is more efficient")
end)

test("fatebound: Shiv sits BELOW the builder (it is a ~1% loss for this tree)", function()
    setAssa("fatebound")
    H.S.power[COMBO] = 4
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, MUTILATE, "Mutilate outranks Shiv for Fatebound")
end)

test("fatebound: no Darkest Night lines leak into the Fatebound list", function()
    setAssa("fatebound")
    H.S.auras[DARKNIGHT] = true     -- even if somehow present
    H.S.power[COMBO] = 6
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, ENVENOM,
       "Fatebound has no 7-CP rule -- plain Envenom at 5+ CP")
end)

--------------------------------------------------------------------------------
-- Sanity: both trees registered, Ambush deliberately absent
--------------------------------------------------------------------------------
test("assa: both hero variants ship real lists", function()
    truthy(#assa.priorityByVariant.deathstalker.st > 5, "deathstalker ST list is populated")
    truthy(#assa.priorityByVariant.fatebound.st  > 5, "fatebound ST list is populated")
    truthy(#assa.priorityByVariant.deathstalker.aoe > #assa.priorityByVariant.deathstalker.st,
           "AoE adds the Crimson Tempest / Fan of Knives builders")
end)

test("assa: Ambush is not in the spell map (zero casts in all three reference logs)", function()
    falsy(assa.spells.Ambush, "Vanish->Garrote is the only stealth interaction in 12.1")
end)
