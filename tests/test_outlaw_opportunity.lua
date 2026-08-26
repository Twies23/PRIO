-- test_outlaw_opportunity.lua -------------------------------------------------
-- Outlaw Opportunity charge tracking. The count is secret in combat, so PRIO predicts
-- it, anchored to readable signals: Fan the Hammer makes each proc +3 / each Pistol
-- Shot -3 (cap 6, so values are 0/3/6), and the Pistol Shot glow pins the low end
-- (off => exactly 0). Grants land on detected Sinister Strike double-strikes; Pistol
-- Shot spends. Lands in P.stacks so predStackMin(aura) reads it.
--------------------------------------------------------------------------------

local SINISTER   = 193315
local PISTOLSHOT = 185763
local OPP        = 279876
local FTH        = 381846   -- Fan the Hammer
local ROLLBONES  = 1214909
local COMBO      = 4

local function setOutlaw(fanTheHammer)
    H.reset(); H.S.specID = 260
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 6
    H.S.stacks[OPP] = 0
    H.S.tracked[ROLLBONES] = true
    if fanTheHammer then H.S.talents[FTH] = true end
    H.rebind()
end

-- Fire a Sinister Strike whose marker (Opportunity) rises by `oppGain` over the window
-- (=> a double-strike), then run BuildState so the grant + reconcile fire.
local function doubleStrike()
    H.S.power[COMBO] = 0; H.S.stacks[OPP] = 0
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)
    H.S.now = H.S.now + 0.6
    H.S.power[COMBO] = 2          -- 2 CP = two strikes
    H.S.stacks[OPP] = 1          -- marker rose => double-strike detected
    H.Engine:CurrentState()
end

local function tick() H.Engine:CurrentState() end

test("opportunity: Fan the Hammer grants +3 per proc, caps at 6", function()
    setOutlaw(true)
    eq(H.Engine.P.oppStacks or 0, 0, "starts empty")
    doubleStrike(); eq(H.Engine.P.oppStacks, 3, "one proc -> 3")
    doubleStrike(); eq(H.Engine.P.oppStacks, 6, "two procs -> 6")
    doubleStrike(); eq(H.Engine.P.oppStacks, 6, "third proc -> still capped at 6")
    truthy(evalClause({ type = "predStackMin", spell = OPP, v = 6 }), "predStackMin(6) reads the cap")
end)

test("opportunity: Pistol Shot spends 3", function()
    setOutlaw(true)
    doubleStrike(); doubleStrike(); eq(H.Engine.P.oppStacks, 6, "at cap")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, PISTOLSHOT)
    eq(H.Engine.P.oppStacks, 3, "one Pistol Shot -> 3")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, PISTOLSHOT)
    eq(H.Engine.P.oppStacks, 0, "second Pistol Shot -> 0")
end)

test("opportunity: glow anchors the count (off => 0, on-while-empty => a proc's worth)", function()
    setOutlaw(true)
    doubleStrike(); doubleStrike(); eq(H.Engine.P.oppStacks, 6)
    H.S.glows[PISTOLSHOT] = false; tick()
    eq(H.Engine.P.oppStacks, 0, "glow off -> hard reset to 0")
    H.S.glows[PISTOLSHOT] = true; tick()
    eq(H.Engine.P.oppStacks, 3, "glow on while empty -> snap to a proc's worth (3)")
end)

test("opportunity: without Fan the Hammer it's a single charge (+1 / cap 1)", function()
    setOutlaw(false)
    doubleStrike(); eq(H.Engine.P.oppStacks, 1, "one proc -> 1")
    doubleStrike(); eq(H.Engine.P.oppStacks, 1, "capped at 1")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, PISTOLSHOT)
    eq(H.Engine.P.oppStacks, 0, "Pistol Shot -> 0")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
