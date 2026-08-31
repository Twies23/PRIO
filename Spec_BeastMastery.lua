-- Spec_BeastMastery.lua ---------------------------------------------------------
-- Beast Mastery Hunter (spec 253), patch 12.1 (Midnight). Built from the Icy Veins /
-- Method 12.1 guides + in-game tooltip verification (2026-08-30). Covers both hero
-- trees -- Pack Leader (default) and Dark Ranger -- as separate priority variants.
-- Untalented lines are filtered by IsKnown and buff-gated lines go inert when the buff
-- never appears, so one file serves every build.
--
-- SIGNAL REALITY (what actually reads in combat -- the whole game of this addon):
--   * FOCUS is a filling bar -> its VALUE is SECRET in combat. Spenders stay VISIBLE
--     (softPowerUsable; Focus regens fast), but the display DESATURATES one while the
--     game's clean insufficient-power flag says you can't yet afford it -- so you still
--     see it queued, just dimmed. No Focus-number prediction; pooling is a later refinement.
--   * FRENZY (272790) lives on the PET -> the Cooldown Viewer (player auras only) can
--     NEVER see it. We do NOT gate on it. Instead Barbed Shot is kept on cooldown /
--     off its 2-charge cap, which maintains Frenzy on its own. This is the honest,
--     readable proxy for "keep Frenzy up".
--   * BEAST CLEAVE (115939) surfaces as a Tracked Bar in the Cooldown Manager (verified
--     from a live dump 2026-08-31), so buffUp/buffDown(BeastCleave) read clean once it's
--     tracked. (The old 268877 guess was wrong and never read.)
--   * HUNTER'S MARK (257284) is a target debuff but shows in the Cooldown Manager's
--     Tracked Buffs, so debuffMissing(HuntersMark) reads and PRIO reapplies it when it's
--     down (e.g. after a target swap).
--   * HOWL OF THE PACK LEADER (471876): "every 30s your next Kill Command summons a
--     Beast." The ready state reads CLEAN off the Kill Command BUTTON GLOW in the
--     Cooldown Manager (confirmed in-game 2026-08-30) -- so we gate the empowered Kill
--     Command line on glow(KillCommand), not on the (untrackable pet-side) Howl aura.
--   * COBRA FANG (1299389) and NATURE'S ALLY (1273145) are PLAYER buffs -> they read
--     clean (stacks / active) when tracked. These are the reliable proc signals.
--
-- COOLDOWNS WE MODEL (spec.cooldownTrack, for the "Bestial Wrath soon" gates):
--   * Bestial Wrath is STATIC: 90s base, -60s from The Beast Within (231548) -> 30s.
--     Anchored to the live off-cooldown flag (ready => 0), so a wrong base self-corrects.
--   * Kill Command / Barbed Shot are CHARGE spells (2 charges). The exact COUNT reads clean
--     in combat (ChargeState via isActive + the usable flag -> 0/1/2), but the recharge
--     TIME is fully SECRET -- verified in-game 2026-08-31: BOTH the charge-duration object
--     AND GetSpellCooldown read secret in combat (dur:-- cd:-- in /prio rotdebug). So there
--     is no reliable sub-second "next charge" to read, and charge-maintenance gates on the
--     readable COUNT (press at 2 charges) rather than a predicted timer. The haste-scaled /
--     chargeCdr prediction (spec.chargeCdr, chargeTrack.hasted) is kept only for the queue
--     look-ahead and the out-of-combat editor condition, NOT the live suggestion.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local FOCUS = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2

-- Castable IDs (high-confidence; verify with /prio spells).
local ID_KILLCOMMAND  = 34026
local ID_BARBEDSHOT   = 217200
local ID_BESTIALWRATH = 19574     -- cast AND the player buff (readable) while active
local ID_COBRASHOT    = 193455
local ID_KILLSHOT     = 53351
local ID_WILDTHRASH   = 1264359   -- AoE spender, replaces Multi-Shot, grants Beast Cleave
local ID_CALLOFWILD   = 359844    -- major CD (talent)
local ID_BLOODSHED    = 321530    -- talent
local ID_EXPLOSIVE    = 212431    -- AoE (talent)
local ID_BLACKARROW   = 466930    -- Dark Ranger
local ID_WAILINGARROW = 392060    -- Dark Ranger (Bestial Wrath replacement during Withering Fire)
local ID_HUNTERSMARK  = 257284

-- Buff / proc IDs (verify with /prio tracked).
local ID_FRENZY      = 272790     -- PET buff -> UNTRACKABLE (see header). Documented only.
local ID_BEASTCLEAVE = 115939     -- Beast Cleave (verified from the live Cooldown Viewer TrackedBar, 2026-08-31)
local ID_COBRAFANG   = 1299389    -- PLAYER buff, stacks to 4 -> spend with Cobra Shot (4-SET tier bonus)
local ID_NATURESALLY = 1273145    -- PLAYER buff -> empowers Kill Command
local ID_HOWL        = 471876     -- Howl of the Pack Leader (ready = next KC summons a Beast)
local ID_WITHERING   = 471877     -- Withering Fire (Dark Ranger) -- UNVERIFIED, set via /prio spells

-- Talents / passives (registered for talent gates, cooldown math, and /prio spells).
-- Verified from in-game tooltips 2026-08-30.
local ID_DIRESUMMONS   = 472352   -- KC / Cobra Shot each -1s Howl cooldown
local ID_PACKMENTALITY = 472358   -- Howl +25% KC damage; beast summon -4s Barbed Shot
local ID_WARORDERS     = 393933   -- Barbed Shot +10% dmg and -3s Kill Command
local ID_BARBEDSCALES  = 469880   -- Cobra Shot -2s Barbed Shot
local ID_BEASTWITHIN   = 231548   -- Bestial Wrath -60s cooldown (static)
local ID_KILLERCOBRA   = 199532   -- during Bestial Wrath, Cobra Shot resets Kill Command
local ID_MASTERHANDLER = 424558   -- Barbed Shot tick -0.5s Kill Command
local ID_SOULDRINKER   = 469638   -- KC 20% / Barbed 50% -> Deathblow (Dark Ranger)
local ID_EBONBOWSTRING = 467897   -- Black Arrow 15% -> Deathblow (Dark Ranger)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)      return { type = "buffActive",  spell = id } end
local function buffDown(id)    return { type = "buffMissing", spell = id } end
local function debuffDown(id)  return { type = "debuffMissing", spell = id } end   -- enemy missing debuff
local function stacksMin(id,n) return { type = "stacksMin",   spell = id, v = n } end
local function chargesMin(n)   return { type = "chargesMin",  v = n } end   -- self (the row's spell)
local function chargesMax(id,n) return { type = "chargesMax", spell = id, v = n } end
local function cdRemainMin(id,n) return { type = "cdRemainMin", spell = id, v = n } end
local function cdRemainMax(id,n) return { type = "cdRemainMax", spell = id, v = n } end
local function glow(id)        return { type = "glowing",     spell = id } end
local function talent(id)      return { type = "talentYes",   spell = id } end
local function talentNo(id)    return { type = "talentNo",    spell = id } end
local function cdReady(id)     return { type = "cdReady",     spell = id } end
local function lastCast(id)    return { type = "lastCast",    spell = id } end
local function usable(id)      return { type = "usable",      spell = id } end   -- gates on Focus affordability (IsUsable)
local function chargesEq(n)    return { type = "chargesEq",   v = n } end         -- self (the row's spell)
local function enemiesMin(n)   return { type = "enemiesMin",  v = n } end
local function preset(key)     return { type = "preset:" .. key } end

--------------------------------------------------------------------------------
-- PACK LEADER (default). Priority from the Icy Veins 12.1 single-target / AoE lists,
-- with major cooldowns (Call of the Wild / Bloodshed) folded in (inert if not talented)
-- and Kill Command kept pressable when no proc gates it.
--------------------------------------------------------------------------------
-- Pack Leader ST -- user-tuned in-game (0.5.13). Spenders gate on "usable" (= Focus
-- affordable). Kill Command splits: Howl-glow, Nature's Ally (bank the last charge near
-- Bestial Wrath), and a plain line that only applies when you DON'T have the Nature's Ally
-- talent (with it, the two proc lines cover Kill Command).
local pl_st = {
    { spell = "HuntersMark", cond = debuffDown(ID_HUNTERSMARK) },                     -- keep the 3% debuff up
    { spell = "BarbedShot",  cond = OR(cdRemainMax(ID_BESTIALWRATH, 3), chargesEq(2)) }, -- refresh before BW / at 2 charges
    { spell = "BestialWrath", cond = cdReady(ID_BESTIALWRATH) },                      -- on cooldown (triggers Howl)
    { spell = "KillCommand", cond = AND(preset("howlReady"), usable(ID_KILLCOMMAND)) }, -- Howl ready -> summon a Beast
    { spell = "KillCommand", cond = AND(buffUp(ID_NATURESALLY), cdRemainMin(ID_BESTIALWRATH, 3), usable(ID_KILLCOMMAND)) }, -- Nature's Ally (BW not imminent)
    { spell = "KillCommand", cond = AND(talentNo(ID_NATURESALLY), usable(ID_KILLCOMMAND)) }, -- plain KC (no Nature's Ally talent)
    { spell = "KillCommand", cond = AND(buffUp(ID_NATURESALLY), cdRemainMax(ID_BESTIALWRATH, 3), chargesEq(2), usable(ID_KILLCOMMAND)) }, -- bank the last charge for BW
    { spell = "CobraShot",   cond = AND(stacksMin(ID_COBRAFANG, 4), usable(ID_COBRASHOT)) }, -- spend a capped Cobra Fang
    { spell = "BarbedShot" },                                                         -- on cooldown (Frenzy upkeep)
    { spell = "CobraShot",   cond = cdRemainMin(ID_BESTIALWRATH, 2) },                -- filler, unless BW is within a GCD
}

-- Pack Leader AoE -- user-tuned in-game (0.5.13). Wild Thrash right after Bestial Wrath
-- and on cooldown; Bestial Wrath held for Wild Thrash / Beast Cleave; Kill Command opened
-- up on 4+ targets (or Howl / when affordable); Cobra Shot cleaves with Cobra Fang + Beast
-- Cleave. Spenders gate on "usable" (Focus affordable).
local pl_aoe = {
    { spell = "HuntersMark", cond = debuffDown(ID_HUNTERSMARK) },                     -- keep the 3% debuff up
    { spell = "WildThrash",  cond = lastCast(ID_BESTIALWRATH) },                      -- right after Bestial Wrath
    { spell = "BarbedShot",  cond = chargesMin(2) },                                  -- at 2 charges (Frenzy)
    { spell = "BestialWrath", cond = OR(cdReady(ID_WILDTHRASH), buffUp(ID_BEASTCLEAVE)) }, -- with Wild Thrash ready / Beast Cleave up
    { spell = "WildThrash" },                                                         -- on cooldown (keep Beast Cleave up)
    { spell = "KillCommand", cond = OR(enemiesMin(4), preset("howlReady"), usable(ID_KILLCOMMAND)) }, -- 4+ targets / Howl / affordable
    { spell = "KillCommand", cond = AND(talentNo(ID_NATURESALLY), usable(ID_KILLCOMMAND)) }, -- plain KC (no Nature's Ally talent)
    { spell = "CobraShot",   cond = AND(buffUp(ID_COBRAFANG), buffUp(ID_BEASTCLEAVE), usable(ID_COBRASHOT)) }, -- Cobra Fang cleaves (30%)
    { spell = "BarbedShot" },                                                         -- on cooldown
    { spell = "CobraShot" },                                                          -- filler
}

--------------------------------------------------------------------------------
-- DARK RANGER. Black Arrow becomes a high-priority builder/spender; Withering Fire
-- (first ~10s of Bestial Wrath) triples Black Arrow and converts Bestial Wrath into a
-- one-shot Wailing Arrow. Deathblow (Soul Drinker / Ebon Bowstring) resets Black Arrow
-- and lets it hit at any health -> read via the Black Arrow button glow.
--------------------------------------------------------------------------------
local dr_st = {
    { spell = "BarbedShot", cond = OR(cdRemainMax(ID_BESTIALWRATH, 3), chargesMin(2)) }, -- refresh before BW / at 2 charges (the recharge time is secret in combat, so gate on the readable count)
    { spell = "BestialWrath" },                                   -- on CD -> opens Withering Fire
    { spell = "CallOfTheWild" },                                  -- major CD (talent)
    { spell = "HuntersMark", cond = debuffDown(ID_HUNTERSMARK) }, -- maintain the 3% damage-taken debuff (reapply on target swap)
    -- Triple-damage Black Arrow inside Withering Fire, without overcapping Kill Command.
    { spell = "BlackArrow", cond = AND(buffUp(ID_WITHERING), chargesMax(ID_KILLCOMMAND, 1)) },
    { spell = "BlackArrow", cond = glow(ID_BLACKARROW) },         -- Deathblow proc (reset + execute-anytime)
    { spell = "KillCommand", cond = AND(buffUp(ID_NATURESALLY), OR(chargesMin(2), cdRemainMin(ID_BESTIALWRATH, 3))) },
    { spell = "WailingArrow" },                                   -- BW-replacement nuke (castable only in its window)
    { spell = "CobraShot", cond = stacksMin(ID_COBRAFANG, 4) },   -- spend a capped Cobra Fang
    { spell = "KillCommand" },                                    -- primary spender (charges)
    { spell = "BlackArrow" },                                     -- on cooldown (DR core)
    { spell = "BarbedShot" },                                     -- Frenzy upkeep
    { spell = "KillShot" },                                       -- execute
    { spell = "CobraShot" },                                      -- filler
}

local dr_aoe = {
    { spell = "BlackArrow", cond = buffDown(ID_BEASTCLEAVE) },    -- DR: Black Arrow puts Beast Cleave up
    { spell = "WildThrash", cond = buffDown(ID_BEASTCLEAVE) },    -- fallback Beast Cleave source
    { spell = "BarbedShot", cond = chargesMin(2) },              -- at 2 charges (readable count; recharge time is secret)
    { spell = "BestialWrath", cond = buffUp(ID_BEASTCLEAVE) },    -- BW with Beast Cleave active
    { spell = "BestialWrath" },                                   -- else on CD
    { spell = "CallOfTheWild" },                                  -- major CD (talent)
    { spell = "HuntersMark", cond = debuffDown(ID_HUNTERSMARK) }, -- maintain the 3% damage-taken debuff (reapply on target swap)
    { spell = "WildThrash" },                                     -- on cooldown
    { spell = "BlackArrow", cond = buffUp(ID_WITHERING) },        -- triple-damage in the window
    { spell = "BlackArrow", cond = glow(ID_BLACKARROW) },         -- Deathblow proc
    { spell = "WailingArrow" },                                   -- AoE shadow nuke (window)
    { spell = "KillCommand", cond = buffUp(ID_NATURESALLY) },     -- empowered KC
    { spell = "KillCommand" },                                    -- splashes via Beast Cleave
    { spell = "CobraShot", cond = AND(stacksMin(ID_COBRAFANG, 4), buffUp(ID_BEASTCLEAVE)) },
    { spell = "ExplosiveShot" },                                  -- AoE nuke (talent)
    { spell = "BlackArrow" },                                     -- on cooldown
    { spell = "BarbedShot" },                                     -- on cooldown
    { spell = "KillShot" },                                       -- execute
    { spell = "CobraShot" },                                      -- filler
}

-- Only ST and AoE modes (no separate Cleave tier); AoE covers 2+ targets.
local heroLists = {
    pack_leader = { st = pl_st, aoe = pl_aoe },
    dark_ranger = { st = dr_st, aoe = dr_aoe },
}

-- Active hero from a STRICT known-check on the keystone (talent/spellbook state, not an
-- aura). Howl of the Pack Leader is the Pack Leader keystone; Black Arrow the Dark Ranger
-- one. Default Pack Leader (the meta pick). Per-hero customization stores separately in db.
local function activeHero()
    if API and API.IsKnownStrict then
        if API.IsKnownStrict(ID_HOWL) then return "pack_leader" end
        if API.IsKnownStrict(ID_BLACKARROW) then return "dark_ranger" end
    end
    return "pack_leader"
end

local spec = {
    key      = "HUNTER_BEASTMASTERY",
    label    = "Beast Mastery",
    className = "Hunter",
    specID   = 253,
    resource = FOCUS,
    resourceLabel = "Focus",
    maelstromMax = 100,           -- Focus cap (secret in combat; used for the resource readout only)

    -- Focus is a fast-regen secret bar. Keep spenders VISIBLE even when you can't afford them
    -- yet (softPowerUsable) -- you'll have the Focus in a moment -- but the display DESATURATES
    -- a spender while the game's insufficient-power flag says you can't afford it (a clean read
    -- even with the bar secret, driven per-pick via API.InsufficientPower -> entry.noResource).
    -- So a Focus-starved spender still shows as "next", just dimmed until the Focus is there.
    softPowerUsable = true,

    -- Only ST and AoE modes; AoE (Wild Thrash / Beast Cleave) starts at 2 targets.
    -- cleaveAt == aoeAt collapses the middle Cleave tier (Engine skips it).
    cleaveAt = 2,
    aoeAt    = 2,
    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    -- Hero split (see heroLists). activeHero picks the live list; priorityVariants drives
    -- the Options hero picker and per-hero custom lists.
    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "pack_leader", label = "Pack Leader" },
        { key = "dark_ranger", label = "Dark Ranger" },
    },

    -- Named presets surfaced in the condition editor (meaning, not mechanics).
    condPresets = {
        { key = "cobraFangCap", label = "Cobra Fang capped (4)", clause = stacksMin(ID_COBRAFANG, 4) },
        { key = "naturesAlly",  label = "Nature's Ally up",      clause = buffUp(ID_NATURESALLY) },
        { key = "howlReady",    label = "Howl ready (KC glow)",  clause = glow(ID_KILLCOMMAND) },
        { key = "beastCleave",  label = "Beast Cleave up",       clause = buffUp(ID_BEASTCLEAVE) },
        { key = "bwSoon",       label = "Bestial Wrath soon",    clause = cdRemainMax(ID_BESTIALWRATH, 3) },
        { key = "witheringFire", label = "Withering Fire up",    clause = buffUp(ID_WITHERING) },
        { key = "deathblow",    label = "Deathblow (Black Arrow)", clause = glow(ID_BLACKARROW) },
        { key = "markMissing",  label = "Hunter's Mark missing",  clause = debuffDown(ID_HUNTERSMARK) },
    },

    -- Relevant buffs (selectable in the condition editor regardless of build). Frenzy is
    -- listed for reference but lives on the pet, so it can't be tracked.
    auras = {
        Frenzy       = ID_FRENZY,
        BeastCleave  = ID_BEASTCLEAVE,
        CobraFang    = ID_COBRAFANG,
        NaturesAlly  = ID_NATURESALLY,
        Howl         = ID_HOWL,
        BestialWrath = ID_BESTIALWRATH,
        WitheringFire = ID_WITHERING,
        HuntersMark  = ID_HUNTERSMARK,
    },

    -- Talent/passive IDs (verified in-game). Registered so talent gates, cooldown math,
    -- and /prio spells all resolve. Not castable rows -- documentation + gating only.
    talents = {
        DireSummons = ID_DIRESUMMONS, PackMentality = ID_PACKMENTALITY, WarOrders = ID_WARORDERS,
        BarbedScales = ID_BARBEDSCALES, TheBeastWithin = ID_BEASTWITHIN, KillerCobra = ID_KILLERCOBRA,
        MasterHandler = ID_MASTERHANDLER, SoulDrinker = ID_SOULDRINKER, EbonBowstring = ID_EBONBOWSTRING,
    },

    setup = {
        { kind = "trackedAura", label = "Cobra Fang tracked (4-set)", spell = ID_COBRAFANG, optional = true,
          hint = "Only with the 4-piece tier set: Cobra Fang is that bonus, so track it to prioritise Cobra Shot at 4 stacks. Without the set the buff never appears and those lines stay inert -- harmless to skip." },
        { kind = "trackedAura", label = "Nature's Ally tracked", spell = ID_NATURESALLY,
          hint = "Track Nature's Ally so the empowered Kill Command lines read (player buff, reads clean)." },
        { kind = "trackedAura", label = "Beast Cleave tracked", spell = ID_BEASTCLEAVE,
          hint = "Track Beast Cleave (it appears in your Cooldown Manager's Tracked Bars) so the AoE lines know when to refresh it with Wild Thrash." },
        { kind = "trackedAura", label = "Hunter's Mark tracked", spell = ID_HUNTERSMARK,
          hint = "Track Hunter's Mark so PRIO reapplies it when your target is missing the 3% damage-taken debuff (e.g. after a target swap)." },
        { kind = "info", label = "Howl of the Pack Leader (KC glow)",
          hint = "No tracking needed: when Howl is ready your Kill Command button GLOWS in the Cooldown Manager, and PRIO reads that glow to prioritise the empowered Kill Command. Just keep Kill Command on your tracked bars." },
        { kind = "trackedAura", label = "Bestial Wrath tracked", spell = ID_BESTIALWRATH, optional = true,
          hint = "Track Bestial Wrath so 'during Bestial Wrath' reads (Killer Cobra line)." },
        { kind = "trackedAura", label = "Withering Fire tracked (Dark Ranger)", spell = ID_WITHERING, optional = true,
          hint = "Dark Ranger only: track Withering Fire for the triple-damage Black Arrow lines. The ID is a best guess -- confirm it with /prio spells." },
        { kind = "info", label = "Frenzy (pet buff)",
          hint = "Frenzy lives on your pet, so the Cooldown Manager (player auras only) can't track it. PRIO keeps it up indirectly by pressing Barbed Shot before it caps 2 charges -- no tracking needed." },
        { kind = "info", label = "Focus",
          hint = "Focus is secret in combat, so PRIO doesn't read the number -- spenders still show, but a spender is dimmed (desaturated) while the game's insufficient-power flag says you can't afford it yet. No tracking needed." },
    },

    spells = {
        KillCommand   = ID_KILLCOMMAND,
        BarbedShot    = ID_BARBEDSHOT,
        BestialWrath  = ID_BESTIALWRATH,
        CobraShot     = ID_COBRASHOT,
        KillShot      = ID_KILLSHOT,
        WildThrash    = ID_WILDTHRASH,
        CallOfTheWild = ID_CALLOFWILD,
        Bloodshed     = ID_BLOODSHED,
        ExplosiveShot = ID_EXPLOSIVE,
        BlackArrow    = ID_BLACKARROW,
        WailingArrow  = ID_WAILINGARROW,
        HuntersMark   = ID_HUNTERSMARK,
    },

    -- Opener (Icy Veins 12.1): Hunter's Mark pre-pull, then Barbed Shot x2 around Bestial
    -- Wrath, Kill Command, Cobra Shot, hand off to the priority. AoE leads with Barbed +
    -- Wild Thrash to seed Beast Cleave.
    openerReady = { "BestialWrath" },
    opener = { "BarbedShot", "BarbedShot", "BestialWrath", "KillCommand", "CobraShot", "BarbedShot", "KillCommand" },
    openerAoe = { "BarbedShot", "WildThrash", "BestialWrath", "KillCommand", "BarbedShot", "KillCommand" },

    precombat = {
        { spell = "HuntersMark", aura = ID_HUNTERSMARK },
    },

    pickable = {
        "BarbedShot", "KillCommand", "BestialWrath", "CobraShot", "WildThrash", "KillShot",
        "CallOfTheWild", "Bloodshed", "ExplosiveShot", "BlackArrow", "WailingArrow", "HuntersMark",
    },

    -- Barbed Shot and Kill Command both run on 2 charges (KC needs Alpha Predator; the
    -- tracker learns the real max from the client, so 1-charge builds self-correct).
    -- Both recharge with spell haste, and the game's own recharge read is SECRET in combat
    -- (verified in-game), so `hasted` tells the engine to predict from base / (1 + haste%)
    -- using the live, readable haste -- keeping the "about to cap" timing honest.
    chargeTrack = {
        BarbedShot  = { max = 2, recharge = 12,  hasted = true },
        KillCommand = { max = 2, recharge = 7.5, hasted = true },
    },

    -- Static cooldown model for the "Bestial Wrath soon / not soon" gates. 90s base, -60s
    -- from The Beast Within -> 30s. Anchored to the live ready flag, so a wrong base
    -- self-corrects the moment Bestial Wrath comes up.
    cooldownTrack = {
        BestialWrath = { base = 90, reduce = { [ID_BEASTWITHIN] = 60 } },
    },

    -- Cast-triggered CHARGE-recharge reductions, so the predicted next-charge timers (and
    -- the charge-time gates / debug seconds) reflect how fast Kill Command and Barbed Shot
    -- really come back. Modeled from the in-game tooltips:
    --   Cobra Shot -> -1s Kill Command (baseline), -2s Barbed Shot (Barbed Scales),
    --                 and a full Kill Command reset in Bestial Wrath (Killer Cobra).
    --   Barbed Shot -> -3s Kill Command (War Orders).
    -- NOT modeled (periodic / tick-based; the readable ready flag still corrects the COUNT,
    -- only the predicted seconds run slightly slow): Pack Mentality's -4s Barbed Shot on
    -- each Beast summon, and Master Handler's -0.5s Kill Command per Barbed Shot tick. Dire
    -- Summons only speeds Howl, which we read from the Kill Command glow, not by timing it.
    chargeCdr = {
        CobraShot = {
            { target = "KillCommand", sec = 1 },                                          -- baseline
            { target = "BarbedShot",  sec = 2, talent = ID_BARBEDSCALES },                -- Barbed Scales
            { target = "KillCommand", reset = true, talent = ID_KILLERCOBRA, whenBuff = ID_BESTIALWRATH }, -- Killer Cobra
        },
        BarbedShot = {
            { target = "KillCommand", sec = 3, talent = ID_WARORDERS },                   -- War Orders
        },
    },

    fillers = { [ID_COBRASHOT] = true },   -- Cobra Shot is the no-cooldown Focus dump

    flash = {
        KillCommand = { type = "glowing",   spell = ID_KILLCOMMAND },   -- Howl ready (empowered KC)
        KillShot    = { type = "cdReady",   spell = ID_KILLSHOT },      -- execute window opened
        BlackArrow  = { type = "glowing",   spell = ID_BLACKARROW },    -- Deathblow proc (Dark Ranger)
    },

    -- Wild Thrash grants Beast Cleave (AoE lines refresh it).
    spellEffects = {
        WildThrash = { grant = { ID_BEASTCLEAVE } },
    },

    OnCast = function(P, key, now) end,

    --------------------------------------------------------------------------------
    -- Debug metadata (see Debug.lua). Rows shown live; economy is informational.
    --------------------------------------------------------------------------------
    debug = {
        { label = "Kill Command (chg/next)", kind = "chargeTime", key = "KillCommand", spell = ID_KILLCOMMAND },
        { label = "Barbed Shot (chg/next)",  kind = "chargeTime", key = "BarbedShot",  spell = ID_BARBEDSHOT },
        { label = "Cobra Fang",              kind = "buff",     spell = ID_COBRAFANG },
        { label = "Nature's Ally",           kind = "buff",     spell = ID_NATURESALLY },
        { label = "Beast Cleave",            kind = "buff",     spell = ID_BEASTCLEAVE },
        { label = "Bestial Wrath (CD left)", kind = "cdRemain", spell = ID_BESTIALWRATH },
    },
    economy = {
        gen   = { "Auto-shot", "Barbed Shot" },
        spend = { "Kill Command", "Cobra Shot", "Wild Thrash" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug): the live signals the rotation
    -- actually reads. abilities = cooldown/charges/usable; buffs = what the Cooldown
    -- Manager reports; rangeProbes = Cobra Fang stacks + the Bestial Wrath timer.
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "BestialWrath", "KillCommand", "BarbedShot", "WildThrash", "CobraShot",
            "KillShot", "CallOfTheWild", "BlackArrow", "WailingArrow",
        },
        buffs = {
            { label = "Cobra Fang (stacks)",    spell = ID_COBRAFANG },
            { label = "Nature's Ally",          spell = ID_NATURESALLY },
            { label = "Beast Cleave",           spell = ID_BEASTCLEAVE },
            { label = "Howl (ready?)",          spell = ID_HOWL },
            { label = "Bestial Wrath (active)", spell = ID_BESTIALWRATH },
            { label = "Withering Fire (DR)",    spell = ID_WITHERING },
            { label = "Hunter's Mark (target)", spell = ID_HUNTERSMARK },
        },
        glows = {
            { label = "Kill Command (Howl ready)", spell = ID_KILLCOMMAND },
            { label = "Black Arrow (Deathblow)",    spell = ID_BLACKARROW },
        },
        rangeProbes = {
            -- Confirms Focus is secret in combat (nothing gates on its value here).
            { label = "Focus", kind = "resource" },
            -- Does Cobra Fang's stack count read via a direct aura query in combat?
            { label = "Cobra Fang (direct)", kind = "directAura", spell = ID_COBRAFANG },
        },
    },
}

-- spec.priority is a live proxy resolving to the ACTIVE hero's list for a mode (editor /
-- export / any direct read). Customization lives in db.customPriorities, so the backing
-- table stays empty and the __index resolver is safe.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.pack_leader
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
