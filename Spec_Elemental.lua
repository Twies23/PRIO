-- Spec_Elemental.lua -----------------------------------------------------------
-- Elemental Shaman (spec 262), Farseer-first, patch 12.1.
--
-- The priority lists are DATA. Each entry names a spell key and an optional
-- `when(S)` predicate over the engine's state object. Predicates are written to
-- fail open (a nil/unreadable signal -> show the ability) so the strip never goes
-- blank because a value was secret. Spell IDs are validated at runtime by
-- IsKnown, so wrong/renamed IDs simply don't appear rather than erroring.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local MAELSTROM = (Enum and Enum.PowerType and Enum.PowerType.Maelstrom) or 11

-- Cross-spell IDs used in default conditions (verified from Cooldown Viewer).
local ID_STORMKEEPER = 191634   -- cooldown + buff
local ID_FLAMESHOCK  = 470411   -- Flame Shock aura (TrackedBar)
local ID_PURGING     = 1259471  -- Purging Flames buff (from Voltaic Blaze)
local ID_LAVASURGE   = 77762    -- Lava Surge BUFF aura (77756 is the passive/proc, not the buff)
local ID_VOLTAIC     = 470057   -- Voltaic Blaze (talent gate; shares an override with Flame Shock)

-- Condition helpers (keep the all-inclusive list readable).
local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end
local function cdDown(id)   return { type = "cdNotReady",  spell = id } end
local function cdReady(id)  return { type = "cdReady",     spell = id } end
local function refreshable(id) return { type = "refreshable", spell = id } end
local function talent(id)      return { type = "talentYes", spell = id } end
local function talentNo(id)    return { type = "talentNo",  spell = id } end
local moteUp   = { type = "moteUp" }
local moteDown = { type = "moteDown" }

local spec = {
    key      = "SHAMAN_ELEMENTAL",
    label    = "Elemental",
    className = "Shaman",
    specID   = 262,
    resource = MAELSTROM,
    moteTalent   = "Master of the Elements", -- gates moteUp/moteDown (not readable)
    moteTalentID = 16166,                    -- stable ID match (preferred over the name)
    usesPandemic = true,                     -- shows the pandemic setup item
    -- First-time setup checklist (see Setup.lua). Global checks (nameplates) are added
    -- automatically; these are the spec-specific ones.
    setup = {
        { kind = "trackedAura", label = "Flame Shock tracked", spell = 470411,
          hint = "Add Flame Shock to your Cooldown Manager tracked bars so PRIO can read its state." },
        { kind = "trackedAura", label = "Lava Surge tracked", spell = 77762,
          hint = "Track Lava Surge so instant Lava Burst procs are detected." },
        { kind = "pandemic", label = "Flame Shock pandemic alert", spell = 470411,
          hint = "Optional: enable the Pandemic Time alert on Flame Shock (Edit Mode -> Cooldown Manager) for no-clip refresh timing. Turns green once detected in combat." },
    },

    spells = {
        LightningBolt      = 188196,
        ChainLightning     = 188443,
        LavaBurst          = 51505,
        FlameShock         = 470411,   -- verified via Cooldown Viewer (was 188389)
        VoltaicBlaze       = 470057,
        EarthShock         = 8042,
        Earthquake         = 462620,   -- verified via Cooldown Viewer (was 61882)
        ElementalBlast     = 117014,
        Stormkeeper        = 191634,
        Ascendance         = 114050,
        Tempest            = 454009,
        AncestralSwiftness = 443454,
        FireElemental      = 198067,
        LightningShield    = 192106,
        FlametongueWeapon  = 318038,
        Skyfury            = 462854,
    },

    -- Hardcoded opener (all cooldowns up). Started at combat when a signature CD is
    -- ready, advancing as you cast each step, then handing off to the priority.
    openerReady = { "Stormkeeper", "Ascendance" },
    opener = { "Stormkeeper", "LavaBurst", "Ascendance", "AncestralSwiftness",
               "LavaBurst", "LightningBolt", "LightningBolt" },

    -- Pre-combat checks (shown out of combat when missing). `aura` = a self-buff to
    -- verify; `imbue` = a main-hand weapon enchant.
    precombat = {
        { spell = "FlametongueWeapon", imbue = true },
        { spell = "Skyfury",           aura = 462854 },
        { spell = "LightningShield",   aura = 192106 },
    },

    -- Readable aura IDs discovered from the Cooldown Viewer (TrackedBuff/TrackedBar).
    -- These are auras the game tracks, so IsAuraActive() reads them live in combat.
    auras = {
        LavaSurge      = 77756,
        PurgingFlames  = 1259471,
        AscendanceBuff = 1219480,
        Stormkeeper    = 191634,
    },

    -- Which spells appear in the "Add ability" picker (spec.spells order is
    -- unstable, so list them explicitly).
    pickable = {
        "Stormkeeper", "AncestralSwiftness", "Ascendance", "FlameShock",
        "VoltaicBlaze", "ElementalBlast", "LavaBurst", "EarthShock",
        "Earthquake", "Tempest", "LightningBolt", "ChainLightning", "FireElemental",
    },

    -- Maelstrom is SECRET in combat, so we predict it: synced to the real value
    -- out of combat, then advanced by casts. Generation is approximate (talent-
    -- dependent); spender cost comes from the real GetSpellPowerCost.
    -- Predicted charge tracking (current charges are secret in combat). Synced to
    -- the real count out of combat, decremented on cast, recharged on a timer, and
    -- a charge granted when resetAura procs (Lava Surge). Clamped by the readable
    -- castable state (not castable -> 0, castable -> >=1).
    chargeTrack = {
        LavaBurst = { max = 3, recharge = 8, resetAura = ID_LAVASURGE },
    },

    -- Proc flash: when a cast is empowered/instant right now, its icon flashes.
    -- Conditions use the same declarative form (read live off the Cooldown Viewer
    -- / predicted state).
    flash = {
        LavaBurst      = { type = "buffActive", spell = ID_LAVASURGE },  -- Lava Surge -> instant
        LightningBolt  = { type = "skStacks", v = 1 },                   -- Stormkeeper stack -> instant
        ChainLightning = { type = "skStacks", v = 1 },
    },

    -- Spells that may repeat freely in the queue (no cooldown, spammable). Only
    -- these are treated as fillers; everything else appears once (or up to its
    -- charge count). Auto-detecting this from the API is unreliable -- Lava Burst
    -- reads as no-cooldown because its recharge is charge-based.
    fillers = {
        [188196] = true,   -- Lightning Bolt
        [188443] = true,   -- Chain Lightning
    },

    -- Cast look-ahead: what casting each ability does to auras/buffs, so the QUEUE
    -- can predict a beat ahead (e.g. Lava Burst consumes Purging Flames, so it
    -- won't be suggested twice). `grant`/`consume` are aura spell IDs; `mote` sets
    -- the predicted Master of the Elements; `skSet`/`skDelta` adjust Stormkeeper stacks.
    spellEffects = {
        VoltaicBlaze   = { grant   = { ID_PURGING } },
        LavaBurst      = { consume = { ID_PURGING, ID_LAVASURGE }, mote = true },
        ElementalBlast = { mote = false },
        EarthShock     = { mote = false },
        Earthquake     = { mote = false },
        Tempest        = { mote = false },
        Stormkeeper    = { skSet = 2 },
        -- Lightning Bolt / Chain Lightning are also MotE consumers.
        LightningBolt  = { skDelta = -1, mote = false },
        ChainLightning = { skDelta = -1, mote = false },
    },

    -- Casting these applies Flame Shock, but the Cooldown Viewer read can lag a tick.
    -- Assume Flame Shock is up for a few seconds so we don't re-suggest it immediately
    -- (short window -> corrects itself if the target actually immuned it).
    assumeOnCast = {
        FlameShock   = { aura = ID_FLAMESHOCK, dur = 4 },
        VoltaicBlaze = { aura = ID_FLAMESHOCK, dur = 4 },
    },

    maelstromMax = 150,
    maelstromGen = {
        LightningBolt  = 8,
        ChainLightning = 12,
        LavaBurst      = 8,
        Tempest        = 0,
        FlameShock     = 0,
        VoltaicBlaze   = 0,
    },

    -- Advance the prediction model on the player's own casts.
    OnCast = function(P, key, now)
        -- Master of the Elements: GRANTED by Lava Burst, CONSUMED by the next
        -- damaging cast (Lightning Bolt, Chain Lightning, Elemental Blast, Earth
        -- Shock, Earthquake, Tempest).
        if key == "LavaBurst" then
            P.mote = true
            P.moteExpire = now + 15              -- MotE buff duration (safety net)
        elseif key == "LightningBolt" or key == "ChainLightning"
            or key == "ElementalBlast" or key == "EarthShock"
            or key == "Earthquake" or key == "Tempest" then
            P.mote = false
        end
        -- Stormkeeper stacks.
        if key == "Stormkeeper" then
            P.skStacks = 2
        elseif key == "LightningBolt" or key == "ChainLightning" then
            if (P.skStacks or 0) > 0 then P.skStacks = P.skStacks - 1 end
        end
        if key == "FlameShock" or key == "VoltaicBlaze" then
            P.fsExpire = now + 18                 -- assumed Flame Shock duration
        end
    end,

    --------------------------------------------------------------------------------
    -- Debug metadata (see Debug.lua). Rows shown live; economy is informational.
    --------------------------------------------------------------------------------
    debug = {
        { label = "MotE talent",            kind = "hasMote" },
        { label = "Master of the Elements", kind = "mote" },
        { label = "Stormkeeper stacks",     kind = "skStacks" },
        { label = "Lava Burst charges",     kind = "charges", key = "LavaBurst" },
        { label = "Flame Shock (target)",   kind = "buff", spell = ID_FLAMESHOCK },
        { label = "Flame Shock pandemic",   kind = "pandemic", spell = ID_FLAMESHOCK },
        { label = "Lava Surge",             kind = "buff", spell = ID_LAVASURGE },
        { label = "Purging Flames",         kind = "buff", spell = ID_PURGING },
    },
    economy = {
        gen   = { "Lightning Bolt", "Chain Lightning", "Lava Burst", "Tempest" },
        spend = { "Earth Shock", "Elemental Blast", "Earthquake" },
    },

    -- Priority lists as DATA. Each entry: { spell = <key>, cond = <declarative or
    -- nil>, ignoreCD = <bool> }. Conditions are self-referential where relevant
    -- (buffMissing/buffActive read the entry's OWN spell aura). The engine already
    -- gates every entry on known + off-cooldown + usable, so most need no condition.
    -- Defaults follow Wowhead's Farseer / Voltaic Blaze build. "Ascendance after
    -- Stormkeeper" = Stormkeeper on cooldown OR its buff up; Flame Shock is kept up
    -- by casting Voltaic Blaze when the DoT is missing; Lava Burst consumes Purging
    -- Flames in AoE. All conditions read live off the Cooldown Viewer.
    priority = {
        -- Single target (1-2). All-inclusive: MotE-build lines (moteUp/moteDown) are
        -- talent-gated, buff lines go inert without the buff, untalented abilities
        -- are filtered by IsKnown. Covers both the Master-of-the-Elements and the
        -- Voltaic Blaze builds from one list.
        st = {
            { spell = "Stormkeeper" },
            { spell = "AncestralSwiftness" },
            { spell = "Ascendance", cond = OR(cdReady(ID_STORMKEEPER), buffUp(ID_STORMKEEPER)) },
            -- Flame Shock upkeep. The Flame Shock button smart-swaps to Voltaic Blaze
            -- when that's talented, so no separate ST Voltaic Blaze line is needed.
            { spell = "FlameShock",  ignoreCD = true, cond = OR(buffDown(ID_FLAMESHOCK), refreshable(ID_FLAMESHOCK)) },
            -- MotE window: spend with Elemental Blast, build with Lava Burst, consume
            -- with a Stormkeeper Lightning Bolt (all inert on non-MotE builds).
            { spell = "ElementalBlast", cond = moteUp },
            { spell = "LavaBurst",      cond = moteDown },
            { spell = "LightningBolt",  cond = moteUp },
            -- General
            { spell = "ElementalBlast" },
            { spell = "LavaBurst", cond = buffUp(ID_LAVASURGE) },   -- instant proc
            { spell = "LavaBurst" },                                -- charge dump
            { spell = "Tempest" },                                  -- proc (if talented)
            { spell = "LightningBolt" },                            -- filler
        },

        -- Cleave (3): the AoE rotation with Elemental Blast as the spender (SimC uses
        -- Earthquake only at 4+). Chain Lightning replaces Lightning Bolt as filler.
        cleave = {
            { spell = "Stormkeeper" },
            { spell = "AncestralSwiftness" },
            -- Non-Voltaic builds keep Flame Shock up manually; Voltaic builds use Voltaic
            -- Blaze on cooldown instead (which applies Flame Shock).
            { spell = "FlameShock",  ignoreCD = true, cond = AND(buffDown(ID_FLAMESHOCK), talentNo(ID_VOLTAIC)) },
            { spell = "FlameShock",  ignoreCD = true, cond = AND(refreshable(ID_FLAMESHOCK), talentNo(ID_VOLTAIC)) },
            { spell = "VoltaicBlaze", cond = talent(ID_VOLTAIC) },  -- 3+: on cooldown, only if talented
            { spell = "Ascendance",  cond = OR(cdReady(ID_STORMKEEPER), buffUp(ID_STORMKEEPER)) },
            { spell = "LavaBurst",   cond = AND(buffUp(ID_PURGING), buffUp(ID_LAVASURGE)) },
            { spell = "Tempest",     cond = moteUp },
            { spell = "ElementalBlast" },                           -- spender at 3 targets
            { spell = "LavaBurst",   cond = buffUp(ID_PURGING) },
            { spell = "Tempest" },
            { spell = "ChainLightning" },                          -- filler (Stormkeeper-empowered via flash)
        },

        -- AoE (4+): all-inclusive, mirroring SimC's actions.aoe. Talent branches are
        -- handled automatically -- untalented abilities are filtered by IsKnown, buff
        -- lines go inert when the buff never appears, and moteUp/moteDown are gated on
        -- the Master of the Elements talent. The same spell may appear on several rows
        -- (like SimC) and fires once. Secret-only checks (Maelstrom deficit, stack
        -- thresholds, cooldown/DoT remaining, per-target selection) are dropped.
        aoe = {
            { spell = "Stormkeeper" },
            { spell = "AncestralSwiftness" },
            -- Non-Voltaic builds keep Flame Shock up manually; Voltaic builds use Voltaic
            -- Blaze on cooldown instead (which applies Flame Shock).
            { spell = "FlameShock",  ignoreCD = true, cond = AND(buffDown(ID_FLAMESHOCK), talentNo(ID_VOLTAIC)) },
            { spell = "FlameShock",  ignoreCD = true, cond = AND(refreshable(ID_FLAMESHOCK), talentNo(ID_VOLTAIC)) },
            { spell = "VoltaicBlaze", cond = talent(ID_VOLTAIC) },  -- 3+: on cooldown, only if talented
            { spell = "Ascendance",  cond = OR(cdReady(ID_STORMKEEPER), buffUp(ID_STORMKEEPER)) },
            -- Instant Lava Burst cleave off a proc
            { spell = "LavaBurst",   cond = AND(buffUp(ID_PURGING), buffUp(ID_LAVASURGE)) },
            -- Spend the MotE window with Tempest
            { spell = "Tempest",     cond = moteUp },
            -- Spender (Earthquake at 4+; Elemental Blast isn't used in AoE)
            { spell = "Earthquake" },
            -- Consume Purging Flames
            { spell = "LavaBurst",   cond = buffUp(ID_PURGING) },
            { spell = "Tempest" },
            { spell = "ChainLightning" },                          -- filler (Stormkeeper-empowered via flash)
        },
    },
}

PRIO.specs[spec.specID] = spec
