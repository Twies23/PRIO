-- test_outlaw_opportunity.lua -------------------------------------------------
-- Outlaw Opportunity charge count (0/3/6 with Fan the Hammer). A Sinister Strike
-- double-strike grants Opportunity, detected from the DELAYED combo-point bump
-- (>instantWindow, <=doubleWindow after the cast); each proc = +3 charges (cap 6).
-- Pistol Shot spends 3. The Pistol Shot glow anchors it: off => 0, on-while-0 => a
-- proc's worth. Lands in P.stacks so predStackMin(aura) reads it.
--------------------------------------------------------------------------------

local SINISTER   = 193315
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

-- A Sinister Strike that double-strikes: instant bump (stage) at ~0ms, then a delayed
-- bump (the second hit) at `delay`s -> one Opportunity proc.
local function doubleStrike(startCP, instant, delayed)
    H.S.power[COMBO] = startCP
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)
    H.S.power[COMBO] = startCP + instant           -- instant bump (stage)
    H.fire("UNIT_POWER_UPDATE", "player")
    H.S.now = H.S.now + 0.25                        -- the double-strike lands later
    H.S.power[COMBO] = startCP + instant + delayed  -- delayed bump = the double
    H.fire("UNIT_POWER_UPDATE", "player")
end

test("opportunity: a detected double-strike grants +3, caps at 6", function()
    setOutlaw(true)
    eq(H.Engine.P.oppStacks or 0, 0, "starts empty")
    doubleStrike(0, 2, 2); eq(H.Engine.P.oppStacks, 3, "one proc -> 3")   -- stage-2 double: +2 then +2
    doubleStrike(0, 1, 1); eq(H.Engine.P.oppStacks, 6, "two procs -> 6")  -- (CP values don't matter; the proc does)
    doubleStrike(0, 1, 1); eq(H.Engine.P.oppStacks, 6, "third proc -> still 6")
    truthy(evalClause({ type = "predStackMin", spell = OPP, v = 6 }), "predStackMin(6) reads the cap")
end)

test("opportunity: a single strike (no delayed bump) grants nothing", function()
    setOutlaw(true)
    H.S.power[COMBO] = 0
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)
    H.S.power[COMBO] = 1                            -- instant only, no delayed bump
    H.fire("UNIT_POWER_UPDATE", "player")
    eq(H.Engine.P.oppStacks or 0, 0, "no double-strike -> no proc")
end)

test("opportunity: Pistol Shot spends 3", function()
    setOutlaw(true)
    doubleStrike(0, 2, 2); doubleStrike(0, 1, 1); eq(H.Engine.P.oppStacks, 6, "at cap")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, PISTOLSHOT)
    eq(H.Engine.P.oppStacks, 3, "one Pistol Shot -> 3")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, PISTOLSHOT)
    eq(H.Engine.P.oppStacks, 0, "second Pistol Shot -> 0")
end)

test("opportunity: glow off resets to 0; procs alone drive the climb (no double-count)", function()
    setOutlaw(true)
    doubleStrike(0, 2, 2); eq(H.Engine.P.oppStacks, 3, "one proc -> 3 (not 6)")
    H.S.glows[PISTOLSHOT] = true; tick()
    eq(H.Engine.P.oppStacks, 3, "glow on does NOT floor/add on top of the proc")
    H.S.glows[PISTOLSHOT] = false; tick()
    eq(H.Engine.P.oppStacks, 0, "glow off -> hard reset to 0")
end)

test("opportunity: without Fan the Hammer, a proc is a single charge", function()
    setOutlaw(false)
    doubleStrike(0, 1, 1); eq(H.Engine.P.oppStacks, 1, "one proc -> 1")
    doubleStrike(0, 1, 1); eq(H.Engine.P.oppStacks, 1, "capped at 1")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
