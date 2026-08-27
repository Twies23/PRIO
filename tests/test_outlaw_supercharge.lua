-- test_outlaw_supercharge.lua -------------------------------------------------
-- Supercharger talent (470347): Adrenaline Rush supercharges 2 combo points; each
-- DAMAGING finisher (Dispatch, Between the Eyes, Killing Spree) consumes one. The count
-- is secret in combat -> PRIO predicts it from the player's own casts. Also covers the
-- new "=" comparison operator and the Stealthed condition.
--------------------------------------------------------------------------------

local AR, DISPATCH, BTE, KS = 13750, 2098, 315341, 51690
local SUPERCHARGER = 470347

local function setOutlaw()
    H.reset(); H.S.specID = 260
    H.S.power[4] = 0; H.S.powerMax[4] = 6
    H.rebind()
end
local function cast(id) H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, id) end

test("supercharge: AR sets 2; damaging finishers each consume one; floors at 0", function()
    setOutlaw()
    eq(H.Engine.P.superCharge or 0, 0, "starts at 0")
    cast(AR);       eq(H.Engine.P.superCharge, 2, "Adrenaline Rush supercharges 2")
    cast(DISPATCH); eq(H.Engine.P.superCharge, 1, "Dispatch consumes one")
    cast(KS);       eq(H.Engine.P.superCharge, 0, "Killing Spree consumes one")
    cast(BTE);      eq(H.Engine.P.superCharge, 0, "Between the Eyes floors at 0")
    cast(AR);       eq(H.Engine.P.superCharge, 2, "AR re-supercharges to 2 (not additive)")
end)

test("supercharge: inert without the Supercharger talent", function()
    setOutlaw()
    H.S.known[SUPERCHARGER] = false
    H.rebind()
    cast(AR)
    eq(H.Engine.P.superCharge or 0, 0, "untalented -> no supercharge counter")
end)

test("supercharge: a non-finisher builder does not consume it", function()
    setOutlaw()
    cast(AR)
    cast(193315)   -- Sinister Strike (builder)
    eq(H.Engine.P.superCharge, 2, "Sinister Strike doesn't consume supercharge")
end)

test("supercharge: reset to 0 on leaving combat", function()
    setOutlaw()
    cast(AR); eq(H.Engine.P.superCharge, 2)
    H.fire("PLAYER_REGEN_ENABLED")
    eq(H.Engine.P.superCharge, 0, "combat end clears the counter")
end)

test("supercharge conditions: >= / <= / = read S.superCharge", function()
    setOutlaw()
    cast(AR)   -- superCharge = 2
    truthy(evalClause({ type = "superChargeMin", v = 2 }), ">= 2 passes at 2")
    truthy(evalClause({ type = "superChargeMin", v = 1 }), ">= 1 passes at 2")
    falsy(evalClause({ type = "superChargeMax", v = 1 }),  "<= 1 fails at 2")
    truthy(evalClause({ type = "superChargeEq",  v = 2 }), "= 2 passes at 2")
    falsy(evalClause({ type = "superChargeEq",  v = 1 }),  "= 1 fails at 2")
    cast(DISPATCH)   -- -> 1
    truthy(evalClause({ type = "superChargeEq", v = 1 }), "= 1 passes at 1")
end)

test("equality operator: resource / opportunity '=' match exactly", function()
    setOutlaw()
    H.S.power[4] = 5
    H.rebind()
    truthy(evalClause({ type = "resourceEq", v = 5 }), "Combo Pts = 5 passes at 5")
    falsy(evalClause({ type = "resourceEq", v = 4 }),  "Combo Pts = 4 fails at 5")
    falsy(evalClause({ type = "resourceEq", v = 6 }),  "Combo Pts = 6 fails at 5")
    -- Opportunity '=' (predicted count; BuildState mirrors P.oppStacks -> P.stacks[aura],
    -- clamped to the Fan-the-Hammer cap of 6 -- without that talent the cap is 1).
    H.S.talents[381846] = true; H.rebind()
    H.Engine.P.oppStacks = 3
    truthy(evalClause({ type = "oppStacksEq", v = 3 }), "Opportunity = 3 passes at 3")
    falsy(evalClause({ type = "oppStacksEq", v = 6 }),  "Opportunity = 6 fails at 3")
end)

test("stealthed condition: reads IsStealthed() clean", function()
    setOutlaw()
    H.S.stealthed = false
    falsy(evalClause({ type = "stealthed" }),     "not stealthed -> stealthed fails")
    truthy(evalClause({ type = "notStealthed" }), "not stealthed -> notStealthed passes")
    H.S.stealthed = true
    truthy(evalClause({ type = "stealthed" }),    "stealthed -> stealthed passes")
    falsy(evalClause({ type = "notStealthed" }),  "stealthed -> notStealthed fails")
end)

test("outlaw picker: Stealth and Vanish are both selectable abilities", function()
    local pick = {}
    for _, k in ipairs(H.outlawSpec.pickable) do pick[k] = true end
    truthy(pick.Stealth, "Stealth is pickable")
    truthy(pick.Vanish,  "Vanish is pickable")
    eq(H.outlawSpec.spells.Stealth, 1784, "Stealth id wired")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
