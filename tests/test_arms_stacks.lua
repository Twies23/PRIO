-- test_arms_stacks.lua --------------------------------------------------------
-- Arms readable-signal modeling: proc-glow conditions (secret-safe boolean stand-in
-- for stacks) and the predicted Executioner's Precision counter advanced by casts.
--------------------------------------------------------------------------------

local EXECUTE   = 163201
local BLADESTORM = 227847
local CLEAVE    = 845
local MORTAL    = 12294
local EXECPREC  = 386634   -- Executioner's Precision (predicted stack aura id)

-- Proc-glow conditions read API.SpellGlowing (clean bool).
test("glowing: true when the spell is glowing", function()
    H.reset()
    H.S.glows[EXECUTE] = true
    truthy(evalClause({ type = "glowing", spell = EXECUTE }))
    falsy(evalClause({ type = "notGlowing", spell = EXECUTE }))
end)

test("glowing: false when not glowing", function()
    H.reset()
    H.S.glows[EXECUTE] = false
    falsy(evalClause({ type = "glowing", spell = EXECUTE }))
    truthy(evalClause({ type = "notGlowing", spell = EXECUTE }))
end)

test("glowing: nil (unreadable) -> not glowing, not-glowing also false", function()
    H.reset()   -- no glow set -> SpellGlowing returns nil
    falsy(evalClause({ type = "glowing", spell = BLADESTORM }))
    falsy(evalClause({ type = "notGlowing", spell = BLADESTORM }))
end)

-- Predicted Executioner's Precision: +1 per Execute (cap 2), reset by Mortal Strike.
test("stackTrack: Execute builds EP, caps at 2, Mortal Strike resets", function()
    H.reset(); H.S.specID = 71; H.rebind()   -- Arms active so spec.stackTrack applies
    eq(H.Engine.P.stacks[EXECPREC] or 0, 0, "starts at 0")

    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)
    eq(H.Engine.P.stacks[EXECPREC], 1, "one Execute -> 1")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)
    eq(H.Engine.P.stacks[EXECPREC], 2, "two Executes -> 2")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)
    eq(H.Engine.P.stacks[EXECPREC], 2, "third Execute -> still capped at 2")

    truthy(evalClause({ type = "predStackMin", spell = EXECPREC, v = 2 }), "predMin(2) passes at 2")

    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, MORTAL)
    eq(H.Engine.P.stacks[EXECPREC], 0, "Mortal Strike resets to 0")
    falsy(evalClause({ type = "predStackMin", spell = EXECPREC, v = 2 }), "predMin(2) fails at 0")

    H.reset(); H.rebind()   -- restore Windwalker as active spec for later suites
end)

-- predStackMin/Max read the predicted counter directly (no aura needed).
test("predStackMin/Max thresholds", function()
    H.reset(); H.S.specID = 71; H.rebind()
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)   -- EP = 1
    truthy(evalClause({ type = "predStackMin", spell = EXECPREC, v = 1 }))
    falsy(evalClause({ type = "predStackMin", spell = EXECPREC, v = 2 }))
    truthy(evalClause({ type = "predStackMax", spell = EXECPREC, v = 1 }))
    falsy(evalClause({ type = "predStackMax", spell = EXECPREC, v = 0 }))
    H.reset(); H.rebind()
end)
