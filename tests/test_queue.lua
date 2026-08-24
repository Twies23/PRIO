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
