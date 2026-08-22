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

-- Readable buff/debuff IDs (verify with /prio tracked).
local ID_SUDDENDEATH = 52437     -- Sudden Death (free/instant Execute)
local ID_COLOSSUS_DBF = 208086   -- Colossus Smash debuff (on target)
local ID_OPPORTUNIST = 217344    -- Opportunist (empowers Overpower)
local ID_COLOSSALMIGHT = 440989  -- Colossal Might stacks (Colossus)
local ID_SWEEPING    = 260708    -- Sweeping Strikes (self)
local ID_REND        = 772       -- Rend debuff (on target)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function talent(id)   return { type = "talentYes",   spell = id } end
local function refreshable(id) return { type = "refreshable", spell = id } end

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
        ColossusSmash = ID_COLOSSUS_DBF,
        ColossalMight = ID_COLOSSALMIGHT,
        Opportunist   = ID_OPPORTUNIST,
        SweepingStrikes = ID_SWEEPING,
    },

    -- First-time setup checklist (Setup.lua adds the global nameplate check).
    setup = {
        { kind = "trackedAura", label = "Rend tracked", spell = ID_REND,
          hint = "Track Rend in your Cooldown Manager so PRIO knows when to refresh it." },
        { kind = "trackedAura", label = "Colossus Smash tracked", spell = ID_COLOSSUS_DBF,
          hint = "Track the Colossus Smash debuff so burst windows read correctly." },
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
    },

    openerReady = { "Avatar", "ColossusSmash", "Warbreaker" },
    opener = { "Rend", "Avatar", "ColossusSmash", "MortalStrike", "Overpower",
               "Execute", "Slam" },

    precombat = {},   -- Rend is a target debuff (opener leads with it), not a self-buff

    pickable = {
        "MortalStrike", "Overpower", "Execute", "Slam", "Cleave", "ThunderClap",
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

    -- Colossal Might is built by Colossus Smash / Warbreaker (Colossus tree).
    spellEffects = {
        ColossusSmash = { grant = { ID_COLOSSUS_DBF, ID_COLOSSALMIGHT } },
        Warbreaker    = { grant = { ID_COLOSSUS_DBF, ID_COLOSSALMIGHT } },
    },

    maelstromMax = 100,   -- Rage cap (generic "resource" fields)
    maelstromGen = {},    -- Rage is auto-attack driven; casts mostly spend it

    OnCast = function(P, key, now) end,

    priority = {
        -- Single target (Colossus + Slayer merged).
        st = {
            { spell = "MortalStrike" },                           -- primary generator / Colossal Might
            { spell = "Rend", cond = OR(buffDown(ID_REND), refreshable(ID_REND)) }, -- maintain Rend (missing or pandemic)
            { spell = "Ravager" },                                -- just before Colossus Smash
            { spell = "Avatar" },                                 -- on CD
            { spell = "ThunderousRoar" },                         -- on CD
            { spell = "ChampionsSpear" },                         -- on CD
            { spell = "ColossusSmash" },                          -- on CD (smart-swaps to Warbreaker if talented)
            { spell = "Demolish" },                               -- Colossus: during Colossus Smash
            { spell = "Execute", cond = buffUp(ID_SUDDENDEATH) }, -- Sudden Death proc
            { spell = "Overpower" },                              -- charges; empowered by Opportunist
            { spell = "Skullsplitter" },                          -- Rage generator
            { spell = "Bladestorm" },                             -- Slayer: weave during Colossus Smash
            { spell = "Slam" },                                   -- Rage dump / filler
        },

        -- Cleave / AoE. Sweeping Strikes + Cleave (applies Rend to all).
        cleave = {
            { spell = "SweepingStrikes" },                        -- on CD (3+ targets)
            { spell = "Ravager" },
            { spell = "Avatar" },
            { spell = "ThunderousRoar" },
            { spell = "ChampionsSpear" },
            { spell = "ColossusSmash" },                          -- smart-swaps to Warbreaker if talented
            { spell = "Bladestorm" },                             -- AoE window
            { spell = "Cleave" },                                 -- main AoE, applies Rend
            { spell = "Demolish" },
            { spell = "Execute", cond = buffUp(ID_SUDDENDEATH) },
            { spell = "MortalStrike" },
            { spell = "ThunderClap" },
            { spell = "Overpower" },
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
        { label = "Collateral Dmg stacks", kind = "stacks", spell = 334779 },
        { label = "Colossal Might stacks", kind = "stacks", spell = ID_COLOSSALMIGHT },
        { label = "Colossus Smash (t)",   kind = "buff",  spell = ID_COLOSSUS_DBF },
        { label = "Sweeping Strikes",     kind = "buff",  spell = ID_SWEEPING },
    },
    economy = {
        gen   = { "Auto-attack", "Mortal Strike", "Skullsplitter", "Overpower" },
        spend = { "Execute", "Slam", "Cleave", "Bladestorm" },
    },
}
spec.priority.aoe = spec.priority.cleave   -- same list for 3+

PRIO.specs[spec.specID] = spec
