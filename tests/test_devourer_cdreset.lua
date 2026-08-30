-- test_devourer_cdreset.lua ---------------------------------------------------
-- Devourer's cast-triggered cooldown RESETS (spec.cdResets). Casting Void Ray with
-- the Moment of Craving talent resets Reap -- so an on-cooldown Reap should reappear
-- in the queue after Void Ray. The reset is talent-gated: without the talent it stays
-- on cooldown and does NOT come back. Also exercises the shared engine path so the
-- feature can't silently regress for other specs.
--------------------------------------------------------------------------------

local REAP        = 1226019
local VOIDRAY     = 473728
local SOULIMMO    = 1241937
local VOIDBLADE   = 1245412
local THEHUNT     = 1246167
local VOIDMETA    = 1217605
local HUNGER      = 1239519
local CONSUME     = 473662
local REAPERSTOLL = 1245470
local PIERCE      = 1245483
local PREDWAKE    = 1259431
local TAL_MOMENT  = 1238488  -- Moment of Craving

local function ids(r)
    local out = { r.primary and r.primary.id }
    for _, e in ipairs(r.queue or {}) do out[#out + 1] = e.id end
    return out
end

local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
end

-- Outside-meta state where Void Ray is the only immediately castable rotational
-- ability and Reap is on cooldown. Everything else is gated off so the walk is
-- deterministic: Void Ray -> (reset) -> Reap -> Consume filler.
local function setup(momentCraving)
    H.reset()
    H.S.specID = 1480
    H.rebind()
    H.Engine.openerActive = false
    H.db.numQueue = 3
    H.S.enemies = 1                       -- ST

    -- Soul Immolation up (tracked) so its "refresh if missing" line fails and doesn't
    -- outrank Void Ray. (Untracked buffMissing reads as "missing" and would pass.)
    H.S.tracked[SOULIMMO] = true
    H.S.auras[SOULIMMO] = true
    -- Give Reap enough ground souls so its soulsGround(4) gate (fails CLOSED) passes --
    -- this test is about the cooldown reset, not the soul breakpoint.
    H.S.stacks[1225789] = 0            -- collected reads 0
    H.S.auras[1245577]  = true         -- souls on the ground

    -- Everything ABOVE Void Ray in the merged ST list is made uncastable so Void Ray is
    -- the deterministic primary; Reap is on cooldown (the reset target).
    H.S.ready[VOIDMETA]     = false
    H.S.ready[VOIDBLADE]    = false
    H.S.ready[THEHUNT]      = false
    H.S.ready[REAPERSTOLL]  = false
    H.S.ready[PIERCE]       = false
    H.S.ready[PREDWAKE]     = false
    H.S.ready[HUNGER]       = false
    H.S.ready[REAP]         = false       -- Reap ON cooldown (reset target)
    H.S.ready[VOIDRAY]      = true
    H.S.ready[CONSUME]      = true        -- generator filler

    H.S.talents[TAL_MOMENT] = momentCraving and true or false
    H.Engine.P.groundSouls = 6         -- >= 4 on the ground -> Reap's soulsGround(4) passes
end

test("devourer: Void Ray resets Reap in the queue (Moment of Craving)", function()
    setup(true)
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    eq(seq[1], VOIDRAY, "Void Ray is the primary (Reap is on cooldown)")
    truthy(has(seq, REAP), "Reap reappears after Void Ray reset it")
end)

test("devourer: no reset without the talent -- Reap stays on cooldown", function()
    setup(false)
    local r = H.Engine:Evaluate()
    local seq = ids(r)
    eq(seq[1], VOIDRAY, "Void Ray is still the primary")
    falsy(has(seq, REAP), "Reap must NOT reappear without Moment of Craving")
end)
