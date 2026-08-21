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

    head("Context")
    row("spec", "Spec", "read")
    row("combat", "In combat", "read")
    row("tracked", "Tracked spells", "read")

    head("Read live")
    row("mode", "Mode", "read")
    row("enemies", "Enemies", "read")
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
        row("gen", "Generators", "read")
        row("spend", "Spenders", "read")
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
            if d.kind == "buff" then
                set(id, auraText(d.spell))
            elseif d.kind == "cd" then
                set(id, cdText(d.spell))
            elseif d.kind == "charges" then
                local cc = P.charges and P.charges[d.key]
                local maxC = spec.chargeTrack and spec.chargeTrack[d.key] and spec.chargeTrack[d.key].max
                set(id, cc and (tostring(cc.cur) .. " / " .. (maxC or "?")) or "-")
            elseif d.kind == "mote" then
                if PRIO.Engine and PRIO.Engine.hasMote == false then
                    set(id, "|cff5a6a76n/a (no talent)|r")
                else
                    set(id, yesno(P.mote))
                end
            elseif d.kind == "hasMote" then
                set(id, PRIO.Engine and PRIO.Engine.hasMote
                    and "|cff0cd29fdetected|r" or "|cffe0685anot detected|r")
            elseif d.kind == "skStacks" then
                set(id, tostring(P.skStacks or 0))
            else
                set(id, "-")
            end
        end
    end

    if spec and spec.economy then
        set("gen", "|cff9fb0be" .. table.concat(spec.economy.gen or {}, ", ") .. "|r")
        set("spend", "|cff9fb0be" .. table.concat(spec.economy.spend or {}, ", ") .. "|r")
    end

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
