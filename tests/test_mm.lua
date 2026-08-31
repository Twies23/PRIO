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
    for variant, lists in pairs(H.mmSpec.priorityByVariant) do
        for mode, list in pairs(lists) do
            for i, row in ipairs(list) do
                if row.action then
                    truthy(H.mmSpec.actions[row.action],
                        ("%s.%s[%d]: action '%s' must be defined"):format(variant, mode, i, tostring(row.action)))
                else
                    truthy(H.mmSpec.spells[row.spell],
                        ("%s.%s[%d]: '%s' must be a known spec spell"):format(variant, mode, i, tostring(row.spell)))
                end
            end
        end
    end
end)

test("action node: Switch Targets is picked (spell-less) when its condition passes", function()
    H.reset(); H.S.specID = 254; H.S.enemies = 1
    setmetatable(H.S.ready, { __index = function() return false end })
    H.rebind(); H.Engine.openerActive = false
    -- A tiny action-only custom list with an always-true condition.
    local list = { { action = "switchTargets", cond = nil } }
    PRIO.db.customPriorities = { HUNTER_MARKSMANSHIP = { st = list, aoe = list } }
    H.rebind()
    local res = H.Engine:Evaluate()
    truthy(res and res.primary and res.primary.isAction, "action node is the primary")
    eq(res.primary.name, "Target Switch")
    PRIO.db.customPriorities = {}
end)

test("MM variant select: Black Arrow -> dark_ranger, else sentinel", function()
    H.reset(); H.S.knownStrict[466930] = true
    eq(H.mmSpec.activeHero(), "dark_ranger")
    H.reset(); H.S.knownStrict[466930] = false
    eq(H.mmSpec.activeHero(), "sentinel")
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

test("Hunter's Mark reads the TARGET aura (per-target), fail-closed on no read", function()
    local HMARK = 257284
    H.reset(); H.S.specID = 254; H.S.enemies = 1
    setmetatable(H.S.ready, { __index = function() return false end })
    H.S.ready[HMARK] = true

    -- Target confirmed to LACK the mark -> the line fires.
    H.S.targetAuras[HMARK] = false
    H.rebind(); H.Engine.openerActive = false
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell" .. HMARK, "target missing the mark -> Hunter's Mark shown")

    -- Mark present on the target -> the line does NOT fire.
    H.S.targetAuras[HMARK] = true
    H.rebind(); H.Engine.openerActive = false
    r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.name == "Spell" .. HMARK),
        "mark on target -> Hunter's Mark not shown")

    -- No target / secret (nil) -> fail-closed: do NOT nag.
    H.S.targetAuras[HMARK] = nil
    H.rebind(); H.Engine.openerActive = false
    r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.name == "Spell" .. HMARK),
        "unreadable target aura -> Hunter's Mark not shown (fail-closed)")
end)

test("Moonlight Chakram once-per-Trueshot flag", function()
    H.reset(); H.S.specID = 254; H.rebind()
    local TS, CHAKRAM = 288613, 1264902
    -- Casting Trueshot while it's NOT active opens a fresh window (Chakram available).
    H.S.auras[TS] = false
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TS)
    eq(H.Engine.P.predFlags.chakramUsed, false, "Trueshot start (not active) -> window open")
    -- Casting Moonlight Chakram spends it.
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, CHAKRAM)
    eq(H.Engine.P.predFlags.chakramUsed, true, "Moonlight Chakram marks it used")
    -- The override may report as Trueshot's id: a Trueshot-key cast WHILE active = Chakram.
    H.reset(); H.S.specID = 254; H.rebind()
    H.S.auras[TS] = true
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TS)
    eq(H.Engine.P.predFlags.chakramUsed, true, "Trueshot-key cast while active = Chakram press -> used")
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
