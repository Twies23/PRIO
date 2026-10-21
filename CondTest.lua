-- CondTest.lua -----------------------------------------------------------------
-- EXPERIMENTAL "Condition Test" panel (/prio condtest). Answers one question: which
-- conditions actually WORK in 12.1 combat, so the editor can be cleaned of the ones
-- that can't (secret values, untracked auras, reads Blizzard blocks).
--
-- While recording, it samples every probe a few times a second with the same
-- Cond.ClauseStatus the Priorities editor dots use, and keeps a tally per probe:
-- pass / fail / "can't tell" (open) / Lua error, split in combat vs out of combat, plus
-- how often the answer FLIPPED. A condition that never flips in a real fight, or never
-- reads at all, is a cleanup candidate.
--
-- Probes come from three places:
--   * Your lists   -- every distinct condition in the active spec's effective lists.
--   * Presets      -- the spec's named conditions (glows, predicted counters, ...).
--   * Editor types -- every condition type the editor offers for this spec, tried with
--                     each relevant spell (abilities for cooldown types, the spec's
--                     auras for buff types) and the editor's default value. Rolled up
--                     to one verdict per type: it WORKS if any variant flipped.
--
-- Self-contained on purpose (this file + one .toc line + one slash command) so it can
-- be removed cleanly if the experiment doesn't pan out.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local CondTest = {}
PRIO.CondTest = CondTest

CondTest.INTERVAL = 0.25          -- seconds between samples while recording

local probes = {}                 -- built per spec: { key, group, label, clause, sid, stats }
local byKey = {}
local builtFor = nil              -- spec key + variant the probes were built for
CondTest.recording = false
CondTest.startedAt = nil
CondTest.elapsedRecorded = 0
CondTest.combatSeconds = 0

--------------------------------------------------------------------------------
-- Probe building
--------------------------------------------------------------------------------
local function ser(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function newStats()
    return { c = { pass = 0, fail = 0, open = 0, err = 0, n = 0, flips = 0 },
             o = { pass = 0, fail = 0, open = 0, err = 0, n = 0, flips = 0 },
             last = nil, lastErr = nil }
end

local function addProbe(group, clause, sid, label)
    local key = group .. "|" .. ser(clause) .. "|" .. tostring(sid)
    if byKey[key] then return byKey[key] end
    local okL, lbl = pcall(PRIO.Cond.ClauseLabel, clause, sid)
    local p = {
        key = key, group = group, clause = clause, sid = sid,
        type = clause.type,
        label = label or (okL and lbl) or tostring(clause.type),
        stats = newStats(),
    }
    probes[#probes + 1] = p
    byKey[key] = p
    return p
end

-- Leaf clauses of a condition tree (AND/OR groups flattened).
local function leaves(cond, out)
    if type(cond) ~= "table" then return out end
    if cond.clauses then
        for _, c in ipairs(cond.clauses) do leaves(c, out) end
    elseif cond.type then
        out[#out + 1] = cond
    end
    return out
end

local function activeSpec()
    local id = API.GetSpecID and API.GetSpecID()
    return id and PRIO.specs and PRIO.specs[id]
end

local function variantOf(spec)
    if spec and spec.activeHero then
        local ok, v = pcall(spec.activeHero)
        if ok then return v end
    end
    return nil
end

-- Spell ids the spec's lists use (in order of first appearance), for ability-type probes.
local function listAbilities(spec)
    local out, seen = {}, {}
    local function add(sid) if sid and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end end
    for _, m in ipairs(PRIO.Cond.SpecModes(spec) or {}) do
        local list = PRIO.Engine:EffectiveList(spec.key, m.value)
        for _, e in ipairs(list or {}) do add(PRIO.Engine:EntrySpellID(e)) end
    end
    return out
end

local function specAuras(spec)
    local out, seen = {}, {}
    for _, sid in pairs(spec.auras or {}) do
        if type(sid) == "number" and not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
    end
    table.sort(out)
    return out
end

-- Editor types with no spell picker that read the ROW's own spell (selfSid).
local SELF_SPELL = { chargesMin = true, chargesMax = true, chargesEq = true }

function CondTest:Build(spec)
    wipe(probes); wipe(byKey)
    spec = spec or activeSpec()
    builtFor = spec and (spec.key .. "/" .. tostring(variantOf(spec))) or "none"
    if not spec then return probes end
    local Cond = PRIO.Cond

    -- 1. Every distinct condition in the lists you're actually running.
    for _, m in ipairs(Cond.SpecModes(spec) or {}) do
        local list = PRIO.Engine:EffectiveList(spec.key, m.value)
        for _, e in ipairs(list or {}) do
            local sid = PRIO.Engine:EntrySpellID(e)
            for _, cl in ipairs(leaves(e.cond, {})) do addProbe("list", cl, sid) end
        end
    end

    -- 2. Named presets.
    for _, p in ipairs(spec.condPresets or {}) do
        addProbe("preset", { type = "preset:" .. p.key }, nil, p.label or p.key)
    end

    -- 3. Every editor type with representative arguments.
    local abilities, auras = listAbilities(spec), specAuras(spec)
    for _, m in ipairs(Cond.TypesForSpec(spec) or {}) do
        local t = m.value
        if type(t) == "string" and not t:find("^preset:") and not m.needsTalent then
            local v = m.needsValue and m.def or nil
            if m.needsSpell then
                local pool = (m.target == "ability") and abilities or auras
                for _, sid in ipairs(pool) do
                    addProbe("type", { type = t, spell = sid, v = v }, sid)
                end
            elseif SELF_SPELL[t] then
                -- Reads the ROW's own spell (no spell picker): probe it on each ability.
                for _, sid in ipairs(abilities) do
                    addProbe("type", { type = t, v = v }, sid,
                        (PRIO.API.SpellName(sid) or ("#" .. sid)) .. ": " .. (m.text or t) .. " " .. tostring(v))
                end
            else
                addProbe("type", { type = t, v = v }, nil)
            end
        end
    end
    return probes
end

function CondTest:Probes() return probes end

--------------------------------------------------------------------------------
-- Sampling
--------------------------------------------------------------------------------
function CondTest:Sample(S, inCombat)
    if not S then return end
    local Cond = PRIO.Cond
    for _, p in ipairs(probes) do
        local bucket = inCombat and p.stats.c or p.stats.o
        bucket.n = bucket.n + 1
        local ok, st = pcall(Cond.ClauseStatus, p.clause, S, p.sid)
        if not ok then
            bucket.err = bucket.err + 1
            p.stats.lastErr = tostring(st)
        else
            if st ~= "pass" and st ~= "fail" then st = "open" end
            bucket[st] = bucket[st] + 1
            if st ~= "open" then
                if p.stats.last and p.stats.last ~= st then bucket.flips = bucket.flips + 1 end
                p.stats.last = st
            end
        end
    end
end

function CondTest:Reset()
    for _, p in ipairs(probes) do p.stats = newStats() end
    self.elapsedRecorded, self.combatSeconds = 0, 0
    self.startedAt = self.recording and GetTime() or nil
end

-- Verdict for a single probe, judged on COMBAT samples (that's where reads go secret).
--   error       -- the read threw
--   no data     -- not sampled in combat yet
--   unreadable  -- every combat sample was "can't tell"
--   always true / always false -- readable but never changed
--   works       -- seen both true and false in combat
local RANK = { error = 1, unreadable = 2, ["always false"] = 3, ["always true"] = 4, ["no data"] = 5, works = 6 }
CondTest.RANK = RANK

function CondTest.Verdict(stats)
    local c = stats.c
    if c.err > 0 then return "error" end
    if c.n == 0 then return "no data" end
    if c.pass > 0 and c.fail > 0 then return "works" end
    if c.pass == 0 and c.fail == 0 then return "unreadable" end
    return (c.pass > 0) and "always true" or "always false"
end

-- One row per editor TYPE: the best verdict across its spell variants (a type works
-- if any variant flipped), plus how many variants worked.
function CondTest:TypeSummary()
    local byType, order = {}, {}
    for _, p in ipairs(probes) do
        if p.group == "type" then
            local t = byType[p.type]
            if not t then
                t = { type = p.type, best = nil, variants = 0, working = 0, sample = nil }
                byType[p.type] = t; order[#order + 1] = t
            end
            local v = CondTest.Verdict(p.stats)
            t.variants = t.variants + 1
            if v == "works" then t.working = t.working + 1 end
            if not t.best or RANK[v] > RANK[t.best] then t.best = v; t.sample = p end
        end
    end
    table.sort(order, function(a, b)
        if RANK[a.best] ~= RANK[b.best] then return RANK[a.best] < RANK[b.best] end
        return a.type < b.type
    end)
    return order
end

local function typeText(t)
    local meta = PRIO.Cond.TypeMeta and PRIO.Cond.TypeMeta(t)
    return (meta and meta.text) or t
end
CondTest.TypeText = typeText

--------------------------------------------------------------------------------
-- Export (plain text for pasting back)
--------------------------------------------------------------------------------
local function counts(b)
    return ("pass %d / fail %d / can't tell %d / err %d, flips %d"):format(b.pass, b.fail, b.open, b.err, b.flips)
end

function CondTest:ExportText()
    local spec = activeSpec()
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
    local L = {}
    L[#L + 1] = ("PRIO v%s  |  Condition Test  |  %s  |  %s"):format(ver,
        spec and ((spec.className and (spec.label .. " " .. spec.className)) or spec.label) or "no spec",
        tostring(variantOf(spec) or "-"))
    L[#L + 1] = ("recorded %ds, in combat %ds, interval %.2fs, probes %d"):format(
        math.floor(self.elapsedRecorded or 0), math.floor(self.combatSeconds or 0), self.INTERVAL, #probes)
    L[#L + 1] = "verdicts are judged on IN-COMBAT samples only"
    L[#L + 1] = "  works = seen true AND false | unreadable = never gave an answer | error = the read threw"
    L[#L + 1] = "  always true/false = never changed while recording -- broken, OR the situation just"
    L[#L + 1] = "  didn't come up (e.g. 'Enemies >= 2' on a single dummy). Check before removing."
    L[#L + 1] = ("-"):rep(60)

    L[#L + 1] = "EDITOR CONDITION TYPES (one line per type; best variant shown)"
    for _, t in ipairs(self:TypeSummary()) do
        local p = t.sample
        L[#L + 1] = (" [%s] %s (%s)  -- %d/%d variants work; best: %s"):format(
            t.best, typeText(t.type), t.type, t.working, t.variants, p and p.label or "-")
        if p then L[#L + 1] = "      combat: " .. counts(p.stats.c) end
        if p and p.stats.lastErr then L[#L + 1] = "      error: " .. p.stats.lastErr end
    end

    local function section(title, group)
        L[#L + 1] = ("-"):rep(60)
        L[#L + 1] = title
        local rows = {}
        for _, p in ipairs(probes) do if p.group == group then rows[#rows + 1] = p end end
        table.sort(rows, function(a, b)
            local va, vb = CondTest.Verdict(a.stats), CondTest.Verdict(b.stats)
            if RANK[va] ~= RANK[vb] then return RANK[va] < RANK[vb] end
            return a.label < b.label
        end)
        if #rows == 0 then L[#L + 1] = " (none)" end
        for _, p in ipairs(rows) do
            L[#L + 1] = (" [%s] %s  (%s)"):format(CondTest.Verdict(p.stats), p.label, tostring(p.type))
            L[#L + 1] = "      combat: " .. counts(p.stats.c) .. "   ooc: " .. counts(p.stats.o)
            if p.stats.lastErr then L[#L + 1] = "      error: " .. p.stats.lastErr end
        end
    end
    section("CONDITIONS IN YOUR LISTS", "list")
    section("PRESETS", "preset")
    L[#L + 1] = ("-"):rep(60)
    L[#L + 1] = "Notes (add yours below):"
    return table.concat(L, "\n")
end

--------------------------------------------------------------------------------
-- Recording driver (runs whether or not the window is open)
--------------------------------------------------------------------------------
local driver, acc = nil, 0
function CondTest:SetRecording(on)
    local spec = activeSpec()
    local want = spec and (spec.key .. "/" .. tostring(variantOf(spec))) or "none"
    if on and (want ~= builtFor or #probes == 0) then self:Build(spec) end
    self.recording = on and true or false
    if on then self.startedAt = GetTime() end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, dt)
            if not CondTest.recording then return end
            acc = acc + dt
            if acc < CondTest.INTERVAL then return end
            local step = acc; acc = 0
            local inCombat = InCombatLockdown and InCombatLockdown() or false
            CondTest.elapsedRecorded = CondTest.elapsedRecorded + step
            if inCombat then CondTest.combatSeconds = CondTest.combatSeconds + step end
            local ok, S = pcall(PRIO.Engine.CurrentState, PRIO.Engine)
            if ok and S then CondTest:Sample(S, inCombat) end
        end)
    end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local win, scroll, content, statusFS, recBtnText
local lines = {}
local elapsedUI = 0

local VCOL = {
    error = "e0685a", unreadable = "e0685a", ["always false"] = "e0a03a",
    ["always true"] = "e0a03a", ["no data"] = "5a6a76", works = "0cd29f",
}
local function colored(v) return ("|cff%s%s|r"):format(VCOL[v] or "ffffff", v) end

local function line(i)
    local fs = lines[i]
    if not fs then
        local UI = PRIO.UI
        fs = UI.Font(content, 12, UI.C.text)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        lines[i] = fs
    end
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
    fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    fs:Show()
    return fs
end

function CondTest:Render()
    if not (win and win:IsShown()) then return end
    local n = 0
    local function add(text) n = n + 1; line(n):SetText(text) end
    local function head(text) add("|cff5a6a76" .. text:upper() .. "|r") end

    head("Editor condition types")
    for _, t in ipairs(self:TypeSummary()) do
        add(("%s  %s  |cff5a6a76%d/%d|r"):format(colored(t.best), typeText(t.type), t.working, t.variants))
    end
    local function section(title, group)
        add(" ")
        head(title)
        local any = false
        for _, p in ipairs(probes) do
            if p.group == group then
                any = true
                local c = p.stats.c
                add(("%s  %s  |cff5a6a76%d/%d/%d|r"):format(colored(CondTest.Verdict(p.stats)), p.label, c.pass, c.fail, c.open))
            end
        end
        if not any then add("|cff5a6a76(none)|r") end
    end
    section("In your lists  (pass/fail/can't tell, in combat)", "list")
    section("Presets", "preset")
    for i = n + 1, #lines do lines[i]:Hide() end
    content:SetHeight(math.max(1, n * 18))

    local rec = self.recording and "|cff0cd29fRECORDING|r" or "|cff5a6a76stopped|r"
    statusFS:SetText(("%s   %ds total, %ds in combat, %d probes"):format(rec,
        math.floor(self.elapsedRecorded or 0), math.floor(self.combatSeconds or 0), #probes))
    recBtnText:SetText(self.recording and "Stop" or "Record")
end

function CondTest:BuildWindow()
    if win then return end
    local UI, C = PRIO.UI, PRIO.UI.C
    win = UI.Window("PRIOCondTest", 460, 560, "PRIO  Condition Test",
        "Which conditions read in combat (experimental)")
    win:SetFrameStrata("DIALOG")
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(380, 300, 900, 1200) end

    statusFS = UI.Font(win, 12, C.muted)
    statusFS:SetPoint("TOPLEFT", 20, -70)

    local function btn(label, w, onClick)
        local b = CreateFrame("Button", nil, win)
        b:SetSize(w, 24)
        local bg = UI.Solid(b, "BACKGROUND", C.accent, 0.16); bg:SetAllPoints()
        local t = UI.Font(b, 12.5, C.accent); t:SetPoint("CENTER"); t:SetText(label)
        b:SetScript("OnEnter", function() bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.30) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16) end)
        b:SetScript("OnClick", onClick)
        return b, t
    end
    local rec, rt = btn("Record", 80, function()
        CondTest:SetRecording(not CondTest.recording); CondTest:Render()
    end)
    recBtnText = rt
    local reset = btn("Reset", 70, function()
        CondTest:Build(); CondTest:Reset(); CondTest:Render()
    end)
    local export = btn("Export", 80, function()
        UI.CopyBox("PRIO  Condition Test", "Ctrl+C to copy", CondTest:ExportText())
    end)
    rec:SetPoint("TOPLEFT", 20, -92)
    reset:SetPoint("LEFT", rec, "RIGHT", 8, 0)
    export:SetPoint("LEFT", reset, "RIGHT", 8, 0)

    local hint = UI.Font(win, 11, C.faint)
    hint:SetPoint("TOPLEFT", 20, -122); hint:SetPoint("RIGHT", win, "RIGHT", -20, 0)
    hint:SetJustifyH("LEFT"); hint:SetWordWrap(true)
    hint:SetText("Press Record, then fight a dummy or a pull for a minute or two using your whole rotation. 'works' = seen both true and false in combat. Verdicts only count in-combat samples.")

    scroll = CreateFrame("ScrollFrame", "PRIOCondTestScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -156); scroll:SetPoint("BOTTOMRIGHT", -34, 18)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 10)
    scroll:SetScrollChild(content)
    win:SetScript("OnSizeChanged", function() content:SetWidth(math.max(200, scroll:GetWidth() - 2)) end)

    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    local gt = grip:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing() end)

    win:SetScript("OnUpdate", function(_, dt)
        elapsedUI = elapsedUI + dt
        if elapsedUI >= 0.5 then elapsedUI = 0; CondTest:Render() end
    end)
end

function CondTest:Toggle()
    self:BuildWindow()
    if win:IsShown() then win:Hide(); return end
    if #probes == 0 then self:Build() end
    win:Show(); self:Render()
end
