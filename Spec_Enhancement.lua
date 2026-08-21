-- Spec_Enhancement.lua ---------------------------------------------------------
-- Enhancement Shaman (spec 263), patch 12.1 (Midnight). All-inclusive ST/AoE lists
-- covering both hero trees -- Stormbringer (Tempest / Primordial Storm cycling) and
-- Totemic (Surging Totem window) -- filtered by IsKnown. Spell IDs are best-guess;
-- verify with /prio spells and /prio tracked.
--
-- RESOURCE REALITY: the "resource" is Maelstrom Weapon (a stacking BUFF, 0-10), not
-- a power bar -- so its stack count is SECRET in combat and can't be read. We can't
-- gate "spend at 10 stacks" precisely; instead spenders are gated on the Maelstrom
-- Weapon buff being PRESENT, and placed below the melee builders so the melee core
-- fires on cooldown and spenders fill the gaps. This is an approximation of the APL,
-- not the exact stack-counted rotation.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

-- Readable buff IDs (verify with /prio tracked).
local ID_MAELWEAPON = 344179   -- Maelstrom Weapon (stacks; presence readable-ish)
local ID_HOTHAND    = 215785   -- Hot Hand (empowers Lava Lash)
local ID_DOOMWINDS  = 335903   -- Doom Winds buff
local ID_ASCENDANCE = 114051   -- Ascendance (Enh) cast + buff
local ID_CRASHLB    = 187878   -- Crash Lightning buff (cleave weapon buff)
local ID_FLAMESHOCK = 188389   -- Flame Shock debuff

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end

local spec = {
    key      = "SHAMAN_ENHANCEMENT",
    label    = "Enhancement",
    className = "Shaman",
    specID   = 263,
    -- No power-bar resource: Maelstrom Weapon is a buff, so leave resource unset.
    resourceLabel = "Maelstrom Wpn",
    cleaveAt = 2,   -- Chain Lightning / Crash Lightning at 2+
    aoeAt    = 3,

    spells = {
        Stormstrike    = 17364,
        LavaLash       = 60103,
        IceStrike      = 342240,
        CrashLightning = 187874,
        FrostShock     = 196840,
        FlameShock     = 188389,
        LightningBolt  = 188196,
        ChainLightning = 188443,
        ElementalBlast = 117014,
        FeralSpirit    = 51533,
        Sundering      = 197214,
        DoomWinds      = 384352,
        PrimordialWave = 375982,
        FireNova       = 333974,
        Windstrike     = 115356,
        Ascendance     = 114051,
        Tempest        = 454009,    -- Stormbringer
        VoltaicBlaze   = 470057,    -- 2pc / Voltaic Blaze
        SurgingTotem   = 444995,    -- Totemic
        PrimordialStorm = 1218090,  -- Stormbringer spender (verify ID)
    },

    openerReady = { "DoomWinds", "FeralSpirit", "Ascendance" },
    opener = { "FlameShock", "FeralSpirit", "DoomWinds", "Sundering",
               "LavaLash", "Stormstrike", "LightningBolt" },

    precombat = {
        { spell = "FlameShock", aura = ID_FLAMESHOCK },
    },

    pickable = {
        "Stormstrike", "LavaLash", "IceStrike", "CrashLightning", "FrostShock",
        "FlameShock", "LightningBolt", "ChainLightning", "ElementalBlast",
        "FeralSpirit", "Sundering", "DoomWinds", "PrimordialWave", "FireNova",
        "Windstrike", "Ascendance", "Tempest", "VoltaicBlaze", "SurgingTotem",
        "PrimordialStorm",
    },

    fillers = { [196840] = true },   -- Frost Shock (melee-range instant filler)

    flash = {
        LavaLash      = { type = "buffActive", spell = ID_HOTHAND },
        Tempest       = { type = "buffActive", spell = ID_MAELWEAPON },
        ElementalBlast = { type = "buffActive", spell = ID_MAELWEAPON },
    },

    -- Look-ahead: Crash Lightning grants its cleave buff; spenders consume Maelstrom
    -- Weapon (sim-only; the real stacks are secret).
    spellEffects = {
        CrashLightning = { grant = { ID_CRASHLB } },
        LightningBolt  = { consume = { ID_MAELWEAPON } },
        ChainLightning = { consume = { ID_MAELWEAPON } },
        ElementalBlast = { consume = { ID_MAELWEAPON } },
        Tempest        = { consume = { ID_MAELWEAPON } },
        PrimordialStorm = { consume = { ID_MAELWEAPON } },
    },

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Maelstrom Weapon", kind = "stacks", spell = ID_MAELWEAPON },
        { label = "Hot Hand",         kind = "buff", spell = ID_HOTHAND },
        { label = "Doom Winds",       kind = "buff", spell = ID_DOOMWINDS },
        { label = "Ascendance",       kind = "buff", spell = ID_ASCENDANCE },
        { label = "Flame Shock (t)",  kind = "buff", spell = ID_FLAMESHOCK },
    },
    economy = {
        gen   = { "Auto-attack", "Stormstrike", "Lava Lash", "Crash Lightning", "Doom Winds" },
        spend = { "Lightning Bolt", "Chain Lightning", "Elemental Blast", "Tempest", "Primordial Storm" },
    },

    priority = {
        -- Single target (Stormbringer + Totemic merged). Cooldowns, then the melee
        -- core on cooldown, then Maelstrom-Weapon spenders (gated on the buff being
        -- up -- stacks aren't readable), then a filler.
        st = {
            { spell = "FeralSpirit" },
            { spell = "DoomWinds" },
            { spell = "Ascendance" },
            { spell = "SurgingTotem" },                              -- Totemic
            { spell = "Sundering" },
            { spell = "PrimordialWave" },
            { spell = "FlameShock", ignoreCD = true, cond = buffDown(ID_FLAMESHOCK) },
            { spell = "VoltaicBlaze" },                              -- 2pc / on CD
            { spell = "Windstrike" },                                -- during Ascendance (replaces Stormstrike)
            { spell = "LavaLash", cond = buffUp(ID_HOTHAND) },       -- Hot Hand priority
            { spell = "PrimordialStorm", cond = buffUp(ID_MAELWEAPON) }, -- Stormbringer spender
            { spell = "Tempest",  cond = buffUp(ID_MAELWEAPON) },    -- Stormbringer spender
            { spell = "Stormstrike" },                               -- melee core (on CD)
            { spell = "LavaLash" },
            { spell = "CrashLightning" },
            { spell = "IceStrike" },
            { spell = "ElementalBlast", cond = buffUp(ID_MAELWEAPON) }, -- spend MW
            { spell = "LightningBolt",  cond = buffUp(ID_MAELWEAPON) }, -- spend MW (instant)
            { spell = "FrostShock" },                                -- filler
        },

        -- Cleave / AoE. Crash Lightning up, Chain Lightning is the spender at 2+.
        cleave = {
            { spell = "FeralSpirit" },
            { spell = "DoomWinds" },
            { spell = "Ascendance" },
            { spell = "SurgingTotem" },
            { spell = "Sundering" },
            { spell = "CrashLightning", cond = buffDown(ID_CRASHLB) }, -- put the cleave buff up
            { spell = "PrimordialWave" },
            { spell = "VoltaicBlaze" },
            { spell = "FireNova" },
            { spell = "Windstrike" },
            { spell = "PrimordialStorm", cond = buffUp(ID_MAELWEAPON) },
            { spell = "ChainLightning",  cond = buffUp(ID_MAELWEAPON) }, -- AoE spender
            { spell = "LavaLash", cond = buffUp(ID_HOTHAND) },
            { spell = "Stormstrike" },
            { spell = "CrashLightning" },
            { spell = "LavaLash" },
            { spell = "IceStrike" },
            { spell = "FrostShock" },
        },
    },
}
spec.priority.aoe = spec.priority.cleave   -- same list for 3+

PRIO.specs[spec.specID] = spec
