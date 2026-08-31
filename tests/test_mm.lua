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
