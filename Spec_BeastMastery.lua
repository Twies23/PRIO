-- Spec_BeastMastery.lua ---------------------------------------------------------
-- Beast Mastery Hunter (spec 253), patch 12.1 (Midnight). Built from the Icy Veins /
-- Method 12.1 guides + in-game tooltip verification (2026-08-30). Covers both hero
-- trees -- Pack Leader (default) and Dark Ranger -- as separate priority variants.
-- Untalented lines are filtered by IsKnown and buff-gated lines go inert when the buff
-- never appears, so one file serves every build.
--
-- SIGNAL REALITY (what actually reads in combat -- the whole game of this addon):
--   * FOCUS is a filling bar -> SECRET in combat (like Energy/Rage). So Focus-value
--     gates are NOT used here; spenders stay visible via softPowerUsable and the queue
--     leans on cooldowns/charges/stacks instead. Focus pooling is a later refinement.
--   * FRENZY (272790) lives on the PET -> the Cooldown Viewer (player auras only) can
--     NEVER see it. We do NOT gate on it. Instead Barbed Shot is kept on cooldown /
--     off its 2-charge cap, which maintains Frenzy on its own. This is the honest,
--     readable proxy for "keep Frenzy up".
--   * BEAST CLEAVE (268877) is a pet-side cleave buff. It MAY surface as a player-
--     trackable aura in the Cooldown Manager -- track it and check /prio rotdebug. If
--     it never reads, the buffDown(BeastCleave) gate fails open and Wild Thrash simply
--     runs on cooldown (still correct, just not refresh-aware).
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
--   * Kill Command is CHARGE-tracked (2 charges). Its many CD reducers (Cobra Shot -1s,
--     War Orders +Barbed -3s, Master Handler -0.5s/tick, Killer Cobra full reset in BW)
--     effectively speed its recharge -- the charge tracker + live ready flag capture the
--     net result without modelling each source. See spec.talents for the reducer IDs.
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
local ID_BEASTCLEAVE = 268877     -- from Wild Thrash; pet-side, track-and-verify
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
local function stacksMin(id,n) return { type = "stacksMin",   spell = id, v = n } end
local function chargesMin(n)   return { type = "chargesMin",  v = n } end   -- self (the row's spell)
local function chargesMax(id,n) return { type = "chargesMax", spell = id, v = n } end
local function cdRemainMin(id,n) return { type = "cdRemainMin", spell = id, v = n } end
local function cdRemainMax(id,n) return { type = "cdRemainMax", spell = id, v = n } end
local function chargeTimeMax(id,n) return { type = "chargeTimeMax", spell = id, v = n } end   -- next charge within n s
local function glow(id)        return { type = "glowing",     spell = id } end
local function talent(id)      return { type = "talentYes",   spell = id } end

--------------------------------------------------------------------------------
-- PACK LEADER (default). Priority from the Icy Veins 12.1 single-target / AoE lists,
-- with major cooldowns (Call of the Wild / Bloodshed) folded in (inert if not talented)
-- and Kill Command kept pressable when no proc gates it.
--------------------------------------------------------------------------------
local pl_st = {
    -- Refresh Frenzy right before Bestial Wrath, or before Barbed Shot caps its 2 charges.
    { spell = "BarbedShot", cond = OR(cdRemainMax(ID_BESTIALWRATH, 3), chargesMin(2), chargeTimeMax(ID_BARBEDSHOT, 1.5)) },
    { spell = "BestialWrath" },                                   -- bread & butter, on CD (triggers Howl)
    { spell = "CallOfTheWild" },                                  -- major CD (talent; inert if not taken)
    { spell = "Bloodshed" },                                      -- talent, on CD
    { spell = "KillCommand", cond = glow(ID_KILLCOMMAND) },       -- Howl ready (KC glows) -> next KC summons a Beast
    -- Nature's Ally empowered KC, but bank the last charge when Bestial Wrath is imminent.
    { spell = "KillCommand", cond = AND(buffUp(ID_NATURESALLY), OR(chargesMin(2), cdRemainMin(ID_BESTIALWRATH, 3))) },
    { spell = "CobraShot", cond = AND(talent(ID_KILLERCOBRA), buffUp(ID_BESTIALWRATH)) }, -- Killer Cobra: reset KC in BW
    { spell = "CobraShot", cond = stacksMin(ID_COBRAFANG, 4) },   -- spend a capped Cobra Fang
    { spell = "BarbedShot" },                                     -- on cooldown (Frenzy upkeep)
    { spell = "KillCommand" },                                    -- primary spender (charges), no proc needed
    { spell = "KillShot" },                                       -- execute
    { spell = "CobraShot", cond = cdRemainMin(ID_BESTIALWRATH, 2) }, -- filler, unless BW is within a GCD
    { spell = "CobraShot" },                                      -- final Focus dump
}

local pl_aoe = {
    -- Wild Thrash (replaces Multi-Shot) puts / keeps Beast Cleave up. The condensed Icy
    -- list omits it; every other source keeps it at the top of AoE, so we do too.
    { spell = "WildThrash", cond = buffDown(ID_BEASTCLEAVE) },    -- put Beast Cleave up
    { spell = "BarbedShot", cond = OR(chargesMin(2), chargeTimeMax(ID_BARBEDSHOT, 1.5)) }, -- at / about to reach 2 charges (Frenzy)
    { spell = "BestialWrath" },                                   -- on CD
    { spell = "CallOfTheWild" },                                  -- major CD (talent)
    { spell = "WildThrash" },                                     -- on CD (keep Beast Cleave up)
    { spell = "Bloodshed" },                                      -- talent, on CD
    { spell = "KillCommand", cond = buffUp(ID_NATURESALLY) },     -- empowered KC
    { spell = "KillCommand" },                                    -- splashes via Beast Cleave
    { spell = "CobraShot", cond = AND(stacksMin(ID_COBRAFANG, 4), buffUp(ID_BEASTCLEAVE)) }, -- Cobra Fang cleaves (30%)
    { spell = "ExplosiveShot" },                                  -- AoE nuke (talent)
    { spell = "BarbedShot" },                                     -- on cooldown
    { spell = "KillShot" },                                       -- execute
    { spell = "CobraShot" },                                      -- filler
}

--------------------------------------------------------------------------------
-- DARK RANGER. Black Arrow becomes a high-priority builder/spender; Withering Fire
-- (first ~10s of Bestial Wrath) triples Black Arrow and converts Bestial Wrath into a
-- one-shot Wailing Arrow. Deathblow (Soul Drinker / Ebon Bowstring) resets Black Arrow
-- and lets it hit at any health -> read via the Black Arrow button glow.
--------------------------------------------------------------------------------
local dr_st = {
    { spell = "BarbedShot", cond = OR(cdRemainMax(ID_BESTIALWRATH, 3), chargesMin(2), chargeTimeMax(ID_BARBEDSHOT, 1.5)) },
    { spell = "BestialWrath" },                                   -- on CD -> opens Withering Fire
    { spell = "CallOfTheWild" },                                  -- major CD (talent)
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
    { spell = "BarbedShot", cond = OR(chargesMin(2), chargeTimeMax(ID_BARBEDSHOT, 1.5)) }, -- at / about to reach 2 charges (Frenzy)
    { spell = "BestialWrath", cond = buffUp(ID_BEASTCLEAVE) },    -- BW with Beast Cleave active
    { spell = "BestialWrath" },                                   -- else on CD
    { spell = "CallOfTheWild" },                                  -- major CD (talent)
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
    softPowerUsable = true,       -- Focus is a fast-regen secret bar -> keep spenders visible

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
          hint = "Track Beast Cleave so the AoE lines know when to refresh it (Wild Thrash). It is pet-side -- check /prio rotdebug; if it never reads, Wild Thrash still runs on cooldown." },
        { kind = "info", label = "Howl of the Pack Leader (KC glow)",
          hint = "No tracking needed: when Howl is ready your Kill Command button GLOWS in the Cooldown Manager, and PRIO reads that glow to prioritise the empowered Kill Command. Just keep Kill Command on your tracked bars." },
        { kind = "trackedAura", label = "Bestial Wrath tracked", spell = ID_BESTIALWRATH, optional = true,
          hint = "Track Bestial Wrath so 'during Bestial Wrath' reads (Killer Cobra line)." },
        { kind = "trackedAura", label = "Withering Fire tracked (Dark Ranger)", spell = ID_WITHERING, optional = true,
          hint = "Dark Ranger only: track Withering Fire for the triple-damage Black Arrow lines. The ID is a best guess -- confirm it with /prio spells." },
        { kind = "info", label = "Frenzy (pet buff)",
          hint = "Frenzy lives on your pet, so the Cooldown Manager (player auras only) can't track it. PRIO keeps it up indirectly by pressing Barbed Shot before it caps 2 charges -- no tracking needed." },
        { kind = "info", label = "Focus",
          hint = "Focus is a filling bar and is secret in combat, so PRIO doesn't gate on a Focus number. Spenders stay visible and the queue leans on cooldowns, charges and procs instead." },
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
    chargeTrack = {
        BarbedShot  = { max = 2, recharge = 12 },
        KillCommand = { max = 2, recharge = 7.5 },
    },

    -- Static cooldown model for the "Bestial Wrath soon / not soon" gates. 90s base, -60s
    -- from The Beast Within -> 30s. Anchored to the live ready flag, so a wrong base
    -- self-corrects the moment Bestial Wrath comes up.
    cooldownTrack = {
        BestialWrath = { base = 90, reduce = { [ID_BEASTWITHIN] = 60 } },
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
