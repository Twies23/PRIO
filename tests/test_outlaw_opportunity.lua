-- test_outlaw_opportunity.lua -------------------------------------------------
-- Outlaw Opportunity PRESENCE. The live count isn't reliably readable in combat (the
-- Cooldown Manager renders max charges, the stack-delta marker is unreliable), so PRIO
-- doesn't resolve 3 vs 6 -- it anchors to the Pistol Shot glow: off => 0, on => a proc's
-- worth (3 with Fan the Hammer, 1 without). Never a phantom 6, so no cap-dump that
-- overcaps combo points. Lands in P.stacks so predStackMin(aura) reads it.
--------------------------------------------------------------------------------

local PISTOLSHOT = 185763
local OPP        = 279876
local FTH        = 381846   -- Fan the Hammer
local COMBO      = 4

local function setOutlaw(fanTheHammer)
    H.reset(); H.S.specID = 260
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 6
    if fanTheHammer then H.S.talents[FTH] = true end
    H.rebind()
end

local function tick() H.Engine:CurrentState() end

test("opportunity: glow off => 0, glow on => 3 with Fan the Hammer", function()
    setOutlaw(true)
    H.S.glows[PISTOLSHOT] = false; tick()
    eq(H.Engine.P.oppStacks, 0, "glow off -> 0")
    H.S.glows[PISTOLSHOT] = true; tick()
    eq(H.Engine.P.oppStacks, 3, "glow on -> a proc's worth (3)")
end)

test("opportunity: never reports the cap (stays 3 while the glow is up)", function()
    setOutlaw(true)
    H.S.glows[PISTOLSHOT] = true
    tick(); tick(); tick()
    eq(H.Engine.P.oppStacks, 3, "held glow stays 3, never a phantom 6")
    falsy(evalClause({ type = "predStackMin", spell = OPP, v = 6 }), "predStackMin(6) never true")
end)

test("opportunity: a max-charges (6) read does NOT inflate the count", function()
    setOutlaw(true)
    H.S.stackSource = { [OPP] = 6 }   -- CDM renders max charges even on a fresh proc
    H.S.glows[PISTOLSHOT] = true; tick()
    eq(H.Engine.P.oppStacks, 3, "glow-anchored 3, not synced up to the 6 read")
end)

test("opportunity: without Fan the Hammer, glow on => a single charge", function()
    setOutlaw(false)
    H.S.glows[PISTOLSHOT] = true; tick()
    eq(H.Engine.P.oppStacks, 1, "single charge without Fan the Hammer")
    H.S.glows[PISTOLSHOT] = false; tick()
    eq(H.Engine.P.oppStacks, 0, "glow off -> 0")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
