-- Encounter.lua ----------------------------------------------------------------
-- The raid cooldown planner (design: docs/encounter-planner.md).
--
-- Assign cooldowns to fight timings or boss abilities per encounter; the engine then
-- takes those cooldowns OUT of the normal priority (suppression) and recommends them
-- when their trigger window opens (injection into the primary slot).
--
-- Runtime source of truth is BigWigs (hard dependency for live triggers): bar starts,
-- stage changes, and warnings feed a small live state. The combat log is NOT read
-- (secret in 12.1). Encounter/difficulty come from the native ENCOUNTER_START event.
--
-- This file splits into (a) PURE logic -- TriggerOpen / Resolve / ParseMRT -- which is
-- unit-tested headless, and (b) WoW/BigWigs GLUE, guarded so it's inert under tests and
-- when BigWigs is absent.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API

local E = { state = {}, active = nil }
PRIO.Encounter = E

local DEFAULT_WINDOW = 5     -- seconds a "cast now" prompt stays live after its trigger
local PHASE_WINDOW   = 8     -- phases get a slightly longer window

-- Difficulty IDs (ENCOUNTER_START's difficultyID). Raid values; the UI maps to these.
E.DIFF = { normal = 14, heroic = 15, mythic = 16, lfr = 17 }
E.DIFF_ORDER = { { key = "mythic", id = 16, label = "Mythic" },
                 { key = "heroic", id = 15, label = "Heroic" },
                 { key = "normal", id = 14, label = "Normal" } }

--------------------------------------------------------------------------------
-- Pure trigger evaluation
--------------------------------------------------------------------------------
-- A trigger is exactly one of:
--   { type = "time",  at = <sec since pull>,           window = <sec?> }
--   { type = "cast",  spell = <bossSpellID>, occ = <n?>, off = <sec?>, window = <sec?> }
--   { type = "phase", stage = <n>,                     window = <sec?> }
-- ctx = { now, pullTime, events = { [spellID] = { times = {t1,t2,...} } }, stage, stageAt }.
function E.TriggerOpen(trig, ctx)
    if not (trig and ctx) then return false end
    local win = trig.window
    if trig.type == "time" then
        win = win or DEFAULT_WINDOW
        local clock = (ctx.now or 0) - (ctx.pullTime or ctx.now or 0)
        local at = trig.at or 0
        return clock >= at and clock <= at + win
    elseif trig.type == "cast" then
        win = win or DEFAULT_WINDOW
        local ev = ctx.events and ctx.events[trig.spell]
        if not (ev and ev.times) then return false end
        local t = ev.times[trig.occ or 1]
        if not t then return false end
        local open = t + (trig.off or 0)
        return ctx.now >= open and ctx.now <= open + win
    elseif trig.type == "phase" then
        win = win or PHASE_WINDOW
        if not (ctx.stage and trig.stage and ctx.stage == trig.stage) then return false end
        local ent = ctx.stageAt or ctx.pullTime or 0
        return ctx.now >= ent and ctx.now <= ent + win
    end
    return false
end

-- Short human summary of a trigger, for the editor rows / MRT review.
function E.TriggerLabel(trig)
    if not trig then return "?" end
    if trig.type == "time" then
        local s = trig.at or 0
        return ("pull + %d:%02d"):format(math.floor(s / 60), s % 60)
    elseif trig.type == "cast" then
        local nm = (API.SpellName and API.SpellName(trig.spell)) or ("#" .. tostring(trig.spell))
        local occ = (trig.occ and trig.occ > 1) and (" #" .. trig.occ) or ""
        local off = (trig.off and trig.off ~= 0) and (" +" .. trig.off .. "s") or ""
        return "on " .. nm .. occ .. off
    elseif trig.type == "phase" then
        return "on phase " .. tostring(trig.stage)
    end
    return "?"
end

--------------------------------------------------------------------------------
-- Resolve the active plan against live state -> (managedSet, injectSid)
--   managedSet[sid] = true  for every cooldown the plan owns (suppress from auto)
--   injectSid                the sid to force as primary right now (or nil)
-- Returns nil, nil when no plan is active (engine then behaves normally).
--------------------------------------------------------------------------------
-- Map a spec key's spell id plus its base/override variants (so suppression matches
-- whichever id the engine resolves the row to).
local function addVariants(set, sid)
    if not sid then return end
    set[sid] = true
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, ovr = pcall(C_Spell.GetOverrideSpell, sid); if ok and ovr then set[ovr] = true end
    end
    if C_Spell and C_Spell.GetBaseSpell then
        local ok, base = pcall(C_Spell.GetBaseSpell, sid); if ok and base then set[base] = true end
    end
end

function E:Resolve(spec)
    local plan = self.active
    if not (spec and plan and plan.enabled ~= false and plan.entries and #plan.entries > 0) then
        return nil, nil
    end
    local now = GetTime()
    local ctx = {
        now = now, pullTime = self.state.pullTime or now,
        events = self.state.events, stage = self.state.stage, stageAt = self.state.stageAt,
    }
    local managed, inject = {}, nil
    for _, e in ipairs(plan.entries) do
        local sid = spec.spells and spec.spells[e.spell]
        if sid then
            addVariants(managed, sid)
            -- First entry (plan order = precedence) whose window is open and which is
            -- actually castable wins the primary slot.
            if not inject and E.TriggerOpen(e.trig, ctx)
               and API.IsKnown(sid) and API.IsReady(sid) then
                inject = sid
            end
        end
    end
    return managed, inject
end

--------------------------------------------------------------------------------
-- MRT note import (pure): parse -> filter-to-me -> map. See docs table.
--   note        the raw MRT/lorrgs note text
--   playerName  keep only lines cast by this name (realm-stripped, case-insensitive)
--   sidToKey    { [assignedSpellID] = specKey } for THIS spec's managed cooldowns
-- Returns entries = { {spell=<specKey>, trig=...}, ... }, and skipped = { {line, reason} }.
--------------------------------------------------------------------------------
local function stripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end
local function baseName(n)
    if not n then return nil end
    return (n:gsub("%-.*$", "")):lower()   -- drop -Realm, lowercase
end

function E.ParseMRT(note, playerName, sidToKey)
    local entries, skipped = {}, {}
    if type(note) ~= "string" then return entries, skipped end
    local me = baseName(playerName)
    for rawline in (note .. "\n"):gmatch("(.-)\n") do
        local line = stripColor(rawline)
        local braces = line:match("^%s*{time:([^}]*)}")
        local assigned = line:match("{spell:(%d+)}")
        if braces and assigned then
            assigned = tonumber(assigned)
            -- caster: first non-space token after the {spell:} tag, before "=>".
            local caster = line:match("{spell:%d+}%s*([^%s=]+)")
            local key = sidToKey and sidToKey[assigned]
            if not key then
                skipped[#skipped + 1] = { line = rawline, reason = "not a tracked cooldown" }
            elseif not caster then
                skipped[#skipped + 1] = { line = rawline, reason = "no assignee (group/role note?)" }
            elseif me and baseName(caster) ~= me then
                -- someone else's assignment; silently ignore (not surfaced as skipped)
            else
                -- Decode the trigger from the {time:...} tokens.
                local mm, ss = braces:match("^(%d+):(%d+)")
                local timeSec = (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
                local scSpell, scOcc = braces:match("SC[CS]:(%d+):?(%d*)")
                local phase = braces:match("[,{]?p(%d+)") or braces:match("p:(%d+)")
                local trig
                if scSpell then
                    trig = { type = "cast", spell = tonumber(scSpell),
                             occ = tonumber(scOcc) or 1, off = timeSec, window = DEFAULT_WINDOW }
                elseif phase then
                    trig = { type = "phase", stage = tonumber(phase), window = PHASE_WINDOW }
                else
                    trig = { type = "time", at = timeSec }
                end
                entries[#entries + 1] = { spell = key, trig = trig }
            end
        end
    end
    return entries, skipped
end

-- Build the { [assignedSpellID] = specKey } map for a spec: every pickable cooldown,
-- keyed by its live spell id (and base/override variants) so MRT's {spell:id} resolves.
function E.SidToKey(spec)
    local map = {}
    if not (spec and spec.spells) then return map end
    for key, sid in pairs(spec.spells) do
        map[sid] = key
        if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ovr = pcall(C_Spell.GetOverrideSpell, sid); if ok and ovr then map[ovr] = key end
        end
        if C_Spell and C_Spell.GetBaseSpell then
            local ok, base = pcall(C_Spell.GetBaseSpell, sid); if ok and base then map[base] = key end
        end
    end
    return map
end

--------------------------------------------------------------------------------
-- Plan storage helpers (db.encounterPlans[specKey][encID][diffID])
--------------------------------------------------------------------------------
function E.SpecKey()
    local id = API.GetSpecID and API.GetSpecID()
    local spec = id and PRIO.specs and PRIO.specs[id]
    return spec and spec.key, spec
end

function E:GetPlan(specKey, encID, diffID, create)
    local db = PRIO.db
    if not (db and specKey and encID and diffID) then return nil end
    local root = db.encounterPlans
    if not root then if not create then return nil end; root = {}; db.encounterPlans = root end
    local byEnc = root[specKey]; if not byEnc then if not create then return nil end; byEnc = {}; root[specKey] = byEnc end
    local byDiff = byEnc[encID]; if not byDiff then if not create then return nil end; byDiff = {}; byEnc[encID] = byDiff end
    local plan = byDiff[diffID]
    if not plan and create then plan = { enabled = true, entries = {} }; byDiff[diffID] = plan end
    return plan
end

--------------------------------------------------------------------------------
-- Live lifecycle (WoW glue). Inert under tests (ENCOUNTER_START never fires there).
--------------------------------------------------------------------------------
function E:OnEncounterStart(encID, name, diffID, size)
    self.lastEnc = { id = encID, name = name, diff = diffID }
    self.state = { pullTime = GetTime(), events = {}, stage = 1, stageAt = GetTime() }
    self.learn = {}   -- learn-from-pull: spellID -> { name, at, fireIn }
    -- Register the encounter name right away so it appears in the editor's picker even
    -- if the pull is a wipe (before ENCOUNTER_END would persist it).
    if PRIO.db and encID and name then
        PRIO.db.encounterNames = PRIO.db.encounterNames or {}
        PRIO.db.encounterNames[encID] = name
    end
    local specKey = E.SpecKey()
    self.active = specKey and self:GetPlan(specKey, encID, diffID, false) or nil
end

function E:OnEncounterEnd(encID, name, diffID, size, success)
    -- Persist what BigWigs showed this pull so the editor can offer real abilities/times.
    if self.learn and encID and next(self.learn) then
        local db = PRIO.db
        if db then
            db.encounterLearned = db.encounterLearned or {}
            db.encounterLearned[encID] = self.learn
            db.encounterNames = db.encounterNames or {}
            if name then db.encounterNames[encID] = name end
        end
    end
    self.active = nil
    self.state = {}
    self.learn = nil
end

-- Record a boss event (an ability fired / was warned). key is BigWigs' option key,
-- usually the spellID. Only numeric keys drive "cast" triggers.
function E:RecordEvent(key)
    local sid = tonumber(key)
    if not (sid and self.state and self.state.events) then return end
    local ev = self.state.events[sid]
    if not ev then ev = { times = {} }; self.state.events[sid] = ev end
    ev.times[#ev.times + 1] = GetTime()
end

-- Record a scheduled bar for learn-from-pull (catalog + default placement).
function E:RecordBar(key, text, time, icon)
    local sid = tonumber(key)
    if not (sid and self.learn) then return end
    if not self.learn[sid] then
        local clock = GetTime() - ((self.state and self.state.pullTime) or GetTime())
        self.learn[sid] = { name = text, icon = icon, at = clock, fireIn = time }
    end
end

function E:OnStage(stage)
    if not self.state then return end
    stage = tonumber(stage)
    if stage and stage ~= self.state.stage then
        self.state.stage = stage
        self.state.stageAt = GetTime()
    end
end

--------------------------------------------------------------------------------
-- BigWigs subscription (guarded). Registered once at login if BigWigs is present.
--------------------------------------------------------------------------------
function E:HookBigWigs()
    if self._bwHooked then return true end
    local BW = _G.BigWigsLoader
    if not (BW and BW.RegisterMessage) then return false end
    local handle = {}
    self._bwHandle = handle
    BW.RegisterMessage(handle, "BigWigs_StartBar", function(_, module, key, text, time, icon)
        E:RecordBar(key, text, time, icon)
    end)
    BW.RegisterMessage(handle, "BigWigs_Message", function(_, module, key)
        E:RecordEvent(key)
    end)
    BW.RegisterMessage(handle, "BigWigs_SetStage", function(_, module, stage)
        E:OnStage(stage)
    end)
    self._bwHooked = true
    return true
end

function E.HasBigWigs() return _G.BigWigsLoader ~= nil end

-- Read the shared MRT note text if MRT is installed (for the "read live" import path).
function E.GetMRTNote()
    local v = _G.VMRT
    local note = v and v.Note
    if type(note) ~= "table" then return nil end
    return note.Text1 or note.SelfText
end

function E.PlayerName()
    return (UnitName and UnitName("player")) or nil
end

--------------------------------------------------------------------------------
-- Wiring (guarded so the headless harness -- which provides PRIO:On -- is unaffected).
--------------------------------------------------------------------------------
if PRIO.On then
    PRIO:On("ENCOUNTER_START", function(id, name, diff, size) E:OnEncounterStart(id, name, diff, size) end)
    PRIO:On("ENCOUNTER_END",   function(id, name, diff, size, ok) E:OnEncounterEnd(id, name, diff, size, ok) end)
    PRIO:On("PLAYER_LOGIN",    function() E:HookBigWigs() end)
    -- BigWigs may load after us; retry once things settle.
    PRIO:On("PLAYER_ENTERING_WORLD", function() E:HookBigWigs() end)
end

return E
