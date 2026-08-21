-- Spec_Devourer.lua ------------------------------------------------------------
-- Devourer Demon Hunter (NEW Midnight spec), patch 12.1. Void-based DPS built
-- around Void Metamorphosis (a form) + Soul Fragment counting.
--
-- !!! VERIFICATION REQUIRED !!!
-- This spec is brand new, so its SPEC ID and most SPELL IDs are not published.
--   * specID below is a BEST GUESS. On a Devourer, open the Debug window (/prio
--     debug) -- if it says "unsupported (NNN)", NNN is the real spec ID; tell me.
--   * Run /prio spells and /prio tracked on Devourer to get the real ability/buff
--     IDs. Until then, abilities with wrong IDs simply won't appear (IsKnown filters
--     them), so the strip may be sparse.
--
-- RESOURCE REALITY: Fury is a secret bar (predicted, spenders fail open). Soul
-- Fragments are a COUNT that isn't a standard readable power, and the 30/50-soul
-- thresholds that drive the spec can't be read -- so Collapsing Star / entering Void
-- Metamorphosis are approximate. Void Metamorphosis itself is a FORM (readable buff),
-- so we CAN branch inside/outside it once its buff ID is known.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local FURY = (Enum and Enum.PowerType and Enum.PowerType.Fury) or 17

-- Readable buff IDs (VERIFY with /prio tracked).
local ID_VOIDMETA  = 0   -- Void Metamorphosis form buff (UNKNOWN - fill in)
local ID_SOULBURST = 0   -- Soulburst proc (UNKNOWN)
local ID_VOIDSTEP  = 0   -- Voidstep (free Vengeful Retreat) (UNKNOWN)

local function buffUp(id)   return { type = "buffActive",  spell = id } end
local function buffDown(id) return { type = "buffMissing", spell = id } end

local spec = {
    key      = "DEMONHUNTER_DEVOURER",
    label    = "Devourer",
    className = "Demon Hunter",
    specID   = 582,   -- BEST GUESS -- verify via Debug "unsupported (NNN)" on Devourer
    resource = FURY,
    resourceLabel = "Fury",
    cleaveAt = 2,
    aoeAt    = 3,

    -- Shared DH abilities have known IDs; Devourer-specific ones are best-guess (0 =
    -- unknown -> won't resolve until filled in). VERIFY ALL via /prio spells.
    spells = {
        TheHunt          = 370965,   -- shared DH (known)
        VengefulRetreat  = 198793,   -- shared DH (known)
        SigilOfSpite     = 390163,   -- shared (verify)
        Consume          = 0,        -- generator (UNKNOWN)
        Devour           = 0,        -- inside-meta generator (UNKNOWN)
        VoidRay          = 0,        -- Fury spender (UNKNOWN)
        Voidblade        = 0,        -- CD leap (UNKNOWN)
        HungeringSlash   = 0,        -- follow-up (UNKNOWN)
        SoulImmolation   = 0,        -- maintain (UNKNOWN)
        Reap             = 0,        -- spender (UNKNOWN)
        Cull             = 0,        -- inside-meta spender (UNKNOWN)
        CollapsingStar   = 0,        -- 30-soul spender (UNKNOWN)
        VoidMetamorphosis = 0,       -- form cooldown (UNKNOWN)
        ReapersToll      = 0,        -- inside melee (UNKNOWN)
        PierceTheVeil    = 0,        -- inside melee (UNKNOWN)
        PredatorsWake    = 0,        -- inside melee (UNKNOWN)
    },

    auras = {
        VoidMetamorphosis = ID_VOIDMETA,
        Soulburst = ID_SOULBURST,
        Voidstep  = ID_VOIDSTEP,
    },
    setup = {
        { kind = "trackedAura", label = "Void Metamorphosis tracked", spell = ID_VOIDMETA,
          hint = "Track the Void Metamorphosis buff so PRIO can branch inside vs outside the form." },
    },

    openerReady = { "VoidMetamorphosis", "TheHunt" },
    opener = { "TheHunt", "Voidblade", "HungeringSlash", "VoidMetamorphosis" },
    precombat = {},

    pickable = {
        "Consume", "Devour", "VoidRay", "Voidblade", "HungeringSlash", "SoulImmolation",
        "Reap", "Cull", "CollapsingStar", "VoidMetamorphosis", "TheHunt",
        "VengefulRetreat", "ReapersToll", "PierceTheVeil", "PredatorsWake", "SigilOfSpite",
    },

    fillers = {},   -- Consume/Devour are the generator fillers (fill in their IDs first)

    maelstromMax = 120,   -- Fury cap (generic "resource" fields)
    maelstromGen = {},

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Void Metamorphosis", kind = "buff", spell = ID_VOIDMETA },
        { label = "Soulburst",          kind = "buff", spell = ID_SOULBURST },
        { label = "Voidstep",           kind = "buff", spell = ID_VOIDSTEP },
    },
    economy = {
        gen   = { "Consume/Devour", "Voidblade", "Hungering Slash", "Soul collection" },
        spend = { "Void Ray (100 Fury)", "Collapsing Star (30 Souls)" },
    },

    -- One list, gated by the Void Metamorphosis form where the buff is known; IsReady
    -- filters abilities that aren't castable in the current form. Ordering follows the
    -- Icy Veins outside-then-inside priority. APPROXIMATE (soul/Fury thresholds secret).
    priority = {
        st = {
            -- Cooldowns / form
            { spell = "VoidMetamorphosis" },                       -- transform (soul gate unreadable)
            { spell = "TheHunt" },                                 -- CD
            { spell = "Voidblade" },                               -- CD
            { spell = "SigilOfSpite" },                            -- CD
            -- Inside-meta spenders (only castable in form -> IsReady gates)
            { spell = "CollapsingStar" },                          -- 30-soul spender
            { spell = "Cull" },                                    -- inside spender
            { spell = "ReapersToll" },
            { spell = "PierceTheVeil" },
            { spell = "PredatorsWake" },
            { spell = "Devour", cond = ID_SOULBURST ~= 0 and buffUp(ID_SOULBURST) or nil }, -- Soulburst priority
            -- Outside-meta
            { spell = "Reap" },                                    -- spender / Soulburst enabler
            { spell = "SoulImmolation" },                          -- maintain buff
            { spell = "VengefulRetreat", cond = ID_VOIDSTEP ~= 0 and buffUp(ID_VOIDSTEP) or nil },
            { spell = "HungeringSlash" },                          -- after Voidblade/The Hunt
            { spell = "VoidRay" },                                 -- 100-Fury spender
            { spell = "Consume" },                                 -- generator filler
        },
    },
}
spec.priority.cleave = spec.priority.st
spec.priority.aoe    = spec.priority.st

PRIO.specs[spec.specID] = spec
