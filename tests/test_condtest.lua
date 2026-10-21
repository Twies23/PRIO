-- test_condtest.lua ------------------------------------------------------------
-- The experimental Condition Test sampler (CondTest.lua): probe building, tallying,
-- verdicts, the per-type roll-up and the export. UI parts are not exercised.
--------------------------------------------------------------------------------

do
    local chunk = assert(loadfile(ADDON_DIR .. "\\CondTest.lua"))
    chunk("PRIO", PRIO)
end
local CT = PRIO.CondTest

local DANCE, SND, ANCIENTARTS, STEALTH = 185313, 315496, 1268932, 1784

local function setup()
    H.reset(); H.S.specID = 261
    H.S.power[4] = 3; H.S.powerMax[4] = 7
    for _, id in ipairs({ DANCE, SND, ANCIENTARTS, STEALTH }) do H.S.tracked[id] = true end
    H.S.knownStrict[441146] = true          -- Trickster
    H.rebind()
    CT:Build()
    CT:Reset()
end

local function find(group, pred)
    for _, p in ipairs(CT:Probes()) do
        if p.group == group and pred(p) then return p end
    end
end

test("condtest: builds list, preset and editor-type probes", function()
    setup()
    truthy(find("list", function(p) return p.type == "resourceMin" end), "a list condition")
    truthy(find("preset", function(p) return p.type == "preset:coupReady" end), "a preset")
    truthy(find("type", function(p) return p.type == "buffActive" and p.sid == DANCE end), "buff type x aura")
    truthy(find("type", function(p) return p.type == "enemiesMin" end), "value type")
end)

test("condtest: list probes are de-duplicated", function()
    setup()
    local n = 0
    for _, p in ipairs(CT:Probes()) do
        if p.group == "list" and p.type == "notStealthed" then n = n + 1 end
    end
    eq(n, 1, "Stealth's 'not stealthed' appears once though it's in ST and AoE")
end)

test("condtest: verdicts from in-combat samples", function()
    setup()
    local p = find("type", function(p) return p.type == "buffActive" and p.sid == DANCE end)
    eq(CT.Verdict(p.stats), "no data")
    H.S.auras[DANCE] = false; CT:Sample(H.Engine:CurrentState(), true)
    eq(CT.Verdict(p.stats), "always false")
    H.S.auras[DANCE] = true;  CT:Sample(H.Engine:CurrentState(), true)
    eq(CT.Verdict(p.stats), "works")
    eq(p.stats.c.flips, 1)
end)

test("condtest: out-of-combat samples don't count toward the verdict", function()
    setup()
    local p = find("type", function(p) return p.type == "buffActive" and p.sid == DANCE end)
    H.S.auras[DANCE] = false; CT:Sample(H.Engine:CurrentState(), false)
    H.S.auras[DANCE] = true;  CT:Sample(H.Engine:CurrentState(), false)
    eq(CT.Verdict(p.stats), "no data")
    eq(p.stats.o.flips, 1)
end)

test("condtest: a read that can't tell is 'unreadable'", function()
    setup()
    local p = find("type", function(p) return p.type == "buffActive" and p.sid == DANCE end)
    H.S.auras[DANCE] = nil                  -- tracked but the read returns nil
    CT:Sample(H.Engine:CurrentState(), true)
    CT:Sample(H.Engine:CurrentState(), true)
    eq(CT.Verdict(p.stats), "unreadable")
end)

test("condtest: a throwing condition is 'error'", function()
    setup()
    local p = find("type", function(p) return p.type == "enemiesMin" end)
    local real = H.Cond.ClauseStatus
    H.Cond.ClauseStatus = function(cl, ...) if cl == p.clause then error("boom") end return real(cl, ...) end
    CT:Sample(H.Engine:CurrentState(), true)
    H.Cond.ClauseStatus = real
    eq(CT.Verdict(p.stats), "error")
    truthy(p.stats.lastErr and p.stats.lastErr:find("boom"))
end)

test("condtest: type roll-up -- works if any variant works, broken first", function()
    setup()
    H.S.auras[DANCE] = false; CT:Sample(H.Engine:CurrentState(), true)
    H.S.auras[DANCE] = true;  CT:Sample(H.Engine:CurrentState(), true)
    local rows = CT:TypeSummary()
    local ba
    for _, t in ipairs(rows) do if t.type == "buffActive" then ba = t end end
    truthy(ba, "buffActive summarised")
    eq(ba.best, "works")
    truthy(ba.working >= 1 and ba.variants > 1)
    for i = 2, #rows do
        truthy(CT.RANK[rows[i - 1].best] <= CT.RANK[rows[i].best], "sorted worst first")
    end
end)

test("condtest: export has a header, the type section and the list section", function()
    setup()
    CT:Sample(H.Engine:CurrentState(), true)
    local txt = CT:ExportText()
    truthy(txt:find("Condition Test", 1, true))
    truthy(txt:find("EDITOR CONDITION TYPES", 1, true))
    truthy(txt:find("CONDITIONS IN YOUR LISTS", 1, true))
    truthy(txt:find("PRESETS", 1, true))
end)

test("condtest: reset clears tallies", function()
    setup()
    CT:Sample(H.Engine:CurrentState(), true)
    CT:Reset()
    for _, p in ipairs(CT:Probes()) do eq(p.stats.c.n, 0) end
end)

--------------------------------------------------------------------------------
-- Tracked-only condition types (time left / stacks / charges / cooldown left)
--------------------------------------------------------------------------------
local function has(list, id) for _, x in ipairs(list or {}) do if x == id then return true end end return false end

test("tracked: ordinary types are not tracked-only", function()
    eq(H.Cond.TrackedSpells(H.subSpec, "buffActive"), nil)
    eq(H.Cond.TrackedSpells(H.subSpec, "resourceMin"), nil)
end)

test("tracked: Subtlety has nothing for time left / stacks / charges, Shadow Blades for cooldown", function()
    local s = H.subSpec
    eq(#H.Cond.TrackedSpells(s, "auraRemainMin"), 0)
    eq(#H.Cond.TrackedSpells(s, "stacksMin"), 0)
    eq(#H.Cond.TrackedSpells(s, "chargesMin"), 0)
    eq(#H.Cond.TrackedSpells(s, "chargeTimeMax"), 0)
    local cds = H.Cond.TrackedSpells(s, "cdRemainMin")
    eq(#cds, 1); truthy(has(cds, 121471), "Shadow Blades (cooldownTrack)")
end)

test("tracked: modelled targets count (Windwalker duration timers + Tigereye stacks)", function()
    local ww = H.spec
    truthy(#H.Cond.TrackedSpells(ww, "auraRemainMax") >= 1, "auraDurations")
    truthy(has(H.Cond.TrackedSpells(ww, "stacksMin"), ww.tigereye.spell), "Tigereye")
    truthy(#H.Cond.TrackedSpells(ww, "chargesMax") >= 1, "chargeTrack")
end)

test("tracked: a target used deliberately in shipped lists counts (Assassination Scent of Blood)", function()
    truthy(has(H.Cond.TrackedSpells(H.assaSpec, "stacksMax"), 381799))
end)

test("condtest: tracked-only types are probed only on tracked spells", function()
    setup()
    for _, p in ipairs(CT:Probes()) do
        if p.group == "type" and p.type == "cdRemainMin" then eq(p.sid, 121471) end
        if p.group == "type" then
            falsy(p.type == "auraRemainMin" or p.type == "stacksMin" or p.type == "chargesMin",
                "no probes for untracked kinds: " .. p.type)
        end
    end
    local txt = CT:ExportText()
    truthy(txt:find("none tracked for this spec", 1, true))
end)
