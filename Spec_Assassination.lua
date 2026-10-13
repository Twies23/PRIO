-- Spec_Assassination.lua -------------------------------------------------------
-- Assassination Rogue (spec 259), patch 12.1 (Midnight). BOTH hero trees built:
-- Deathstalker and Fatebound (real, separate lists -- they genuinely differ).
--
-- Built from: Icy Veins 12.1 rotation page (updated 2026-08-10, per-hero tab panels),
-- Wowhead 12.1.0 rotation (2026-09-06), Maxroll 12.1.5, AND three live +22 M+ logs
-- (VHRPMJNnBZhCTAY8 / Z7WpDarfthvxTj4H / WY3Bhvg8DC7HTpKM -- two Fatebound, one
-- Deathstalker). Where the guides disagreed, the logs broke the tie; those calls are
-- marked LOG-CONFIRMED below.
--
-- SIGNAL REALITY:
--   * COMBO POINTS are a DISCRETE class power -> read CLEAN in combat. Every CP gate
--     here is EXACT. Max CP is 7 (Deeper Stratagem +1, Sanguine Stratagem +1).
--     LOG-CONFIRMED: every Envenom in the sample was cast at 5, 6 or 7 CP.
--   * ENERGY is a filling bar -> SECRET in combat. Assassination is energy-locked
--     rather than GCD-locked, and the guides' whole "pool energy / chain Envenom in
--     the last 1-2s of the buff" skill expression is therefore NOT MODELLABLE. We set
--     softPowerUsable so a spender that is unusable ONLY for lack of energy still
--     shows (the game's insufficient-power flag is the indicator), and we do NOT try
--     to predict energy. Thistle Tea is likewise left OUT of the priority: its rule is
--     "when low on Energy", which we cannot read -- use the auto-cast talent version
--     (it fires below 30 energy by itself; the guides say it makes no difference).
--   * AURAS need Cooldown-Manager tracking (API.IsAuraActive reads CDM frames; direct
--     aura reads are dead in combat). All gated auras are in the user's CDM dump.
--
-- THREE 12.1 REWORKS THAT BREAK ANY TWW-ERA LIST (all log-confirmed):
--   1. CRIMSON TEMPEST (1247227) IS A BUILDER, NOT A FINISHER. 60 Energy, GENERATES
--      1 CP, no CP cost, no cooldown, 10 yd. It absorbed Indiscriminate Carnage: it
--      spreads your existing bleeds (including Improved-Garrote-empowered Garrotes) to
--      nearby targets. LOG-CONFIRMED: Crimson Tempest casts carry NO combo-point spend
--      in classResources, while Envenom/Rupture do. It must NOT be in `finishers`.
--   2. SLICE AND DICE IS NEVER CAST past the opener -- Cut to the Chase is baseline
--      and Envenom extends it. LOG-CONFIRMED: 1 cast / 94.7% uptime and 2 casts /
--      97.5% uptime across the logs. So there is ONE buffDown line that fires at most
--      once, not a maintenance line.
--   3. CAUSTIC SPATTER moved off Shiv onto ENVENOM + KINGSBANE and no longer needs
--      active bleeds. Nothing to gate -- it rides Envenom, which we already spam.
--   Also: Deathmark no longer duplicates bleeds (now +75% to Rupture/Garrote/poisons,
--   16s, 2 min CD -- LOG-CONFIRMED at ~120s intervals) and Deathstalker's Mark is now
--   applied by GARROTE, not Ambush.
--
-- AMBUSH IS DELIBERATELY ABSENT from both lists. Icy Veins still lists it, but Wowhead
-- says Vanish->Garrote is "the only remaining interaction with Stealth in Midnight for
-- Assassination", and all three logs cast Ambush ZERO times. In a stealth/Vanish window
-- you want Garrote (Improved Garrote), not Ambush. It stays pickable for manual use.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

-- IDs. Taken from the user's live Cooldown Viewer dump (authoritative for what PRIO can
-- READ in game). NOTE: several of these differ from the ids the same auras carry in
-- Warcraft Logs (Darkest Night CDM 457058 vs log 457280; Lingering Darkness 457056 vs
-- 457273; Caustic Spatter 421975 vs 421976/421979). That is the known two-namespace
-- split -- always trust the CDM dump here and treat log ids as rotation evidence only.
local ID_MUTILATE   = 1329     -- builder, 50 Energy, +2 CP (log also shows 5374/27576 hits)
local ID_GARROTE    = 703      -- Essential + TrackedBuff. 45 Energy, +1 CP, 18s, 6s CD
local ID_RUPTURE    = 1943     -- Essential + TrackedBuff. finisher, 4s + 4s per CP
local ID_ENVENOM    = 32645    -- Essential + TrackedBuff. finisher, 35 Energy
local ID_DEATHMARK  = 360194   -- Essential + TrackedBuff. 2 min CD, 16s
local ID_FOK        = 51723    -- Essential. 35 Energy, +1 CP, 8 yd
local ID_CRIMSONTEMP = 1247227 -- Essential. 60 Energy, +1 CP -- A BUILDER (see header)
local ID_SND        = 315496   -- Essential + TrackedBuff. opener-only (Cut to the Chase)
local ID_MARKDEATH  = 1293340  -- Essential. Deathstalker mark-swap: 25 Energy, 20s CD, OFF-GCD
local ID_SHIV       = 5938     -- Utility. 30 Energy, +1 CP
local ID_VANISH     = 1856     -- Utility + TrackedBuff. 2 min CD -- Improved Garrote enabler
local ID_STEALTH    = 1784     -- TrackedBuff
-- Improved Garrote: the PASSIVE/talent id, and the one the Cooldown Manager tracks
-- (TrackedBar #381632) -- so this is what PRIO reads. The buff the game applies
-- carries UnitAuraID 392403, but that needs a direct aura read, which is dead in
-- combat. Do not "fix" this to 392403: there is no CDM frame for it.
local ID_IMPGARROTE = 381632
local ID_KINGSBANE  = 385627   -- Essential + TrackedBuff. 1 min CD, +1 CP
local ID_KINGSBANEBUFF = 394095 -- TrackedBuff. the stacking Kingsbane buff
local ID_THISTLETEA = 1298826  -- Essential. energy cooldown -- see the noPower gate below
-- Scent of Blood: 4 stacks per bleeding target, CAP 20 (log-confirmed -- the observed
-- stack values are 0/1/4/8/12/16/20, matching "5 Ruptures to reach max stacks").
local ID_SCENT      = 381799   -- TrackedBuff
local ID_CAUSTIC    = 421975   -- TrackedBuff. now applied by Envenom/Kingsbane, not Shiv
local ID_AMPPOISONDOT = 383414 -- TrackedBuff. the stacking Amplifying Poison debuff
local ID_COLDBLOODED = 382245  -- TrackedBuff. Cold Blooded Killer
local ID_UNSHAKEABLE = 1248774 -- TrackedBuff. Unshakeable Drive

-- Deathstalker
local ID_DSMARK     = 457052   -- TrackedBuff. Deathstalker's Mark (3 stacks, applied by Garrote)
local ID_DARKNIGHT  = 457058   -- TrackedBuff. Darkest Night -- spend on a max-CP Envenom
local ID_LINGERDARK = 457056   -- TrackedBuff. Lingering Darkness (passive damage node)
local ID_MOMENTUM   = 457067   -- TrackedBuff. Momentum of Despair (AoE crit, feeds Seal Fate)

-- Fatebound
local ID_HANDOFFATE = 452536   -- keystone: flips a coin per 5+ CP finisher (hero detection)
local ID_DEALFATE   = 454419   -- Seal Fate extra-CP chance (12.1 nerfed 100% -> 60%)

-- Poisons (pre-combat, not rotational). 2823 = the castable weapon buff; 2818 = the
-- target DoT that the CDM dump lists. Amplifying 381664 is the weapon buff.
local ID_DEADLYPOISON = 2823
local ID_AMPPOISON    = 381664
local ID_ATROPHIC     = 392388

--------------------------------------------------------------------------------
-- Condition helpers (same DSL as the other specs)
--------------------------------------------------------------------------------
local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)      return { type = "buffActive",  spell = id } end
local function buffDown(id)    return { type = "buffMissing", spell = id } end
local function refreshable(id) return { type = "refreshable", spell = id } end
local function cdReady(id)     return { type = "cdReady",     spell = id } end
local function cpMin(n)        return { type = "resourceMin", v = n } end
local function cpMax(n)        return { type = "resourceMax", v = n } end
local function cpEq(n)         return { type = "resourceEq",  v = n } end
local function enemiesMin(n)   return { type = "enemiesMin",  v = n } end
local function enemiesMax(n)   return { type = "enemiesMax",  v = n } end
local function notStealthed()  return { type = "notStealthed" } end
local function stacksMax(id, n) return { type = "stacksMax", spell = id, v = n } end
-- THE readable low-energy proxy. Energy itself is secret in combat, but the game's
-- insufficient-power FLAG is clean -- so "can't afford Mutilate" (50 Energy) is an
-- exact, in-combat read of "Energy < 50". Fails closed: an unreadable flag never fires.
local function noPower(id)     return { type = "noPower", spell = id } end

-- "Keep it up": missing, or inside the pandemic window. `refreshable` fails CLOSED
-- (only true when Blizzard confirms it), so this never spam-refreshes a fresh DoT.
local function keepUp(id) return OR(buffDown(id), refreshable(id)) end

--------------------------------------------------------------------------------
-- PRIORITY LISTS -- one explicit list per hero tree per mode, written to follow the
-- Icy Veins 12.1 per-hero lists line for line. The guide numbers are in [brackets] so
-- every row can be audited against the source. The two trees diverge enough (Darkest
-- Night, Shiv placement, the Mark) that composing them from a shared "core" hid real
-- ordering mistakes -- notably that Rupture belongs ABOVE Deathmark in every list.
--
-- Three deliberate departures from the printed order, all marked inline:
--   * The Darkest Night 6->7 CP bridge is hoisted ABOVE the plain Envenom row. The
--     guide lists it last ("you can also..."), but below a 5+ CP Envenom it is
--     unreachable -- you would simply Envenom at 6 and never arrive at 7.
--   * Slice and Dice is not in the guide at all (Cut to the Chase maintains it), but
--     ONE cast is needed to start the chain, so there is a single buffDown row just
--     above the Envenoms: high enough to win the combo points, low enough that bleeds
--     and cooldowns still come first.
--   * Mark for Death is omitted. Its rule is "swap the Mark when you need to change
--     targets", which is player intent PRIO cannot infer (4 casts in 26 min of log).
--     It stays `pickable` for manual use.
--
-- GARROTE ordering: Mark row, then the Improved-Garrote window, then plain pandemic
-- maintenance. PRIO cannot read whether the DoT on the target was empowered -- only
-- whether the IG window is open right now -- so outside that window a plain refresh
-- can still clip an empowered bleed. Tune in game if it bites.
--------------------------------------------------------------------------------

-- Shared row builders. Identical text appears in several lists; ORDER is set per list.
-- Mark missing AND no Darkest Night pending. The DN-consuming Envenom re-applies the
-- Mark by itself, so Garroting while DN is up burns a GCD and 45 Energy for nothing
-- (the simulator caught this: Deathstalker Garrotes ran 8.3/min vs Fatebound 4.4).
local function rowGarroteMark()
    return { spell = "Garrote", cond = AND(buffDown(ID_DSMARK), buffDown(ID_DARKNIGHT)) }
end
local function rowGarroteIG()   return { spell = "Garrote", cond = buffUp(ID_IMPGARROTE) } end
local function rowGarroteKeep() return { spell = "Garrote", cond = keepUp(ID_GARROTE) } end
local function rowDeathmark()   return { spell = "Deathmark" } end
local function rowKingsbane()   return { spell = "Kingsbane" } end
local function rowVanish()      return { spell = "Vanish", cond = buffUp(ID_DEATHMARK) } end
local function rowSnD()         return { spell = "SliceandDice", cond = AND(buffDown(ID_SND), cpMin(5)) } end
local function rowEnvenom()     return { spell = "Envenom", cond = cpMin(5) } end
local function rowAmbush()      return { spell = "Ambush" } end     -- self-gates: stealth-only
local function rowMutilate()    return { spell = "Mutilate", cond = cpMax(5) } end
local function rowThistleTea()  return { spell = "ThistleTea", cond = noPower(ID_MUTILATE) } end
local function rowFoK()         return { spell = "FanOfKnives", cond = AND(enemiesMin(2), cpMax(4)) } end
-- Crimson Tempest spreads bleeds; the Scent of Blood clause is the guide's real stop
-- condition ("until all targets have bleeds"). LOG-GROUNDED: Scent gains 4 stacks per
-- bleeding target and caps at 20. AND-ing it can only make CT fire LESS -- under 5
-- targets the cap is unreachable, so it is a no-op there.
local function rowCrimsonTempest()
    return { spell = "CrimsonTempest", cond = AND(enemiesMin(2), cpMax(4), stacksMax(ID_SCENT, 16)) }
end

--------------------------------------------------------------------------------
-- DEATHSTALKER
--
-- Loop (LOG-CONFIRMED from aura apply/remove timestamps): Garrote applies
-- Deathstalker's Mark with 3 stacks -> every finisher spending 5+ CP consumes one ->
-- the last grants Darkest Night -> spend it on a max-CP Envenom, which re-applies the
-- Mark. The cycle ran ~14-19s in the log and was consumed within 3-6s, at an Envenom
-- with 6 or 7 CP.
--
-- Two readable tree-specific rules:
--   * Rupture is gated on Darkest Night being DOWN -- Wowhead: "Do not cast Rupture
--     during Darkest Night outside of your opener... Letting Rupture drop entirely to
--     facilitate this is acceptable." (It would consume a Mark stack instead.)
--   * The plain Envenom row is ALSO gated on Darkest Night being down, so Envenom
--     genuinely waits for 7 CP while it is up ("Cast it with 7 CP when Darkest Night
--     is active") instead of dumping at 5. The bridge rows above supply the 7th point.
--------------------------------------------------------------------------------
local deathstalker_st = {
    { spell = "Stealth", cond = notStealthed() },
    rowGarroteMark(),                                                      -- [1] Garrote applies the Mark
    rowGarroteIG(),                                                        -- [3] maintain, from Vanish when possible
    rowGarroteKeep(),                                                      -- [3]
    { spell = "Rupture", cond = AND(buffDown(ID_DARKNIGHT), cpMin(5), keepUp(ID_RUPTURE)) }, -- [4]
    rowDeathmark(),                                                        -- [5]
    rowKingsbane(),                                                        -- [6] synced to Deathmark
    rowVanish(),                                                           -- [3] "before every Deathmark"
    -- [7] on cooldown. cpMax(6) is ours, not the guide's: Shiv generates 1 CP, and
    -- this row sits ABOVE Envenom, so without it Shiv fires at max CP and overcaps.
    { spell = "Shiv", cond = cpMax(6) },
    rowSnD(),                                                              -- (not in guide; one cast starts the chain)
    { spell = "Envenom", cond = AND(buffUp(ID_DARKNIGHT), cpMin(7)) },     -- [8] 7 CP under Darkest Night
    { spell = "Shiv",    cond = AND(buffUp(ID_DARKNIGHT), cpEq(6)) },      -- [13] hoisted: bridge 6 -> 7
    { spell = "Envenom", cond = AND(buffDown(ID_DARKNIGHT), cpMin(5)) },   -- [8] otherwise 5+ CP
    rowAmbush(),                                                           -- [9] whenever usable (stealth)
    rowMutilate(),                                                         -- [10]
    rowFoK(),                                                              -- [11] more than 1 target
    rowThistleTea(),                                                       -- [12] low energy
}

local deathstalker_aoe = {
    { spell = "Stealth" },
    rowGarroteMark(),                                                      -- [1]
    rowGarroteIG(),                                                        -- [1] cast twice to extend Improved Garrote
    rowGarroteKeep(),                                                      -- [3]
    { spell = "Rupture", cond = AND(buffDown(ID_DARKNIGHT), cpMin(5), keepUp(ID_RUPTURE)) }, -- [3]
    rowCrimsonTempest(),                                                   -- [4][5] AoE builder, spreads bleeds
    rowFoK(),                                                              -- [5] once every target is bled
    rowDeathmark(),                                                        -- [6]
    rowKingsbane(),                                                        -- [7]
    rowVanish(),                                                           -- [8] re-apply empowered Garrotes
    rowSnD(),
    { spell = "Envenom",     cond = AND(buffUp(ID_DARKNIGHT), cpMin(7)) }, -- [9]
    { spell = "Shiv",        cond = AND(buffUp(ID_DARKNIGHT), cpEq(6)) },  -- [9] "Shiv to get to 7 CP"
    { spell = "FanOfKnives", cond = AND(buffUp(ID_DARKNIGHT), cpEq(6)) },  -- [11] the other bridge
    { spell = "Envenom",     cond = AND(buffDown(ID_DARKNIGHT), cpMin(5)) }, -- [9]
    rowMutilate(),
    rowThistleTea(),                                                       -- [10]
}

--------------------------------------------------------------------------------
-- FATEBOUND
--
-- Hand of Fate flips a coin on every finisher spending 5+ CP, but both guides are
-- explicit that you have NO control over the flips -- so Fatebound needs no coin
-- conditions and nothing extra to track. It is the plain 5+ CP list.
--
-- Shiv drops to the BOTTOM (guide [10], below even Thistle Tea): Wowhead measures it
-- as a ~1% DPS LOSS for this tree, because Deal Fate makes non-Shiv generators better.
-- LOG-CONFIRMED: the Fatebound rogues cast Shiv 14 and 19 times vs 31 for Deathstalker.
-- The Fatebound AoE list has no Shiv row at all.
--------------------------------------------------------------------------------
local fatebound_st = {
    { spell = "Stealth", cond = notStealthed() },
    rowGarroteIG(),                                                        -- [1] maintain, from Vanish when possible
    rowGarroteKeep(),                                                      -- [1]
    { spell = "Rupture", cond = AND(cpMin(5), keepUp(ID_RUPTURE)) },       -- [2]
    rowDeathmark(),                                                        -- [3]
    rowKingsbane(),                                                        -- [4]
    rowVanish(),                                                           -- [1] "before every Deathmark"
    rowSnD(),
    rowEnvenom(),                                                          -- [5]
    rowAmbush(),                                                           -- [6]
    rowMutilate(),                                                         -- [7]
    rowFoK(),                                                              -- [8] more than 1 target
    rowThistleTea(),                                                       -- [9]
    { spell = "Shiv", cond = cpMax(6) },                                   -- [10] last: a ~1% loss for Fatebound
}

local fatebound_aoe = {
    { spell = "Stealth" },
    rowGarroteIG(),                                                        -- [1] ideally from Stealth
    rowGarroteKeep(),                                                      -- [2]
    { spell = "Rupture", cond = AND(cpMin(5), keepUp(ID_RUPTURE)) },       -- [1]
    rowCrimsonTempest(),                                                   -- [2][3] AoE builder, spreads bleeds
    rowFoK(),                                                              -- [3] once every target is bled
    rowDeathmark(),                                                        -- [4]
    rowKingsbane(),                                                        -- [5]
    rowVanish(),                                                           -- [6]
    rowSnD(),
    rowEnvenom(),                                                          -- [7]
    rowMutilate(),
    rowThistleTea(),                                                       -- [8]
}

local heroLists = {
    deathstalker = { st = deathstalker_st, aoe = deathstalker_aoe },
    fatebound    = { st = fatebound_st,    aoe = fatebound_aoe },
}

-- Hero detection by strict known-check on each tree's giveaway spell: Hand of Fate is
-- the Fatebound keystone; Mark for Death is auto-learned by talenting into Deathstalker
-- (Icy Veins: "you will learn automatically as you talent into Deathstalker"). Fatebound
-- is the fallback -- it is what 2 of the 3 reference logs ran and what all three Icy
-- Veins Quick Start import codes use. (Their prose recommends Deathstalker and
-- contradicts itself; Method.gg disagrees with both. Pick your own in Options.)
local function activeHero()
    if API and API.IsKnownStrict then
        if API.IsKnownStrict(ID_HANDOFFATE) then return "fatebound" end
        if API.IsKnownStrict(ID_MARKDEATH)  then return "deathstalker" end
    end
    return "fatebound"
end

local spec = {
    key      = "ROGUE_ASSASSINATION",
    label    = "Assassination",
    className = "Rogue",
    specID   = 259,
    resource = COMBO,             -- COMBO POINTS: discrete -> readable in combat (exact gates)
    resourceLabel = "Combo Pts",
    maelstromMax = 7,             -- CP cap (readable PowerMax overrides; 5-7 with the Stratagem talents)

    alerts = {},

    -- Fan of Knives / Crimson Tempest come in at 2+ targets, so there is no distinct
    -- cleave tier -- AoE mode covers 2+.
    cleaveAt = 2,
    aoeAt    = 2,

    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "deathstalker", label = "Deathstalker" },
        { key = "fatebound",    label = "Fatebound" },
    },

    -- ENERGY is secret and regenerates fast, so relax the usable-gate: a spender that is
    -- unusable ONLY for insufficient energy still shows (you press it as energy ticks up)
    -- instead of collapsing to the builder. Same reasoning as Outlaw. Do NOT set this on
    -- built-resource specs (Maelstrom/Holy Power), where IsUsable is the correct check.
    softPowerUsable = true,

    -- Surfaces the "Can't afford <spell>" conditions in the editor -- the readable
    -- stand-in for Energy, which is a secret value in combat.
    condTags = { nopower = true },

    -- FINISHERS spend ALL combo points and are castable at any CP >= 1, but the game
    -- reports their cost as the MAX -- so the affordability gate would wrongly withhold
    -- them below max. Clamped to a 1-CP minimum so the CP conditions above decide.
    -- CRIMSON TEMPEST IS NOT HERE: it is a BUILDER in 12.1 (generates 1 CP, costs none).
    finishers = { Envenom = true, Rupture = true, SliceandDice = true },

    -- No-cooldown builders (the safety net at the bottom of each list).
    fillers = { [ID_MUTILATE] = true, [ID_FOK] = true },

    -- Pulse the Envenom icon while Darkest Night is up -- that is the one Deathstalker
    -- window where which Envenom you press actually matters.
    flash = {
        Envenom = { type = "buffActive", spell = ID_DARKNIGHT },
    },

    -- Look-ahead combo-point simulation. Finishers spend ALL combo points; Mutilate is
    -- the only 2-CP generator. Crimson Tempest is listed with the GENERATORS on purpose
    -- -- in 12.1 it builds 1 CP and costs none (see the header).
    -- Not modelled: Seal Fate's crit-driven extra CP (and Fatebound's Deal Fate chance
    -- on top of it), which is a large but unpredictable share of real generation.
    ResourceDelta = function(_, key, sid, S)
        if key == "Envenom" or key == "Rupture" or key == "SliceandDice" then
            return -(S.maelstrom or 0)                      -- finisher: spend all combo points
        elseif key == "Mutilate" then
            return 2
        elseif key == "Garrote" or key == "FanOfKnives" or key == "CrimsonTempest"
            or key == "Shiv" or key == "Kingsbane" then
            return 1
        end
        return 0
    end,

    condPresets = {
        { key = "finisherCP",  label = "Finisher combo points (>=5)", clause = cpMin(5) },
        { key = "lowCP",       label = "Low combo points (<=4)",      clause = cpMax(4) },
        { key = "darkestNight", label = "Darkest Night up",           clause = buffUp(ID_DARKNIGHT) },
        { key = "impGarrote",  label = "Improved Garrote window",     clause = buffUp(ID_IMPGARROTE) },
        { key = "bleedsUp",    label = "Garrote + Rupture both up",   clause = AND(buffUp(ID_GARROTE), buffUp(ID_RUPTURE)) },
        { key = "burst",       label = "Deathmark window",            clause = buffUp(ID_DEATHMARK) },
        { key = "lowEnergy",   label = "Low energy (<50, can't Mutilate)", clause = noPower(ID_MUTILATE) },
        { key = "scentCapped", label = "Scent of Blood capped (20)",   clause = { type = "stacksMin", spell = ID_SCENT, v = 20 } },
    },

    auras = {
        Garrote           = ID_GARROTE,
        Rupture           = ID_RUPTURE,
        Envenom           = ID_ENVENOM,
        SliceAndDice      = ID_SND,
        Deathmark         = ID_DEATHMARK,
        ImprovedGarrote   = ID_IMPGARROTE,
        DarkestNight      = ID_DARKNIGHT,
        DeathstalkersMark = ID_DSMARK,
        LingeringDarkness = ID_LINGERDARK,
        Vanish            = ID_VANISH,
        Stealth           = ID_STEALTH,
        Kingsbane         = ID_KINGSBANE,
        ScentOfBlood      = ID_SCENT,
        CausticSpatter    = ID_CAUSTIC,
        AmplifyingPoison  = ID_AMPPOISONDOT,
        MomentumOfDespair = ID_MOMENTUM,
    },

    -- Only what the rotation actually reads. `pandemic` rows show Blizzard's own refresh
    -- window off the Cooldown Manager glow (enable "Pandemic Time" on Garrote and Rupture).
    debug = {
        { label = "Garrote (dot)",      kind = "buff",     spell = ID_GARROTE },
        { label = "Garrote refresh",    kind = "pandemic", spell = ID_GARROTE },
        { label = "Rupture (dot)",      kind = "buff",     spell = ID_RUPTURE },
        { label = "Rupture refresh",    kind = "pandemic", spell = ID_RUPTURE },
        { label = "Improved Garrote",   kind = "buff",     spell = ID_IMPGARROTE },
        { label = "Darkest Night (DS)", kind = "buff",     spell = ID_DARKNIGHT },
    },
    economy = {
        gen   = { "Mutilate", "Fan of Knives", "Crimson Tempest", "Garrote", "Shiv", "Kingsbane" },
        spend = { "Envenom", "Rupture", "Slice and Dice" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug). Deliberately short: every row
    -- here is a signal the priority list actually gates on. Energy is absent because
    -- its VALUE is secret -- the "Energy low" probe below is the readable stand-in.
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "Garrote", "Rupture", "Envenom", "Mutilate",
            "Deathmark", "Kingsbane", "Vanish", "Shiv",
            "FanOfKnives", "CrimsonTempest",
        },
        buffs = {
            { label = "Garrote (dot)",       spell = ID_GARROTE, pandemic = true },
            { label = "Rupture (dot)",       spell = ID_RUPTURE, pandemic = true },
            { label = "Improved Garrote",    spell = ID_IMPGARROTE },
            { label = "Slice and Dice",      spell = ID_SND },
            { label = "Deathmark",           spell = ID_DEATHMARK },
            { label = "Darkest Night (DS)",  spell = ID_DARKNIGHT },
            { label = "Deathstalker's Mark", spell = ID_DSMARK },
            { label = "Scent of Blood",      spell = ID_SCENT },
        },
        rangeProbes = {
            { label = "Combo Points", kind = "resource" },
            { label = "Energy low",   kind = "noPower", spell = ID_MUTILATE },
        },
    },

    setup = {
        { kind = "trackedAura", label = "Garrote tracked", spell = ID_GARROTE,
          hint = "Track Garrote so PRIO can see when it needs refreshing (18s, pandemic window 5.4s). Uptime target is 100% -- Venomous Wounds energy depends on your bleeds." },
        { kind = "trackedAura", label = "Rupture tracked", spell = ID_RUPTURE,
          hint = "Track Rupture so the refresh line reads. Pandemic scales with the combo points you spend: 7.2s at 5 CP, 8.4s at 6, 9.6s at 7. Uptime target is 100%." },
        { kind = "trackedAura", label = "Improved Garrote tracked", spell = ID_IMPGARROTE,
          hint = "Track Improved Garrote (it is a TrackedBar) so PRIO can see the 6-second empowered window opened by Stealth/Vanish and tell you to cast Garrote inside it." },
        { kind = "trackedAura", label = "Deathmark tracked", spell = ID_DEATHMARK,
          hint = "Track Deathmark so PRIO can sync Vanish to it (Vanish exists only to open an Improved Garrote window during your burst)." },
        { kind = "trackedAura", label = "Slice and Dice tracked", spell = ID_SND,
          hint = "Track Slice and Dice so the single opener line reads. You only ever cast it once -- Cut to the Chase is baseline and Envenom extends it from there (confirmed in logs: 1 cast, 95% uptime)." },
        { kind = "trackedAura", label = "Darkest Night tracked", spell = ID_DARKNIGHT, optional = true,
          hint = "DEATHSTALKER ONLY: track Darkest Night. It drives the max-combo-point Envenom, the Shiv / Fan of Knives bridge at exactly 6 CP, and the rule that holds Rupture while it is up. Harmless to skip on Fatebound." },
        { kind = "trackedAura", label = "Deathstalker's Mark tracked", spell = ID_DSMARK, optional = true,
          hint = "DEATHSTALKER ONLY, and optional: PRIO does not gate on the Mark (Garrote applies it with 3 stacks and your 5+ CP finishers eat them automatically), but tracking it lets you watch the cycle." },
        { kind = "info", label = "Combo Points",
          hint = "No tracking needed -- combo points are a discrete resource PRIO reads directly, so every finisher and builder combo-point gate is exact. Max is 7 with Deeper Stratagem + Sanguine Stratagem." },
        { kind = "trackedAura", label = "Kingsbane tracked", spell = ID_KINGSBANE, optional = true,
          hint = "Optional: PRIO reads cooldowns directly so Kingsbane is recommended either way, but tracking it (and its stacking buff 394095) lets you see the window you are stacking Envenoms into." },
        { kind = "trackedAura", label = "Scent of Blood tracked", spell = ID_SCENT, optional = true,
          hint = "Optional but useful in AoE: Scent of Blood gains 4 stacks per bleeding target and caps at 20. PRIO uses it to stop spamming Crimson Tempest once the pack is fully bled and switch to the cheaper Fan of Knives." },
        { kind = "info", label = "Energy: tracked indirectly, and that is on purpose",
          hint = "Energy is a filling bar, so its VALUE is a secret in combat -- but the game's insufficient-power FLAG is clean. PRIO uses that instead: \"can't afford Mutilate\" (50 Energy) is an exact read of \"Energy < 50\", and that is what gates Thistle Tea. The finer plays -- pooling, and chaining Envenom in the last 1-2s of its buff -- still need the real number, so they stay on you." },
        { kind = "info", label = "Poisons (pre-combat)",
          hint = "Run Deadly Poison AND Amplifying Poison together (Dragon-Tempered Blades lets you carry two lethal poisons). Non-lethal: Atrophic Poison for raid -- buffed in 12.1 to 4% damage reduction and 60s duration." },
    },

    spells = {
        Mutilate       = ID_MUTILATE,
        Garrote        = ID_GARROTE,
        Rupture        = ID_RUPTURE,
        Envenom        = ID_ENVENOM,
        Deathmark      = ID_DEATHMARK,
        Kingsbane      = ID_KINGSBANE,
        FanOfKnives    = ID_FOK,
        CrimsonTempest = ID_CRIMSONTEMP,
        SliceandDice   = ID_SND,
        Shiv           = ID_SHIV,
        MarkForDeath   = ID_MARKDEATH,
        Vanish         = ID_VANISH,
        Stealth        = ID_STEALTH,
        ThistleTea     = ID_THISTLETEA,
    },

    -- Opener (Icy Veins 12.1, identical for both trees through step 8): open from Stealth
    -- with Garrote, build, Rupture, re-Garrote to extend Improved Garrote, build, Envenom,
    -- THEN Deathmark + Kingsbane, then hand off to the normal rotation.
    openerReady = { "Deathmark" },
    opener = { "Garrote", "Mutilate", "Mutilate", "Rupture", "Garrote",
               "Mutilate", "Mutilate", "Envenom", "Deathmark", "Kingsbane" },
    -- AoE opener: double Garrote for max pandemic on Improved Garrote, build with Fan of
    -- Knives, Rupture, cooldowns, then Crimson Tempest to spread the bleeds to the pack.
    openerAoe = { "Garrote", "Garrote", "FanOfKnives", "FanOfKnives", "Rupture",
                  "Deathmark", "Kingsbane", "Envenom", "CrimsonTempest", "CrimsonTempest" },
    precombat = {},

    pickable = {
        "Mutilate", "Garrote", "Rupture", "Envenom", "Deathmark", "Kingsbane",
        "FanOfKnives", "CrimsonTempest", "SliceandDice", "Shiv", "MarkForDeath",
        "Vanish", "Stealth", "ThistleTea",
    },
}

-- spec.priority is a live proxy resolving to the ACTIVE hero's list for a mode (editor /
-- export / any direct read). Customization lives in db.customPriorities, so the backing
-- table stays empty and the __index resolver is safe.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.fatebound
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
