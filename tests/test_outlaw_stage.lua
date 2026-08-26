-- test_outlaw_stage.lua -------------------------------------------------------
-- Outlaw Roll the Bones STAGE READ via combo-point timing. The RtB stage bonus is
-- applied INSTANTLY with a Sinister Strike, while a double-strike's CP lands ~200-330ms
-- later. So the FIRST combo-point bump after the builder cast (within instantWindow) is
-- the stage read: +1 => stage 1 (rtbStage2=false), +2 => stage 2+ (true). Later bumps
-- (the double-strike) are ignored. Guarded against the CP cap; reset on Roll the Bones.
--------------------------------------------------------------------------------

local SINISTER  = 193315
local ROLLBONES = 1214909
local COMBO     = 4

local function setOutlaw()
    H.reset(); H.S.specID = 260
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 6
    H.S.tracked[ROLLBONES] = true
    H.rebind()
end

-- Cast a Sinister Strike at `startCP`, then `dt` seconds later land `bump` combo points
-- and fire the power update the engine reads the stage from.
local function sinisterStrike(startCP, bump, dt)
    H.S.power[COMBO] = startCP
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)   -- records ssT0 / ssCP0
    H.S.now = H.S.now + (dt or 0)
    H.S.power[COMBO] = startCP + bump
    H.fire("UNIT_POWER_UPDATE", "player")
end

test("outlaw stage: instant +1 -> stage 1 (reroll)", function()
    setOutlaw()
    eq(H.Engine.P.predFlags.rtbStage2, nil, "starts unknown")
    sinisterStrike(0, 1, 0)
    eq(H.Engine.P.predFlags.rtbStage2, false, "instant +1 CP -> stage 1")
    truthy(evalClause({ type = "predFalse", key = "rtbStage2" }), "reroll fires")
end)

test("outlaw stage: instant +2 -> stage 2+ (good)", function()
    setOutlaw()
    sinisterStrike(0, 2, 0)
    eq(H.Engine.P.predFlags.rtbStage2, true, "instant +2 CP -> stage 2+")
    truthy(evalClause({ type = "predTrue", key = "rtbStage2" }), "confirmed good roll")
end)

test("outlaw stage: a delayed bump (double-strike) is not misread as the instant", function()
    setOutlaw()
    sinisterStrike(0, 1, 0.30)   -- first bump arrives past the 0.15s window
    eq(H.Engine.P.predFlags.rtbStage2, nil, "late first bump ignored, no stage set")
end)

test("outlaw stage: the double-strike after the instant does not flip the stage", function()
    setOutlaw()
    sinisterStrike(0, 2, 0)                       -- instant +2 -> stage 2+
    eq(H.Engine.P.predFlags.rtbStage2, true)
    H.S.now = H.S.now + 0.25                       -- the double-strike lands later
    H.S.power[COMBO] = 4
    H.fire("UNIT_POWER_UPDATE", "player")
    eq(H.Engine.P.predFlags.rtbStage2, true, "stage already read this cast; unchanged")
end)

test("outlaw stage: near combo-point cap is not read (clipped bump)", function()
    setOutlaw()
    sinisterStrike(5, 1, 0)   -- startCP 5 > max(6)-2: skip
    eq(H.Engine.P.predFlags.rtbStage2, nil, "clipped bump not read")
end)

test("outlaw stage: Roll the Bones resets the stage to unknown", function()
    setOutlaw()
    sinisterStrike(0, 1, 0); eq(H.Engine.P.predFlags.rtbStage2, false, "stage 1 read")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, ROLLBONES)
    eq(H.Engine.P.predFlags.rtbStage2, nil, "re-roll -> unknown until next builder")
end)

test("outlaw alert: Keep It Rolling advisory only on a confirmed good roll", function()
    setOutlaw()
    H.S.auras[ROLLBONES] = true
    sinisterStrike(0, 2, 0)                        -- confirm stage 2+
    eq(H.Engine.P.predFlags.rtbStage2, true)
    local r = H.Engine:Evaluate()
    truthy(r and r.alerts and #r.alerts >= 1, "KiR alert on a good roll")

    setOutlaw(); H.S.auras[ROLLBONES] = true
    sinisterStrike(0, 1, 0)                        -- stage 1
    local r2 = H.Engine:Evaluate()
    falsy(r2 and r2.alerts, "no KiR alert on a stage-1 roll")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
