-- test_ret.lua ----------------------------------------------------------------
-- Retribution Paladin (70) smoke + Holy-Power gating: the "5 Holy Power" dumps,
-- the Divine Arbiter proc line ordering, and finishers withheld below 3 HP.
--------------------------------------------------------------------------------

local AW, ES, DS, FV, WOA, TOLL, BOJ, HOW, JUDG = 31884, 343527, 53385, 383328, 255937, 375576, 184575, 1241288, 20271
local DIVARBITER = 1306161
local DIVCAST = 1241410   -- "Hammer of Wrath can be cast" buff

-- Set up Ret in ST with all COOLDOWNS on cooldown so the Holy-Power lines are what
-- the walk reaches (Avenging Wrath / Execution Sentence / Wake of Ashes / Divine Toll
-- otherwise fire first, being unconditional).
local function ret(hp)
    H.reset()
    H.S.specID = 70
    H.S.enemies = 1
    H.S.power[9] = hp or 0                  -- Holy Power (discrete, clean)
    H.S.powerMax[9] = 5
    H.rebind()
    H.Engine.openerActive = false
    H.db.numQueue = 2
    -- cooldowns unavailable this beat
    H.S.ready[AW] = false; H.S.ready[ES] = false
    H.S.ready[WOA] = false; H.S.ready[TOLL] = false
end

local function has(r, id)
    if r.primary and r.primary.id == id then return true end
    for _, e in ipairs(r.queue or {}) do if e.id == id then return true end end
    return false
end

test("Ret spec registered under 70", function()
    truthy(H.retSpec, "Retribution spec should be registered")
    eq(H.retSpec.className, "Paladin")
    eq(H.retSpec.resource, 9, "resource is Holy Power (9)")
    truthy(H.retSpec.priority.st and H.retSpec.priority.st[1], "ST list resolves")
    truthy(H.retSpec.priority.aoe and H.retSpec.priority.aoe[1], "AoE list resolves")
end)

test("every Ret priority row names a spell that exists in spec.spells", function()
    for _, mode in ipairs({ "st", "aoe" }) do
        for i, row in ipairs(H.retSpec.priority[mode]) do
            truthy(H.retSpec.spells[row.spell],
                ("%s[%d]: '%s' must be a known spec spell"):format(mode, i, tostring(row.spell)))
        end
    end
end)

test("ST: at 5 Holy Power with no Divine Arbiter proc, Final Verdict is the primary", function()
    ret(5)
    -- HoW held (not usable outside execute/Wings), no Art of War, no Divine Arbiter.
    H.S.usable[HOW] = false
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, FV, "Final Verdict dumps at 5 HP")
end)

test("ST: Divine Arbiter proc (glow) at 5 HP takes Divine Storm over Final Verdict", function()
    ret(5)
    H.S.usable[HOW] = false
    H.S.glows[DS] = true          -- Divine Arbiter empowers the next Divine Storm (proc glow)
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, DS, "empowered Divine Storm beats Final Verdict at 5 HP")
end)

test("ST: below 3 Holy Power, the PRIMARY is a builder, not a finisher", function()
    -- (The predicted queue may still show a finisher in a LATER slot once it has
    -- simulated building enough Holy Power -- that's the look-ahead working. Only the
    -- primary, the thing to press right now, must be a builder.)
    ret(2)
    H.S.usable[HOW] = false        -- Hammer of Wrath not usable this beat
    local r = H.Engine:Evaluate()
    truthy(r.primary, "a primary is suggested")
    truthy(r.primary.id ~= FV and r.primary.id ~= DS, "primary is not a finisher below 3 HP")
    truthy(r.primary.id == JUDG or r.primary.id == BOJ,
        "a Holy-Power builder (Judgment / Blade of Justice) is the primary instead")
end)

test("AoE: at 5 HP with no proc, Divine Storm is the AoE dump", function()
    ret(5)
    H.S.enemies = 4
    H.rebind()
    H.Engine.openerActive = false
    H.S.usable[HOW] = false
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, DS, "Divine Storm dumps at 5 HP in AoE")
end)

test("Hammer of Wrath is withheld outside Wings, shown during Wings (Avenging Wrath buff)", function()
    ret(0)
    -- Outside Avenging Wrath: the HoW lines gate on the Avenging Wrath buff -> not shown.
    H.S.tracked[AW] = true; H.S.auras[AW] = false
    local r = H.Engine:Evaluate()
    falsy(has(r, HOW), "HoW withheld outside Wings")

    -- During Avenging Wrath (buff up) + Hammer of Wrath ready -> HoW is suggested (line 11).
    H.S.auras[AW] = true
    H.S.ready[HOW] = true
    r = H.Engine:Evaluate()
    truthy(has(r, HOW), "HoW shown during Wings")
end)

test("cooldownTrack: Divine Toll base 60s, -30s with Quickened Invocation", function()
    local QI = 379391
    -- Base (talent not known): 60s.
    H.reset(); H.S.specID = 70; H.S.known[QI] = false; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TOLL)
    eq(H.Engine.P.cdExpire[TOLL], 1060, "Divine Toll base 60s cooldown")

    -- Quickened Invocation known: 30s.
    H.reset(); H.S.specID = 70; H.S.known[QI] = true; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, TOLL)
    eq(H.Engine.P.cdExpire[TOLL], 1030, "Quickened Invocation -> 30s cooldown")

    -- Wake of Ashes fixed 30s (no talent reduction).
    H.reset(); H.S.specID = 70; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, WOA)
    eq(H.Engine.P.cdExpire[WOA], 1030, "Wake of Ashes 30s cooldown")

    -- Avenging Wrath fixed 60s.
    H.reset(); H.S.specID = 70; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, AW)
    eq(H.Engine.P.cdExpire[AW], 1060, "Avenging Wrath 60s cooldown")
end)
