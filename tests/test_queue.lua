-- test_queue.lua --------------------------------------------------------------
-- The priority walk (Engine:Evaluate): always fills the queue, never repeats an
-- ability back-to-back (Combo Strikes), and never recommends Rushing Wind Kick
-- without its proc.
--------------------------------------------------------------------------------

local RWK, RWK_PROC, UNBROKEN, XUEN = 1250566, 1250554, 1296624, 123904

local function shadopan(mode)
    H.reset()
    H.S.knownStrict[XUEN] = false          -- Shado-Pan
    H.S.enemies = (mode == "aoe") and 4 or (mode == "cleave") and 2 or 1
    H.rebind()
    H.Engine.openerActive = false
    H.db.numQueue = 2                       -- want = primary + 2 = 3 total
    H.S.power[12] = 3                       -- Chi
    H.Engine:UpdateEnergy(H.S.now)
end

local function ids(r)
    local out = { r.primary and r.primary.id }
    for _, e in ipairs(r.queue or {}) do out[#out + 1] = e.id end
    return out
end

test("queue: fills 3 (primary + 2) on Shado-Pan ST", function()
    shadopan("st")
    local r = H.Engine:Evaluate()
    truthy(r and r.primary, "primary present")
    eq(#r.queue, 2, "two queued abilities (3 total)")
end)

test("queue: fills 3 even when Chi is empty (fillers carry it)", function()
    shadopan("st")
    H.S.power[12] = 0
    local r = H.Engine:Evaluate()
    truthy(r and r.primary, "primary present")
    eq(#r.queue, 2, "still fills 3")
end)

test("queue: Combo Strikes -- no ability twice in a row", function()
    shadopan("st")
    H.db.numQueue = 3
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    for i = 2, #seq do
        truthy(seq[i] ~= seq[i - 1],
            "consecutive picks must differ (" .. tostring(seq[i]) .. ")")
    end
end)

test("queue: Rushing Wind Kick NOT recommended without its proc (AoE)", function()
    shadopan("aoe")
    -- proc absent: RWK_PROC untracked/inactive
    local r = H.Engine:Evaluate()
    for _, id in ipairs(ids(r)) do
        truthy(id ~= RWK, "Rushing Wind Kick must not appear without its proc")
    end
end)

-- Conduit (Invoke Xuen talented) -- RWK is now part of the AoE list and must appear
-- when its proc is up, and never without it.
local RWK_ID = 1250566
local function conduit(mode)
    H.reset()
    H.S.knownStrict[XUEN] = true            -- Conduit
    H.S.enemies = (mode == "aoe") and 4 or (mode == "cleave") and 2 or 1
    H.rebind()
    H.Engine.openerActive = false
    H.db.numQueue = 3
    H.S.power[12] = 3
    H.Engine:UpdateEnergy(H.S.now)
end

test("conduit AoE: Rushing Wind Kick appears when its proc is up", function()
    conduit("aoe")
    H.S.tracked[RWK_PROC] = true; H.S.auras[RWK_PROC] = true   -- proc active + readable
    -- Suppress everything ranked ABOVE Rushing Wind Kick so it's reached:
    H.S.power[3] = 50                                  -- readable low Energy -> not near cap
    H.S.ready[123904] = true                           -- Xuen ready -> WDP "Xuen >10s" fails
    H.S.ready[443028] = false                          -- Celestial Conduit not ready -> Invoke Xuen line off (else Xuen+Zenith fill the queue)
    H.S.tracked[443294] = true; H.S.auras[443294] = true  -- HoJS active -> Celestial Conduit fails
    H.S.ready[113656] = false                          -- Fists of Fury on cooldown
    H.S.chargeState[1249625] = { max = 2, cur = 1, belowMax = true }  -- Zenith <2 charges -> its line fails
    local r = H.Engine:Evaluate()
    local found = false
    for _, id in ipairs(ids(r)) do if id == RWK_ID then found = true end end
    truthy(found, "RWK should be recommended while its proc is up")
end)

test("conduit AoE: Rushing Wind Kick absent without its proc", function()
    conduit("aoe")   -- proc not active/tracked
    local r = H.Engine:Evaluate()
    for _, id in ipairs(ids(r)) do
        truthy(id ~= RWK_ID, "RWK must not appear without its proc")
    end
end)

local ZENITH, CC, HOJS = 1249625, 443028, 443294
local function has(r, id) for _, x in ipairs(ids(r)) do if x == id then return true end end return false end

test("conduit: Zenith recommended at 2 charges (overcap dump) when glowing", function()
    conduit("st")
    H.S.tracked[HOJS] = true; H.S.auras[HOJS] = true             -- HoJS up -> CC suppressed (no burst path)
    H.S.chargeState[ZENITH] = { max = 2, cur = 2, belowMax = false }
    H.S.glows[ZENITH] = true                                     -- lit up (20 Tigereye stacks ready)
    truthy(has(H.Engine:Evaluate(), ZENITH), "Zenith at 2 charges + glowing should be recommended")
end)

test("conduit: Zenith is the very next pick after Invoke Xuen, even at 1 charge (burst)", function()
    conduit("st")
    H.Engine.P.lastCast = XUEN; H.Engine.P.lastCastKey = "InvokeXuen"   -- just pressed Xuen
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.id == ZENITH, "Zenith should be the primary right after Invoke Xuen")
end)

test("conduit: Zenith still fires if another pick slipped in right after Invoke Xuen (cooldown-based gate)", function()
    conduit("st")
    H.S.talents[392986] = true                                   -- Xuen's Bond -> 90s cooldown
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, XUEN)      -- press Xuen (seeds its 90s predicted cooldown)
    H.Engine.P.lastCast = 107428; H.Engine.P.lastCastKey = "RisingSunKick"   -- ...then an RSK got pressed
    H.S.ready[XUEN] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.id == ZENITH, "Zenith should still lead within ~10s of the Xuen press")
end)

test("conduit: Celestial Conduit still gated on Whirling Dragon Punch being on cooldown", function()
    conduit("st")
    H.S.ready[XUEN] = false                                      -- no Xuen -> no simulated Zenith/HoJS ahead of CC
    H.S.known[392983] = false                                    -- no Strike of the Windlord (it would grant HoJS in the sim)
    H.S.ready[152175] = false                                    -- WDP on CD -> CC's gate passes
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    truthy(has(H.Engine:Evaluate(), CC), "Celestial Conduit should appear while WDP is on cooldown")
end)

-- 0.10.2: Tiger Palm no longer outranks a castable Fists / free proc / Rising Sun Kick
-- (decision-point replay of 3 top logs). Suppress the cooldown lines so the spender tier decides.
local TP_ID, RSK_ID, FOF, DANCE_GLOW2 = 100780, 107428, 113656, 101546
local function conduit_spenders()
    conduit("st")
    H.S.ready[XUEN] = true                                          -- xuenAway false -> WDP/Strike hold
    H.S.ready[443028] = false                                       -- Celestial Conduit not ready -> Xuen line off
    H.S.tracked[443294] = true; H.S.auras[443294] = true           -- HoJS up -> CC line off
    H.S.chargeState[1249625] = { max = 2, cur = 1, belowMax = true } -- Zenith lines off
    H.S.ready[1272696] = false                                      -- Zenith Stomp on cooldown (it correctly outranks TP at Chi <= 2)
    H.S.power[3] = 150                                              -- readable Energy at cap -> TP's gate is TRUE
    H.Engine:UpdateEnergy(H.S.now)
end

test("conduit ST: Fists of Fury beats Tiger Palm at 2 Chi (old chiMax(2) line used to win)", function()
    conduit_spenders(); H.S.power[12] = 2; H.S.ready[FOF] = true
    H.S.talents[1250041] = true                                     -- Harmonic Combo: Fists costs 2
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, FOF, "Fists should be the pick at 2 Chi, not Tiger Palm")
end)

test("conduit ST: a Dance of Chi-Ji proc beats Tiger Palm at 1 Chi", function()
    conduit_spenders(); H.S.power[12] = 1; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = false
    H.S.glows[DANCE_GLOW2] = true
    H.S.tracked[325202] = true; H.S.auras[325202] = true            -- Dance buff tracked (as in-game) -> SCK costs 0
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 101546, "free Spinning Crane Kick should out-rank Tiger Palm")
end)

test("conduit ST: Rising Sun Kick beats Tiger Palm at 2 Chi", function()
    conduit_spenders(); H.S.power[12] = 2; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = true
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, RSK_ID, "RSK should be the pick over Tiger Palm")
end)

test("conduit ST: Tiger Palm is not recommended at 5 Chi even at Energy cap", function()
    conduit_spenders(); H.S.power[12] = 5; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = false
    H.db.numQueue = 0
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == TP_ID), "no Tiger Palm at 5 Chi")
end)

test("affordGate: an unaffordable Tiger Palm is withheld via the clean insufficient-power flag", function()
    -- Chi 1, Fists/RSK down: Tiger Palm (Energy at cap, Chi <= 1) normally outranks the paid
    -- Blackout Kick. With the game saying TP is unaffordable, Blackout Kick must lead instead.
    conduit_spenders(); H.S.power[12] = 1; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = false
    H.db.numQueue = 0
    H.S.insufficientPower[TP_ID] = true
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 100784, "Blackout Kick leads while Tiger Palm is unaffordable")
    H.S.insufficientPower[TP_ID] = false
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, TP_ID, "Tiger Palm returns once affordable")
end)

test("safety net: a placeholder pick carries the dim flags (unaffordable / on cooldown)", function()
    conduit_spenders(); H.S.power[12] = 0; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = false
    H.S.insufficientPower[TP_ID] = true                             -- nothing castable at all
    local r = H.Engine:Evaluate()
    truthy(r and r.primary, "still shows something (never blank)")
    truthy(r.primary.noResource or r.primary.notReady, "but flagged so the display dims it")
end)

test("Harmonic Combo: Fists of Fury costs 2 Chi with the talent, 3 without", function()
    H.reset(); H.S.knownStrict[XUEN] = true; H.rebind()
    eq(H.spec:ResourceCost("FistsOfFury", FOF, {}), 3, "base cost 3")
    H.S.talents[1250041] = true
    eq(H.spec:ResourceCost("FistsOfFury", FOF, {}), 2, "Harmonic Combo -> 2")
end)

test("look-ahead: Whirling Dragon Punch grants Dance of Chi-Ji / Blackout Kick! in the queue sim", function()
    local g = H.spec.spellEffects.WhirlingDragonPunch.grant
    local dance, combo = false, false
    for _, a in ipairs(g) do if a == 325202 then dance = true end; if a == 137284 then combo = true end end
    truthy(dance and combo, "WDP look-ahead should assume its Dance / Combo Breaker procs")
end)

test("conduit: Zenith NOT recommended at 1 charge outside the burst", function()
    conduit("st")
    H.S.ready[CC] = false                                        -- Celestial Conduit not ready -> Invoke Xuen line off (no burst)
    H.S.tracked[HOJS] = true; H.S.auras[HOJS] = true             -- HoJS up -> CC suppressed, no lastCast trigger
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    falsy(has(H.Engine:Evaluate(), ZENITH), "Zenith should not fire at 1 charge outside burst")
end)

test("conduit: Zenith at 2 charges is cast regardless of the Tigereye glow (0.10.5)", function()
    conduit("st")
    H.S.ready[CC] = false                                        -- no burst path (Invoke Xuen line off)
    H.S.tracked[HOJS] = true; H.S.auras[HOJS] = true
    H.S.chargeState[ZENITH] = { max = 2, cur = 2, belowMax = false }
    H.S.glows[ZENITH] = false
    truthy(has(H.Engine:Evaluate(), ZENITH), "2nd charge back -> Zenith recommended even without the glow")
end)

local SCK, BOK, DANCE_GLOW, BOK_GLOW = 101546, 100784, 101546, 100784
local BOKPROC, COMBOBREAK, DANCEBUFF = 116768, 137284, 325202

-- Reach the aggressive proc lines (Conduit ST #8/#9) by suppressing everything above:
-- Xuen ready (WDP/Strike hold), high Chi (Zenith Stomp off), Celestial not ready
-- (Invoke Xuen off), HoJS up (Celestial Conduit off), Zenith <2 charges (both Zenith
-- lines off). Fists of Fury (#7, unconditional) then the proc dumps are what remain.
local function conduit_procready()
    conduit("st")
    H.S.ready[XUEN] = true                                          -- Xuen ready -> xuenAway false
    H.S.power[12] = 5                                               -- Chi high -> chiMax(2) false
    H.S.power[3]  = 50                                              -- readable low Energy -> not near cap
    H.S.ready[443028] = false                                       -- Celestial Conduit not ready
    H.S.tracked[443294] = true; H.S.auras[443294] = true           -- HoJS up -> Celestial Conduit line off
    H.S.chargeState[1249625] = { max = 2, cur = 1, belowMax = true } -- Zenith <2 charges
    H.S.ready[113656] = true                                        -- Fists of Fury available
end

test("conduit: Dance of Chi-Ji proc glow -> Spinning Crane Kick spent aggressively", function()
    conduit_procready()
    H.S.glows[DANCE_GLOW] = true                                   -- Dance proc lit on SCK
    truthy(has(H.Engine:Evaluate(), SCK), "SCK should be recommended on a Dance of Chi-Ji glow")
end)

test("conduit: Blackout Kick! proc glow -> Blackout Kick spent aggressively", function()
    conduit_procready()
    H.S.glows[BOK_GLOW] = true                                     -- BoK! proc lit on Blackout Kick
    truthy(has(H.Engine:Evaluate(), BOK), "Blackout Kick should be recommended on a BoK! glow")
end)

test("conduit: Blackout Kick! also spent on the readable Combo Breaker buff", function()
    conduit_procready()
    H.S.tracked[COMBOBREAK] = true; H.S.auras[COMBOBREAK] = true
    truthy(has(H.Engine:Evaluate(), BOK), "Blackout Kick should be recommended on Combo Breaker")
end)

local SCK_ID, BOK_ID, ZEN_ID, FOF_ID = 101546, 100784, 1249625, 113656

test("shadopan ST: Spinning Crane Kick is the primary spender over Blackout Kick", function()
    shadopan("st")
    H.db.numQueue = 3
    H.S.power[12] = 6                                   -- plenty of Chi
    H.S.ready[FOF_ID] = false                            -- Fists on CD so it doesn't eat the Chi/slots
    H.Engine:UpdateEnergy(H.S.now)
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    local sck, bok = false, false
    for _, id in ipairs(seq) do
        if id == SCK_ID then sck = true end
        if id == BOK_ID then bok = true end
    end
    truthy(sck, "SCK should appear in the ST queue as the primary spender")
    falsy(bok, "Blackout Kick should not out-rank Spinning Crane Kick on ST")
end)

test("shadopan: Fists of Fury follows immediately after Zenith (burst)", function()
    shadopan("st")
    H.Engine.P.lastCast = ZEN_ID                         -- just cast Zenith (engine reads P, not S)
    H.Engine.P.lastCastKey = "Zenith"
    H.S.ready[FOF_ID] = true
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.id == FOF_ID,
        "Fists of Fury should be the pick right after Zenith")
end)

test("opener: resolves per hero (Conduit vs Shado-Pan)", function()
    H.reset(); H.S.knownStrict[XUEN] = true; H.rebind()   -- Conduit
    local c = H.Engine:ActiveOpener("st")
    truthy(c and c[2] == "InvokeXuen", "Conduit opener includes Invoke Xuen early")

    H.reset(); H.S.knownStrict[XUEN] = false; H.rebind()  -- Shado-Pan
    local s = H.Engine:ActiveOpener("st")
    truthy(s and s[2] == "Zenith", "Shado-Pan opener is Zenith-centric")
    local hasXuen = false; for _, k in ipairs(s) do if k == "InvokeXuen" then hasXuen = true end end
    falsy(hasXuen, "Shado-Pan opener has no Invoke Xuen")
end)

test("Zenith recharge prediction honors Spiritual Focus / Efficient Training", function()
    conduit("st")
    H.S.known[280197] = false; H.S.known[450989] = false            -- neither talent
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, ZENITH)
    local c = H.Engine.P.charges.Zenith
    eq(math.floor(c.rechargeEnd - H.S.now + 0.5), 90, "base 90s")
    conduit("st")
    H.S.talents[280197] = true; H.S.talents[450989] = true          -- both talents
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, ZENITH)
    c = H.Engine.P.charges.Zenith
    eq(math.floor(c.rechargeEnd - H.S.now + 0.5), 60, "-20 -10 -> 60s")
end)

test("conduit AoE: Rising Sun Kick main line only as the WDP enabler (WDP CD up, Fists down)", function()
    conduit("aoe")
    H.S.ready[XUEN] = true; H.S.ready[443028] = false                -- burst lines off (CC not ready -> Xuen line off)
    H.S.tracked[443294] = true; H.S.auras[443294] = false           -- HoJS DOWN (its own RSK line stays inert)
    H.S.chargeState[1249625] = { max = 2, cur = 1, belowMax = true }
    H.S.ready[1272696] = false; H.S.ready[113656] = false           -- ZS + Fists on cooldown
    H.S.power[12] = 2; H.S.power[3] = 50; H.Engine:UpdateEnergy(H.S.now)
    H.db.numQueue = 0
    H.S.ready[152175] = false                                       -- WDP on its own cooldown -> RSK line off, SCK leads
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.id ~= 107428, "RSK should not lead while WDP is on cooldown")
    H.S.ready[152175] = true; H.S.usable[152175] = false            -- WDP CD up but not castable yet (needs RSK) -> RSK enables it
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 107428, "RSK leads as the WDP enabler")
end)

test("conduit: Zenith Stomp 'Zenith ending' branch does not fire at 5+ Chi", function()
    conduit("st")
    H.S.ready[XUEN] = true; H.S.ready[443028] = false
    H.S.tracked[443294] = true; H.S.auras[443294] = false
    H.S.chargeState[1249625] = { max = 2, cur = 1, belowMax = true }
    H.S.tracked[1249625] = true; H.S.auras[1249625] = true          -- Zenith up ...
    H.Engine.P.auraExpire = H.Engine.P.auraExpire or {}
    H.Engine.P.auraExpire[1249625] = H.S.now + 3                    -- ... and ending in 3s
    H.S.ready[113656] = false; H.S.ready[107428] = false; H.S.ready[152175] = false
    H.db.numQueue = 0
    H.S.power[12] = 5
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == 1272696), "no Zenith Stomp at 5 Chi even as Zenith ends")
    H.S.power[12] = 3
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 1272696, "Zenith Stomp at 3 Chi as Zenith ends")
end)

test("conduit: 2nd Zenith chains when the window ends inside the Xuen window (not outside it)", function()
    conduit("st")
    H.S.talents[392986] = true                                       -- Xuen's Bond -> 90s
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, XUEN)          -- Xuen pressed just now (CD 90 left)
    H.Engine.P.lastCast = 113656; H.Engine.P.lastCastKey = "FistsOfFury"
    H.S.now = H.S.now + 16                                           -- 16s later: first Zenith window over
    H.S.ready[XUEN] = false
    H.S.tracked[ZENITH] = true; H.S.auras[ZENITH] = false            -- Zenith buff down
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }  -- one charge left
    local r = H.Engine:Evaluate()
    truthy(r and r.primary and r.primary.id == ZENITH, "chain the 2nd Zenith inside the Xuen window")

    conduit("st")                                                    -- no Xuen pressed recently -> hold the charge
    H.S.ready[XUEN] = false; H.S.ready[CC] = false
    H.S.tracked[ZENITH] = true; H.S.auras[ZENITH] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == ZENITH), "outside the Xuen window the last charge is held")
end)

test("conduit: an unseeded on-cooldown Xuen (pressed before /reload) does not fake the Xuen window", function()
    conduit("st")
    H.S.ready[XUEN] = false                                          -- on cooldown, never seen pressed -> reads raw 120s
    H.S.ready[CC] = false
    H.S.tracked[ZENITH] = true; H.S.auras[ZENITH] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == ZENITH), "no Zenith from a fake 'just pressed Xuen'")
end)

test("look-ahead: Zenith never appears twice in the queue (its window is granted in the sim)", function()
    conduit("st"); H.db.numQueue = 3
    H.S.talents[392986] = true
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, XUEN)          -- just pressed Xuen
    H.S.ready[XUEN] = false
    H.S.tracked[ZENITH] = true; H.S.auras[ZENITH] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 2, belowMax = false } -- 2 charges: both lines would want it
    local r = H.Engine:Evaluate()
    local n = 0
    for _, id in ipairs(ids(r)) do if id == ZENITH then n = n + 1 end end
    eq(n, 1, "exactly one Zenith in primary+queue")
    eq(r.primary.id, ZENITH, "and it is the primary")
end)

test("look-ahead: WDP does not pivot into the primary during a Fists channel while RSK is up", function()
    conduit("st"); H.db.numQueue = 2
    H.S.ready[XUEN] = false; H.S.ready[443028] = false
    H.S.tracked[443294] = true; H.S.auras[443294] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    H.Engine.P.lastCast = 113656; H.Engine.P.lastCastKey = "FistsOfFury"
    H.S.ready[113656] = false                                        -- Fists on cooldown (channeling it)
    H.S.ready[152175] = true; H.S.usable[152175] = true              -- WDP's own CD up (usability is skipped mid-channel)
    local oldCh = UnitChannelInfo
    UnitChannelInfo = function() return "Fists of Fury", nil, nil, nil, 0, 4000 end
    H.S.ready[107428] = true                                         -- RSK is UP -> WDP not actually castable
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == 152175), "no WDP while RSK is up")
    H.S.ready[107428] = false                                        -- RSK on cooldown -> WDP is real
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 152175, "WDP once RSK is down too")
    UnitChannelInfo = oldCh
end)

test("look-ahead: a channel's Chi is not double-spent (RSK, not Tiger Palm, mid-Fists at 2 Chi)", function()
    conduit("st"); H.db.numQueue = 2
    H.S.ready[XUEN] = false; H.S.ready[443028] = false; H.S.known[392983] = false
    H.S.tracked[443294] = true; H.S.auras[443294] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    H.S.ready[113656] = false; H.S.ready[1272696] = false; H.S.ready[152175] = false
    H.S.power[12] = 2                                                -- live Chi ALREADY net of the Fists cost
    H.S.power[3] = 150; H.Engine:UpdateEnergy(H.S.now)
    local oldCh, oldCast = UnitChannelInfo, UnitCastingInfo
    UnitChannelInfo = function() return "Fists of Fury", nil, nil, nil, 0, 4000, nil, nil, 113656 end
    H.Engine.P.lastCast = 113656; H.Engine.P.lastCastKey = "FistsOfFury"
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    eq(seq[1], 107428, "Rising Sun Kick (2 Chi) leads mid-Fists, not Tiger Palm")
    local tp = 0
    for _, id in ipairs(seq) do if id == 100780 then tp = tp + 1 end end
    truthy(tp <= 1, "Tiger Palm at most once in the queue")
    UnitChannelInfo, UnitCastingInfo = oldCh, oldCast
end)

test("look-ahead: a starved strip still names what's next (queued TP defers to simulated Energy)", function()
    conduit("st"); H.db.numQueue = 2
    H.S.ready[XUEN] = false; H.S.ready[443028] = false; H.S.known[392983] = false
    H.S.tracked[443294] = true; H.S.auras[443294] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    H.S.ready[113656] = false; H.S.ready[107428] = false; H.S.ready[152175] = false; H.S.ready[1272696] = false
    H.S.power[12] = 1                                                -- one Chi: paid Blackout Kick is the only press
    H.S.power[3] = 40; H.Engine:UpdateEnergy(H.S.now)                -- Energy 40 (< 55): TP not pressable NOW
    H.S.insufficientPower[100780] = true
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    eq(seq[1], 100784, "Blackout Kick leads")
    truthy(seq[2] == 100780, "Tiger Palm is queued next (affordable after a GCD of regen), not blanked")
end)

test("conduit: the chained 2nd Zenith waits until Chi is spent down to 3", function()
    conduit("st"); H.db.numQueue = 0
    H.S.talents[392986] = true
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, XUEN)
    H.Engine.P.lastCast = 113656; H.Engine.P.lastCastKey = "FistsOfFury"
    H.S.now = H.S.now + 16; H.S.ready[XUEN] = false
    H.S.tracked[ZENITH] = true; H.S.auras[ZENITH] = false
    H.S.chargeState[ZENITH] = { max = 2, cur = 1, belowMax = true }
    H.S.ready[113656] = false; H.S.ready[152175] = false
    H.S.power[12] = 6
    local r = H.Engine:Evaluate()
    truthy(not (r and r.primary and r.primary.id == ZENITH), "at 6 Chi: spend first, no Zenith yet")
    H.S.power[12] = 3
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, ZENITH, "at 3 Chi: chain the 2nd Zenith")
end)

test("conduit ST: Spinning Crane Kick with Unbroken Rhythm out-ranks Rising Sun Kick", function()
    conduit_spenders(); H.S.power[12] = 4; H.S.ready[FOF] = false; H.S.ready[RSK_ID] = true
    H.S.tracked[1296624] = true; H.S.auras[1296624] = true          -- Unbroken Rhythm up
    H.db.numQueue = 0
    local r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, 101546, "SCK (Unbroken) leads over RSK")
    H.S.auras[1296624] = false
    r = H.Engine:Evaluate()
    eq(r and r.primary and r.primary.id, RSK_ID, "without Unbroken, RSK leads")
end)
