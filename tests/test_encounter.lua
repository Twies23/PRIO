-- test_encounter.lua ----------------------------------------------------------
-- Encounter planner: trigger-window evaluation, plan resolution (managed set +
-- injection), MRT note parsing, and the engine overlay (suppression + injection).
--------------------------------------------------------------------------------

-- Load the real module into the harness PRIO (not loaded by harness.lua).
loadfile(ADDON_DIR .. "\\Encounter.lua")("PRIO", PRIO)
local E = PRIO.Encounter

--------------------------------------------------------------------------------
-- TriggerOpen
--------------------------------------------------------------------------------
test("trigger: time window opens for `window` seconds after `at`", function()
    local ctx = { now = 103, pullTime = 100 }                 -- clock = 3
    truthy(E.TriggerOpen({ type = "time", at = 3, window = 5 }, ctx), "open at start")
    falsy(E.TriggerOpen({ type = "time", at = 10, window = 5 }, ctx), "before its time")
    ctx.now = 110                                             -- clock = 10
    falsy(E.TriggerOpen({ type = "time", at = 3, window = 5 }, ctx), "past the window")
end)

test("trigger: cast fires on the Nth occurrence, offset by `off`", function()
    local ctx = { now = 0, events = { [12345] = { times = { 200, 260 } } } }
    ctx.now = 203; truthy(E.TriggerOpen({ type = "cast", spell = 12345, occ = 1, window = 5 }, ctx), "1st cast open")
    ctx.now = 207; falsy(E.TriggerOpen({ type = "cast", spell = 12345, occ = 1, window = 5 }, ctx), "1st cast expired")
    ctx.now = 262; truthy(E.TriggerOpen({ type = "cast", spell = 12345, occ = 2, window = 5 }, ctx), "2nd cast open")
    ctx.now = 266; truthy(E.TriggerOpen({ type = "cast", spell = 12345, occ = 2, off = 5, window = 5 }, ctx), "offset shifts window")
    falsy(E.TriggerOpen({ type = "cast", spell = 99999, occ = 1 }, ctx), "unseen cast never opens")
end)

test("trigger: phase opens while in the stage, for the phase window", function()
    local ctx = { now = 305, stage = 2, stageAt = 300 }
    truthy(E.TriggerOpen({ type = "phase", stage = 2, window = 8 }, ctx), "in stage")
    ctx.now = 309; falsy(E.TriggerOpen({ type = "phase", stage = 2, window = 8 }, ctx), "past phase window")
    ctx.now = 305; ctx.stage = 1
    falsy(E.TriggerOpen({ type = "phase", stage = 2, window = 8 }, ctx), "wrong stage")
end)

--------------------------------------------------------------------------------
-- Resolve: managed set + injection precedence + castable gating
--------------------------------------------------------------------------------
local function twoRetKeys()
    local keys = {}
    for _, k in ipairs(H.retSpec.pickable or {}) do
        if H.retSpec.spells[k] then keys[#keys + 1] = k end
        if #keys == 2 then break end
    end
    return keys[1], keys[2]
end

test("resolve: managed = all plan spells; inject = first open+castable entry", function()
    H.reset()
    local k1, k2 = twoRetKeys()
    local sid1, sid2 = H.retSpec.spells[k1], H.retSpec.spells[k2]
    E.state = { pullTime = GetTime(), events = {}, stage = 1, stageAt = GetTime() }
    E.active = { enabled = true, entries = {
        { spell = k1, trig = { type = "time", at = 0,   window = 60 } },   -- open now
        { spell = k2, trig = { type = "time", at = 999, window = 5 } },    -- closed
    } }
    local managed, inject = E:Resolve(H.retSpec)
    truthy(managed[sid1], "k1 suppressed")
    truthy(managed[sid2], "k2 suppressed (even though its window is closed)")
    eq(inject, sid1, "first open+castable entry injects")
    E.active = nil
end)

test("resolve: on-cooldown drift withholds injection but keeps suppression", function()
    H.reset()
    local k1 = (twoRetKeys())
    local sid1 = H.retSpec.spells[k1]
    H.S.ready[sid1] = false                       -- window open but on cooldown
    E.state = { pullTime = GetTime(), events = {}, stage = 1, stageAt = GetTime() }
    E.active = { enabled = true, entries = { { spell = k1, trig = { type = "time", at = 0, window = 60 } } } }
    local managed, inject = E:Resolve(H.retSpec)
    truthy(managed[sid1], "still suppressed")
    eq(inject, nil, "not injected while on cooldown")
    E.active = nil
end)

test("resolve: no active plan -> nil (engine untouched)", function()
    E.active = nil
    local managed, inject = E:Resolve(H.retSpec)
    eq(managed, nil); eq(inject, nil)
end)

--------------------------------------------------------------------------------
-- ParseMRT: parse -> filter-to-me -> map
--------------------------------------------------------------------------------
test("MRT import: maps my lines, decodes triggers, skips others", function()
    local sidToKey = { [31884] = "avengingWrath", [343527] = "execSentence" }
    local note = table.concat({
        "{time:0:03} {spell:31884}Tester",
        "{time:0:05,SCC:12345:2} {spell:343527}Tester => Boss",
        "{time:1:30} {spell:31884}Someone",              -- not me -> ignored
        "{time:0:10} {spell:99999}Tester",               -- unmapped -> skipped
        "{time:2:00,p2} {spell:343527}Tester",           -- phase
        "{time:0:20} {spell:31884}|cfffff468Tester|r",   -- class-colored name
    }, "\n")
    local entries, skipped = E.ParseMRT(note, "Tester-Realm", sidToKey)
    eq(#entries, 4, "kept my 4 mapped lines")
    eq(entries[1].trig.type, "time"); eq(entries[1].trig.at, 3)
    eq(entries[1].spell, "avengingWrath")
    eq(entries[2].trig.type, "cast"); eq(entries[2].trig.spell, 12345)
    eq(entries[2].trig.occ, 2); eq(entries[2].trig.off, 5)
    eq(entries[3].trig.type, "phase"); eq(entries[3].trig.stage, 2)
    eq(entries[4].trig.at, 20, "color codes stripped from the name")
    local sawUnmapped = false
    for _, s in ipairs(skipped) do if s.reason:match("tracked") then sawUnmapped = true end end
    truthy(sawUnmapped, "unmapped spell surfaced as skipped")
end)

test("MRT import: line with no {time:} tag is ignored", function()
    local entries = E.ParseMRT("just a note line {spell:31884}Tester", "Tester", { [31884] = "avengingWrath" })
    eq(#entries, 0)
end)

test("MRT import: assignee BEFORE the spell tag (lorrgs personal format)", function()
    local map = { [31884] = "avengingWrath" }
    local note = "{time:0:03} - Bilbrotem {spell:31884}\n{time:0:39.7} - Bilbrotem {spell:31884}"
    -- Name doesn't match the importer -> treat as a personal note, import all mapped lines.
    local entries = E.ParseMRT(note, "Someoneelse", map)
    eq(#entries, 2, "personal-note fallback imports all")
    eq(entries[1].trig.at, 3); eq(entries[2].trig.at, 39, "decimal seconds truncated")
    -- Same note, importer IS Bilbrotem -> still imports both (they're mine).
    eq(#(E.ParseMRT(note, "Bilbrotem-Realm", map)), 2)
end)

test("MRT import: note with no names at all imports every mapped line", function()
    local entries = E.ParseMRT("{time:0:05} {spell:31884}\n{time:1:00} {spell:31884}", "Whoever", { [31884] = "avengingWrath" })
    eq(#entries, 2)
end)

--------------------------------------------------------------------------------
-- Engine overlay: suppression + injection through Engine:Evaluate
--------------------------------------------------------------------------------
local function pickHas(res, sid)
    if res.primary and res.primary.id == sid then return true end
    for _, e in ipairs(res.queue or {}) do if e.id == sid then return true end end
    return false
end

test("engine: injection forces a triggered cooldown to the primary slot", function()
    H.reset(); H.S.specID = 70; H.rebind()
    local baseline = H.Engine:Evaluate()
    local basePrimary = baseline.primary and baseline.primary.id
    -- Choose a known cooldown that is NOT the baseline primary, so injection is observable.
    local injectKey, injectSid
    for _, k in ipairs(H.retSpec.pickable or {}) do
        local sid = H.retSpec.spells[k]
        if sid and sid ~= basePrimary then injectKey, injectSid = k, sid; break end
    end
    E.state = { pullTime = GetTime(), events = {}, stage = 1, stageAt = GetTime() }
    E.active = { enabled = true, entries = { { spell = injectKey, trig = { type = "time", at = 0, window = 60 } } } }
    local res = H.Engine:Evaluate()
    eq(res.primary.id, injectSid, "triggered cooldown is primary")
    truthy(res.bossPlan, "result flagged as boss plan")
    eq(res.modeLabel, "Boss plan")
    E.active = nil
end)

test("engine: a managed cooldown with a closed window is suppressed from the strip", function()
    H.reset(); H.S.specID = 70; H.rebind()
    local baseline = H.Engine:Evaluate()
    local basePrimary = baseline.primary and baseline.primary.id
    -- Find the spec key for the baseline primary and suppress it with a closed window.
    local key
    for k, sid in pairs(H.retSpec.spells) do if sid == basePrimary then key = k; break end end
    truthy(key, "resolved baseline primary to a spec key")
    E.state = { pullTime = GetTime(), events = {}, stage = 1, stageAt = GetTime() }
    E.active = { enabled = true, entries = { { spell = key, trig = { type = "time", at = 9999, window = 5 } } } }
    local res = H.Engine:Evaluate()
    falsy(pickHas(res, basePrimary), "suppressed cooldown no longer appears")
    falsy(res.bossPlan, "no injection while the window is closed")
    E.active = nil
end)
