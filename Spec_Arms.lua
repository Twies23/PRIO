-- Spec_Arms.lua ----------------------------------------------------------------
-- Arms Warrior (spec 71), patch 12.1 (Midnight). All-inclusive lists covering
-- both hero trees -- Colossus (Demolish / Colossal Might) and Slayer (Sudden
-- Death / Imminent Demise / Bladestorm-weaving). Untalented abilities are filtered
-- by IsKnown; talent-only lines are gated with talentYes/No or go inert when their
-- buff never appears. Spell IDs are best-guess; verify with /prio spells.
--
-- Resource note: Rage is a filling bar -> secret in combat (like Focus/Maelstrom),
-- so it's predicted and spenders never hard-gate in combat (fail open).
-- Health is secret too, so execute-range usage can't be detected -- Execute is
-- driven by the Sudden Death proc here, which is the readable trigger.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1

-- Readable buff/debuff IDs (verified via /prio tracked in 12.1).
local ID_SUDDENDEATH  = 29725    -- Sudden Death (free/instant Execute) -- tracked buff
local ID_COLLATERAL   = 334779   -- Collateral Damage (stacks to 3; Sweeping Strikes)
local ID_EXECPREC     = 386634   -- Executioner's Precision (stacks)
local ID_IMMINENT     = 445606   -- Imminent Demise (stacks)
local ID_COLOSSUS_DBF = 167105   -- Colossus Smash (tracked bar / debuff)
local ID_SWEEPING     = 260708   -- Sweeping Strikes (self)
local ID_REND         = 772      -- Rend debuff (on target)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function talent(id)   return { type = "talentYes",   spell = id } end
local function refreshable(id) return { type = "refreshable", spell = id } end
local function cdReady(id)  return { type = "cdReady",     spell = id } end
local function stacksMin(id, n) return { type = "stacksMin", spell = id, v = n } end
local function stacksMax(id, n) return { type = "stacksMax", spell = id, v = n } end
local function chargesMin(id, n) return { type = "chargesMin", spell = id, v = n } end

local spec = {
    key      = "WARRIOR_ARMS",
    label    = "Arms",
    className = "Warrior",
    specID   = 71,
    resource = RAGE,
    resourceLabel = "Rage",
    cleaveAt = 2,
    aoeAt    = 3,
    usesPandemic = true,             -- Rend refreshes in its pandemic window

    -- Relevant buffs/debuffs (selectable in the condition editor regardless of build).
    auras = {
        Rend          = ID_REND,
        SuddenDeath   = ID_SUDDENDEATH,
        CollateralDamage = ID_COLLATERAL,
        ExecutionersPrecision = ID_EXECPREC,
        ImminentDemise = ID_IMMINENT,
        ColossusSmash = ID_COLOSSUS_DBF,
        SweepingStrikes = ID_SWEEPING,
    },

    -- First-time setup checklist (Setup.lua adds the global nameplate check).
    setup = {
        { kind = "trackedAura", label = "Rend tracked", spell = ID_REND,
          hint = "Track Rend in your Cooldown Manager so PRIO knows when to refresh it." },
        { kind = "trackedAura", label = "Sudden Death tracked", spell = ID_SUDDENDEATH,
          hint = "Track Sudden Death (Buff Icons) so PRIO can read its stacks for Execute timing." },
        { kind = "trackedAura", label = "Collateral Damage tracked", spell = ID_COLLATERAL,
          hint = "Track Collateral Damage so AoE Cleave fires at 3 stacks." },
        { kind = "trackedAura", label = "Imminent Demise tracked", spell = ID_IMMINENT,
          hint = "Track Imminent Demise so the pre-Bladestorm Execute reads its stacks." },
        { kind = "trackedAura", label = "Executioner's Precision tracked", spell = ID_EXECPREC,
          hint = "Track Executioner's Precision for execute-window Mortal Strike timing." },
        { kind = "pandemic", label = "Rend pandemic alert", spell = ID_REND,
          hint = "Optional: enable the Pandemic Time alert on Rend (Edit Mode -> Cooldown Manager) for no-clip refresh timing." },
    },

    spells = {
        MortalStrike   = 12294,
        Overpower      = 7384,
        Execute        = 163201,
        Slam           = 1464,
        Cleave         = 845,
        ThunderClap    = 6343,
        Bladestorm     = 227847,
        ColossusSmash  = 167105,
        Warbreaker     = 262161,   -- talent, replaces Colossus Smash
        Rend           = 772,
        Skullsplitter  = 260643,
        ChampionsSpear = 376079,   -- talent
        Avatar         = 107574,
        SweepingStrikes = 260708,
        Ravager        = 228920,   -- talent
        Demolish       = 436358,   -- Colossus
        ThunderousRoar = 384318,
        HeroicStrike   = 1269383,  -- Slayer proc (Slam-swap)
    },

    openerReady = { "Avatar", "ColossusSmash", "Warbreaker" },
    opener = { "Rend", "Avatar", "ColossusSmash", "MortalStrike", "Overpower",
               "Execute", "Slam" },

    precombat = {},   -- Rend is a target debuff (opener leads with it), not a self-buff

    pickable = {
        "MortalStrike", "Overpower", "Execute", "Slam", "Cleave", "HeroicStrike", "ThunderClap",
        "Bladestorm", "ColossusSmash", "Warbreaker", "Rend", "Skullsplitter",
        "ChampionsSpear", "Avatar", "SweepingStrikes", "Ravager", "Demolish",
        "ThunderousRoar",
    },

    -- Overpower runs on 2 charges.
    chargeTrack = {
        Overpower = { max = 2, recharge = 12 },
    },

    fillers = { [1464] = true, [845] = true },   -- Slam (ST) / Cleave (AoE)

    flash = {
        Execute = { type = "buffActive", spell = ID_SUDDENDEATH },
    },

    -- Colossus Smash / Warbreaker apply the Colossus Smash debuff (look-ahead).
    spellEffects = {
        ColossusSmash = { grant = { ID_COLOSSUS_DBF } },
        Warbreaker    = { grant = { ID_COLOSSUS_DBF } },
    },

    maelstromMax = 100,   -- Rage cap (generic "resource" fields)
    maelstromGen = {},    -- Rage is auto-attack driven; casts mostly spend it

    OnCast = function(P, key, now) end,

    priority = {
        -- Single target (Slayer list from Icy Veins; talent CDs fold in via IsKnown).
        -- Cleave applies/refreshes Rend in this build (no separate Rend cast).
        st = {
            { spell = "Cleave", cond = AND(refreshable(ID_REND), cdReady(ID_COLOSSUS_DBF)) }, -- refresh Rend before Colossus Smash
            { spell = "Avatar" },                                 -- on CD
            { spell = "ThunderousRoar" },                         -- talent CD
            { spell = "ChampionsSpear" },                         -- talent CD
            { spell = "ColossusSmash" },                          -- on CD (smart-swaps to Warbreaker if talented)
            { spell = "Ravager" },                                -- talent: with Colossus Smash
            { spell = "Demolish" },                               -- Colossus: during Colossus Smash
            { spell = "Execute", cond = stacksMin(ID_SUDDENDEATH, 2) }, -- 2 stacks Sudden Death
            { spell = "Execute", cond = AND(stacksMax(ID_IMMINENT, 2), cdReady(227847)) }, -- before Bladestorm, <3 Imminent Demise
            { spell = "Bladestorm", cond = buffUp(ID_COLOSSUS_DBF) }, -- during Colossus Smash
            { spell = "HeroicStrike" },                           -- Slayer proc (when available)
            { spell = "MortalStrike" },
            { spell = "Execute", cond = buffUp(ID_SUDDENDEATH) }, -- during Sudden Death
            { spell = "Overpower" },
            { spell = "Cleave", cond = OR(buffDown(ID_REND), refreshable(ID_REND)) }, -- keep Rend up
            { spell = "Slam" },                                   -- filler
        },

        -- AoE (3+): Sweeping Strikes + Cleave-heavy. Cleave applies Rend and is the
        -- Collateral Damage spender at 3 stacks.
        aoe = {
            { spell = "SweepingStrikes" },                        -- on CD
            { spell = "Cleave", cond = buffDown(ID_REND) },       -- early, to apply Rend
            { spell = "Avatar" },
            { spell = "ThunderousRoar" },
            { spell = "ChampionsSpear" },
            { spell = "ColossusSmash" },
            { spell = "Ravager" },
            { spell = "Cleave", cond = stacksMin(ID_COLLATERAL, 3) }, -- 3 stacks Collateral Damage
            { spell = "Bladestorm" },
            { spell = "Demolish" },
            { spell = "Execute", cond = stacksMin(ID_SUDDENDEATH, 2) },
            { spell = "Cleave" },                                 -- main AoE spender
            { spell = "Overpower", cond = chargesMin(7384, 2) },  -- with 2 charges
            { spell = "Execute", cond = buffUp(ID_SUDDENDEATH) },
            { spell = "Overpower" },
            { spell = "MortalStrike" },
            { spell = "Execute" },
            { spell = "Slam" },                                   -- filler
        },
    },

    --------------------------------------------------------------------------------
    -- Debug metadata (see Debug.lua). Rows shown live; economy is informational.
    --------------------------------------------------------------------------------
    debug = {
        { label = "Overpower charges",    kind = "charges", key = "Overpower" },
        { label = "Rend (target)",        kind = "buff",  spell = ID_REND },
        { label = "Sudden Death stacks",  kind = "stacks", spell = ID_SUDDENDEATH },
        { label = "Collateral Dmg stacks", kind = "stacks", spell = ID_COLLATERAL },
        { label = "Exec. Precision stacks", kind = "stacks", spell = ID_EXECPREC },
        { label = "Imminent Demise stacks", kind = "stacks", spell = ID_IMMINENT },
        { label = "Colossus Smash (t)",   kind = "buff",  spell = ID_COLOSSUS_DBF },
        { label = "Sweeping Strikes",     kind = "buff",  spell = ID_SWEEPING },
    },
    economy = {
        gen   = { "Auto-attack", "Mortal Strike", "Skullsplitter", "Overpower" },
        spend = { "Execute", "Slam", "Cleave", "Bladestorm" },
    },
}

-- 2-target cleave = Sweeping Strikes up + the single-target list (Arms cleaves its
-- ST rotation onto a second target via Sweeping Strikes).
spec.priority.cleave = { { spell = "SweepingStrikes" } }
for _, e in ipairs(spec.priority.st) do spec.priority.cleave[#spec.priority.cleave + 1] = e end

PRIO.specs[spec.specID] = spec
