-- test_outlaw_stage.lua -------------------------------------------------------
-- Outlaw Roll the Bones STAGE INFERENCE. The stage buffs are secret by ID in combat,
-- but combo points read clean and stage 2 makes Sinister Strike generate an extra CP.
-- So a Sinister Strike whose total yield is only its base 1 CP proves the roll is
-- stage 1 -> predFlags.rtbStage2 = false -> reroll. Stage 2+ always yields >= 2, so it
-- can never false-flag. Measured over spec.stageInfer.window after the cast.
--------------------------------------------------------------------------------

local SINISTER  = 193315
local ROLLBONES = 1214909
local COMBO     = 4

local function setOutlaw()
    H.reset(); H.S.specID = 260
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 6
    H.rebind()
end

-- Fire a Sinister Strike at `startCP`, let the observation window elapse, land the
-- total `yield`, then run BuildState (via CurrentState) so the windowed eval fires.
local function observeSS(startCP, yield)
    H.S.power[COMBO] = startCP
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)
    H.S.now = H.S.now + 0.6                       -- past the 0.5s window
    H.S.power[COMBO] = startCP + yield
    H.Engine:CurrentState()                       -- runs BuildState -> windowed eval
end

test("outlaw stage: Sinister Strike yielding 1 CP -> proven stage 1 (reroll)", function()
    setOutlaw()
    eq(H.Engine.P.predFlags.rtbStage2, nil, "starts unknown")
    observeSS(0, 1)
    eq(H.Engine.P.predFlags.rtbStage2, false, "1-CP Sinister Strike -> stage 1")
    truthy(evalClause({ type = "predFalse", key = "rtbStage2" }), "predFalse passes -> reroll fires")
end)

test("outlaw stage: Sinister Strike yielding 2 CP -> never false-flags (stays unknown)", function()
    setOutlaw()
    observeSS(0, 2)                               -- stage 2, or a stage-1 double-strike
    eq(H.Engine.P.predFlags.rtbStage2, nil, ">=2 yield can't prove stage 1")
    falsy(evalClause({ type = "predFalse", key = "rtbStage2" }), "unknown -> no reroll")
end)

test("outlaw stage: near combo-point cap is not measured (wasted cast)", function()
    setOutlaw()
    observeSS(5, 1)                               -- startCP 5 > max(6)-2: skip
    eq(H.Engine.P.predFlags.rtbStage2, nil, "near-cap Sinister Strike ignored")
end)

test("outlaw stage: Roll the Bones resets the flag to unknown", function()
    setOutlaw()
    observeSS(0, 1); eq(H.Engine.P.predFlags.rtbStage2, false, "stage 1 flagged")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, ROLLBONES)
    eq(H.Engine.P.predFlags.rtbStage2, nil, "re-roll -> unknown again")
end)

test("outlaw stage: not measured until the window closes", function()
    setOutlaw()
    H.S.power[COMBO] = 0
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)
    H.S.now = H.S.now + 0.2                       -- still inside the window
    H.S.power[COMBO] = 1
    H.Engine:CurrentState()
    eq(H.Engine.P.predFlags.rtbStage2, nil, "not measured mid-window")
    H.S.now = H.S.now + 0.5                       -- now past the window
    H.Engine:CurrentState()
    eq(H.Engine.P.predFlags.rtbStage2, false, "measured once the window closes")
end)

H.reset(); H.rebind()   -- restore Windwalker as the active spec for later suites
