-- test_bm.lua -----------------------------------------------------------------
-- Beast Mastery (253) smoke + hero-detection tests. Guards the structural
-- contract: the spec registers, both hero variants resolve for every mode, and
-- the Pack Leader / Dark Ranger split keys on a STRICT keystone check.
--------------------------------------------------------------------------------

local HOWL       = 471876   -- Howl of the Pack Leader (Pack Leader keystone)
local BLACKARROW = 466930   -- Black Arrow (Dark Ranger keystone)

test("BM spec registered under 253", function()
    truthy(H.bmSpec, "Beast Mastery spec should be registered")
    eq(H.bmSpec.className, "Hunter")
    eq(H.bmSpec.label, "Beast Mastery")
end)

test("activeHero: Howl talented -> pack_leader", function()
    H.reset()
    H.S.knownStrict[HOWL] = true
    eq(H.bmSpec.activeHero(), "pack_leader")
end)

test("activeHero: no Howl but Black Arrow -> dark_ranger", function()
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = true
    eq(H.bmSpec.activeHero(), "dark_ranger")
end)

test("activeHero: neither keystone -> pack_leader default", function()
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = false
    eq(H.bmSpec.activeHero(), "pack_leader")
end)

test("exposes only ST and AoE modes (no Cleave tier)", function()
    eq(#H.bmSpec.modes, 2)
    eq(H.bmSpec.modes[1].value, "st")
    eq(H.bmSpec.modes[2].value, "aoe")
    eq(H.bmSpec.cleaveAt, H.bmSpec.aoeAt, "cleaveAt == aoeAt collapses the Cleave tier")
end)

test("both hero variants resolve for every mode", function()
    for _, variant in ipairs({ "pack_leader", "dark_ranger" }) do
        local lists = H.bmSpec.priorityByVariant[variant]
        truthy(lists, variant .. " lists should exist")
        for _, mode in ipairs({ "st", "aoe" }) do
            truthy(lists[mode] and lists[mode][1], variant .. "." .. mode .. " should be a non-empty list")
        end
    end
end)

test("spec.priority proxy resolves to the active hero's list", function()
    H.reset()
    H.S.knownStrict[HOWL] = true
    truthy(H.bmSpec.priority.st and H.bmSpec.priority.st[1], "pack_leader st resolves")
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = true
    truthy(H.bmSpec.priority.aoe and H.bmSpec.priority.aoe[1], "dark_ranger aoe resolves")
end)

test("charge-time condition reads predicted time to next charge", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local BARBED = 217200
    local P = H.Engine.P
    -- At max charges -> no pending recharge -> nil.
    P.charges.BarbedShot = { cur = 2, rechargeEnd = 0, dur = 12 }
    eq(H.Engine:ChargeTimeRemaining(BARBED), nil)
    -- One charge banked, the next lands in 5s.
    P.charges.BarbedShot = { cur = 1, rechargeEnd = H.S.now + 5, dur = 12 }
    eq(H.Engine:ChargeTimeRemaining(BARBED), 5)
    truthy(H.Cond.Eval({ type = "chargeTimeMax", spell = BARBED, v = 6 }, H.S, BARBED), "next charge <= 6s passes")
    truthy(not H.Cond.Eval({ type = "chargeTimeMax", spell = BARBED, v = 1.5 }, H.S, BARBED), "next charge <= 1.5s fails")
end)

test("hasted charge recharge: Barbed Shot prediction scales with haste", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local BARBED = 217200
    -- 25% haste -> 12 / 1.25 = 9.6s recharge (not the unhasted 12s).
    H.S.haste = 25
    H.Engine.P.charges.BarbedShot = { cur = 2, rechargeEnd = 0, dur = 12 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, BARBED)   -- spend 2->1, seeds rechargeEnd
    local rem = H.Engine:ChargeTimeRemaining(BARBED)
    truthy(rem and math.abs(rem - 9.6) < 0.02, "expected ~9.6s hasted, got " .. tostring(rem))

    -- 0% haste -> the unhasted base 12s.
    H.reset(); H.S.specID = 253; H.rebind()
    H.S.haste = 0
    H.Engine.P.charges.BarbedShot = { cur = 2, rechargeEnd = 0, dur = 12 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, BARBED)
    eq(H.Engine:ChargeTimeRemaining(BARBED), 12, "no haste -> base 12s")
end)

test("charge-count rising edge re-anchors the recharge timer (erases drift)", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local BARBED = 217200
    H.S.haste = 0
    -- Combat: ChargeFull's raw count is secret (cur=nil) so UpdateCharges takes the
    -- predicted path; ChargeState still resolves the exact count via cleanCur.
    H.S.chargeState[BARBED] = { max = 2, cur = nil, cleanCur = 0, belowMax = true, recharge = 12 }
    H.S.ready[BARBED] = false                                   -- 0 charges, not usable
    -- Badly drifted prediction (recharge "ends" way in the future).
    H.Engine.P.charges.BarbedShot = { cur = 0, rechargeEnd = H.S.now + 999, dur = 12 }
    H.Engine:UpdateCharges(H.S.now)                            -- readPrev := 0 (no edge yet)
    -- A charge lands: exact count goes 0 -> 1, spell becomes usable.
    H.S.chargeState[BARBED].cleanCur = 1
    H.S.ready[BARBED] = true
    H.Engine:UpdateCharges(H.S.now)                            -- rising edge -> restart recharge from now
    eq(H.Engine:ChargeTimeRemaining(BARBED), 12, "0->1 edge restarts the recharge (drift erased)")
end)

test("charge-time anchors to the clean readable recharge (no drift)", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local BARBED = 217200
    -- Prediction drifted to 8s left, but the clean duration-object read says 3s -> clean wins.
    H.Engine.P.charges.BarbedShot = { cur = 1, rechargeEnd = H.S.now + 8, dur = 12 }
    local orig = H.API.ChargeRechargeRemaining
    H.API.ChargeRechargeRemaining = function(id) if id == BARBED then return 3 end end
    eq(H.Engine:ChargeTimeRemaining(BARBED), 3, "clean recharge read overrides the drifted prediction")
    H.API.ChargeRechargeRemaining = orig
end)

test("cast-triggered charge CDR speeds Kill Command / Barbed Shot timers", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local KC, COBRA, BARBED = 34026, 193455, 217200
    local WARORDERS, BARBEDSCALES = 393933, 469880
    local P = H.Engine.P

    -- Cobra Shot -> -1s Kill Command (baseline, no talent needed).
    P.charges.KillCommand = { cur = 1, rechargeEnd = H.S.now + 7, dur = 7.5 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, COBRA)
    eq(H.Engine:ChargeTimeRemaining(KC), 6, "Cobra Shot shaves 1s off Kill Command")

    -- War Orders (talented): Barbed Shot -> -3s Kill Command.
    H.S.talents[WARORDERS] = true
    P.charges.KillCommand = { cur = 1, rechargeEnd = H.S.now + 7, dur = 7.5 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, BARBED)
    eq(H.Engine:ChargeTimeRemaining(KC), 4, "War Orders shaves 3s off Kill Command")

    -- Without the talent, no reduction.
    H.S.talents[WARORDERS] = false
    P.charges.KillCommand = { cur = 1, rechargeEnd = H.S.now + 7, dur = 7.5 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, BARBED)
    eq(H.Engine:ChargeTimeRemaining(KC), 7, "no War Orders -> Barbed Shot doesn't touch Kill Command")

    -- Barbed Scales (talented): Cobra Shot -> -2s Barbed Shot.
    H.S.talents[BARBEDSCALES] = true
    P.charges.BarbedShot = { cur = 1, rechargeEnd = H.S.now + 8, dur = 12 }
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, COBRA)
    eq(H.Engine:ChargeTimeRemaining(BARBED), 6, "Barbed Scales shaves 2s off Barbed Shot")
end)

-- Focus is secret in combat. Spenders stay VISIBLE (softPowerUsable) but are flagged
-- entry.noResource when the game's insufficient-power flag says you can't afford them, so
-- the display desaturates them. Set up BM with only Kill Command castable.
local KC = 34026
local function setBMkc()
    H.reset(); H.S.specID = 253; H.S.enemies = 1
    setmetatable(H.S.ready, { __index = function() return false end })
    H.S.ready[KC] = true
    H.rebind()
    H.Engine.openerActive = false
end

test("BM: unaffordable Focus spender still shows, flagged noResource (for desaturation)", function()
    setBMkc(); H.S.insufficientPower[KC] = true
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.name == "Spell" .. KC, "Kill Command still shown when unaffordable")
    truthy(r.primary.noResource, "flagged noResource when insufficientPower=true (-> desaturated)")

    setBMkc(); H.S.insufficientPower[KC] = false
    local r2 = H.Engine:Evaluate()
    truthy(r2 and r2.primary and r2.primary.name == "Spell" .. KC, "shown when affordable")
    falsy(r2.primary.noResource, "not flagged when affordable")
end)

test("BM: Hunter's Mark maintenance reads the target-debuff state", function()
    H.reset(); H.S.specID = 253; H.rebind()
    local HM = 257284
    H.S.tracked[HM] = true
    -- Mark up on the target -> not missing -> the maintenance line stays inert.
    H.S.auras[HM] = true
    falsy(H.Cond.Eval({ type = "debuffMissing", spell = HM }, H.S, HM), "mark up -> not missing")
    -- Mark down -> missing -> reapply.
    H.S.auras[HM] = false
    truthy(H.Cond.Eval({ type = "debuffMissing", spell = HM }, H.S, HM), "mark down -> missing (reapply)")
end)

test("BM pet lines: a dead or missing pet is shown first", function()
    H.reset(); H.S.specID = 253; H.S.enemies = 1; H.rebind()
    H.Engine.openerActive = false
    local origE, origA = H.API.PetExists, H.API.PetAlive

    H.API.PetExists = function() return true end       -- pet exists but dead -> Revive Pet
    H.API.PetAlive  = function() return false end
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell982", "pet dead -> Revive Pet")

    H.API.PetExists = function() return false end       -- no pet -> Call Pet
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell883", "no pet -> Call Pet")

    H.API.PetExists = function() return true end         -- pet up -> guardian inert
    H.API.PetAlive  = function() return true end
    r = H.Engine:Evaluate()
    truthy(r and r.primary, "pet alive -> normal rotation")
    truthy(r.primary.name ~= "Spell982" and r.primary.name ~= "Spell883", "no pet spell shown when the pet is up")

    H.API.PetExists, H.API.PetAlive = origE, origA
end)

test("every priority row names a spell that exists in spec.spells", function()
    for variant, lists in pairs(H.bmSpec.priorityByVariant) do
        for mode, list in pairs(lists) do
            for i, row in ipairs(list) do
                truthy(H.bmSpec.spells[row.spell],
                    ("%s.%s[%d]: '%s' must be a known spec spell"):format(variant, mode, i, tostring(row.spell)))
            end
        end
    end
end)
