-- Spec_Windwalker.lua ----------------------------------------------------------
-- Windwalker Monk (spec 269), patch 12.1 (Midnight). All-inclusive ST/AoE covering
-- both hero trees -- Conduit of the Celestials and Shado-Pan -- filtered by IsKnown.
--
-- RESOURCE: Chi is a DISCRETE class power (reads CLEAN in combat), so the engine gates
-- Chi spenders on the real Chi count -- that covers the guide's "not enough Chi for
-- Fists of Fury -> Tiger Palm" logic automatically. Energy is a secret bar and only
-- paces Tiger Palm, so it isn't gated.
-- MASTERY (Combo Strikes): never cast the same ability twice in a row -> `comboOK`
-- (didn't just cast this) on the spammable abilities, from readable cast history.
-- APPROXIMATIONS: the guide's duration/timing conditions ("Heart of the Jade Serpent
-- < 1s", "Zenith almost over", "Xuen 10s away") aren't readable, so those lines use
-- buff PRESENCE / cooldown readiness instead. Spell/buff IDs from the 12.1 guide;
-- verify with /prio spells and /prio tracked.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local CHI = (Enum and Enum.PowerType and Enum.PowerType.Chi) or 12

-- Readable buff IDs (verify with /prio tracked).
local ID_HEARTJADE   = 443294   -- Heart of the Jade Serpent (from WDP / Strike / Conduit)
local ID_ZENITH      = 1249625  -- Zenith window
local ID_UNBROKEN    = 1296624  -- Unbroken Rhythm
local ID_COMBOBREAK  = 137384   -- Combo Breaker (free Blackout Kick)
local ID_DANCECHIJI  = 325201   -- Dance of Chi-Ji (free Spinning Crane Kick)
local ID_OBSIDIAN    = 1249832  -- Obsidian Spiral (talent)

local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function chiMin(n) return { type = "resourceMin", v = n } end   -- Chi >= n
local function chiMax(n) return { type = "resourceMax", v = n } end   -- Chi <= n (low Chi)
local comboOK = { type = "lastCastNot" }   -- Combo Strikes: not the previous ability

local spec = {
    key      = "MONK_WINDWALKER",
    label    = "Windwalker",
    className = "Monk",
    specID   = 269,
    resource = CHI,
    resourceLabel = "Chi",
    cleaveAt = 3,   -- ~single-target up to 2; AoE (Spinning Crane Kick) at 3+
    aoeAt    = 3,

    spells = {
        TigerPalm          = 100780,
        BlackoutKick       = 100784,
        RisingSunKick      = 107428,
        FistsOfFury        = 113656,
        SpinningCraneKick  = 101546,
        WhirlingDragonPunch = 152175,
        StrikeOfTheWindlord = 392983,
        RushingWindKick    = 1250566,   -- 12.1
        ZenithStomp        = 1272696,   -- 12.1
        TouchOfDeath       = 322109,
        InvokeXuen         = 123904,
        StormEarthAndFire  = 137639,
        CelestialConduit   = 443028,    -- Conduit of the Celestials
        SlicingWinds       = 1217413,   -- Conduit
    },

    auras = {
        HeartOfJadeSerpent = ID_HEARTJADE,
        Zenith        = ID_ZENITH,
        UnbrokenRhythm = ID_UNBROKEN,
        ComboBreaker  = ID_COMBOBREAK,
        DanceOfChiJi  = ID_DANCECHIJI,
    },
    setup = {
        { kind = "trackedAura", label = "Dance of Chi-Ji tracked", spell = ID_DANCECHIJI,
          hint = "Track Dance of Chi-Ji so free Spinning Crane Kick procs are detected." },
        { kind = "trackedAura", label = "Combo Breaker tracked", spell = ID_COMBOBREAK,
          hint = "Track Combo Breaker so free Blackout Kick procs are detected." },
        { kind = "trackedAura", label = "Heart of the Jade Serpent tracked", spell = ID_HEARTJADE,
          hint = "Track Heart of the Jade Serpent so Celestial Conduit timing reads right." },
    },

    openerReady = { "InvokeXuen", "StormEarthAndFire" },
    opener = { "InvokeXuen", "StrikeOfTheWindlord", "RisingSunKick", "FistsOfFury",
               "WhirlingDragonPunch", "BlackoutKick", "TigerPalm" },
    precombat = {},

    pickable = {
        "TigerPalm", "BlackoutKick", "RisingSunKick", "FistsOfFury", "SpinningCraneKick",
        "WhirlingDragonPunch", "StrikeOfTheWindlord", "RushingWindKick", "ZenithStomp",
        "TouchOfDeath", "InvokeXuen", "StormEarthAndFire", "CelestialConduit", "SlicingWinds",
    },

    fillers = { [100780] = true },   -- Tiger Palm (Chi builder / filler)

    flash = {
        SpinningCraneKick = { type = "buffActive", spell = ID_DANCECHIJI },  -- free SCK
        BlackoutKick      = { type = "buffActive", spell = ID_COMBOBREAK },  -- free BoK
    },

    maelstromMax = 6,   -- Chi cap (generic "resource" fields)
    maelstromGen = { TigerPalm = 2 },   -- Tiger Palm builds Chi

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Heart of Jade Serpent", kind = "buff", spell = ID_HEARTJADE },
        { label = "Zenith",         kind = "buff", spell = ID_ZENITH },
        { label = "Combo Breaker",  kind = "buff", spell = ID_COMBOBREAK },
        { label = "Dance of Chi-Ji", kind = "buff", spell = ID_DANCECHIJI },
        { label = "Fists of Fury",  kind = "cd",   spell = 113656 },
    },
    economy = {
        gen   = { "Tiger Palm", "Zenith Stomp", "auto-attack (Energy)" },
        spend = { "Rising Sun Kick", "Fists of Fury", "Blackout Kick", "Spinning Crane Kick", "Whirling Dragon Punch" },
    },

    priority = {
        -- Single target (Conduit + Shado-Pan merged). Cooldowns first, procs, spenders,
        -- then Chi builder / fillers. Chi spenders are gated on real Chi by the engine.
        st = {
            { spell = "InvokeXuen" },                              -- major CD
            { spell = "StormEarthAndFire" },                       -- major CD (alt to Xuen)
            { spell = "WhirlingDragonPunch" },                     -- CD (needs RSK + FoF down)
            { spell = "StrikeOfTheWindlord" },                     -- CD (builds Heart of Jade Serpent)
            { spell = "CelestialConduit", cond = buffDown(ID_HEARTJADE) }, -- Conduit: build the buff
            { spell = "ZenithStomp", cond = chiMax(2) },           -- generate when low on Chi
            { spell = "TigerPalm",   cond = chiMax(2) },           -- build Chi for Fists of Fury
            { spell = "FistsOfFury" },                             -- CD (Chi spender)
            { spell = "RushingWindKick" },                         -- CD
            { spell = "SpinningCraneKick", cond = OR(buffUp(ID_DANCECHIJI), buffUp(ID_UNBROKEN)) }, -- free / empowered
            { spell = "RisingSunKick" },                           -- CD (Chi spender)
            { spell = "BlackoutKick", cond = OR(buffUp(ID_COMBOBREAK), buffUp(ID_ZENITH)) }, -- proc / Zenith
            { spell = "SpinningCraneKick", cond = chiMin(5) },     -- spend high Chi (Zenith window)
            { spell = "SlicingWinds" },                            -- Conduit: on CD
            { spell = "TouchOfDeath" },                            -- execute CD
            { spell = "TigerPalm",   cond = comboOK },             -- Chi builder / filler
            { spell = "BlackoutKick", cond = comboOK },            -- Chi spender / filler
        },

        -- AoE (3+): Fists of Fury and Spinning Crane Kick lead.
        aoe = {
            { spell = "InvokeXuen" },
            { spell = "StormEarthAndFire" },
            { spell = "WhirlingDragonPunch" },
            { spell = "ZenithStomp" },
            { spell = "FistsOfFury" },                             -- strong AoE, high
            { spell = "RisingSunKick" },                           -- enables WDP
            { spell = "RushingWindKick" },
            { spell = "CelestialConduit", cond = buffDown(ID_HEARTJADE) },
            { spell = "SpinningCraneKick", cond = OR(buffUp(ID_DANCECHIJI), buffUp(ID_UNBROKEN), buffUp(ID_ZENITH)) },
            { spell = "BlackoutKick", cond = buffUp(ID_COMBOBREAK) }, -- proc
            { spell = "SpinningCraneKick", cond = comboOK },       -- AoE spender
            { spell = "SlicingWinds" },
            { spell = "TigerPalm",   cond = comboOK },             -- Chi builder / filler
            { spell = "BlackoutKick", cond = comboOK },
        },
    },
}
spec.priority.cleave = spec.priority.st   -- 2 targets plays like single target

PRIO.specs[spec.specID] = spec
