-- Spec_Arms.lua ----------------------------------------------------------------
-- Arms Warrior (spec 71), patch 12.1 (Midnight).
--
-- HERO-SPLIT: the two hero trees play with different orderings, so this spec holds
-- TWO complete lists per mode and picks one at runtime (mirrors Windwalker):
--   * Slayer   -- Sudden Death / Imminent Demise / Bladestorm-weaving (default)
--   * Colossus -- Demolish during the Colossus Smash window; no Bladestorm weave
-- `spec.priority` is a live metatable proxy that returns the ACTIVE hero's list on
-- read, so the engine, condition editor, and export always see the right list, and
-- it swaps automatically on a talent change. Active hero is decided by a STRICT
-- known-check on Demolish (436358) -- the Colossus capstone ability that Slayer
-- never has -- so it can't flip just because a buff/debuff became tracked.
--
-- Untalented abilities are filtered by IsKnown; talent-only lines are gated with
-- talentYes/No or go inert when their buff never appears. Spell IDs verified via
-- /prio spells; Demolish confirmed 436358.
--
-- Resource note: Rage is a filling bar -> secret in combat (like Focus/Maelstrom),
-- so it's predicted and spenders never hard-gate in combat (fail open).
-- Health is secret too, so execute-range usage can't be detected -- Execute is
-- driven by the Sudden Death proc here, which is the readable trigger.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1

-- Readable buff/debuff IDs (verified via /prio tracked in 12.1).
local ID_SUDDENDEATH  = 29725    -- Sudden Death (free/instant Execute) -- tracked buff
local ID_COLLATERAL   = 334779   -- Collateral Damage (stacks to 3; Sweeping Strikes)
local ID_EXECPREC     = 386634   -- Executioner's Precision TALENT (also the predicted-counter key)
local ID_EXECPREC_AURA = 386633  -- Executioner's Precision BUFF (what the Cooldown Manager shows)
local ID_IMMINENT     = 445606   -- Imminent Demise (stacks)
local ID_COLOSSUS_DBF = 167105   -- Colossus Smash (tracked bar / debuff)
local ID_SWEEPING     = 260708   -- Sweeping Strikes (self)
local ID_REND         = 772      -- Rend debuff (on target)
local ID_DEMOLISH     = 436358   -- Demolish (Colossus capstone -- hero signature)
local ID_BLADESTORM   = 227847   -- Bladestorm (Slayer weave gate)

local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function talent(id)   return { type = "talentYes",   spell = id } end
local function refreshable(id) return { type = "refreshable", spell = id } end
local function cdReady(id)  return { type = "cdReady",     spell = id } end
local function stacksMin(id, n) return { type = "stacksMin", spell = id, v = n } end
local function stacksMax(id, n) return { type = "stacksMax", spell = id, v = n } end
local function chargesMin(id, n) return { type = "chargesMin", spell = id, v = n } end
-- Proc-glow reads (secret-safe boolean stand-ins for stacks we can't read):
--   Execute glow    = Sudden Death proc up
--   Bladestorm glow = Imminent Demise at 3
--   Cleave glow     = Collateral Damage at 3
local function glowing(id)    return { type = "glowing",    spell = id } end
local function notGlowing(id) return { type = "notGlowing", spell = id } end
-- Predicted stack count (our own cast counter; Executioner's Precision):
local function predMin(id, n) return { type = "predStackMin", spell = id, v = n } end
-- Named preset reference (resolves to a glow/predstack clause). These are what the
-- lists and the condition editor show ("Sudden Death up", etc.) -- the raw glow /
-- predicted-stack types are never exposed to the user.
local function preset(key) return { type = "preset:" .. key } end
local function debuffDown(id) return { type = "debuffMissing", spell = id } end  -- enemy missing debuff
local function lastCastNot(id) return { type = "lastCastNot", spell = id } end   -- didn't just cast

local API = PRIO.API

--------------------------------------------------------------------------------
-- HERO LISTS. Slayer is the default; Colossus swaps Bladestorm-weaving for the
-- Demolish burst window. Cleave (2-target) = Sweeping Strikes + the hero's ST list.
--------------------------------------------------------------------------------

-- Readable signals below are surfaced as named presets (see condPresets on the spec):
--   "Sudden Death up"       = Execute glows          (163201)
--   "Imminent Demise (3)"   = Bladestorm glows       (227847)
--   "Collateral Damage (3)" = Cleave glows           (845)
--   "Exec. Precision (2)"   = predicted counter (Execute casts, reset by Mortal Strike)

-- Slayer lists (0.10.30), rebuilt from the posted 12.1 priority and checked decision by
-- decision against four top Ula'tek logs + a top Coiled Altar log (agreement with what
-- those players pressed: 28.6% with the old lists -> 44.8%). Bladestorm is a channel:
-- nothing is pressable during it, and the Mortal Strikes you see are Unhinged procs.

-- Sudden Death Execute right before Bladestorm: top players spend the proc first (87% of
-- their pre-Bladestorm Executes were procs; Imminent Demise was usually already at 3).
local preBladestormExecute = { spell = "Execute",
    cond = AND(preset("suddenDeath"), cdReady(ID_BLADESTORM), buffUp(ID_COLOSSUS_DBF)) }

-- Slayer single target.
local slayer_st = {
    { spell = "Cleave", cond = AND(refreshable(ID_REND), cdReady(ID_COLOSSUS_DBF)) }, -- refresh Rend before Colossus Smash
    { spell = "Cleave", cond = debuffDown(ID_REND) },                                 -- apply Rend
    { spell = "Avatar", cond = OR(cdReady(ID_COLOSSUS_DBF), buffUp(ID_COLOSSUS_DBF)) }, -- with Colossus Smash (refs: 95%)
    { spell = "ColossusSmash" },
    preBladestormExecute,
    { spell = "Bladestorm", cond = buffUp(ID_COLOSSUS_DBF) },                         -- inside Colossus Smash
    { spell = "HeroicStrike" },
    { spell = "MortalStrike" },
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Overpower" },
    { spell = "Cleave", cond = refreshable(ID_REND) },
    { spell = "Slam" },
}

-- Slayer ST-Execute: Execute sits ABOVE Overpower (refs pressed it 61:22 over Overpower;
-- it simply isn't castable when rage is short).
local slayer_st_execute = {
    { spell = "Cleave", cond = AND(refreshable(ID_REND), cdReady(ID_COLOSSUS_DBF)) },
    { spell = "Avatar", cond = OR(cdReady(ID_COLOSSUS_DBF), buffUp(ID_COLOSSUS_DBF)) },
    { spell = "ColossusSmash" },
    { spell = "HeroicStrike" },
    preBladestormExecute,
    { spell = "Bladestorm", cond = buffUp(ID_COLOSSUS_DBF) },
    { spell = "MortalStrike", cond = preset("execPrec2") },                           -- 2 Executioner's Precision
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Execute" },
    { spell = "Overpower" },
    { spell = "MortalStrike" },
    { spell = "Slam" },
}

-- Slayer AoE: Sweeping Strikes only when it has dropped. At 3+ targets top players rate
-- Cleave above Mortal Strike / Heroic Strike / Overpower, level with a Sudden Death Execute.
local slayer_aoe = {
    { spell = "SweepingStrikes", cond = buffDown(ID_SWEEPING) },
    { spell = "Cleave", cond = debuffDown(ID_REND) },
    { spell = "Avatar", cond = OR(cdReady(ID_COLOSSUS_DBF), buffUp(ID_COLOSSUS_DBF)) },
    { spell = "ColossusSmash" },
    preBladestormExecute,
    { spell = "Bladestorm", cond = buffUp(ID_COLOSSUS_DBF) },
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Cleave" },
    { spell = "HeroicStrike" },
    { spell = "MortalStrike" },
    { spell = "Overpower" },
    { spell = "Slam" },
}

local slayer_aoe_execute = {
    { spell = "SweepingStrikes", cond = buffDown(ID_SWEEPING) },
    { spell = "Cleave", cond = debuffDown(ID_REND) },
    { spell = "Avatar", cond = OR(cdReady(ID_COLOSSUS_DBF), buffUp(ID_COLOSSUS_DBF)) },
    { spell = "ColossusSmash" },
    preBladestormExecute,
    { spell = "Bladestorm", cond = buffUp(ID_COLOSSUS_DBF) },
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Cleave" },
    { spell = "HeroicStrike" },
    { spell = "MortalStrike" },
    { spell = "Execute" },
    { spell = "Overpower" },
    { spell = "Slam" },
}

-- Colossus single target: Demolish inside the Colossus Smash window (Colossal Might
-- payoff), no Bladestorm weave.
local colossus_st = {
    { spell = "Cleave", cond = AND(refreshable(ID_REND), cdReady(ID_COLOSSUS_DBF)) }, -- refresh Rend before Colossus Smash
    { spell = "Avatar" },                                 -- on CD
    { spell = "ThunderousRoar" },                         -- talent CD
    { spell = "ChampionsSpear" },                         -- talent CD
    { spell = "ColossusSmash" },                          -- on CD (smart-swaps to Warbreaker if talented)
    { spell = "Ravager" },                                -- talent: with Colossus Smash
    { spell = "Demolish", cond = buffUp(ID_COLOSSUS_DBF) }, -- Colossus: spend inside the Colossus Smash window
    { spell = "Execute", cond = preset("suddenDeath") },  -- Sudden Death proc
    { spell = "MortalStrike", cond = preset("execPrec2") }, -- 2 Executioner's Precision
    { spell = "MortalStrike" },
    { spell = "Overpower" },
    { spell = "Cleave", cond = OR(buffDown(ID_REND), refreshable(ID_REND)) }, -- keep Rend up
    { spell = "Execute" },                                -- filler (execute range)
    { spell = "Slam" },                                   -- filler
}

-- Colossus AoE (3+): as Slayer AoE but Demolish replaces the Bladestorm line.
local colossus_aoe = {
    { spell = "SweepingStrikes" },                        -- on CD
    { spell = "Cleave", cond = buffDown(ID_REND) },       -- early, to apply Rend
    { spell = "Avatar" },
    { spell = "ThunderousRoar" },
    { spell = "ChampionsSpear" },
    { spell = "ColossusSmash" },
    { spell = "Ravager" },
    { spell = "Demolish", cond = buffUp(ID_COLOSSUS_DBF) }, -- Colossus burst inside Colossus Smash
    { spell = "Cleave", cond = preset("collateral3") },   -- 3 Collateral Damage
    { spell = "Execute", cond = preset("suddenDeath") },  -- Sudden Death proc
    { spell = "MortalStrike", cond = preset("execPrec2") }, -- 2 Executioner's Precision
    { spell = "Cleave" },                                 -- main AoE spender
    { spell = "Overpower", cond = chargesMin(7384, 2) },  -- with 2 charges
    { spell = "Overpower" },
    { spell = "MortalStrike" },
    { spell = "Execute" },                                -- filler (execute range)
    { spell = "Slam" },                                   -- filler
}

-- EXECUTE-PHASE lists. Auto-swapped in when the latched "In execute range" flag is on
-- (Engine's execute overlay). Execute becomes the main spender: the bare Execute line
-- self-gates on usability (i.e. enough rage), covering the "Execute at >40 rage" intent
-- without a readable rage value.

local colossus_st_execute = {
    { spell = "Cleave", cond = AND(refreshable(ID_REND), cdReady(ID_COLOSSUS_DBF)) }, -- maintain Rend
    { spell = "Avatar" },
    { spell = "ThunderousRoar" },
    { spell = "ChampionsSpear" },
    { spell = "ColossusSmash" },
    { spell = "Ravager" },
    { spell = "Demolish", cond = buffUp(ID_COLOSSUS_DBF) }, -- Colossus burst in the CS window
    { spell = "MortalStrike", cond = preset("execPrec2") },
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Execute" },
    { spell = "Overpower" },
    { spell = "MortalStrike" },
    { spell = "Slam" },
}

local colossus_aoe_execute = {
    { spell = "SweepingStrikes" },
    { spell = "Cleave", cond = buffDown(ID_REND) },
    { spell = "Avatar" },
    { spell = "ThunderousRoar" },
    { spell = "ChampionsSpear" },
    { spell = "ColossusSmash" },
    { spell = "Ravager" },
    { spell = "Demolish", cond = buffUp(ID_COLOSSUS_DBF) },
    { spell = "Cleave", cond = preset("collateral3") },
    { spell = "MortalStrike", cond = preset("execPrec2") },
    { spell = "Execute", cond = preset("suddenDeath") },
    { spell = "Execute" },
    { spell = "Cleave" },
    { spell = "Overpower" },
    { spell = "MortalStrike" },
    { spell = "Slam" },
}

-- No Cleave tier: Arms uses ST (1 target) and AoE (2+, configurable via "AoE at" in the
-- Behavior panel), each with an execute-phase variant the engine swaps in automatically.
local heroLists = {
    slayer   = { st = slayer_st,   aoe = slayer_aoe,
                 st_execute = slayer_st_execute,   aoe_execute = slayer_aoe_execute },
    colossus = { st = colossus_st, aoe = colossus_aoe,
                 st_execute = colossus_st_execute, aoe_execute = colossus_aoe_execute },
}

-- Active hero: Demolish (436358) is the Colossus capstone -- Slayer never has it, so
-- a STRICT known check (spellbook/talent only, not tracked/aura state) is the reliable
-- signature. Default to Slayer.
local function activeHero()
    if API and API.IsKnownStrict and API.IsKnownStrict(ID_DEMOLISH) then return "colossus" end
    return "slayer"
end

local spec = {
    key      = "WARRIOR_ARMS",
    label    = "Arms",
    className = "Warrior",
    specID   = 71,
    resource = RAGE,
    resourceLabel = "Rage",
    -- No Cleave tier: AoE at 2+ by default (user-configurable via "AoE at" in Behavior).
    -- cleaveAt == aoeAt collapses the middle tier in ResolveMode.
    cleaveAt = 2,
    aoeAt    = 2,
    usesPandemic = true,             -- Rend refreshes in its pandemic window

    -- Editor mode tabs and the execute-phase overlay map: when the latched "In execute
    -- range" flag is on, the engine swaps each tier to its execute variant.
    modes = {
        { value = "st",          text = "ST" },
        { value = "aoe",         text = "AoE" },
        { value = "st_execute",  text = "ST (Exec)" },
        { value = "aoe_execute", text = "AoE (Exec)" },
    },
    executeMode = { st = "st_execute", aoe = "aoe_execute" },

    -- Execute-range detection: Execute (163201) is usable only in execute range or on a
    -- Sudden Death proc, so "usable without the proc glow" => in range (see Engine's
    -- latched UpdateExecuteRange). Drives the "In execute range" preset.
    executeSpell = 163201,
    executeHold  = 4,                -- seconds to hold the latch through rage dips

    -- Hero split (see top-of-file note). activeHero picks the list; priorityVariants
    -- drives the Options hero picker + per-hero custom lists.
    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "slayer",   label = "Slayer" },
        { key = "colossus", label = "Colossus" },
    },

    -- Predicted stack tracking (no readable count): when Executioner's Precision (talent
    -- 386634) is taken, every Execute adds a stack (cap 2) and Mortal Strike resets it to 0.
    -- If the buff (386633) is tracked in the Cooldown Manager and reads MISSING, the count
    -- is also reset to 0 (it expired). Keyed by the talent ID so predMin(ID_EXECPREC, n)
    -- and the "Exec. Precision (2)" preset read it. Drives the live pick AND the look-ahead.
    stackTrack = {
        [ID_EXECPREC] = { max = 2, gen = { "Execute" }, reset = { "MortalStrike" },
                          talent = ID_EXECPREC, aura = ID_EXECPREC_AURA },
    },

    -- Cast IDs the game reports that differ from spells{} and are not overrides: Execute
    -- SUCCEEDS as 281000 (listed 163201), Slayer's Bladestorm as 446035 (listed 227847).
    -- Without these the casts never resolve, so Executioner's Precision never counted.
    castAliases = { [281000] = "Execute", [446035] = "Bladestorm" },

    -- Named conditions surfaced in the editor. Each resolves to a readable clause
    -- (a proc-glow or predicted-stack read) so the user picks a MEANING, not a glow.
    condPresets = {
        { key = "suddenDeath",  label = "Sudden Death up",       clause = glowing(163201) },
        { key = "immDemise3",   label = "Imminent Demise (3)",   clause = glowing(ID_BLADESTORM) },
        { key = "immDemiseLt3", label = "Imminent Demise (<3)",  clause = notGlowing(ID_BLADESTORM) },
        { key = "collateral3",  label = "Collateral Damage (3)", clause = glowing(845) },
        { key = "execPrec2",    label = "Exec. Precision (2)",   clause = predMin(ID_EXECPREC, 2) },
        { key = "execRange",    label = "In execute range",      clause = { type = "inExecuteRange" } },
    },

    -- Relevant buffs/debuffs (selectable in the condition editor regardless of build).
    auras = {
        Rend          = ID_REND,
        SuddenDeath   = ID_SUDDENDEATH,
        CollateralDamage = ID_COLLATERAL,
        ExecutionersPrecision = ID_EXECPREC_AURA,
        ImminentDemise = ID_IMMINENT,
        ColossusSmash = ID_COLOSSUS_DBF,
        SweepingStrikes = ID_SWEEPING,
    },

    -- First-time setup checklist (Setup.lua adds the global nameplate check). Only the
    -- auras PRIO actually READS from the Cooldown Manager need tracking: Rend (missing/
    -- refresh) and Colossus Smash (its debuff window). Sudden Death, Imminent Demise and
    -- Collateral Damage are read from BUTTON GLOWS, and Executioner's Precision is
    -- predicted from casts -- none of those need tracking (shown as "Automatic").
    setup = {
        { kind = "trackedAura", label = "Rend tracked", spell = ID_REND,
          hint = "Track Rend (target debuff) in your Cooldown Manager so PRIO can tell when it's missing or about to fall off." },
        { kind = "trackedAura", label = "Sweeping Strikes tracked", spell = ID_SWEEPING,
          hint = "Track Sweeping Strikes (buff) in your Cooldown Manager so PRIO only asks for it when it has dropped. Untracked, PRIO assumes it is down and asks whenever it is off cooldown." },
        { kind = "trackedAura", label = "Colossus Smash tracked", spell = ID_COLOSSUS_DBF,
          hint = "Track Colossus Smash in your Cooldown Manager so PRIO can see its debuff window (drives the Bladestorm / Demolish timing)." },
        { kind = "pandemic", label = "Rend pandemic alert", spell = ID_REND,
          hint = "Optional: enable the Pandemic Time alert on Rend (Edit Mode -> Cooldown Manager) so it refreshes exactly in its no-clip window." },
        { kind = "info", label = "Sudden Death / Imminent Demise / Collateral Damage",
          hint = "No tracking needed -- PRIO reads these from the Execute, Bladestorm and Cleave button glows automatically." },
        { kind = "info", label = "Executioner's Precision",
          hint = "PRIO counts it from your casts (Execute +1, max 2; Mortal Strike resets). Optional: track the Executioner's Precision buff in your Cooldown Manager so PRIO also resets the count when the buff falls off." },
    },

    spells = {
        MortalStrike   = 12294,
        Overpower      = 7384,
        Execute        = 163201,
        Slam           = 1464,
        Cleave         = 845,
        ThunderClap    = 6343,
        Bladestorm     = 227847,
        ColossusSmash  = 167105,
        Warbreaker     = 262161,   -- talent, replaces Colossus Smash
        Rend           = 772,
        Skullsplitter  = 260643,
        ChampionsSpear = 376079,   -- talent
        Avatar         = 107574,
        SweepingStrikes = 260708,
        Ravager        = 228920,   -- talent
        Demolish       = 436358,   -- Colossus
        ThunderousRoar = 384318,
        HeroicStrike   = 1269383,  -- Slayer proc (Slam-swap)
        StormBolt      = 107570,   -- talent (stun + damage)
        Charge         = 100,      -- gap-closer (opener)
    },

    openerReady = { "Avatar", "ColossusSmash", "Warbreaker" },
    -- ST opener (opener) and AoE opener (openerAoe); the engine picks by pull size.
    opener = { "Cleave", "Avatar", "ColossusSmash", "Execute", "Bladestorm",
               "StormBolt", "HeroicStrike", "MortalStrike", "Overpower" },
    openerAoe = { "SweepingStrikes", "Charge", "Cleave", "Avatar", "ColossusSmash",
                  "Bladestorm", "Cleave", "Overpower", "Execute", "Cleave" },

    precombat = {},   -- Rend is a target debuff (opener leads with it), not a self-buff

    pickable = {
        "MortalStrike", "Overpower", "Execute", "Slam", "Cleave", "HeroicStrike", "ThunderClap",
        "Bladestorm", "ColossusSmash", "Warbreaker", "Rend", "Skullsplitter",
        "ChampionsSpear", "Avatar", "SweepingStrikes", "Ravager", "Demolish",
        "ThunderousRoar", "StormBolt", "Charge",
    },

    -- Overpower runs on 2 charges.
    chargeTrack = {
        Overpower = { max = 2, recharge = 12 },
    },

    -- Only Slam is a true no-cooldown filler. Cleave has a (hasted) cooldown -- except
    -- with Crushing Combo (1261056: 2 free Cleaves after Colossus Smash), which we can't
    -- model -- so it must NOT be a spammable filler, or the look-ahead stacks it 3x.
    fillers = { [1464] = true },   -- Slam

    flash = {
        Execute = { type = "buffActive", spell = ID_SUDDENDEATH },
    },

    -- Colossus Smash / Warbreaker apply the Colossus Smash debuff (look-ahead).
    spellEffects = {
        ColossusSmash = { grant = { ID_COLOSSUS_DBF } },
        Warbreaker    = { grant = { ID_COLOSSUS_DBF } },
    },

    maelstromMax = 100,   -- Rage cap (generic "resource" fields)
    maelstromGen = {},    -- Rage is auto-attack driven; casts mostly spend it

    OnCast = function(P, key, now) end,

    --------------------------------------------------------------------------------
    -- Debug metadata (see Debug.lua). Rows shown live; economy is informational.
    --------------------------------------------------------------------------------
    debug = {
        { label = "Overpower charges",    kind = "charges", key = "Overpower" },
        { label = "Rend (target)",        kind = "buff",  spell = ID_REND },
        { label = "Sudden Death stacks",  kind = "stacks", spell = ID_SUDDENDEATH },
        { label = "Collateral Dmg stacks", kind = "stacks", spell = ID_COLLATERAL },
        { label = "Exec. Precision stacks", kind = "stacks", spell = ID_EXECPREC_AURA },
        { label = "Imminent Demise stacks", kind = "stacks", spell = ID_IMMINENT },
        { label = "Colossus Smash (t)",   kind = "buff",  spell = ID_COLOSSUS_DBF },
        { label = "Sweeping Strikes",     kind = "buff",  spell = ID_SWEEPING },
    },
    economy = {
        gen   = { "Auto-attack", "Mortal Strike", "Skullsplitter", "Overpower" },
        spend = { "Execute", "Slam", "Cleave", "Bladestorm" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (separate window: /prio rotdebug). Abilities show
    -- cooldown-ready + usable state; buffs show active + stacks. IDs mirror the
    -- rotation gates above, so an "untracked" row means the gate itself reads a bad ID.
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {   -- spec.spells keys; window reads IsReady + IsUsable
            "Cleave", "Avatar", "ColossusSmash", "Execute", "Bladestorm",
            "HeroicStrike", "MortalStrike", "Overpower", "Slam",
        },
        buffs = {
            { label = "Sudden Death",           spell = ID_SUDDENDEATH },
            { label = "Imminent Demise",        spell = ID_IMMINENT },
            { label = "Executioner's Precision", spell = ID_EXECPREC_AURA },
        },
        -- Predicted counters (advanced by our casts; no readable aura count).
        predStacks = {
            { label = "Exec. Precision (pred)", spell = ID_EXECPREC },
        },
        -- Execute-range probes: can we detect target < 35% at all? Testing target health
        -- readability and whether Execute's usable flag reads clean (flips on in range).
        rangeProbes = {
            { label = "Target health %",        kind = "health" },
            { label = "Execute usable (clean)", kind = "usableClean", spell = 163201 },
            { label = "In execute range",       kind = "execRange" },
        },
        -- Proc-glow probes: testing whether the button glow is a readable stand-in for a
        -- stack count we can't read. Bladestorm glows at 3 Imminent Demise; Execute glows
        -- on a Sudden Death proc; Mortal Strike may glow with Executioner's Precision.
        glows = {
            { label = "Bladestorm (ImmDemise 3?)", spell = 227847 },
            { label = "Execute (Sudden Death?)",   spell = 163201 },
            { label = "Mortal Strike (Exec Prec?)", spell = 12294 },
            { label = "Cleave (Collateral 3?)",    spell = 845 },
        },
    },
}

-- spec.priority is a live proxy: reads resolve to the ACTIVE hero's list for the
-- requested mode. Nothing writes to spec.priority (customization lives in
-- db.customPriorities), so an empty backing table with an __index resolver is safe
-- for the engine, editor, and export.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.slayer
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
