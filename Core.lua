-- Core.lua ---------------------------------------------------------------------
-- Bootstrap: namespace, saved variables, a tiny event dispatcher, and the update
-- ticker that drives the engine + display.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
_G.PRIO = PRIO

PRIO.name    = ADDON
PRIO.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.1.0"

-- Colors reused across the UI (EllesmereUI-style accent).
PRIO.color = {
    accent = { 0.047, 0.824, 0.616 },   -- #0CD29D
    gold   = { 1.00, 0.886, 0.294 },    -- keybind
    text   = { 0.79, 0.83, 0.86 },
    faint  = { 0.42, 0.48, 0.53 },
    panel  = { 0.051, 0.071, 0.090 },
}

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
PRIO.defaults = {
    enabled       = true,
    locked        = true,
    showOOC       = false,      -- show the strip when out of combat
    scale         = 1.0,
    numQueue      = 3,          -- icons AFTER the primary
    primarySize   = 64,
    queueSize     = 40,
    spacing       = 10,
    growth        = "RIGHT",    -- RIGHT | LEFT | UP | DOWN
    showKeybinds  = true,
    showNames     = false,
    showGlow      = true,
    showTitle     = true,
    showCooldown  = true,
    showFlash     = true,
    debug         = false,
    mode          = "auto",     -- auto | st | cleave | aoe
    useOpener     = true,       -- play the hardcoded opener at pull
    showPrecombat = true,       -- pre-combat reminders out of combat
    advanceWhileCasting = true, -- while hard-casting, advance the primary to the next GCD
    enemyDetect   = "engaged",  -- engaged (threat/combat/target) | nameplates (all attackable)
    manageNameplates = true,    -- auto-enable enemy nameplates (EnemyCount needs them)
    cleaveAt      = 3,          -- >= this many enemies -> cleave (AoE rotation starts at 3)
    aoeAt         = 4,          -- >= this many enemies -> aoe (Earthquake at 4+)
    combatRate    = 0.15,
    idleRate      = 0.5,
    point         = { "CENTER", "CENTER", 0, -180 },
    -- Minimap button
    minimapShow   = true,
    minimapAngle  = 205,
    -- Fonts (display text)
    font          = "Fonts\\FRIZQT__.TTF",
    titleSize     = 12,
    keybindSize   = 14,
    nameSize      = 11,
    -- Custom priority lists: customPriorities[specKey][mode] = { {spell=id, cond=, off=}, ... }
    -- When present for a spec/mode, it replaces the built-in default entirely.
    customPriorities = {},
}

--------------------------------------------------------------------------------
-- Tiny event dispatcher
--------------------------------------------------------------------------------
local handlers = {}   -- event -> { fn, fn, ... }
local frame = CreateFrame("Frame", "PRIOEventFrame", UIParent)

function PRIO:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    handlers[event][#handlers[event] + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end)

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------
local function DeepFill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepFill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

PRIO:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    PRIODB = PRIODB or {}
    DeepFill(PRIODB, PRIO.defaults)
    PRIO.db = PRIODB
end)

--------------------------------------------------------------------------------
-- Ticker
--------------------------------------------------------------------------------
local ticker
function PRIO:StartTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    if not (self.db and self.db.enabled) then return end
    local rate = InCombatLockdown() and self.db.combatRate or self.db.idleRate
    ticker = C_Timer.NewTicker(rate, function() PRIO:Tick() end)
end

function PRIO:Tick()
    if not (self.db and self.db.enabled and self.Display and self.Engine) then return end
    if not self.API.IsActiveSpec() then
        self.Display:Hide()
        return
    end
    local inCombat = InCombatLockdown()
    if not inCombat then
        -- Out of combat: pre-combat reminders take precedence, then optional rotation.
        local pre = self.Engine:PrecombatResult()
        if pre then self.Display:Render(pre); return end
        if not self.db.showOOC then self.Display:Hide(); return end
    end
    local result = self.Engine:Evaluate()
    self.Display:Render(result)
end

--------------------------------------------------------------------------------
-- Lifecycle wiring
--------------------------------------------------------------------------------
PRIO:On("PLAYER_ENTERING_WORLD", function()
    if PRIO.Display then PRIO.Display:EnsureCreated() end
    if PRIO.Engine  then PRIO.Engine:OnSpecChanged() end
    PRIO:StartTicker()
    PRIO:Tick()
end)

PRIO:On("PLAYER_REGEN_DISABLED", function() PRIO:StartTicker() end)   -- entered combat
PRIO:On("PLAYER_REGEN_ENABLED",  function() PRIO:StartTicker() end)   -- left combat
PRIO:On("PLAYER_SPECIALIZATION_CHANGED", function()
    if PRIO.Engine then PRIO.Engine:OnSpecChanged() end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------
SLASH_PRIO1 = "/prio"
SlashCmdList.PRIO = function(msg)
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "lock" then
        PRIO.db.locked = true;  if PRIO.Display then PRIO.Display:ApplyLock() end
        print("|cff0cd29fPRIO|r: locked.")
    elseif msg == "unlock" then
        PRIO.db.locked = false; if PRIO.Display then PRIO.Display:ApplyLock() end
        print("|cff0cd29fPRIO|r: unlocked — drag to move.")
    elseif msg == "toggle" then
        PRIO.db.enabled = not PRIO.db.enabled
        PRIO:StartTicker(); PRIO:Tick()
        print("|cff0cd29fPRIO|r: " .. (PRIO.db.enabled and "enabled" or "disabled") .. ".")
    elseif msg == "debug" then
        if PRIO.Debug then PRIO.Debug:Toggle() end
    elseif msg == "spells" then
        local API = PRIO.API
        local id = API.GetSpecID()
        local spec = id and PRIO.specs and PRIO.specs[id]
        if not spec then
            print("|cff0cd29fPRIO|r: no supported spec active.")
            return
        end
        print("|cff0cd29fPRIO|r spell check for |cffffffff" .. spec.label .. "|r (verify names match; red = unknown ID):")
        local keys = spec.pickable or {}
        for _, key in ipairs(keys) do
            local sid = spec.spells[key]
            local known = sid and API.IsKnown(sid)
            local name = sid and API.SpellName(sid) or "?"
            local tracked = sid and API.IsTracked(sid)
            print(string.format("  |cffbbbbbb%s|r  #%s  |cff%s%s|r  %s%s",
                key, tostring(sid),
                known and "0cd29f" or "e0685a", name,
                known and "" or "|cffe0685a[UNKNOWN]|r",
                tracked and "  |cff6fb3ff[tracked]|r" or ""))
        end
    elseif msg == "tracked" or msg == "auras" then
        -- The Cooldown Viewer is the runtime lookup for both cooldown AND aura IDs.
        -- TrackedBuff/TrackedBar categories are the buff/DoT (aura) spell IDs.
        local API = PRIO.API
        if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
            print("|cff0cd29fPRIO|r: Cooldown Viewer API unavailable.")
            return
        end
        local CATS = {
            [0] = "Essential", [1] = "Utility", [2] = "TrackedBuff", [3] = "TrackedBar",
            [4] = "GroupBuff", [5] = "SpecEssential", [6] = "SpecTracked",
            [7] = "EquipEssential", [8] = "EquipTracked",
        }
        print("|cff0cd29fPRIO|r Cooldown Viewer contents (aura IDs live under TrackedBuff / TrackedBar):")
        for cat = 0, 8 do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
            if ok and type(ids) == "table" and #ids > 0 then
                print("|cff6fb3ff" .. (CATS[cat] or ("cat " .. cat)) .. "|r:")
                for _, cdID in ipairs(ids) do
                    local infoOk, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if infoOk and type(info) == "table" and info.spellID then
                        print(string.format("   #%s  %s", tostring(info.spellID), API.SpellName(info.spellID)))
                    end
                end
            end
        end
    elseif msg == "power" then
        -- Validate which class resources read clean vs. secret. Run IN COMBAT on the
        -- class you care about -- everything is readable out of combat.
        local API = PRIO.API
        local E = Enum and Enum.PowerType or {}
        local LIST = {
            { "Mana", E.Mana or 0 }, { "Rage", E.Rage or 1 }, { "Focus", E.Focus or 2 },
            { "Energy", E.Energy or 3 }, { "ComboPoints", E.ComboPoints or 4 },
            { "Runes", E.Runes or 5 }, { "RunicPower", E.RunicPower or 6 },
            { "SoulShards", E.SoulShards or 7 }, { "AstralPower", E.LunarPower or 8 },
            { "HolyPower", E.HolyPower or 9 }, { "Maelstrom", E.Maelstrom or 11 },
            { "Chi", E.Chi or 12 }, { "Insanity", E.Insanity or 13 },
            { "ArcaneCharges", E.ArcaneCharges or 16 }, { "Fury", E.Fury or 17 },
            { "Pain", E.Pain or 18 }, { "Essence", E.Essence or 19 },
        }
        print(("|cff0cd29fPRIO|r power readability (%s):")
            :format(InCombatLockdown() and "|cff0cd29fin combat|r" or "|cffe0a03aOUT of combat - values are always readable here|r"))
        for _, p in ipairs(LIST) do
            local ok, v = pcall(UnitPower, "player", p[2])
            local mx = select(2, pcall(UnitPowerMax, "player", p[2]))
            local secret = ok and API.IsSecret(v)
            local maxN = (not API.IsSecret(mx)) and tonumber(mx) or nil
            if maxN and maxN > 0 then                       -- only classes-relevant resources
                local shown = secret and "|cffe0685aSECRET|r"
                    or ("|cff0cd29f" .. tostring(tonumber(v) or "?") .. "|r / " .. maxN)
                print(string.format("   %-14s %s", p[1], shown))
            end
        end
        print("|cff5a6a76(only resources your class has a max for are shown)|r")
    else
        if PRIO.Options then PRIO.Options:Toggle() end
    end
end
