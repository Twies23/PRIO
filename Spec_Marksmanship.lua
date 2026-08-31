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

local API = PRIO.API
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

-- Talents (verified in-game 2026-08-31).
local ID_CANTMISS      = 1253830  -- Can't Miss, Won't Miss: Trueshot duration +2s (15 -> 17)
local ID_CALLINGSHOTS  = 260404   -- Calling the Shots: Trueshot cooldown -30s (120 -> 90)
local ID_UNBREAKABLE   = 1223323  -- Unbreakable Bond: regains Call Pet (MM is petless without it)
local ID_TRICKSHOTS_T  = 257621   -- Trick Shots talent (choice node) -- same id as its buff
local ID_ASPECTHYDRA   = 470945   -- Aspect of the Hydra talent (choice node opposite Trick Shots)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)      return { type = "buffActive",   spell = id } end
local function buffDown(id)    return { type = "buffMissing",  spell = id } end
local function debuffDown(id)  return { type = "debuffMissing", spell = id } end
local function debuffUp(id)    return { type = "debuffActive", spell = id } end
local function usable(id)      return { type = "usable",       spell = id } end
local function petMissing()    return { type = "petMissing" } end
local function petDead()       return { type = "petDead" } end
local function talentYes(id)   return { type = "talentYes", spell = id } end
local function auraRemainMax(id,n) return { type = "auraRemainMax", spell = id, v = n } end
local function predFalse(key)  return { type = "predFalse", key = key } end
local function cdReady(id)     return { type = "cdReady",     spell = id } end
local function cdRemainMin(id,n) return { type = "cdRemainMin", spell = id, v = n } end
local function lastCast(id)    return { type = "lastCast",    spell = id } end
local function glow(id)        return { type = "glowing",     spell = id } end
-- Moonlight Chakram replaces the Trueshot button during Trueshot and its CDM icon GLOWS
-- when it's castable -- the clean "cast it now" signal (cdReady is unreliable for an
-- override spell). Read the glow off either the Chakram or the Trueshot frame.
local function chakramGlow() return OR(glow(1264902), glow(288613)) end
local function chargesMin(n)   return { type = "chargesMin",  v = n } end   -- self (the row's spell)
local function enemiesMin(n)   return { type = "enemiesMin",  v = n } end
-- MM only has a pet WITH Unbreakable Bond (petless Lone Wolf otherwise), so the pet-check
-- lines gate on that talent -- inert on a Lone Wolf build, active once you take the pet.
local function petGuarded(inner) return AND(talentYes(ID_UNBREAKABLE), inner) end
-- The target's "mark" -- Spotter's Mark at base, Sentinel's Mark with the hero talent.
-- Reads whichever is present, so it works while levelling and at max.
local function markUp()   return OR(debuffUp(ID_SPOTTERMARK), debuffUp(ID_SENTMARK)) end
local function markDown() return AND(debuffDown(ID_SPOTTERMARK), debuffDown(ID_SENTMARK)) end
-- Hunter's Mark reads as the TARGET's unit aura (UnitAuraID 257284) -- per-target, so it
-- re-prompts on a target swap. Fail-closed: "missing" only fires when the target is
-- confirmed to lack it (no nag with no target / an unreadable read). NOT the CDM buff read
-- (that only says "a mark exists somewhere" and doesn't follow the swap).
local function hmarkDown() return { type = "tgtAuraMissing", spell = ID_HUNTERSMARK } end
local function hmarkUp()   return { type = "tgtAura",        spell = ID_HUNTERSMARK } end

--------------------------------------------------------------------------------
-- Sentinel priority -- user-tuned in-game (0.6.8). Explosive Shot / Volley on CD; hold
-- Trueshot until Explosive is >=15s out (send Explos right before Trueshot) then pop it
-- right after Explosive; Moonlight Chakram inside Trueshot; spend Precise Shots on Kill /
-- Arcane; Aimed Shot on cooldown; Steady Shot filler. Without Trick Shots the ST and AoE
-- lists are identical, so AoE is a clone (the Trick Shots variant is a separate list).
--------------------------------------------------------------------------------
-- Sentinel -- user-tuned in-game (0.6.13), used for BOTH ST and AoE (the Aspect of the
-- Hydra Multi-Shot line self-gates on 2+ targets, so AoE == ST). Moonlight Chakram near
-- the end of Trueshot (<=7s) and as a filler in Trueshot; Kill Shot / Arcane spend Precise.
local st = {
    { spell = "CallPet",     cond = petGuarded(petMissing()) },       -- (Unbreakable Bond) no pet -> summon
    { spell = "RevivePet",   cond = petGuarded(petDead()) },          -- (Unbreakable Bond) pet dead -> revive
    { spell = "HuntersMark", cond = hmarkDown() },                    -- keep the target's Hunter's Mark up (per-target read)
    { spell = "ExplosiveShot", cond = cdReady(ID_EXPLOSIVE) },        -- on CD (2 casts, Unstable Trigger)
    { spell = "Volley",      cond = cdReady(ID_VOLLEY) },             -- on CD
    { spell = "Trueshot",    cond = AND(cdRemainMin(ID_EXPLOSIVE, 15), buffDown(ID_TRUESHOT), cdReady(ID_TRUESHOT)) }, -- hold until Explosive is >=15s out
    { spell = "Trueshot",    cond = lastCast(ID_EXPLOSIVE) },         -- pop right after Explosive Shot
    { spell = "MoonlightChakram", cond = AND(buffUp(ID_TRUESHOT), auraRemainMax(ID_TRUESHOT, 7), predFalse("chakramUsed")) }, -- ~end of Trueshot, once per window
    { spell = "RapidFire" },                                          -- on CD, builds Precise
    { spell = "KillShot",    cond = buffUp(ID_PRECISE) },             -- spend Precise (execute)
    { spell = "MultiShot",   cond = AND(buffUp(ID_PRECISE), enemiesMin(2), talentYes(ID_ASPECTHYDRA)) }, -- Hydra: spend Precise on 2+
    { spell = "ArcaneShot",  cond = buffUp(ID_PRECISE) },             -- spend Precise -> apply the mark
    { spell = "AimedShot" },                                          -- on CD (charges), consumes the mark
    { spell = "MoonlightChakram", cond = AND(buffUp(ID_TRUESHOT), predFalse("chakramUsed")) }, -- in Trueshot, once per window
    { spell = "SteadyShot" },                                         -- Focus filler
}

--------------------------------------------------------------------------------
-- DARK RANGER priority (Icy Veins 12.1). Black Arrow is the high-priority Precise
-- spender + core cooldown; Wailing Arrow on CD; Aimed Shot in Trueshot without Precise
-- when Black Arrow is ready. Target-preference notes ("prefer unmarked") are left to you
-- for now -- the Switch Targets node will surface those. TO TUNE in-game.
--------------------------------------------------------------------------------
local dr_st = {
    { spell = "CallPet",     cond = petGuarded(petMissing()) },
    { spell = "RevivePet",   cond = petGuarded(petDead()) },
    { spell = "HuntersMark", cond = hmarkDown() },                    -- per-target read (re-prompts on swap)
    { spell = "BlackArrow",  cond = buffUp(ID_PRECISE) },              -- spend Precise (prefer unmarked)
    { spell = "ExplosiveShot", cond = cdReady(ID_EXPLOSIVE) },        -- on CD (Unstable Trigger x2)
    { spell = "Volley",      cond = cdReady(ID_VOLLEY) },             -- on CD
    { spell = "AimedShot",   cond = OR(AND(buffUp(ID_TRUESHOT), buffDown(ID_PRECISE), cdReady(ID_BLACKARROW)), chargesMin(2)) }, -- in Trueshot w/o Precise if Black Arrow up, or at 2 charges
    { spell = "Trueshot",    cond = AND(cdRemainMin(ID_EXPLOSIVE, 15), buffDown(ID_TRUESHOT), cdReady(ID_TRUESHOT)) }, -- hold until Explosive is >=15s out
    { spell = "Trueshot",    cond = lastCast(ID_EXPLOSIVE) },         -- pop right after Explosive
    { spell = "WailingArrow", cond = cdReady(ID_WAILINGARROW) },      -- on CD
    { spell = "RapidFire" },                                          -- builder (stay on the priority target)
    { spell = "ArcaneShot",  cond = buffUp(ID_PRECISE) },             -- spend Precise
    { spell = "AimedShot" },                                          -- on CD
    { spell = "BlackArrow" },                                         -- on CD
    { spell = "SteadyShot" },                                         -- Focus filler
}

-- Variant split (like BM's Pack Leader / Dark Ranger): Dark Ranger when Black Arrow is
-- talented, else Sentinel (the default). Sentinel uses the same list for ST and AoE (the
-- Aspect of the Hydra Multi-Shot line self-gates on 2+ targets). Per-variant customization
-- stores separately in db.
local heroLists = {
    sentinel    = { st = st,    aoe = st },
    dark_ranger = { st = dr_st, aoe = dr_st },
}
local function activeHero()
    if API and API.IsKnownStrict and API.IsKnownStrict(ID_BLACKARROW) then return "dark_ranger" end
    return "sentinel"
end

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

    -- Named conditions surfaced in the editor. The Chakram button glow doesn't read (it's
    -- not a proc overlay), so "Chakram available" uses the reliable signal instead: Trueshot
    -- active AND not yet used this window. (The raw glow reads are kept too, in case a future
    -- client exposes them.)
    condPresets = {
        { key = "chakramReady", label = "Chakram available",  clause = AND(buffUp(ID_TRUESHOT), predFalse("chakramUsed")) },
        { key = "chakramGlow",  label = "Chakram glowing (raw)", clause = OR(glow(ID_MOONCHAKRAM), glow(ID_TRUESHOT)) },
        { key = "hmarkDown",    label = "Hunter's Mark missing (target)", clause = hmarkDown() },
        { key = "hmarkUp",      label = "Hunter's Mark on target",        clause = hmarkUp() },
    },

    -- Action nodes: spell-less priority instructions the strip shows on a condition (always
    -- "off cooldown"). Placed in a list as { action = "<key>", cond = ... }.
    actions = {
        switchTargets = { texture = 450908, label = "Target Switch", desaturate = true },
    },

    -- Keybind aliases: an override spell has no bind of its own -- Moonlight Chakram is cast
    -- on the Trueshot key, so show Trueshot's keybind for it.
    keybindAlias = { [ID_MOONCHAKRAM] = ID_TRUESHOT },

    -- Variant split: Sentinel (default) / Dark Ranger, auto-selected from Black Arrow.
    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "sentinel",    label = "Sentinel" },
        { key = "dark_ranger", label = "Dark Ranger" },
    },

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
        Trueshot      = { base = 120, reduce = { [ID_CALLINGSHOTS] = 30 } },  -- Calling the Shots -> 90s
        ExplosiveShot = { base = 30, window = 3 },
    },

    -- Trueshot's buff DURATION (15s base, +2s with Can't Miss, Won't Miss). Seeded on cast
    -- and read via "Buff time left" conditions -- the window is fixed and secret in combat,
    -- so we time it from the cast. Drives "Moonlight Chakram at ~5s left", "hold X", etc.
    auraDurations = {
        Trueshot = { spell = ID_TRUESHOT, base = 15, extend = { [ID_CANTMISS] = 2 } },
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

    -- Moonlight Chakram REPLACES the Trueshot button during Trueshot and can be used ONCE
    -- per window. The button glow doesn't read (it's not a proc overlay) and Chakram's
    -- cooldown/usable read is always true, so we track "used this window" from casts: the
    -- override may report as Trueshot's id, so a Trueshot-key cast while Trueshot is ALREADY
    -- active is really the Chakram press (mark used); a Trueshot cast while it's NOT active
    -- is the window start (reset). The Chakram lines gate on buffUp(Trueshot) + predFalse.
    OnCast = function(P, key, now)
        P.predFlags = P.predFlags or {}
        if key == "MoonlightChakram" then
            P.predFlags.chakramUsed = true
        elseif key == "Trueshot" then
            if API.IsAuraActive(ID_TRUESHOT) == true then
                P.predFlags.chakramUsed = true     -- Chakram press (override on the Trueshot key)
            else
                P.predFlags.chakramUsed = false    -- window start
            end
        end
    end,

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
        { label = "Trueshot (dur left)",   kind = "auraRemain", spell = ID_TRUESHOT },
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
            { label = "Trueshot (active)",   spell = ID_TRUESHOT },
        },
        rangeProbes = {
            { label = "Focus", kind = "resource" },
            -- Hunter's Mark on the CURRENT TARGET (UnitAuraID 257284) -- the per-target read
            -- the maintenance line uses, unlike the CDM buff ("a mark exists somewhere").
            { label = "Hunter's Mark (target)", kind = "targetAura", spell = ID_HUNTERSMARK },
            -- Moonlight Chakram once-per-Trueshot: false = available this window, true = used.
            { label = "Chakram used (window)", kind = "predFlag", key = "chakramUsed" },
        },
    },

}

-- spec.priority is a live proxy resolving to the ACTIVE variant's list for a mode.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.sentinel
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
