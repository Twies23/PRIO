-- test_conditions.lua ---------------------------------------------------------
-- Condition evaluation against a mocked state. These lock in the tricky secret-safe
-- semantics (buff tracked/untracked, charges, energy near-cap, buff/cooldown timers).
--------------------------------------------------------------------------------

local ZENITH, UNBROKEN, BOKPROC, HEARTJADE, XUEN = 1249625, 1296624, 116768, 443294, 123904
local BOK, TIGERPALM, OBSIDIAN = 100784, 100780, 1249832

-- Chi model: Obsidian Spiral flips Blackout Kick from a 1-Chi spender to a +1 builder,
-- and it must be resilient to the talent being on or off.
test("chi: Blackout Kick costs 1 / delta -1 without Obsidian Spiral", function()
    H.reset()
    local S = {}
    eq(H.spec.ResourceCost(H.spec, "BlackoutKick", BOK, S), 1, "BoK costs 1 Chi")
    eq(H.spec.ResourceDelta(H.spec, "BlackoutKick", BOK, S), -1, "BoK nets -1 Chi")
end)
test("chi: Obsidian Spiral -> Blackout Kick costs 0 / delta +1 (builder)", function()
    H.reset()
    H.S.talents[OBSIDIAN] = true
    local S = {}
    eq(H.spec.ResourceCost(H.spec, "BlackoutKick", BOK, S), 0, "BoK free with Obsidian")
    eq(H.spec.ResourceDelta(H.spec, "BlackoutKick", BOK, S), 1, "BoK builds +1 with Obsidian")
end)
test("chi: Tiger Palm always builds +2", function()
    H.reset()
    eq(H.spec.ResourceDelta(H.spec, "TigerPalm", TIGERPALM, {}), 2)
end)


-- Has buff -------------------------------------------------------------------
test("buffActive: tracked & active -> pass", function()
    H.reset()
    H.S.tracked[UNBROKEN] = true; H.S.auras[UNBROKEN] = true
    truthy(evalClause({ type = "buffActive", spell = UNBROKEN }))
end)
test("buffActive: tracked & gone -> fail", function()
    H.reset()
    H.S.tracked[UNBROKEN] = true; H.S.auras[UNBROKEN] = false
    falsy(evalClause({ type = "buffActive", spell = UNBROKEN }))
end)
test("buffActive: untracked -> fail (can't confirm it's up)", function()
    H.reset()
    falsy(evalClause({ type = "buffActive", spell = UNBROKEN }))
end)

-- Missing buff (0.2.41 regression: untracked must PASS) -----------------------
test("buffMissing: tracked & gone -> pass", function()
    H.reset()
    H.S.tracked[UNBROKEN] = true; H.S.auras[UNBROKEN] = false
    truthy(evalClause({ type = "buffMissing", spell = UNBROKEN }))
end)
test("buffMissing: tracked & active -> fail", function()
    H.reset()
    H.S.tracked[UNBROKEN] = true; H.S.auras[UNBROKEN] = true
    falsy(evalClause({ type = "buffMissing", spell = UNBROKEN }))
end)
test("buffMissing: UNTRACKED -> pass (buff you can't have is missing)", function()
    H.reset()
    truthy(evalClause({ type = "buffMissing", spell = UNBROKEN }),
        "Unbroken Rhythm without the 4pc should read as missing")
end)

-- Charges --------------------------------------------------------------------
test("chargesMin: 2/2 >= 2 -> pass", function()
    H.reset()
    H.S.chargeState[ZENITH] = { max = 2, cur = 2, belowMax = false }
    truthy(evalClause({ type = "chargesMin", spell = ZENITH, v = 2 }))
end)
test("chargesMin: 1/2 >= 2 -> fail", function()
    H.reset()
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    falsy(evalClause({ type = "chargesMin", spell = ZENITH, v = 2 }))
end)

-- Chi (readable resource) ----------------------------------------------------
test("resourceMax: Chi 3 <= 2 -> fail; <= 3 -> pass", function()
    H.reset(); H.S.power[12] = 3
    falsy(evalClause({ type = "resourceMax", v = 2 }))
    truthy(evalClause({ type = "resourceMax", v = 3 }))
end)

-- Energy near cap ------------------------------------------------------------
test("energyNearCap: full -> pass, low -> fail", function()
    H.reset()
    H.Engine:UpdateEnergy(H.S.now)                 -- secret energy -> dead-reckons to max
    truthy(evalClause({ type = "energyNearCap" }), "150/150 should be near cap")
    H.Engine.P.energyEst = 50
    falsy(evalClause({ type = "energyNearCap" }), "50/150 should not be near cap")
end)

-- Buff time-left (predicted) -------------------------------------------------
test("auraRemainMax: HoJS 0.5s <= 1 -> pass; 5s -> fail", function()
    H.reset()
    H.Engine.P.auraExpire[HEARTJADE] = H.S.now + 0.5
    truthy(evalClause({ type = "auraRemainMax", spell = HEARTJADE, v = 1 }))
    H.Engine.P.auraExpire[HEARTJADE] = H.S.now + 5
    falsy(evalClause({ type = "auraRemainMax", spell = HEARTJADE, v = 1 }))
end)

-- Cooldown remaining (predicted) ---------------------------------------------
test("cdRemainMin: Xuen 30s left >= 10 -> pass; ready -> fail", function()
    H.reset()
    H.S.ready[XUEN] = false
    H.Engine.P.cdExpire[XUEN] = H.S.now + 30
    truthy(evalClause({ type = "cdRemainMin", spell = XUEN, v = 10 }))
    H.S.ready[XUEN] = true                          -- off cooldown -> 0 left
    falsy(evalClause({ type = "cdRemainMin", spell = XUEN, v = 10 }))
end)
