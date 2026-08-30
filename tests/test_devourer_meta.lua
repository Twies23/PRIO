-- test_devourer_meta.lua ------------------------------------------------------
-- Devourer's Void Metamorphosis phase overlay: while the form buff (1217607) is up,
-- the engine swaps the active list st -> st_meta / aoe -> aoe_meta (spec.phaseMode +
-- phaseActive), mirroring Arms' execute overlay. Collapsing Star is st_meta-only, so
-- it's the tell for whether the meta list is in play.
--------------------------------------------------------------------------------

local FORM     = 1217607
local COLLAPSE = 1227702   -- Collapsing Star: appears only in the (Meta) lists

local function dev()
    H.reset()
    H.S.specID = 1480
    H.rebind()
    H.Engine.openerActive = false
    H.db.numQueue = 1
    H.S.enemies = 1          -- ST
end

test("devourer meta: form up swaps ST -> ST (Meta)", function()
    dev()
    H.S.auras[FORM] = true
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, COLLAPSE, "in the form, the ST (Meta) list drives (Collapsing Star)")
end)

test("devourer meta: form down uses the plain ST list", function()
    dev()
    H.S.auras[FORM] = false
    local r = H.Engine:Evaluate()
    truthy(r.primary and r.primary.id ~= COLLAPSE, "outside the form, Collapsing Star isn't in ST")
end)

test("devourer meta: form up + Void-Scarred drives the AoE sequence", function()
    dev()
    H.S.enemies = 3          -- AoE
    H.S.auras[FORM] = true   -- in the form -> aoe_meta, where the Void-Scarred sequence lives
    local r = H.Engine:Evaluate()
    eq(r.debug and r.debug.mode, "sequence", "the sequence follower is driving")
    eq(r.primary and r.primary.id, 1225826, "sequence step 1 = Eradicate")
end)

test("devourer meta: off-sequence cast does NOT end the sequence (no deviations set)", function()
    dev()
    H.S.enemies = 3
    H.S.auras[FORM] = true
    H.Engine:Evaluate()                                        -- start (index 1)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 198589)  -- Blur (defensive, off-sequence)
    truthy(H.Engine.P.seq, "sequence survives an off-sequence cast")
    eq(H.Engine.P.seq.index, 1, "index unchanged by the off-sequence cast")
end)

test("devourer meta: sequence advances on cast and stops when the form ends", function()
    dev()
    H.S.enemies = 3
    H.S.auras[FORM] = true
    H.Engine:Evaluate()                                   -- starts the sequence (index 1)
    eq(H.Engine.P.seq and H.Engine.P.seq.id, "vs_aoe_meta", "sequence active")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1225826)  -- cast Eradicate (step 1)
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, 473728, "next step = Void Ray")
    H.S.auras[FORM] = false                               -- leave the form -> stop trigger
    H.Engine:Evaluate()
    falsy(H.Engine.P.seq, "sequence cleared when the form ended")
end)

test("devourer: Soul Immolation not double-recommended (2nd charge gated by its buff)", function()
    dev()
    local SI = 1241937
    H.db.numQueue = 3
    H.S.tracked[SI] = true
    H.S.auras[SI] = false                       -- buff down -> line eligible
    H.S.chargeState[SI] = { max = 2, cur = 2 }  -- both charges up (would repeat without the fix)
    local r = H.Engine:Evaluate()
    local n = 0
    if r.primary and r.primary.id == SI then n = n + 1 end
    for _, e in ipairs(r.queue or {}) do if e.id == SI then n = n + 1 end end
    eq(n, 1, "Soul Immolation appears once (sim marks its buff applied)")
end)

test("devourer: Moment of Craving gain -> 8s timer -> dump when expiring", function()
    dev()
    local MOC = 1238488
    H.S.auras[MOC] = true                 -- Moment of Craving gained (rising edge)
    H.Engine:CurrentState()               -- seeds an 8s timer at now=1000 (expire 1008)
    falsy(evalClause({ type = "auraRemainMax", spell = MOC, v = 2 }), ">2s left: hold")
    H.S.now = 1007                         -- 1s left
    truthy(evalClause({ type = "auraRemainMax", spell = MOC, v = 2 }), "<=2s left: dump")
end)

local HUNGER_BUFF = 1239519   -- Hungering Slash window (CDM)
local VOIDBLADE   = 1245412
test("devourer: Voidblade cast opens the Hungering Slash window (assume)", function()
    dev()
    local hs = { type = "buffActive", spell = HUNGER_BUFF }
    falsy(evalClause(hs), "window closed before Voidblade")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, VOIDBLADE)
    truthy(evalClause(hs), "Voidblade opens the window (assumed up)")
end)

test("devourer hero: Annihilator when Voidfall known, else Void-Scarred", function()
    dev()
    eq(H.devourerSpec.activeHero(), "voidscarred", "default is Void-Scarred")
    H.S.talents[1253304] = true                         -- Voidfall passive learned
    eq(H.devourerSpec.activeHero(), "annihilator", "Voidfall -> Annihilator")
end)

local CULL = 1245453
test("devourer meta: Cull fires at max charges (avoid overcap)", function()
    dev()
    H.S.auras[FORM] = true                                          -- ST (Meta) list
    H.S.chargeState[CULL] = { max = 2, cur = 2, belowMax = false }  -- Cull at max charges
    H.S.ready[COLLAPSE] = false; H.S.usable[COLLAPSE] = false        -- clear the line above Cull
    -- No ground souls set -> soulsGround(4) fails closed; the OR chargesMin(Cull,2) carries it.
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, CULL, "Cull fires at 2 charges without needing 4 ground souls")
end)
