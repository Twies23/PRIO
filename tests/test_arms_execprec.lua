-- test_arms_execprec.lua -------------------------------------------------------
-- Executioner's Precision counter: Execute +1 (cap 2), Mortal Strike -> 0, only while
-- talent 386634 is taken, and reset to 0 when the tracked buff (386633) reads missing.
-- Covers the live count (what the primary reads) and the look-ahead (what the queue reads).
--------------------------------------------------------------------------------

local EXECUTE, EXECUTE_CAST = 163201, 281000   -- listed id / id the game actually casts
local MORTAL, SLAM = 12294, 1464
local EP, EP_AURA = 386634, 386633
local BLADESTORM_CAST = 446035

local function fire(id) H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, id) end
local function ep() return H.Engine.P.stacks[EP] or 0 end
local function arms() H.reset(); H.S.specID = 71; H.rebind(); H.Engine.openerActive = false end
local function done() H.db.customPriorities = {}; H.reset(); H.rebind() end

test("EP: Execute cast as 281000 counts (the in-game cast id)", function()
    arms()
    fire(EXECUTE_CAST); eq(ep(), 1, "one Execute (281000) -> 1")
    fire(EXECUTE_CAST); eq(ep(), 2, "two -> 2")
    fire(EXECUTE_CAST); eq(ep(), 2, "capped at 2")
    fire(MORTAL);       eq(ep(), 0, "Mortal Strike -> 0")
    fire(EXECUTE);      eq(ep(), 1, "the listed id 163201 still counts too")
    done()
end)

test("EP: Bladestorm cast as 446035 resolves (last cast)", function()
    arms()
    fire(BLADESTORM_CAST)
    eq(H.Engine.P.lastCastKey, "Bladestorm", "446035 maps to Bladestorm")
    done()
end)

test("EP: not talented -> never counts", function()
    arms()
    H.S.known[EP] = false; H.S.talents[EP] = false
    fire(EXECUTE_CAST); fire(EXECUTE_CAST)
    eq(ep(), 0, "untalented -> stays 0")
    falsy(evalClause({ type = "preset:execPrec2" }), "Exec. Precision (2) preset false when untalented")
    done()
end)

test("EP: tracked buff reads missing -> reset to 0 (after the cast grace)", function()
    arms()
    H.S.tracked[EP_AURA] = true
    fire(EXECUTE_CAST); fire(EXECUTE_CAST); eq(ep(), 2)

    -- Inside the grace window the Cooldown Viewer may not show the buff yet: keep the count.
    H.S.auras[EP_AURA] = false
    H.Engine:Evaluate()
    eq(ep(), 2, "within 1s of the cast a missing read is ignored")

    -- Buff up -> kept.
    H.S.now = H.S.now + 5
    H.S.auras[EP_AURA] = true
    H.Engine:Evaluate()
    eq(ep(), 2, "buff up -> count kept")

    -- Buff gone (expired) -> 0.
    H.S.auras[EP_AURA] = false
    H.Engine:Evaluate()
    eq(ep(), 0, "buff missing -> reset to 0")
    done()
end)

test("EP: buff not tracked -> no missing-read reset", function()
    arms()
    fire(EXECUTE_CAST); fire(EXECUTE_CAST)
    H.S.now = H.S.now + 5
    H.S.auras[EP_AURA] = false            -- unreadable without a tracked frame
    H.Engine:Evaluate()
    eq(ep(), 2, "untracked -> cast-driven count stands")
    done()
end)

-- Look-ahead: the queue advances the counter for picks it 'casts' ahead of you.
local function epList()
    return {
        { spell = "Execute" },
        { spell = "MortalStrike", cond = { type = "preset:execPrec2" } },
        { spell = "Slam" },
    }
end

test("EP look-ahead: Execute at 1 stack -> queued Mortal Strike at 2", function()
    arms()
    H.db.customPriorities = { [H.armsSpec.key] = { variants = { slayer = { st = epList() } } } }
    fire(EXECUTE_CAST)                    -- live EP = 1
    H.S.now = H.S.now + 5
    local r = H.Engine:Evaluate()
    eq(r.primary.id, EXECUTE, "primary Execute")
    eq(r.queue[1].id, MORTAL, "after the predicted Execute EP is 2 -> Mortal Strike next")
    done()
end)

test("EP look-ahead: untalented -> no Mortal Strike from the EP row", function()
    arms()
    H.S.known[EP] = false; H.S.talents[EP] = false
    H.db.customPriorities = { [H.armsSpec.key] = { variants = { slayer = { st = epList() } } } }
    fire(EXECUTE_CAST)
    local r = H.Engine:Evaluate()
    eq(r.primary.id, EXECUTE)
    eq(r.queue[1].id, SLAM, "no EP stacks predicted when untalented -> Slam")
    done()
end)

test("EP look-ahead: Mortal Strike in the queue resets the predicted count", function()
    arms()
    H.db.customPriorities = { [H.armsSpec.key] = { variants = { slayer = { st = {
        { spell = "MortalStrike" },
        { spell = "Execute", cond = { type = "predStackMax", spell = EP, v = 0 } },
        { spell = "Slam" },
    } } } } }
    fire(EXECUTE_CAST); fire(EXECUTE_CAST)   -- live EP = 2
    local r = H.Engine:Evaluate()
    eq(r.primary.id, MORTAL)
    eq(r.queue[1].id, EXECUTE, "after the predicted Mortal Strike EP is 0")
    done()
end)

-- 0.10.30 Slayer lists (log-validated): spot checks on the rows that changed.
local SS, CS, AVATAR, OVERPOWER, CLEAVE, REND, HS = 260708, 167105, 107574, 7384, 845, 772, 1269383
local function slayerBase()
    arms()
    H.S.tracked[REND] = true; H.S.auras[REND] = true             -- Rend up, not refreshable
    H.S.tracked[CS] = true; H.S.auras[CS] = false                 -- Colossus Smash debuff down
    H.S.tracked[SS] = true
    H.S.ready[CS] = false; H.S.ready[AVATAR] = false; H.S.ready[227847] = false
    H.S.ready[HS] = false; H.S.usable[HS] = false
    H.S.glows[EXECUTE] = false; H.S.usableClean[EXECUTE] = false
end

test("Slayer AoE: Sweeping Strikes first whenever ready, then Cleave", function()
    slayerBase(); H.S.enemies = 2
    H.S.auras[SS] = true
    eq(H.Engine:Evaluate().primary.id, SS, "AoE leads with Sweeping Strikes when it is off cooldown")
    H.S.ready[SS] = false
    eq(H.Engine:Evaluate().primary.id, CLEAVE, "Sweeping Strikes on cooldown -> Cleave")
    done()
end)

test("Slayer ST: Avatar waits for Colossus Smash", function()
    slayerBase(); H.S.enemies = 1
    H.S.ready[AVATAR] = true
    falsy(H.Engine:Evaluate().primary.id == AVATAR, "Avatar ready but Colossus Smash on cooldown -> not Avatar")
    H.S.ready[CS] = true
    eq(H.Engine:Evaluate().primary.id, CLEAVE, "Colossus Smash ready -> Cleave first (row 1: Rend missing OR CS ready)")
    H.S.ready[CLEAVE] = false
    eq(H.Engine:Evaluate().primary.id, AVATAR, "...then Avatar with Colossus Smash")
    done()
end)

test("Slayer ST-Execute: Overpower before the plain Execute", function()
    slayerBase(); H.S.enemies = 1
    H.S.usableClean[EXECUTE] = true                               -- in execute range, no proc
    H.S.ready[MORTAL] = false
    eq(H.Engine:Evaluate().primary.id, OVERPOWER, "execute range, no proc -> Overpower, then Execute")
    H.S.ready[OVERPOWER] = false
    eq(H.Engine:Evaluate().primary.id, EXECUTE, "Overpower on cooldown -> Execute")
    done()
end)

-- Sudden Death (2): reads the number drawn on the Execute icon; unreadable fails closed.
test("Sudden Death (2) preset: icon count 2 passes, 1 fails, unreadable fails closed", function()
    arms()
    H.S.iconCount = { [EXECUTE] = 2 }
    truthy(evalClause({ type = "preset:suddenDeath2" }), "2 on the icon -> Sudden Death (2)")
    H.S.iconCount = { [EXECUTE] = 1 }
    falsy(evalClause({ type = "preset:suddenDeath2" }), "1 on the icon -> not 2")
    H.S.iconCount = {}
    falsy(evalClause({ type = "preset:suddenDeath2" }), "secret / unreadable -> never fires")
    eq(H.Cond.ClauseStatus({ type = "preset:suddenDeath2" }, H.Engine:CurrentState(), nil), "open",
       "editor shows it as can't-tell")
    done()
end)

-- Out of rage / Bladestorm: the queue keeps showing what to press next.
local BLADESTORM_ID = 227847
local function allUnusable(noPower)
    setmetatable(H.S.usable, { __index = function() return false end })
    H.S.usableNoPower = setmetatable({}, { __index = function() return noPower end })
    H.S.insufficientPower = setmetatable({}, { __index = function() return noPower end })
end
local function queueLen(r) return (r and r.primary and 1 or 0) + #((r and r.queue) or {}) end

test("Arms out of rage: spenders still shown (dimmed), full queue", function()
    slayerBase(); H.S.enemies = 1; H.db.numQueue = 3
    allUnusable(true)                                   -- every spender short on rage
    local r = H.Engine:Evaluate()
    truthy(r and r.primary, "still has a primary")
    eq(queueLen(r), 4, "primary + 3 queued, not a lone fallback")
    truthy(r.primary.noResource, "primary dimmed: not enough rage")
    done()
end)

test("Arms: Execute unusable for a non-rage reason stays filtered", function()
    slayerBase(); H.S.enemies = 1
    H.S.usable[EXECUTE] = false
    H.S.usableNoPower = { [EXECUTE] = false }          -- not in range, no proc
    H.S.glows[EXECUTE] = true                           -- even with the SD row's glow
    local r = H.Engine:Evaluate()
    falsy(r.primary.id == EXECUTE, "not usable (not a rage shortfall) -> not shown")
    done()
end)

test("Arms Bladestorm lockout: predicts past it, never shows Bladestorm", function()
    slayerBase(); H.S.enemies = 1; H.db.numQueue = 3
    H.db.advanceWhileCasting = true                     -- the in-game default
    H.S.ready[CS] = true
    fire(BLADESTORM_CAST)                               -- Slayer Bladestorm (446035)
    allUnusable(false)                                  -- nothing pressable, NOT a rage issue
    local r = H.Engine:Evaluate()
    truthy(r and r.primary, "lockout: still recommends")
    eq(queueLen(r), 4, "lockout: full queue")
    falsy(r.primary.id == BLADESTORM_ID, "Bladestorm itself is not re-shown")
    for _, e in ipairs(r.queue) do falsy(e.id == BLADESTORM_ID, "not in the queue either") end

    -- After the window the usable gate is back: nothing pressable -> the old lone filler.
    H.S.now = H.S.now + 5
    local r2 = H.Engine:Evaluate()
    eq(queueLen(r2), 1, "lockout over + genuinely unusable -> lone fallback, no queue")
    -- With "Advance primary while casting" turned off, the lockout is off too.
    H.db.advanceWhileCasting = false
    H.Engine.P.lockoutUntil = 0; fire(BLADESTORM_CAST)
    local r3 = H.Engine:Evaluate()
    eq(queueLen(r3), 1, "option off -> no prediction through Bladestorm")
    setmetatable(H.S.usable, nil); H.S.usableNoPower = nil; H.S.insufficientPower = {}
    done()
end)

test("Arms Bladestorm lockout ends early when its tracked buff drops", function()
    slayerBase(); H.S.enemies = 1
    H.S.tracked[446035] = true; H.S.auras[446035] = true
    fire(BLADESTORM_CAST)
    truthy(H.Engine:InLockout(H.S.now + 1), "buff up -> in lockout")
    H.S.auras[446035] = false
    falsy(H.Engine:InLockout(H.S.now + 1), "buff gone after the grace -> lockout over")
    done()
end)
