-- test_outlaw_stage.lua -------------------------------------------------------
-- Outlaw Roll the Bones STAGE INFERENCE. The stage buffs are secret by ID in combat,
-- but combo points read clean and stage 2 makes Sinister Strike generate an extra CP.
-- So a Sinister Strike whose total yield is only its base 1 CP proves the roll is
-- stage 1 -> predFlags.rtbStage2 = false -> reroll. Stage 2+ always yields >= 2, so it
-- can never false-flag. Measured over spec.stageInfer.window after the cast.
--------------------------------------------------------------------------------

local SINISTER  = 193315
local ROLLBONES = 1214909
local OPP       = 279876   -- Opportunity (double-strike marker)
local COMBO     = 4

local function setOutlaw()
    H.reset(); H.S.specID = 260
    H.S.power[COMBO] = 0; H.S.powerMax[COMBO] = 6
    H.S.stacks[OPP] = 0            -- Opportunity not up by default
    H.rebind()
end

-- Fire a Sinister Strike at `startCP`, land the total `yield` after the window, and
-- optionally raise Opportunity by `oppGain` to simulate a double-strike. Then run
-- BuildState (via CurrentState) so the windowed eval fires.
local function observeSS(startCP, yield, oppGain)
    H.S.power[COMBO] = startCP
    H.S.stacks[OPP]  = 0
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)   -- captures start CP + Opp
    H.S.now = H.S.now + 0.6                       -- past the 0.5s window
    H.S.power[COMBO] = startCP + yield
    H.S.stacks[OPP]  = oppGain or 0               -- >0 => Opportunity granted (double-strike)
    H.Engine:CurrentState()                       -- runs BuildState -> windowed eval
end

test("outlaw stage: single strike yielding 1 CP -> proven stage 1 (reroll)", function()
    setOutlaw()
    eq(H.Engine.P.predFlags.rtbStage2, nil, "starts unknown")
    observeSS(0, 1)
    eq(H.Engine.P.predFlags.rtbStage2, false, "1-CP single strike -> stage 1")
    truthy(evalClause({ type = "predFalse", key = "rtbStage2" }), "predFalse passes -> reroll fires")
end)

test("outlaw stage: single strike yielding 2 CP -> confirmed stage 2+", function()
    setOutlaw()
    observeSS(0, 2)                               -- no Opportunity gain => single strike
    eq(H.Engine.P.predFlags.rtbStage2, true, "single strike +extra CP -> stage 2+")
    truthy(evalClause({ type = "predTrue", key = "rtbStage2" }), "predTrue passes -> Keep It Rolling")
end)

test("outlaw stage: double-strike (Opportunity granted) yielding 2 CP -> stage 1", function()
    setOutlaw()
    observeSS(0, 2, 2)                            -- Opportunity +2 => 2 strikes; 2 CP == strikes
    eq(H.Engine.P.predFlags.rtbStage2, false, "2 strikes for 2 CP = no bonus -> stage 1")
end)

test("outlaw stage: double-strike yielding 3 CP -> confirmed stage 2+", function()
    setOutlaw()
    observeSS(0, 3, 1)                            -- 2 strikes + bonus = 3 CP
    eq(H.Engine.P.predFlags.rtbStage2, true, "2 strikes + extra CP -> stage 2+")
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
