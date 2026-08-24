-- test_hero.lua ---------------------------------------------------------------
-- Hero-tree detection: must key on Invoke Xuen via a STRICT talent check, so it
-- can't flip to Conduit just because Xuen became tracked / was summoned.
--------------------------------------------------------------------------------

local XUEN = 123904

test("activeHero: Invoke Xuen talented -> conduit", function()
    H.reset()
    H.S.knownStrict[XUEN] = true
    eq(H.spec.activeHero(), "conduit")
end)

test("activeHero: Invoke Xuen not talented -> shadopan", function()
    H.reset()
    H.S.knownStrict[XUEN] = false
    eq(H.spec.activeHero(), "shadopan")
end)

test("activeHero: uses STRICT known -- tracked-but-not-talented does NOT flip", function()
    H.reset()
    H.S.knownStrict[XUEN] = false     -- not talented (Shado-Pan)
    H.S.tracked[XUEN] = true          -- but Xuen showed up in the Cooldown Manager
    H.S.known[XUEN] = true            -- and loose IsKnown would say "known"
    eq(H.spec.activeHero(), "shadopan", "must stay Shado-Pan despite Xuen being tracked")
end)

test("spec.priority resolves to the active hero's list", function()
    H.reset()
    H.S.knownStrict[XUEN] = true; H.rebind()
    truthy(H.spec.priority.st, "conduit st list should resolve")
    H.S.knownStrict[XUEN] = false; H.rebind()
    truthy(H.spec.priority.st, "shadopan st list should resolve")
end)
