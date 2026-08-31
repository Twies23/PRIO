-- test_mm.lua -----------------------------------------------------------------
-- Marksmanship (254) smoke + the Unstable Trigger cooldown-window behaviour:
-- Explosive Shot's 30s runs from the FIRST press; a re-press within 3s (the
-- Unstable Trigger second cast) must NOT restart the timer.
--------------------------------------------------------------------------------

test("MM spec registered under 254", function()
    truthy(H.mmSpec, "Marksmanship spec should be registered")
    eq(H.mmSpec.className, "Hunter")
    truthy(H.mmSpec.priority.st and H.mmSpec.priority.st[1], "ST list resolves")
    truthy(H.mmSpec.priority.aoe and H.mmSpec.priority.aoe[1], "AoE list resolves")
end)

test("every MM priority row names a spell that exists in spec.spells", function()
    for mode, list in pairs(H.mmSpec.priority) do
        for i, row in ipairs(list) do
            truthy(H.mmSpec.spells[row.spell],
                ("%s[%d]: '%s' must be a known spec spell"):format(mode, i, tostring(row.spell)))
        end
    end
end)

test("MM pet lines gate on Unbreakable Bond (Lone Wolf -> no Call Pet)", function()
    local CALLPET, UNBREAKABLE = 883, 1223323
    H.reset(); H.S.specID = 254; H.S.enemies = 1
    setmetatable(H.S.ready, { __index = function() return false end })
    H.S.ready[CALLPET] = true
    local origE = H.API.PetExists
    H.API.PetExists = function() return false end        -- no pet -> petMissing true

    -- Lone Wolf (no Unbreakable Bond): Call Pet must NOT show.
    H.S.talents[UNBREAKABLE] = false
    H.rebind(); H.Engine.openerActive = false
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.name == "Spell" .. CALLPET),
        "no Unbreakable Bond -> Call Pet not shown (Lone Wolf)")

    -- With Unbreakable Bond: Call Pet shows.
    H.S.talents[UNBREAKABLE] = true
    H.rebind(); H.Engine.openerActive = false
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell" .. CALLPET, "Unbreakable Bond -> Call Pet shown")

    H.API.PetExists = origE
end)

test("Trueshot duration + cooldown-reduction tracking", function()
    local TS, CANTMISS, CALLING = 288613, 1253830, 260404

    -- Base (talents NOT known): 15s duration, 120s cooldown.
    H.reset(); H.S.specID = 254
    H.S.known[CANTMISS] = false; H.S.known[CALLING] = false
    H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TS)
    eq(H.Engine.P.auraExpire[TS], 1015, "base 15s Trueshot duration")
    eq(H.Engine.P.cdExpire[TS], 1120, "base 120s Trueshot cooldown")

    -- Talented: Can't Miss (+2s) and Calling the Shots (-30s).
    H.reset(); H.S.specID = 254
    H.S.known[CANTMISS] = true; H.S.known[CALLING] = true
    H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TS)
    eq(H.Engine.P.auraExpire[TS], 1017, "Can't Miss -> 17s duration")
    eq(H.Engine.P.cdExpire[TS], 1090, "Calling the Shots -> 90s cooldown")
end)

test("cooldownTrack window: Explosive Shot re-press within 3s doesn't restart the 30s", function()
    H.reset(); H.S.specID = 254; H.rebind()
    local EXP = 212431
    local P = H.Engine.P

    -- First press at t=1000 -> 30s cooldown seeded to 1030.
    H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXP)
    eq(P.cdExpire[EXP], 1030, "first press seeds a 30s cooldown")

    -- Second press at t=1002 (inside the 3s Unstable Trigger window) -> NOT re-seeded.
    H.S.now = 1002
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXP)
    eq(P.cdExpire[EXP], 1030, "re-press within the window keeps the original 30s (starts on the first press)")

    -- A fresh press after the cooldown -> restarts the 30s.
    H.S.now = 1035
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, EXP)
    eq(P.cdExpire[EXP], 1065, "a fresh press after the window restarts the 30s")
end)
