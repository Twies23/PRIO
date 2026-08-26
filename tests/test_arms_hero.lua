-- test_arms_hero.lua ----------------------------------------------------------
-- Arms warrior hero split: keys on Demolish (436358, the Colossus capstone) via a
-- STRICT known check. Demolish talented -> Colossus; otherwise Slayer. Must not flip
-- to Colossus just because the Colossus Smash debuff (or anything else) is tracked.
--------------------------------------------------------------------------------

local DEMOLISH = 436358
local arms = H.armsSpec

test("arms activeHero: Demolish talented -> colossus", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = true
    eq(arms.activeHero(), "colossus")
end)

test("arms activeHero: Demolish not talented -> slayer (default)", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = false
    eq(arms.activeHero(), "slayer")
end)

test("arms activeHero: STRICT known -- tracked/loose-known does NOT flip", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = false   -- not talented (Slayer)
    H.S.tracked[DEMOLISH] = true        -- but showed up somewhere
    H.S.known[DEMOLISH] = true          -- and loose IsKnown would say "known"
    eq(arms.activeHero(), "slayer", "must stay Slayer despite loose/tracked Demolish")
end)

test("arms spec.priority resolves to the active hero's list", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = true
    truthy(arms.priority.st, "colossus st list should resolve")
    truthy(arms.priority.aoe, "colossus aoe list should resolve")
    truthy(arms.priority.cleave, "colossus cleave list should resolve")
    H.S.knownStrict[DEMOLISH] = false
    truthy(arms.priority.st, "slayer st list should resolve")
end)

-- The hero split must actually differ: Colossus casts Demolish, Slayer weaves
-- Bladestorm. Assert each list contains the signature and NOT the other's.
local function listHas(list, key)
    for _, e in ipairs(list) do if e.spell == key then return true end end
    return false
end

test("arms colossus st has Demolish, no Bladestorm weave", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = true
    local st = arms.priority.st
    truthy(listHas(st, "Demolish"), "Colossus ST should include Demolish")
    falsy(listHas(st, "Bladestorm"), "Colossus ST should not weave Bladestorm")
    falsy(listHas(st, "HeroicStrike"), "Colossus ST should not include the Slayer Heroic Strike")
end)

test("arms slayer st has Bladestorm weave, no Demolish", function()
    H.reset()
    H.S.knownStrict[DEMOLISH] = false
    local st = arms.priority.st
    truthy(listHas(st, "Bladestorm"), "Slayer ST should weave Bladestorm")
    truthy(listHas(st, "HeroicStrike"), "Slayer ST should include Heroic Strike")
    falsy(listHas(st, "Demolish"), "Slayer ST should not include Demolish")
end)
