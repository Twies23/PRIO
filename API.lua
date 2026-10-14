-- API.lua ----------------------------------------------------------------------
-- Secret-value-safe wrappers around the 12.1 API. Every read is pcall-guarded and
-- checked against issecretvalue; unreadable results fail *open* so the engine
-- never hides the whole rotation because it couldn't read one value.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local API = {}
PRIO.API = API

local issecret = issecretvalue or issecret
local function IsSecret(v)
    if not issecret then return false end
    local ok, s = pcall(issecret, v)
    return ok and s or false
end
API.IsSecret = IsSecret

local function SafeNum(v)
    if v == nil or IsSecret(v) then return nil end
    local ok, n = pcall(tonumber, v)
    if ok then return n end
    return nil
end
API.SafeNum = SafeNum

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------
function API.GetSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    local id = GetSpecializationInfo and GetSpecializationInfo(idx)
    return id
end

function API.IsActiveSpec()
    local id = API.GetSpecID()
    return id ~= nil and PRIO.specs and PRIO.specs[id] ~= nil
end

--------------------------------------------------------------------------------
-- Spell info
--------------------------------------------------------------------------------
function API.SpellName(spellID)
    local n = SafeCall(C_Spell and C_Spell.GetSpellName, spellID)
    return n or ("Spell " .. tostring(spellID))
end

function API.SpellTexture(spellID)
    local t = SafeCall(C_Spell and C_Spell.GetSpellTexture, spellID)
    return t or 134400
end

function API.IsKnown(spellID)
    if not spellID then return false end
    -- Overrides FIRST: a talented spell often replaces a base one (Flame Shock ->
    -- Voltaic Blaze), and IsPlayerSpell returns false for the overridden base even
    -- though you still "have" it. IsSpellKnownOrOverridesKnown handles that.
    if C_SpellBook and C_SpellBook.IsSpellKnownOrOverridesKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnownOrOverridesKnown, spellID)
        if ok and known then return true end
    end
    if IsSpellKnownOrOverridesKnown then
        local ok, known = pcall(IsSpellKnownOrOverridesKnown, spellID)
        if ok and known then return true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    -- Tracked by the Cooldown Viewer counts as "have it": covers DoTs and
    -- proc/hero abilities that aren't spellbook-known but are clearly yours.
    if API.IsTracked and API.IsTracked(spellID) then return true end
    return false
end

-- STRICT "is this spell talented/in your spellbook" -- no Cooldown-Viewer or override
-- fallback. Use for stable decisions (hero-tree detection) that must NOT flip when an
-- ability becomes tracked or temporarily granted mid-combat.
function API.IsKnownStrict(spellID)
    if not spellID then return false end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    return false
end

-- Full usability read: usable(bool/nil), insufficientPower(bool/nil). nil = the
-- value was secret/unreadable. Since our own Maelstrom reads secret in combat,
-- this insufficientPower flag is how spender abilities get gated on resources.
function API.UsableInfo(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, insufficient = pcall(C_Spell.IsSpellUsable, spellID)
        if ok then
            if type(usable) == "table" then
                insufficient = usable.insufficientPower or usable.noMana or usable.notEnoughPower
                usable = usable.isUsable or usable.usable
            end
            local u = (not IsSecret(usable)) and (usable and true or false) or nil
            local i = (not IsSecret(insufficient)) and (insufficient and true or false) or nil
            return u, i
        end
    end
    return nil, nil
end

-- Usable ignoring resource (resource is gated separately). Fails open.
function API.IsUsable(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, spellID)
        if ok then
            if type(usable) == "table" then
                local u = usable.isUsable
                if u ~= nil and not IsSecret(u) then return u and true or false end
            elseif not IsSecret(usable) then
                return usable and true or false
            end
        end
    end
    return true  -- fail open
end

-- Diagnostic: what C_Spell.IsSpellUsable actually exposes for a spell, so we can
-- tell in the Debug window whether "not enough Energy" is a READABLE signal (it
-- would let us gate Tiger Palm) or secret like the Energy bar itself.
function API.UsableDebug(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return "no api" end
    local ok, a, b = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return "err" end
    local function show(v)
        if v == nil then return "nil" end
        if IsSecret(v) then return "secret" end
        return tostring(v)
    end
    if type(a) == "table" then
        return ("usable=%s noPower=%s"):format(show(a.isUsable), show(a.insufficientPower))
    end
    return ("usable=%s noPower=%s"):format(show(a), show(b))
end

-- Insufficient-power flag from IsSpellUsable: true = can't afford it right now,
-- false = affordable, nil = secret/unknown. This reads CLEAN in combat even when the
-- power bar itself is secret (confirmed for Windwalker Energy on Tiger Palm), so it's
-- how we gate an energy spender we can't afford without ever reading the Energy value.
function API.InsufficientPower(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return nil end
    local ok, usable, insufficient = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return nil end
    if type(usable) == "table" then
        insufficient = usable.insufficientPower or usable.noMana or usable.notEnoughPower
    end
    if insufficient == nil or IsSecret(insufficient) then return nil end
    return insufficient and true or false
end

-- Strict usable read: true/false when clean, nil when secret/unknown. Unlike
-- API.IsUsable (which fails OPEN to true), this never guesses -- used to pin a charge
-- spell's low count (castable => >=1 charge) only when the flag is genuinely readable.
function API.UsableClean(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return nil end
    local ok, usable = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return nil end
    if type(usable) == "table" then usable = usable.isUsable end
    if usable == nil or IsSecret(usable) then return nil end
    return usable and true or false
end

-- "Should we still recommend this?" -- true if usable, OR if the ONLY thing stopping it
-- is insufficient power (Energy regens, so you'll press it in a moment). A genuinely
-- unusable spell (out of range, no target, wrong form) still returns false. This lets a
-- spender show at low Energy instead of collapsing to the cheapest builder -- no Energy
-- model, just the game's own insufficient-power flag as the indicator.
function API.UsableOrNoPower(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellUsable) then return true end
    local ok, a, b = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return true end
    local usable, noPower = a, b
    if type(a) == "table" then usable, noPower = a.isUsable, a.insufficientPower end
    if usable == nil or IsSecret(usable) then return true end   -- unreadable -> recommend (fail open)
    if usable then return true end
    -- Not usable: allow it only if it's (or might be) just a power shortfall.
    if noPower == nil or IsSecret(noPower) then return true end  -- can't tell why -> fail open
    return noPower and true or false
end

-- True while stealthed (Stealth / Vanish / Shadow Dance). IsStealthed() is a clean
-- boolean, readable in combat -- so a "Stealthed" condition is exact, not predicted.
function API.Stealthed()
    if type(IsStealthed) ~= "function" then return false end
    local ok, s = pcall(IsStealthed)
    return (ok and s) and true or false
end

-- Pet state -- readable in combat (not a secret value). Exists = a pet is summoned;
-- Alive = that pet is up and not dead. Used by the Hunter pet guardian.
function API.PetExists()
    return SafeCall(UnitExists, "pet") and true or false
end
function API.PetAlive()
    if not API.PetExists() then return false end
    if SafeCall(UnitIsDead, "pet") then return false end
    return true
end

-- Does the CURRENT TARGET have this aura (e.g. your Hunter's Mark debuff)? Reads the unit
-- aura directly (UnitAuraID), so it's per-target and handles target swaps -- unlike the
-- Cooldown Manager buff read, which only says "a mark exists somewhere". true = present,
-- false = absent (target exists, no aura), nil = no target / secret / unavailable.
function API.TargetHasAura(spellID)
    if not (spellID and SafeCall(UnitExists, "target")) then return nil end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local ok, d = pcall(C_UnitAuras.GetAuraDataBySpellID, "target", spellID)
        if ok then
            if d == nil then return false end
            if IsSecret(d) then return nil end
            return true
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Cooldown: the reliable clean-boolean readiness test.
--   ready = not (isActive and not isOnGCD)
-- Falls back to startTime/duration with a GCD filter when the bools are absent.
-- Returns: isReady(bool)
--------------------------------------------------------------------------------
function API.IsReady(spellID)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCooldown, spellID)
    if type(info) == "table" then
        local isActive, isOnGCD = info.isActive, info.isOnGCD
        if isActive ~= nil and not IsSecret(isActive) then
            if isOnGCD ~= nil and not IsSecret(isOnGCD) then
                return not (isActive and not isOnGCD)
            end
            -- No GCD flag: treat short durations as the GCD (ready).
            local dur = SafeNum(info.duration)
            if dur and dur > 0 and dur <= 1.5 then return true end
            return not isActive
        end
        -- Legacy shape: startTime + duration.
        local startTime, duration = SafeNum(info.startTime or info.start), SafeNum(info.duration)
        if not startTime or not duration then return true end        -- secret/unknown -> ready
        if startTime == 0 or duration == 0 then return true end
        if duration <= 1.5 then return true end                      -- GCD, not a real CD
        return false
    end

    -- Charge spells: ready if any charge in hand.
    local charges = SafeCall(C_Spell and C_Spell.GetSpellCharges, spellID)
    if type(charges) == "table" then
        local cur = SafeNum(charges.currentCharges)
        if cur ~= nil then return cur >= 1 end
        if charges.isActive ~= nil and not IsSecret(charges.isActive) then
            return not charges.isActive
        end
    end
    return true  -- fail open
end

-- Base (unmodified) cooldown in seconds -- static data, never secret. Used by the
-- queue simulation to tell "has a real cooldown" from "spammable / no cooldown".
function API.BaseCooldownSeconds(spellID)
    if not (spellID and GetSpellBaseCooldown) then return 0 end
    local ok, ms = pcall(GetSpellBaseCooldown, spellID)
    ms = ok and SafeNum(ms) or nil
    return (ms and ms > 0) and (ms / 1000) or 0
end

-- True if the spell costs a resource (Maelstrom etc). Static cost data, not
-- secret. The queue sim uses this so a spender never appears twice in a row --
-- we can't read Maelstrom to know you can afford a second one.
function API.HasPowerCost(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if ok and type(costs) == "table" then
        for _, c in ipairs(costs) do
            local cost = SafeNum(c and c.cost)
            if cost and cost > 0 then return true end
        end
    end
    return false
end

-- The spell's resource cost amount (Maelstrom etc), or nil. Static, not secret.
-- Cost of a spell. With `powerType` (e.g. the spec's resource), returns ONLY the cost
-- of that power type -- so a spell that costs Energy doesn't get compared against Combo
-- Points. Without it, returns the first non-zero cost (legacy). nil = no such cost.
function API.PowerCostAmount(spellID, powerType)
    if not (spellID and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if ok and type(costs) == "table" then
        for _, c in ipairs(costs) do
            local cost = SafeNum(c and c.cost)
            if cost and cost > 0 and (powerType == nil or c.type == powerType) then return cost end
        end
    end
    return nil
end

-- Secret-safe charge state, the way EllesmereUI's Cooldown Manager reads it.
-- GetSpellCharges().isActive is a CLEAN boolean (the recharge-active flag): it is
-- false ONLY at max charges, and stays readable while currentCharges is secret.
-- Returns: maxCharges (clean/static, nil if not a charge spell),
--          current (EXACT count when derivable without a secret, else nil),
--          belowMax (true = definitely recharging/below max, false = at max, nil = unknown).
-- At max we know the count exactly (= maxCharges) without ever touching the secret
-- currentCharges. Out of combat currentCharges is clean, so we use it directly.
function API.ChargeState(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCharges) then return nil end
    local ok, ch = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or type(ch) ~= "table" then return nil end
    local maxC = SafeNum(ch.maxCharges)
    if not maxC or maxC < 1 then return nil end          -- not a charge spell
    local cur = SafeNum(ch.currentCharges)               -- clean out of combat; nil if secret
    if cur ~= nil then return maxC, cur, cur < maxC end
    local active = ch.isActive
    if active == nil or IsSecret(active) then return maxC, nil, nil end
    if not active then return maxC, maxC, false end      -- at max: exact, secret-free
    -- Recharging (below max). Pin the low end with CASTABILITY, read from the charge-aware
    -- cooldown (IsReady) -- NOT the plain usable flag (IsSpellUsable), which ignores
    -- cooldown/charges and reads TRUE even at 0 charges (that bug made a 2-charge spell
    -- report 1 when it had 0). IsReady is the same signal that makes Lava Burst castable at
    -- 1/3 but not 0/3: castable => >=1 charge in hand; not castable => 0. For a 2-charge
    -- spell that resolves the exact 0/1; for 3+ it only bounds the low end (leave the
    -- middle to prediction).
    local castable = API.IsReady and API.IsReady(spellID)
    if castable == true then
        if maxC == 2 then return maxC, 1, true end       -- below max & castable => exactly 1
        return maxC, nil, true                           -- 3+ charges: >=1 but ambiguous
    elseif castable == false then
        return maxC, 0, true                             -- can't cast => 0 charges
    end
    return maxC, nil, true                               -- readiness unknown -> prediction fills
end

-- Clean seconds until the next charge returns, via the duration OBJECT's method
-- (the object answers a readable number even when the raw start/duration are secret --
-- the same handle EllesmereUI drives its recharge bars with). nil if not recharging /
-- not available.
function API.ChargeRechargeRemaining(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellChargeDuration) then return nil end
    local ok, dur = pcall(C_Spell.GetSpellChargeDuration, spellID)
    if ok and dur and dur.GetRemainingDuration then
        local rok, rem = pcall(dur.GetRemainingDuration, dur)
        if rok then return SafeNum(rem) end
    end
    return nil
end

-- Second candidate for the recharge remaining: the spell's COOLDOWN start/duration
-- (GetSpellCooldown). For a charge spell this reflects the recharge in progress. Some
-- reads that are secret via the charge-duration object are readable here (or vice-versa),
-- so we probe both. nil if not on cooldown / secret / unavailable.
function API.ChargeCooldownRemaining(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return nil end
    local start, dur = SafeNum(info.startTime), SafeNum(info.duration)
    if not start or not dur or start == 0 or dur == 0 then return nil end
    if dur <= 1.5 then return nil end                    -- GCD, not a recharge
    local rem = (start + dur) - GetTime()
    return rem > 0 and rem or 0
end

-- For a CHARGE spell, returns maxCharges (>=1, static/readable) and currentCharges
-- (may be nil/secret). For a non-charge spell, GetSpellCharges returns nil, so we
-- return nil -- callers use that to tell "charge-limited" from "spammable filler".
-- (A charge spell's cooldown is a recharge, so GetSpellBaseCooldown reads 0 and
-- can't be trusted to detect it.)
function API.Charges(spellID)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCharges, spellID)
    if type(info) == "table" then
        local maxC = SafeNum(info.maxCharges)
        if maxC and maxC >= 1 then return maxC, SafeNum(info.currentCharges) end
    end
    return nil, nil
end

-- Full charge read for the predictor: maxCharges, currentCharges (nil if secret),
-- rechargeDuration (nil if secret). maxCharges is nil for non-charge spells.
function API.ChargeFull(spellID)
    local info = SafeCall(C_Spell and C_Spell.GetSpellCharges, spellID)
    if type(info) == "table" then
        local maxC = SafeNum(info.maxCharges)
        if maxC and maxC >= 1 then
            return maxC, SafeNum(info.currentCharges), SafeNum(info.cooldownDuration)
        end
    end
    return nil, nil, nil
end

-- Drive a CooldownFrame's swipe WITHOUT ever comparing the secret numbers.
-- The widget's SetCooldown accepts secret start/duration natively; we only gate on
-- the clean isActive/isOnGCD booleans (skip the GCD). Wrapped in pcall so any
-- unexpected secret taint degrades to a cleared swipe instead of erroring.
-- Drive the swipe from the player's CURRENT cast/channel so it matches the real
-- cast time (Lightning Bolt's ~2s, not the GCD). The player's own cast times are
-- generally readable; if they come back secret we return false and the caller
-- falls back to the GCD. Returns true if a cast swipe was set.
function API.ApplyCastSwipe(cd)
    if not cd then return false end
    local ok, set = pcall(function()
        local name, _, _, startMS, endMS = UnitCastingInfo("player")
        local channel = false
        if not name then
            name, _, _, startMS, endMS = UnitChannelInfo("player")
            channel = name ~= nil
        end
        if not name then return false end
        local s, e = SafeNum(startMS), SafeNum(endMS)
        if s and e and e > s then
            cd:SetReverse(channel)                 -- channels drain, casts fill
            cd:SetCooldown(s / 1000, (e - s) / 1000)
            return true
        end
        return false                               -- casting but times secret
    end)
    return ok and set or false
end

-- Drive the swipe from the global cooldown (spell 61304 -- never secret), so the
-- primary icon sweeps on each cast.
function API.ApplyGCDSwipe(cd)
    if not cd then return end
    pcall(function()
        cd:SetReverse(false)
        local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(61304)
        if type(info) == "table" and info.startTime and info.duration then
            cd:SetCooldown(info.startTime, info.duration, info.modRate or 1)
        else
            cd:Clear()
        end
    end)
end

function API.ApplyCooldownSwipe(cd, spellID)
    if not cd then return end
    local ok = pcall(function()
        local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
        if type(info) == "table" and info.isActive == true and info.isOnGCD ~= true then
            cd:SetCooldown(info.startTime, info.duration, info.modRate or 1)
        else
            cd:Clear()
        end
    end)
    if not ok then cd:Clear() end
end

--------------------------------------------------------------------------------
-- Resources (player's own power reads as a real number; guarded anyway)
--------------------------------------------------------------------------------
function API.Power(powerType)
    local cur = SafeCall(UnitPower, "player", powerType)
    return SafeNum(cur)
end

function API.PowerMax(powerType)
    local mx = SafeCall(UnitPowerMax, "player", powerType)
    return SafeNum(mx)
end

-- Player haste as a percent (e.g. 14.3), readable (a character stat, not secret). Used
-- to scale Energy regen -- Windwalker's Energy regenerates faster with haste.
function API.Haste()
    if GetHaste then
        local ok, h = pcall(GetHaste)
        if ok and type(h) == "number" and not IsSecret(h) then return h end
    end
    if UnitSpellHaste then
        local ok, h = pcall(UnitSpellHaste, "player")
        if ok and type(h) == "number" and not IsSecret(h) then return h end
    end
    return 0
end

-- Player power as a clean PERCENT (0-100), even when the raw amount is secret. WoW's
-- UnitPowerPercent with the ScaleTo100 curve is the sanctioned "show a percentage, not
-- the number" path (EllesmereUI uses it unguarded for its bar text), so unlike
-- UnitPower it reads clean in combat. Returns nil if unavailable/secret. Lets us tell
-- "Energy near cap" (avoid-capping lines) without ever reading the secret Energy value.
function API.PowerPercent(powerType)
    if not (UnitPowerPercent and powerType) then return nil end
    local scale = (CurveConstants and CurveConstants.ScaleTo100) or nil
    local ok, pct = pcall(UnitPowerPercent, "player", powerType, true, scale)
    if ok and type(pct) == "number" and not IsSecret(pct) then return pct end
    return nil
end

--------------------------------------------------------------------------------
-- Enemy count: hostile nameplates that are in combat. Best-effort (bounded by
-- nameplate visibility). Great for ST/Cleave/AoE mode switching.
--------------------------------------------------------------------------------
function API.EnemyCount()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return 1 end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return 1 end
    local engagedOnly = not (PRIO.db and PRIO.db.enemyDetect == "nameplates")
    local playerInCbt = SafeCall(UnitAffectingCombat, "player")
    local n = 0
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            local exists = SafeCall(UnitExists, unit)
            local canAtk = SafeCall(UnitCanAttack, "player", unit)
            local dead   = SafeCall(UnitIsDead, unit)   -- nil (secret) -> treat as alive
            if exists and canAtk and not dead then
                if not engagedOnly then
                    n = n + 1
                else
                    -- "Engaged with me": on their threat table, flagged in combat, or
                    -- my current target. In 12.1 the threat/combat state of an enemy
                    -- nameplate can come back SECRET (nil), which would collapse the
                    -- count to just the target (1) and freeze the mode in ST. So:
                    --   * use the precise signals when they're readable, else
                    --   * fall back to counting attackable nameplates while I'm in
                    --     combat (in a real pull a visible enemy plate is our fight;
                    --     training dummies -- named "Dummy" -- also land here).
                    local threat = SafeCall(UnitThreatSituation, "player", unit)
                    local inCbt  = SafeCall(UnitAffectingCombat, unit)
                    local isTgt  = SafeCall(UnitIsUnit, unit, "target")
                    local counted = (threat ~= nil) or inCbt or isTgt
                    if not counted and playerInCbt and threat == nil and inCbt == nil then
                        counted = true                         -- signals secret -> assume in-fight
                    end
                    if counted then n = n + 1 end
                end
            end
        end
    end
    return n > 0 and n or 1
end

--------------------------------------------------------------------------------
-- Cooldown Viewer aura tracking.
-- Blizzard's own Cooldown Viewer item frames expose a CLEAN IsActive() boolean per
-- tracked spell -- buffs AND debuffs/DoTs on the current target (Flame Shock) --
-- readable in combat. This is the sanctioned way to know an aura is up without
-- touching secret aura data. We map tracked spellID -> item frame and read it.
--------------------------------------------------------------------------------
local VIEWERS = {
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer",  "BuffBarCooldownViewer",
}
local trackedFrames = {}   -- spellID -> Blizzard item frame (any viewer)
-- Aura viewers ONLY. Many spells sit in BOTH an ability viewer and an aura viewer under
-- the SAME spellID -- every Assassination DoT does (Garrote 703, Rupture 1943, Envenom
-- 32645, Deathmark 360194, Slice and Dice 315496, Kingsbane 385627 are each in Essential
-- *and* TrackedBuff). An Essential frame's IsActive() means "the ABILITY is on cooldown",
-- which is a completely different question from "the aura is up" -- and answering an aura
-- question with a cooldown frame silently inverts it. So aura reads resolve here first and
-- only fall back to the general map. (Elemental never hit this because Flame Shock's aura
-- id 470411 differs from its cast id 188389, so the two never collided.)
local trackedAuraFrames = {}
local trackedViewers = {}   -- spellID -> "Essential+BuffIcon" etc, for the probe
local AURA_VIEWERS = { BuffIconCooldownViewer = true, BuffBarCooldownViewer = true }

-- EVERY frame registered for a spell id, across all four viewers. One spell routinely
-- has several: Garrote is an Essential ability icon AND a Tracked Buff AND (optionally) a
-- Tracked Bar, all under 703. Each kind publishes "the aura is up" differently (see
-- entryAuraActive), and any ONE of them saying so is enough.
local trackedEntries = {}   -- spellID -> { { frame=, cdID=, aura=bool, viewer="BuffIcon" }, ... }
local lastRefresh = 0

-- PANDEMIC. Blizzard publishes the refresh window by calling ShowPandemicStateFrame /
-- HidePandemicStateFrame on the item frame, so we observe those calls. Reading
-- frame.PandemicIcon:IsShown() is NOT reliable: UI addons that draw their own pandemic
-- glow (EllesmereUI does) hide Blizzard's PandemicIcon the instant it appears, so the
-- icon reads hidden while the spell is visibly glowing.
local pandemicState  = setmetatable({}, { __mode = "k" })   -- frame -> true while in pandemic
local pandemicHooked = setmetatable({}, { __mode = "k" })
local function pandemicShow(self) pandemicState[self] = true end
local function pandemicHide(self) pandemicState[self] = nil end
local function hookPandemic(frame)
    if pandemicHooked[frame] or not hooksecurefunc then return end
    if type(frame.ShowPandemicStateFrame) ~= "function" then return end
    pandemicHooked[frame] = true
    pcall(hooksecurefunc, frame, "ShowPandemicStateFrame", pandemicShow)
    if type(frame.HidePandemicStateFrame) == "function" then
        pcall(hooksecurefunc, frame, "HidePandemicStateFrame", pandemicHide)
    end
end

function API.RefreshTracked()
    lastRefresh = GetTime and GetTime() or 0
    wipe(trackedFrames)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return end
    wipe(trackedAuraFrames)
    wipe(trackedViewers)
    wipe(trackedEntries)
    for _, name in ipairs(VIEWERS) do
        local isAuraViewer = AURA_VIEWERS[name]
        local short = name:gsub("CooldownViewer", "")
        local viewer = _G[name]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do
                local cdID = frame.cooldownID or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
                if cdID then
                    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if ok and type(info) == "table" then
                        hookPandemic(frame)
                        local function map(id)
                            id = SafeNum(id)
                            if id and id > 0 then
                                trackedFrames[id] = frame
                                if isAuraViewer then trackedAuraFrames[id] = frame end
                                local list = trackedEntries[id]
                                if not list then list = {}; trackedEntries[id] = list end
                                local dup = false
                                for i = 1, #list do if list[i].frame == frame then dup = true end end
                                if not dup then
                                    list[#list + 1] = { frame = frame, cdID = cdID, aura = isAuraViewer and true or false, viewer = short }
                                end
                                local cur = trackedViewers[id]
                                if not cur then trackedViewers[id] = short
                                elseif not cur:find(short, 1, true) then
                                    trackedViewers[id] = cur .. "+" .. short
                                end
                            end
                        end
                        map(info.spellID)
                        map(info.overrideSpellID)
                        map(info.overrideTooltipSpellID)
                        if type(info.linkedSpellIDs) == "table" then
                            for _, lid in ipairs(info.linkedSpellIDs) do map(lid) end
                        end
                    end
                end
            end
        end
    end
end

-- Is this tracked frame currently active? true/false when readable, nil when secret.
local function frameActive(frame)
    if frame.IsActive then
        local ok, active = pcall(frame.IsActive, frame)
        if ok and active ~= nil and not IsSecret(active) then return active and true or false end
    end
    -- Fallback: swipe-colour first channel (nonzero => active), per EllesmereUI CDM.
    -- Guard the exact value we compare so we never compare a secret number.
    local sc = frame.cooldownSwipeColor
    if type(sc) == "table" and sc.GetRGBA then
        local ok, r = pcall(sc.GetRGBA, sc)
        if ok and type(r) == "number" and not IsSecret(r) then return r ~= 0 end
    end
    return nil
end

-- Does the frame currently RENDER `text` in one of its FontStrings? Used to tell apart
-- linked spells that share one Cooldown-Manager frame (e.g. the Roll the Bones stage
-- buffs: the bar shows "One of a Kind" / "Double Trouble" / "Triple Threat"). Tolerant
-- of truncation ("Double Troub...") via prefix matching. Rendered text reads clean in
-- combat (same path as the stack-count number). Returns true/false, or nil if we can't
-- read any text at all.
local function frameShowsText(frame, text)
    if not text or text == "" then return nil end
    local target = text:lower()
    local sawAny, matched = false, false
    local ok = pcall(function()
        local function consider(fs)
            if type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString" and fs.GetText then
                local t = fs:GetText()
                if type(t) == "string" and t ~= "" then
                    local s = t:lower():gsub("%.%.%.$", ""):gsub("%s+$", "")
                    if s ~= "" and not tonumber(s) then       -- ignore the duration/stack number
                        sawAny = true
                        if target == s or target:find(s, 1, true) == 1 or s:find(target, 1, true) == 1 then
                            matched = true
                        end
                    end
                end
            end
        end
        if frame.Name then consider(frame.Name) end
        if frame.Label then consider(frame.Label) end
        if frame.GetRegions then for _, r in ipairs({ frame:GetRegions() }) do consider(r) end end
        if frame.GetChildren then
            for _, ch in ipairs({ frame:GetChildren() }) do
                if ch.GetRegions then for _, r in ipairs({ ch:GetRegions() }) do consider(r) end end
            end
        end
    end)
    if not ok or not sawAny then return nil end
    return matched
end

-- Spells whose "active" read must be disambiguated by the frame's rendered NAME, because
-- several of them alias to one Cooldown-Manager frame (linked spells). Specs register
-- their IDs here (see Spec_Outlaw's Roll the Bones stage buffs). Empty for every other
-- spec -> no extra work, no behaviour change.
API.linkedNameDisambig = API.linkedNameDisambig or {}

-- true/false when the tracked aura's state is readable, nil when we can't tell
-- (spell not tracked by the viewer). Callers fail open on nil.
-- These are POOLED frames: when the Cooldown Manager re-lays out (an icon hides when
-- inactive, you add or remove a tracked spell) a frame is handed to a different cooldown.
-- The map used to be built once per spec change, so after any such change PRIO kept
-- reading a frame that now belonged to something else. Rebuild it on a cheap throttle,
-- and immediately when an entry is seen to have changed hands.
local REFRESH_EVERY = 1.0
local function ensureFresh()
    local now = GetTime and GetTime() or 0
    if now - lastRefresh >= REFRESH_EVERY then API.RefreshTracked() end
end
local function entryFresh(e)
    local ok, cd = pcall(function() return e.frame.cooldownID end)
    if not ok or cd == nil or IsSecret(cd) then return true end   -- unreadable: do not churn
    return cd == e.cdID
end
local function entriesFor(spellID)
    ensureFresh()
    local list = trackedEntries[spellID]
    if list then
        for i = 1, #list do
            if not entryFresh(list[i]) then
                API.RefreshTracked()
                return trackedEntries[spellID]
            end
        end
    end
    return list
end

-- "Is the aura up", asked the way each kind of frame actually answers it:
--   * aura viewers (Tracked Buff / Tracked Bar): the item's own IsActive().
--   * ability viewers (Essential / Utility): Blizzard shows the AURA's timer on the ability
--     icon while it is up, and marks the frame with wasSetFromAura / auraInstanceID. That is
--     the "there is a timer on the icon" signal -- and it is the dependable one for a DoT on
--     your TARGET, where the buff viewer is known to stall (it can sit inactive until a real
--     target switch). `hasAuraEntry` keeps the old IsActive() read for ids that live ONLY
--     in an ability viewer, so nothing that relied on it changes.
local function entryAuraActive(e, hasAuraEntry)
    local f = e.frame
    if e.aura then return frameActive(f) end
    local ok, shown = pcall(function()
        local w = f.wasSetFromAura
        if w ~= nil and not IsSecret(w) and w then return true end
        return type(f.auraInstanceID) ~= "nil"      -- type() is safe on a secret id
    end)
    if ok and shown then return true end
    if not hasAuraEntry then return frameActive(f) end
    -- Explicit branch on purpose: `ok and false or nil` is ALWAYS nil in Lua.
    if not ok then return nil end
    return false
end

-- Back-compat single-frame resolver (stacks / text reads): an aura viewer's frame first.
local function auraFrame(spellID)
    ensureFresh()
    return trackedAuraFrames[spellID] or trackedFrames[spellID]
end
API.AuraFrameIsFromAuraViewer = function(spellID) return trackedAuraFrames[spellID] ~= nil end

-- Backstop for a debuff YOU put on the TARGET whose only Cooldown Manager frame is a
-- Tracked Buff item (Deathstalker's Mark): that item can fail to bind the aura and sit
-- inactive until a real target switch, and there is no ability icon to fall back on.
-- Ask the game for "my aura of this name on the target" (ownership filtered by the
-- engine). POSITIVE-ONLY: a hit means it is up; nil or a secret result means "no
-- information", never "absent" -- so where the read is restricted this changes nothing.
local function targetAuraByName(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and UnitExists) then return nil end
    local okE, exists = pcall(UnitExists, "target")
    if not okE or IsSecret(exists) or not exists then return nil end
    local name = API.SpellName(spellID)
    if type(name) ~= "string" or name == "" then return nil end
    local filter = "HARMFUL|PLAYER"
    if UnitIsFriend then
        local okF, friend = pcall(UnitIsFriend, "player", "target")
        if okF and not IsSecret(friend) and friend then filter = "HELPFUL|PLAYER" end
    end
    local ok, d = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, filter)
    if ok and d ~= nil and not IsSecret(d) then return true end
    return nil
end
API.TargetAuraByName = targetAuraByName

function API.IsAuraActive(spellID)
    if not spellID then return nil end
    local list = entriesFor(spellID)
    if list and #list > 0 then
        local hasAuraEntry = false
        for i = 1, #list do if list[i].aura then hasAuraEntry = true end end
        local sawFalse = false
        for i = 1, #list do
            local e = list[i]
            local active = entryAuraActive(e, hasAuraEntry)
            if active == true then
                -- If this spell shares its frame with other linked spells, it is only THE
                -- active one when the frame is currently showing its name.
                if e.aura and API.linkedNameDisambig[spellID] then
                    local shows = frameShowsText(e.frame, API.SpellName(spellID))
                    if shows ~= nil then return shows end
                end
                return true
            elseif active == false then
                sawFalse = true
            end
        end
        if hasAuraEntry and targetAuraByName(spellID) then return true end
        if sawFalse then return false end
        return nil
    end
    -- NOT Cooldown-Manager tracked: read the player aura directly. This is the only
    -- path for buffs the CDM doesn't track -- e.g. the named Roll the Bones stage buffs
    -- (One of a Kind / Double Trouble / Triple Threat), which the RtB bar doesn't expose
    -- as a stack. Clean present -> true, clean absent -> false, secret -> nil (in combat
    -- if the aura is protected). Tracked auras above are untouched by this fallback.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then
            if d == nil then return false end
            if IsSecret(d) then return nil end
            return true
        end
    end
    return nil
end

function API.IsTracked(spellID)
    if spellID == nil then return false end
    ensureFresh()
    return trackedFrames[spellID] ~= nil
end

-- Live buff STACK COUNT, secret-safe. Blizzard's Cooldown Viewer renders the aura's
-- application count to a fontstring on the BuffIcon item frame; we read that rendered
-- text (a clean string) rather than the secret .applications value. Blizzard only
-- draws the number when it's > 1, so: no frame -> nil; not active -> 0; active with a
-- number -> that number; active without a number -> 1. Requires the buff to be tracked
-- in the Cooldown Manager.
-- Target health percent (0-100) if readable, else nil (no target, or a secret value).
-- Tests whether execute range (< 35%) can be detected at all -- enemy health may or may
-- not be a secret value in combat like our own resources are.
function API.TargetHealthPct()
    if not (UnitExists and UnitExists("target")) then return nil end
    local okH, h  = pcall(UnitHealth, "target")
    local okM, hm = pcall(UnitHealthMax, "target")
    if not (okH and okM) then return nil end
    if h == nil or hm == nil or IsSecret(h) or IsSecret(hm) then return nil end
    h, hm = tonumber(h), tonumber(hm)
    if not (h and hm) or hm <= 0 then return nil end
    return (h / hm) * 100
end

-- Spell activation overlay ("proc glow"): true when Blizzard is glowing the spell's
-- button (e.g. Bladestorm lights up at 3 Imminent Demise, Execute at a Sudden Death
-- proc). This is a DIFFERENT signal than the aura stack count, so it can be readable
-- even when stacks are secret. Returns true/false, or nil if the API is missing.
-- Guarded for secret values like everything else.
function API.SpellGlowing(spellID)
    if not spellID then return nil end
    -- Modern namespaced API first, then the classic global.
    local fn = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
        or IsSpellOverlayed
    if not fn then return nil end
    local ok, glowing = pcall(fn, spellID)
    if not ok then return nil end
    if glowing == nil or IsSecret(glowing) then return nil end
    return glowing and true or false
end

function API.AuraStackCount(spellID)
    local frame = auraFrame(spellID)
    if not frame then return nil end
    local active = API.IsAuraActive(spellID)
    if active == false then return 0 end

    -- PRIMARY: the aura's own .applications, if it reads clean (guarded for secret in
    -- API.AuraStacks). Some stacking buffs expose this even in combat -- when they do
    -- it's exact, so prefer it over the rendered-text heuristic.
    local direct = API.AuraStacks(spellID)
    if direct and direct > 0 then return direct end

    -- FALLBACK: read the number Blizzard renders on the Cooldown Viewer item frame.
    -- It lives in different spots by viewer type, so scan the known named fields AND
    -- any FontString region on the frame or its direct children for numeric text.
    local ok, n = pcall(function()
        local best = nil
        local function consider(fs)
            if type(fs) == "table" and fs.GetText and fs.GetObjectType and fs:GetObjectType() == "FontString" then
                local txt = fs:GetText()
                -- type() reports "string" even for a SECRET string, and comparing one
                -- (txt ~= "") taints/throws -- so guard with IsSecret and SKIP secret
                -- fontstrings, continuing the scan (a later clean one may hold the count).
                if type(txt) == "string" and not IsSecret(txt) and txt ~= "" then
                    local num = tonumber((txt:gsub("%D", "")))
                    if num and (not best or num > best) then best = num end
                end
            end
        end
        -- Named spots first (fast path for the common BuffIcon/BuffBar layouts).
        local af = frame.Applications
        if af then consider(af); if type(af) == "table" then consider(af.Applications) end end
        if frame.Icon and frame.Icon.Applications then consider(frame.Icon.Applications) end
        if frame.Bar and frame.Bar.Applications then consider(frame.Bar.Applications) end
        if frame.Count then consider(frame.Count) end
        -- Then sweep regions on the frame and one level of child frames.
        if frame.GetRegions then for _, r in ipairs({ frame:GetRegions() }) do consider(r) end end
        if frame.GetChildren then
            for _, ch in ipairs({ frame:GetChildren() }) do
                if ch.GetRegions then for _, r in ipairs({ ch:GetRegions() }) do consider(r) end end
                consider(ch.Applications)
            end
        end
        return best
    end)
    if ok and n then return n end
    if active == true then return 1 end       -- up, but no readable count = assume 1 stack
    return nil
end

-- The count Blizzard draws ON A SPELL'S COOLDOWN MANAGER ICON -- e.g. the 1 / 2 Sudden
-- Death stacks shown on Execute. It sits in one of three spots depending on the frame
-- layout (EllesmereUI reads the same ones): frame.Applications.Applications (aura stacks
-- on an item), frame.Icon.Applications (container-Icon items), frame.ChargeCount.Current
-- (spell charges). Returns:
--   n, "text"   -- the number, read from text that is CLEAN (exact)
--   nil, "secret" -- a count is on screen but its text is a secret value (combat lock)
--   nil, "none" / "untracked" -- nothing drawn / the spell isn't in the Cooldown Manager
-- Never compares or stores a secret. Callers fail closed on nil.
local function countSpots(f)
    local out = {}
    local ok = pcall(function()
        if f.Applications then out[#out + 1] = { "Applications", f.Applications.Applications or f.Applications } end
        if f.Icon and f.Icon.Applications then out[#out + 1] = { "Icon.Applications", f.Icon.Applications } end
        if f.ChargeCount then out[#out + 1] = { "ChargeCount", f.ChargeCount.Current or f.ChargeCount } end
    end)
    return ok and out or {}
end
API.IconCountSpots = countSpots

-- The SAME number through the spell API instead of the icon text. The Execute icon draws
-- Sudden Death in its ChargeCount spot (verified in game, 0.10.32 probe), i.e. as the
-- spell's cast count / charges -- and those API fields can read clean where the rendered
-- text is secret. Tries the listed id and its live override (Execute casts as 281000).
-- Only a CLEAN number is ever returned.
local function spellCountIDs(spellID)
    local ids = { spellID }
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, o = pcall(C_Spell.GetOverrideSpell, spellID)
        o = ok and SafeNum(o) or nil
        if o and o ~= spellID then ids[2] = o end
    end
    return ids
end
local function spellApiCount(spellID)
    for _, id in ipairs(spellCountIDs(spellID)) do
        if C_Spell and C_Spell.GetSpellCastCount then
            local ok, c = pcall(C_Spell.GetSpellCastCount, id)
            c = ok and SafeNum(c) or nil
            if c then return c, "castCount" end
        end
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, ch = pcall(C_Spell.GetSpellCharges, id)
            if ok and type(ch) == "table" then
                local maxC, cur = SafeNum(ch.maxCharges), SafeNum(ch.currentCharges)
                if maxC and maxC > 1 and cur then return cur, "charges" end
            end
        end
    end
    return nil
end

function API.IconCount(spellID)
    if not spellID then return nil, "none" end
    local list = entriesFor(spellID)
    if not list or #list == 0 then
        local c, how = spellApiCount(spellID)
        if c then return c, how end
        return nil, "untracked"
    end
    local sawSecret = false
    for i = 1, #list do
        for _, spot in ipairs(countSpots(list[i].frame)) do
            local fs = spot[2]
            local okV, vis = pcall(function() return fs.IsVisible and fs:IsVisible() end)
            if okV and vis ~= nil and not IsSecret(vis) and vis then
                local okT, txt = pcall(function() return fs.GetText and fs:GetText() end)
                if okT and type(txt) == "string" then
                    if IsSecret(txt) then
                        sawSecret = true
                    else
                        local n = tonumber(txt:match("%d+") or "")
                        if n then return n, "text" end
                    end
                end
            end
        end
    end
    -- Text unreadable or blank: ask the spell API for the same number.
    local c, how = spellApiCount(spellID)
    if c then return c, how end
    return nil, sawSecret and "secret" or "none"
end

-- /prio iconcount: everything each count spot on a spell's icon(s) exposes right now,
-- so one in-combat run settles which signal (if any) can tell 1 from 2. Also hooks each
-- spot's SetText once and reports how many times Blizzard has rewritten it since.
local iconSetTextCalls = setmetatable({}, { __mode = "k" })
function API.IconCountProbe(spellID)
    local out = {}
    local function add(f, ...)
        local ok, line = pcall(string.format, f, ...)
        out[#out + 1] = ok and line or "  <format failed>"
    end
    local function val(v)
        if v == nil then return "nil" end
        local okS, secret = pcall(IsSecret, v)
        if okS and secret then return "|cffe0a03a<SECRET>|r" end
        local ok, s = pcall(tostring, v)
        return ok and s or "?"
    end
    local function get(fn) local ok, v = pcall(fn); if ok then return val(v) end return "|cffe0685athrew|r" end
    pcall(API.RefreshTracked)
    add("|cff0cd29f%s|r (%s)  viewers: |cff9fb0be%s|r", tostring(API.SpellName(spellID) or "?"),
        tostring(spellID), trackedViewers[spellID] or "NONE")
    local list = trackedEntries[spellID]
    if not list or #list == 0 then
        add("  |cffe0685anot in any Cooldown Viewer -- add it to Essential or Utility|r")
        return out
    end
    for i = 1, #list do
        local e = list[i]
        add("  |cff6fb3ff[%s]|r frame shown=%s", e.viewer, get(function() return e.frame:IsShown() end))
        local spots = countSpots(e.frame)
        if #spots == 0 then add("      no count regions on this frame") end
        for _, spot in ipairs(spots) do
            local fs = spot[2]
            if hooksecurefunc and type(fs) == "table" and fs.SetText and iconSetTextCalls[fs] == nil then
                iconSetTextCalls[fs] = 0
                pcall(hooksecurefunc, fs, "SetText", function(self) iconSetTextCalls[self] = (iconSetTextCalls[self] or 0) + 1 end)
            end
            add("      %s: shown=%s visible=%s text=%s width=%s  setText calls=%s", spot[1],
                get(function() return fs:IsShown() end), get(function() return fs:IsVisible() end),
                get(function() return fs:GetText() end), get(function() return fs.GetStringWidth and fs:GetStringWidth() end),
                tostring(iconSetTextCalls[fs]))
        end
    end
    -- The same number via the spell API (cast count / charges), for the id and its override.
    for _, id in ipairs(spellCountIDs(spellID)) do
        add("  |cff6fb3ffspell API #%s|r castCount=%s", tostring(id),
            get(function() return C_Spell.GetSpellCastCount(id) end))
        add("      charges: cur=%s max=%s isActive=%s cdDuration=%s  usable=%s ready=%s",
            get(function() return C_Spell.GetSpellCharges(id).currentCharges end),
            get(function() return C_Spell.GetSpellCharges(id).maxCharges end),
            get(function() return C_Spell.GetSpellCharges(id).isActive end),
            get(function() return C_Spell.GetSpellCharges(id).cooldownDuration end),
            get(function() return API.UsableClean and API.UsableClean(id) end),
            get(function() return API.IsReady and API.IsReady(id) end))
    end
    local n, how = API.IconCount(spellID)
    add("  |cff5a6a76PRIO reads:|r count=%s (%s)  glow=%s", val(n), tostring(how), val(API.SpellGlowing(spellID)))
    return out
end

-- Diagnostic: dump everything we can learn about a buff's stack count, so we can see
-- in-game which source is readable. Prints: the raw .applications (and whether it's
-- secret), IsAuraActive, what AuraStackCount resolves to, and every FontString text
-- found on the tracked frame + its children. Drives /prio stackprobe.
-- /prio aura: what each Cooldown Manager frame registered for a spell is saying right now,
-- one line per frame, using exactly the signals IsAuraActive / InPandemic read. Every read
-- is guarded and secrets are labelled, so it is safe to run mid-fight.
function API.AuraFrameProbe(spellID)
    local out = {}
    local function add(f, ...)
        local ok, line = pcall(string.format, f, ...)
        out[#out + 1] = ok and line or "  |cffe0685a<format failed>|r"
    end
    local function val(v)
        if v == nil then return "nil" end
        local ok, secret = pcall(IsSecret, v)
        if ok and secret then return "|cffe0a03a<SECRET>|r" end
        local okS, str = pcall(tostring, v)
        return okS and str or "?"
    end
    local function get(fn) local ok, v = pcall(fn); if ok then return val(v) end return "|cffe0685athrew|r" end

    pcall(API.RefreshTracked)
    add("|cff0cd29f%s|r (%s)  viewers: |cff9fb0be%s|r", tostring(API.SpellName(spellID) or "?"),
        tostring(spellID), trackedViewers[spellID] or "NONE")
    local list = trackedEntries[spellID]
    if not list or #list == 0 then
        add("  |cffe0685anot registered in any Cooldown Viewer|r")
        return out
    end
    local hasAuraEntry = false
    for i = 1, #list do if list[i].aura then hasAuraEntry = true end end
    for i = 1, #list do
        local e = list[i]; local f = e.frame
        add("  |cff6fb3ff[%s]|r IsActive()=%s  wasSetFromAura=%s  auraInstanceID=%s  |cff5a6a76=> aura up:|r %s",
            e.viewer,
            get(function() return f:IsActive() end),
            get(function() return f.wasSetFromAura end),
            get(function() return type(f.auraInstanceID) ~= "nil" and "set" or "nil" end),
            val(entryAuraActive(e, hasAuraEntry)))
        add("      pandemic: hooked=%s  flagged=%s  PandemicIcon=%s",
            val(pandemicHooked[f] and true or false),
            val(pandemicState[f] and true or false),
            get(function() local ic = f.PandemicIcon; if not ic then return "none" end; return ic:IsShown() and "shown" or "hidden" end))
    end
    add("  target read by name (my aura on target): %s",
        targetAuraByName(spellID) and "|cff0cd29ffound|r" or "|cff5a6a76no hit / unreadable|r")
    add("  |cff5a6a76PRIO reads:|r IsAuraActive=%s  InPandemic=%s  stacks=%s",
        val(API.IsAuraActive(spellID)), val(API.InPandemic(spellID)), val(API.AuraStackCount(spellID)))
    return out
end

function API.StackProbe(spellID)
    local out = {}
    local frame = trackedFrames[spellID]
    out[#out + 1] = ("tracked=%s active=%s stackCount=%s")
        :format(tostring(frame ~= nil), tostring(API.IsAuraActive(spellID)),
                tostring(API.AuraStackCount(spellID)))

    -- Raw .applications from C_UnitAuras (player then target), with secret status.
    local function dumpApplications(unit, d)
        if type(d) ~= "table" then return end
        local a = d.applications
        local secret = IsSecret(a)
        out[#out + 1] = ("  %s .applications=%s secret=%s")
            :format(unit, secret and "<secret>" or tostring(a), tostring(secret))
    end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then dumpApplications("player", d) end
    end

    -- Every FontString text on the frame + one level of children (this is where the
    -- rendered count lives; shows us the exact field to read).
    if frame then
        local seen = {}
        local function sweep(f, tag)
            if not f or seen[f] then return end
            seen[f] = true
            if f.GetRegions then
                local ok, regions = pcall(function() return { f:GetRegions() } end)
                if ok then
                    for _, r in ipairs(regions) do
                        if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "FontString" then
                            local t = r.GetText and r:GetText()
                            -- Guard: comparing a SECRET string taints/throws -- log it as
                            -- <secret> and keep scanning so we can see clean fontstrings too.
                            if type(t) == "string" and IsSecret(t) then
                                out[#out + 1] = ("  %s FontString=<secret>"):format(tag)
                            elseif type(t) == "string" and t ~= "" then
                                out[#out + 1] = ("  %s FontString=%q"):format(tag, t)
                            end
                        end
                    end
                end
            end
        end
        sweep(frame, "frame")
        if frame.GetChildren then
            local ok, kids = pcall(function() return { frame:GetChildren() } end)
            if ok then for i, ch in ipairs(kids) do sweep(ch, "child" .. i) end end
        end
    end
    return table.concat(out, "\n")
end

-- Pandemic / "is refreshable" read, secret-safe. Blizzard's Cooldown Viewer computes
-- the pandemic window (the last ~30% where refreshing doesn't clip) and, while the
-- aura is inside it, shows a PandemicIcon on the item frame. We read that already-
-- computed VISUAL state (a clean bool) instead of the secret expiration times.
-- Returns true (refresh now) / false (too early) / nil (not tracked).
-- CAVEAT: Blizzard only computes this when the spell's "Pandemic Time" alert is
-- enabled in the Cooldown Manager; if it isn't, PandemicIcon is never created and
-- this reads false. (See API.RefreshCarryover for a settings-independent probe.)
function API.InPandemic(spellID)
    local list = entriesFor(spellID)
    if not list or #list == 0 then return nil end
    local hasAuraEntry = false
    for i = 1, #list do if list[i].aura then hasAuraEntry = true end end
    for i = 1, #list do
        local e = list[i]
        -- Blizzard told this frame it is in pandemic. Only believe it while the aura is
        -- still up there, so a pooled frame released mid-glow cannot leave a stale "yes".
        if pandemicState[e.frame] and entryAuraActive(e, hasAuraEntry) ~= false then return true end
        -- Blizzard-default style (nobody hides the icon), or the window opened before
        -- our hook was installed.
        local okI, icon = pcall(function() return e.frame.PandemicIcon end)
        if okI and icon then
            local ok, shown = pcall(icon.IsShown, icon)
            if ok and shown ~= nil and not IsSecret(shown) and shown then return true end
        end
    end
    return false
end

-- Settings-independent pandemic probe: how much of the current aura would carry over
-- if refreshed right now (Blizzard's own pandemic math). > 0 across the whole active
-- window, but equals min(remaining, 30% base) -- so we surface it to TEST whether the
-- duration APIs read clean here. Returns carriedOver seconds, or nil if unreadable.
function API.RefreshCarryover(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetRefreshExtendedDuration and C_UnitAuras.GetAuraBaseDuration) then
        return nil
    end
    local d = findAura(spellID)
    if not (d and d.auraInstanceID) then return nil end
    -- The aura was found on player or target; try both units for the duration APIs.
    for _, u in ipairs({ "player", "target" }) do
        local okB, base = pcall(C_UnitAuras.GetAuraBaseDuration, u, d.auraInstanceID, spellID)
        local okE, ext  = pcall(C_UnitAuras.GetRefreshExtendedDuration, u, d.auraInstanceID, spellID)
        -- type() reports "number" even for SECRET values, so guard with IsSecret
        -- before the subtraction or it taints (throws) outside the pcall.
        if okB and okE and type(base) == "number" and type(ext) == "number"
            and not IsSecret(base) and not IsSecret(ext) then
            return ext - base
        end
    end
    return nil
end

-- Simple "do I have this buff" (used out of combat for pre-combat checks).
function API.HasAura(spellID)
    if not (spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    return (ok and a ~= nil and not IsSecret(a)) and true or false
end

-- Main-hand weapon enchant present? (Flametongue etc.)
function API.HasMainHandEnchant()
    if not GetWeaponEnchantInfo then return true end
    local ok, has = pcall(GetWeaponEnchantInfo)
    return (not ok) or (has and true or false)   -- fail open (don't nag on error)
end

-- Enumerate the Cooldown Viewer for condition-target spells, at runtime (no
-- hardcoded aura IDs). Returns a deduped list of { value=spellID, text=name,
-- icon= }. `categories` selects which sets: default = buffs + bars + essential.
function API.EnumerateTracked(categories)
    categories = categories or { 0, 2, 3 }   -- Essential, TrackedBuff, TrackedBar
    local out, seen = {}, {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return out end
    for _, cat in ipairs(categories) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
        if ok and type(ids) == "table" then
            for _, cdID in ipairs(ids) do
                local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                if iok and type(info) == "table" then
                    local sid = SafeNum(info.spellID)
                    if sid and sid > 0 and not seen[sid] then
                        seen[sid] = true
                        out[#out + 1] = { value = sid, text = API.SpellName(sid), icon = API.SpellTexture(sid) }
                    end
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Keybind resolution: map a spell to its action-bar key.
--------------------------------------------------------------------------------
local SLOT_BINDINGS = {
    { first = 1,   last = 12,  prefix = "ACTIONBUTTON" },
    { first = 61,  last = 72,  prefix = "MULTIACTIONBAR1BUTTON" },
    { first = 49,  last = 60,  prefix = "MULTIACTIONBAR2BUTTON" },
    { first = 25,  last = 36,  prefix = "MULTIACTIONBAR3BUTTON" },
    { first = 37,  last = 48,  prefix = "MULTIACTIONBAR4BUTTON" },
    { first = 145, last = 156, prefix = "MULTIACTIONBAR5BUTTON" },
    { first = 157, last = 168, prefix = "MULTIACTIONBAR6BUTTON" },
    { first = 169, last = 180, prefix = "MULTIACTIONBAR7BUTTON" },
}

local function BindingForSlot(slot)
    for _, r in ipairs(SLOT_BINDINGS) do
        if slot >= r.first and slot <= r.last then
            return r.prefix .. (((slot - r.first) % 12) + 1)
        end
    end
end

local function Shorten(key)
    if not key or key == "" then return "" end
    key = key:upper()
    key = key:gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("SHIFT%-", "S")
    key = key:gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
    key = key:gsub("BUTTON", "M"):gsub("NUMPAD", "N")
    return key
end

function API.Keybind(spellID)
    if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return "" end
    local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, spellID)
    if not ok or type(slots) ~= "table" then return "" end
    for _, slot in ipairs(slots) do
        local cmd = BindingForSlot(SafeNum(slot) or 0)
        if cmd then
            local k1, k2 = GetBindingKey(cmd)
            local key = k1 or k2
            if key then return Shorten(key) end
        end
    end
    return ""
end

--------------------------------------------------------------------------------
-- Talents (Traits API). Enumerate the spec's talent tree so conditions can gate
-- on "talent selected / not selected" without any hardcoded talent IDs.
--------------------------------------------------------------------------------
local talentSelected = {}   -- spellID -> true if the talent is currently chosen
local talentList = {}       -- { {value=spellID, text=name, icon=}, ... } (all talents)
local lastConfigID          -- the talent loadout we last read

function API.RefreshTalents()
    wipe(talentSelected); wipe(talentList)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then return end
    lastConfigID = configID
    local cfgOk, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if not cfgOk or type(cfg) ~= "table" or not cfg.treeIDs then return end
    local seen = {}
    for _, treeID in ipairs(cfg.treeIDs) do
        local nOk, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if nOk and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local iOk, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if iOk and type(node) == "table" and node.entryIDs then
                    local activeEntry = node.activeEntry and node.activeEntry.entryID
                    local purchased = (node.ranksPurchased or 0) > 0
                    for _, entryID in ipairs(node.entryIDs) do
                        local eOk, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
                        if eOk and type(entry) == "table" and entry.definitionID then
                            local dOk, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
                            local sid = dOk and type(def) == "table" and SafeNum(def.spellID)
                            if sid and sid > 0 then
                                if not seen[sid] then
                                    seen[sid] = true
                                    talentList[#talentList + 1] =
                                        { value = sid, text = API.SpellName(sid), icon = API.SpellTexture(sid) }
                                end
                                if purchased and activeEntry == entryID then talentSelected[sid] = true end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(talentList, function(a, b) return a.text < b.text end)
end

function API.IsTalentSelected(spellID) return spellID ~= nil and talentSelected[spellID] == true end
function API.GetTalentList() return talentList end

-- True if a talent with this (case-insensitive) name is currently selected.
function API.IsTalentSelectedByName(name)
    if not name then return false end
    name = name:lower()
    for _, o in ipairs(talentList) do
        if o.text and o.text:lower() == name and talentSelected[o.value] then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Enemy nameplates are how EnemyCount sees targets. If they're disabled the count
-- freezes at 1 and the mode gets stuck in ST. Turn them on out of combat (unless
-- the user opted out), and expose the status for the Debug window / options.
--------------------------------------------------------------------------------
function API.NameplatesEnabled()
    local ok, v = pcall(GetCVar, "nameplateShowEnemies")
    return ok and v == "1"
end

function API.NameplateCount()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return 0 end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    return (ok and type(plates) == "table") and #plates or 0
end

function API.EnsureNameplates()
    if PRIO.db and PRIO.db.manageNameplates == false then return end
    if InCombatLockdown() then return end
    if not API.NameplatesEnabled() then pcall(SetCVar, "nameplateShowEnemies", 1) end
end
PRIO:On("PLAYER_ENTERING_WORLD", function() API.EnsureNameplates() end)
PRIO:On("PLAYER_REGEN_ENABLED", function() API.EnsureNameplates() end)

--------------------------------------------------------------------------------
-- Aura probes: try to read a player aura's stack count / remaining time. In 12.1
-- these fields are often SECRET in combat (return userdata, not a number) -- these
-- return the value ONLY when it's a clean number, else nil. Use to test whether
-- Maelstrom Weapon stacks / Flame Shock pandemic windows are actually readable.
--------------------------------------------------------------------------------
local function findAura(spellID)
    -- Player buffs/debuffs (Maelstrom Weapon, Hot Hand, ...).
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and type(d) == "table" then return d end
    end
    -- Target harmful auras (our DoTs, e.g. Flame Shock).
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and SafeCall(UnitExists, "target") then
        for i = 1, 40 do
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
            if not ok or type(d) ~= "table" then break end
            local sid = d.spellId
            if type(sid) == "number" and not IsSecret(sid) and sid == spellID then return d end
        end
    end
    return nil
end
local playerAura = findAura

-- Stack count if readable (a real number, not secret), else nil. NOTE: type() can
-- report "number" for a SECRET value, so IsSecret must be checked before any
-- comparison / arithmetic or it taints (throws) outside a pcall.
function API.AuraStacks(spellID)
    local d = playerAura(spellID)
    if not d then return nil end
    local a = d.applications
    if type(a) == "number" and not IsSecret(a) then return a end
    return nil
end

-- Which source the stack count came from, for the Rotation Debug window. Returns:
--   count(number|nil), source("appl"|"appl-secret"|"cdm"|"assumed"|nil)
-- "appl" = clean .applications (exact); "appl-secret" = .applications exists but is a
-- protected value (so we fell back); "cdm" = read the Cooldown Viewer rendered number;
-- "assumed" = active but no readable count (defaulted to 1).
function API.AuraStackSource(spellID)
    local active = API.IsAuraActive(spellID)
    if active == false then return 0, nil end
    local d = playerAura(spellID)
    local applSecret = d and IsSecret(d.applications) or false
    local clean = API.AuraStacks(spellID)
    if clean and clean > 0 then return clean, "appl" end
    local n = API.AuraStackCount(spellID)   -- runs the CDM fontstring fallback
    if applSecret then return n, "appl-secret" end
    if n and n > 1 then return n, "cdm" end
    if active == true then return n or 1, "assumed" end
    return n, nil
end

-- Seconds remaining if readable (expirationTime is a clean, non-secret number), else nil.
function API.AuraRemaining(spellID)
    local d = playerAura(spellID)
    if not d then return nil end
    local e = d.expirationTime
    if type(e) == "number" and not IsSecret(e) and e > 0 then
        local rem = e - GetTime()
        return rem > 0 and rem or 0
    end
    return nil
end

-- Diagnostic: probe a TRACKED frame to find what reveals its CURRENT active linked
-- spell in combat. Roll the Bones (#1214909) aliases its stage buffs (One of a Kind /
-- Double Trouble / Triple Threat) to one frame, so IsAuraActive can't tell the stage.
-- The frame is DISPLAYING the active stage buff, though, so its icon and/or a live
-- field should carry it -- and being display state, may read where the aura (by ID) is
-- secret. Dumps: each stage's spell icon, the FRAME's current icon, any frame field
-- holding a stage/spellID-looking number, and the base aura's name. Drives /prio rtbframe.
function API.FrameProbe(spellID, stageIDs)
    local out = {}
    local frame = trackedFrames[spellID]
    out[#out + 1] = ("tracked frame for #%s: %s"):format(tostring(spellID), tostring(frame ~= nil))

    local function tex(id)
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, id); if ok then return t end
        end
        return nil
    end
    for _, id in ipairs(stageIDs or {}) do
        out[#out + 1] = ("  stage #%s %-18s icon=%s"):format(id, API.SpellName(id) or "?", tostring(tex(id)))
    end

    -- Base aura name (the user's hunch: does the active aura report its stage NAME?).
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs({ spellID }) do
            local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and type(d) == "table" then
                local nm = IsSecret(d.name) and "<secret>" or tostring(d.name)
                local sid = IsSecret(d.spellId) and "<secret>" or tostring(d.spellId)
                out[#out + 1] = ("  base aura #%s: name=%s spellId=%s"):format(id, nm, sid)
            else
                out[#out + 1] = ("  base aura #%s: %s"):format(id, ok and "absent" or "err")
            end
        end
    end

    if not frame then return table.concat(out, "\n") end

    -- FRAME current icon (compare to the stage icons above).
    local icon = frame.Icon or frame.icon
    local fIcon
    if icon then
        for _, m in ipairs({ "GetTextureFileID", "GetTexture" }) do
            if icon[m] then local ok, t = pcall(icon[m], icon); if ok and t then fIcon = t; break end end
        end
    end
    out[#out + 1] = "  FRAME.Icon = " .. tostring(fIcon)

    -- Scan the frame's top-level fields for a stage ID or any 12149xx-range spellID.
    local want = {}; for _, id in ipairs(stageIDs or {}) do want[id] = true end
    local hits = {}
    local okScan = pcall(function()
        for k, v in pairs(frame) do
            if type(v) == "number" and (want[v] or (v > 1200000 and v < 1300000)) then
                hits[#hits + 1] = ("%s=%s"):format(tostring(k), tostring(v))
            end
        end
    end)
    out[#out + 1] = "  frame spellID-like fields: " .. (okScan and (#hits > 0 and table.concat(hits, ", ") or "(none)") or "(scan err)")
    for _, k in ipairs({ "cooldownID", "spellID", "overrideSpellID", "auraInstanceID" }) do
        if frame[k] ~= nil then out[#out + 1] = ("  frame.%s=%s"):format(k, tostring(frame[k])) end
    end

    -- Rendered FontString text (this is where the active stage NAME lives, e.g.
    -- "Double Trouble"). Sweep the frame + one level of children.
    local seen = {}
    local function sweep(f, tag)
        if not f or seen[f] then return end
        seen[f] = true
        if not f.GetRegions then return end
        local okR, regions = pcall(function() return { f:GetRegions() } end)
        if not okR then return end
        for _, r in ipairs(regions) do
            if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
                local t = r:GetText()
                if type(t) == "string" and t ~= "" then out[#out + 1] = ("  %s text=%q"):format(tag, t) end
            end
        end
    end
    sweep(frame, "frame")
    if frame.GetChildren then
        local okC, kids = pcall(function() return { frame:GetChildren() } end)
        if okC then for i, ch in ipairs(kids) do sweep(ch, "child" .. i) end end
    end
    return table.concat(out, "\n")
end

-- Diagnostic: dump EVERY current player buff (HELPFUL), whether or not it's tracked
-- in the Cooldown Viewer. For each: spellId, name, .applications (with secret status)
-- and whether the duration reads clean. This is how we find the IDs of auras that
-- aren't in any CDV category (e.g. the six Roll the Bones buffs) AND learn whether
-- they read clean in combat -- run it OOC to grab IDs, then IN COMBAT to test secrecy.
-- Drives /prio myauras.
function API.DumpPlayerAuras(probeIDs)
    local out = {}

    -- SECTION 1: enumerate all player buffs by index. This WORKS OUT OF COMBAT but is
    -- blocked in combat (GetAuraDataByIndex returns a secret object at index 1, so the
    -- loop can't iterate) -- so use it OOC to discover IDs.
    out[#out + 1] = "|cff6fb3ffEnumerate (works OOC only):|r"
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        out[#out + 1] = "  GetAuraDataByIndex unavailable."
    else
        local found = 0
        for i = 1, 60 do
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(d) ~= "table" then break end
            local sid = d.spellId
            local idStr = (type(sid) == "number" and not IsSecret(sid)) and tostring(sid) or "<secret>"
            local name = (type(sid) == "number" and not IsSecret(sid)) and (API.SpellName(sid) or "?") or "?"
            local a = d.applications
            local appStr = IsSecret(a) and "<secret>" or (type(a) == "number" and a > 0 and ("x" .. a) or "-")
            local durSecret = IsSecret(d.expirationTime)
            out[#out + 1] = ("  #%s  %s  %s%s")
                :format(idStr, name, appStr, durSecret and "  |cffe0685adur:secret|r" or "")
            found = found + 1
        end
        if found == 0 then out[#out + 1] = "  (none enumerable -- expected in combat)" end
    end

    -- SECTION 2: probe SPECIFIC ids via GetPlayerAuraBySpellID. This is a DIFFERENT API
    -- path that can survive combat where enumeration can't -- this is the real test of
    -- whether an untracked aura (e.g. a Roll the Bones buff) is readable while fighting.
    if probeIDs and #probeIDs > 0 then
        out[#out + 1] = "|cff6fb3ffDirect ID probes (GetPlayerAuraBySpellID):|r"
        local haveAPI = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        for _, id in ipairs(probeIDs) do
            local name = API.SpellName(id) or "?"
            if not haveAPI then
                out[#out + 1] = ("  #%s  %s  |cffe0685aAPI missing|r"):format(id, name)
            else
                local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
                if not ok then
                    out[#out + 1] = ("  #%s  %s  |cffe0685aerror|r"):format(id, name)
                elseif d == nil then
                    out[#out + 1] = ("  #%s  %s  |cff5a6a76not present|r"):format(id, name)
                elseif IsSecret(d) then
                    out[#out + 1] = ("  #%s  %s  |cffe0685aPRESENT but SECRET|r"):format(id, name)
                else
                    local a = d.applications
                    local appStr = IsSecret(a) and "appl:secret"
                        or (type(a) == "number" and a > 0 and ("x" .. a) or "x1")
                    local durSecret = IsSecret(d.expirationTime)
                    out[#out + 1] = ("  #%s  %s  |cff0cd29fREADABLE|r %s%s")
                        :format(id, name, appStr, durSecret and "  dur:secret" or "  dur:ok")
                end
            end
        end
    end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Keep the tracked-frame map fresh.
--------------------------------------------------------------------------------
local function refreshAll() API.RefreshTracked(); API.RefreshTalents() end
PRIO:On("PLAYER_ENTERING_WORLD", refreshAll)
PRIO:On("PLAYER_SPECIALIZATION_CHANGED", refreshAll)
PRIO:On("PLAYER_TALENT_UPDATE", refreshAll)
PRIO:On("TRAIT_CONFIG_UPDATED", refreshAll)
PRIO:On("TRAIT_CONFIG_LIST_UPDATED", refreshAll)
PRIO:On("ACTIVE_COMBAT_CONFIG_CHANGED", refreshAll)
PRIO:On("SPELLS_CHANGED", refreshAll)
PRIO:On("COOLDOWN_VIEWER_DATA_LOADED", refreshAll)
-- Rebuild shortly after login too, once the viewer/trait data exists.
PRIO:On("PLAYER_LOGIN", function() C_Timer.After(2, refreshAll) end)

-- Static out-of-combat safety net: talent loadout swaps don't always fire an event
-- we catch, so poll the active config ID and refresh when it changes. Called from
-- the engine tick; cheap, and only does work when the loadout actually changed.
function API.PollTalentConfig()
    if InCombatLockdown() then return end
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return end
    local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
    if ok and id and id ~= lastConfigID then
        refreshAll()   -- RefreshTalents updates lastConfigID
        if PRIO.Engine and PRIO.Engine.RefreshTalentFlags then PRIO.Engine:RefreshTalentFlags() end
    end
end
