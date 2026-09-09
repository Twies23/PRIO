-- Spec_Retribution.lua ---------------------------------------------------------
-- Retribution Paladin (spec 70), patch 12.1 (Midnight). Hero tree: HERALD OF THE SUN.
--
-- Built from the user's supplied Herald of the Sun ST + AoE priority (Wowhead/Icy Veins
-- 12.1), cross-checked against three top logs (Repláy, Grómm, Poloqq). The published
-- priority is a simplified shape -- the logs revealed two things it glosses over, which
-- are folded in as low-priority builder lines so the rotation actually flows:
--   * CRUSADING STRIKES (408385) is the ~1200-cast "ability" in every log -- it's the
--     auto-attack replacement (passive Holy Power generation), NOT something you press,
--     so it is deliberately absent from the priority.
--   * JUDGMENT (20271) is cast ~130-170x/fight as a core Holy-Power builder + debuff, but
--     the simplified list omits it. Added at the bottom as an on-cooldown builder.
--   * BLADE OF JUSTICE only appears in the source list behind a 2-stack Art-of-War gate,
--     yet is the most-cast builder in the logs (160-205x). A plain on-cooldown Blade of
--     Justice builder line is added below the finishers so it fires as the main builder.
--
-- SIGNAL REALITY:
--   * HOLY POWER is a DISCRETE class power -> reads CLEAN in combat (like Chi / Combo
--     Points). Every Holy-Power gate below is EXACT: "5 Holy Power" dumps, 3-HP spends.
--   * COOLDOWNS (Avenging Wrath, Execution Sentence, Wake of Ashes, Divine Toll) are FIXED
--     (non-haste) so they're predicted with a dead-reckoned timer (cooldownTrack).
--   * PROC BUFFS are secret by ID in combat, so Divine Arbiter and Art of War are read
--     via the Cooldown-Manager tracked read AND the button proc-glow (surfaced as named
--     presets). Art of War's 2-STACK count is not readable -> approximated to "proc up".
--   * HAMMER OF WRATH is NOT a separate spell in this build -- it's JUDGMENT (20271)
--     empowered into Hammer of Wrath DURING AVENGING WRATH (1-for-1: same cooldown, same
--     2 charges, same button). So the "Hammer of Wrath" rows ARE Judgment rows gated on the
--     Avenging Wrath buff; readiness/charges/casts all read the real Judgment, and the
--     display resolves the game override so the icon shows as Hammer of Wrath while Wings
--     are up (spec.overrideDisplay). Keying it off the passive 1241288 was wrong -- that ID
--     never reports a cooldown, so it got recommended every GCD.
--   * NO FILLERS: every Retribution ability has a cooldown or a Holy Power cost, so nothing
--     repeats freely in the queue (spec.fillers = {}).
-- Verify IDs with /prio spells and /prio tracked.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local HOLYPOWER = (Enum and Enum.PowerType and Enum.PowerType.HolyPower) or 9

-- Verified IDs (user-supplied Wowhead links + log ability IDs).
local ID_AVENGINGWRATH    = 31884
local ID_EXECUTIONSENTENCE = 343527
local ID_DIVINESTORM      = 53385
local ID_DIVINEARBITER    = 1306161   -- proc buff: empowers the next spender
local ID_FINALVERDICT     = 383328
local ID_WAKEOFASHES      = 255937
local ID_DIVINETOLL       = 375576
local ID_BLADEOFJUSTICE   = 184575
local ID_ARTOFWAR         = 406064    -- proc buff (free/empowered Blade of Justice)
local ID_HOW_CASTABLE     = 1241410   -- "Hammer of Wrath can be cast" -- READABLE buff, up during Avenging Wrath (Hammer of Wrath = Judgment empowered; no separate spell)
local ID_JUDGMENT         = 20271
local ID_QUICKENEDINVOCATION = 379391 -- talent: Divine Toll cooldown -30s (the only talent that shifts these three CDs)
local ID_EMPYREANLEGACY   = 387170    -- buff: during Avenging Wrath, next ST Holy Power spender auto-fires Divine Storm (+25%)
-- Reference only (passive auto-attack replacement, not pressed):
-- local ID_CRUSADINGSTRIKES = 408385

-- Condition builders -----------------------------------------------------------
local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)    return { type = "buffActive",  spell = id } end
local function buffDown(id)  return { type = "buffMissing", spell = id } end
local function cdReady(id)   return { type = "cdReady",     spell = id } end
local function glow(id)      return { type = "glowing",     spell = id } end
local function hpMin(n)      return { type = "resourceMin", v = n } end   -- Holy Power >= n
local function chargesEq(n)  return { type = "chargesEq",   v = n } end   -- self charges == n
local function preset(key)   return { type = "preset:" .. key } end

--------------------------------------------------------------------------------
-- SINGLE TARGET (Herald of the Sun). Mirrors the supplied priority; the two builder
-- lines at the bottom (Judgment, Blade of Justice on cooldown) are the log-derived
-- additions that keep Holy Power flowing.
--------------------------------------------------------------------------------
local st = {
    { spell = "AvengingWrath" },                                                        -- 1: always
    { spell = "ExecutionSentence" },                                                    -- 2: always
    { spell = "DivineStorm",  cond = AND(preset("divineArbiter"), hpMin(5)) },          -- 3: Divine Arbiter proc + 5 HP
    { spell = "FinalVerdict", cond = hpMin(5) },                                        -- 4: dump at 5 HP
    { spell = "WakeOfAshes" },                                                          -- 5: always
    { spell = "DivineToll" },                                                           -- 6: always
    { spell = "BladeOfJustice", cond = AND(preset("artOfWar"), buffDown(ID_AVENGINGWRATH)) }, -- 7: Art of War proc, no Wings
    { spell = "Judgment", cond = AND(buffUp(ID_AVENGINGWRATH), chargesEq(2)) },         -- 8: HoW (= Judgment during Wings), 2 charges
    { spell = "DivineStorm",  cond = AND(buffUp(ID_DIVINEARBITER), hpMin(3)) },         -- 9: Divine Arbiter buff + 3 HP
    { spell = "FinalVerdict", cond = hpMin(3) },                                        -- 10: normal spend
    { spell = "Judgment", cond = AND(cdReady(ID_JUDGMENT), buffUp(ID_AVENGINGWRATH)) }, -- 11: HoW during Wings, whenever ready
    { spell = "BladeOfJustice", cond = cdReady(ID_BLADEOFJUSTICE) },                    -- 12: builder, on cooldown
    { spell = "Judgment", cond = cdReady(ID_JUDGMENT) },                                -- 13: builder / debuff (becomes HoW during Wings)
}

--------------------------------------------------------------------------------
-- AoE (Herald of the Sun). Retribution swaps to this at 2+ targets. Divine Arbiter
-- procs from Divine Storm here and empowers Final Verdict (same buff, either spender).
--------------------------------------------------------------------------------
local aoe = {
    { spell = "AvengingWrath" },                                                        -- 1: always
    { spell = "ExecutionSentence" },                                                    -- 2: always
    { spell = "FinalVerdict", cond = AND(buffUp(ID_DIVINEARBITER), hpMin(5)) },         -- 3: Divine Arbiter buff + 5 HP
    { spell = "FinalVerdict", cond = buffUp(ID_EMPYREANLEGACY) },                       -- 4: Empyrean Legacy (free Divine Storm armed)
    { spell = "DivineStorm",  cond = hpMin(5) },                                        -- 5: dump at 5 HP
    { spell = "WakeOfAshes" },                                                          -- 6: always
    { spell = "DivineToll" },                                                           -- 7: always
    { spell = "Judgment", cond = AND(chargesEq(2), cdReady(ID_JUDGMENT)) },             -- 8: HoW (= Judgment during Wings), 2 charges
    { spell = "BladeOfJustice", cond = AND(buffUp(ID_ARTOFWAR), buffDown(ID_AVENGINGWRATH)) }, -- 9: Art of War buff, no Wings
    { spell = "DivineStorm",  cond = buffUp(ID_DIVINEARBITER) },                        -- 10: Divine Arbiter buff
    { spell = "DivineStorm",  cond = hpMin(3) },                                        -- 11: normal AoE spend
    { spell = "Judgment", cond = AND(cdReady(ID_JUDGMENT), buffUp(ID_AVENGINGWRATH)) }, -- 12: HoW during Wings, whenever ready
    { spell = "BladeOfJustice", cond = cdReady(ID_BLADEOFJUSTICE) },                    -- 13: builder, on cooldown
    { spell = "Judgment", cond = cdReady(ID_JUDGMENT) },                                -- 14: builder / debuff (becomes HoW during Wings)
}

local spec = {
    key      = "PALADIN_RETRIBUTION",
    label    = "Retribution",
    className = "Paladin",
    specID   = 70,
    resource = HOLYPOWER,           -- HOLY POWER: discrete -> readable in combat (exact gates)
    resourceLabel = "Holy Power",
    maelstromMax = 5,               -- Holy Power cap (readable PowerMax overrides)

    -- 2+ targets -> AoE. Retribution has no distinct cleave tier, so cleave aliases AoE
    -- and the cleave tab is hidden.
    cleaveAt = 2,
    aoeAt    = 2,
    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    priority = { st = st, cleave = aoe, aoe = aoe },

    -- Named presets surfaced in the condition editor (meaning, not glow IDs). Each ORs the
    -- readable buff with the button proc-glow so it works whether or not the aura reads.
    condPresets = {
        { key = "divineArbiter", label = "Divine Arbiter proc",
          clause = OR(buffUp(ID_DIVINEARBITER), glow(ID_DIVINESTORM), glow(ID_FINALVERDICT)) },
        { key = "artOfWar", label = "Art of War proc",
          clause = OR(buffUp(ID_ARTOFWAR), glow(ID_BLADEOFJUSTICE)) },
        { key = "wingsUp", label = "Avenging Wrath active",
          clause = buffUp(ID_AVENGINGWRATH) },
        { key = "maxHP", label = "Max Holy Power (>=5)", clause = hpMin(5) },
        -- Empyrean Legacy: next ST Holy Power spender auto-casts Divine Storm (+25%). Use it
        -- to prefer Final Verdict so the free Divine Storm isn't wasted.
        { key = "empyreanLegacy", label = "Empyrean Legacy (free Divine Storm armed)",
          clause = buffUp(ID_EMPYREANLEGACY) },
    },

    spells = {
        AvengingWrath     = ID_AVENGINGWRATH,
        ExecutionSentence = ID_EXECUTIONSENTENCE,
        DivineStorm       = ID_DIVINESTORM,
        FinalVerdict      = ID_FINALVERDICT,
        WakeOfAshes       = ID_WAKEOFASHES,
        DivineToll        = ID_DIVINETOLL,
        BladeOfJustice    = ID_BLADEOFJUSTICE,
        Judgment          = ID_JUDGMENT,   -- becomes Hammer of Wrath during Avenging Wrath (override display)
    },

    auras = {
        DivineArbiter    = ID_DIVINEARBITER,
        ArtOfWar         = ID_ARTOFWAR,
        AvengingWrath    = ID_AVENGINGWRATH,
        HammerOfWrathReady = ID_HOW_CASTABLE,
        EmpyreanLegacy   = ID_EMPYREANLEGACY,
    },

    setup = {
        { kind = "info", label = "Holy Power",
          hint = "No tracking needed -- Holy Power is a discrete resource PRIO reads directly, so the \"5 Holy Power\" dumps and 3-HP spends are exact." },
        { kind = "trackedAura", label = "Divine Arbiter tracked", spell = ID_DIVINEARBITER,
          hint = "Track Divine Arbiter in your Cooldown Manager so the empowered Divine Storm / Final Verdict lines read (PRIO also falls back to the spender's proc glow)." },
        { kind = "trackedAura", label = "Art of War tracked", spell = ID_ARTOFWAR,
          hint = "Track Art of War so the Blade of Justice proc line reads (the 2-stack count isn't readable in combat, so PRIO treats \"proc up\" as the gate; the glow is the fallback)." },
        { kind = "trackedAura", label = "Avenging Wrath tracked", spell = ID_AVENGINGWRATH,
          hint = "Track Avenging Wrath so the Wings-gated lines read -- including Hammer of Wrath, which is the empowered Judgment during Avenging Wrath." },
        { kind = "trackedAura", label = "Hammer of Wrath castable tracked", spell = ID_HOW_CASTABLE,
          hint = "Track the \"Hammer of Wrath can be cast\" buff (1241410) so PRIO reads the Judgment->Hammer of Wrath window cleanly. Its charges are hasted and refill on Avenging Wrath, so PRIO doesn't predict the count -- it just uses the clean off-cooldown read. Falls back to the Avenging Wrath buff / usable flag if untracked." },
        { kind = "trackedAura", label = "Empyrean Legacy tracked", spell = ID_EMPYREANLEGACY, optional = true,
          hint = "Track Empyrean Legacy (387170) so the \"free Divine Storm armed\" condition reads. While it's up during Avenging Wrath, your next Final Verdict auto-casts Divine Storm (+25%) -- keep spending Final Verdict so it isn't wasted. Only relevant if you run the Empyrean Legacy talent." },
    },

    -- Opener (screenshot / log-validated): Blade of Justice -> Avenging Wrath (+ potion &
    -- trinkets) -> Execution Sentence -> Wake of Ashes -> Final Verdict, then Final Verdict
    -- (ST) / Divine Storm (AoE) -> Divine Toll, then hand off to the rotation.
    openerReady = { "AvengingWrath" },
    opener = { "BladeOfJustice", "AvengingWrath", "ExecutionSentence", "WakeOfAshes",
               "FinalVerdict", "FinalVerdict", "DivineToll" },
    openerAoe = { "BladeOfJustice", "AvengingWrath", "ExecutionSentence", "WakeOfAshes",
                  "FinalVerdict", "DivineStorm", "DivineToll" },
    precombat = {},

    pickable = {
        "AvengingWrath", "ExecutionSentence", "DivineStorm", "FinalVerdict", "WakeOfAshes",
        "DivineToll", "BladeOfJustice", "Judgment",
    },

    fillers = {},   -- Retribution has NO spammable fillers: every ability has a cooldown or a Holy Power cost, so nothing repeats freely in the queue.

    flash = {
        DivineStorm    = { type = "buffActive", spell = ID_DIVINEARBITER },   -- empowered (ST)
        FinalVerdict   = { type = "buffActive", spell = ID_DIVINEARBITER },   -- empowered (AoE)
        BladeOfJustice = { type = "buffActive", spell = ID_ARTOFWAR },        -- Art of War proc
        Judgment       = { type = "buffActive", spell = ID_HOW_CASTABLE },    -- flashes as Hammer of Wrath during Wings
    },

    -- Hammer of Wrath (= empowered Judgment during Wings) runs on 2 charges. The count is
    -- secret in combat AND haste-scaled / refilled by Avenging Wrath, so it's PREDICTED
    -- (synced OOC, decremented on cast, clamped by the castable flag) to feed the "2 chg"
    -- gate. Treat it as approximate -- the Wings buff gate is the reliable half.
    -- Judgment carries 2 charges (haste-scaled, refilled by Avenging Wrath); the count is
    -- secret in combat so it's predicted, feeding the "2 charges" line + queue multiplicity.
    -- The PRIMARY is always gated on the clean real off-cooldown read, so over-prediction
    -- can only ever add a (dimmed) extra to the queue, never a wrong press.
    chargeTrack = {
        Judgment = { max = 2, recharge = 6 },
    },

    -- During Avenging Wrath, Judgment's icon/name is empowered into Hammer of Wrath (a game
    -- spell override). This tells the display to resolve the active override for the icon +
    -- name, so a Judgment row shows as Hammer of Wrath while Wings are up -- matching the
    -- action bar -- while all the cooldown/charge/cast logic still reads the real Judgment.
    overrideDisplay = true,

    -- Cooldown prediction: remaining cooldown is secret in combat, so we seed a timer on
    -- cast and count it down (anchored to the clean off-cooldown flag). These three are
    -- FIXED cooldowns (NOT haste-scaled), so the dead-reckoned timer stays accurate. The
    -- only talent that shifts any of them is Quickened Invocation (Divine Toll -30s), so
    -- that's the one talent we check. Drives cdRemain conditions + accurate "next" queue
    -- placement for the big cooldowns.
    cooldownTrack = {
        AvengingWrath     = { base = 60 },
        ExecutionSentence = { base = 60 },
        WakeOfAshes       = { base = 30 },
        DivineToll        = { base = 60, reduce = { [ID_QUICKENEDINVOCATION] = 30 } },
    },

    -- Holy Power look-ahead (queue prediction). HP reads clean, so the sim seeds from the
    -- real value and advances by this each pick. Spenders cost 3; builder generation is
    -- approximate (exact amounts vary with talents) -- it only shapes the "next" icons.
    ResourceCost = function(_, key, sid, S)
        if key == "FinalVerdict" or key == "DivineStorm" then return 3 end
        return 0
    end,

    ResourceDelta = function(_, key, sid, S)
        if key == "FinalVerdict" or key == "DivineStorm" then return -3
        elseif key == "BladeOfJustice" then return 2
        elseif key == "WakeOfAshes"    then return 3
        elseif key == "DivineToll"     then return 3
        elseif key == "Judgment"       then return 1   -- also HoW during Wings (same ability)
        end
        return 0
    end,

    OnCast = function(P, key, now) end,

    debug = {
        { label = "Divine Arbiter",  kind = "buff", spell = ID_DIVINEARBITER },
        { label = "Art of War",      kind = "buff", spell = ID_ARTOFWAR },
        { label = "Avenging Wrath",  kind = "buff", spell = ID_AVENGINGWRATH },
        { label = "Hammer of Wrath castable", kind = "buff", spell = ID_HOW_CASTABLE },
        { label = "Empyrean Legacy",  kind = "buff", spell = ID_EMPYREANLEGACY },
        { label = "Avenging Wrath CD", kind = "cdRemain", spell = ID_AVENGINGWRATH },
        { label = "Execution Sentence CD", kind = "cdRemain", spell = ID_EXECUTIONSENTENCE },
        { label = "Wake of Ashes CD", kind = "cdRemain", spell = ID_WAKEOFASHES },
        { label = "Divine Toll CD",  kind = "cdRemain", spell = ID_DIVINETOLL },
    },
    economy = {
        gen   = { "Crusading Strikes (autos)", "Blade of Justice", "Judgment", "Wake of Ashes", "Divine Toll", "Hammer of Wrath" },
        spend = { "Final Verdict", "Divine Storm" },
    },

    --------------------------------------------------------------------------------
    -- Rotation Ability & Buff Debug (/prio rotdebug): the live signals the rotation
    -- reads. abilities = cooldown/usable; buffs = Cooldown-Manager active reads; glows =
    -- the proc overlays; rangeProbes = Holy Power (discrete, exact).
    --------------------------------------------------------------------------------
    rotationDebug = {
        title = "Retribution Rotation Debug",
        abilities = {
            "AvengingWrath", "ExecutionSentence", "WakeOfAshes", "DivineToll",
            "BladeOfJustice", "Judgment", "DivineStorm", "FinalVerdict",
        },
        buffs = {
            { label = "Divine Arbiter", spell = ID_DIVINEARBITER },
            { label = "Art of War",     spell = ID_ARTOFWAR },
            { label = "Avenging Wrath", spell = ID_AVENGINGWRATH },
            { label = "Hammer of Wrath castable", spell = ID_HOW_CASTABLE },
            { label = "Empyrean Legacy (free DS armed)", spell = ID_EMPYREANLEGACY },
        },
        glows = {
            { label = "Divine Storm glow (Divine Arbiter)",  spell = ID_DIVINESTORM },
            { label = "Final Verdict glow (Divine Arbiter)", spell = ID_FINALVERDICT },
            { label = "Blade of Justice glow (Art of War)",  spell = ID_BLADEOFJUSTICE },
        },
        rangeProbes = {
            { label = "Holy Power", kind = "resource" },
        },
    },
}

PRIO.specs[spec.specID] = spec
