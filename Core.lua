-- Core.lua ---------------------------------------------------------------------
-- Bootstrap: namespace, saved variables, a tiny event dispatcher, and the update
-- ticker that drives the engine + display.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
_G.PRIO = PRIO

PRIO.name    = ADDON
PRIO.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.1.0"

-- Bump this ONLY when a shipped default PRIORITY LIST changes. On login, users who
-- have customized lists and haven't seen this revision get prompted to reset.
PRIO.defaultsRevision = 21

-- Settings a saved profile captures (everything except the display position).
PRIO.PROFILE_KEYS = {
    "enabled", "locked", "showOOC", "scale", "numQueue", "primarySize", "queueSize",
    "spacing", "growth", "showKeybinds", "showNames", "showGlow", "showTitle",
    "showCooldown", "showFlash", "mode", "useOpener", "showPrecombat",
    "advanceWhileCasting", "enemyDetect", "manageNameplates", "cleaveAt", "aoeAt",
    "combatRate", "idleRate", "minimapShow", "classColor",
    "font", "titleSize", "keybindSize", "nameSize", "showModeButtons",
}

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
    showModeButtons = false,    -- clickable Auto/ST/AoE buttons under the display
    useOpener     = true,       -- play the hardcoded opener at pull
    showPrecombat = true,       -- pre-combat reminders out of combat
    advanceWhileCasting = true, -- while hard-casting, advance the primary to the next GCD
    enemyDetect   = "engaged",  -- engaged (threat/combat/target) | nameplates (all attackable)
    manageNameplates = true,    -- auto-enable enemy nameplates (EnemyCount needs them)
    cleaveAt      = 3,          -- >= this many enemies -> cleave (AoE rotation starts at 3)
    aoeAt         = 4,          -- >= this many enemies -> aoe (Earthquake at 4+)
    aoeThreshold  = {},         -- per-spec AoE-at-N override (by spec key); {} = use spec default
    combatRate    = 0.15,
    idleRate      = 0.5,
    point         = { "CENTER", "CENTER", 0, -180 },
    -- Minimap button
    minimapShow   = true,
    minimapAngle  = 205,
    classColor    = true,       -- tint the UI accent with the player's class color
    -- Fonts (display text)
    font          = "Fonts\\FRIZQT__.TTF",
    titleSize     = 12,
    keybindSize   = 14,
    nameSize      = 11,
    -- Custom priority lists: customPriorities[specKey][mode] = { {spell=id, cond=, off=}, ... }
    -- When present for a spec/mode, it replaces the built-in default entirely.
    customPriorities = {},
    -- Custom openers: customOpeners[specKey] = { st = {"Key",...}, aoe = {...} }. Per-mode;
    -- a legacy flat array is read as the ST opener. Replaces spec.opener / spec.openerAoe.
    customOpeners = {},
    -- Opener gate: openerRequireAll[specKey] = true -> only open when ALL signature
    -- cooldowns are ready (default: any one is enough).
    openerRequireAll = {},
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
    PRIODB.profiles = PRIODB.profiles or {}
    -- First run after this key was added: start "up to date" so we don't prompt on
    -- the very first login; only prompt when the revision actually increases later.
    if PRIODB.defaultsRevisionSeen == nil then PRIODB.defaultsRevisionSeen = PRIO.defaultsRevision end
    PRIO.db = PRIODB
end)

--------------------------------------------------------------------------------
-- Profiles: save/apply/delete named bundles of settings (+ custom priority lists).
--------------------------------------------------------------------------------
function PRIO:SaveProfile(name)
    if not (self.db and name and name:gsub("%s", "") ~= "") then return end
    local p = {}
    for _, k in ipairs(self.PROFILE_KEYS) do p[k] = self.db[k] end
    p.customPriorities = CopyTable(self.db.customPriorities or {})
    p.customOpeners = CopyTable(self.db.customOpeners or {})
    p.openerRequireAll = CopyTable(self.db.openerRequireAll or {})
    self.db.profiles[name] = p
    print("|cff" .. (self.UI and self.UI.accentHex or "0cd29f") .. "PRIO|r: saved profile \"" .. name .. "\".")
end

function PRIO:ApplyProfile(name)
    local p = self.db and self.db.profiles and self.db.profiles[name]
    if not p then return end
    for _, k in ipairs(self.PROFILE_KEYS) do if p[k] ~= nil then self.db[k] = p[k] end end
    if p.customPriorities then self.db.customPriorities = CopyTable(p.customPriorities) end
    if p.customOpeners then self.db.customOpeners = CopyTable(p.customOpeners) end
    if p.openerRequireAll then self.db.openerRequireAll = CopyTable(p.openerRequireAll) end
    if self.UI then self.UI.ApplyAccent() end
    if self.RecolorMinimapButton then self.RecolorMinimapButton() end
    if self.Display and self.Display.Refresh then self.Display:Refresh() end
    if self.UpdateMinimapButton then self.UpdateMinimapButton() end
    if self.Options and self.Options.RefreshOpen then self.Options:RefreshOpen() end
    self:StartTicker()
    print("|cff" .. (self.UI and self.UI.accentHex or "0cd29f") .. "PRIO|r: applied profile \"" .. name .. "\".")
end

function PRIO:DeleteProfile(name)
    if self.db and self.db.profiles then self.db.profiles[name] = nil end
end

--------------------------------------------------------------------------------
-- "Defaults changed" prompt: shown once when a release updates default priorities.
--------------------------------------------------------------------------------
StaticPopupDialogs["PRIO_DEFAULTS_CHANGED"] = {
    text = "|cff0cd29fPRIO|r's default rotation priorities were updated in this release.\n\n"
        .. "Reset your customized priority lists to the new defaults?\n"
        .. "|cffe0a03aThis discards your custom priority edits (settings are kept).|r",
    button1 = "Reset to defaults",
    button2 = "Keep mine",
    OnAccept = function()
        if PRIO.db then
            wipe(PRIO.db.customPriorities)
            if PRIO.Options and PRIO.Options.RefreshOpen then PRIO.Options:RefreshOpen() end
            print("|cff" .. (PRIO.UI and PRIO.UI.accentHex or "0cd29f") .. "PRIO|r: priority lists reset to defaults.")
        end
    end,
    OnCancel = function() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Name-entry popup for saving a profile (a modal edit box handles focus cleanly,
-- unlike an inline one). The edit box accessor differs across client versions, so
-- resolve it defensively.
local function popupEditBox(dialog)
    if not dialog then return nil end
    return dialog.editBox or dialog.EditBox
        or (dialog.GetEditBox and dialog:GetEditBox())
        or (dialog.GetName and dialog:GetName() and _G[dialog:GetName() .. "EditBox"])
end
local function doSaveProfileFrom(dialog)
    local eb = popupEditBox(dialog)
    local n = eb and eb:GetText()
    if n and n:gsub("%s", "") ~= "" then
        PRIO:SaveProfile(n)
        if PRIO.Options and PRIO.Options.RefreshOpen then PRIO.Options:RefreshOpen() end
        return true
    end
    return false
end
StaticPopupDialogs["PRIO_NEW_PROFILE"] = {
    text = "Save current settings + priority lists as a profile named:",
    button1 = "Save", button2 = "Cancel",
    hasEditBox = true, maxLetters = 32,
    OnShow = function(self) local eb = popupEditBox(self); if eb then eb:SetText(""); eb:SetFocus() end end,
    OnAccept = function(self) doSaveProfileFrom(self) end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        doSaveProfileFrom(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function PRIO:MaybePromptDefaults()
    if not self.db then return end
    if (self.db.defaultsRevisionSeen or 0) >= self.defaultsRevision then return end
    local hasCustom = self.db.customPriorities and next(self.db.customPriorities) ~= nil
    self.db.defaultsRevisionSeen = self.defaultsRevision   -- mark seen either way
    if hasCustom then StaticPopup_Show("PRIO_DEFAULTS_CHANGED") end
end

--------------------------------------------------------------------------------
-- Presets: named bundles of display/behavior settings the user can one-click apply
-- (does not touch priority lists, keybinds, or the display position).
--------------------------------------------------------------------------------
PRIO.presets = {
    -- The author's tuned layout: compact strip, left growth, faster polling.
    Recommended = {
        numQueue = 2, primarySize = 50, queueSize = 50, spacing = 5, growth = "LEFT",
        showKeybinds = true, showNames = false, showGlow = false, showTitle = true,
        showCooldown = true, showFlash = true,
        showOOC = true, useOpener = false, showPrecombat = false, advanceWhileCasting = true,
        enemyDetect = "engaged", cleaveAt = 2, aoeAt = 4, combatRate = 0.05, idleRate = 0.1,
        font = "Fonts\\ARIALN.TTF", titleSize = 12, keybindSize = 15, nameSize = 11,
    },
}

function PRIO:ApplyPreset(name)
    local p = self.presets and self.presets[name]
    if not (p and self.db) then return end
    for k, v in pairs(p) do self.db[k] = v end
    if self.Display and self.Display.Refresh then self.Display:Refresh() end
    if self.Options and self.Options.RefreshOpen then self.Options:RefreshOpen() end
    self:StartTicker()
    print("|cff" .. (PRIO.UI and PRIO.UI.accentHex or "0cd29f") .. "PRIO|r: applied the \"" .. name .. "\" preset.")
end

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
        if self.API.PollTalentConfig then self.API.PollTalentConfig() end   -- catch loadout swaps
        -- Out of combat: pre-combat reminders take precedence, then optional rotation.
        local pre = self.Engine:PrecombatResult()
        if pre then self.Display:Render(pre); return end
        -- Arm the opener before the pull so it's shown while out of combat.
        if self.db.useOpener and not self.Engine.openerActive then self.Engine:StartOpener() end
        -- Show the strip out of combat if enabled OR the opener is armed (pre-pull view).
        if not (self.db.showOOC or self.Engine.openerActive) then self.Display:Hide(); return end
    end
    local result = self.Engine:Evaluate()
    self.Display:Render(result)
end

--------------------------------------------------------------------------------
-- One-time tip: how to enable pandemic-window tracking via the Cooldown Manager.
-- Only shown for specs that actually use a pandemic (refreshable) condition.
--------------------------------------------------------------------------------
StaticPopupDialogs["PRIO_PANDEMIC_TIP"] = {
    text = "|cff0cd29fPRIO|r can track DoT |cffffffffpandemic windows|r (e.g. Flame Shock) so it "
        .. "tells you to refresh at the right time, without clipping duration.\n\n"
        .. "To enable it: open |cffffffffEdit Mode \226\134\146 Cooldown Manager|r and turn on the "
        .. "|cffffffffPandemic Time|r alert for that DoT.\n\n"
        .. "This is optional \226\128\148 without it, PRIO still refreshes DoTs when they drop off.",
    button1 = "Got it",
    button2 = "Remind me later",
    OnAccept = function() if PRIO.db then PRIO.db.pandemicTipSeen = true end end,
    OnCancel = function() end,   -- remind me later: leave the flag unset
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function PRIO:MaybeShowPandemicTip()
    if self._pandemicTipTried then return end            -- at most once per session
    if not (self.db and not self.db.pandemicTipSeen) then return end
    local id   = self.API and self.API.GetSpecID and self.API.GetSpecID()
    local spec = id and self.specs and self.specs[id]
    if not (spec and spec.usesPandemic) then return end  -- only pandemic-using specs
    self._pandemicTipTried = true
    StaticPopup_Show("PRIO_PANDEMIC_TIP")
end

--------------------------------------------------------------------------------
-- Lifecycle wiring
--------------------------------------------------------------------------------
PRIO:On("PLAYER_LOGIN", function()
    if PRIO.UI then PRIO.UI.ApplyAccent() end   -- class-color the accent before frames build
    if PRIO.RecolorMinimapButton then PRIO.RecolorMinimapButton() end
end)

PRIO:On("PLAYER_ENTERING_WORLD", function()
    if PRIO.Display then PRIO.Display:EnsureCreated() end
    if PRIO.Engine  then PRIO.Engine:OnSpecChanged() end
    PRIO:StartTicker()
    PRIO:Tick()
    C_Timer.After(4, function()                                    -- after spec data loads
        PRIO:MaybePromptDefaults()
        if PRIO.Setup then PRIO.Setup:MaybeAutoOpen() end
        if PRIO.Changelog then PRIO.Changelog:MaybeAutoOpen() end   -- once per new version
    end)
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
    local raw = msg or ""                      -- keep the raw text for arg parsing
    msg = raw:lower():gsub("%s+", "")
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
    elseif msg == "rotdebug" or msg == "rotation" then
        if PRIO.RotationDebug then PRIO.RotationDebug:Toggle() end
    elseif msg == "stackprobe" then
        -- Diagnose stack-count reads: for each buff in the spec's rotationDebug (else
        -- its auras), dump raw .applications + rendered FontStrings. Run IN COMBAT with
        -- the stacks actually up.
        local API = PRIO.API
        local id = API.GetSpecID()
        local spec = id and PRIO.specs and PRIO.specs[id]
        if not (spec and API.StackProbe) then
            print("|cff0cd29fPRIO|r: no supported spec / probe unavailable.")
            return
        end
        local list = {}
        if spec.rotationDebug and spec.rotationDebug.buffs then
            for _, b in ipairs(spec.rotationDebug.buffs) do
                list[#list + 1] = { b.label or "?", b.spell }
            end
        elseif spec.auras then
            for name, sid in pairs(spec.auras) do list[#list + 1] = { name, sid } end
        end
        print(("|cff0cd29fPRIO|r stack probe (%s):")
            :format(InCombatLockdown() and "|cff0cd29fin combat|r" or "|cffe0a03aOUT of combat|r"))
        for _, b in ipairs(list) do
            print(("|cffffffff%s|r #%s"):format(b[1], tostring(b[2])))
            print(API.StackProbe(b[2]))
        end
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
    elseif msg:match("^myauras") or msg:match("^buffs") or msg:match("^rtb") then
        -- Dump player buffs. Two sections: (1) enumerate all buffs (works OOC only), and
        -- (2) probe specific IDs via GetPlayerAuraBySpellID (a path that can survive
        -- combat). Grab IDs OOC, then test in-combat readability of those IDs.
        --   /prio myauras                -> enumerate only
        --   /prio myauras 193356 193358  -> enumerate + probe those IDs
        --   /prio rtb                    -> probe the candidate Roll the Bones IDs
        local API = PRIO.API
        local probe = {}
        if msg:match("^rtb") then
            -- 12.1 named Roll the Bones stage buffs (One of a Kind / Double Trouble /
            -- Triple Threat) + the tracked RtB bar / Loaded Dice, so one in-combat run
            -- shows which RtB signal is actually readable.
            probe = { 1214933, 1214934, 1214935, 1214909, 256170, 279876, 315496 }
        else
            for d in raw:gmatch("%d+") do probe[#probe + 1] = tonumber(d) end
        end
        print(("|cff0cd29fPRIO|r player buffs (%s):")
            :format(InCombatLockdown() and "|cff0cd29fin combat|r" or "|cffe0a03aOUT of combat - values always readable here|r"))
        print(API.DumpPlayerAuras(probe))
    elseif msg == "setup" then
        if PRIO.Setup then PRIO.Setup:Toggle() end
    elseif msg == "changelog" or msg == "changes" then
        if PRIO.Changelog then PRIO.Changelog:Toggle() end
    elseif msg == "export" then
        if PRIO.Options then PRIO.Options:ExportCurrent() end
    elseif msg == "pandemic" then
        StaticPopup_Show("PRIO_PANDEMIC_TIP")
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
