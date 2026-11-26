-- Spec_Blood.lua ---------------------------------------------------------------
-- Blood Death Knight (spec 250), patch 12.1.5 (Midnight). PRIO's FIRST TANK SPEC.
--
-- HERO-SPLIT (mirrors Arms / Windwalker): San'layn (default -- ~97% of top keys) and
-- Deathbringer. Active hero = STRICT known-check on Reaper's Mark (439843), the
-- Deathbringer signature San'layn never has.
-- Lists: San'layn = the USER'S TUNED LIST (in-game export), one list for both ST and AoE,
-- with the DRW play as DRW-buff-gated rows inside it. Deathbringer = Method's list, built
-- from the shared named rows (see ROWS), also one list for ST and AoE.
--
-- Built from: Method's Blood guide (12.1.5, updated 2026-10-13) -- per-hero priorities
-- and openers -- cross-checked against two top +24 San'layn logs (7m4kFCRwBnbYDQv6 #31
-- Vividk, tBqcKNg7W96nFGHr #15 Ricordblood, Den of Nalorakk). The logs agree on shape:
-- Death Strike is the most-pressed button (420-530 / 30 min), then Heart Strike (300-420),
-- Vampiric Strike (235-260), Blood Boil (210-310), Death and Decay (~120), Marrowrend
-- (60-95), Death's Caress (30-55), Dancing Rune Weapon (17-18). Neither log casts
-- Consumption, Bonestorm, Tombstone, Soul Reaper, Blooddrinker or Rune Tap -- those lines
-- are IsKnown-filtered, so they only appear if talented.
--
-- TANK SCOPE (user's call): the queue carries the rotation plus the two tank jobs that ARE
-- rotational -- Bone Shield upkeep (Marrowrend) and Death Strike spending. The big
-- defensives (Icebound Fortitude, Anti-Magic Shell, Rune Tap) are left to the player and
-- are NOT in the default lists. EXCEPTION: Vampiric Blood is on cooldown in the SAN'LAYN
-- lists, because there it's the Gift of the San'layn damage window (see VB_ONCD below).
-- On Deathbringer it's a plain defensive and stays the player's.
-- "Death Strike to prevent death" is the player's job too: health is secret in combat.
--
-- SIGNAL REALITY:
--   * RUNIC POWER: the raw value is SECRET in combat. Reads, best first:
--       1. the game's clean PERCENT read (UnitPowerPercent) x max -- a REAL read
--          (resourcePercentRead). Only a real read may fire "Death Strike at 75+ RP"
--          (resourceReadMin) -- it FAILS CLOSED otherwise.
--       2. no read -> a cast-based estimate (ResourceDelta), clamped to Death Strike's clean
--          can-I-afford-it flag (resourceAnchors). Used ONLY for the queue look-ahead, never
--          to gate a spend: top logs spend ~2x the RP that rune spending explains, so it drifts.
--     Death Strike's live affordability is the game's clean insufficient-power flag
--     (affordGate), so the PRIMARY never shows a Death Strike you can't press.
--   * RUNES are a discrete count like combo points (API.Runes: UnitPower, else the per-rune
--     ready flags). The PRIMARY stays on the game's exact usable flag; the look-ahead spends
--     runes per pick (runeModel) so the queue can't stack three Heart Strikes on one rune.
--     "Runes >= / <=" conditions are available in the editor. Rune-starved -> the bottom
--     Death Strike line catches the GCD.
--   * BONE SHIELD (Method: keep >= 5). Reads, all strict (an unreadable read never fires):
--       1. Bone Shield bar reads cleanly ABSENT -> rebuild.
--       2. OSSUARY (219788) is up exactly while Bone Shield has 5+ stacks, so "Bone Shield up
--          but Ossuary cleanly absent" == "below 5" -> top up.
--       3. A cast-seeded 30s duration timer -> refresh with <= 5s left.
--     The stack NUMBER is NOT used: in-game it reads "x1 assumed" (not a real count), and
--     gating on it over-recommended Marrowrend.
--   * PROCS: Crimson Scourge (free DnD) reads from the CDM + the DnD button glow. Vampiric
--     Strike is Heart Strike's override -- read via GetOverrideSpell (overrideActive), the
--     CDM buff, and the Heart Strike glow. Exterminate likewise overrides Marrowrend.
--   * COOLDOWNS: DRW / Reaper's Mark are dead-reckoned (cooldownTrack) for "cd remaining".
-- Verify IDs with /prio spells, /prio tracked; Bone Shield count with /prio stackprobe.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
PRIO.specs = PRIO.specs or {}

local API = PRIO.API
local RUNIC = (Enum and Enum.PowerType and Enum.PowerType.RunicPower) or 6

-- Abilities (user's Cooldown Viewer dump + Method's wowhead links + log cast IDs).
local ID_HEARTSTRIKE    = 206930
local ID_VAMPSTRIKE     = 433895    -- the CAST id (logs): Heart Strike's override while the proc is up
local ID_MARROWREND     = 195182
local ID_BLOODBOIL      = 50842
local ID_DND            = 43265
local ID_DRW            = 49028
local ID_DEATHSTRIKE    = 49998
local ID_DEATHSCARESS   = 195292
local ID_VAMPBLOOD      = 55233
local ID_CONSUMPTION    = 1263824   -- [not in the user's build] empowered in 12.x
local ID_REAPERSMARK    = 439843    -- Deathbringer signature
local ID_EXTERMINATE    = 441378    -- [ID TBD in-game] Marrowrend override after Reaper's Mark
local ID_RAISEDEAD      = 46585

-- Auras. Where one CDM entry carries two auras (433901 = Vampiric Strike AND Essence of the
-- Blood Queen), use the LINKED id so each reads its own frame.
local ID_BONESHIELD     = 195181
local ID_DRW_BUFF       = 81256
local ID_DND_BUFF       = 188290    -- standing in your Death and Decay
local ID_CRIMSON        = 81141     -- Crimson Scourge proc (CDM 81136, linked 81141)
local ID_VS_PROC        = 433899    -- Vampiric Strike ready (CDM 433901, linked 433899)
local ID_ESSENCE        = 433925    -- Essence of the Blood Queen
local ID_GIFT           = 434153    -- Gift of the San'layn (CDM 434152, linked 434153)
local ID_OSSUARY        = 219788    -- Ossuary: Death Strike -5 RP at 5+ Bone Shield
local ID_HEMOSTASIS     = 273947
local ID_COAGULATING    = 463730    -- Coagulating Blood (Death Strike's tracked buff)
local ID_BLOODSHIELD    = 77535
local ID_BLOODPLAGUE    = 55078
local ID_BLOODDEBT      = 1310372   -- [not in the user's build] consumed by Marrowrend / Exterminate
local ID_BOILINGPOINT   = 1265790   -- [not in the user's build] empowered Blood Boil proc

-- Talents that shift the RP model / cooldowns (tooltips verified in-game).
local ID_HEARTBREAKER   = 221536    -- Heart Strike +2 RP per target hit (up to 5)
local ID_REDTHIRST      = 205723    -- Vampiric Blood cooldown -2s per 10 RP spent
local ID_REAPERSONSLAUGHT = 469870  -- Reaper's Mark cooldown -15s (and 1 fewer Exterminate)
-- Chance-based, NOT modeled (the clean ready / charge reads already reflect them):
--   Carnage 458752 (Consumption reset on Blood Shield hits), Plague Infusion 1265869
--   (Blood Plague crits -0.25s Blood Boil).

local BONESHIELD_DUR    = 30        -- Bone Shield duration (refreshed by Marrowrend / Death's Caress)

-- Condition builders -----------------------------------------------------------
local function AND(...) return { op = "and", clauses = { ... } } end
local function OR(...)  return { op = "or",  clauses = { ... } } end
local function buffUp(id)    return { type = "buffActive",  spell = id } end
local function buffDown(id)  return { type = "buffMissing", spell = id } end
local function glow(id)      return { type = "glowing",     spell = id } end
local function rpRead(n)     return { type = "resourceReadMin", v = n } end -- RP >= n on a REAL read only
local function remainMax(id, s) return { type = "auraRemainMax", spell = id, v = s } end
local function chargesEq(n)  return { type = "chargesEq",   v = n } end    -- self charges == n
local function chargesMin(n) return { type = "chargesMin",  v = n } end
local function lastCast(id)  return { type = "lastCast",    spell = id } end
local function buffDownStrict(id) return { type = "buffMissingConfirmed", spell = id } end
local function override(base, to) return { type = "overrideActive", spell = base, v = to } end
local function preset(key)   return { type = "preset:" .. key } end
local function usable(id)    return { type = "usable",      spell = id } end
local function runesMin(n)   return { type = "runesMin",    v = n } end    -- runes ready >= n

--------------------------------------------------------------------------------
-- ROWS. Every list below is assembled from these named rows, so a tuning change lands in
-- every list that uses the row. (Rows are shared tables: nothing mutates defaults -- the
-- editor copies a list into db.customPriorities before you change it.)
--------------------------------------------------------------------------------
-- Tank rows, top of every list (Method, both hero trees).
-- Spend before capping RP. (The "to prevent death" half is the player's: health is secret.)
-- Gated on a REAL RP read only (clean percent read): it FAILS CLOSED when RP can't be read,
-- because the cast-based estimate drifts too far to gate a spend on (top logs spend ~2x the
-- RP that rune spending alone explains). With no read, Death Strike still comes up as the
-- bottom line whenever the game says it's affordable.
local DS_ANTICAP   = { spell = "DeathStrike", cond = rpRead(75) }
-- Bone Shield: gone -> rebuild now; below 5 (Ossuary down) -> top up; about to expire -> refresh.
-- "Gone" uses the CONFIRMED missing check: only a clean "absent" read counts (from the bar, or
-- the game's aura lookup when the bar hides while inactive). The loose check also passes on an
-- UNREADABLE read, and a blank read was firing Marrowrend (over-recommending it in-game).
local BONE_SHIELD  = {
    { spell = "Marrowrend", cond = buffDownStrict(ID_BONESHIELD) },
    { spell = "Marrowrend", cond = preset("boneShieldLow") },
    { spell = "Marrowrend", cond = AND(buffUp(ID_BONESHIELD), remainMax(ID_BONESHIELD, 5)) },
}
-- Bottom of every list: rune-starved GCD -> Death Strike if affordable (live insufficient-power flag).
local DS_DUMP      = { spell = "DeathStrike" }

-- VAMPIRIC BLOOD is a DAMAGE cooldown on San'layn, not just a defensive: while it's up,
-- Gift of the San'layn turns every Heart Strike into Vampiric Strike and empowers Essence
-- of the Blood Queen. Red Thirst (RP spent -> VB cooldown) brings it back every ~35-45s.
-- Logs: 40-56 casts / 30 min, 31-44% uptime. So: on cooldown, next to DRW. Its cooldown
-- is RP-driven, so the row gates on the game's clean ready flag, not a timer.
-- (Deathbringer has no Gift, so there VB stays a player-owned defensive.)
local VB_ONCD      = { spell = "VampiricBlood", cond = buffDown(ID_VAMPBLOOD) }   -- don't overlap a running VB
local DRW_ONCD     = { spell = "DancingRuneWeapon" }                                -- 90s; logs ~every 100s

local DND_MAINT    = { spell = "DeathAndDecay", cond = buffDown(ID_DND_BUFF) }      -- maintenance: stand in it
local DND_CRIMSON  = { spell = "DeathAndDecay", cond = preset("crimsonScourge") }   -- free DnD proc

local BB_FILL      = { spell = "BloodBoil", cond = chargesMin(1) }                  -- spend any charge

-- RUNES (read directly, see runeModel). 3 runes recharge at once (confirmed in-game from the
-- recharge timers), so with 5+ ready at least two recharge slots sit idle: spend one.
local HS_RUNECAP   = { spell = "HeartStrike", cond = runesMin(5) }
-- Filler Heart Strike POOLS for Marrowrend: while Bone Shield is below 5 (Ossuary down) it
-- holds until 2+ runes are ready -- at that point the Marrowrend line above takes them --
-- so a Heart Strike on the last rune never starves the Bone Shield top-up.
local HS_POOLED    = { spell = "HeartStrike", cond = OR(preset("ossuaryUp"), runesMin(2)) }

-- Flatten rows and row-groups into one list.
local function list(...)
    local out = {}
    for _, item in ipairs({ ... }) do
        if item.spell then out[#out + 1] = item
        else for _, r in ipairs(item) do out[#out + 1] = r end end
    end
    return out
end

--------------------------------------------------------------------------------
-- SAN'LAYN: the USER'S TUNED LIST (in-game export, 2026-11-25), used for BOTH ST and AoE.
-- Shape: inside DRW first (Blood Boil on entry, Crimson DnD, Death Strike, Ossuary-gated
-- Vampiric Strike, Blood Boil filler -- or any time Blood Boil is at 2 charges), then Vampiric
-- Blood, an always-on Death Strike (spend RP whenever the game says it's affordable -- RP
-- itself can't be read), then the outside-DRW fillers. OSSUARY (5+ Bone Shield) is the
-- backbone: Marrowrend when it's gone, and Vampiric Strike / Heart Strike (and DnD, unless
-- it's a free Crimson Scourge one) wait for it, so runes go to Bone Shield first.
--------------------------------------------------------------------------------
local sanlayn = {
    { spell = "DancingRuneWeapon" },                                                     -- 1: on cooldown
    { spell = "BloodBoil", cond = AND(buffUp(ID_DRW_BUFF), lastCast(ID_DRW)) },          -- 2: DRW entry
    { spell = "Marrowrend", cond = AND(buffDown(ID_OSSUARY), usable(ID_MARROWREND)) },   -- 3: below 5 Bone Shield
    { spell = "DeathAndDecay", cond = AND(buffUp(ID_CRIMSON), buffUp(ID_DRW_BUFF)) },   -- 4: DRW + free DnD
    { spell = "DeathStrike", cond = buffUp(ID_DRW_BUFF) },                               -- 5: DRW
    { spell = "VampiricStrike",                                                          -- 6: DRW + proc
      cond = AND(preset("vampiricStrike"), buffUp(ID_DRW_BUFF), buffUp(ID_OSSUARY)) },
    { spell = "BloodBoil", cond = OR(buffUp(ID_DRW_BUFF), chargesMin(2)) },              -- 7: DRW filler / don't cap
    { spell = "VampiricBlood", cond = buffDown(ID_VAMPBLOOD) },                          -- 8: on cooldown
    { spell = "DeathStrike" },                                                           -- 9: whenever affordable
    { spell = "DeathAndDecay", cond = OR(buffUp(ID_OSSUARY), preset("crimsonScourge")) }, -- 10
    { spell = "BloodBoil", cond = buffUp(ID_BOILINGPOINT) },                             -- 11: Boiling Point
    { spell = "VampiricStrike", cond = AND(preset("vampiricStrike"), buffUp(ID_OSSUARY)) }, -- 12
    { spell = "BloodBoil" },                                                             -- 13
    { spell = "HeartStrike", cond = buffUp(ID_OSSUARY) },                                -- 14
}

--------------------------------------------------------------------------------
-- DEATHBRINGER (Method's single list -- no DRW-specific rows; the same list serves ST and
-- AoE). Reaper's Mark goes BEFORE DRW: DRW doesn't copy it. Keeps
-- Method's Consumption / Blood Debt / Boiling Point rows: that build takes them (untalented
-- they're IsKnown-filtered / buff-gated). Untested -- the user plays San'layn.
--------------------------------------------------------------------------------
local deathbringer = list(
    DS_ANTICAP, BONE_SHIELD,
    DND_MAINT,
    { spell = "ReapersMark" },                                                          -- on cooldown
    DRW_ONCD,
    { spell = "Marrowrend", cond = OR(buffUp(ID_BLOODDEBT), preset("exterminate")) },   -- Blood Debt via Exterminate
    { spell = "BloodBoil", cond = OR(chargesEq(2), buffUp(ID_BOILINGPOINT)) },          -- don't cap / Boiling Point
    DND_CRIMSON,
    { spell = "Consumption" },                                                          -- Rank I (if talented)
    HS_RUNECAP,
    BB_FILL,                                                                            -- filler while charges last
    HS_POOLED,
    DS_DUMP
)

local heroLists = {
    sanlayn      = { st = sanlayn,      aoe = sanlayn },        -- one tuned list for both
    deathbringer = { st = deathbringer, aoe = deathbringer },
}

local function activeHero()
    if API and API.IsKnownStrict and API.IsKnownStrict(ID_REAPERSMARK) then return "deathbringer" end
    return "sanlayn"
end

local spec = {
    key       = "DEATHKNIGHT_BLOOD",
    label     = "Blood",
    className = "Death Knight",
    specID    = 250,
    -- Bump when the DEFAULT lists change: users with custom Blood lists get a reset prompt
    -- scoped to Blood only (Core.lua PRIO:ChangedDefaultSpecs).
    defaultsRevision = 2,           -- 2: San'layn ST/AoE = the user's tuned list
    resource  = RUNIC,              -- RUNIC POWER: secret in combat -> predicted from casts
    resourceLabel = "Runic Power",
    maelstromMax = 125,             -- RP cap (readable PowerMax overrides)
    -- RP is secret raw, so try the game's clean PERCENT read (percent x max = RP). If that
    -- reads in combat, every RP gate is exact.
    resourcePercentRead = true,
    -- No read? Clamp the cast-based estimate to Death Strike's CLEAN can-I-afford-it flag
    -- (below its cost when it can't be afforded, at least its cost when it can).
    resourceAnchors = {
        { spell = ID_DEATHSTRIKE, cost = function()
            local c = API.PowerCostAmount and API.PowerCostAmount(ID_DEATHSTRIKE, RUNIC)
            return (type(c) == "number" and c > 0) and c or 40
        end },
    },

    -- Blood has no cleave tier. 3+ -> AoE (Blood Boil / DnD carry more weight); 2 targets
    -- stay on the ST list, which already spends Blood Boil before it caps.
    cleaveAt = 3,
    aoeAt    = 3,
    modes = {
        { value = "st",  text = "ST" },
        { value = "aoe", text = "AoE" },
    },

    activeHero = activeHero,
    priorityByVariant = heroLists,
    priorityVariants = {
        { key = "sanlayn",      label = "San'layn" },
        { key = "deathbringer", label = "Deathbringer" },
    },

    condPresets = {
        -- Bone Shield up but below 5 = Ossuary (5+ stacks) tracked and reading ABSENT. Clean
        -- boolean, strict (an unreadable Ossuary never fires). The stack NUMBER is deliberately not
        -- used: in-game it reads "x1 assumed" (no real count), and a fake 1 satisfied "1-4
        -- stacks" -> Marrowrend nearly every GCD. Missing Bone Shield is its own line.
        { key = "boneShieldLow", label = "Bone Shield below 5 (Ossuary down)",
          clause = AND(buffUp(ID_BONESHIELD), buffDownStrict(ID_OSSUARY)) },
        { key = "ossuaryUp", label = "Ossuary up (Bone Shield 5+)", clause = buffUp(ID_OSSUARY) },
        { key = "runes2", label = "2+ runes ready", clause = { type = "runesMin", v = 2 } },
        { key = "boneShieldExpiring", label = "Bone Shield <= 5s left (predicted)",
          clause = AND(buffUp(ID_BONESHIELD), remainMax(ID_BONESHIELD, 5)) },
        { key = "crimsonScourge", label = "Crimson Scourge proc (free DnD)",
          clause = OR(buffUp(ID_CRIMSON), glow(ID_DND)) },
        { key = "vampiricStrike", label = "Vampiric Strike ready",
          clause = OR(override(ID_HEARTSTRIKE, ID_VAMPSTRIKE), buffUp(ID_VS_PROC), glow(ID_HEARTSTRIKE)) },
        { key = "exterminate", label = "Exterminate ready (Marrowrend replaced)",
          clause = OR(override(ID_MARROWREND), glow(ID_MARROWREND)) },
        { key = "drwUp", label = "Dancing Rune Weapon active", clause = buffUp(ID_DRW_BUFF) },
        { key = "vampBloodUp", label = "Vampiric Blood active", clause = buffUp(ID_VAMPBLOOD) },
        { key = "giftUp", label = "Gift of the San'layn active",
          clause = OR(buffUp(ID_GIFT), buffUp(ID_VAMPBLOOD)) },
        { key = "inDnD", label = "Standing in Death and Decay", clause = buffUp(ID_DND_BUFF) },
        { key = "rpHigh", label = "Runic Power >= 75 (real read only)", clause = rpRead(75) },
    },

    spells = {
        HeartStrike       = ID_HEARTSTRIKE,
        VampiricStrike    = ID_VAMPSTRIKE,
        Marrowrend        = ID_MARROWREND,
        BloodBoil         = ID_BLOODBOIL,
        DeathAndDecay     = ID_DND,
        DancingRuneWeapon = ID_DRW,
        DeathStrike       = ID_DEATHSTRIKE,
        DeathsCaress      = ID_DEATHSCARESS,
        VampiricBlood     = ID_VAMPBLOOD,
        Consumption       = ID_CONSUMPTION,
        ReapersMark       = ID_REAPERSMARK,
        RaiseDead         = ID_RAISEDEAD,
    },

    auras = {
        BoneShield     = ID_BONESHIELD,
        DancingRuneWeapon = ID_DRW_BUFF,
        DeathAndDecay  = ID_DND_BUFF,
        CrimsonScourge = ID_CRIMSON,
        VampiricStrike = ID_VS_PROC,
        EssenceOfTheBloodQueen = ID_ESSENCE,
        GiftOfTheSanlayn = ID_GIFT,
        Ossuary        = ID_OSSUARY,
        Hemostasis     = ID_HEMOSTASIS,
        CoagulatingBlood = ID_COAGULATING,
        BloodShield    = ID_BLOODSHIELD,
        BloodPlague    = ID_BLOODPLAGUE,
        BloodDebt      = ID_BLOODDEBT,
        BoilingPoint   = ID_BOILINGPOINT,
        VampiricBlood  = ID_VAMPBLOOD,
    },

    setup = {
        { kind = "info", label = "Runic Power",
          hint = "No tracking needed -- Runic Power is secret in combat, but it only moves with your own casts (runes spent build it, Death Strike spends it), so PRIO predicts it from your casts and re-syncs out of combat. Death Strike's 'can I press it' check uses the game's own clean flag." },
        { kind = "trackedAura", label = "Bone Shield tracked", spell = ID_BONESHIELD,
          hint = "Track Bone Shield (as a bar or icon) so the Marrowrend lines read. 'Missing' always reads; the stack count reads only where the Cooldown Manager renders it -- check /prio stackprobe in combat." },
        { kind = "trackedAura", label = "Ossuary tracked", spell = ID_OSSUARY,
          hint = "Track Ossuary -- it's up exactly while Bone Shield has 5+ stacks, so PRIO uses it as the clean 'Bone Shield below 5 -> Marrowrend' signal even when the stack number can't be read in combat." },
        { kind = "trackedAura", label = "Dancing Rune Weapon tracked", spell = ID_DRW_BUFF,
          hint = "Track the Dancing Rune Weapon buff so the inside-DRW lines (Blood Boil on entry, Blood Boil filler) switch on." },
        { kind = "trackedAura", label = "Death and Decay tracked", spell = ID_DND_BUFF,
          hint = "Track Death and Decay so PRIO knows whether you're standing in it (DnD is a maintenance buff for Blood)." },
        { kind = "trackedAura", label = "Crimson Scourge tracked", spell = ID_CRIMSON,
          hint = "Track Crimson Scourge for the free-DnD line (the DnD button glow is the fallback)." },
        { kind = "trackedAura", label = "Vampiric Blood tracked", spell = ID_VAMPBLOOD,
          hint = "San'layn: Vampiric Blood is your Gift of the San'layn damage window and PRIO suggests it on cooldown. Track its buff so PRIO doesn't re-suggest it while it's already running." },
        { kind = "trackedAura", label = "Gift of the San'layn tracked", spell = ID_GIFT, optional = true,
          hint = "San'layn only. Debug visibility for the Gift window (Heart Strike -> Vampiric Strike for the duration)." },
        { kind = "trackedAura", label = "Vampiric Strike tracked", spell = ID_VS_PROC, optional = true,
          hint = "San'layn only. Optional -- PRIO also reads Heart Strike turning into Vampiric Strike directly." },
    },

    -- Openers (Method raid openers). Death's Caress is the pre-pull pull (initial Bone Shield).
    openerReady = { "DancingRuneWeapon" },
    -- One opener per hero, used for ST and AoE pulls alike (aoe falls back to st).
    openerByVariant = {
        sanlayn      = { st = { "DeathsCaress", "DeathAndDecay", "DancingRuneWeapon", "BloodBoil",
                                "VampiricStrike", "VampiricStrike", "DeathStrike" } },
        deathbringer = { st = { "DeathsCaress", "DeathAndDecay", "ReapersMark", "DancingRuneWeapon",
                                "BloodBoil", "Marrowrend" } },
    },
    openerReadyByVariant = {
        sanlayn      = { "DancingRuneWeapon" },
        deathbringer = { "DancingRuneWeapon", "ReapersMark" },
    },
    precombat = {},

    pickable = {
        "HeartStrike", "VampiricStrike", "Marrowrend", "BloodBoil", "DeathAndDecay",
        "DancingRuneWeapon", "DeathStrike", "DeathsCaress", "VampiricBlood", "Consumption",
        "ReapersMark", "RaiseDead",
    },

    -- Heart Strike is the filler, but it costs a rune -- not free-repeating. Nothing else is.
    fillers = {},

    flash = {
        DeathAndDecay  = { type = "buffActive", spell = ID_CRIMSON },   -- free DnD
        VampiricStrike = { type = "buffActive", spell = ID_VS_PROC },
    },

    -- Heart Strike -> Vampiric Strike and Marrowrend -> Exterminate are game overrides on the
    -- same button. Read cooldown/usable through the active override, and show its icon.
    overrideReads   = true,
    overrideDisplay = true,
    -- 433895 only "exists" while the proc is up: its known-check + keybind follow Heart Strike.
    knownAlias   = { [ID_VAMPSTRIKE] = ID_HEARTSTRIKE },
    keybindAlias = { [ID_VAMPSTRIKE] = ID_HEARTSTRIKE },

    -- Death Strike: live "can I press it" = the game's clean insufficient-power flag; queued
    -- slots fall back to the predicted RP below.
    affordGate = { DeathStrike = true },

    -- Look-ahead: Marrowrend (+3 stacks) puts Bone Shield back up and, from the usual 2-4
    -- stacks, back over 5 -> Ossuary. So later queue slots stop asking for another Marrowrend
    -- and the pooled Heart Strike is released. Death's Caress (+stacks) restores the buff.
    spellEffects = {
        Marrowrend   = { grant = { ID_BONESHIELD, ID_OSSUARY } },
        DeathsCaress = { grant = { ID_BONESHIELD } },
    },

    -- Bone Shield's 30s timer, seeded by the casts that refresh it. Read by the
    -- "<= 5s left" line (secret in combat otherwise).
    auraDurations = {
        Marrowrend   = { spell = ID_BONESHIELD, base = BONESHIELD_DUR },
        DeathsCaress = { spell = ID_BONESHIELD, base = BONESHIELD_DUR },
    },

    -- Dead-reckoned cooldowns for "cd remaining" + queue placement (the rows themselves gate
    -- on the clean ready flag). Vampiric Blood's timer is then pulled in by Red Thirst on
    -- every Death Strike (OnCast below) -- RP-driven, so an estimate, re-anchored the moment
    -- the game reports it ready.
    cooldownTrack = {
        DancingRuneWeapon = { base = 90 },
        ReapersMark       = { base = 45, reduce = { [ID_REAPERSONSLAUGHT] = 15 } },
        VampiricBlood     = { base = 90 },
    },

    -- Runes for the look-ahead. Costs per cast; DnD's Crimson Scourge (free) is only known
    -- live, so the primary uses the exact usable flag and only queued slots use these.
    -- perSlot = regen credited per queued GCD: 3 runes recharge at once, ~10s each ->
    -- ~0.3 runes/s x ~1.5s GCD. Haste speeds both regen and the GCD, so it nets out.
    runeModel = {
        max = 6,
        perSlot = 0.45,
        -- The count is READ directly (per-rune GetRuneCooldown flags, then UnitPower), like
        -- combo points. One of those read 6/6 at 0 runes in-game (12.1), so each is checked
        -- against these spells: Heart Strike (1 rune) / Marrowrend (2) go "on cooldown" when
        -- you can't pay. A read that contradicts them is dropped for the session; with no
        -- honest read left, the probes' own 0 / 1 / 2+ is the fallback.
        probes = {
            { spell = ID_HEARTSTRIKE, cost = 1 },
            { spell = ID_MARROWREND,  cost = 2 },
        },
        costs = {
            HeartStrike = 1, VampiricStrike = 1, Marrowrend = 2, DeathAndDecay = 1,
            DeathsCaress = 1, ReapersMark = 2,
        },
    },
    condTags = { runes = true },

    --------------------------------------------------------------------------------
    -- Runic Power model. ~10 RP per rune spent; Death Strike spends 40 (35 with Ossuary at
    -- 5+ Bone Shield). Seeded from the real value out of combat; advanced on every cast,
    -- live and in the look-ahead.
    --------------------------------------------------------------------------------
    ResourceCost = function(_, key, sid, S)
        if key ~= "DeathStrike" then return 0 end
        local c = API.PowerCostAmount and API.PowerCostAmount(ID_DEATHSTRIKE, RUNIC)
        if type(c) == "number" and c > 0 then return c end
        return 40
    end,

    ResourceDelta = function(self, key, sid, S)
        if key == "DeathStrike" then
            return -(self.ResourceCost(self, key, sid, S) or 40)
        elseif key == "HeartStrike" or key == "VampiricStrike" then
            local gen = 10
            if API.IsTalentSelected(ID_HEARTBREAKER) or API.IsKnown(ID_HEARTBREAKER) then
                gen = gen + 2 * math.min(5, math.max(1, API.EnemyCount() or 1))
            end
            return gen
        elseif key == "Marrowrend"   then return 20   -- 2 runes
        elseif key == "ReapersMark"  then return 20   -- 2 runes
        elseif key == "DeathAndDecay" then return 10  -- 1 rune (0 on Crimson Scourge: slight over-predict)
        elseif key == "DeathsCaress" then return 10
        end
        return 0
    end,

    -- Red Thirst: every 10 RP spent takes 2s off Vampiric Blood. Death Strike is Blood's
    -- RP spender, so pull the predicted VB timer in on each one.
    OnCast = function(P, key, now)
        if key ~= "DeathStrike" then return end
        if not (API.IsTalentSelected(ID_REDTHIRST) or API.IsKnown(ID_REDTHIRST)) then return end
        local e = P.cdExpire and P.cdExpire[ID_VAMPBLOOD]
        if not e then return end
        local self = PRIO.specs[250]
        local spent = (self and self.ResourceCost(self, "DeathStrike")) or 40
        P.cdExpire[ID_VAMPBLOOD] = math.max(now, e - 2 * spent / 10)
    end,

    debug = {
        { label = "Bone Shield",       kind = "buff",  spell = ID_BONESHIELD },
        { label = "Bone Shield stacks", kind = "stacks", spell = ID_BONESHIELD },
        { label = "Dancing Rune Weapon", kind = "buff", spell = ID_DRW_BUFF },
        { label = "In Death and Decay", kind = "buff", spell = ID_DND_BUFF },
        { label = "Crimson Scourge",   kind = "buff",  spell = ID_CRIMSON },
        { label = "Vampiric Strike",   kind = "buff",  spell = ID_VS_PROC },
        { label = "Vampiric Blood",    kind = "buff",  spell = ID_VAMPBLOOD },
        { label = "Gift of the San'layn", kind = "buff", spell = ID_GIFT },
        { label = "Blood Boil charges", kind = "charges", key = "BloodBoil" },
        { label = "DRW CD",            kind = "cdRemain", spell = ID_DRW },
        { label = "Vampiric Blood CD (Red Thirst)", kind = "cdRemain", spell = ID_VAMPBLOOD },
        { label = "Ossuary (5+ Bone Shield)", kind = "buff", spell = ID_OSSUARY },
    },
    economy = {
        gen   = { "Heart Strike / Vampiric Strike", "Marrowrend", "Death and Decay", "Death's Caress", "Reaper's Mark" },
        spend = { "Death Strike" },
    },

    rotationDebug = {
        title = "Blood Rotation Debug",
        abilities = {
            "DeathStrike", "Marrowrend", "HeartStrike", "VampiricStrike", "BloodBoil",
            "DeathAndDecay", "DancingRuneWeapon", "VampiricBlood", "DeathsCaress", "ReapersMark",
            "Consumption",
        },
        buffs = {
            { label = "Vampiric Blood",       spell = ID_VAMPBLOOD },
            { label = "Bone Shield",          spell = ID_BONESHIELD },
            { label = "Dancing Rune Weapon",  spell = ID_DRW_BUFF },
            { label = "Death and Decay",      spell = ID_DND_BUFF },
            { label = "Crimson Scourge",      spell = ID_CRIMSON },
            { label = "Vampiric Strike",      spell = ID_VS_PROC },
            { label = "Essence of the Blood Queen", spell = ID_ESSENCE },
            { label = "Gift of the San'layn", spell = ID_GIFT },
            { label = "Ossuary",              spell = ID_OSSUARY },
            { label = "Coagulating Blood",    spell = ID_COAGULATING },
            { label = "Blood Shield",         spell = ID_BLOODSHIELD },
        },
        glows = {
            { label = "Heart Strike glow (Vampiric Strike?)", spell = ID_HEARTSTRIKE },
            { label = "DnD glow (Crimson Scourge?)",          spell = ID_DND },
            { label = "Marrowrend glow (Exterminate?)",       spell = ID_MARROWREND },
        },
        rangeProbes = {
            { label = "Runic Power (raw)",       kind = "resource" },
            { label = "Runic Power % -> engine", kind = "resourcePercent" },
            { label = "Runes ready",             kind = "runes" },
            { label = "Runes recharging (s)",    kind = "runeRecharge" },
            { label = "Death Strike usable (clean)", kind = "usableClean", spell = ID_DEATHSTRIKE },
        },
    },
}

-- Live proxy: spec.priority[mode] resolves to the ACTIVE hero's list (see Spec_Arms.lua).
spec.priority = setmetatable({}, {
    __index = function(_, mode)
        local h = heroLists[activeHero()] or heroLists.sanlayn
        return h[mode] or h.st
    end,
})

PRIO.specs[spec.specID] = spec
