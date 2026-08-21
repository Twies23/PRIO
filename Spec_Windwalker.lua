-- Spec_Windwalker.lua ----------------------------------------------------------
-- Windwalker Monk (spec 269), patch 12.1 (Midnight). All-inclusive ST/AoE lists
-- covering both hero trees -- Shado-Pan and Conduit of the Celestials -- filtered
-- by IsKnown. Spell IDs are best-guess; verify with /prio spells and /prio tracked.
--
-- RESOURCE: Chi is a DISCRETE class power (max 5) and reads CLEAN in combat, so the
-- engine gates Chi spenders on the real Chi count. Energy is a secret bar but only
-- paces Tiger Palm, so it's not gated.
-- MASTERY (Combo Strikes): never cast the same ability twice in a row. Modeled with
-- `comboOK` = "didn't just cast this" on the spammable abilities (cooldown abilities
-- can't repeat anyway), using the readable cast history -- a perfect fit for PRIO.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local CHI = (Enum and Enum.PowerType and Enum.PowerType.Chi) or 12

-- Readable buff IDs (verify with /prio tracked).
local ID_DANCECHIJI = 325202   -- Dance of Chi-Ji (free, empowered Spinning Crane Kick)

local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local comboOK = { type = "lastCastNot" }   -- Combo Strikes: not the previous ability

local spec = {
    key      = "MONK_WINDWALKER",
    label    = "Windwalker",
    className = "Monk",
    specID   = 269,
    resource = CHI,
    resourceLabel = "Chi",
    cleaveAt = 3,   -- Windwalker plays ~single-target up to 2; AoE (SCK) at 3+
    aoeAt    = 3,

    spells = {
        TigerPalm          = 100780,
        BlackoutKick       = 100784,
        RisingSunKick      = 107428,
        FistsOfFury        = 113656,
        SpinningCraneKick  = 101546,
        WhirlingDragonPunch = 152175,
        StrikeOfTheWindlord = 392983,
        TouchOfDeath       = 322109,
        InvokeXuen         = 123904,
        StormEarthAndFire  = 137639,
        CelestialConduit   = 443028,   -- Conduit of the Celestials
        SlicingWinds       = 1217413,  -- Conduit (verify)
    },

    auras = {
        DanceOfChiJi = ID_DANCECHIJI,
    },
    setup = {
        { kind = "trackedAura", label = "Dance of Chi-Ji tracked", spell = ID_DANCECHIJI,
          hint = "Track Dance of Chi-Ji so free Spinning Crane Kick procs are detected." },
    },

    openerReady = { "InvokeXuen", "StormEarthAndFire" },
    opener = { "InvokeXuen", "StrikeOfTheWindlord", "RisingSunKick", "FistsOfFury",
               "WhirlingDragonPunch", "BlackoutKick", "TigerPalm" },
    precombat = {},

    pickable = {
        "TigerPalm", "BlackoutKick", "RisingSunKick", "FistsOfFury", "SpinningCraneKick",
        "WhirlingDragonPunch", "StrikeOfTheWindlord", "TouchOfDeath", "InvokeXuen",
        "StormEarthAndFire", "CelestialConduit", "SlicingWinds",
    },

    fillers = { [100780] = true },   -- Tiger Palm (Chi builder / filler)

    flash = {
        SpinningCraneKick = { type = "buffActive", spell = ID_DANCECHIJI },  -- free SCK proc
    },

    -- Chi (generic "maelstrom" fields). Chi reads clean, so the spender gate uses the
    -- real value; generation lets the prediction stay sane out of combat.
    maelstromMax = 5,
    maelstromGen = {
        TigerPalm = 2,   -- Tiger Palm builds Chi
    },

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Dance of Chi-Ji", kind = "buff", spell = ID_DANCECHIJI },
        { label = "Fists of Fury",   kind = "cd",   spell = 113656 },
        { label = "Rising Sun Kick", kind = "cd",   spell = 107428 },
    },
    economy = {
        gen   = { "Tiger Palm", "auto-attack (Energy)" },
        spend = { "Rising Sun Kick", "Fists of Fury", "Blackout Kick", "Spinning Crane Kick", "Whirling Dragon Punch" },
    },

    priority = {
        -- Single target (Shado-Pan + Conduit merged). Cooldowns first, then the Chi
        -- spenders / builder. Combo Strikes keeps the same ability from repeating.
        st = {
            { spell = "InvokeXuen" },                              -- CD (talent)
            { spell = "StormEarthAndFire" },                       -- CD (talent alt to Xuen)
            { spell = "CelestialConduit" },                        -- Conduit: CD
            { spell = "WhirlingDragonPunch" },                     -- CD (needs RSK + FoF on CD)
            { spell = "StrikeOfTheWindlord" },                     -- CD
            { spell = "FistsOfFury" },                             -- CD (channel, Chi spender)
            { spell = "RisingSunKick" },                           -- CD (Chi spender)
            { spell = "TouchOfDeath" },                            -- CD (execute)
            { spell = "SlicingWinds" },                            -- Conduit: on CD
            { spell = "SpinningCraneKick", cond = buffUp(ID_DANCECHIJI) }, -- free proc, spend it
            { spell = "BlackoutKick",     cond = comboOK },        -- Chi spender / CD reduction
            { spell = "TigerPalm",        cond = comboOK },        -- Chi builder / filler
        },

        -- AoE (3+): Spinning Crane Kick becomes the core spender.
        aoe = {
            { spell = "InvokeXuen" },
            { spell = "StormEarthAndFire" },
            { spell = "CelestialConduit" },
            { spell = "WhirlingDragonPunch" },
            { spell = "StrikeOfTheWindlord" },
            { spell = "FistsOfFury" },                             -- strong AoE, high priority
            { spell = "RisingSunKick" },
            { spell = "SpinningCraneKick", cond = comboOK },       -- AoE spender
            { spell = "BlackoutKick",     cond = comboOK },
            { spell = "TigerPalm",        cond = comboOK },        -- Chi builder / filler
        },
    },
}
spec.priority.cleave = spec.priority.st   -- 2 targets plays like single target

PRIO.specs[spec.specID] = spec
