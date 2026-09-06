-- test_ret.lua ----------------------------------------------------------------
-- Retribution Paladin (70) smoke + Holy-Power gating: the "5 Holy Power" dumps,
-- the Divine Arbiter proc line ordering, and finishers withheld below 3 HP.
--------------------------------------------------------------------------------

local AW, ES, DS, FV, WOA, TOLL, BOJ, HOW, JUDG = 31884, 343527, 53385, 383328, 255937, 375576, 184575, 24275, 20271
local DIVARBITER = 1306161

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
