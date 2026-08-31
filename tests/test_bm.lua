-- test_bm.lua -----------------------------------------------------------------
-- Beast Mastery (253) smoke + hero-detection tests. Guards the structural
-- contract: the spec registers, both hero variants resolve for every mode, and
-- the Pack Leader / Dark Ranger split keys on a STRICT keystone check.
--------------------------------------------------------------------------------

local HOWL       = 471876   -- Howl of the Pack Leader (Pack Leader keystone)
local BLACKARROW = 466930   -- Black Arrow (Dark Ranger keystone)

test("BM spec registered under 253", function()
    truthy(H.bmSpec, "Beast Mastery spec should be registered")
    eq(H.bmSpec.className, "Hunter")
    eq(H.bmSpec.label, "Beast Mastery")
end)

test("activeHero: Howl talented -> pack_leader", function()
    H.reset()
    H.S.knownStrict[HOWL] = true
    eq(H.bmSpec.activeHero(), "pack_leader")
end)

test("activeHero: no Howl but Black Arrow -> dark_ranger", function()
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = true
    eq(H.bmSpec.activeHero(), "dark_ranger")
end)

test("activeHero: neither keystone -> pack_leader default", function()
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = false
    eq(H.bmSpec.activeHero(), "pack_leader")
end)

test("exposes only ST and AoE modes (no Cleave tier)", function()
    eq(#H.bmSpec.modes, 2)
    eq(H.bmSpec.modes[1].value, "st")
    eq(H.bmSpec.modes[2].value, "aoe")
    eq(H.bmSpec.cleaveAt, H.bmSpec.aoeAt, "cleaveAt == aoeAt collapses the Cleave tier")
end)

test("both hero variants resolve for every mode", function()
    for _, variant in ipairs({ "pack_leader", "dark_ranger" }) do
        local lists = H.bmSpec.priorityByVariant[variant]
        truthy(lists, variant .. " lists should exist")
        for _, mode in ipairs({ "st", "aoe" }) do
            truthy(lists[mode] and lists[mode][1], variant .. "." .. mode .. " should be a non-empty list")
        end
    end
end)

test("spec.priority proxy resolves to the active hero's list", function()
    H.reset()
    H.S.knownStrict[HOWL] = true
    truthy(H.bmSpec.priority.st and H.bmSpec.priority.st[1], "pack_leader st resolves")
    H.reset()
    H.S.knownStrict[HOWL] = false
    H.S.knownStrict[BLACKARROW] = true
    truthy(H.bmSpec.priority.aoe and H.bmSpec.priority.aoe[1], "dark_ranger aoe resolves")
end)

test("every priority row names a spell that exists in spec.spells", function()
    for variant, lists in pairs(H.bmSpec.priorityByVariant) do
        for mode, list in pairs(lists) do
            for i, row in ipairs(list) do
                truthy(H.bmSpec.spells[row.spell],
                    ("%s.%s[%d]: '%s' must be a known spec spell"):format(variant, mode, i, tostring(row.spell)))
            end
        end
    end
end)
