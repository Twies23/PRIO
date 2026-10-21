-- Spec_Subtlety.lua ------------------------------------------------------------
-- Subtlety Rogue (spec 261), patch 12.1.5 (Midnight). BOTH hero trees built:
-- Trickster and Deathstalker (real, separate lists -- they open Shadow Dance on
-- opposite combo-point counts, so they genuinely differ).
--
-- Built from: Icy Veins 12.1.5 rotation page (Eleem, reviewed 2026-10-12; its per-hero
-- lines live in hidden `rotation_line_preset-N_on` panels -- preset-1 = Trickster,
-- preset-2 = Deathstalker, "BEST CHOICE" on the page) plus the user's screenshots of the
-- Trickster ST / AoE / opener tabs, and the user's live Cooldown Viewer dump for IDs.
--
-- THE SHAPE OF THE 12.1 SPEC (much leaner than TWW -- a ported list is wrong):
--   * NO Rupture, NO Symbols of Death, NO Shuriken Tornado in the rotation. The whole
--     spec is Shadow Blades (90s) + two Shadow Dances inside it, Secret Technique in
--     every Dance, and 6+ CP finishers (Eviscerate / Black Powder).
--   * SLICE AND DICE is maintained passively by Cut to the Chase (Eviscerate extends
--     it). The guide's only note: an Eviscerate to APPLY it may be needed in AoE during
--     the opener, because Black Powder doesn't. One buffDown row in AoE covers that.
--   * COUP DE GRACE (Trickster) is not its own button: after 4 Unseen Blade strikes the
--     game re-skins EVISCERATE into Coup de Grace (441776). Spell ids are not secret, so
--     "Eviscerate is currently Coup de Grace" is a clean read (condition overrideActive)
--     -- that is what lets AoE prefer CdG over Black Powder. `overrideDisplay` shows the
--     CdG icon on the Eviscerate row while it is up.
--   * ANCIENT ARTS (Apex): after a builder leaves 5+ Shadow Techniques stacks, your next
--     damaging finisher expends them for combo points (a free re-finish + a clone). The
--     buff is in the Cooldown Manager (1268932 -> 1269163), so it reads clean. Both
--     trees want it up on their big finisher in Dance: Trickster on Secret Technique,
--     Deathstalker on the Darkest Night Eviscerate -- "if Ancient Arts is not active,
--     press another Shadowstrike, even at full combo points".
--
-- SIGNAL REALITY:
--   * COMBO POINTS are discrete -> CLEAN in combat. Every CP gate is EXACT (max 7).
--   * ENERGY is SECRET. The guide says there's nothing to manage ("outside of Shadow
--     Dance there will not be enough energy to cast a spell every global, that is
--     completely fine"), so softPowerUsable + no energy model is exactly right.
--     Thistle Tea: the guide says let the auto-cast talent fire it -- left out of the
--     lists, kept pickable.
--   * SHADOW TECHNIQUES stacks are not gated on (the stack count is not reliably
--     readable); the Ancient Arts buff they produce IS, so we gate on that instead.
--   * SHADOWSTRIKE requires Stealth / Shadow Dance -- the game's usable flag gates it, so
--     its rows need no stealth condition of their own.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

-- IDs. From the user's live Cooldown Viewer dump (authoritative for in-game reads) and
-- verified against Wowhead tooltips (2026-10-18).
local ID_EVISCERATE   = 196819   -- Essential. finisher, 35 Energy
local ID_COUPDEGRACE  = 441776   -- Trickster: Eviscerate's override after 4 Unseen Blade strikes
local ID_SECRETTECH   = 280719   -- Essential. finisher, 30 Energy, 25s CD
local ID_SHADOWDANCE  = 185313   -- Essential + TrackedBuff (linked buff 185422). 6s, 20s CD
local ID_SHADOWBLADES = 121471   -- Essential + TrackedBuff. 16s, 90s CD -- double CP
local ID_GOREMAW      = 426591   -- Essential + TrackedBuff (linked 426593). 45s CD
local ID_BACKSTAB     = 53       -- Essential. builder, 40 Energy, +1 CP (Gloomblade replaces it)
local ID_SHADOWSTRIKE = 185438   -- builder, 50 Energy, +2 CP. Stealth / Shadow Dance only
local ID_SHURIKENSTORM = 197835  -- AoE builder, 50 Energy
local ID_BLACKPOWDER  = 319175   -- AoE finisher, 35 Energy
local ID_VANISH       = 1856     -- Utility. Premeditation -> next builder = full CP
local ID_STEALTH      = 1784     -- TrackedBuff (linked 158185)
local ID_SND          = 315496   -- TrackedBuff. maintained by Cut to the Chase
local ID_THISTLETEA   = 1298826  -- auto-cast talent recommended; pickable only
local ID_RUPTURE      = 1943     -- NOT in the 12.1 rotation; pickable only

-- Auras the lists read (Cooldown Manager keys).
local ID_ANCIENTARTS  = 1268932  -- TrackedBuff (linked 1269163): next finisher refunds CP
local ID_SHADOWTECH   = 196912   -- TrackedBuff (linked 196911). shown in debug only
local ID_SILENTSTORM  = 385722   -- TrackedBuff (linked 385727). next Shuriken Storm crits
local ID_PREMEDITATION = 343160  -- TrackedBuff (linked 343173): next builder = full CP
local ID_SUPERCHARGER = 470347   -- talent: Shadow Dance supercharges 2 combo points
local ID_POTENTPOWDER = 1265952  -- talent: Black Powder +20% of Mastery at 5+ CP

-- Trickster
local ID_UNSEENBLADE  = 441146   -- keystone (hero detection)
local ID_COUPTRACK    = 441423   -- TrackedBuff (linked 441786 Escalating Blade)

-- Deathstalker (not in the user's dump -- they run Trickster; same ids as Assassination)
local ID_MARKDEATH    = 1293340  -- auto-learned by Deathstalker (hero detection)
local ID_DSMARK       = 457052   -- applied by SHADOWSTRIKE on Subtlety (tooltip 457129)
local ID_DARKNIGHT    = 457058   -- next 5+ CP Eviscerate crits, +35%, re-applies the Mark

--------------------------------------------------------------------------------
-- Condition helpers (same DSL as the other specs)
--------------------------------------------------------------------------------
local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)      return { type = "buffActive",  spell = id } end
local function buffDown(id)    return { type = "buffMissing", spell = id } end
local function cdReady(id)     return { type = "cdReady",     spell = id } end
local function cdRemainMin(id, s) return { type = "cdRemainMin", spell = id, v = s } end
local function lastCastNot(id) return { type = "lastCastNot", spell = id } end
local function cpMin(n)        return { type = "resourceMin", v = n } end
local function cpMax(n)        return { type = "resourceMax", v = n } end
local function notStealthed()  return { type = "notStealthed" } end
-- Eviscerate is currently re-skinned into Coup de Grace (clean spell-id read).
local function scMin(n)        return { type = "superChargeMin", v = n } end
local function enemiesMin(n)   return { type = "enemiesMin", v = n } end
local function enemiesEq(n)    return { type = "enemiesEq",  v = n } end
local function talentYes(id)   return { type = "talentYes", spell = id } end
local function talentNo(id)    return { type = "talentNo",  spell = id } end
local function coupReady()     return { type = "overrideActive", spell = ID_EVISCERATE, v = ID_COUPDEGRACE } end

--------------------------------------------------------------------------------
-- Shared rows. ORDER is set per list.
--------------------------------------------------------------------------------
-- "You always want two Shadow Dances inside Shadow Blades, so do not cast it when Shadow
-- Blades has less than 10 seconds left of its cooldown." Shadow Blades' 90s cooldown is
-- fixed, so it is dead-reckoned (cooldownTrack) -- an unseeded timer reads the full 90,
-- i.e. this fails OPEN rather than stalling Dance.
local function sbWindowOk()
    return OR(cdReady(ID_SHADOWBLADES), cdRemainMin(ID_SHADOWBLADES, 10))
end

local function rowStealth()   return { spell = "Stealth", cond = notStealthed() } end
local function rowGoremaw()   return { spell = "GoremawsBite" } end           -- "whenever it is ready, right before your other cooldowns"
local function rowBlades()    return { spell = "ShadowBlades", cond = buffUp(ID_SHADOWDANCE) } end
local function rowSecretTech() return { spell = "SecretTechnique", cond = AND(buffUp(ID_SHADOWDANCE), cpMin(6)) } end
local function rowEviscerate() return { spell = "Eviscerate", cond = cpMin(6) } end
local function rowShadowstrike() return { spell = "Shadowstrike" } end        -- self-gates: Stealth / Dance only
local function rowBackstab()  return { spell = "Backstab" } end
local function rowStorm()     return { spell = "ShurikenStorm" } end
local function rowBlackPowder() return { spell = "BlackPowder", cond = cpMin(6) } end
-- AoE: the one Eviscerate that applies Slice and Dice (Black Powder does not extend it).
local function rowSnDApply()  return { spell = "Eviscerate", cond = AND(buffDown(ID_SND), cpMin(6)) } end
-- Vanish outside Dance. Premeditation makes the follow-up Shadowstrike generate FULL
-- combo points, so anything banked is wasted -- hence low CP ("on cooldown with low
-- combo points", Icy Veins Trickster).
local function rowVanishST()  return { spell = "Vanish", cond = AND(buffDown(ID_SHADOWDANCE), notStealthed(), cpMax(2)) } end
-- AoE: "whenever Shadow Dance is not active, to trigger Silent Storm".
local function rowVanishAoE() return { spell = "Vanish", cond = AND(buffDown(ID_SHADOWDANCE), notStealthed()) } end

--------------------------------------------------------------------------------
-- TRICKSTER -- the user's own tuned lists (ST 1.2.2, AoE 1.3.1).
--
-- Shadow Blades and Goremaw's Bite are lined up with Shadow Dance (only when Dance is
-- ready). Dance at 6+ CP with Secret Technique ready or Shadow Blades up. Secret
-- Technique only inside Dance with a supercharged combo point banked (Dance gives 2).
-- Shadowstrike from Stealth, and spammed in Dance; Backstab only outside Dance.
-- Coup de Grace still shows on the Eviscerate row via the override icon.
--------------------------------------------------------------------------------
local function trickster_list()
    return {
        { spell = "Stealth",         cond = notStealthed() },
        { spell = "Shadowstrike",    cond = buffUp(ID_STEALTH) },
        { spell = "Eviscerate",      cond = AND(buffDown(ID_SND), cpMin(6)) },   -- start Slice and Dice
        { spell = "ShadowBlades",    cond = cdReady(ID_SHADOWDANCE) },
        { spell = "GoremawsBite",    cond = cdReady(ID_SHADOWDANCE) },
        { spell = "ShadowDance",     cond = AND(cpMin(6), cdReady(ID_SECRETTECH)) },
        { spell = "ShadowDance",     cond = AND(cpMin(6), buffUp(ID_SHADOWBLADES)) },
        { spell = "Vanish",          cond = AND(cpMax(2), buffDown(ID_SHADOWDANCE)) },
        { spell = "SecretTechnique", cond = AND(cpMin(6), buffUp(ID_SHADOWDANCE), scMin(1)) },
        { spell = "Eviscerate",      cond = cpMin(6) },
        { spell = "Shadowstrike",    cond = buffUp(ID_SHADOWDANCE) },
        { spell = "Backstab",        cond = buffDown(ID_SHADOWDANCE) },
    }
end
local trickster_st = trickster_list()

-- AoE (user's list, 1.3.1): same cooldown block, then Coup de Grace, Black Powder (always
-- with Potent Powder, else at 3+ targets), Eviscerate on exactly 2 targets without Potent
-- Powder, and Shuriken Storm as the builder.
local trickster_aoe = {
    { spell = "Stealth",         cond = notStealthed() },
    { spell = "Shadowstrike",    cond = buffUp(ID_STEALTH) },
    { spell = "Eviscerate",      cond = AND(cpMin(6), buffDown(ID_SND)) },
    { spell = "ShadowBlades",    cond = cdReady(ID_SHADOWDANCE) },
    { spell = "GoremawsBite",    cond = cdReady(ID_SHADOWDANCE) },
    { spell = "ShadowDance",     cond = AND(cpMin(6), cdReady(ID_SECRETTECH)) },
    { spell = "ShadowDance",     cond = AND(cpMin(6), buffUp(ID_SHADOWBLADES)) },
    { spell = "Vanish",          cond = AND(cpMax(2), buffDown(ID_SHADOWDANCE)) },
    { spell = "SecretTechnique", cond = AND(cpMin(6), buffUp(ID_SHADOWDANCE), scMin(1)) },
    { spell = "Eviscerate",      cond = AND(cpMin(6), { type = "preset:coupReady" }) },   -- preset, so the editor shows it
    { spell = "BlackPowder",     cond = AND(cpMin(6), talentYes(ID_POTENTPOWDER)) },
    { spell = "BlackPowder",     cond = AND(cpMin(6), enemiesMin(3)) },
    { spell = "Eviscerate",      cond = AND(enemiesEq(2), cpMin(6), talentNo(ID_POTENTPOWDER)) },
    { spell = "ShurikenStorm" },
}

--------------------------------------------------------------------------------
-- DEATHSTALKER
--
-- Shadowstrike applies Deathstalker's Mark (3 stacks) -> each 5+ CP finisher consumes
-- one -> the last grants Darkest Night -> spend it on a 6+ CP Eviscerate, which
-- re-applies the Mark. Dance is entered at LOW combo points (<=2), the opposite of
-- Trickster. Darkest Night only matters at low target counts -- the guide says follow
-- the Trickster rules in AoE, so the AoE list has no Mark row.
--------------------------------------------------------------------------------
local function rowDanceDS()
    return { spell = "ShadowDance", cond = AND(buffDown(ID_SHADOWDANCE), cpMax(2),
        OR(buffUp(ID_SHADOWBLADES), AND(cdReady(ID_SECRETTECH), sbWindowOk()))) }
end
-- Re-apply the Mark when it is gone and no Darkest Night is pending (the DN Eviscerate
-- re-applies it by itself). Shadowstrike self-gates to Stealth / Dance.
local function rowMarkDS()
    return { spell = "Shadowstrike", cond = AND(buffDown(ID_DSMARK), buffDown(ID_DARKNIGHT)) }
end
-- "If you do not have Ancient Arts active [on Darkest Night during Dance] you can press
-- another Shadowstrike to ensure it procs, even when you have full combo points."
local function rowArtsBeforeDN()
    return { spell = "Shadowstrike", cond = AND(buffUp(ID_SHADOWDANCE), buffUp(ID_DARKNIGHT),
        buffDown(ID_ANCIENTARTS), lastCastNot(ID_SHADOWSTRIKE)) }
end

local deathstalker_st = {
    rowStealth(),
    rowGoremaw(),                                                          -- [1]
    rowMarkDS(),                                                           -- "start the fight with Shadowstrike"
    rowDanceDS(),                                                          -- [2]
    rowBlades(),                                                           -- [3]
    rowArtsBeforeDN(),                                                     -- (guide note)
    { spell = "Eviscerate", cond = AND(buffUp(ID_DARKNIGHT), cpMin(6)) },  -- [4]
    rowSecretTech(),                                                       -- [5]
    rowEviscerate(),                                                       -- [6]
    rowVanishST(),                                                         -- "any point Dance is not active"
    rowShadowstrike(),                                                     -- [7]
    rowBackstab(),                                                         -- [7]
}

local deathstalker_aoe = {
    { spell = "Stealth" },
    rowGoremaw(),                                                          -- [1]
    rowDanceDS(),                                                          -- [2]
    rowBlades(),                                                           -- [3]
    rowSecretTech(),                                                       -- [4]
    { spell = "Eviscerate", cond = AND(buffUp(ID_DARKNIGHT), cpMin(6)) },  -- [5]
    rowSnDApply(),
    rowBlackPowder(),                                                      -- [6]
    rowVanishAoE(),                                                        -- Silent Storm
    rowStorm(),                                                            -- [7]
}

local heroLists = {
    trickster    = { st = trickster_st,    aoe = trickster_aoe },
    deathstalker = { st = deathstalker_st, aoe = deathstalker_aoe },
}

-- Strict known-checks on each tree's giveaway: Unseen Blade is the Trickster keystone
-- (same check Outlaw uses); Mark for Death is auto-learned by talenting Deathstalker.
-- Fallback = Trickster (what the user runs; Icy Veins rates Deathstalker the "best
-- choice" -- pick your own in Options).
local function activeHero()
    if API and API.IsKnownStrict then
        if API.IsKnownStrict(ID_UNSEENBLADE) then return "trickster" end
        if API.IsKnownStrict(ID_MARKDEATH)   then return "deathstalker" end
    end
    return "trickster"
end

-- Look-ahead helpers. Inside the queue simulation S._sim holds the auras earlier picks
-- turned on/off; otherwise (and for anything the sim hasn't touched) read the live
-- Cooldown Manager state. Untracked reads as down.
local FINISHER = { Eviscerate = true, SecretTechnique = true, BlackPowder = true }
local BUILDER  = { Shadowstrike = 2, Backstab = 1, ShurikenStorm = "perTarget" }
local function simAura(S, id)
    if S and S._sim and S._sim[id] ~= nil then return S._sim[id] and true or false end
    if not (API.IsTracked and API.IsTracked(id)) then return false end
    return API.IsAuraActive(id) == true
end
local function simConsume(S, id)
    if S and S._sim then S._sim[id] = false end
end

local spec = {
    key      = "ROGUE_SUBTLETY",
    label    = "Subtlety",
    className = "Rogue",
    specID   = 261,
    resource = COMBO,             -- COMBO POINTS: discrete -> readable in combat (exact gates)
    resourceLabel = "Combo Pts",
    maelstromMax = 7,

    alerts = {},

    -- "Subtlety switches to a multi-target rotation already with two or more targets."
    cleaveAt = 2,
    aoeAt    = 2,

    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "trickster",    label = "Trickster" },
        { key = "deathstalker", label = "Deathstalker" },
    },

    -- Energy is secret and the guide says not to manage it: a spender unusable ONLY for
    -- lack of energy still shows (you press it as energy ticks up).
    softPowerUsable = true,
    condTags = { nopower = true, supercharge = true, stealth = true },

    -- SUPERCHARGER (470347, 2/2): Shadow Dance supercharges 2 combo points; each DAMAGING
    -- finisher consumes one and hits as if it spent 2 more. Not readable, so predicted from
    -- our casts (same engine tracker as Outlaw) -- live and per queue slot. PERSISTS out of
    -- combat: the guide's pre-pull move is a Shadow Dance 20s+ before the pull to bank them.
    superchargeTrack = {
        talent  = ID_SUPERCHARGER,
        charge  = { ShadowDance = 2 },
        consume = { Eviscerate = true, SecretTechnique = true, BlackPowder = true },
        persist = true,
    },

    -- Shadowstrike needs Stealth / Shadow Dance, so its live usable flag is false until you
    -- actually Dance. A QUEUED Shadowstrike after a queued Dance / Vanish is fine.
    usableAfter = {
        Shadowstrike = { ShadowDance = true, Vanish = true, Stealth = true },
    },

    -- Show the live override's icon/name: Eviscerate -> Coup de Grace (Trickster) and
    -- Backstab -> Gloomblade if talented. Reads stay on the base spell.
    overrideDisplay = true,

    -- Finishers are castable at any CP >= 1; the game reports their cost as the max.
    finishers = { Eviscerate = true, SecretTechnique = true, BlackPowder = true },

    fillers = { [ID_BACKSTAB] = true, [ID_SHURIKENSTORM] = true },
    -- No cooldown, so the queue may show them again in later slots (their combo-point
    -- conditions decide): Eviscerate after an Ancient Arts refund, Shadowstrike spam in Dance.
    repeatable = { [ID_EVISCERATE] = true, [ID_BLACKPOWDER] = true, [ID_SHADOWSTRIKE] = true },

    -- Not offered by the Cooldown Manager for Subtlety (no cooldown to show), so Setup
    -- leaves them out of the "add to Essential / Utility" column. PRIO reads them directly.
    cdmUnavailable = { [ID_SHADOWSTRIKE] = true, [ID_BLACKPOWDER] = true, [ID_SHURIKENSTORM] = true },

    -- Pulse the Eviscerate icon while Darkest Night is up (Deathstalker's key press).
    flash = {
        Eviscerate = { type = "buffActive", spell = ID_DARKNIGHT },
    },

    -- Fixed (non-haste) cooldowns, dead-reckoned from the cast so "Cooldown >= / <=" reads
    -- in combat: Shadow Blades 90s, Vanish 120s.
    cooldownTrack = {
        ShadowBlades = { base = 90 },
        Vanish       = { base = 120 },          -- always 2 min (not hasted, nothing reduces it)
    },

    -- Shadow Dance: 2 charges on a flat 20s recharge (not hasted, nothing reduces it --
    -- same shape as Windwalker's Zenith). Current charges are secret in combat, so they're
    -- PREDICTED: synced out of combat, -1 per cast, +1 every 20s, re-anchored on the
    -- readable charge-count edge. Lets the queue show a second Dance when one is banked.
    chargeTrack = {
        ShadowDance = { max = 2, recharge = 20 },
    },
    -- The game won't let you Shadow Dance while Shadow Dance is up. The live usable flag
    -- already covers the primary; this keeps the queue from stacking Dance -> Dance when a
    -- second charge is banked.
    unusableWhile = { ShadowDance = ID_SHADOWDANCE },

    -- The Cooldown Viewer read lags a tick behind; assume our own Dance / Blades are up
    -- right after the cast so Shadow Blades and Secret Technique queue behind Dance.
    assumeOnCast = {
        ShadowDance  = { aura = ID_SHADOWDANCE,  dur = 2 },
        ShadowBlades = { aura = ID_SHADOWBLADES, dur = 2 },
    },
    -- Look-ahead aura changes per simulated cast. Vanish / Stealth arm Premeditation (the
    -- next builder gives full CP); Eviscerate keeps Slice and Dice up (Cut to the Chase) and
    -- spends Darkest Night. Ancient Arts / Premeditation are consumed inside ResourceDelta,
    -- which needs to see them first.
    spellEffects = {
        ShadowDance  = { grant = { ID_SHADOWDANCE } },
        ShadowBlades = { grant = { ID_SHADOWBLADES } },
        Vanish       = { grant = { ID_PREMEDITATION, ID_STEALTH } },
        Stealth      = { grant = { ID_PREMEDITATION, ID_STEALTH } },
        Shadowstrike = { consume = { ID_STEALTH } },          -- breaks Stealth (not Dance)
        Eviscerate   = { grant = { ID_SND }, consume = { ID_DARKNIGHT } },
    },

    -- Look-ahead combo points. Combo points read clean, so every slot starts from the real
    -- value; this only has to predict what the queued casts do to it:
    --   * Finishers spend everything -- UNLESS Ancient Arts is up, which refunds you back to
    --     max (it expends Shadow Techniques like a builder), so the next slot is another
    --     finisher, not a builder.
    --   * Builders: Shadowstrike 2, Backstab 1, Shuriken Storm 1 PER TARGET. Premeditation
    --     (after Stealth / Vanish) makes the next one fill to max; Shadow Blades doubles them.
    -- Not modelled: Shadow Techniques' banked points from auto attacks (random) and which
    -- builder will proc Ancient Arts (needs the secret stack count).
    ResourceDelta = function(_, key, sid, S)
        local cur = S.maelstrom or 0
        local cap = S.maelstromMax
        if not cap or cap <= 0 then cap = 7 end
        if FINISHER[key] then
            if simAura(S, ID_ANCIENTARTS) then
                simConsume(S, ID_ANCIENTARTS)
                return cap - cur
            end
            return -cur
        end
        local gen = BUILDER[key]
        if not gen then return 0 end
        if gen == "perTarget" then gen = math.max(1, S.enemies or 1) end
        if simAura(S, ID_PREMEDITATION) then
            simConsume(S, ID_PREMEDITATION)
            return cap - cur
        end
        if simAura(S, ID_SHADOWBLADES) then gen = gen * 2 end
        return gen
    end,

    condPresets = {
        { key = "finisherCP",   label = "Finisher combo points (>=6)", clause = cpMin(6) },
        { key = "lowCP",        label = "Low combo points (<=2)",      clause = cpMax(2) },
        { key = "inDance",      label = "Shadow Dance up",             clause = buffUp(ID_SHADOWDANCE) },
        { key = "blades",       label = "Shadow Blades up",            clause = buffUp(ID_SHADOWBLADES) },
        { key = "ancientArts",  label = "Ancient Arts up",             clause = buffUp(ID_ANCIENTARTS) },
        { key = "noAncientArts", label = "Ancient Arts down",          clause = buffDown(ID_ANCIENTARTS) },
        { key = "coupReady",    label = "Coup de Grace ready (Trickster)", clause = coupReady() },
        { key = "darkestNight", label = "Darkest Night up (Deathstalker)", clause = buffUp(ID_DARKNIGHT) },
        { key = "silentStorm",  label = "Silent Storm up",             clause = buffUp(ID_SILENTSTORM) },
        { key = "supercharged", label = "Supercharged CP banked",      clause = scMin(1) },
    },

    auras = {
        ShadowDance       = ID_SHADOWDANCE,
        ShadowBlades      = ID_SHADOWBLADES,
        GoremawsBite      = ID_GOREMAW,
        AncientArts       = ID_ANCIENTARTS,
        ShadowTechniques  = ID_SHADOWTECH,
        SilentStorm       = ID_SILENTSTORM,
        Premeditation     = ID_PREMEDITATION,
        SliceAndDice      = ID_SND,
        CoupDeGrace       = ID_COUPTRACK,
        DarkestNight      = ID_DARKNIGHT,
        DeathstalkersMark = ID_DSMARK,
        Stealth           = ID_STEALTH,
    },

    debug = {
        { label = "Shadow Dance",       kind = "buff", spell = ID_SHADOWDANCE },
        { label = "Shadow Blades",      kind = "buff", spell = ID_SHADOWBLADES },
        { label = "Ancient Arts",       kind = "buff", spell = ID_ANCIENTARTS },
        { label = "Slice and Dice",     kind = "buff", spell = ID_SND },
        { label = "Darkest Night (DS)", kind = "buff", spell = ID_DARKNIGHT },
        { label = "Deathstalker's Mark (DS)", kind = "buff", spell = ID_DSMARK },
    },
    economy = {
        gen   = { "Shadowstrike", "Backstab", "Shuriken Storm" },
        spend = { "Eviscerate", "Secret Technique", "Black Powder" },
    },

    rotationDebug = {
        title = "Rotation Ability & Buff Debug",
        abilities = {
            "ShadowDance", "ShadowBlades", "SecretTechnique", "GoremawsBite",
            "Eviscerate", "BlackPowder", "Shadowstrike", "Backstab",
            "ShurikenStorm", "Vanish",
        },
        buffs = {
            { label = "Shadow Dance",       spell = ID_SHADOWDANCE },
            { label = "Shadow Blades",      spell = ID_SHADOWBLADES },
            { label = "Ancient Arts",       spell = ID_ANCIENTARTS },
            { label = "Shadow Techniques",  spell = ID_SHADOWTECH },
            { label = "Slice and Dice",     spell = ID_SND },
            { label = "Silent Storm",       spell = ID_SILENTSTORM },
            { label = "Premeditation",      spell = ID_PREMEDITATION },
            { label = "Darkest Night (DS)", spell = ID_DARKNIGHT },
            { label = "Deathstalker's Mark", spell = ID_DSMARK },
        },
        rangeProbes = {
            { label = "Combo Points", kind = "resource" },
            { label = "Energy low",   kind = "noPower", spell = ID_BACKSTAB },
            -- Supercharger (470347): predicted 0-2, set to 2 by Shadow Dance, -1 per
            -- Eviscerate / Secret Technique / Black Powder.
            { label = "Supercharged CP", kind = "predCount", field = "superCharge" },
        },
    },

    setup = {
        { kind = "trackedAura", label = "Shadow Dance tracked", spell = ID_SHADOWDANCE,
          hint = "Track Shadow Dance in Tracked Buffs. Shadow Blades and Secret Technique are gated on being inside a Dance, and the Dance row waits for the current one to end." },
        { kind = "trackedAura", label = "Shadow Blades tracked", spell = ID_SHADOWBLADES,
          hint = "Track Shadow Blades in Tracked Buffs. While it is up you Dance again as soon as the first Dance ends (Trickster) and Dance ignores the Secret Technique cooldown." },
        { kind = "trackedAura", label = "Ancient Arts tracked", spell = ID_ANCIENTARTS,
          hint = "Track Ancient Arts (1268932) in Tracked Buffs. IMPORTANT: if it is not tracked, PRIO assumes it is missing and asks for one extra Shadowstrike before every Secret Technique (Trickster) / Darkest Night Eviscerate (Deathstalker)." },
        { kind = "trackedAura", label = "Slice and Dice tracked", spell = ID_SND, optional = true,
          hint = "Cut to the Chase keeps Slice and Dice up off your Eviscerates. In AoE, Black Powder does not -- PRIO asks for one Eviscerate to apply it when it is missing." },
        { kind = "trackedAura", label = "Darkest Night tracked", spell = ID_DARKNIGHT, optional = true,
          hint = "DEATHSTALKER ONLY: track Darkest Night. It drives the 6+ CP Eviscerate and the extra-Shadowstrike-for-Ancient-Arts rule. Harmless to skip on Trickster." },
        { kind = "trackedAura", label = "Deathstalker's Mark tracked", spell = ID_DSMARK, optional = true,
          hint = "DEATHSTALKER ONLY: track Deathstalker's Mark so PRIO can ask for a Shadowstrike to re-apply it. Harmless to skip on Trickster." },
        { kind = "info", label = "Coup de Grace (Trickster)",
          hint = "No tracking needed -- PRIO reads when your Eviscerate button turns into Coup de Grace and shows its icon on the Eviscerate row. In AoE it then beats Black Powder." },
        { kind = "info", label = "Energy and Thistle Tea",
          hint = "Energy is secret in combat and the guide says there is nothing to manage: outside Shadow Dance you will simply have idle globals. Take the auto-cast Thistle Tea talent." },
    },

    spells = {
        Eviscerate      = ID_EVISCERATE,
        SecretTechnique = ID_SECRETTECH,
        ShadowDance     = ID_SHADOWDANCE,
        ShadowBlades    = ID_SHADOWBLADES,
        GoremawsBite    = ID_GOREMAW,
        Backstab        = ID_BACKSTAB,
        Shadowstrike    = ID_SHADOWSTRIKE,
        ShurikenStorm   = ID_SHURIKENSTORM,
        BlackPowder     = ID_BLACKPOWDER,
        Vanish          = ID_VANISH,
        Stealth         = ID_STEALTH,
        SliceandDice    = ID_SND,
        ThistleTea      = ID_THISTLETEA,
        Rupture         = ID_RUPTURE,
    },

    -- Openers (Icy Veins 12.1.5). Trickster ST/AoE are the user's screenshots; the
    -- Deathstalker one is the page's Deathstalker tab (pre-pull Dance for Supercharger
    -- is done out of combat and isn't part of the sequence).
    openerReady = { "ShadowBlades" },
    openerByVariant = {
        trickster = {
            st  = { "Shadowstrike", "Eviscerate", "Vanish", "Shadowstrike", "GoremawsBite",
                    "ShadowDance", "ShadowBlades", "SecretTechnique", "Shadowstrike", "Eviscerate" },
            aoe = { "Shadowstrike", "GoremawsBite", "ShadowDance", "ShadowBlades",
                    "SecretTechnique", "ShurikenStorm", "BlackPowder", "ShurikenStorm", "Eviscerate" },
        },
        deathstalker = {
            st  = { "Shadowstrike", "Eviscerate", "Vanish", "Shadowstrike", "GoremawsBite",
                    "Eviscerate", "ShadowBlades", "ShadowDance", "ShurikenStorm", "SecretTechnique" },
            aoe = { "Shadowstrike", "GoremawsBite", "ShadowDance", "ShadowBlades",
                    "SecretTechnique", "ShurikenStorm", "BlackPowder", "ShurikenStorm", "Eviscerate" },
        },
    },
    precombat = {},

    -- Recommended macros, shown in /prio setup with a Copy button each. `icon` is the
    -- spell whose texture labels the row. Keep names <= 16 chars and bodies <= 255.
    macros = {
        { name = "Powder+Coup", icon = ID_BLACKPOWDER,
          note = "Coup de Grace when it's up, otherwise Black Powder.",
          body = "#showtooltip Black Powder\n/cast Coup de Grace\n/cast Black Powder" },
        { name = "Blades+Trinkets", icon = ID_SHADOWBLADES,
          note = "Shadow Blades with both trinkets and your potion.",
          body = "#showtooltip Shadow Blades\n/cast Shadow Blades\n/use 13\n/use 14\n/use Light's Potential" },
        { name = "Shadow Tea", icon = ID_SHADOWDANCE,
          note = "Shadow Dance (off the global cooldown) straight into Secret Technique.",
          body = "#showtooltip Shadow Dance\n/use 13\n/cast Shadow Dance\n/cast Secret Technique" },
    },

    pickable = {
        "Eviscerate", "SecretTechnique", "ShadowDance", "ShadowBlades", "GoremawsBite",
        "Shadowstrike", "Backstab", "ShurikenStorm", "BlackPowder", "Vanish", "Stealth",
        "SliceandDice", "ThistleTea", "Rupture",
    },
}

-- spec.priority is a live proxy resolving to the ACTIVE hero's list for a mode.
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.trickster
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
