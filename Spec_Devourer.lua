-- Spec_Devourer.lua ------------------------------------------------------------
-- Devourer Demon Hunter (NEW Midnight spec), spec 1480, patch 12.1. Void-based DPS
-- built around Void Metamorphosis (a FORM) + Soul Fragment counting. Void-Scarred hero.
--
-- IDs are VERIFIED from a live Cooldown Viewer dump (/prio tracked) + the Icy Veins/
-- Wowhead 12.1 guide (2026-08-27) unless flagged [ID TBD].
--
-- THE CENTRAL MECHANIC: the rotation splits OUTSIDE vs INSIDE Void Metamorphosis, and
-- the form BUFF (1225789) reads clean in combat (confirmed: "×50 appl" in Rotation
-- Debug) -- so PRIO branches on it directly. Inside the form, several abilities are
-- form-locked (Reaper's Toll / Pierce the Veil / Predator's Wake / Devour / Cull); the
-- usable/IsReady check gates them out when you're outside, and vice-versa.
--
-- VOID METAMORPHOSIS ids: cast/ability = 1217605 (confirmed usable live), Wowhead lists
-- the base as 471306 (override-resolved to 1217605 in the Cooldown Viewer). The FORM
-- BUFF is 1225789 -- a SEPARATE id, and the one we branch on. NOTE: the form buff's
-- stack count (×25 OOC / ×50 in combat) is a decay/duration counter, NOT the Soul
-- Fragment count -- do NOT gate soul thresholds on it.
--
-- RESOURCE REALITY (confirmed live): Fury is SECRET in combat ("SECRET / na"), so every
-- Fury gate ("100 Fury", "20 Fury") fails open -- the spender shows and you press it when
-- Fury allows. Soul Fragment COUNT is likewise unreadable, so "4+ souls / 10 souls /
-- enough souls" gates are approximate: those lines fall back to cooldown gating + your
-- judgement. Both are inherent 12.1 limits (see [[prio-addon-project]]).
--
-- All core abilities verified. Soulburst (2-set) is read from the Consume/Devour glow.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local FURY = (Enum and Enum.PowerType and Enum.PowerType.Fury) or 17

-- Abilities. VERIFIED unless [ID TBD].
local ID_CONSUME     = 473662    -- basic Fury generator (the filler)
local ID_REAP        = 1226019   -- outside spender
local ID_VOIDRAY     = 473728    -- Fury spender (100 Fury; Fury secret -> fail open)
local ID_VOIDMETA    = 1217605   -- cast the form (base 471306 override-resolved)
local ID_SOULIMMO    = 1241937   -- ability + maintain buff (same id)
local ID_VOIDBLADE   = 1245412   -- pre-meta CD
local ID_VOIDNOVA    = 1234195   -- AoE ability + buff
local ID_THROWGLAIVE = 185123    -- ranged filler (AoE "AFK" filler late in meta)
local ID_THEHUNT     = 1246167   -- Devourer's The Hunt (NOT the generic 370965)
local ID_HUNGERING   = 1239519   -- Hungering Slash: replaces Voidblade for 6s after The Hunt/Voidblade
                                 -- damage; tracked in the CDM under this id (the replacement window).
                                 -- Shatters up to 2 ground souls, +10 Fury, grants a VR charge.
                                 -- (The "replaced" buff aura 1239525 also exists but we gate on the CDM entry.)
local ID_ERADICATE   = 1225826   -- AoE spender (CAST id; gathers up to 10 souls). Buff was 1226033.
local ID_REAPERSTOLL = 1245470   -- in-form
local ID_PIERCEVEIL  = 1245483   -- in-form
local ID_PREDWAKE    = 1259431   -- in-form
local ID_DEVOUR      = 1217610   -- in-form generator (Consume's form version): +18 Fury, +2 souls, -1s Reap CD
local ID_CULL        = 1245453   -- in-form spender (8s CD, gathers up to 4 souls)
local ID_VENGRETREAT = 198793    -- cast (buff 198813)
local ID_DISRUPT     = 183752    -- interrupt
local ID_CONSUMEMAGIC = 278326   -- purge
local ID_BLUR        = 198589    -- defensive
local ID_DARKNESS    = 196718    -- raid CD
local ID_SPECTRAL    = 1251417   -- Spectral Sight

-- Readable buffs / tracked bars (Cooldown Viewer TrackedBuff). VERIFIED unless [ID TBD].
-- 1225789 is the SOUL COUNT (0-50 toward Void Metamorphosis), NOT an "in form" signal --
-- its stack count reads CLEAN in combat (the "x15 appl" debug row = the 15/50 soul bar).
local ID_SOULCOUNT       = 1225789   -- collected souls 0-50 (readable stack; = progress to Void Meta)
local ID_GROUNDSOULS     = 1245577   -- "Soul Fragments nearby": ACTIVE bool reads (souls on ground?); count secret
local ID_FORM            = 1217607   -- Void Metamorphosis FORM buff (transformed state) -- NOT the cast (1217605) or soul count (1225789)
local ID_VOIDSTEP        = 1239520   -- free Vengeful Retreat proc (NOT in the CDM dump -- track it to read)
local ID_VOIDSURGE       = 1246160   -- Void Ray-cycling proc
-- Soulburst (2-set, 1297432): a chance for your next Consume to be instant + explode. It
-- lights up the Consume button (Devour in-form), so the default line detects it from the
-- button GLOW -- but it's also registered as a tracked buff (auras.Soulburst) so you can
-- pick "Has buff: Soulburst" in the condition editor / track it in the CDM.
local ID_SOULBURST       = 1297432
local ID_SHATTEREDSOULS  = 1227619
local ID_FEASTOFSOULS    = 1237270
local ID_MOMENTOFCRAVING = 1238488   -- AoE Eradicate is gated on its refresh
local ID_IMPENDINGAPOC   = 1227707
local ID_VOIDFALL        = 1253304
local ID_DARKMATTER      = 1256307
local ID_ROLLINGTORMENT  = 1244237
local ID_COLLAPSINGSTAR  = 1227702

-- Talents that RESET cooldowns (drive spec.cdResets -- so the queue reflects the reset).
local ID_TAL_MOMENTCRAVE = 1238488   -- Moment of Craving: fully channeling Void Ray resets Reap
local ID_TAL_MASSACCEL   = 1256295   -- Mass Acceleration: Void Metamorphosis resets Reap (+3 Voidfall)
local ID_TAL_VIOLENT     = 452409    -- Violent Transformation: Void Meta resets Voidblade + The Hunt; The Hunt resets Soul Immolation
local ID_TAL_SECONDHELP  = 1239537   -- Second Helping: Reap/Cull gains a 2nd charge (drives the overcap gate)

-- HERO TREES. Void-Scarred is keyed off its Voidsurge passive (452402); Annihilator off
-- its Voidfall passive (1253304). Each hero gets its own set of the four lists.
local ID_HERO_VOIDSCARRED = 452402   -- Voidsurge (Void-Scarred keystone passive)
local ID_HERO_ANNIHILATOR = 1253304  -- Voidfall (Annihilator keystone passive)
-- Cooldown-affecting talents NOT modelled as resets (readiness is read live; noted for reference):
--   Tempered Soul 1246555  -- Soul Immolation CD -30s + 1 charge
--   Voidpurge     1244220  -- Void Ray CD -2s DURING Void Metamorphosis (conditional reduce)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function cdReady(id)  return { type = "cdReady",     spell = id } end
local function cdDown(id)   return { type = "cdNotReady",  spell = id } end
local function lastCast(id) return { type = "lastCast",    spell = id } end
local function enemiesMin(n) return { type = "enemiesMin", v = n } end
local function soulsGround(n) return { type = "soulsGroundMin", v = n } end   -- predicted ground souls 0-10
local function soulsHeld(n)   return { type = "soulsHeldMin",  v = n } end    -- collected souls 0-50 (read clean)
local function chargesMin(id, n) return { type = "chargesMin", spell = id, v = n } end   -- charges >= n (clean at max)
local function glow(id)       return { type = "glowing", spell = id } end     -- button proc glow (Soulburst lights up Consume/Devour)
-- Real form branching: 1217607 is the transformed buff (NOT the soul count 1225789).
local function inMeta()  return buffUp(ID_FORM) end
local function outMeta() return buffDown(ID_FORM) end

--------------------------------------------------------------------------------
-- PRIORITY (Icy Veins/Wowhead 12.1). FOUR separate lists: ST / ST (Meta) / AoE /
-- AoE (Meta). The engine auto-swaps to the "(Meta)" variant while the Void Metamorphosis
-- form buff (1217607) is up (spec.phaseMode + phaseActive), exactly like Arms' execute
-- overlay -- so each list has NO inMeta/outMeta gating; the mode selection handles it.
-- Soul breakpoints use the predicted ground count; Void Metamorphosis / Collapsing Star
-- are usable-gated by the game on their soul cost.
--------------------------------------------------------------------------------

-- SINGLE TARGET, outside the form.
local st = {
    { spell = "Consume",         cond = glow(ID_CONSUME) },                           -- Soulburst: empowered instant Consume
    { spell = "Reap",            cond = soulsGround(4) },                             -- gather at 4+ on the ground
    { spell = "SoulImmolation",  cond = buffDown(ID_SOULIMMO) },                      -- maintain the buff
    { spell = "Voidblade" },                                                          -- right before entering the form
    { spell = "VengefulRetreat", cond = AND(lastCast(ID_VOIDBLADE), cdReady(ID_THEHUNT)) }, -- pre-meta VR
    { spell = "TheHunt" },
    { spell = "VoidMetamorphosis" },                                                  -- usable-gated at 50 souls
    { spell = "HungeringSlash", cond = buffUp(ID_HUNGERING) },                        -- while Voidblade is replaced by it (CDM window)
    { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },                        -- free via Voidstep
    { spell = "VoidRay" },                                                            -- Fury spender (secret -> fail open)
    { spell = "Consume" },                                                            -- generator filler
}

-- SINGLE TARGET, inside Void Metamorphosis.
local st_meta = {
    { spell = "Devour",          cond = glow(ID_DEVOUR) },                            -- Soulburst: empowered instant Devour
    { spell = "CollapsingStar" },                                                     -- usable-gated at 30 in-meta souls
    { spell = "Cull",            cond = OR(soulsGround(4), chargesMin(ID_CULL, 2)) }, -- 4+ on the ground OR at max charges (avoid overcap)
    { spell = "ReapersToll" },
    { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },                        -- free via Voidstep
    { spell = "PierceTheVeil" },
    { spell = "PredatorsWake" },
    { spell = "VoidRay" },
    { spell = "Devour" },                                                             -- in-form generator filler (+2 souls)
}

-- AOE, outside the form.
local aoe = {
    { spell = "Consume",         cond = glow(ID_CONSUME) },                           -- Soulburst: empowered instant Consume
    { spell = "Eradicate",       cond = soulsGround(10) },                            -- AoE spender at 10+ on the ground
    { spell = "Voidblade" },
    { spell = "TheHunt" },
    { spell = "VoidMetamorphosis" },
    { spell = "VoidNova" },
    { spell = "SoulImmolation",  cond = buffDown(ID_SOULIMMO) },
    { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },
    { spell = "VoidRay" },
    { spell = "Consume" },
}

-- AOE, inside Void Metamorphosis.
local aoe_meta = {
    { sequence = "vs_aoe_meta" },   -- Void-Scarred: strict fixed sequence (self-gates to that hero)
    { spell = "Devour",          cond = glow(ID_DEVOUR) },                            -- Soulburst: empowered instant Devour
    { spell = "CollapsingStar" },
    { spell = "Eradicate",       cond = soulsGround(10) },                            -- AoE spender at 10+ on the ground
    { spell = "ReapersToll" },
    { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },
    { spell = "PierceTheVeil" },
    { spell = "PredatorsWake" },
    { spell = "VoidRay" },
    { spell = "Devour" },                                                             -- in-form generator (+2 souls)
    { spell = "ThrowGlaive" },                                                        -- late-meta filler
}

-- HERO SPLIT. Both heroes start from the SAME default lists (the user tunes each in-game;
-- per-hero customization stores separately in db). Annihilator's Voidfall/meteor build and
-- Void-Scarred's Voidsurge build diverge there without a code change. Active hero is decided
-- by which keystone passive is learned; default Void-Scarred.
local heroLists = {
    voidscarred = { st = st, st_meta = st_meta, aoe = aoe, aoe_meta = aoe_meta },
    annihilator = { st = st, st_meta = st_meta, aoe = aoe, aoe_meta = aoe_meta },
}

local function activeHero()
    if API.IsTalentSelected(ID_HERO_ANNIHILATOR) or (API.IsKnownStrict and API.IsKnownStrict(ID_HERO_ANNIHILATOR)) then
        return "annihilator"
    end
    return "voidscarred"   -- default (also when Voidsurge/452402 is the learned keystone)
end

local spec = {
    key      = "DEMONHUNTER_DEVOURER",
    label    = "Devourer",
    className = "Demon Hunter",
    specID   = 1480,  -- CONFIRMED live from Debug window (2026-08-27)
    resource = FURY,
    resourceLabel = "Fury",  -- SECRET in combat -> predicted, spenders fail open
    -- No Cleave tier: ST (1 target) vs AoE (2+), each with a Void Metamorphosis variant the
    -- engine swaps in automatically. cleaveAt == aoeAt collapses the middle tier.
    cleaveAt = 2,
    aoeAt    = 2,

    -- Editor mode tabs + the phase-overlay map: while the Void Metamorphosis form buff is up,
    -- the engine swaps st -> st_meta, aoe -> aoe_meta (mirrors Arms' execute overlay).
    modes = {
        { value = "st",       text = "ST" },
        { value = "st_meta",  text = "ST (Meta)" },
        { value = "aoe",      text = "AoE" },
        { value = "aoe_meta", text = "AoE (Meta)" },
    },
    phaseMode   = { st = "st_meta", aoe = "aoe_meta" },
    phaseActive = function() return API.IsAuraActive(ID_FORM) == true end,   -- in Void Metamorphosis?

    -- Hero split (see heroLists above). activeHero picks the live list; priorityVariants
    -- drives the Options hero picker + per-hero custom lists.
    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "voidscarred", label = "Void-Scarred" },
        { key = "annihilator", label = "Annihilator" },
    },

    -- Fury is a fast secret bar: a spender unusable ONLY for lack of Fury should still
    -- show (you press it when Fury ticks up) rather than collapse to the cheapest option.
    softPowerUsable = true,

    -- Reap/Cull charges (Second Helping talent 1239537 -> 2 charges). Current charges are
    -- secret in combat, so PRIO predicts them, but the clean maxCharges + isActive ("at max"
    -- / "recharging") reads from GetSpellCharges anchor it -- so "Charges >= 2" is reliable at
    -- the cap. max=2 is an upper bound; untalented the clean read reports 1 and the >=2 gate
    -- simply never fires. Drives the in-meta "Cull to avoid overcapping charges" line.
    chargeTrack = {
        Cull = { max = 2, recharge = 8 },
    },

    -- Proc-glow overlay on the icon: Consume/Devour lit up = Soulburst (2-set) empowered cast.
    flash = {
        Consume = glow(ID_CONSUME),
        Devour  = glow(ID_DEVOUR),
    },

    -- Predicted grant chain: Voidblade / The Hunt -> Hungering Slash window (replaces
    -- Voidblade 6s); Hungering Slash -> Voidstep (free Vengeful Retreat). Drives the queue
    -- look-ahead (spellEffects: sim aura on/off) AND the primary read (assumeOnCast: assume
    -- the aura up briefly after the cast, before the CDM read catches up).
    spellEffects = {
        Voidblade      = { grant = { ID_HUNGERING } },
        TheHunt        = { grant = { ID_HUNGERING } },
        HungeringSlash = { consume = { ID_HUNGERING }, grant = { ID_VOIDSTEP } },
        -- Soul Immolation has 2 charges; without this the look-ahead would recommend the
        -- 2nd charge (its "no Soul Immolation buff" line stays true in the sim). Marking the
        -- buff applied makes that line fail on the next slot -> no double-recommend.
        SoulImmolation = { grant = { ID_SOULIMMO } },
    },
    assumeOnCast = {
        Voidblade      = { aura = ID_HUNGERING, dur = 6 },
        TheHunt        = { aura = ID_HUNGERING, dur = 6 },
        HungeringSlash = { aura = ID_VOIDSTEP,  dur = 6 },
        SoulImmolation = { aura = ID_SOULIMMO,  dur = 5 },   -- its own buff (stops instant re-suggest)
    },

    -- SEQUENCE follower (see Engine). Void-Scarred's inside-meta AoE is a strict fixed
    -- order, not a priority -- so it's a sequence: start when the active hero is Void-Scarred
    -- (only reached inside the form, since it lives in aoe_meta), stop when the form ends.
    -- Steps skip themselves when uncastable (e.g. Vengeful Retreat without Voidstep). It
    -- self-gates: for Annihilator the start returns false and the normal aoe_meta lines run.
    sequences = {
        vs_aoe_meta = {
            start = function() return activeHero() == "voidscarred" end,
            stop  = function() return API.IsAuraActive(ID_FORM) ~= true end,   -- left the form
            steps = {
                { spell = "Eradicate" },
                { spell = "VoidRay" },
                { spell = "ReapersToll" },
                { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },
                { spell = "PierceTheVeil" },
                { spell = "ReapersToll" },
                { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },
                { spell = "PredatorsWake" },
                { spell = "ReapersToll" },
                { spell = "VengefulRetreat", cond = buffUp(ID_VOIDSTEP) },
                { spell = "Eradicate" },
                { spell = "Devour" },      -- until Void Ray is available
                { spell = "VoidRay" },
            },
        },
    },

    -- Rising-edge predicted buff timers: when the buff is GAINED, start an N-second
    -- countdown (its remaining is secret in combat). Moment of Craving lasts 8s -> enables
    -- a "dump it before it expires" line via "Buff time left <= N".
    auraGainTimers = {
        [ID_MOMENTOFCRAVING] = 8,
    },

    spells = {
        Consume          = ID_CONSUME,
        Reap             = ID_REAP,
        VoidRay          = ID_VOIDRAY,
        VoidMetamorphosis = ID_VOIDMETA,
        SoulImmolation   = ID_SOULIMMO,
        Voidblade        = ID_VOIDBLADE,
        VoidNova         = ID_VOIDNOVA,
        ThrowGlaive      = ID_THROWGLAIVE,
        TheHunt          = ID_THEHUNT,
        HungeringSlash   = ID_HUNGERING,
        Eradicate        = ID_ERADICATE,
        ReapersToll      = ID_REAPERSTOLL,
        PierceTheVeil    = ID_PIERCEVEIL,
        PredatorsWake    = ID_PREDWAKE,
        CollapsingStar   = ID_COLLAPSINGSTAR,   -- in-form spender (cast id assumed = counter aura; IsKnown filters if wrong)
        Devour           = ID_DEVOUR,        -- in-form Consume
        Cull             = ID_CULL,
        VengefulRetreat  = ID_VENGRETREAT,
        Disrupt          = ID_DISRUPT,
        ConsumeMagic     = ID_CONSUMEMAGIC,
        Blur             = ID_BLUR,
        Darkness         = ID_DARKNESS,
        SpectralSight    = ID_SPECTRAL,
    },

    -- SOUL TRACKING (see Engine BuildState). The readable soul counter PIVOTS by form:
    -- outside = ID_SOULCOUNT (1225789, souls -> 50); inside Void Metamorphosis it goes
    -- "gone" and ID_COLLAPSINGSTAR (1227702) carries the in-meta counter (-> 30) instead.
    -- groundAura's ACTIVE bool = "souls on the ground?" (count secret -> predicted).
    soulTrack = {
        countAura     = ID_SOULCOUNT,        -- outside form (0-50)
        countAuraForm = ID_COLLAPSINGSTAR,   -- inside form (Collapsing Star counter, 0-40)
        formAura      = ID_FORM,             -- transformed?
        groundAura    = ID_GROUNDSOULS,
    },
    condTags = { devourer = true },   -- surfaces the "Ground/Collected souls" conditions in the editor

    auras = {
        SoulCount         = ID_SOULCOUNT,       -- collected souls 0-50 (readable stack; outside form)
        VoidMetaForm      = ID_FORM,            -- transformed? (1217607)
        HungeringSlash    = ID_HUNGERING,       -- Voidblade-replacement window (CDM)
        Soulburst         = ID_SOULBURST,       -- 2-set proc buff (selectable as "Has buff: Soulburst")
        GroundSouls       = ID_GROUNDSOULS,     -- souls-on-ground boolean
        SoulImmolation    = ID_SOULIMMO,
        Voidstep          = ID_VOIDSTEP,
        Voidsurge         = ID_VOIDSURGE,
        ShatteredSouls    = ID_SHATTEREDSOULS,
        FeastOfSouls      = ID_FEASTOFSOULS,
        MomentOfCraving   = ID_MOMENTOFCRAVING,
        ImpendingApocalypse = ID_IMPENDINGAPOC,
        Voidfall          = ID_VOIDFALL,
        DarkMatter        = ID_DARKMATTER,
        RollingTorment    = ID_ROLLINGTORMENT,
        CollapsingStar    = ID_COLLAPSINGSTAR,
        VoidNova          = ID_VOIDNOVA,
    },

    condPresets = {
        { key = "inMeta",       label = "In Void Metamorphosis",     clause = inMeta() },
        { key = "outMeta",      label = "Not in Void Metamorphosis", clause = outMeta() },
        -- Ground souls (estimated: spawns from casts minus the readable collected count).
        { key = "ground4",      label = "Ground souls \226\137\165 4",  clause = soulsGround(4) },
        { key = "ground10",     label = "Ground souls \226\137\165 10", clause = soulsGround(10) },
        { key = "onGround",     label = "Souls on the ground",   clause = buffUp(ID_GROUNDSOULS) },   -- reliable boolean
        -- Collected soul count (readable, pivots by form) -- for progress-to-50 style gates.
        { key = "held30",       label = "Collected souls \226\137\165 30", clause = soulsHeld(30) },
        { key = "cullCap",      label = "Cull charges full (2)", clause = chargesMin(ID_CULL, 2) },
        { key = "soulburst",    label = "Soulburst (Consume glow)", clause = glow(ID_CONSUME) },
        { key = "mocExpiring",  label = "Moment of Craving expiring (\226\137\1642s)", clause = { type = "auraRemainMax", spell = ID_MOMENTOFCRAVING, v = 2 } },
        { key = "soulImmoDown", label = "Soul Immolation missing",   clause = buffDown(ID_SOULIMMO) },
        { key = "voidstep",     label = "Voidstep up (free VR)",     clause = buffUp(ID_VOIDSTEP) },
    },

    setup = {
        { kind = "trackedAura", label = "Void Metamorphosis form tracked", spell = ID_FORM,
          hint = "Track the Void Metamorphosis FORM buff (1217607) so PRIO knows when you're transformed and branches the inside/outside rotation correctly. This is NOT the soul counter (1225789) -- it's the 'spells empowered, Fury draining' buff." },
        { kind = "trackedAura", label = "Soul count tracked", spell = ID_SOULCOUNT,
          hint = "Track the soul aura (1225789) -- its stack is your COLLECTED souls (0-50), reads clean in combat, and anchors the ground-soul estimate. Inside the form this goes 'gone' and the counter pivots to Collapsing Star (1227702) -- track that too." },
        { kind = "trackedAura", label = "Collapsing Star tracked (in-form counter)", spell = ID_COLLAPSINGSTAR,
          hint = "Track Collapsing Star (1227702). Inside Void Metamorphosis its stack is the in-meta soul counter (toward 30), which replaces the 1225789 read." },
        { kind = "trackedAura", label = "Ground souls tracked", spell = ID_GROUNDSOULS,
          hint = "Track Soul Fragments (1245577). Its active state is the 'souls on the ground?' boolean PRIO uses to reset the ground estimate to 0 when nothing is out (kills drift)." },
        { kind = "trackedAura", label = "Soul Immolation tracked", spell = ID_SOULIMMO,
          hint = "Track Soul Immolation so its maintain-buff state reads (drives the 'refresh if missing' line)." },
        { kind = "trackedAura", label = "Hungering Slash tracked", spell = ID_HUNGERING,
          hint = "Track Hungering Slash (1239519) so PRIO sees the window where Voidblade is replaced by it (6s after The Hunt/Voidblade damage) and suggests it then." },
        { kind = "trackedAura", label = "Voidstep tracked", spell = ID_VOIDSTEP,
          hint = "Voidstep isn't in the default Cooldown Manager -- add it so the free Vengeful Retreat lines read. Without it those lines fail open (always shown)." },
        { kind = "info", label = "Fury",
          hint = "Fury is SECRET in combat -- PRIO can't read it, so Void Ray and other spenders fail open (shown even when you might be short). Exact Fury gating isn't possible on this spec." },
        { kind = "info", label = "Ground souls are ESTIMATED",
          hint = "Reap/Cull fire at >= 4 on the ground, Eradicate at >= 10 (capped). Estimate: souls pile up from casts (Consume/Devour +2, Void Ray +4, Collapsing Star +5, transform +5), Reap/Cull subtract 4, Eradicate clears it, and it zeroes when the 'souls on ground' boolean (1245577) says none are out. Track 1245577 so that anchor reads. Fails CLOSED (withheld unless the estimate confirms the threshold). Soul Immolation and Voidfall aren't counted -- watch 'Ground souls (est)' and tell me if it drifts." },
        { kind = "info", label = "Cull charges (Second Helping)",
          hint = "With Second Helping (1239537), Cull/Reap have 2 charges. PRIO reads charge state from the game directly (no CDM tracking needed): the debug shows 'Cull charges' with 'at max' / 'recharging (next Ns)'. In Void Meta, Cull also fires when at max charges (2) to avoid overcapping -- the 'Charges >= N' condition and the 'Cull charges full (2)' preset drive it. Untalented, the game reports 1 charge and the overcap line simply never fires." },
        { kind = "info", label = "In-form abilities wired",
          hint = "Devour (1217610) and Cull (1245453) are the in-form generator/spender and are fully wired. Inside Void Metamorphosis the priority uses them; outside it uses Consume/Reap." },
    },

    -- Opener: maintain Soul Immolation, Voidblade -> The Hunt -> Void Metamorphosis to
    -- burst into the form, then hand off to the normal rotation.
    openerReady = { "VoidMetamorphosis" },
    opener = { "SoulImmolation", "Voidblade", "TheHunt", "VoidMetamorphosis" },
    precombat = {},

    pickable = {
        "Consume", "Reap", "VoidRay", "SoulImmolation", "VoidMetamorphosis", "Voidblade",
        "VoidNova", "ThrowGlaive", "TheHunt", "HungeringSlash", "Eradicate",
        "ReapersToll", "PierceTheVeil", "PredatorsWake", "CollapsingStar", "Devour", "Cull",
        "VengefulRetreat", "Disrupt", "ConsumeMagic", "Blur", "Darkness", "SpectralSight",
    },

    fillers = { [ID_CONSUME] = true, [ID_DEVOUR] = true },   -- no-cooldown generators (outside / in-form)

    maelstromMax = 120,   -- Fury cap (generic "resource" fields)

    -- GROUND-SOUL counter (P.groundSouls, 0-10): souls pile up from your casts; gathers pull
    -- it down. The engine also floors it to 0 when the "souls on ground" boolean says none
    -- are out, and clamps to the 10 cap (souls made at cap auto-collect instead).
    --   * Consume / Devour +2, Void Ray +4, Collapsing Star +5, Void Metamorphosis +5
    --   * Reap / Cull -4 (gather up to 4)
    --   * Eradicate -> 0 (clears the ground)
    -- Soul Immolation is intentionally NOT counted; Voidfall's meteor soul isn't either.
    OnCast = function(P, key, now)
        P.groundSouls = P.groundSouls or 0
        if key == "Consume" or key == "Devour" then
            P.groundSouls = P.groundSouls + 2
        elseif key == "VoidRay" then
            P.groundSouls = P.groundSouls + 4
        elseif key == "CollapsingStar" then
            P.groundSouls = P.groundSouls + 5
        elseif key == "VoidMetamorphosis" then
            P.groundSouls = P.groundSouls + 5         -- transform drops 5 on the ground
        elseif key == "Reap" or key == "Cull" then
            P.groundSouls = P.groundSouls - 4         -- gather up to 4
        elseif key == "HungeringSlash" then
            P.groundSouls = P.groundSouls - 2         -- shatters up to 2
        elseif key == "Eradicate" then
            P.groundSouls = 0                         -- clears the ground
        end
        if P.groundSouls < 0 then P.groundSouls = 0 end
        if P.groundSouls > 10 then P.groundSouls = 10 end
    end,

    -- Cast-triggered cooldown RESETS (talent-gated). The engine forces the target ready in
    -- the queue look-ahead and keeps predicted cooldown in sync; the live off-cooldown read
    -- already reflects the reset. Each entry self-disables if you don't have the talent.
    cdResets = {
        VoidRay = { { target = "Reap", talent = ID_TAL_MOMENTCRAVE } },        -- Moment of Craving
        VoidMetamorphosis = {
            { target = "Reap",      talent = ID_TAL_MASSACCEL },               -- Mass Acceleration
            { target = "Voidblade", talent = ID_TAL_VIOLENT },                 -- Violent Transformation
            { target = "TheHunt",   talent = ID_TAL_VIOLENT },                 -- Violent Transformation
        },
        TheHunt = { { target = "SoulImmolation", talent = ID_TAL_VIOLENT } },  -- Violent Transformation
    },

    debug = {
        { label = "In Void Meta (form)",       kind = "buff", spell = ID_FORM },
        { label = "Collected souls (/50)",     kind = "buff", spell = ID_SOULCOUNT },
        { label = "In-meta counter (Coll.Star)", kind = "buff", spell = ID_COLLAPSINGSTAR },
        { label = "Souls on ground?",          kind = "buff", spell = ID_GROUNDSOULS },
        { label = "Cull charges",              kind = "chargeClean", spell = ID_CULL },   -- count + at max / recharging
        { label = "Soul Immolation",           kind = "buff", spell = ID_SOULIMMO },
    },
    economy = {
        gen   = { "Consume", "Devour (in-form)", "Soul collection" },
        spend = { "Void Ray (Fury)", "Reap / Cull", "Eradicate", "Reaper's Toll" },
    },

    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "VoidMetamorphosis", "Voidblade", "TheHunt", "VoidNova", "SoulImmolation",
            "Reap", "Cull", "Eradicate", "ReapersToll", "PierceTheVeil", "PredatorsWake",
            "CollapsingStar", "VoidRay", "Consume", "ThrowGlaive",
        },
        buffs = {
            { label = "In Void Meta (form)",       spell = ID_FORM },           -- transformed?
            { label = "Collected souls (/50)",     spell = ID_SOULCOUNT },      -- stack 0-50 (outside form)
            { label = "In-meta counter (Coll.Star)", spell = ID_COLLAPSINGSTAR }, -- stack -> 30 (inside form)
            { label = "Souls on ground?",          spell = ID_GROUNDSOULS },    -- active bool
            { label = "Hungering Slash (window)",   spell = ID_HUNGERING },      -- Voidblade replaced
            { label = "Soul Immolation",           spell = ID_SOULIMMO },
            { label = "Voidstep",                  spell = ID_VOIDSTEP },
            { label = "Moment of Craving",         spell = ID_MOMENTOFCRAVING },
        },
        glows = {
            { label = "Consume (Soulburst)", spell = ID_CONSUME },   -- glow = empowered instant Consume
            { label = "Devour (Soulburst)",  spell = ID_DEVOUR },    -- in-form empowered Devour
        },
        rangeProbes = {
            { label = "Ground souls (est)", kind = "predCount", field = "groundSouls" },   -- +2 per Consume, down on pickup
            { label = "Fury (predicted)",   kind = "resource" },
        },
    },

}

-- Live proxy resolving to the ACTIVE hero's list for a mode (editor / export / direct
-- reads). Customization lives in db.customPriorities, so the backing table stays empty.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.voidscarred
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
