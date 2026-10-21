-- test_elemental.lua -----------------------------------------------------------
-- Elemental (262): the user's default lists (1.3.6) and the Overcharge! 4-set buff
-- feeding the free-spender latch.
--------------------------------------------------------------------------------

local OVERCHARGE = 1300222
local EB, EQ = 117014, 462620
local ele = H.eleSpec

local function spells(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.spell end
    return table.concat(out, ",")
end

test("ele: default lists match the user's exports row for row", function()
    eq(spells(ele.priority.st),
       "Stormkeeper,AncestralSwiftness,FlameShock,Ascendance,ElementalBlast,LavaBurst,LightningBolt,ElementalBlast,LavaBurst,LavaBurst,LightningBolt")
    eq(spells(ele.priority.cleave),
       "Stormkeeper,AncestralSwiftness,FlameShock,VoltaicBlaze,Ascendance,ElementalBlast,ChainLightning,ElementalBlast,LavaBurst,LavaBurst,ChainLightning")
    eq(spells(ele.priority.aoe),
       "Stormkeeper,AncestralSwiftness,FlameShock,VoltaicBlaze,Ascendance,Earthquake,ChainLightning,LavaBurst,Earthquake,LavaBurst,ChainLightning")
end)

test("ele: every condition in the shipped lists is one the editor can show", function()
    H.reset(); H.S.specID = 262; H.rebind()
    local bad = {}
    local function walk(c, where)
        if type(c) ~= "table" then return end
        if c.clauses then for _, x in ipairs(c.clauses) do walk(x, where) end return end
        if c.type and not H.Cond.TypeMeta(c.type) then bad[#bad + 1] = where .. ": " .. c.type end
    end
    for mode, list in pairs(ele.priority) do
        for i, e in ipairs(list) do walk(e.cond, mode .. " #" .. i) end
    end
    eq(#bad, 0, table.concat(bad, ", "))
end)

test("ele: Overcharge! (tracked) makes the next spender free", function()
    H.reset(); H.S.specID = 262; H.rebind()
    H.S.tracked[OVERCHARGE] = true
    H.S.auras[OVERCHARGE] = false
    falsy(H.Engine:CurrentState().freeSpend, "no proc")
    H.S.auras[OVERCHARGE] = true
    truthy(H.Engine:CurrentState().freeSpend, "Overcharge! up -> free spender")
end)

test("ele: Overcharge! untracked -> falls back to the glow only", function()
    H.reset(); H.S.specID = 262; H.rebind()
    H.S.auras[OVERCHARGE] = true           -- not tracked: ignored
    falsy(H.Engine:CurrentState().freeSpend)
    H.S.glows[EB] = true
    truthy(H.Engine:CurrentState().freeSpend, "glow still works")
end)

test("ele: Overcharge! is in the setup checklist and the preset list", function()
    local found = false
    for _, it in ipairs(ele.setup) do if it.spell == OVERCHARGE then found = true end end
    truthy(found, "setup entry")
    local p = false
    for _, c in ipairs(ele.condPresets or {}) do if c.clause.spell == OVERCHARGE then p = true end end
    truthy(p, "preset")
end)
