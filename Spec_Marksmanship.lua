-- Spec_Marksmanship.lua --------------------------------------------------------
-- Marksmanship Hunter (spec 254), patch 12.1 (Midnight). TRACKING PASS: getting the
-- abilities, buffs, and predicted cooldowns right first (verify with /prio spells and
-- /prio tracked); the rotation below is a Sentinel first pass to tune afterwards.
--
-- MM plays SENTINEL in ~all content (default here); Dark Ranger is the secondary tree.
-- The Sentinel core loop: spend Precise Shots ASAP -> that applies Sentinel's Mark to the
-- target (~40% ST, ~90% in Trueshot) -> Aimed Shot into a marked target consumes it and
-- procs Lunar Storm. So "spend Precise Shots" and "Aimed Shot the Mark" are the priorities.
--
-- SIGNAL REALITY (what reads in combat -- same rules as Beast Mastery):
--   * FOCUS value is SECRET -> spenders gate on affordability (the game's clean
--     insufficient-power flag) and show dimmed when you can't afford them (softPowerUsable).
--   * Aimed Shot CHARGES: the exact count reads via the charge-aware cooldown; the recharge
--     TIME is secret, so charge gates use the count. Aimed Shot recharge is HASTED.
--   * PROC / DEBUFF buffs read from the Cooldown Manager: Precise Shots, Trick Shots,
--     the target's mark (Spotter's Mark at base -> Sentinel's Mark with the hero talent),
--     Bullseye (Trueshot stacks), Unstable Trigger (Explosive Shot recast), Trueshot.
--     Add them via /prio setup.
--   * MARK UPGRADE: Spotter's Mark becomes Sentinel's Mark via a specific Sentinel node --
--     without that node (or on a partial hero tree) you have Spotter's Mark, so markUp/
--     markDown read either. Likewise Kill Shot / Black Arrow / apex-talent lines stay inert
--     (IsKnown) until learned, so the one list scales from a partial build up to max.
--   * Only TRUESHOT gets a predicted cooldown (2 min), for the "Trueshot soon" hold/delay
--     logic. Everything else rides on booleans (buffs) + charges + the live ready flag --
--     no cooldown modelling, since it's not worth the effort for short cooldowns.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local FOCUS = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2

-- Castable IDs (core ones are stable/well-known; verify with /prio spells).
local ID_AIMEDSHOT   = 19434
local ID_RAPIDFIRE   = 257044
local ID_ARCANESHOT  = 185358
local ID_STEADYSHOT  = 56641
local ID_MULTISHOT   = 257620
local ID_EXPLOSIVE   = 212431    -- Explosive Shot (Unstable Trigger -> 2 casts)
local ID_VOLLEY      = 260243
local ID_TRUESHOT    = 288613    -- cast AND the Trueshot buff
local ID_KILLSHOT    = 53351
local ID_MOONCHAKRAM = 1264902   -- Moonlight Chakram (Sentinel) -- verified via guide 2026-08-31
local ID_BLACKARROW  = 466930    -- Dark Ranger
local ID_WAILINGARROW = 392060   -- Dark Ranger
local ID_HUNTERSMARK = 257284

-- Buff / debuff IDs -- verified from the live Cooldown Viewer dump 2026-08-31 unless noted.
local ID_PRECISE     = 260240    -- Precise Shots (spend proc)
local ID_TRICK       = 257621    -- Trick Shots (AoE)
local ID_SPOTTERMARK = 1219616   -- Spotter's Mark (target debuff -> Aimed Shot) -- the BASE mark
local ID_SENTMARK    = 1266960   -- Sentinel's Mark -- REPLACES Spotter's Mark with the Sentinel hero talent (not present pre-hero, e.g. while levelling)
local ID_BULLSEYE    = 204089    -- Bullseye (Trueshot-hold stacks)
local ID_LOCKLOAD    = 194595    -- Lock and Load (instant Aimed Shot proc)
local ID_UNSTABLE    = 473520    -- Unstable Trigger (bar) -- enables the Explosive Shot recast
local ID_BULLETSTORM = 389019    -- Bulletstorm (bar) -- Aimed Shot stacking buff
-- Not present at low level / without the talent (kept for reference, not tracked):
-- Streamline 260242, Lunar Storm (Sentinel proc), Master Marksman 260309.

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)      return { type = "buffActive",   spell = id } end
local function buffDown(id)    return { type = "buffMissing",  spell = id } end
local function debuffDown(id)  return { type = "debuffMissing", spell = id } end
local function debuffUp(id)    return { type = "debuffActive", spell = id } end
local function usable(id)      return { type = "usable",       spell = id } end
local function petMissing()    return { type = "petMissing" } end
local function petDead()       return { type = "petDead" } end
-- The target's "mark" -- Spotter's Mark at base, Sentinel's Mark with the hero talent.
-- Reads whichever is present, so it works while levelling and at max.
local function markUp()   return OR(debuffUp(ID_SPOTTERMARK), debuffUp(ID_SENTMARK)) end
local function markDown() return AND(debuffDown(ID_SPOTTERMARK), debuffDown(ID_SENTMARK)) end

--------------------------------------------------------------------------------
-- Sentinel first-pass priority (Icy Veins 12.1 ST list). Spend Precise Shots (Kill /
-- Arcane) to seed Sentinel's Mark, then Aimed Shot the Mark. AoE folds in Multi-Shot /
-- Trick Shots. TO TUNE after the IDs are verified in-game.
--------------------------------------------------------------------------------
local st = {
    { spell = "CallPet",       cond = petMissing() },                 -- no pet up -> summon
    { spell = "RevivePet",     cond = petDead() },                    -- pet dead -> revive
    { spell = "HuntersMark",   cond = debuffDown(ID_HUNTERSMARK) },   -- keep the 3% debuff up
    { spell = "ExplosiveShot" },                                      -- on CD (2 casts, Unstable Trigger)
    { spell = "Volley" },                                             -- on CD
    { spell = "Trueshot" },                                           -- major CD (hold last for 30 Bullseye)
    { spell = "RapidFire" },                                          -- on CD, builds Precise
    { spell = "KillShot",   cond = AND(buffUp(ID_PRECISE), usable(ID_KILLSHOT)) },   -- spend Precise (execute)
    { spell = "ArcaneShot", cond = AND(buffUp(ID_PRECISE), usable(ID_ARCANESHOT)) }, -- spend Precise -> apply Sentinel's Mark
    { spell = "AimedShot",  cond = usable(ID_AIMEDSHOT) },            -- on CD (charges), consumes Sentinel's Mark
    { spell = "MoonlightChakram", cond = usable(ID_MOONCHAKRAM) },    -- Sentinel filler
    { spell = "SteadyShot" },                                         -- Focus filler (resource-starved)
}

local aoe = {
    { spell = "CallPet",       cond = petMissing() },
    { spell = "RevivePet",     cond = petDead() },
    { spell = "HuntersMark",   cond = debuffDown(ID_HUNTERSMARK) },
    { spell = "ExplosiveShot" },
    { spell = "Volley" },
    { spell = "Trueshot" },
    { spell = "MultiShot",  cond = buffDown(ID_TRICK) },              -- put Trick Shots up
    { spell = "RapidFire",  cond = buffUp(ID_TRICK) },               -- cleaves with Trick Shots
    { spell = "AimedShot",  cond = AND(buffUp(ID_TRICK), usable(ID_AIMEDSHOT)) }, -- cleaves with Trick Shots
    { spell = "MultiShot",  cond = buffUp(ID_PRECISE) },             -- spend Precise Shots
    { spell = "MoonlightChakram", cond = usable(ID_MOONCHAKRAM) },
    { spell = "SteadyShot" },
}

local spec = {
    key      = "HUNTER_MARKSMANSHIP",
    label    = "Marksmanship",
    className = "Hunter",
    specID   = 254,
    resource = FOCUS,
    resourceLabel = "Focus",
    maelstromMax = 100,           -- Focus cap (secret in combat; resource readout only)
    softPowerUsable = true,       -- Focus secret -> keep spenders visible; unaffordable ones show dimmed

    -- Only ST and AoE (AoE == ST without Trick Shots; the Multi-Shot / Trick Shots lines
    -- self-gate). cleaveAt == aoeAt collapses the middle Cleave tier.
    cleaveAt = 2,
    aoeAt    = 2,
    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    condTags = { pet = true },

    -- Relevant buffs (selectable in the condition editor). Flagged IDs need /prio tracked
    -- verification. Sentinel's Mark is a target DEBUFF; the rest are self buffs.
    auras = {
        PreciseShots  = ID_PRECISE,
        TrickShots    = ID_TRICK,
        SpottersMark  = ID_SPOTTERMARK,
        SentinelsMark = ID_SENTMARK,
        Bullseye      = ID_BULLSEYE,
        Trueshot      = ID_TRUESHOT,
        LockAndLoad   = ID_LOCKLOAD,
        UnstableTrigger = ID_UNSTABLE,
        Bulletstorm   = ID_BULLETSTORM,
        HuntersMark   = ID_HUNTERSMARK,
    },

    setup = {
        { kind = "trackedAura", label = "Precise Shots tracked", spell = ID_PRECISE,
          hint = "Track Precise Shots -- the core Sentinel proc. PRIO spends it (Kill / Arcane Shot) to seed Sentinel's Mark." },
        { kind = "trackedAura", label = "Spotter's Mark tracked", spell = ID_SPOTTERMARK,
          hint = "Track Spotter's Mark (the target debuff) so PRIO knows when to Aimed Shot the marked target. With the Sentinel hero talent this becomes Sentinel's Mark -- track that instead once you have it." },
        { kind = "trackedAura", label = "Unstable Trigger tracked", spell = ID_UNSTABLE, optional = true,
          hint = "Track Unstable Trigger so PRIO knows when Explosive Shot can be recast (the double-cast)." },
        { kind = "trackedAura", label = "Trick Shots tracked", spell = ID_TRICK,
          hint = "Track Trick Shots so the AoE Aimed / Rapid Fire cleave lines read." },
        { kind = "trackedAura", label = "Trueshot tracked", spell = ID_TRUESHOT, optional = true,
          hint = "Track Trueshot so 'during Trueshot' lines (Moonlight Chakram, Precise-heavy) read." },
        { kind = "trackedAura", label = "Bullseye tracked", spell = ID_BULLSEYE, optional = true,
          hint = "Track Bullseye so the 'hold Trueshot for 30 stacks' logic reads. Verify the ID with /prio tracked." },
        { kind = "trackedAura", label = "Hunter's Mark tracked", spell = ID_HUNTERSMARK,
          hint = "Track Hunter's Mark so PRIO reapplies the 3% damage-taken debuff on a target that's missing it." },
        { kind = "info", label = "Focus",
          hint = "Focus is secret in combat -- PRIO doesn't read the number. Spenders show, dimmed while the game's insufficient-power flag says you can't afford them yet." },
        { kind = "info", label = "Pet",
          hint = "The top of each list checks your pet: Call Pet if it's missing, Revive Pet if it's dead." },
    },

    spells = {
        AimedShot     = ID_AIMEDSHOT,
        RapidFire     = ID_RAPIDFIRE,
        ArcaneShot    = ID_ARCANESHOT,
        SteadyShot    = ID_STEADYSHOT,
        MultiShot     = ID_MULTISHOT,
        ExplosiveShot = ID_EXPLOSIVE,
        Volley        = ID_VOLLEY,
        Trueshot      = ID_TRUESHOT,
        KillShot      = ID_KILLSHOT,
        MoonlightChakram = ID_MOONCHAKRAM,
        BlackArrow    = ID_BLACKARROW,
        WailingArrow  = ID_WAILINGARROW,
        HuntersMark   = ID_HUNTERSMARK,
        CallPet       = 883,
        RevivePet     = 982,
        MendPet       = 136,
    },

    -- Opener (Icy Veins 12.1): Hunter's Mark pre-pull, Aimed Shot ~2.5s pre-pull, then
    -- Explosive x2, Volley, Trueshot, Rapid Fire, Aimed, Arcane, Aimed.
    openerReady = { "Trueshot" },
    opener = { "AimedShot", "ExplosiveShot", "ExplosiveShot", "Volley", "Trueshot",
               "RapidFire", "AimedShot", "ArcaneShot", "AimedShot" },

    precombat = {
        { spell = "HuntersMark", aura = ID_HUNTERSMARK },
    },

    pickable = {
        "AimedShot", "RapidFire", "ArcaneShot", "MultiShot", "ExplosiveShot", "Volley",
        "Trueshot", "KillShot", "MoonlightChakram", "BlackArrow", "WailingArrow",
        "SteadyShot", "HuntersMark", "CallPet", "RevivePet", "MendPet",
    },

    -- Aimed Shot runs on charges and recharges with haste (the recharge TIME is secret in
    -- combat, so charge gates use the readable count -- same as BM's Barbed Shot / KC).
    chargeTrack = {
        AimedShot = { max = 2, recharge = 12, hasted = true },
    },

    -- Predicted cooldowns. Trueshot (2 min) for its hold/delay logic, and Explosive Shot
    -- (30s) for lining Explosives up with Trueshot. Explosive Shot uses `window = 3`:
    -- Unstable Trigger lets you fire it a SECOND time within 3s, but the 30s runs from the
    -- FIRST press -- so a re-press inside the window doesn't restart the timer. Everything
    -- else leans on booleans (buffs) + charges, anchored to the live ready flag.
    cooldownTrack = {
        Trueshot      = { base = 120 },
        ExplosiveShot = { base = 30, window = 3 },
    },

    fillers = { [ID_STEADYSHOT] = true },   -- Steady Shot is the no-cooldown Focus filler

    flash = {
        KillShot   = { type = "buffActive", spell = ID_PRECISE },   -- spend Precise (execute)
        ArcaneShot = { type = "buffActive", spell = ID_PRECISE },   -- spend Precise
        AimedShot  = { type = "buffActive", spell = ID_LOCKLOAD },  -- Lock and Load instant (if tracked)
    },

    -- Precise Shots: generated by Aimed Shot / Rapid Fire, spent by Arcane / Kill Shot /
    -- Multi-Shot. Trick Shots: from Multi-Shot, consumed by Aimed / Rapid Fire.
    spellEffects = {
        AimedShot  = { grant = { ID_PRECISE }, consume = { ID_TRICK } },
        RapidFire  = { grant = { ID_PRECISE }, consume = { ID_TRICK } },
        MultiShot  = { grant = { ID_TRICK },   consume = { ID_PRECISE } },
        ArcaneShot = { consume = { ID_PRECISE } },
        KillShot   = { consume = { ID_PRECISE } },
    },

    OnCast = function(P, key, now) end,

    --------------------------------------------------------------------------------
    -- Debug metadata (/prio debug): the live tracking signals.
    --------------------------------------------------------------------------------
    debug = {
        { label = "Aimed Shot (chg/next)", kind = "chargeTime", key = "AimedShot", spell = ID_AIMEDSHOT },
        { label = "Precise Shots",         kind = "buff", spell = ID_PRECISE },
        { label = "Spotter's Mark",        kind = "buff", spell = ID_SPOTTERMARK },
        { label = "Bullseye",              kind = "buff", spell = ID_BULLSEYE },
        { label = "Unstable Trigger",      kind = "buff", spell = ID_UNSTABLE },
        { label = "Explosive Shot (CD)",   kind = "cdRemain", spell = ID_EXPLOSIVE },
        { label = "Trueshot (CD left)",    kind = "cdRemain", spell = ID_TRUESHOT },
    },
    economy = {
        gen   = { "Steady Shot", "Auto-shot" },
        spend = { "Aimed Shot", "Arcane Shot", "Kill Shot", "Multi-Shot" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug): cooldown/usable + charges/seconds
    -- per ability, and the buff/debuff reads. Use this to verify the IDs in combat.
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "Trueshot", "ExplosiveShot", "Volley", "RapidFire", "AimedShot",
            "ArcaneShot", "KillShot", "MoonlightChakram", "SteadyShot",
        },
        buffs = {
            { label = "Precise Shots",       spell = ID_PRECISE },
            { label = "Spotter's Mark (t)",  spell = ID_SPOTTERMARK },
            { label = "Trick Shots",         spell = ID_TRICK },
            { label = "Bullseye",            spell = ID_BULLSEYE },
            { label = "Unstable Trigger",    spell = ID_UNSTABLE },
            { label = "Hunter's Mark (tgt)", spell = ID_HUNTERSMARK },
            { label = "Trueshot (active)",   spell = ID_TRUESHOT },
        },
        rangeProbes = {
            { label = "Focus", kind = "resource" },
        },
    },

    priority = { st = st, aoe = aoe },
}

PRIO.specs[spec.specID] = spec
