-- test_subtlety.lua ------------------------------------------------------------
-- Subtlety Rogue (261): hero split, the Shadow Dance entry rules (Trickster at 6+ CP,
-- Deathstalker at <=2), the Shadow Blades <10s hold, Ancient Arts forcing, Coup de
-- Grace read off the Eviscerate override, and the Deathstalker Darkest Night rows.
--------------------------------------------------------------------------------

local EVISCERATE  = 196819
local COUPDEGRACE = 441776
local SECRETTECH  = 280719
local DANCE       = 185313
local BLADES      = 121471
local GOREMAW     = 426591
local BACKSTAB    = 53
local SHADOWSTRIKE = 185438
local STORM       = 197835
local BLACKPOWDER = 319175
local VANISH      = 1856
local STEALTH     = 1784
local SND         = 315496
local ANCIENTARTS = 1268932
local UNSEENBLADE = 441146
local MARKDEATH   = 1293340
local DSMARK      = 457052
local DARKNIGHT   = 457058
local COMBO       = 4

local sub = H.subSpec

-- Steady state out of Dance: cooldowns spent, Slice and Dice up, single target, not
-- stealthed (Stealth + Shadowstrike unusable). Tests poke one thing at a time.
local function setSub(hero, cp)
    H.reset(); H.S.specID = 261
    H.db.numQueue = 3                  -- primary + 3 (other suites change it)
    H.S.power[COMBO] = cp or 0; H.S.powerMax[COMBO] = 7
    H.S.enemies = 1
    for _, id in ipairs({ DANCE, BLADES, SND, ANCIENTARTS, DSMARK, DARKNIGHT, STEALTH }) do
        H.S.tracked[id] = true
    end
    H.S.auras[STEALTH] = false
    H.S.auras[DANCE] = false
    H.S.auras[BLADES] = false
    H.S.auras[SND] = true
    H.S.auras[ANCIENTARTS] = true
    H.S.auras[DSMARK] = true
    H.S.auras[DARKNIGHT] = false
    H.S.usable[STEALTH] = false
    H.S.usable[SHADOWSTRIKE] = false
    H.S.ready[GOREMAW] = false
    H.S.ready[BLADES] = false
    H.S.ready[VANISH] = false
    H.S.ready[SECRETTECH] = false
    H.S.ready[DANCE] = false
    if hero == "deathstalker" then
        H.S.knownStrict[MARKDEATH] = true
    else
        H.S.knownStrict[UNSEENBLADE] = true
    end
    H.rebind()
end

-- Put us inside a Shadow Dance (Shadowstrike usable).
local function inDance()
    H.S.auras[DANCE] = true
    H.S.usable[SHADOWSTRIKE] = true
end

local function primary() local r = H.Engine:Evaluate(); return r.primary and r.primary.id end

--------------------------------------------------------------------------------
-- Hero split
--------------------------------------------------------------------------------
test("sub activeHero: Unseen Blade -> trickster", function()
    H.reset(); H.S.knownStrict[UNSEENBLADE] = true
    eq(sub.activeHero(), "trickster")
end)

test("sub activeHero: Mark for Death -> deathstalker", function()
    H.reset(); H.S.knownStrict[MARKDEATH] = true
    eq(sub.activeHero(), "deathstalker")
end)

test("sub activeHero: neither known -> trickster (default)", function()
    H.reset()
    eq(sub.activeHero(), "trickster")
end)

test("sub spec.priority resolves to the active hero's list", function()
    H.reset(); H.S.knownStrict[MARKDEATH] = true
    eq(sub.priority.st, sub.priorityByVariant.deathstalker.st)
    H.reset(); H.S.knownStrict[UNSEENBLADE] = true
    eq(sub.priority.aoe, sub.priorityByVariant.trickster.aoe)
end)

--------------------------------------------------------------------------------
-- Basics
--------------------------------------------------------------------------------
test("sub: finishers registered (Eviscerate, Secret Technique, Black Powder)", function()
    truthy(sub.finishers.Eviscerate)
    truthy(sub.finishers.SecretTechnique)
    truthy(sub.finishers.BlackPowder)
end)

test("sub: Eviscerate at 6 CP outside Dance", function()
    setSub("trickster", 6)
    eq(primary(), EVISCERATE)
end)

test("sub: Backstab below 6 CP outside Dance (Shadowstrike unusable)", function()
    setSub("trickster", 3)
    eq(primary(), BACKSTAB)
end)

--------------------------------------------------------------------------------
-- Trickster: the user's tuned list (same list for ST and AoE)
--------------------------------------------------------------------------------
test("sub trickster: ST is 12 rows, AoE is 14 rows", function()
    local v = sub.priorityByVariant.trickster
    eq(#v.st, 12); eq(#v.aoe, 14)
    eq(v.aoe[14].spell, "ShurikenStorm")
end)

test("sub trickster AoE: Black Powder at 3+ targets, Eviscerate on 2 without Potent Powder", function()
    setSub("trickster", 6); H.S.enemies = 3
    eq(primary(), BLACKPOWDER, "3 targets")
    H.S.enemies = 2
    eq(primary(), EVISCERATE, "2 targets, no Potent Powder")
    H.S.talents[1265952] = true
    eq(primary(), BLACKPOWDER, "Potent Powder -> Black Powder at any count")
end)

test("sub trickster AoE: Coup de Grace beats Black Powder", function()
    setSub("trickster", 6); H.S.enemies = 4
    H.S.overrides = { [EVISCERATE] = COUPDEGRACE }
    eq(primary(), EVISCERATE)
end)

test("sub trickster AoE: Shuriken Storm builds", function()
    setSub("trickster", 2); H.S.enemies = 4
    eq(primary(), STORM)
end)

test("sub trickster: Shadowstrike from Stealth", function()
    setSub("trickster", 0)
    H.S.auras[STEALTH] = true; H.S.usable[SHADOWSTRIKE] = true
    eq(primary(), SHADOWSTRIKE)
end)

test("sub trickster: Shadow Blades then Goremaw's only when Dance is ready", function()
    setSub("trickster", 3)
    H.S.ready[BLADES] = true; H.S.ready[GOREMAW] = true
    eq(primary(), BACKSTAB, "Dance on cooldown -> hold both")
    H.S.ready[DANCE] = true
    eq(primary(), BLADES, "Dance ready -> Blades first")
    H.S.ready[BLADES] = false
    eq(primary(), GOREMAW, "then Goremaw's Bite")
end)

test("sub trickster: Dance at 6+ CP with Secret Technique ready", function()
    setSub("trickster", 6)
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true
    eq(primary(), DANCE)
end)

test("sub trickster: Dance at 6+ CP with Shadow Blades up", function()
    setSub("trickster", 6)
    H.S.ready[DANCE] = true
    H.S.auras[BLADES] = true
    eq(primary(), DANCE)
end)

test("sub trickster: no Dance below 6 CP, even with Blades up", function()
    setSub("trickster", 3)
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true
    H.S.auras[BLADES] = true
    eq(primary(), BACKSTAB)
end)

test("sub trickster: Secret Technique needs a supercharged combo point", function()
    setSub("trickster", 6); inDance()
    H.S.ready[SECRETTECH] = true
    H.Engine.P.superCharge = 1
    eq(primary(), SECRETTECH)
    H.Engine.P.superCharge = 0
    eq(primary(), EVISCERATE, "no supercharge -> Eviscerate")
end)

test("sub trickster: Vanish at <=2 CP", function()
    setSub("trickster", 2)
    H.S.ready[VANISH] = true
    eq(primary(), VANISH)
    setSub("trickster", 3)
    H.S.ready[VANISH] = true
    eq(primary(), BACKSTAB)
end)

test("sub trickster: Shadowstrike in Dance, Backstab only outside", function()
    setSub("trickster", 2); inDance()
    eq(primary(), SHADOWSTRIKE)
    H.S.ready[VANISH] = true
    eq(primary(), SHADOWSTRIKE, "no Vanish inside Dance")
end)


test("sub trickster: queue lines up Blades -> Goremaw's -> Dance -> Secret Technique", function()
    setSub("trickster", 7)
    H.Engine.P.superCharge = 0
    for _, id in ipairs({ BLADES, GOREMAW, DANCE, SECRETTECH }) do H.S.ready[id] = true end
    local r = H.Engine:Evaluate()
    local q = { r.primary and r.primary.id }
    for _, e in ipairs(r.queue or {}) do q[#q + 1] = e.id end
    eq(q[1], BLADES); eq(q[2], GOREMAW); eq(q[3], DANCE)
    eq(q[4], SECRETTECH, "Dance banks the supercharge Secret Technique needs")
end)

test("sub overrideActive: reads Eviscerate -> Coup de Grace", function()
    setSub("trickster", 6)
    local cl = { type = "overrideActive", spell = EVISCERATE, v = COUPDEGRACE }
    falsy(H.Cond.Eval(cl, { now = H.S.now }, EVISCERATE), "no override -> false")
    H.S.overrides = { [EVISCERATE] = COUPDEGRACE }
    truthy(H.Cond.Eval(cl, { now = H.S.now }, EVISCERATE), "override -> true")
    H.S.overrides = { [EVISCERATE] = 12345 }
    falsy(H.Cond.Eval(cl, { now = H.S.now }, EVISCERATE), "a different override -> false")
end)

test("sub DS AoE: Eviscerate applies a missing Slice and Dice", function()
    setSub("deathstalker", 6); H.S.enemies = 4
    H.S.auras[SND] = false
    eq(primary(), EVISCERATE)
end)

test("sub DS AoE: Shuriken Storm is the builder", function()
    setSub("deathstalker", 3); H.S.enemies = 4
    eq(primary(), STORM)
end)

--------------------------------------------------------------------------------
-- Deathstalker
--------------------------------------------------------------------------------
test("sub DS: Dance at <=2 CP with Secret Technique ready", function()
    setSub("deathstalker", 1)
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true
    eq(primary(), DANCE)
end)

test("sub DS: no Dance at 6 CP -- spend first", function()
    setSub("deathstalker", 6)
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true
    eq(primary(), EVISCERATE)
end)

test("sub DS: Darkest Night Eviscerate beats Secret Technique in Dance", function()
    setSub("deathstalker", 6); inDance()
    H.S.ready[SECRETTECH] = true
    H.S.auras[DARKNIGHT] = true
    eq(primary(), EVISCERATE)
end)

test("sub DS: Darkest Night without Ancient Arts -> one Shadowstrike first", function()
    setSub("deathstalker", 7); inDance()
    H.S.auras[DARKNIGHT] = true
    H.S.auras[ANCIENTARTS] = false
    eq(primary(), SHADOWSTRIKE)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SHADOWSTRIKE)
    eq(primary(), EVISCERATE)
end)

test("sub DS: Mark missing + no Darkest Night -> Shadowstrike re-applies it", function()
    setSub("deathstalker", 6); inDance()
    H.S.ready[SECRETTECH] = true
    H.S.auras[DSMARK] = false
    eq(primary(), SHADOWSTRIKE)
end)

test("sub trickster: Darkest Night / Mark rows are absent", function()
    setSub("trickster", 6); inDance()
    H.S.auras[DSMARK] = false
    eq(primary(), EVISCERATE, "Trickster has no Mark row")
end)

--------------------------------------------------------------------------------
-- Supercharger (shared engine tracker with Outlaw)
--------------------------------------------------------------------------------
local SUPERCHARGER = 470347
local PREMEDITATION = 343160
local function cast(id) H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, id) end
local function queueIds()
    local r = H.Engine:Evaluate()
    local out = { r.primary and r.primary.id }
    for _, e in ipairs(r.queue or {}) do out[#out + 1] = e.id end
    return out
end

test("sub supercharge: Dance banks 2, damaging finishers spend one each", function()
    setSub("trickster", 6)
    H.Engine.P.superCharge = 0
    cast(DANCE);       eq(H.Engine.P.superCharge, 2, "Shadow Dance supercharges 2")
    cast(EVISCERATE);  eq(H.Engine.P.superCharge, 1, "Eviscerate spends one")
    cast(BLACKPOWDER); eq(H.Engine.P.superCharge, 0, "Black Powder spends one")
    cast(SECRETTECH);  eq(H.Engine.P.superCharge, 0, "floors at 0")
    cast(BACKSTAB);    eq(H.Engine.P.superCharge, 0, "builders don't touch it")
end)

test("sub supercharge: persists out of combat (pre-pull Dance)", function()
    setSub("trickster", 0)
    cast(DANCE)
    H.fire("PLAYER_REGEN_ENABLED")
    eq(H.Engine.P.superCharge, 2, "banked charges survive combat end")
end)

test("sub supercharge: untalented -> no counter", function()
    setSub("trickster", 0)
    H.Engine.P.superCharge = 0
    H.S.known[SUPERCHARGER] = false
    cast(DANCE)
    eq(H.Engine.P.superCharge, 0)
end)

test("sub supercharge: the look-ahead spends it per queued finisher", function()
    setSub("trickster", 7)
    H.S.auras[ANCIENTARTS] = false
    H.S.ready[SECRETTECH] = true
    H.Engine.P.superCharge = 2
    PRIO.db.customPriorities["ROGUE_SUBTLETY"] = { variants = { trickster = { st = {
        { spell = "SecretTechnique", cond = { type = "superChargeMin", v = 2 } },
        { spell = "Eviscerate",      cond = { type = "superChargeEq",  v = 2 } },
        { spell = "Backstab" },
    } } } }
    local q = queueIds()
    PRIO.db.customPriorities["ROGUE_SUBTLETY"] = nil
    eq(q[1], SECRETTECH)
    eq(q[2], BACKSTAB, "after a queued finisher only 1 supercharged CP is left")
end)

--------------------------------------------------------------------------------
-- Queue prediction
--------------------------------------------------------------------------------
test("sub predict: Vanish -> Shadowstrike (Premeditation fills to max) -> Eviscerate", function()
    setSub("trickster", 1)
    H.S.auras[ANCIENTARTS] = false
    H.S.ready[VANISH] = true
    local q = queueIds()
    eq(q[1], VANISH)
    eq(q[2], SHADOWSTRIKE, "usable after the queued Vanish")
    eq(q[3], EVISCERATE, "Premeditation made it full combo points")
end)

test("sub predict: Shadow Blades doubles builders", function()
    setSub("trickster", 3)
    H.S.auras[ANCIENTARTS] = false
    H.S.auras[BLADES] = true
    local q = queueIds()
    eq(q[1], BACKSTAB); eq(q[2], BACKSTAB, "3 -> 5")
    eq(q[3], EVISCERATE, "5 -> 7 with Blades, so the third slot finishes")
end)

test("sub predict: Ancient Arts refunds a finisher -> Eviscerate twice", function()
    setSub("trickster", 6)
    local q = queueIds()
    eq(q[1], EVISCERATE)
    eq(q[2], EVISCERATE, "Ancient Arts refunds to max")
    eq(q[3], BACKSTAB, "refund consumed -> back to building")
end)

test("sub predict: Shuriken Storm gives 1 CP per target", function()
    setSub("deathstalker", 2); H.S.enemies = 4
    H.S.auras[ANCIENTARTS] = false
    local q = queueIds()
    eq(q[1], STORM)
    eq(q[2], BLACKPOWDER, "2 + 4 targets = 6")
end)

test("sub predict: queued Dance unlocks repeated Shadowstrikes", function()
    setSub("deathstalker", 1)
    H.S.auras[ANCIENTARTS] = false
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true
    local q = queueIds()
    eq(q[1], DANCE)
    eq(q[2], SHADOWSTRIKE, "usable after the queued Dance"); eq(q[3], SHADOWSTRIKE, "and again (no cooldown)")
    eq(q[4], SHADOWSTRIKE, "1 -> 3 -> 5 -> 7")
end)

test("sub predict: AoE Slice and Dice Eviscerate is not repeated", function()
    setSub("deathstalker", 7); H.S.enemies = 4
    H.S.auras[ANCIENTARTS] = true
    H.S.auras[SND] = false
    local q = queueIds()
    eq(q[1], EVISCERATE, "applies Slice and Dice")
    eq(q[2], BLACKPOWDER, "refunded to 7, Slice and Dice now up -> Black Powder")
end)

test("sub trickster: Eviscerate starts a missing Slice and Dice before cooldowns", function()
    setSub("trickster", 6)
    H.S.auras[SND] = false
    H.S.ready[DANCE] = true; H.S.ready[SECRETTECH] = true; H.S.ready[BLADES] = true
    eq(primary(), EVISCERATE)
end)

test("sub macros: every macro has a name and a body", function()
    truthy(sub.macros and #sub.macros >= 3)
    for _, m in ipairs(sub.macros) do
        truthy(m.name and m.name ~= "" and #m.name <= 16, "macro names are max 16 chars in game")
        truthy(m.body and m.body:find("^#showtooltip"), m.name .. " body")
        truthy(#m.body <= 255, m.name .. " fits the 255-char macro limit")
    end
end)

test("sub: every condition in the shipped lists is one the editor can show", function()
    H.reset(); H.S.specID = 261; H.rebind()
    local bad = {}
    local function walk(c, where)
        if type(c) ~= "table" then return end
        if c.clauses then for _, x in ipairs(c.clauses) do walk(x, where) end return end
        if c.type and not H.Cond.TypeMeta(c.type) then bad[#bad + 1] = where .. ": " .. c.type end
    end
    for hero, lists in pairs(sub.priorityByVariant) do
        for mode, list in pairs(lists) do
            for i, e in ipairs(list) do walk(e.cond, hero .. "/" .. mode .. " #" .. i) end
        end
    end
    eq(#bad, 0, table.concat(bad, ", "))
end)
