-- Debug.lua --------------------------------------------------------------------
-- A live engine-state window: what PRIO reads vs. what it predicts, updated on a
-- throttle while open. Useful for telling whether a wrong recommendation is a bad
-- read (mode/enemies/maelstrom) or a drifted prediction (mote/sk/fs).
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
local UI  = PRIO.UI
local C   = UI.C
local Debug = {}
PRIO.Debug = Debug

local MAELSTROM = (Enum and Enum.PowerType and Enum.PowerType.Maelstrom) or 11

local win, rows, elapsed = nil, {}, 0

local function AddRow(parent, y, label, kind)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(258, 22); r:SetPoint("TOPLEFT", 20, -y)
    local l = UI.Font(r, 12, C.muted); l:SetPoint("LEFT", 0, 0); l:SetText(label)
    local v = UI.Font(r, 12.5, kind == "read" and C.accent or C.head)
    v:SetPoint("RIGHT", 0, 0); v:SetJustifyH("RIGHT")
    v:SetWidth(180)
    return v
end

function Debug:Build()
    if win then return end
    win = UI.Window("PRIODebug", 300, 526, "PRIO  Debug", "Live engine state")
    win:SetFrameStrata("DIALOG")

    local y = 74
    local function head(text)
        local h = UI.Font(win, 10.5, C.faint); h:SetPoint("TOPLEFT", 20, -y); h:SetText(text:upper())
        local line = UI.Solid(win, "ARTWORK", { 1, 1, 1 }, 0.06)
        line:SetPoint("LEFT", h, "RIGHT", 8, 0); line:SetPoint("RIGHT", win, "RIGHT", -20, 0)
        line:SetPoint("TOP", h, "CENTER", 0, 0); line:SetHeight(1)
        y = y + 22
    end
    local function row(label, kind) local v = AddRow(win, y, label, kind); y = y + 24; return v end

    head("Context")
    rows.spec    = row("Spec", "read")
    rows.combat  = row("In combat", "read")
    rows.tracked = row("Tracked spells", "read")
    head("Read live")
    rows.mode      = row("Mode", "read")
    rows.enemies   = row("Enemies", "read")
    rows.maelstrom = row("Maelstrom", "read")
    rows.eb        = row("Elemental Blast", "read")
    rows.eq        = row("Earthquake", "read")
    rows.fsRead    = row("Flame Shock (target)", "read")
    head("Predicted")
    rows.mote    = row("Master of the Elements")
    rows.sk      = row("Stormkeeper stacks")
    rows.lbCharges = row("Lava Burst charges")
    head("Output")
    rows.primary = row("Now", "read")
    rows.queue   = row("Next")

    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.1 then elapsed = 0; Debug:Update() end
    end)
end

local function yesno(v) return v and "|cff0cd29fyes|r" or "|cff5a6a76no|r" end

function Debug:Update()
    if not (win and win:IsShown()) then return end
    local specID = API.GetSpecID()
    local spec = specID and PRIO.specs and PRIO.specs[specID]

    rows.spec:SetText(spec and spec.label or ("|cffe0685aunsupported|r (" .. tostring(specID) .. ")"))
    rows.combat:SetText(yesno(InCombatLockdown()))

    -- Tracked-spell count (sanity check the Cooldown Viewer hookup)
    local tcount = 0
    if API.IsTracked and spec then
        for _, id in pairs(spec.spells) do if API.IsTracked(id) then tcount = tcount + 1 end end
    end
    rows.tracked:SetText(tostring(tcount))

    local method = (PRIO.db and PRIO.db.enemyDetect) or "engaged"
    rows.enemies:SetText(("%d  |cff5a6a76(%s)|r"):format(API.EnemyCount(), method))

    -- Resource: real value when readable, else the prediction the gate uses.
    local realMs = API.Power(spec and spec.resource or MAELSTROM)
    local pred = PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.maelstrom
    local effMs = realMs or pred
    if realMs ~= nil then
        rows.maelstrom:SetText(("%d  |cff5a6a76(read)|r"):format(realMs))
    elseif pred ~= nil then
        rows.maelstrom:SetText(("|cffe0a03a~%d|r  |cff5a6a76(predicted, secret)|r"):format(math.floor(pred)))
    else
        rows.maelstrom:SetText("|cffe0a03asecret/nil|r")
    end

    -- Spender readout: cost vs the effective Maelstrom the gate uses.
    local function spenderText(id)
        if not id then return "-" end
        local cost = API.PowerCostAmount(id)
        local costStr = cost and ("|cff5a6a76cost " .. cost .. "|r") or ""
        local afford
        if effMs ~= nil and cost then afford = effMs >= cost end
        local state = (afford == true and "|cff0cd29fafford|r")
            or (afford == false and "|cffe0685alow|r")
            or "|cffe0a03a?|r"
        return state .. "  " .. costStr
    end
    rows.eb:SetText(spenderText(spec and spec.spells.ElementalBlast))
    rows.eq:SetText(spenderText(spec and spec.spells.Earthquake))

    -- Real Flame Shock read from the Cooldown Viewer
    local fsID = spec and spec.spells.FlameShock
    local fsA = fsID and API.IsAuraActive(fsID)
    rows.fsRead:SetText(fsA == true and "|cff0cd29factive|r"
        or fsA == false and "|cffe0685agone|r"
        or "|cffe0a03auntracked|r")

    -- Predicted state straight from the engine model
    local P = PRIO.Engine and PRIO.Engine.P or {}
    rows.mote:SetText(yesno(P.mote))
    rows.sk:SetText(tostring(P.skStacks or 0))
    local lb = P.charges and P.charges.LavaBurst
    rows.lbCharges:SetText(lb and (tostring(lb.cur) .. " / 3") or "-")

    local result = PRIO.Engine and PRIO.Engine:Evaluate()
    if result then
        rows.mode:SetText(result.debug.mode)
        rows.primary:SetText("|cffffffff" .. (result.primary and result.primary.name or "-") .. "|r")
        local q = {}
        for _, e in ipairs(result.queue or {}) do q[#q + 1] = e.name end
        rows.queue:SetText(#q > 0 and table.concat(q, ", ") or "-")
    else
        rows.mode:SetText(PRIO.db and PRIO.db.mode or "-")
        rows.primary:SetText("-")
        rows.queue:SetText("-")
    end
end

function Debug:Toggle()
    self:Build()
    if win:IsShown() then win:Hide()
    else win:Show(); self:Update() end
end
