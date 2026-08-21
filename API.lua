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
function API.PowerCostAmount(spellID)
    if not (spellID and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if ok and type(costs) == "table" then
        for _, c in ipairs(costs) do
            local cost = SafeNum(c and c.cost)
            if cost and cost > 0 then return cost end
        end
    end
    return nil
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
                    -- my current target. Correct in real content. Training dummies
                    -- don't flag combat or hold threat, so ALSO count attackable
                    -- "Dummy" nameplates while I'm in combat -- dummies never appear
                    -- in real content, so this can't over-count a live pull.
                    local threat = SafeCall(UnitThreatSituation, "player", unit)
                    local inCbt  = SafeCall(UnitAffectingCombat, unit)
                    local isTgt  = SafeCall(UnitIsUnit, unit, "target")
                    local isDummy = false
                    if playerInCbt then
                        local nm = SafeCall(UnitName, unit)
                        isDummy = nm and nm:find("Dummy") ~= nil
                    end
                    if threat ~= nil or inCbt or isTgt or isDummy then
                        n = n + 1
                    end
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
local trackedFrames = {}   -- spellID -> Blizzard item frame

function API.RefreshTracked()
    wipe(trackedFrames)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return end
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for frame in pool:EnumerateActive() do
                local cdID = frame.cooldownID or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
                if cdID then
                    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if ok and type(info) == "table" then
                        local function map(id)
                            id = SafeNum(id)
                            if id and id > 0 then trackedFrames[id] = frame end
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

-- true/false when the tracked aura's state is readable, nil when we can't tell
-- (spell not tracked by the viewer). Callers fail open on nil.
function API.IsAuraActive(spellID)
    if not spellID then return nil end
    local frame = trackedFrames[spellID]
    if not frame then return nil end
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

function API.IsTracked(spellID)
    return spellID ~= nil and trackedFrames[spellID] ~= nil
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

function API.RefreshTalents()
    wipe(talentSelected); wipe(talentList)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not ok or not configID then return end
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
-- Keep the tracked-frame map fresh.
--------------------------------------------------------------------------------
local function refreshAll() API.RefreshTracked(); API.RefreshTalents() end
PRIO:On("PLAYER_ENTERING_WORLD", refreshAll)
PRIO:On("PLAYER_SPECIALIZATION_CHANGED", refreshAll)
PRIO:On("PLAYER_TALENT_UPDATE", refreshAll)
PRIO:On("TRAIT_CONFIG_UPDATED", refreshAll)
PRIO:On("SPELLS_CHANGED", refreshAll)
PRIO:On("COOLDOWN_VIEWER_DATA_LOADED", refreshAll)
-- Rebuild shortly after login too, once the viewer/trait data exists.
PRIO:On("PLAYER_LOGIN", function() C_Timer.After(2, refreshAll) end)
