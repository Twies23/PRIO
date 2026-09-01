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
    H.S.tracked[443294] = true; H.S.auras[443294] = true  -- HoJS active -> Celestial Conduit fails
    H.S.ready[113656] = false                          -- Fists of Fury on cooldown
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
