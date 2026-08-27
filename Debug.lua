-- Debug.lua --------------------------------------------------------------------
-- A live, spec-aware engine-state window: what PRIO reads vs. what it predicts.
-- The row layout is rebuilt from the active spec's `debug` / `economy` metadata,
-- so each spec shows its own charges, stacking buffs, and Focus/Rage/Maelstrom
-- economy instead of a hardcoded Elemental readout.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local UI  = PRIO.UI
local C   = UI.C

local Debug = {}
PRIO.Debug = Debug

local win, body, elapsed = nil, nil, 0
local rows = {}          -- dynamic value fontstrings keyed by an id
local pool = {}          -- reusable row/heading frames
local builtSpecID = nil  -- which spec the current layout was built for
local layoutH = 0

local function yesno(v) return v and "|cff0cd29fyes|r" or "|cff5a6a76no|r" end

--------------------------------------------------------------------------------
-- Layout (rebuilt on spec change)
--------------------------------------------------------------------------------
local function acquire(kind, parent)
    for _, f in ipairs(pool) do
        if not f._used and f._kind == kind then f._used = true; f:Show(); return f end
    end
    local f
    if kind == "head" then
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(258, 18)
        f.text = UI.Font(f, 10.5, C.faint)
        f.text:SetPoint("TOPLEFT", 0, 0)
        f.line = UI.Solid(f, "ARTWORK", { 1, 1, 1 }, 0.06)
        f.line:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
        f.line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.line:SetPoint("TOP", f.text, "CENTER", 0, 0); f.line:SetHeight(1)
    elseif kind == "wide" then
        -- Full-width label + wrapping value beneath it, for long list text (the
        -- Economy generators/spenders) that would otherwise wrap into the next row.
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(258, 40)
        f.label = UI.Font(f, 12, C.muted); f.label:SetPoint("TOPLEFT", 0, 0)
        f.value = UI.Font(f, 11.5, C.faint)
        f.value:SetPoint("TOPLEFT", 0, -16); f.value:SetWidth(250)
        f.value:SetJustifyH("LEFT"); f.value:SetWordWrap(true)
    else -- "row"
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(258, 22)
        f.label = UI.Font(f, 12, C.muted); f.label:SetPoint("LEFT", 0, 0)
        f.value = UI.Font(f, 12.5, C.head)
        f.value:SetPoint("RIGHT", 0, 0); f.value:SetJustifyH("RIGHT"); f.value:SetWidth(180)
    end
    f._kind = kind
    f._used = true
    pool[#pool + 1] = f
    return f
end

local function releaseAll()
    for _, f in ipairs(pool) do f._used = false; f:Hide() end
    wipe(rows)
end

function Debug:Rebuild(spec)
    releaseAll()
    local y = 74

    local function head(text)
        local h = acquire("head", body)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 20, -y)
        h.text:SetText(text:upper())
        y = y + 22
    end
    local function row(id, label, kind)
        local r = acquire("row", body)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -y)
        r.label:SetText(label)
        local col = (kind == "read") and C.accent or C.head
        r.value:SetTextColor(col[1], col[2], col[3], col[4] or 1)
        rows[id] = r.value
        y = y + 24
    end
    -- Full-width wrapping block (static text set at build time), self-sizing so it
    -- never overlaps the following row.
    local function wide(id, label, text)
        local r = acquire("wide", body)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -y)
        r.label:SetText(label)
        r.value:SetText(text or "")
        local h = 18 + math.max(14, r.value:GetStringHeight() + 4)
        r:SetHeight(h)
        y = y + h + 6
    end

    head("Context")
    row("spec", "Spec", "read")
    row("combat", "In combat", "read")
    row("tracked", "Tracked spells", "read")

    head("Read live")
    row("mode", "Mode", "read")
    row("enemies", "Enemies", "read")
    row("plates", "Nameplates", "read")
    row("resource", (spec and spec.resourceLabel) or "Resource", "read")
    row("casting", "Casting", "read")

    if spec and spec.debug and #spec.debug > 0 then
        head("Predicted / tracked")
        for i, d in ipairs(spec.debug) do
            row("d" .. i, d.label or "?", d.kind == "buff" and "read" or "pred")
        end
    end

    if spec and spec.economy then
        head("Economy")
        wide("gen", "Generators", "|cff9fb0be" .. table.concat(spec.economy.gen or {}, ", ") .. "|r")
        wide("spend", "Spenders", "|cff9fb0be" .. table.concat(spec.economy.spend or {}, ", ") .. "|r")
    end

    head("Output")
    row("primary", "Now", "read")
    row("queue", "Next")

    layoutH = y + 20
    builtSpecID = spec and spec.specID or "none"
    if win then win:SetHeight(layoutH) end
end

--------------------------------------------------------------------------------
-- Build the frame once; body holds the rebuildable rows.
--------------------------------------------------------------------------------
function Debug:Build()
    if win then return end
    win = UI.Window("PRIODebug", 300, 560, "PRIO  Debug", "Live engine state")
    win:SetFrameStrata("DIALOG")
    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 0, 0); body:SetPoint("BOTTOMRIGHT", 0, 0)

    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.1 then elapsed = 0; Debug:Update() end
    end)
end

--------------------------------------------------------------------------------
-- Live update
--------------------------------------------------------------------------------
local function auraText(spell)
    local a = API.IsAuraActive(spell)
    if a == true then return "|cff0cd29factive|r"
    elseif a == false then return "|cffe0685agone|r"
    else return "|cffe0a03auntracked|r" end
end

local function cdText(spell)
    local r = API.IsReady(spell)
    if r == true then return "|cff0cd29fready|r"
    elseif r == false then return "|cffe0685aon CD|r"
    else return "|cffe0a03a?|r" end
end

function Debug:Update()
    if not (win and win:IsShown()) then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]

    -- Rebuild layout if the spec changed since the rows were laid out.
    if (spec and spec.specID or "none") ~= builtSpecID then
        self:Rebuild(spec)
    end

    local function set(id, text) if rows[id] then rows[id]:SetText(text) end end

    set("spec", spec and (spec.label .. " " .. (spec.className or ""))
        or ("|cffe0685aunsupported|r (" .. tostring(specID) .. ")"))
    set("combat", yesno(InCombatLockdown()))

    local tcount = 0
    if API.IsTracked and spec then
        for _, id in pairs(spec.spells) do if API.IsTracked(id) then tcount = tcount + 1 end end
    end
    set("tracked", tostring(tcount))

    local method = (PRIO.db and PRIO.db.enemyDetect) or "engaged"
    set("enemies", ("%d  |cff5a6a76(%s)|r"):format(API.EnemyCount(), method))

    -- Nameplate status: EnemyCount can't see targets without enemy nameplates.
    if API.NameplatesEnabled then
        if API.NameplatesEnabled() then
            set("plates", ("|cff0cd29fon|r  |cff5a6a76%d shown|r"):format(API.NameplateCount()))
        else
            set("plates", "|cffe0685aOFF -- enable enemy nameplates|r")
        end
    end

    -- Resource: real value when readable, else the prediction the gate uses.
    local realMs = spec and spec.resource and API.Power(spec.resource) or nil
    local pred = PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.maelstrom
    if realMs ~= nil then
        set("resource", ("%d  |cff5a6a76(read)|r"):format(realMs))
    elseif pred ~= nil then
        set("resource", ("|cffe0a03a~%d|r  |cff5a6a76(predicted, secret)|r"):format(math.floor(pred)))
    else
        set("resource", "|cffe0a03asecret/nil|r")
    end

    -- Live cast detection (drives the advance-while-casting behavior).
    local ck, csid, cname = nil, nil, nil
    if PRIO.Engine and PRIO.Engine.InFlightCast then ck, csid, cname = PRIO.Engine:InFlightCast() end
    if csid then
        set("casting", (cname or "?") .. (ck
            and (" |cff0cd29f\226\134\146 " .. ck .. "|r")
            or  " |cffe0685a(unmapped)|r"))
    else
        set("casting", "|cff5a6a76none|r")
    end

    -- Spec-defined predicted / tracked rows.
    local P = PRIO.Engine and PRIO.Engine.P or {}
    if spec and spec.debug then
        for i, d in ipairs(spec.debug) do
            local id = "d" .. i
            -- Guard each row so a probe that trips a secret value can't error out of
            -- the whole Update (which would blank the rest and flood the error log).
            local ok, err = pcall(function()
            if d.kind == "buff" then
                set(id, auraText(d.spell))
            elseif d.kind == "cd" then
                set(id, cdText(d.spell))
            elseif d.kind == "charges" then
                local cc = P.charges and P.charges[d.key]
                local maxC = spec.chargeTrack and spec.chargeTrack[d.key] and spec.chargeTrack[d.key].max
                set(id, cc and (tostring(cc.cur) .. " / " .. (maxC or "?")) or "-")
            elseif d.kind == "chargeClean" then
                -- The effective count the Charges condition uses: clean read (maxCharges
                -- + isActive + usable) where possible, else clamped prediction. Shows the
                -- count, its source, and the time to the next charge.
                local maxC, cur, belowMax = API.ChargeState and API.ChargeState(d.spell)
                if not maxC then
                    set(id, "|cff5a6a76not a charge spell|r")
                else
                    local rem = API.ChargeRechargeRemaining and API.ChargeRechargeRemaining(d.spell)
                    local tail = (rem and rem > 0) and ("  |cff5a6a76next %.0fs|r"):format(rem) or ""
                    local eff = PRIO.Engine and PRIO.Engine.EffectiveCharges
                        and PRIO.Engine:EffectiveCharges(d.spell)
                    local src = (cur ~= nil) and ((belowMax == false) and "at max" or "usable")
                        or "predicted"
                    if eff ~= nil then
                        set(id, ("|cff0cd29f%d|r / %d  |cff5a6a76(%s)|r%s"):format(eff, maxC, src, tail))
                    else
                        set(id, ("|cffe0a03a? / %d|r  |cff5a6a76(recharging)|r%s"):format(maxC, tail))
                    end
                end
            elseif d.kind == "cdRemain" then
                -- Predicted cooldown remaining (Invoke Xuen): seeded on cast, counted down.
                local r = PRIO.Engine and PRIO.Engine.CooldownRemaining
                    and PRIO.Engine:CooldownRemaining(d.spell)
                if r == nil then
                    set(id, "|cff5a6a76?|r")
                elseif r <= 0 then
                    set(id, "|cff0cd29fready|r")
                else
                    set(id, ("|cffe0685a%.0fs|r"):format(r))
                end
            elseif d.kind == "auraRemain" then
                -- Predicted buff time-left (Zenith): clean expirationTime out of combat,
                -- cast-seeded timer in combat. What a "Buff time left <=" condition uses.
                local r = PRIO.Engine and PRIO.Engine.AuraRemaining
                    and PRIO.Engine:AuraRemaining(d.spell)
                if r and r > 0 then
                    set(id, ("|cff0cd29f%.1fs|r  |cff5a6a76left|r"):format(r))
                else
                    set(id, "|cff5a6a76not up|r")
                end
            elseif d.kind == "energyFloor" then
                -- Dead-reckoned Energy: fixed regen integrated to the readable max, anchored
                -- to the usable-flag checkpoint floor (synced to the real value if readable).
                local E = PRIO.Engine
                local est = E and E.EnergyEstimate and E:EnergyEstimate()
                local max = E and E.P and E.P.energyMax
                local floor = E and E.EnergyFloor and E:EnergyFloor()
                local nc = spec.energyModel and spec.energyModel.nearCapAt
                local near = (nc and est and est >= nc) and "  |cffe0a03aNEAR CAP|r" or ""
                if est and max then
                    set(id, ("|cff0cd29f%d|r / %d  |cff9fb0be%d%%|r%s")
                        :format(est, max, (est / max) * 100, near))
                else
                    set(id, "|cff5a6a76unknown|r")
                end
            elseif d.kind == "usableProbe" then
                -- Diagnostic: is "insufficient power" readable? (Energy is secret; this
                -- tells us whether the usability flag still exposes castability.)
                set(id, "|cff9fb0be" .. tostring(API.UsableDebug and API.UsableDebug(d.spell) or "?") .. "|r")
            elseif d.kind == "mote" then
                if PRIO.Engine and PRIO.Engine.hasMote == false then
                    set(id, "|cff5a6a76n/a (no talent)|r")
                else
                    set(id, yesno(P.mote))
                end
            elseif d.kind == "stacks" then
                local s = API.AuraStackCount and API.AuraStackCount(d.spell)
                if s and s > 0 then
                    set(id, ("|cff0cd29f%d stack%s|r  |cff5a6a76(read)|r"):format(s, s > 1 and "s" or ""))
                elseif s == 0 then
                    set(id, "|cff5a6a76none|r")
                else
                    set(id, "|cffe0a03auntracked|r")
                end
            elseif d.kind == "remaining" then
                local r = API.AuraRemaining and API.AuraRemaining(d.spell)
                if r then
                    set(id, ("|cff0cd29f%.1fs|r  |cff5a6a76(read!)|r"):format(r))
                else
                    local act = API.IsAuraActive(d.spell)
                    set(id, act == true and "|cffe0a03aup (time secret)|r"
                        or act == false and "|cff5a6a76gone|r" or "|cffe0a03a?|r")
                end
            elseif d.kind == "pandemic" then
                -- Secret-safe: reads Blizzard's PandemicIcon (needs the spell's
                -- "Pandemic Time" alert enabled in the Cooldown Manager).
                local ip = API.InPandemic and API.InPandemic(d.spell)
                set(id, ip == true and "|cff0cd29fREFRESH (in pandemic)|r"
                    or ip == false and "|cff5a6a76hold|r"
                    or "|cffe0a03auntracked|r")
            elseif d.kind == "hasMote" then
                set(id, PRIO.Engine and PRIO.Engine.hasMote
                    and "|cff0cd29fdetected|r" or "|cffe0685anot detected|r")
            elseif d.kind == "skStacks" then
                set(id, tostring(P.skStacks or 0))
            else
                set(id, "-")
            end
            end)   -- close pcall
            if not ok then set(id, "|cffe0685aerr|r") end
        end
    end

    -- Economy generators/spenders are static per-spec text, set once at Rebuild.

    local result = PRIO.Engine and PRIO.Engine:Evaluate()
    if result then
        set("mode", result.debug.mode)
        set("primary", "|cffffffff" .. (result.primary and result.primary.name or "-") .. "|r")
        local q = {}
        for _, e in ipairs(result.queue or {}) do q[#q + 1] = e.name end
        set("queue", #q > 0 and table.concat(q, ", ") or "-")
    else
        set("mode", PRIO.db and PRIO.db.mode or "-")
        set("primary", "-")
        set("queue", "-")
    end
end

function Debug:Toggle()
    self:Build()
    if win:IsShown() then win:Hide()
    else win:Show(); self:Update() end
end

--------------------------------------------------------------------------------
-- RotationDebug: a SECOND, standalone window focused on the raw signals a rotation
-- gate reads -- per-ability cooldown/usable state and per-buff active/stacks --
-- driven by the active spec's `rotationDebug` metadata. Its own frame/pool so it
-- never touches the main Debug window's layout.
--------------------------------------------------------------------------------
local RotationDebug = {}
PRIO.RotationDebug = RotationDebug

local rwin, rbody, relapsed = nil, nil, 0
local rrows, rpool = {}, {}
local rBuiltSpecID = nil
local rLayoutH = 0

-- "ColossusSmash" -> "Colossus Smash" for row labels.
local function spaceCamel(s)
    return (s:gsub("(%l)(%u)", "%1 %2"))
end

local function racquire(kind)
    for _, f in ipairs(rpool) do
        if not f._used and f._kind == kind then f._used = true; f:Show(); return f end
    end
    local f
    if kind == "head" then
        f = CreateFrame("Frame", nil, rbody)
        f:SetSize(258, 18)
        f.text = UI.Font(f, 10.5, C.faint)
        f.text:SetPoint("TOPLEFT", 0, 0)
        f.line = UI.Solid(f, "ARTWORK", { 1, 1, 1 }, 0.06)
        f.line:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
        f.line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.line:SetPoint("TOP", f.text, "CENTER", 0, 0); f.line:SetHeight(1)
    else -- "row"
        f = CreateFrame("Frame", nil, rbody)
        f:SetSize(258, 22)
        f.label = UI.Font(f, 12, C.muted); f.label:SetPoint("LEFT", 0, 0)
        f.value = UI.Font(f, 12.5, C.head)
        f.value:SetPoint("RIGHT", 0, 0); f.value:SetJustifyH("RIGHT"); f.value:SetWidth(180)
    end
    f._kind = kind; f._used = true
    rpool[#rpool + 1] = f
    return f
end

local function rreleaseAll()
    for _, f in ipairs(rpool) do f._used = false; f:Hide() end
    wipe(rrows)
end

function RotationDebug:Rebuild(spec)
    rreleaseAll()
    local y = 74
    local function head(text)
        local h = racquire("head")
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 20, -y)
        h.text:SetText(text:upper())
        y = y + 22
    end
    local function row(id, label)
        local r = racquire("row")
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 20, -y)
        r.label:SetText(label)
        rrows[id] = r.value
        y = y + 24
    end

    local rd = spec and spec.rotationDebug
    if not rd then
        head("Rotation debug")
        row("none", "(no rotation debug for this spec)")
    else
        head("Abilities  (cooldown / usable)")
        for i, key in ipairs(rd.abilities or {}) do
            row("a" .. i, spaceCamel(key))
        end
        head("Buffs  (active / stacks)")
        for i, b in ipairs(rd.buffs or {}) do
            row("b" .. i, b.label or "?")
        end
        if rd.predStacks and #rd.predStacks > 0 then
            head("Predicted stacks  (cast counter)")
            for i, p in ipairs(rd.predStacks) do
                row("p" .. i, p.label or "?")
            end
        end
        if rd.glows and #rd.glows > 0 then
            head("Proc glows  (overlay)")
            for i, g in ipairs(rd.glows) do
                row("g" .. i, g.label or "?")
            end
        end
        if rd.rangeProbes and #rd.rangeProbes > 0 then
            head("Execute range  (probe)")
            for i, r in ipairs(rd.rangeProbes) do
                row("r" .. i, r.label or "?")
            end
        end
    end

    rLayoutH = y + 20
    rBuiltSpecID = spec and spec.specID or "none"
    if rwin then rwin:SetHeight(rLayoutH) end
end

function RotationDebug:Build()
    if rwin then return end
    rwin = UI.Window("PRIORotationDebug", 300, 460, "PRIO  Rotation Debug",
        "Ability cooldown/usable + buff/stacks")
    rwin:SetFrameStrata("DIALOG")
    rbody = CreateFrame("Frame", nil, rwin)
    rbody:SetPoint("TOPLEFT", 0, 0); rbody:SetPoint("BOTTOMRIGHT", 0, 0)
    rwin:SetScript("OnUpdate", function(_, dt)
        relapsed = relapsed + dt
        if relapsed >= 0.1 then relapsed = 0; RotationDebug:Update() end
    end)
end

-- Cooldown-ready + usable, side by side. IsReady is a clean bool; UsableClean is
-- true/false/nil (never guesses), so a secret usable flag reads honestly.
local function abilityText(sid)
    local ready = API.IsReady(sid)
    local cd = (ready == true) and "|cff0cd29fready|r"
        or (ready == false) and "|cffe0685aon CD|r" or "|cffe0a03a?|r"
    local u = API.UsableClean and API.UsableClean(sid)
    local us = (u == true) and "|cff0cd29fusable|r"
        or (u == false) and "|cffe0685aunusable|r" or "|cffe0a03asecret|r"
    return cd .. "  |cff5a6a76/|r  " .. us
end

-- Shows active + stack count + WHERE the count came from, so we can see live whether
-- the exact .applications value reads clean or is a secret value we had to fall back on.
local srcColor = {
    ["appl"]        = "5a6a76",   -- clean exact read (grey, all good)
    ["cdm"]         = "5a6a76",   -- Cooldown Viewer rendered number
    ["appl-secret"] = "e0a03a",   -- .applications is protected -> need another source
    ["assumed"]     = "e0a03a",   -- active but no readable count -> defaulted to 1
}
local function buffText(sid)
    local a = API.IsAuraActive(sid)
    if a == nil then return "|cffe0a03auntracked|r" end
    if a ~= true then return "|cffe0685agone|r" end
    -- NOTE: `X and f()` truncates multiple returns to one, so guard with an if to keep
    -- both n and src (this bug once made the source tag silently never render).
    local n, src
    if API.AuraStackSource then n, src = API.AuraStackSource(sid) end
    local stack = (n and n > 0) and (" |cff9fb0be\195\151" .. n .. "|r") or ""
    local tag = src and ("  |cff" .. (srcColor[src] or "5a6a76") .. src .. "|r") or ""
    return "|cff0cd29factive|r" .. stack .. tag
end

function RotationDebug:Update()
    if not (rwin and rwin:IsShown()) then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]
    if (spec and spec.specID or "none") ~= rBuiltSpecID then
        self:Rebuild(spec)
    end
    local rd = spec and spec.rotationDebug
    if not rd then return end

    local function set(id, text) if rrows[id] then rrows[id]:SetText(text) end end
    for i, key in ipairs(rd.abilities or {}) do
        local sid = spec.spells and spec.spells[key]
        local ok, res = pcall(function() return sid and abilityText(sid) or "|cffe0685ano id|r" end)
        set("a" .. i, ok and res or "|cffe0685aerr|r")
    end
    for i, b in ipairs(rd.buffs or {}) do
        local ok, res = pcall(function() return buffText(b.spell) end)
        set("b" .. i, ok and res or "|cffe0685aerr|r")
    end
    for i, p in ipairs(rd.predStacks or {}) do
        local n = (PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.stacks
            and PRIO.Engine.P.stacks[p.spell]) or 0
        set("p" .. i, ("|cff0cd29f%d|r  |cff5a6a76(predicted)|r"):format(n))
    end
    for i, g in ipairs(rd.glows or {}) do
        local ok, res = pcall(function()
            local v = API.SpellGlowing and API.SpellGlowing(g.spell)
            if v == true then return "|cff0cd29fGLOWING|r" end
            if v == false then return "|cff5a6a76off|r" end
            return "|cffe0a03asecret/na|r"
        end)
        set("g" .. i, ok and res or "|cffe0685aerr|r")
    end
    for i, r in ipairs(rd.rangeProbes or {}) do
        local ok, res = pcall(function()
            if r.kind == "health" then
                local p = API.TargetHealthPct and API.TargetHealthPct()
                if p == nil then return "|cffe0a03asecret / no target|r" end
                local col = (p < 35) and "0cd29f" or "9fb0be"
                return ("|cff%s%.0f%%|r%s"):format(col, p, p < 35 and "  |cff0cd29f(execute)|r" or "")
            elseif r.kind == "usableClean" then
                local u = API.UsableClean and API.UsableClean(r.spell)
                if u == true then return "|cff0cd29fusable|r" end
                if u == false then return "|cffe0685aunusable|r" end
                return "|cffe0a03asecret|r"
            elseif r.kind == "execRange" then
                local on = PRIO.Engine and PRIO.Engine.InExecuteRange and PRIO.Engine:InExecuteRange()
                return on and "|cff0cd29fYES (latched)|r" or "|cff5a6a76no|r"
            elseif r.kind == "directAura" then
                -- Direct GetPlayerAuraBySpellID read: the ONLY path for auras the CDM
                -- doesn't track (e.g. the six Roll the Bones buffs). Tests whether they
                -- read clean in combat (index enumeration is blocked there).
                local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                if not fn then return "|cffe0a03ana|r" end
                local ok2, d = pcall(fn, r.spell)
                if not ok2 then return "|cffe0685aerr|r" end
                if d == nil then return "|cff5a6a76absent|r" end
                if API.IsSecret(d) then return "|cffe0685aPRESENT/secret|r" end
                local a = d.applications
                local st = (type(a) == "number" and not API.IsSecret(a) and a > 0) and (" \195\151" .. a) or ""
                return "|cff0cd29freadable|r|cff9fb0be" .. st .. "|r"
            elseif r.kind == "resource" then
                -- Discrete class power (e.g. Combo Points) -- readable clean in combat.
                local pt = r.power or (spec and spec.resource)
                local v = pt and API.Power(pt)
                local mx = pt and API.PowerMax(pt)
                if v == nil then return "|cffe0685aSECRET / na|r" end
                return ("|cff0cd29f%s|r|cff5a6a76 / %s|r"):format(tostring(v), tostring(mx or "?"))
            elseif r.kind == "predFlag" then
                -- Inferred boolean (e.g. Outlaw rtbStage2): true / false / unknown.
                local pf = PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.predFlags
                local v = pf and pf[r.key]
                if v == true then return "|cff0cd29ftrue|r" end
                if v == false then return "|cffe0685afalse (reroll)|r" end
                return "|cff9fb0beunknown (assume good)|r"
            elseif r.kind == "boolStack" then
                -- A predicted counter shown as a boolean up/down (e.g. Opportunity).
                local st = PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.stacks
                local v = (st and st[r.spell]) or 0
                return v > 0 and "|cff0cd29fup|r" or "|cff5a6a76down|r"
            elseif r.kind == "predCount" then
                -- A predicted numeric counter on Engine.P (e.g. Outlaw superCharge).
                local P = PRIO.Engine and PRIO.Engine.P
                local v = (P and r.field and P[r.field]) or 0
                return ("|cff0cd29f%s|r"):format(tostring(v))
            end
            return "-"
        end)
        set("r" .. i, ok and res or "|cffe0685aerr|r")
    end
end

function RotationDebug:Toggle()
    self:Build()
    if rwin:IsShown() then rwin:Hide()
    else rwin:Show(); self:Update() end
end
