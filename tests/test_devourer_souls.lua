-- test_devourer_souls.lua -----------------------------------------------------
-- Devourer ground-soul counter (P.groundSouls, 0-10): souls pile up from casts, a
-- gather (Reap/Cull/Eradicate) sweeps to 0, the "souls on ground" boolean (1245577)
-- floors it to 0 when none are out, and it clamps to the 10 cap. Drives Reap/Cull at
-- >= 4 and Eradicate at >= 10 (capped).
--------------------------------------------------------------------------------

local GROUND = 1245577

local function devourer()
    H.reset()
    H.S.specID = 1480
    H.rebind()
end

test("devourer souls: casts pile souls onto the ground", function()
    devourer()
    H.Engine.P.groundSouls = 0
    H.devourerSpec.OnCast(H.Engine.P, "Consume", H.S.now)   -- +2
    H.devourerSpec.OnCast(H.Engine.P, "Devour", H.S.now)    -- +2
    H.devourerSpec.OnCast(H.Engine.P, "VoidRay", H.S.now)   -- +4
    eq(H.Engine.P.groundSouls, 8, "2 + 2 + 4 = 8 on the ground")
end)

test("devourer souls: Reap/Cull subtract 4, Eradicate clears", function()
    devourer()
    H.Engine.P.groundSouls = 7
    H.devourerSpec.OnCast(H.Engine.P, "Reap", H.S.now)      -- -4
    eq(H.Engine.P.groundSouls, 3, "Reap gathers 4 -> 3")
    H.devourerSpec.OnCast(H.Engine.P, "Cull", H.S.now)      -- -4, floors at 0
    eq(H.Engine.P.groundSouls, 0, "Cull -4 floors at 0")
    H.Engine.P.groundSouls = 8
    H.devourerSpec.OnCast(H.Engine.P, "Eradicate", H.S.now) -- clears
    eq(H.Engine.P.groundSouls, 0, "Eradicate clears the ground")
end)

test("devourer souls: transform drops 5 on the ground", function()
    devourer()
    H.Engine.P.groundSouls = 2
    H.devourerSpec.OnCast(H.Engine.P, "VoidMetamorphosis", H.S.now)
    eq(H.Engine.P.groundSouls, 7, "Void Metamorphosis +5")
end)

test("devourer souls: Hungering Slash shatters up to 2", function()
    devourer()
    H.Engine.P.groundSouls = 5
    H.devourerSpec.OnCast(H.Engine.P, "HungeringSlash", H.S.now)
    eq(H.Engine.P.groundSouls, 3, "Hungering Slash -2")
end)

test("devourer souls: clamps to the 10 cap", function()
    devourer()
    H.Engine.P.groundSouls = 8
    H.devourerSpec.OnCast(H.Engine.P, "CollapsingStar", H.S.now)  -- +5 -> clamps
    eq(H.Engine.P.groundSouls, 10, "clamps at 10 (extras auto-collect)")
end)

test("devourer souls: 'souls on ground' false forces the counter to 0", function()
    devourer()
    H.Engine.P.groundSouls = 6
    H.S.auras[GROUND] = false
    eq(H.Engine:CurrentState().groundSouls, 0, "boolean anchor zeroes it")
end)

test("devourer souls: 'Ground souls >= N' gates on the counter (fails closed)", function()
    devourer()
    H.S.auras[GROUND] = true
    H.Engine.P.groundSouls = 4
    truthy(evalClause({ type = "soulsGroundMin", v = 4 }), ">=4 passes at 4")
    H.Engine.P.groundSouls = 3
    falsy(evalClause({ type = "soulsGroundMin", v = 4 }), ">=4 fails at 3")
end)
