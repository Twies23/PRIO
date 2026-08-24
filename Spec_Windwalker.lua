-- Spec_Windwalker.lua ----------------------------------------------------------
-- Windwalker Monk (spec 269), patch 12.1 (Midnight).
--
-- HERO-SPLIT: the two hero trees play with different orderings, so this spec holds
-- FOUR lists -- Conduit of the Celestials (ST/AoE) and Shado-Pan (ST/AoE) -- and
-- `spec.priority` is a live metatable proxy that returns the ACTIVE hero's list on
-- every access. Detection: Celestial Conduit known -> Conduit, else Shado-Pan.
-- The engine, editor, and export all read spec.priority[mode] unchanged, so they
-- always see the right hero's list, and it swaps automatically on a talent change.
--
-- RESOURCE: Chi is a DISCRETE class power (reads CLEAN in combat), so Chi spenders
-- gate on the real Chi count -- that already covers "not enough Chi for Fists of
-- Fury -> Tiger Palm". Energy is a secret bar and only paces Tiger Palm.
-- MASTERY (Combo Strikes): the engine never queues the same ability twice in a row
-- (spec.comboStrikes), from readable cast history.
-- APPROXIMATIONS: the guide's duration/timing conditions ("Heart of the Jade Serpent
-- < 1s", "Zenith almost over", "Xuen 10s away") and the tier-set 4-piece aren't
-- readable, so those lines fall back to buff PRESENCE / cooldown readiness / target
-- count. Verify IDs with /prio spells and /prio tracked.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = PRIO.API
PRIO.specs = PRIO.specs or {}

local CHI = (Enum and Enum.PowerType and Enum.PowerType.Chi) or 12

-- Readable buff IDs (verify with /prio tracked).
local ID_HEARTJADE   = 443294   -- Heart of the Jade Serpent (from WDP / Strike / Conduit)
local ID_ZENITH      = 1249625  -- Zenith window
local ID_UNBROKEN    = 1296624  -- Unbroken Rhythm
local ID_COMBOBREAK  = 137284   -- Combo Breaker (free Blackout Kick)
local ID_DANCECHIJI  = 325202   -- Dance of Chi-Ji (free Spinning Crane Kick)
local ID_RUSHINGWIND = 1250554  -- "Rushing Wind Kick available!" proc buff
-- Talent gates (readable via IsTalentSelected).
local ID_OBSIDIAN    = 1249832  -- Obsidian Spiral (talent)
local ID_AIRBORNE    = 1248833  -- Airborne Rhythm (Slicing Winds generates 1 Chi)
local ID_ENERGYBURST = 451498   -- Energy Burst (Blackout Kick! generates 1 Chi)
local ID_SHADOWBOX   = 392982   -- Shadowboxing Treads (talent)
local ID_CELESTIAL   = 443028   -- Celestial Conduit (Conduit hero signature)
local ID_INVOKEXUEN  = 123904   -- Invoke Xuen (burst-window gate)
local ID_TOUCHOFDEATH = 322109  -- Touch of Death (execute availability via Cooldown Viewer)
local ID_SLICINGWINDS = 1217413 -- Slicing Winds (talent)
local ID_DRINKINGHORN = 391370  -- Drinking Horn Cover (talent: Zenith lasts +5s)
local ID_INNERPEACE   = 397768  -- Inner Peace (talent: Tiger Palm energy cost -5)

-- Condition builders -----------------------------------------------------------
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function talentYes(id) return { type = "talentYes",  spell = id } end
local function cdNotReady(id) return { type = "cdNotReady", spell = id } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function AND(...) return { op = "and", clauses = { ... } } end
local function chiMin(n) return { type = "resourceMin", v = n } end   -- Chi >= n
local function chiMax(n) return { type = "resourceMax", v = n } end   -- Chi <= n (low Chi)
local function enemiesMin(n) return { type = "enemiesMin", v = n } end
local function stacksMin(id, n) return { type = "stacksMin", spell = id, v = n } end
local comboOK = { type = "lastCastNot" }   -- Combo Strikes: not the previous ability

-- "Not right before Invoke Xuen" -- approximates the guide's "Xuen 10s+ away" by
-- holding the ability while Xuen is off cooldown (i.e. burst is imminent).
local xuenAway = cdNotReady(ID_INVOKEXUEN)
-- Common Blackout Kick proc gate: free proc, or a Zenith Obsidian-Spiral spender.
local bokProc  = OR(buffUp(ID_COMBOBREAK), AND(buffUp(ID_ZENITH), talentYes(ID_OBSIDIAN)))
-- Spinning Crane Kick inside the Zenith window (single target).
local sckZenith = AND(buffUp(ID_ZENITH), OR(chiMin(5), buffUp(ID_DANCECHIJI)))
-- Tiger Palm pool-to-avoid-cap filler (energy is secret; below 5 Chi, no Zenith).
local tpBelowCap = AND(chiMax(4), buffDown(ID_ZENITH))
local comboBreaker2 = stacksMin(ID_COMBOBREAK, 2)
local bokZenith = AND(buffUp(ID_ZENITH), OR(buffUp(ID_COMBOBREAK), talentYes(ID_OBSIDIAN)))
local touchOfDeathUp = buffUp(ID_TOUCHOFDEATH)
local slicingWindsTalent = talentYes(ID_SLICINGWINDS)

-- CONDUIT of the Celestials -----------------------------------------------------
local conduit_st = {
    { spell = "WhirlingDragonPunch", cond = xuenAway },        -- hold for after Xuen
    { spell = "StrikeOfTheWindlord", cond = xuenAway },        -- hold for after Xuen
    { spell = "CelestialConduit", cond = buffDown(ID_HEARTJADE) }, -- build the buff
    { spell = "ZenithStomp",  cond = chiMax(2) },              -- generate when low on Chi
    { spell = "TigerPalm",    cond = chiMax(2) },              -- build Chi for Fists of Fury
    { spell = "FistsOfFury" },                                 -- Chi spender CD
    { spell = "RushingWindKick", cond = buffUp(ID_RUSHINGWIND) }, -- only when the proc is up
    { spell = "SpinningCraneKick", cond = buffUp(ID_UNBROKEN) }, -- Unbroken Rhythm empowered
    { spell = "RisingSunKick" },                               -- Chi spender CD
    { spell = "BlackoutKick", cond = bokProc },                -- proc / Zenith Obsidian
    { spell = "SpinningCraneKick", cond = sckZenith },         -- Zenith spend (>4 Chi or Dance)
    { spell = "TigerPalm",    cond = chiMax(1) },              -- less than 2 Chi
    { spell = "SpinningCraneKick", cond = buffUp(ID_DANCECHIJI) }, -- free proc
    { spell = "SlicingWinds", cond = slicingWindsTalent },     -- on CD
    { spell = "TigerPalm",    cond = comboOK },                -- filler (without overcapping Chi)
    { spell = "BlackoutKick", cond = comboOK },                -- filler
}

local conduit_aoe = {
    { spell = "WhirlingDragonPunch", cond = xuenAway },
    { spell = "StrikeOfTheWindlord", cond = xuenAway },
    { spell = "ZenithStomp",  cond = chiMax(2) },
    { spell = "TigerPalm",    cond = chiMax(2) },              -- build Chi for Fists of Fury
    { spell = "FistsOfFury" },
    { spell = "SpinningCraneKick", cond = buffUp(ID_UNBROKEN) }, -- 4pc / Unbroken Rhythm
    { spell = "RisingSunKick" },                               -- enables WDP
    { spell = "RushingWindKick", cond = buffUp(ID_RUSHINGWIND) },
    { spell = "SpinningCraneKick", cond = AND(buffUp(ID_ZENITH), enemiesMin(5)) }, -- Zenith, 5+
    { spell = "BlackoutKick", cond = AND(talentYes(ID_OBSIDIAN), buffUp(ID_ZENITH), cdNotReady(107428)) },
    { spell = "SpinningCraneKick" },                           -- main AoE spender
    { spell = "SlicingWinds", cond = slicingWindsTalent },
    { spell = "BlackoutKick", cond = buffUp(ID_COMBOBREAK) },  -- proc
    { spell = "TigerPalm",    cond = tpBelowCap },             -- <5 Chi and no Zenith
    { spell = "BlackoutKick", cond = talentYes(ID_SHADOWBOX) },-- Shadowboxing Treads
    { spell = "TigerPalm",    cond = comboOK },                -- filler
    { spell = "BlackoutKick", cond = comboOK },                -- filler
}

-- SHADO-PAN ---------------------------------------------------------------------
local shadopan_st = {
    { spell = "WhirlingDragonPunch" },                         -- grace period / top CD
    { spell = "ZenithStomp",  cond = chiMax(2) },              -- low Chi (or Zenith ending)
    { spell = "TigerPalm",    cond = tpBelowCap },             -- avoid capping energy outside Zenith
    { spell = "FistsOfFury" },
    { spell = "WhirlingDragonPunch" },
    { spell = "StrikeOfTheWindlord" },
    { spell = "TigerPalm",    cond = chiMax(2) },              -- build Chi for Fists of Fury
    { spell = "RushingWindKick", cond = buffUp(ID_RUSHINGWIND) },
    { spell = "SpinningCraneKick", cond = AND(buffUp(ID_DANCECHIJI), buffUp(ID_UNBROKEN)) }, -- Dance + Unbroken
    { spell = "RisingSunKick" },
    { spell = "BlackoutKick", cond = comboBreaker2 },          -- 2x Combo Breaker
    { spell = "BlackoutKick", cond = bokZenith },              -- Zenith + Combo Breaker / Obsidian
    { spell = "SpinningCraneKick", cond = sckZenith },         -- Zenith spend (>4 Chi or Dance)
    { spell = "TouchOfDeath", cond = touchOfDeathUp },
    { spell = "TigerPalm",    cond = chiMax(1) },              -- less than 2 Chi
    { spell = "BlackoutKick", cond = buffUp(ID_COMBOBREAK) },  -- proc
    { spell = "SpinningCraneKick", cond = buffUp(ID_DANCECHIJI) }, -- free proc
    { spell = "SlicingWinds", cond = slicingWindsTalent },
    { spell = "TigerPalm",    cond = comboOK },                -- filler
    { spell = "BlackoutKick", cond = comboOK },                -- filler
}

local shadopan_aoe = {
    { spell = "WhirlingDragonPunch" },
    { spell = "StrikeOfTheWindlord" },
    { spell = "ZenithStomp",  cond = chiMax(2) },
    { spell = "TigerPalm",    cond = chiMax(2) },              -- build Chi for Fists of Fury
    { spell = "FistsOfFury" },
    { spell = "SpinningCraneKick", cond = buffUp(ID_UNBROKEN) }, -- 4pc / Unbroken Rhythm
    { spell = "TigerPalm",    cond = tpBelowCap },             -- avoid capping energy outside Zenith
    { spell = "RisingSunKick" },                               -- enables WDP
    { spell = "RushingWindKick", cond = buffUp(ID_RUSHINGWIND) },
    { spell = "SpinningCraneKick", cond = AND(buffUp(ID_ZENITH), enemiesMin(5)) }, -- Zenith, 5+
    { spell = "BlackoutKick", cond = AND(talentYes(ID_OBSIDIAN), buffUp(ID_ZENITH), cdNotReady(107428)) },
    { spell = "SpinningCraneKick" },                           -- main AoE spender
    { spell = "SlicingWinds", cond = slicingWindsTalent },
    { spell = "BlackoutKick", cond = buffUp(ID_COMBOBREAK) },  -- proc
    { spell = "TigerPalm",    cond = tpBelowCap },             -- <5 Chi and no Zenith
    { spell = "BlackoutKick", cond = talentYes(ID_SHADOWBOX) },-- Shadowboxing Treads
    { spell = "RisingSunKick" },
    { spell = "BlackoutKick", cond = comboOK },                -- filler
}

local heroLists = {
    conduit  = { st = conduit_st,  aoe = conduit_aoe },
    shadopan = { st = shadopan_st, cleave = shadopan_aoe, aoe = shadopan_aoe },
}

-- Active hero: Celestial Conduit is the Conduit-of-the-Celestials signature; if the
-- player doesn't have it, treat them as Shado-Pan.
local function activeHero()
    if API and API.IsKnown and API.IsKnown(ID_CELESTIAL) then return "conduit" end
    return "shadopan"
end

local BASE_CHI_COST = {
    BlackoutKick      = 1,
    RisingSunKick     = 2,
    FistsOfFury       = 3,
    SpinningCraneKick = 2,
    StrikeOfTheWindlord = 2,
}

local function auraUp(S, spellID)
    if S and S._sim and S._sim[spellID] ~= nil then return S._sim[spellID] end
    return API and API.IsAuraActive and API.IsAuraActive(spellID) == true
end

local function talentSelected(spellID)
    return API and API.IsTalentSelected and API.IsTalentSelected(spellID)
end

local function chiCost(key, S)
    local cost = BASE_CHI_COST[key] or 0
    if key == "BlackoutKick" and (auraUp(S, ID_COMBOBREAK) or auraUp(S, ID_ZENITH)) then
        cost = 0
    elseif key == "SpinningCraneKick" and auraUp(S, ID_DANCECHIJI) then
        cost = 0
    elseif cost > 0 and auraUp(S, ID_ZENITH) then
        cost = math.max(0, cost - 1)
    end
    return cost
end

local function chiDelta(key, S)
    local delta = -chiCost(key, S)
    if key == "TigerPalm" or key == "ZenithStomp" then
        delta = delta + 2
    elseif key == "SlicingWinds" and talentSelected(ID_AIRBORNE) then
        delta = delta + 1
    elseif key == "BlackoutKick" then
        if auraUp(S, ID_COMBOBREAK) and talentSelected(ID_ENERGYBURST) then
            delta = delta + 1
        end
        if auraUp(S, ID_ZENITH) and talentSelected(ID_OBSIDIAN) then
            delta = delta + 1
        end
    end
    return delta
end

local spec = {
    key      = "MONK_WINDWALKER",
    label    = "Windwalker",
    className = "Monk",
    specID   = 269,
    resource = CHI,
    resourceLabel = "Chi",
    -- ENERGY (secret bar) -- CHECKPOINT model. We can't read Energy, but an ability's
    -- clean "usable" flag flips on at its Energy cost, so "X is usable" => Energy >= X's
    -- cost. The highest such cost among currently-usable probes is a safe FLOOR on our
    -- Energy. The look-ahead seeds from that floor and subtracts each spender's cost (no
    -- regen assumed -- conservative), so it won't queue a Tiger Palm you can't afford.
    -- Costs shift with talents (Inner Peace cuts Tiger Palm by 5). Vivify is deliberately
    -- NOT a probe: Vivacious Vivification makes its cost/instant state vary.
    energyModel = {
        power = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3,
        probes = {
            { spell = 100780,  cost = 60, reduce = { [ID_INNERPEACE] = 5 } }, -- Tiger Palm
            { spell = 117952,  cost = 20 },  -- Crackling Jade Lightning
            { spell = 115078,  cost = 20 },  -- Paralysis
            { spell = 218164,  cost = 10 },  -- Detox
        },
        -- Look-ahead spend: Tiger Palm is the only Energy spender in the rotation
        -- (everything else costs Chi).
        costs = {
            TigerPalm = { base = 60, reduce = { [ID_INNERPEACE] = 5 } },
        },
    },

    -- Zenith's buff duration is SECRET in combat, but it's a fixed window: 15s base,
    -- +5s with Drinking Horn Cover. We seed a predicted timer when Zenith is cast and
    -- count it down, so a "Zenith remaining <= N" condition can gate the spend-before-it-
    -- ends lines. Keyed by cast key; `spell` is the buff whose remaining it drives.
    auraDurations = {
        Zenith = { spell = ID_ZENITH, base = 15, extend = { [ID_DRINKINGHORN] = 5 } },
    },
    cleaveAt = 2,   -- Shado-Pan uses the AoE priority for cleave as well
    aoeAt    = 3,
    comboStrikes = true,   -- mastery: engine never queues the same ability twice in a row
    condTags = { energy = true },   -- offer the "Energy %" condition (avoid-capping lines)
    activeHero = activeHero,   -- exposed for the Debug window
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "shadopan", label = "Shado-Pan" },
        { key = "conduit",  label = "Conduit" },
    },

    spells = {
        TigerPalm          = 100780,
        BlackoutKick       = 100784,
        RisingSunKick      = 107428,
        FistsOfFury        = 113656,
        SpinningCraneKick  = 101546,
        WhirlingDragonPunch = 152175,
        StrikeOfTheWindlord = 392983,
        RushingWindKick    = 1250566,   -- 12.1
        Zenith             = ID_ZENITH,  -- 12.1 Shado-Pan window (cast shares the buff ID; verify /prio spells)
        ZenithStomp        = 1272696,   -- 12.1
        TouchOfDeath       = ID_TOUCHOFDEATH,
        InvokeXuen         = 123904,
        CelestialConduit   = 443028,    -- Conduit of the Celestials
        SlicingWinds       = ID_SLICINGWINDS, -- Conduit
    },

    auras = {
        HeartOfJadeSerpent = ID_HEARTJADE,
        Zenith        = ID_ZENITH,
        UnbrokenRhythm = ID_UNBROKEN,
        ComboBreaker  = ID_COMBOBREAK,
        DanceOfChiJi  = ID_DANCECHIJI,
        RushingWindKick = ID_RUSHINGWIND,
    },
    setup = {
        { kind = "trackedAura", label = "Dance of Chi-Ji tracked", spell = ID_DANCECHIJI,
          hint = "Track Dance of Chi-Ji so free Spinning Crane Kick procs are detected." },
        { kind = "trackedAura", label = "Combo Breaker tracked", spell = ID_COMBOBREAK,
          hint = "Track Combo Breaker so free Blackout Kick procs are detected." },
        { kind = "trackedAura", label = "Rushing Wind Kick tracked", spell = ID_RUSHINGWIND,
          hint = "Track the Rushing Wind Kick 'available' buff so its line only fires when the proc is up." },
        { kind = "trackedAura", label = "Unbroken Rhythm tracked", spell = ID_UNBROKEN,
          hint = "Track Unbroken Rhythm so the empowered Spinning Crane Kick lines read right." },
        { kind = "trackedAura", label = "Zenith tracked", spell = ID_ZENITH,
          hint = "Track Zenith so the Zenith-window lines evaluate." },
        { kind = "trackedAura", label = "Heart of the Jade Serpent tracked", spell = ID_HEARTJADE,
          hint = "Track Heart of the Jade Serpent so Celestial Conduit timing reads right." },
        { kind = "trackedAura", label = "Touch of Death tracked", spell = ID_TOUCHOFDEATH,
          hint = "Track Touch of Death so execute availability is read from the Cooldown Manager." },
        { kind = "trackedAura", label = "Zenith tracked (for Charges)", spell = ID_ZENITH,
          hint = "Track Zenith in the Cooldown Manager so its charge count reads cleanly for a \"Charges >=\" condition." },
    },

    openerReady = { "InvokeXuen" },
    opener = { "InvokeXuen", "StrikeOfTheWindlord", "RisingSunKick", "FistsOfFury",
               "WhirlingDragonPunch", "BlackoutKick", "TigerPalm" },
    precombat = {},

    pickable = {
        "TigerPalm", "BlackoutKick", "RisingSunKick", "FistsOfFury", "SpinningCraneKick",
        "WhirlingDragonPunch", "StrikeOfTheWindlord", "RushingWindKick", "Zenith", "ZenithStomp",
        "TouchOfDeath", "InvokeXuen", "CelestialConduit", "SlicingWinds",
    },

    fillers = { [100780] = true },   -- Tiger Palm (Chi builder / filler)

    flash = {
        SpinningCraneKick = { type = "buffActive", spell = ID_DANCECHIJI },  -- free SCK
        BlackoutKick      = { type = "buffActive", spell = ID_COMBOBREAK },  -- free BoK
        RushingWindKick   = { type = "buffActive", spell = ID_RUSHINGWIND }, -- proc available
    },

    spellEffects = {
        BlackoutKick = { consume = { ID_COMBOBREAK } },
        SpinningCraneKick = { consume = { ID_DANCECHIJI } },
        RushingWindKick = { consume = { ID_RUSHINGWIND } },
        ZenithStomp = { grant = { ID_ZENITH } },
        CelestialConduit = { grant = { ID_HEARTJADE } },
        StrikeOfTheWindlord = { grant = { ID_HEARTJADE } },
        WhirlingDragonPunch = { grant = { ID_HEARTJADE } },
    },

    maelstromMax = 6,   -- Chi cap (generic "resource" fields)
    maelstromGen = { TigerPalm = 2 },   -- Tiger Palm builds Chi

    -- Zenith runs on 2 charges. Current charges are SECRET in combat (and the Cooldown
    -- Manager frame renders the recharge timer, not a clean count), so -- exactly like
    -- Lava Burst -- we PREDICT them: synced to the real count out of combat, decremented
    -- on cast, recharged on a timer, clamped by the readable castable state. `recharge`
    -- is a seed; the engine learns the real (haste'd) value out of combat.
    chargeTrack = {
        Zenith = { max = 2, recharge = 60 },
    },

    ResourceCost = function(_, key, sid, S)
        return chiCost(key, S)
    end,

    ResourceDelta = function(_, key, sid, S)
        return chiDelta(key, S)
    end,

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Heart of Jade Serpent", kind = "buff", spell = ID_HEARTJADE },
        { label = "Zenith",         kind = "buff", spell = ID_ZENITH },
        { label = "Unbroken Rhythm", kind = "buff", spell = ID_UNBROKEN },
        { label = "Combo Breaker",  kind = "buff", spell = ID_COMBOBREAK },
        { label = "Dance of Chi-Ji", kind = "buff", spell = ID_DANCECHIJI },
        { label = "Rushing Wind Kick", kind = "buff", spell = ID_RUSHINGWIND },
        { label = "Touch of Death", kind = "buff", spell = ID_TOUCHOFDEATH },
        { label = "Zenith charges", kind = "chargeClean", spell = ID_ZENITH },
        { label = "Zenith time left", kind = "auraRemain", spell = ID_ZENITH },
        { label = "Energy (est.)", kind = "energyFloor" },
        { label = "Tiger Palm usable", kind = "usableProbe", spell = 100780 },
        { label = "Fists of Fury",  kind = "cd",   spell = 113656 },
    },
    economy = {
        gen   = { "Tiger Palm", "Zenith Stomp", "Blackout Kick! + Energy Burst", "Slicing Winds + Airborne Rhythm", "Obsidian Spiral during Zenith" },
        spend = { "Rising Sun Kick", "Fists of Fury", "Blackout Kick", "Spinning Crane Kick", "Whirling Dragon Punch" },
    },
}

-- spec.priority is a live proxy: reads resolve to the ACTIVE hero's list for the
-- requested mode. Nothing writes to spec.priority (customization lives in
-- db.customPriorities), so an empty
-- backing table with an __index resolver is safe for the engine, editor, and export.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.shadopan
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
