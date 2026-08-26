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

-- Latched execute-range detection: usable-without-proc = in range; holds through rage
-- dips (spec.executeHold); resets on target change.
test("execute range: latch on usable-without-proc, hold, reset", function()
    H.reset(); H.S.specID = 71; H.rebind()
    local E = H.Engine

    -- Execute unusable -> not in range.
    H.S.usableClean[EXECUTE] = false; H.S.glows[EXECUTE] = false
    falsy(E:UpdateExecuteRange(), "unusable -> not in range")

    -- Usable with no proc glow -> in execute range (latched on).
    H.S.usableClean[EXECUTE] = true; H.S.glows[EXECUTE] = false
    truthy(E:UpdateExecuteRange(), "usable + no proc -> in range")

    -- A Sudden Death proc (glow) alone isn't range, but the latch holds.
    H.S.usableClean[EXECUTE] = true; H.S.glows[EXECUTE] = true
    truthy(E:UpdateExecuteRange(), "latch holds during a proc")

    -- Brief rage dip (unusable) within the hold window -> still latched.
    H.S.usableClean[EXECUTE] = false; H.S.glows[EXECUTE] = false
    truthy(E:UpdateExecuteRange(), "holds through a brief unusable dip")

    -- Past the hold window with no fresh true -> drops.
    H.S.now = H.S.now + 10
    falsy(E:UpdateExecuteRange(), "drops after the hold window")

    -- Re-latch, then a target change clears it immediately.
    H.S.usableClean[EXECUTE] = true; H.S.glows[EXECUTE] = false
    truthy(E:UpdateExecuteRange())
    H.fire("PLAYER_TARGET_CHANGED")
    falsy(E:InExecuteRange(), "target change resets the latch")

    -- The preset resolves to the latched flag.
    H.S.usableClean[EXECUTE] = true; H.S.glows[EXECUTE] = false
    E:UpdateExecuteRange()
    truthy(evalClause({ type = "preset:execRange" }), "In execute range preset true when latched")

    H.reset(); H.rebind()
end)

-- Execute overlay: Evaluate swaps ST->ST-Execute / AoE->AoE-Execute when latched,
-- and AoE kicks in at the (dropped-cleave) threshold of 2.
test("execute overlay swaps the active mode", function()
    H.reset(); H.S.specID = 71; H.rebind()
    H.S.enemies = 1

    -- Out of range -> plain ST.
    H.S.usableClean[EXECUTE] = false; H.S.glows[EXECUTE] = false
    eq(H.Engine:Evaluate().debug.mode, "st", "1 target, not in range -> st")

    -- In execute range -> ST (Execute).
    H.S.usableClean[EXECUTE] = true; H.S.glows[EXECUTE] = false
    eq(H.Engine:Evaluate().debug.mode, "st_execute", "1 target, in range -> st_execute")

    -- 2 targets: AoE tier (cleave dropped), and in range -> AoE (Execute).
    H.S.enemies = 2
    eq(H.Engine:Evaluate().debug.mode, "aoe_execute", "2 targets, in range -> aoe_execute")
    H.S.usableClean[EXECUTE] = false
    H.Engine:ResetExecuteRange()
    eq(H.Engine:Evaluate().debug.mode, "aoe", "2 targets, not in range -> aoe (no cleave tier)")

    H.reset(); H.rebind()
end)

-- Configurable opener: a custom sequence in db overrides the spec default.
test("opener: custom db override wins, else spec default", function()
    H.reset(); H.S.specID = 71; H.rebind()
    local def = H.armsSpec.opener
    truthy(def and #def > 0, "spec has a default opener")
    eq(H.Engine:ActiveOpener(), def, "no custom -> spec default")

    H.db.customOpeners = { [H.armsSpec.key] = { "Avatar", "MortalStrike" } }
    local ao = H.Engine:ActiveOpener()
    eq(ao[1], "Avatar"); eq(ao[2], "MortalStrike")
    eq(#ao, 2, "custom opener replaces the default entirely")

    H.db.customOpeners = nil
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
