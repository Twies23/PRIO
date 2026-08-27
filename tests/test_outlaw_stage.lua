-- test_outlaw_stage.lua -------------------------------------------------------
-- Outlaw Roll the Bones STAGE READ from Sinister Strike combo-point bumps, split by
-- ORDER (robust to timing jitter): within `window` after the builder cast, the FIRST
-- positive combo-point bump is the instant (first strike + stage bonus) -> +1 = stage 1
-- (rtbStage2=false), +2 = stage 2+ (true); a SECOND bump is the double-strike (an
-- Opportunity proc, see the opportunity suite). Guarded against the CP cap; reset on
-- Roll the Bones; bumps after `window` (the next GCD) are ignored.
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

-- Cast a Sinister Strike at `startCP`, then `dt` seconds later land a `bump` and fire
-- the power update the engine reads.
local function sinisterStrike(startCP, bump, dt)
    H.S.power[COMBO] = startCP
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, SINISTER)   -- records ssT0 / ssCP0
    H.S.now = H.S.now + (dt or 0)
    H.S.power[COMBO] = startCP + bump
    H.fire("UNIT_POWER_UPDATE", "player")
end

test("outlaw stage: first bump +1 -> stage 1 (reroll)", function()
    setOutlaw()
    eq(H.Engine.P.predFlags.rtbStage2, nil, "starts unknown")
    sinisterStrike(0, 1, 0)
    eq(H.Engine.P.predFlags.rtbStage2, false, "instant +1 -> stage 1")
    truthy(evalClause({ type = "predFalse", key = "rtbStage2" }), "reroll fires")
end)

test("outlaw stage: first bump +2 -> stage 2+ (good)", function()
    setOutlaw()
    sinisterStrike(0, 2, 0)
    eq(H.Engine.P.predFlags.rtbStage2, true, "instant +2 -> stage 2+")
    truthy(evalClause({ type = "predTrue", key = "rtbStage2" }), "confirmed good roll")
end)

test("outlaw stage: the instant reads even when it lands late (order, not ms)", function()
    setOutlaw()
    sinisterStrike(0, 2, 0.12)   -- first bump at 120ms is still the instant
    eq(H.Engine.P.predFlags.rtbStage2, true, "first bump = instant regardless of exact ms")
end)

test("outlaw stage: the second bump (double-strike) does not re-read the stage", function()
    setOutlaw()
    sinisterStrike(0, 2, 0)                        -- 1st bump -> stage 2+
    eq(H.Engine.P.predFlags.rtbStage2, true)
    H.S.now = H.S.now + 0.25                        -- 2nd bump lands (the double)
    H.S.power[COMBO] = 4
    H.fire("UNIT_POWER_UPDATE", "player")
    eq(H.Engine.P.predFlags.rtbStage2, true, "2nd bump is the double, stage unchanged")
end)

test("outlaw stage: a bump after the window is ignored (next GCD)", function()
    setOutlaw()
    sinisterStrike(0, 1, 0.75)   -- first bump arrives past the 0.6s window
    eq(H.Engine.P.predFlags.rtbStage2, nil, "out-of-window bump not read")
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

test("outlaw: an Energy-cost ability (Roll the Bones) is not blocked by combo points", function()
    setOutlaw()
    H.S.power[COMBO] = 2                                   -- combo points readable = 2
    H.S.powerCost = { [ROLLBONES] = { type = 3, cost = 25 } }  -- RtB: 25 Energy (type 3), 0 CP
    H.rebind()
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell" .. ROLLBONES,
       "RtB (Energy cost) is recommended at 2 combo points, not gated out")
end)

test("outlaw: a combo-point-cost ability IS still gated by combo points", function()
    setOutlaw()
    H.S.power[COMBO] = 2
    H.S.powerCost = { [ROLLBONES] = { type = 4, cost = 5 } }   -- pretend RtB costs 5 CP
    H.rebind()
    local r = H.Engine:Evaluate()
    falsy(r and r.primary and r.primary.name == "Spell" .. ROLLBONES,
          "a real combo-point cost above the pool still blocks it")
end)

test("outlaw look-ahead: builders build toward a finisher in the queue", function()
    setOutlaw()
    H.S.power[COMBO] = 4                                   -- 4 combo points now
    H.S.auras[ROLLBONES] = true                            -- a roll is active (no reroll)
    H.S.ready[51690] = false                               -- Killing Spree on CD
    H.S.ready[271877] = false                              -- Blade Rush on CD
    H.rebind()
    H.Engine.P.predFlags = { rtbStage2 = true }            -- stage 2 -> Sinister Strike gives 2 CP
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.name, "Spell" .. SINISTER, "primary is Sinister Strike at 4 CP")
    -- +2 from the stage-2 Sinister Strike -> 6 CP, so a finisher should appear next
    local n1 = r.queue and r.queue[1] and r.queue[1].name
    truthy(n1 == "Spell315341" or n1 == "Spell2098",
           "next is a finisher (Between the Eyes / Dispatch) once combo points reach 6")
end)

test("outlaw: a spender blocked only by low energy still shows (no collapse to Sinister Strike)", function()
    setOutlaw()
    H.S.power[COMBO] = 6                                   -- at 6 combo points -> finisher
    H.S.auras[ROLLBONES] = true                            -- a roll is active (no reroll)
    H.S.ready[315341] = false                              -- Between the Eyes on CD -> Dispatch is the finisher
    H.S.ready[271877] = false                              -- Blade Rush on CD (higher "always" line)
    -- Dispatch reads unusable via IsUsable (low energy) but is "usable if it weren't for power"
    H.S.usable = { [2098] = false }
    H.S.usableNoPower = { [2098] = true }
    H.rebind()
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell2098",
       "Dispatch (blocked only by energy) is recommended, not the fallback Sinister Strike")
end)

test("outlaw: Pistol Shot blocked only by energy still shows when it's the priority", function()
    setOutlaw()
    H.S.power[COMBO] = 2                                   -- low CP -> the "glow + <=3 CP" line
    H.S.auras[ROLLBONES] = true                            -- roll active
    H.S.ready[13750] = false; H.S.ready[271877] = false; H.S.ready[51690] = false  -- AR/BladeRush/KS on CD
    H.S.glows[185763] = true                               -- Opportunity up (glow)
    H.S.usable = { [185763] = false }; H.S.usableNoPower = { [185763] = true }     -- energy-blocked only
    H.rebind(); H.Engine.P.predFlags = { rtbStage2 = true }
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell185763", "Pistol Shot shows despite low energy")
end)

test("outlaw AoE: Blade Flurry blocked only by energy still shows", function()
    setOutlaw()
    H.S.power[COMBO] = 2; H.S.enemies = 3                  -- AoE mode
    H.S.usable = { [13877] = false }; H.S.usableNoPower = { [13877] = true }        -- energy-blocked only
    H.rebind()
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.name, "Spell13877", "Blade Flurry shows despite low energy")
end)

test("engine: without softPowerUsable, an unaffordable spender IS withheld (built-resource specs)", function()
    setOutlaw()
    H.outlawSpec.softPowerUsable = false                  -- simulate a Maelstrom/Holy-Power spec
    H.S.power[COMBO] = 6
    H.S.auras[ROLLBONES] = true
    H.S.ready[315341] = false; H.S.ready[271877] = false  -- BtE / Blade Rush on CD
    H.S.usable = { [2098] = false }; H.S.usableNoPower = { [2098] = true }   -- Dispatch unaffordable
    H.rebind()
    local r = H.Engine:Evaluate()
    falsy(r and r.primary and r.primary.name == "Spell2098",
          "strict IsUsable withholds the unaffordable spender (no soft-power opt-in)")
    H.outlawSpec.softPowerUsable = true                   -- restore
end)

test("engine: gatePredictedResource gates a SECRET-resource spender on the PREDICTED value", function()
    -- Elemental's case: Maelstrom is secret in combat, so the readable cost gate is skipped
    -- and spenders would show at any amount. With spec.gatePredictedResource the gate runs
    -- against the predicted resource instead. Modelled here on Outlaw with combo points made
    -- secret (power=nil) and a spender costing 5 of the primary resource.
    setOutlaw()
    H.outlawSpec.gatePredictedResource = true
    H.S.power[COMBO] = nil                                 -- resource reads secret -> not readable
    H.S.powerCost = { [2098] = { type = 4, cost = 5 } }    -- Dispatch: 5 of the primary resource
    H.S.auras[ROLLBONES] = true
    H.S.ready[315341] = false; H.S.ready[271877] = false   -- BtE / Blade Rush on CD
    H.rebind()

    H.Engine.P.maelstrom = 3                               -- predicted below cost -> withheld
    local lo = H.Engine:Evaluate()
    falsy(lo and lo.primary and lo.primary.name == "Spell2098",
          "predicted 3 < cost 5: spender withheld even though the resource is secret")

    H.Engine.P.maelstrom = 6                               -- predicted at/above cost -> shown
    local hi = H.Engine:Evaluate()
    eq(hi and hi.primary and hi.primary.name, "Spell2098",
       "predicted 6 >= cost 5: spender shows")
    H.outlawSpec.gatePredictedResource = nil              -- restore
end)

-- Elemental's 4-set (Ophidian Oracle): a proc makes the next Earth Shock / Elemental
-- Blast / Earthquake free and lights it on the CDM (spec.freeSpendGlow). Set up Ele with
-- Maelstrom secret and every ST line but the bare Elemental Blast out of the way, so EB is
-- the reachable candidate and its cost gate is what's under test. EB costs 75 Maelstrom.
local EB, ELE_FS = 117014, 188389
local function setEle()
    H.reset(); H.S.specID = 262
    H.S.power[11] = nil; H.S.powerMax[11] = 150            -- Maelstrom secret in combat
    H.S.powerCost = { [EB] = { type = 11, cost = 75 } }
    H.S.auras[ELE_FS] = true                                -- Flame Shock up -> upkeep line skips
    setmetatable(H.S.ready, { __index = function() return false end })
    H.S.ready[EB] = true                                   -- only bare Elemental Blast is ready
    H.S.glows = {}
    H.rebind()
end
local function eleShowsEB()
    local r = H.Engine:Evaluate(); local hit = {}
    if r and r.primary then hit[r.primary.name] = true end
    for _, e in ipairs((r and r.queue) or {}) do hit[e.name] = true end
    return hit["Spell" .. EB] == true
end

test("Elemental 4-set: a glowing (free) spender isn't withheld at low Maelstrom", function()
    setEle()
    H.Engine.P.maelstrom = 20                              -- predicted below the 75 cost
    falsy(eleShowsEB(), "no proc: Elemental Blast withheld below its Maelstrom cost")

    setEle()
    H.S.glows[EB] = true                                   -- 4-set proc lights EB on the CDM
    H.Engine.P.maelstrom = 20
    truthy(eleShowsEB(), "proc glow: the free Elemental Blast shows even at low Maelstrom")
end)

test("Elemental 4-set: a free spender doesn't drain predicted Maelstrom (one cast only)", function()
    setEle()
    H.S.glows[EB] = true                                   -- EB lit = free
    H.Engine.P.maelstrom = 100
    H.Engine:CurrentState()                                -- latch the free-spender read
    truthy(H.Engine.P.freeSpend, "glow latched a free spender")

    H.Engine:ApplyMaelstrom(H.Engine.P, EB, "ElementalBlast")   -- free cast
    eq(H.Engine.P.maelstrom, 100, "free cast doesn't drain Maelstrom")
    falsy(H.Engine.P.freeSpend, "latch consumed after the free cast")

    H.S.glows[EB] = nil; H.Engine:CurrentState()           -- glow gone -> next cast is normal
    H.Engine:ApplyMaelstrom(H.Engine.P, EB, "ElementalBlast")
    eq(H.Engine.P.maelstrom, 25, "the following cast drains normally (100 - 75)")
end)

H.reset(); H.rebind()   -- restore Windwalker for later suites
