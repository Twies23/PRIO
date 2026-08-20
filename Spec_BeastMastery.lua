-- Spec_BeastMastery.lua --------------------------------------------------------
-- Beast Mastery Hunter (spec 253), patch 12.1. All-inclusive lists covering both
-- Pack Leader and Dark Ranger -- untalented abilities (Black Arrow / Bloodshed /
-- Call of the Wild) are filtered by IsKnown, and buff-gated lines go inert when
-- the buff never appears. Spell IDs are best-guess; verify with /prio spells.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local FOCUS = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2

-- Readable buff IDs (verify with /prio tracked).
local ID_FRENZY    = 272790   -- Frenzy (pet, from Barbed Shot)
local ID_BEASTCLEAVE = 268877 -- Beast Cleave (from Multi-Shot)
local ID_HOWL      = 471877   -- Howl of the Pack Leader (Pack Leader)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end

local spec = {
    key      = "HUNTER_BEASTMASTERY",
    label    = "Beast Mastery",
    specID   = 253,
    resource = FOCUS,
    resourceLabel = "Focus",
    cleaveAt = 2,   -- Beast Cleave (Multi-Shot) starts at 2 targets
    aoeAt    = 3,

    spells = {
        KillCommand  = 34026,
        BarbedShot   = 217200,
        BestialWrath = 19574,
        CobraShot    = 193455,
        MultiShot    = 2643,
        KillShot     = 53351,
        Bloodshed    = 321530,   -- Pack Leader / talent
        BlackArrow   = 466930,   -- Dark Ranger
        CallOfTheWild = 359844,
        ExplosiveShot = 212431,
        DireBeast    = 120679,
    },

    openerReady = { "BestialWrath" },
    opener = { "BarbedShot", "BestialWrath", "KillCommand", "Bloodshed",
               "BarbedShot", "CobraShot", "KillCommand" },

    precombat = {},

    pickable = {
        "BarbedShot", "KillCommand", "BestialWrath", "CobraShot", "MultiShot",
        "KillShot", "Bloodshed", "BlackArrow", "CallOfTheWild", "ExplosiveShot",
        "DireBeast",
    },

    -- Barbed Shot and Kill Command both run on 2 charges.
    chargeTrack = {
        BarbedShot  = { max = 2, recharge = 12 },
        KillCommand = { max = 2, recharge = 7.5 },
    },

    fillers = { [193455] = true },   -- Cobra Shot

    flash = {
        KillShot = { type = "cdReady", spell = 53351 },
    },

    -- Beast Cleave from Multi-Shot; consumed passively by pet melee. Track it so
    -- AoE lines can keep it up.
    spellEffects = {
        MultiShot = { grant = { ID_BEASTCLEAVE } },
    },

    maelstromMax = 100,   -- Focus cap (generic "resource" fields)
    maelstromGen = {
        BarbedShot = 5,
        CobraShot  = 0,   -- Cobra Shot spends Focus
    },

    OnCast = function(P, key, now) end,

    priority = {
        -- Single target (Pack Leader + Dark Ranger merged).
        st = {
            { spell = "BestialWrath" },
            { spell = "CallOfTheWild" },
            { spell = "Bloodshed" },                              -- PL / talent
            { spell = "BarbedShot", cond = buffDown(ID_FRENZY) }, -- keep Frenzy up
            { spell = "BlackArrow" },                             -- DR: on CD (also Kill Shot exec)
            { spell = "KillShot" },
            { spell = "KillCommand" },
            { spell = "ExplosiveShot" },
            { spell = "BarbedShot" },                             -- dump charges
            { spell = "DireBeast" },
            { spell = "CobraShot" },                              -- Focus dump / filler
        },

        -- Cleave / AoE (Beast Cleave). Multi-Shot keeps Beast Cleave up so pet
        -- melee and Kill Command splash.
        cleave = {
            { spell = "MultiShot",  cond = buffDown(ID_BEASTCLEAVE) },  -- put Beast Cleave up
            { spell = "BestialWrath" },
            { spell = "CallOfTheWild" },
            { spell = "BarbedShot", cond = buffDown(ID_FRENZY) },
            { spell = "Bloodshed" },
            { spell = "BlackArrow" },
            { spell = "KillCommand" },
            { spell = "ExplosiveShot" },
            { spell = "KillShot" },
            { spell = "BarbedShot" },
            { spell = "DireBeast" },
            { spell = "CobraShot" },
        },
    },
}
spec.priority.aoe = spec.priority.cleave   -- same list for 3+

PRIO.specs[spec.specID] = spec
