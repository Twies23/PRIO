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

-- Named presets resolve to their underlying clause against the ACTIVE spec.
test("condPresets: resolve to the underlying glow / counter clause", function()
    H.reset(); H.S.specID = 71; H.rebind()
    -- "Sudden Death up" == Execute glow
    H.S.glows[EXECUTE] = true
    truthy(evalClause({ type = "preset:suddenDeath" }), "SD preset true when Execute glows")
    H.S.glows[EXECUTE] = false
    falsy(evalClause({ type = "preset:suddenDeath" }), "SD preset false when not glowing")
    -- "Imminent Demise (3)" == Bladestorm glow; "(<3)" is its inverse
    H.S.glows[BLADESTORM] = true
    truthy(evalClause({ type = "preset:immDemise3" }))
    falsy(evalClause({ type = "preset:immDemiseLt3" }))
    H.S.glows[BLADESTORM] = false
    falsy(evalClause({ type = "preset:immDemise3" }))
    truthy(evalClause({ type = "preset:immDemiseLt3" }))
    -- "Exec. Precision (2)" == predicted counter >= 2
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXECUTE)
    truthy(evalClause({ type = "preset:execPrec2" }), "EP preset true at 2 predicted stacks")
    -- Presets appear in the editor type list; raw glow/predstack do NOT.
    local types = H.Cond.TypesForSpec(H.armsSpec)
    local haveSD, haveRawGlow = false, false
    for _, m in ipairs(types) do
        if m.value == "preset:suddenDeath" then haveSD = true end
        if m.value == "glowing" or m.value == "predStackMin" then haveRawGlow = true end
    end
    truthy(haveSD, "preset shows in editor picker")
    falsy(haveRawGlow, "raw glow/predstack hidden from editor picker")
    H.reset(); H.rebind()
end)

-- Debuff conditions alias the tracked-aura read (buff logic), debuff-labeled.
test("debuffActive / debuffMissing read the tracked aura", function()
    H.reset()
    local REND = 772
    H.S.tracked[REND] = true
    H.S.auras[REND] = true
    truthy(evalClause({ type = "debuffActive", spell = REND }))
    falsy(evalClause({ type = "debuffMissing", spell = REND }))
    H.S.auras[REND] = false
    falsy(evalClause({ type = "debuffActive", spell = REND }))
    truthy(evalClause({ type = "debuffMissing", spell = REND }))
end)
