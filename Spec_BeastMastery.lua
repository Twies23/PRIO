-- Spec_BeastMastery.lua --------------------------------------------------------
-- Beast Mastery Hunter (spec 253), patch 12.1 (Midnight). All-inclusive lists
-- covering both Pack Leader and Dark Ranger -- untalented abilities (Black Arrow /
-- Bloodshed / Call of the Wild) are filtered by IsKnown, and buff-gated lines go
-- inert when the buff never appears. Spell IDs are best-guess; verify /prio spells.
--
-- Midnight notes: Multi-Shot and Dire Beast are gone from BM. Wild Thrash (8s CD)
-- is the AoE spender and is what activates Beast Cleave now. Dire Beast is a
-- passive proc, not a button.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local FOCUS = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2

-- Readable buff IDs (verify with /prio tracked).
local ID_FRENZY      = 272790    -- Frenzy (pet, from Barbed Shot)
local ID_BEASTCLEAVE = 268877    -- Beast Cleave (from Wild Thrash)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end

local spec = {
    key      = "HUNTER_BEASTMASTERY",
    label    = "Beast Mastery",
    className = "Hunter",
    specID   = 253,
    resource = FOCUS,
    resourceLabel = "Focus",
    cleaveAt = 2,   -- Wild Thrash / Beast Cleave starts at 2 targets
    aoeAt    = 3,

    spells = {
        KillCommand  = 34026,
        BarbedShot   = 217200,
        BestialWrath = 19574,
        CobraShot    = 193455,
        KillShot     = 53351,
        WildThrash   = 1264359,   -- AoE spender, grants Beast Cleave
        Bloodshed    = 321530,    -- Pack Leader / talent
        BlackArrow   = 466930,    -- Dark Ranger
        CallOfTheWild = 359844,
        ExplosiveShot = 212431,
    },

    openerReady = { "BestialWrath" },
    opener = { "BarbedShot", "BestialWrath", "KillCommand", "Bloodshed",
               "BarbedShot", "CobraShot", "KillCommand" },

    precombat = {},

    pickable = {
        "BarbedShot", "KillCommand", "BestialWrath", "CobraShot", "WildThrash",
        "KillShot", "Bloodshed", "BlackArrow", "CallOfTheWild", "ExplosiveShot",
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

    -- Beast Cleave is now granted by Wild Thrash (8s CD, 10s buff). Track it so
    -- AoE lines can keep it up.
    spellEffects = {
        WildThrash = { grant = { ID_BEASTCLEAVE } },
    },

    maelstromMax = 100,   -- Focus cap (generic "resource" fields)
    maelstromGen = {
        BarbedShot = 20,
        CobraShot  = 0,   -- Cobra Shot spends Focus
    },

    OnCast = function(P, key, now) end,

    --------------------------------------------------------------------------------
    -- Debug metadata (see Debug.lua). Rows shown live; economy is informational.
    --------------------------------------------------------------------------------
    debug = {
        { label = "Barbed Shot charges",  kind = "charges", key = "BarbedShot" },
        { label = "Kill Command charges", kind = "charges", key = "KillCommand" },
        { label = "Frenzy (pet)",         kind = "buff", spell = ID_FRENZY },
        { label = "Beast Cleave",         kind = "buff", spell = ID_BEASTCLEAVE },
        { label = "Bestial Wrath",        kind = "cd",   spell = 19574 },
    },
    economy = {
        gen   = { "Auto-shot", "Cobra Shot" },
        spend = { "Kill Command", "Barbed Shot", "Wild Thrash" },
    },

    priority = {
        -- Single target (Pack Leader + Dark Ranger merged). Wild Thrash is AoE-only,
        -- so it never appears here.
        st = {
            { spell = "BestialWrath" },                            -- big CD, on cooldown
            { spell = "CallOfTheWild" },
            { spell = "Bloodshed" },                               -- PL / talent, on CD
            { spell = "BarbedShot", cond = buffDown(ID_FRENZY) },  -- keep Frenzy up
            { spell = "KillCommand" },                             -- primary spender (charges)
            { spell = "BlackArrow" },                              -- DR: on CD / execute
            { spell = "KillShot" },
            { spell = "ExplosiveShot" },
            { spell = "BarbedShot" },                              -- dump charges
            { spell = "CobraShot" },                               -- Focus dump / filler
        },

        -- Cleave / AoE. Wild Thrash keeps Beast Cleave up so Kill Command and pet
        -- melee splash.
        cleave = {
            { spell = "WildThrash", cond = buffDown(ID_BEASTCLEAVE) }, -- put Beast Cleave up
            { spell = "BestialWrath" },
            { spell = "CallOfTheWild" },
            { spell = "WildThrash" },                                  -- on cooldown
            { spell = "BarbedShot", cond = buffDown(ID_FRENZY) },
            { spell = "Bloodshed" },
            { spell = "KillCommand" },
            { spell = "BlackArrow" },
            { spell = "ExplosiveShot" },
            { spell = "KillShot" },
            { spell = "BarbedShot" },
            { spell = "CobraShot" },                                   -- filler
        },
    },
}
spec.priority.aoe = spec.priority.cleave   -- same list for 3+

PRIO.specs[spec.specID] = spec
