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
local ID_LOADEDDICE = 256171   -- Loaded Dice BUFF aura (256170 is the talent); verified in-game
local ID_UNSEENBLADE = 441146  -- Trickster
local ID_FLAWLESS   = 441326   -- Flawless Form BUFF aura (Trickster; 441321 is the talent), verified in-game
local ID_FANGSTRIKE = 1301405  -- Fang Strike: 4pc tier buff -> next Dispatch is free/empowered
local ID_VANISH     = 1856
local ID_AMBUSH     = 8676
local ID_GHOSTLY    = 196937
local ID_STEALTH    = 1784     -- baseline Stealth
local ID_SUPERCHARGER = 470347 -- Supercharger talent: AR supercharges 2 combo points
local ID_DEALFATE   = 454419   -- Deal Fate (Fatebound): SS +1 CP when it grants Opportunity
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
local function glow(id)      return { type = "glowing", spell = id } end            -- button proc glow
local function enemiesMin(n) return { type = "enemiesMin", v = n } end               -- nameplate count >= n
local function lastCast(id)  return { type = "lastCast", spell = id } end            -- previous cast was this
local function oppMin(n)     return { type = "oppStacksMin", v = n } end             -- Opportunity charges >= n (editable)
local function cpEq(n)       return { type = "resourceEq", v = n } end               -- combo points == n
local function scMin(n)      return { type = "superChargeMin", v = n } end            -- supercharged CP >= n
local function talent(id)    return { type = "talentYes", spell = id } end            -- talent selected
local function preset(key)   return { type = "preset:" .. key } end                  -- named condPreset (editable chip)

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
-- Keep It Rolling is NOT auto-suggested. Whether it's worth extending depends on the
-- exact stage (2 vs 3 vs Jackpot), which we can't read -- but YOU can see it on the
-- buff. So instead of guessing, PRIO ALERTS when KiR is ready and the roll is a
-- confirmed good one (stage 2+), and leaves the call to you (see spec.alerts).

local function notStealthed() return { type = "notStealthed" } end

-- Default lists = user-tuned (0.4.11). A shared `core` (Roll the Bones down) drives every
-- mode/hero -- hero/mode-specific lines self-select (the Deal Fate line is inert without
-- that Fatebound talent; Blade Flurry is AoE-only). Sinister Strike at the bottom is the
-- baseline builder (Outlaw doesn't pool Energy). Stealth leads each mode but is gated per
-- the tuned lists (below). The shared core:
local core = {
    { spell = "RollTheBones",  cond = preset("rtbReroll") },                        -- reroll a stage-1 (or no) roll
    { spell = "Preparation",   cond = AND(cdDown(ID_BTE), cdDown(ID_ADRENALINE), cdDown(ID_KILLSPREE)) },
    { spell = "AdrenalineRush", cond = cpMax(2) },                                  -- on CD at <=2 CP
    { spell = "BetweenTheEyes", cond = AND(scMin(2), cpMin(6)) },                   -- spend a supercharge with BtE
    { spell = "KillingSpree",  cond = AND(scMin(1), cpMin(6)) },                    -- spend a supercharge with KS
    { spell = "KillingSpree",  cond = AND(buffUp(ID_ADRENALINE), cdDown(ID_ADRENALINE)) }, -- during the Adrenaline Rush window
    { spell = "Dispatch",      cond = buffUp(ID_FANGSTRIKE) },                      -- free Dispatch (4pc Fang Strike)
    { spell = "BladeRush" },                                                        -- on CD
    { spell = "BetweenTheEyes", cond = cpMin(6) },                                  -- finisher at >=6 CP
    { spell = "Dispatch",      cond = cpMin(6) },                                   -- finisher at >=6 CP
    { spell = "SinisterStrike", cond = AND(talent(ID_DEALFATE), preset("rtbGood"), cpEq(1)) }, -- Fatebound: Deal Fate build at 1 CP on a good roll
    { spell = "PistolShot",    cond = oppMin(6) },                                  -- dump at cap
    { spell = "PistolShot",    cond = AND(preset("oppUp"), cpMax(3)) },            -- or spend at low CP (Opportunity up)
    { spell = "SinisterStrike", cond = cpMax(5) },                                  -- baseline builder at <=5 CP
}

-- Stealth leads both modes (unusable in combat either way): ST only when NOT already
-- stealthed; AoE always, plus the two Blade Flurry lines. Rest is the shared core.
local st = { { spell = "Stealth", cond = notStealthed() } }
for i = 1, #core do st[#st + 1] = core[i] end

local aoe = {
    { spell = "Stealth" },
    { spell = "BladeFlurry", cond = buffDown(ID_BLADEFLURRY) },                     -- put the cleave buff up
    { spell = "BladeFlurry", cond = AND(buffUp(ID_BLADEFLURRY), enemiesMin(4), cpMax(4)) }, -- recast on 4+ at low CP
}
for i = 1, #core do aoe[#aoe + 1] = core[i] end

--------------------------------------------------------------------------------
-- HERO SPLIT. Trickster and Fatebound share the SAME default lists (the user tunes one
-- set; hero-specific lines like Deal Fate self-gate). Active hero is decided by a STRICT
-- known-check on the Trickster keystone Unseen Blade (441146) -- talent/spellbook state,
-- not an aura -- which Fatebound rogues lack; default is Trickster. Per-hero customization
-- still stores separately in db, so the two can diverge later without a code change.
--------------------------------------------------------------------------------
local heroLists = {
    trickster = { st = st, aoe = aoe },
    fatebound = { st = st, aoe = aoe },
}

local function activeHero()
    if API and API.IsKnownStrict and API.IsKnownStrict(ID_UNSEENBLADE) then return "trickster" end
    return "fatebound"
end

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
        -- Detection is by ORDER, not exact timing (the ms jitter is real -- instant lands
        -- 0-120ms, the double 200-330ms). Within `window` after the cast, the FIRST combo-
        -- point bump is the instant (first strike + stage bonus: +1 = stage 1, +2 = stage
        -- 2+); the SECOND bump is the double-strike (grants Opportunity -> a proc). Bumps
        -- after `window` (the next GCD's builder) are ignored.
        window = 0.6,
    },

    -- OPPORTUNITY charge tracking. The stack COUNT is secret in combat, so PRIO tracks it
    -- from reliable signals: a Sinister Strike DOUBLE-STRIKE grants Opportunity, and we
    -- detect that from the delayed combo-point bump (~200-330ms after the cast -- see the
    -- UNIT_POWER_UPDATE handler). Each proc = +3 with Fan the Hammer (cap 6), Pistol Shot
    -- spends 3, so the count is 0/3/6. The Pistol Shot GLOW anchors it: glow off => 0 (so
    -- drift can't accumulate), glowing while we somehow read 0 => floor at one proc. All
    -- amounts gate on Fan the Hammer (degrades to a single-charge buff without it).
    oppInfer = {
        aura      = ID_OPPORTUNITY,
        glowSpell = ID_PISTOLSHOT,     -- button glow = Opportunity present (>=3 with Fan the Hammer)
        spendKey  = "PistolShot",
        talent    = 381846,            -- Fan the Hammer (rank 2: +2 gain / +2 spend / max 6)
        gain = 3, spend = 3, cap = 6,  -- with Fan the Hammer
        gainBase = 1, spendBase = 1, capBase = 1,   -- without it (single charge)
    },

    -- ALERTS: advisory nudges, not auto-suggestions. Keep It Rolling's value depends on
    -- the exact stage (2 vs 3 vs Jackpot) -- which PRIO can't read but YOU can see on the
    -- buff -- so when it's ready on a confirmed good roll, PRIO prompts you to check and
    -- extend rather than pressing it for you.
    alerts = {
        { key = "keepItRolling",
          when = AND(cdReady(ID_KEEPROLLING), buffUp(ID_ROLLBONES), predStage2True()),
          text = "2+ roll detected \226\128\148 extend if it's a 3 or Jackpot",
          spell = "KeepItRolling" },
    },

    -- Blade Flurry at 2+; no distinct cleave tier, so AoE mode covers 2+.
    cleaveAt = 2,
    aoeAt    = 2,

    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    -- Hero split (see heroLists above). activeHero picks the live list; priorityVariants
    -- drives the Options hero picker + per-hero custom lists (Trickster tuned, Fatebound
    -- currently a clone to rework in-game).
    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "trickster", label = "Trickster" },
        { key = "fatebound", label = "Fatebound" },
    },

    -- Offer the Outlaw-only "Opportunity >=/<=" condition (reads PRIO's tracked 0/3/6
    -- count, not the Cooldown Manager's max-charges number).
    condTags = { outlaw = true },

    -- Energy is a fast-regen secondary, so a spender that's unusable ONLY for lack of
    -- Energy still shows (you'll press it when Energy ticks up) instead of collapsing to
    -- the cheapest builder. Combo-point affordability is enforced by the CP conditions.
    -- (Specs whose gating resource is BUILT -- Maelstrom, Holy Power -- leave this off so
    -- the usable check still withholds unaffordable spenders.)
    softPowerUsable = true,

    -- Named presets surfaced in the condition editor (meaning, not mechanics).
    condPresets = {
        { key = "maxCP",     label = "Max combo points (>=6)", clause = cpMin(6) },
        { key = "lowCP",     label = "Low combo points (<=2)", clause = cpMax(2) },
        { key = "rtbReroll", label = "RtB needs reroll",       clause = rtbReroll() },
        { key = "rtbGood",   label = "RtB good roll (2+)",     clause = AND(buffUp(ID_ROLLBONES), predStage2True()) },
        { key = "oppUp",     label = "Opportunity up (glow)",  clause = glow(ID_PISTOLSHOT) },
        { key = "fangStrike", label = "Fang Strike (4pc)",     clause = buffUp(ID_FANGSTRIKE) },
    },

    auras = {
        SliceAndDice   = ID_SND,
        BladeFlurry    = ID_BLADEFLURRY,
        Opportunity    = ID_OPPORTUNITY,
        AdrenalineRush = ID_ADRENALINE,
        BetweenTheEyes = ID_BTE,
        FangStrike     = ID_FANGSTRIKE,
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
          hint = "Track Roll the Bones in your Cooldown Manager -- as a bar OR a buff, either works -- so PRIO can see a roll is active (drives the reroll and the Keep It Rolling alert). The stage itself isn't read from here: PRIO infers it from your combo points automatically." },
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
        { kind = "trackedAura", label = "Fang Strike tracked (4-set)", spell = ID_FANGSTRIKE,
          hint = "Only if you have the 4-piece tier set: track Fang Strike so PRIO can suggest the free Dispatch while it's up. Harmless to skip if you don't have the set." },
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
        Stealth        = ID_STEALTH,
        GhostlyStrike  = ID_GHOSTLY,
        ThistleTea     = ID_THISTLETEA,
    },

    -- Opener (Icy Veins 12.1): pre-pull Adrenaline Rush -> Roll the Bones -> Slice and Dice,
    -- then Blade Rush / Sinister Strike to build, Between the Eyes at 6 CP, then hand off to
    -- the normal rotation (which fires Killing Spree after Adrenaline Rush, keeps building).
    openerReady = { "AdrenalineRush" },
    opener = { "AdrenalineRush", "RollTheBones", "SliceandDice",
               "BladeRush", "SinisterStrike", "SinisterStrike", "BetweenTheEyes" },
    openerAoe = { "AdrenalineRush", "RollTheBones", "SliceandDice", "BladeFlurry",
                  "BladeRush", "SinisterStrike", "SinisterStrike", "BetweenTheEyes" },
    precombat = {},

    pickable = {
        "SinisterStrike", "PistolShot", "Dispatch", "BetweenTheEyes", "RollTheBones",
        "SliceandDice", "BladeFlurry", "BladeRush", "AdrenalineRush", "KillingSpree",
        "KeepItRolling", "Preparation", "Ambush", "Vanish", "Stealth", "GhostlyStrike", "ThistleTea",
    },

    fillers = { [ID_SINISTER] = true },   -- Sinister Strike is the no-cooldown builder

    -- FINISHERS: spend ALL combo points and are castable at ANY combo points >= 1. The game
    -- reports their cost as the MAX, so the affordability gate would wrongly withhold them
    -- below max -- these are clamped to a 1-CP minimum so YOUR combo-point condition (e.g.
    -- "Dispatch at >= 5") decides when to spend. (Slice and Dice is a finisher too.)
    finishers = { Dispatch = true, BetweenTheEyes = true, SliceandDice = true },

    flash = {
        PistolShot = { type = "buffActive", spell = ID_OPPORTUNITY },   -- free/empowered shot
    },

    -- SUPERCHARGED COMBO POINTS (Supercharger talent 470347). Adrenaline Rush supercharges 2
    -- combo points; each DAMAGING finisher (Dispatch, Between the Eyes, Killing Spree) consumes
    -- one. The count is secret in combat, so PRIO predicts it from your own casts (reliable --
    -- no drift). Inert unless talented. Reset to 0 on combat end (Engine). Read via the
    -- "Supercharged CP >=/<=/=" conditions and S.superCharge.
    OnCast = function(P, key, now)
        if not API.IsKnown(ID_SUPERCHARGER) then return end
        P.superCharge = P.superCharge or 0
        if key == "AdrenalineRush" then
            P.superCharge = 2                                   -- AR supercharges 2 (rank 2/2)
        elseif key == "Dispatch" or key == "BetweenTheEyes" or key == "KillingSpree" then
            if P.superCharge > 0 then P.superCharge = P.superCharge - 1 end
        end
    end,

    -- LOOK-AHEAD combo-point modelling: how each cast changes combo points, so the queue
    -- (the "next" icons) predicts building toward a finisher and spending it. Combo points
    -- read clean, so the sim seeds from the real value and advances by this each pick.
    --   * Builders GENERATE: Sinister Strike 1 (2 at RtB stage 2+), Ambush 2, and an
    --     Opportunity-empowered Pistol Shot with Fan the Hammer fires extra bullets (3 CP).
    --   * Finishers SPEND ALL: Dispatch / Between the Eyes / Slice and Dice -> 0.
    --   * Roll the Bones is NOT a finisher (costs Energy, no combo points) -> no change;
    --     nor do Adrenaline Rush / Blade Rush / Killing Spree / Keep It Rolling / Preparation.
    ResourceDelta = function(_, key, sid, S)
        if key == "Dispatch" or key == "BetweenTheEyes" or key == "SliceandDice" then
            return -(S.maelstrom or 0)                       -- finisher: spend all combo points
        elseif key == "SinisterStrike" then
            return (S.predFlags and S.predFlags.rtbStage2 == true) and 2 or 1
        elseif key == "PistolShot" then
            local opp = (PRIO.Engine and PRIO.Engine.P and PRIO.Engine.P.stacks
                         and PRIO.Engine.P.stacks[ID_OPPORTUNITY]) or 0
            if opp > 0 and API.IsTalentSelected(381846) then return 3 end   -- Fan the Hammer empowered
            return 1
        elseif key == "Ambush" then
            return 2
        end
        return 0
    end,

    debug = {
        { label = "Roll the Bones (active)", kind = "buff", spell = ID_ROLLBONES },
        { label = "Slice and Dice",      kind = "buff",  spell = ID_SND },
        { label = "Blade Flurry",        kind = "buff",  spell = ID_BLADEFLURRY },
        { label = "Adrenaline Rush",     kind = "buff",  spell = ID_ADRENALINE },
        { label = "Between the Eyes (t)", kind = "buff", spell = ID_BTE },
    },
    economy = {
        gen   = { "Sinister Strike", "Pistol Shot", "Ambush" },
        spend = { "Dispatch", "Between the Eyes", "Roll the Bones", "Slice and Dice" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug): the live signals the rotation
    -- actually reads. abilities = cooldown/usable; buffs = what the Cooldown Manager
    -- reports active; rangeProbes = combo points, the inferred roll state, and the
    -- Opportunity boolean (from the Pistol Shot glow).
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "RollTheBones", "KeepItRolling", "Preparation", "AdrenalineRush", "KillingSpree",
            "BladeRush", "BetweenTheEyes", "Dispatch", "PistolShot", "SinisterStrike", "BladeFlurry",
        },
        buffs = {
            { label = "Roll the Bones (active)", spell = ID_ROLLBONES },   -- a roll is up (bar/buff)
            { label = "Slice and Dice",          spell = ID_SND },
            { label = "Blade Flurry",            spell = ID_BLADEFLURRY },
            { label = "Adrenaline Rush",         spell = ID_ADRENALINE },
            { label = "Between the Eyes (dbf)",  spell = ID_BTE },
        },
        predStacks = {
            -- Tracked Opportunity charges (0/3/6 with Fan the Hammer): +proc on a detected
            -- double-strike, -3 on Pistol Shot, glow-anchored (off => 0).
            { label = "Opportunity (charges)",   spell = ID_OPPORTUNITY },
        },
        glows = {
            { label = "Pistol Shot (Opp up)",    spell = ID_PISTOLSHOT },   -- glow = Opportunity present (>=3)
        },
        rangeProbes = {
            { label = "Combo Points",            kind = "resource" },
            -- Read from the instant combo-point bump: false = stage 1 (reroll), true =
            -- stage 2+ (good), unknown = not read yet this roll.
            { label = "Roll good? (read)",       kind = "predFlag", key = "rtbStage2" },
            -- Supercharger (470347): predicted 0-2, set to 2 by Adrenaline Rush, -1 per
            -- damaging finisher (Dispatch / Between the Eyes / Killing Spree).
            { label = "Supercharged CP",         kind = "predCount", field = "superCharge" },
        },
    },
}

-- spec.priority is a live proxy resolving to the ACTIVE hero's list for a mode (editor /
-- export / any direct read). Customization lives in db.customPriorities, so the backing
-- table stays empty and the __index resolver is safe.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.trickster
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
