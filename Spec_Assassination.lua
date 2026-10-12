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
local ID_IMPGARROTE = 381632   -- TrackedBar. the 6s empowered-Garrote window
local ID_KINGSBANE  = 385627   -- 1 min CD, +1 CP. NOT in the user's CDM dump (see setup)
local ID_THISTLETEA = 1298826  -- energy cooldown; NOT in the priority (energy unreadable)

-- Deathstalker
local ID_DSMARK     = 457052   -- TrackedBuff. Deathstalker's Mark (3 stacks, applied by Garrote)
local ID_DARKNIGHT  = 457058   -- TrackedBuff. Darkest Night -- spend on a max-CP Envenom
local ID_LINGERDARK = 457056   -- TrackedBuff. Lingering Darkness (passive damage node)

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

-- "Keep it up": missing, or inside the pandemic window. `refreshable` fails CLOSED
-- (only true when Blizzard confirms it), so this never spam-refreshes a fresh DoT.
local function keepUp(id) return OR(buffDown(id), refreshable(id)) end

--------------------------------------------------------------------------------
-- SHARED CORE -- the lines both hero trees run identically, in guide order.
--
-- Ordering follows Icy Veins/Wowhead merged: bleeds -> cooldowns -> Vanish/Garrote ->
-- finisher -> builder. Per-hero lines get spliced in by the builders below.
--
-- GARROTE has TWO lines, and the order matters:
--   (a) during the Improved Garrote window -> always correct (empowered application).
--   (b) normal pandemic maintenance.
-- KNOWN APPROXIMATION: the guides say never overwrite an Improved-Garrote-empowered
-- Garrote with an unempowered one ("it is best to let the DoT run its full duration").
-- PRIO cannot read whether the DoT on the target was empowered -- only whether the IG
-- window is open right now. (a) sitting above (b) gets this right whenever the window
-- is open; outside it we can still clip an empowered bleed. Tune in game if it bites.
--------------------------------------------------------------------------------
local function bleedsAndCooldowns()
    return {
        -- Opener-only: Cut to the Chase + Envenom maintain it from here on.
        { spell = "SliceandDice",  cond = AND(buffDown(ID_SND), cpMin(5)) },
        -- Garrote inside the empowered window (Stealth/Vanish).
        { spell = "Garrote",       cond = buffUp(ID_IMPGARROTE) },
        -- Garrote maintenance. Uptime target is 100%; 18s base -> 5.4s pandemic.
        { spell = "Garrote",       cond = keepUp(ID_GARROTE) },
        -- Deathmark on cooldown (2 min). Bleeds are above it so they are up first --
        -- Deathmark multiplies Rupture/Garrote/poison damage by 75%.
        { spell = "Deathmark" },
        -- Kingsbane on cooldown (1 min), synced immediately after Deathmark.
        { spell = "Kingsbane" },
        -- Vanish ONLY to open an Improved Garrote window, synced to Deathmark.
        -- LOG-CONFIRMED: Vanish landed ~2.6s after Deathmark in the burst sample.
        { spell = "Vanish",        cond = buffUp(ID_DEATHMARK) },
    }
end

-- AoE builders. Crimson Tempest spreads bleeds, Fan of Knives is the cheap filler
-- (35 vs 60 Energy). The real rule is "CT until every target has your bleeds, then
-- FoK" -- which needs per-target bleed coverage we cannot read. Proxy: CT early in
-- the combo-point cycle (the spreading phase), FoK to top the cycle off. This is the
-- single most worthwhile thing to retune in game.
-- Breakpoint is 2+ (Wowhead + Icy Veins "as soon as there is more than 1 target");
-- Maxroll says 3+. LOG-CONFIRMED heavy use of both (FoK 221-273, CT 152-266 per run).
local function aoeBuilders()
    return {
        { spell = "CrimsonTempest", cond = AND(enemiesMin(2), cpMax(2)) },
        { spell = "FanOfKnives",    cond = AND(enemiesMin(2), cpMax(4)) },
    }
end

local function append(dst, src)
    for i = 1, #src do dst[#dst + 1] = src[i] end
    return dst
end

--------------------------------------------------------------------------------
-- DEATHSTALKER
--
-- The loop (LOG-CONFIRMED against apply/remove timestamps): Garrote applies
-- Deathstalker's Mark with 3 stacks -> every finisher spending 5+ CP consumes one ->
-- the last one grants Darkest Night -> spend Darkest Night on a MAX-CP Envenom, which
-- re-applies the Mark. In the log the cycle ran ~14-19s and Darkest Night was consumed
-- within 3-6s, at an Envenom with 6 or 7 CP.
--
-- Two Deathstalker-specific rules, both readable and both implemented:
--   * Rupture is gated on Darkest Night being DOWN. Wowhead: "Do not cast Rupture
--     during Darkest Night outside of your opener... Letting Rupture drop entirely to
--     facilitate this is acceptable." (A Rupture would eat a Mark stack instead.)
--   * Shiv is a core generator for Deathstalker (cheapest CP with Toxic Stiletto) but
--     SINGLE TARGET ONLY -- "never with any adds up, as Fan of Knives becomes more
--     efficient". LOG-CONFIRMED: the Deathstalker rogue cast Shiv 31 times vs 14-19
--     for the two Fatebound rogues.
--
-- Mark for Death is intentionally NOT in the list: its rule is "swap your Mark when you
-- need to change targets", which is player intent PRIO cannot infer. LOG-CONFIRMED as
-- situational (4 casts in 26 minutes). It stays pickable.
--------------------------------------------------------------------------------
local function deathstalkerList(isAoe)
    local list = bleedsAndCooldowns()
    -- Rupture: 5+ CP, and NOT during Darkest Night (outside the opener).
    list[#list + 1] = { spell = "Rupture", cond = AND(buffDown(ID_DARKNIGHT), cpMin(5), keepUp(ID_RUPTURE)) }
    -- Darkest Night: dump it on the biggest Envenom you can.
    list[#list + 1] = { spell = "Envenom", cond = AND(buffUp(ID_DARKNIGHT), cpMin(7)) }
    -- Sitting at exactly 6 with Darkest Night up? Bridge to 7 with a 1-CP generator.
    -- NOTE: if you do not run both Stratagem talents your max CP is below 7 and these
    -- bridge lines cannot resolve -- the plain Envenom line below still catches it.
    if isAoe then
        list[#list + 1] = { spell = "FanOfKnives", cond = AND(buffUp(ID_DARKNIGHT), cpEq(6)) }
    end
    list[#list + 1] = { spell = "Shiv", cond = AND(buffUp(ID_DARKNIGHT), cpEq(6)) }
    -- Shiv on cooldown, single target only.
    list[#list + 1] = { spell = "Shiv", cond = enemiesMax(1) }
    if isAoe then append(list, aoeBuilders()) end
    list[#list + 1] = { spell = "Envenom",  cond = cpMin(5) }
    list[#list + 1] = { spell = "Mutilate", cond = cpMax(5) }
    return list
end

--------------------------------------------------------------------------------
-- FATEBOUND
--
-- Hand of Fate flips a Fatebound Coin on every finisher spending 5+ CP. Heads stacks
-- damage, Tails adds flat Cosmic damage, 7 flips in a row grants the Lucky Coin buff.
-- Both guides are explicit that you have NO control over the flips -- so Fatebound
-- needs NO coin-based decisions, only the 5+ CP finisher gate we already have. There
-- is nothing to track and nothing to read.
--
-- Differences from Deathstalker: no Darkest Night / Mark lines, no 7-CP rule, and Shiv
-- drops to the BOTTOM. Wowhead measured Shiv as a ~1% DPS LOSS for Fatebound (Deal
-- Fate makes non-Shiv generators better), though it can flip positive under perfect
-- conditions -- so it sits last and is the first line to delete if you dislike it.
-- LOG-CONFIRMED: the Fatebound rogues cast Shiv 14 and 19 times vs 31 for Deathstalker.
--------------------------------------------------------------------------------
local function fateboundList(isAoe)
    local list = bleedsAndCooldowns()
    list[#list + 1] = { spell = "Rupture", cond = AND(cpMin(5), keepUp(ID_RUPTURE)) }
    if isAoe then append(list, aoeBuilders()) end
    list[#list + 1] = { spell = "Envenom",  cond = cpMin(5) }
    list[#list + 1] = { spell = "Mutilate", cond = cpMax(5) }
    list[#list + 1] = { spell = "Shiv" }
    return list
end

-- Stealth leads each mode (the engine filters it in combat, so it only shows pre-pull).
local function withStealth(list, isAoe)
    local out = { isAoe and { spell = "Stealth" } or { spell = "Stealth", cond = notStealthed() } }
    return append(out, list)
end

local heroLists = {
    deathstalker = {
        st  = withStealth(deathstalkerList(false), false),
        aoe = withStealth(deathstalkerList(true),  true),
    },
    fatebound = {
        st  = withStealth(fateboundList(false), false),
        aoe = withStealth(fateboundList(true),  true),
    },
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
    name     = "Assassination",
    specID   = 259,
    resource = COMBO,             -- COMBO POINTS: discrete -> readable in combat (exact gates)

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
        { kind = "info", label = "Energy is unreadable in combat",
          hint = "Energy is a filling bar, so it is a secret value in combat. PRIO cannot do Assassination's energy pooling or Envenom chaining (pressing Envenom in the last 1-2s of the buff) -- that part stays on you. Take the AUTO-CAST Thistle Tea talent; it fires below 30 energy by itself and the guides say it makes no difference." },
        { kind = "info", label = "Kingsbane is not in your Cooldown Manager",
          hint = "PRIO reads cooldowns directly, so it will still recommend Kingsbane -- but it was missing from your Cooldown Viewer setup and it is a real 1-minute cooldown (21-24 casts per run in the reference logs). Add it to Essential if you want to see it on your own bars." },
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
