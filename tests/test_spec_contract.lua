-- test_spec_contract.lua -------------------------------------------------------
-- Every registered spec must carry the fields the UI and engine read, for EVERY
-- spec at once. Added after Assassination shipped with `name` where the rest of the
-- codebase uses `label`: the Lua compiled, all 206 rotation tests passed, and the
-- spec still could not be selected -- Options resolved nothing, so the sidebar said
-- "No spec profile" and the Specialization dropdown was empty. Nothing caught it
-- because the rotation tests drive Engine:Evaluate() directly and never touch Options.
--------------------------------------------------------------------------------

-- field -> who reads it, so a failure says why it matters.
local REQUIRED = {
    { "key",           "db customPriorities / profiles are keyed on it" },
    { "label",         "Options spec name + the export header (NOT `name`)" },
    { "specID",        "PRIO.specs registration key" },
    { "resource",      "the engine's resource gates" },
    -- NOT required: `resourceLabel`. Every reader falls back ("Resource" / "resource"),
    -- so a spec without one is only cosmetically worse. Elemental currently has none
    -- and shows the generic label -- left alone rather than quietly changed here.
    { "spells",        "name -> spellID map the priority lists resolve through" },
    { "pickable",      "the ability picker in the priority editor" },
}

local function describe(id, spec)
    return (spec and spec.label or ("spec " .. tostring(id)))
end

test("spec contract: every registered spec has the fields the UI reads", function()
    local checked = 0
    for id, spec in pairs(PRIO.specs) do
        checked = checked + 1
        for _, req in ipairs(REQUIRED) do
            local field, why = req[1], req[2]
            truthy(spec[field],
                ("%s (specID %s) is missing `%s` -- %s"):format(describe(id, spec), tostring(id), field, why))
        end
        -- A spec must offer a priority list one way or the other.
        truthy(spec.priority or spec.priorityByVariant,
            ("%s has neither `priority` nor `priorityByVariant`"):format(describe(id, spec)))
    end
    -- Guard against a vacuous loop. Deliberately loose: the harness loads a SUBSET of
    -- the spec files (see harness.lua), so an exact count would drift on every new spec.
    truthy(checked >= 5, "expected specs to be registered, got " .. checked)
end)

test("spec contract: no spec uses `name` where `label` is meant", function()
    for id, spec in pairs(PRIO.specs) do
        falsy(spec.name,
            ("%s (specID %s) sets `name` -- Options reads `label`; `name` is silently ignored")
                :format(describe(id, spec), tostring(id)))
    end
end)

test("spec contract: hero-split specs are internally consistent", function()
    for id, spec in pairs(PRIO.specs) do
        if spec.priorityByVariant then
            truthy(spec.activeHero,
                ("%s has priorityByVariant but no activeHero resolver"):format(describe(id, spec)))
            truthy(spec.priorityVariants,
                ("%s has priorityByVariant but no priorityVariants (the Options picker)"):format(describe(id, spec)))
            -- Every variant the picker offers must actually have lists behind it.
            for _, v in ipairs(spec.priorityVariants or {}) do
                local lists = spec.priorityByVariant[v.key]
                truthy(lists, ("%s: variant %q is offered but has no lists"):format(describe(id, spec), tostring(v.key)))
                truthy(lists and lists.st, ("%s: variant %q has no ST list"):format(describe(id, spec), tostring(v.key)))
            end
            -- ...and the resolver must return one of the offered variants.
            local ok, key = pcall(spec.activeHero)
            truthy(ok, ("%s: activeHero() threw"):format(describe(id, spec)))
            if ok then
                truthy(spec.priorityByVariant[key],
                    ("%s: activeHero() returned %q, which has no lists"):format(describe(id, spec), tostring(key)))
            end
        end
    end
end)

test("spec contract: every pickable name resolves to a spell id", function()
    for id, spec in pairs(PRIO.specs) do
        for _, nm in ipairs(spec.pickable or {}) do
            truthy(spec.spells and spec.spells[nm],
                ("%s: pickable %q has no entry in spec.spells"):format(describe(id, spec), tostring(nm)))
        end
    end
end)
