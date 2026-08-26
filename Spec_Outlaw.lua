-- Spec_Outlaw.lua ---------------------------------------------------------------
-- Outlaw Rogue (spec 260), patch 12.1 (Midnight). FIRST PASS -- Trickster priority
-- built from the Wowhead 12.1 guide; Fatebound is deferred (rides the same core for
-- now). This ships primarily to (a) register the spec so the Rotation Debug window
-- turns on for Outlaw, and (b) verify which signals actually read in combat before
-- the rotation is tuned. Treat the priority as a working default, not final.
--
-- SIGNAL REALITY (the good news):
--   * COMBO POINTS are a DISCRETE class power -> they read CLEAN in combat (unlike
--     Rage/Energy/Maelstrom). So every combo-point gate below is EXACT: finishers at
--     >=6 CP, Adrenaline Rush at <=2 CP, Sinister Strike at <=5 CP, etc.
--   * ENERGY is a filling bar -> SECRET in combat. Builders therefore fail open (the
--     engine won't hard-gate them on an unreadable Energy value). Energy pooling
--     (Windwalker-style energyModel) is a later refinement.
--
-- ROLL THE BONES stage -- how we settled it (12.1 rework):
--   RtB grants ONE buff whose stage (1-4) is random and cumulative: One of a Kind (1) /
--   Double Trouble (2) / Triple Threat (3) / Jackpot (4). The rotation only cares about
--   the stage-2 breakpoint (reroll a stage-1 roll). Reading the stage directly FAILED:
--     - the stage buffs are secret by spell ID in combat (GetPlayerAuraBySpellID -> nil);
--     - index aura enumeration is blocked in combat;
--     - all stage buffs alias to one Cooldown-Manager bar, which only says "a roll is up".
--   WHAT WORKS: infer it from combo points (which DO read clean). Stage 2 makes Sinister
--   Strike generate an extra combo point, so a Sinister Strike that yields only its base
--   1 CP proves the roll is stage 1 -> reroll. See `spec.stageInfer` + Engine BuildState.
--   Disproof-only: stage 2+ can never look this low, so we never reroll a good roll.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

-- Verified IDs from the live Cooldown Viewer dump (2026-08-26) unless noted.
local ID_SINISTER   = 193315
local ID_PISTOLSHOT = 185763
local ID_DISPATCH   = 2098
local ID_BTE        = 315341   -- Between the Eyes (cast + target debuff)
local ID_ROLLBONES  = 1214909  -- Roll the Bones (Essential + TrackedBar; stage lives here)
local ID_SND        = 315496   -- Slice and Dice (cast + self buff)
local ID_BLADEFLURRY = 13877   -- Blade Flurry (TrackedBar)
local ID_BLADERUSH  = 271877
local ID_ADRENALINE = 13750    -- Adrenaline Rush (cast + buff)
local ID_KILLSPREE  = 51690
local ID_KEEPROLLING = 381989  -- Keep It Rolling
local ID_PREPARATION = 1277933
local ID_OPPORTUNITY = 279876  -- Opportunity (stacks: 3 / 6 gates)
local ID_LOADEDDICE = 256170
local ID_UNSEENBLADE = 441146  -- Trickster
local ID_FLAWLESS   = 441321   -- Flawless Form (Trickster)
local ID_ZEROIN     = 1259485  -- best-guess 4pc / BtE buff (VERIFY)
local ID_VANISH     = 1856
local ID_AMBUSH     = 8676
local ID_GHOSTLY    = 196937
local ID_THISTLETEA = 381623
-- ROLL THE BONES STAGE (12.1 rework, confirmed live 2026-08-26): RtB grants ONE named
-- buff whose identity IS the stage -- not six separate buffs, and the RtB bar (#1214909)
-- only ever reads "1 stack (assumed)", so stage must be read from WHICH buff is up.
-- These are mutually exclusive and NOT Cooldown-Manager tracked, so they rely on the
-- direct player-aura read (API.IsAuraActive's untracked fallback).
local ID_RTB_S1 = 1214933   -- "One of a Kind"  = stage 1
local ID_RTB_S2 = 1214934   -- "Double Trouble" = stage 2
local ID_RTB_S3 = 1214935   -- "Triple Threat"  = stage 3 (top; Wowhead "stage 3+")

-- All three stage buffs alias to the single Roll the Bones bar in the Cooldown Manager,
-- so their raw "active" read is just "a roll is up". Register them for NAME-based
-- disambiguation: PRIO reads which name the bar is rendering ("Double Trouble", ...) to
-- know the actual stage. This is the readable-in-combat signal (the aura is secret by ID).
API.linkedNameDisambig = API.linkedNameDisambig or {}
API.linkedNameDisambig[ID_RTB_S1] = true
API.linkedNameDisambig[ID_RTB_S2] = true
API.linkedNameDisambig[ID_RTB_S3] = true

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)    return { type = "buffActive",  spell = id } end
local function buffDown(id)  return { type = "buffMissing", spell = id } end
local function cdReady(id)   return { type = "cdReady",     spell = id } end
local function cdDown(id)    return { type = "cdNotReady",  spell = id } end
local function cpMin(n)      return { type = "resourceMin", v = n } end   -- combo points >= n
local function cpMax(n)      return { type = "resourceMax", v = n } end   -- combo points <= n
local function stacksMin(id, n) return { type = "stacksMin", spell = id, v = n } end
local function stacksMax(id, n) return { type = "stacksMax", spell = id, v = n } end

--------------------------------------------------------------------------------
-- Trickster priority (Wowhead 12.1). Combo-point gates are exact; RtB stage reads
-- from the CDM bar (#1214909). Same list drives ST and AoE, with Blade Flurry added
-- to the front of AoE (the only AoE adjustment Outlaw makes).
--------------------------------------------------------------------------------

-- STAGE via combo-point INFERENCE (the readable path -- see spec.stageInfer below and
-- Engine's BuildState). The stage buffs are secret by ID in combat and the bar only
-- reads "a roll is active", but combo points read clean and Roll the Bones stage 2 makes
-- Sinister Strike generate an extra CP -- so a Sinister Strike that yields only its base
-- 1 CP proves the roll is stage 1 (reroll). Stage 3 (Restless Blades) touches only secret
-- cooldowns, so we can't read it -> Keep It Rolling just runs on cooldown while a roll is up.
local function predStage2False() return { type = "predFalse", key = "rtbStage2" } end
local function predStage2True()  return { type = "predTrue",  key = "rtbStage2" } end
-- Reroll: no roll active, OR the current roll was inferred to be stage 1.
local function rtbReroll() return OR(buffDown(ID_ROLLBONES), predStage2False()) end
-- Keep It Rolling: on cooldown once we've CONFIRMED a good roll (stage 2+). We can't
-- read stage 3 (Restless Blades touches only secret cooldowns), so "stage 2+ confirmed"
-- is the best readable trigger -- and it's strictly better than firing on any roll,
-- since it never extends a stage-1 roll we're about to reroll.
local function rtbKeep()   return AND(buffUp(ID_ROLLBONES), predStage2True()) end

local st = {
    { spell = "RollTheBones",  cond = rtbReroll() },                                 -- reroll: nothing up, or inferred stage 1
    { spell = "KeepItRolling", cond = rtbKeep() },                                  -- Keep It Rolling on CD while a roll is up
    { spell = "Preparation",   cond = AND(cdDown(ID_BTE), cdDown(ID_ADRENALINE), cdDown(ID_KILLSPREE)) },
    { spell = "AdrenalineRush", cond = cpMax(2) },                                  -- on CD at <=2 CP
    { spell = "KillingSpree" },                                                     -- follows Adrenaline Rush
    { spell = "Dispatch",      cond = buffUp(ID_ZEROIN) },                          -- 4pc proc (VERIFY buff)
    { spell = "BladeRush" },                                                        -- on CD
    { spell = "BetweenTheEyes", cond = cpMin(6) },                                  -- finisher at >=6 CP
    { spell = "Dispatch",      cond = cpMin(6) },                                   -- finisher at >=6 CP
    { spell = "PistolShot",    cond = OR(stacksMin(ID_OPPORTUNITY, 6),
                                         AND(stacksMin(ID_OPPORTUNITY, 3), cpMin(1), cpMax(3))) },
    { spell = "SinisterStrike", cond = cpMax(5) },                                  -- builder at <=5 CP
}

local aoe = {
    { spell = "BladeFlurry",   cond = buffDown(ID_BLADEFLURRY) },                   -- keep the cleave buff up
    { spell = "RollTheBones",  cond = rtbReroll() },
    { spell = "KeepItRolling", cond = rtbKeep() },
    { spell = "Preparation",   cond = AND(cdDown(ID_BTE), cdDown(ID_ADRENALINE),
                                          cdDown(ID_KILLSPREE), cdDown(ID_BLADERUSH)) },
    { spell = "AdrenalineRush", cond = cpMax(2) },
    { spell = "KillingSpree" },
    { spell = "Dispatch",      cond = buffUp(ID_ZEROIN) },
    { spell = "BladeRush" },
    { spell = "BetweenTheEyes", cond = cpMin(6) },
    { spell = "Dispatch",      cond = cpMin(6) },
    { spell = "PistolShot",    cond = OR(stacksMin(ID_OPPORTUNITY, 6),
                                         AND(stacksMin(ID_OPPORTUNITY, 3), cpMin(1), cpMax(3))) },
    { spell = "SinisterStrike", cond = cpMax(5) },
}

local spec = {
    key      = "ROGUE_OUTLAW",
    label    = "Outlaw",
    className = "Rogue",
    specID   = 260,
    resource = COMBO,             -- COMBO POINTS: discrete -> readable in combat (exact gates)
    resourceLabel = "Combo Pts",
    maelstromMax = 7,             -- CP cap (readable PowerMax overrides; 6-7 with talents)

    -- STAGE INFERENCE: watch Sinister Strike's combo-point yield to detect Roll the Bones
    -- stage 1 (reroll). The engine records CP before the builder cast, waits `window`
    -- seconds for the (possibly double-strike) yield to land, then if the total yield is
    -- <= baseYield sets predFlags[flag]=false (proven stage 1). A `reset` cast (re-rolling)
    -- clears it back to unknown. Read in the rotation via predFalse("rtbStage2").
    stageInfer = {
        builder   = "SinisterStrike",
        reset     = "RollTheBones",
        flag      = "rtbStage2",
        window    = 0.5,   -- seconds to sum the yield (covers the double-strike)
        -- Double-strike marker: Sinister Strike awards 1 CP PER strike and, on its ~30%
        -- double-strike, grants Opportunity. So the engine reads Opportunity's stack gain
        -- to know how many strikes landed (1 or 2). A yield equal to the strike count =
        -- no Roll-the-Bones bonus = stage 1; a yield above it = stage 2+ (the extra CP).
        doubleMarker = { aura = ID_OPPORTUNITY },
    },

    -- Blade Flurry at 2+; no distinct cleave tier, so AoE mode covers 2+.
    cleaveAt = 2,
    aoeAt    = 2,

    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    priority = { st = st, aoe = aoe },

    -- Named presets surfaced in the condition editor (meaning, not mechanics).
    condPresets = {
        { key = "maxCP",     label = "Max combo points (>=6)", clause = cpMin(6) },
        { key = "lowCP",     label = "Low combo points (<=2)", clause = cpMax(2) },
        { key = "rtbReroll", label = "RtB needs reroll",       clause = rtbReroll() },
        { key = "rtbActive", label = "RtB roll active",        clause = rtbKeep() },
        { key = "opp6",      label = "Opportunity (6)",        clause = stacksMin(ID_OPPORTUNITY, 6) },
        { key = "opp3",      label = "Opportunity (3+)",       clause = stacksMin(ID_OPPORTUNITY, 3) },
    },

    auras = {
        SliceAndDice   = ID_SND,
        BladeFlurry    = ID_BLADEFLURRY,
        Opportunity    = ID_OPPORTUNITY,
        AdrenalineRush = ID_ADRENALINE,
        BetweenTheEyes = ID_BTE,
        RollTheBones   = ID_ROLLBONES,
        RtBOneOfAKind  = ID_RTB_S1,
        RtBDoubleTrouble = ID_RTB_S2,
        RtBTripleThreat = ID_RTB_S3,
        LoadedDice     = ID_LOADEDDICE,
        UnseenBlade    = ID_UNSEENBLADE,
        FlawlessForm   = ID_FLAWLESS,
    },

    setup = {
        { kind = "trackedAura", label = "Roll the Bones tracked", spell = ID_ROLLBONES,
          hint = "Track Roll the Bones (a Tracked Bar) so PRIO sees a roll is active. NOTE: the bar doesn't expose the stage -- PRIO reads that from which named buff is up (One of a Kind / Double Trouble / Triple Threat), automatically." },
        { kind = "trackedAura", label = "Opportunity tracked", spell = ID_OPPORTUNITY,
          hint = "Track Opportunity so its stack count (3 / 6) reads for the Pistol Shot lines." },
        { kind = "trackedAura", label = "Slice and Dice tracked", spell = ID_SND,
          hint = "Track Slice and Dice so its buff state reads." },
        { kind = "trackedAura", label = "Blade Flurry tracked", spell = ID_BLADEFLURRY,
          hint = "Track Blade Flurry so the AoE cleave-maintenance line reads." },
        { kind = "trackedAura", label = "Between the Eyes tracked", spell = ID_BTE,
          hint = "Track Between the Eyes so its debuff window reads." },
        { kind = "info", label = "Combo Points",
          hint = "No tracking needed -- combo points are a discrete resource PRIO reads directly, so finisher / builder combo-point gates are exact." },
    },

    spells = {
        SinisterStrike = ID_SINISTER,
        PistolShot     = ID_PISTOLSHOT,
        Dispatch       = ID_DISPATCH,
        BetweenTheEyes = ID_BTE,
        RollTheBones   = ID_ROLLBONES,
        SliceandDice   = ID_SND,
        BladeFlurry    = ID_BLADEFLURRY,
        BladeRush      = ID_BLADERUSH,
        AdrenalineRush = ID_ADRENALINE,
        KillingSpree   = ID_KILLSPREE,
        KeepItRolling  = ID_KEEPROLLING,
        Preparation    = ID_PREPARATION,
        Ambush         = ID_AMBUSH,
        Vanish         = ID_VANISH,
        GhostlyStrike  = ID_GHOSTLY,
        ThistleTea     = ID_THISTLETEA,
    },

    openerReady = { "AdrenalineRush" },
    opener = { "AdrenalineRush", "RollTheBones", "SliceandDice", "SinisterStrike",
               "PistolShot", "BetweenTheEyes" },
    openerAoe = { "AdrenalineRush", "RollTheBones", "SliceandDice", "BladeFlurry",
                  "SinisterStrike", "PistolShot", "BetweenTheEyes" },
    precombat = {},

    pickable = {
        "SinisterStrike", "PistolShot", "Dispatch", "BetweenTheEyes", "RollTheBones",
        "SliceandDice", "BladeFlurry", "BladeRush", "AdrenalineRush", "KillingSpree",
        "KeepItRolling", "Preparation", "Ambush", "Vanish", "GhostlyStrike", "ThistleTea",
    },

    fillers = { [ID_SINISTER] = true },   -- Sinister Strike is the no-cooldown builder

    flash = {
        PistolShot = { type = "buffActive", spell = ID_OPPORTUNITY },   -- free/empowered shot
    },

    OnCast = function(P, key, now) end,

    debug = {
        { label = "RtB stage 3 (TripleThreat)", kind = "buff", spell = ID_RTB_S3 },
        { label = "Roll the Bones (bar)", kind = "buff",  spell = ID_ROLLBONES },
        { label = "Slice and Dice",      kind = "buff",  spell = ID_SND },
        { label = "Blade Flurry",        kind = "buff",  spell = ID_BLADEFLURRY },
        { label = "Opportunity",         kind = "stacks", spell = ID_OPPORTUNITY },
        { label = "Adrenaline Rush",     kind = "buff",  spell = ID_ADRENALINE },
        { label = "Between the Eyes (t)", kind = "buff", spell = ID_BTE },
    },
    economy = {
        gen   = { "Sinister Strike", "Pistol Shot", "Ambush" },
        spend = { "Dispatch", "Between the Eyes", "Roll the Bones", "Slice and Dice" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug). THIS is the point of this build:
    -- watch which signals read live in combat before trusting the rotation.
    --   * buffs  -> API.IsAuraActive (what the COOLDOWN MANAGER reports active) + the
    --               rendered stack/stage count and its source.
    --   * rangeProbes.resource   -> combo points read straight off the power bar.
    --   * rangeProbes.directAura -> GetPlayerAuraBySpellID for the untracked RtB buffs
    --               (the only path that might survive combat). "readable" vs
    --               "PRESENT/secret" vs "absent" tells us if direct reads work.
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "RollTheBones", "KeepItRolling", "Preparation", "AdrenalineRush", "KillingSpree",
            "BladeRush", "BetweenTheEyes", "Dispatch", "PistolShot", "SinisterStrike", "BladeFlurry",
        },
        buffs = {
            { label = "RtB bar (assumed 1)",     spell = ID_ROLLBONES },   -- CDM bar: active, no stage
            { label = "One of a Kind (stg1)",    spell = ID_RTB_S1 },      -- via direct-read fallback
            { label = "Double Trouble (stg2)",   spell = ID_RTB_S2 },
            { label = "Triple Threat (stg3)",    spell = ID_RTB_S3 },
            { label = "Slice and Dice",          spell = ID_SND },
            { label = "Blade Flurry",            spell = ID_BLADEFLURRY },
            { label = "Opportunity",             spell = ID_OPPORTUNITY },
            { label = "Adrenaline Rush",         spell = ID_ADRENALINE },
            { label = "Loaded Dice",             spell = ID_LOADEDDICE },
            { label = "Between the Eyes (dbf)",  spell = ID_BTE },
            { label = "Unseen Blade",            spell = ID_UNSEENBLADE },
            { label = "Flawless Form",           spell = ID_FLAWLESS },
        },
        rangeProbes = {
            { label = "Combo Points",            kind = "resource" },
            -- Inferred RtB stage: false = proven stage 1 (reroll), true = proven high,
            -- unknown = not yet disproven (treated as good). Drives the reroll line.
            { label = "RtB stage2 (inferred)",   kind = "predFlag", key = "rtbStage2" },
            -- Direct-ID reads for the named RtB stage buffs (CDM doesn't track them).
            -- These confirm whether the direct read survives combat -- if it does, the
            -- reroll / Keep It Rolling lines work; if "PRESENT/secret", they can't.
            { label = "One of a Kind (direct)",  kind = "directAura", spell = ID_RTB_S1 },
            { label = "Double Trouble (direct)", kind = "directAura", spell = ID_RTB_S2 },
            { label = "Triple Threat (direct)",  kind = "directAura", spell = ID_RTB_S3 },
        },
    },
}

PRIO.specs[spec.specID] = spec
