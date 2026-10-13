"""Exercise the REAL API.lua against fake Cooldown Manager viewers that reproduce the
in-game failure: Garrote on the target, buff-viewer item stalled inactive, aura timer
showing on the Essential icon, and a UI addon hiding Blizzard's PandemicIcon."""
import os, sys
from lupa import LuaRuntime

ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r"""
NOW = 1000
function GetTime() return NOW end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function issecretvalue(v) return false end
function hooksecurefunc(t, name, hook)
    local orig = t[name]
    t[name] = function(...) local r = orig(...); hook(...); return r end
end
UnitExists = function() return true end
InCombatLockdown = function() return true end
C_Spell = { GetSpellInfo = function(id) return { name = "Spell" .. tostring(id) } end,
            GetSpellCooldown = function() return { isActive = false } end,
            IsSpellUsable = function() return true, false end,
            GetSpellCharges = function() return nil end }
TARGET_AURAS = {}     -- name -> true: "my debuff of this name is on the target"
C_UnitAuras = { GetAuraDataBySpellName = function(unit, name, filter)
    if unit == "target" and filter == "HARMFUL|PLAYER" and TARGET_AURAS[name] then return { name = name } end
    return nil
end }
UnitIsFriend = function() return false end
C_NamePlate = { GetNamePlates = function() return {} end }
Enum = { PowerType = { ComboPoints = 4, Energy = 3 } }

-- cooldownID -> spellID
CDINFO = { [1] = 703, [2] = 703, [3] = 1943, [4] = 999, [5] = 381632, [7] = 457052 }
C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(cdID) return { spellID = CDINFO[cdID] } end,
    GetCooldownViewerCategorySet = function() return {} end,
}

local function mkframe(cdID, active)
    local f = { cooldownID = cdID, _active = active }
    f.IsActive = function(self) return self._active end
    f.IsShown = function() return true end
    f.PandemicIcon = { _shown = false, IsShown = function(self) return self._shown end,
                       Hide = function(self) self._shown = false end }
    f.ShowPandemicStateFrame = function(self) self.PandemicIcon._shown = true end
    f.HidePandemicStateFrame = function(self) self.PandemicIcon._shown = false end
    return f
end
local function pool(frames)
    return { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return frames[i] end
    end }
end

ESS_GARROTE  = mkframe(1, false)   -- Essential ability icon for Garrote
BUFF_GARROTE = mkframe(2, false)   -- Tracked Buff item for Garrote (STALLED inactive)
ESS_RUPTURE  = mkframe(3, false)
ESS_ONLY     = mkframe(4, true)    -- an id that lives ONLY in an ability viewer
BAR_IMPG     = mkframe(5, true)    -- Improved Garrote tracked bar
BUFF_MARK    = mkframe(7, false)   -- Deathstalker's Mark: Tracked Buff ONLY, no ability icon

EssentialCooldownViewer = { itemFramePool = pool({ ESS_GARROTE, ESS_RUPTURE, ESS_ONLY }) }
BuffIconCooldownViewer  = { itemFramePool = pool({ BUFF_GARROTE, BUFF_MARK }) }
BuffBarCooldownViewer   = { itemFramePool = pool({ BAR_IMPG }) }

PRIO = { color = {}, db = {}, On = function() end, specs = {} }
""")
loadfile = lua.eval("function(p) return assert(loadfile(p)) end")
loadfile(os.path.join(ADDON, "API.lua"))("PRIO", lua.globals().PRIO)

fails = lua.execute(r"""
local API = PRIO.API
local fails, n = {}, 0
local function check(name, got, want)
    n = n + 1
    if got ~= want then fails[#fails + 1] = ("%s: expected %s, got %s"):format(name, tostring(want), tostring(got)) end
end
API.RefreshTracked()

-- 1. Nothing up yet.
check("no aura -> Garrote not active", API.IsAuraActive(703), false)
check("no aura -> not in pandemic",    API.InPandemic(703), false)

-- 2. THE SCREENSHOT: Garrote is on the target. Blizzard puts the aura timer on the
--    Essential icon (wasSetFromAura + auraInstanceID); the buff-viewer item is stalled.
ESS_GARROTE.wasSetFromAura = true; ESS_GARROTE.auraInstanceID = 77
check("timer on the Essential icon -> Garrote ACTIVE", API.IsAuraActive(703), true)
check("Rupture untouched", API.IsAuraActive(1943), false)
check("fresh DoT -> not in pandemic", API.InPandemic(703), false)

-- 3. It enters pandemic. Blizzard calls ShowPandemicStateFrame; a UI addon (EllesmereUI,
--    custom glow style) immediately hides Blizzard's PandemicIcon.
ESS_GARROTE:ShowPandemicStateFrame()
ESS_GARROTE.PandemicIcon:Hide()
check("PandemicIcon hidden by the UI addon", ESS_GARROTE.PandemicIcon:IsShown(), false)
check("...but the glow is still read as REFRESH", API.InPandemic(703), true)

-- 4. Refreshed: Blizzard clears the pandemic state.
ESS_GARROTE:HidePandemicStateFrame()
check("refreshed -> hold", API.InPandemic(703), false)

-- 5. Blizzard-default style (icon left visible) still works, even without the hook flag.
ESS_GARROTE.PandemicIcon._shown = true
check("visible PandemicIcon -> REFRESH", API.InPandemic(703), true)
ESS_GARROTE.PandemicIcon._shown = false

-- 6. Aura drops while a stale pandemic flag is still set -> must NOT read refresh.
ESS_GARROTE:ShowPandemicStateFrame(); ESS_GARROTE.PandemicIcon:Hide()
ESS_GARROTE.wasSetFromAura = false; ESS_GARROTE.auraInstanceID = nil
check("aura gone -> not active", API.IsAuraActive(703), false)
check("aura gone -> stale glow flag ignored", API.InPandemic(703), false)
ESS_GARROTE:HidePandemicStateFrame()

-- 7. The buff-viewer item recovers on its own: that alone is enough too.
BUFF_GARROTE._active = true
check("buff viewer IsActive alone -> active", API.IsAuraActive(703), true)
BUFF_GARROTE._active = false

-- 8. Legacy: an id that lives ONLY in an ability viewer keeps its old IsActive() read.
check("ability-viewer-only id keeps legacy read", API.IsAuraActive(999), true)
check("tracked bar reads active", API.IsAuraActive(381632), true)

-- 8b. DEATHSTALKER'S MARK: a target debuff whose ONLY frame is a Tracked Buff item.
check("Mark: item inactive, nothing on target -> missing", API.IsAuraActive(457052), false)
BUFF_MARK._active = true
check("Mark: Tracked Buff item active -> present", API.IsAuraActive(457052), true)
BUFF_MARK._active = false
local MARK = API.SpellName(457052)
TARGET_AURAS[MARK] = true                   -- item STALLED, but my Mark is on the target
check("Mark: stalled item, target read finds it -> present", API.IsAuraActive(457052), true)
TARGET_AURAS[MARK] = nil
check("Mark: gone again -> missing", API.IsAuraActive(457052), false)
-- The backstop only applies to ids that have a Tracked Buff/Bar item; an id that lives
-- only in an ability viewer keeps its own read and is not overridden by a name match.
ESS_ONLY._active = false
TARGET_AURAS[API.SpellName(999)] = true
check("ability-only id is not flipped by a target name match", API.IsAuraActive(999), false)
TARGET_AURAS[API.SpellName(999)] = nil
ESS_ONLY._active = true

-- 9. POOLED FRAMES: the Cooldown Manager re-lays out and hands Garrote's Essential frame
--    to Rupture (and vice versa). No spec change, no manual refresh.
ESS_GARROTE.cooldownID, ESS_RUPTURE.cooldownID = 3, 1
ESS_RUPTURE.wasSetFromAura = true; ESS_RUPTURE.auraInstanceID = 91   -- this frame is Garrote's now
check("after re-layout Garrote follows its NEW frame", API.IsAuraActive(703), true)
check("after re-layout Rupture reads its new frame", API.IsAuraActive(1943), false)

-- 10. Time-based refresh picks up an item that only appears once its aura is up.
CDINFO[6] = 315496
local late = { cooldownID = 6, IsActive = function() return true end, IsShown = function() return true end }
BuffIconCooldownViewer.itemFramePool = { EnumerateActive = function()
    local t, i = { BUFF_GARROTE, late }, 0
    return function() i = i + 1; return t[i] end
end }
NOW = NOW + 2
check("late-acquired buff icon is found without a spec change", API.IsAuraActive(315496), true)

-- 11. The probe runs clean.
local ok, lines = pcall(API.AuraFrameProbe, 703)
check("probe runs", ok, true)
PROBE = ok and table.concat(lines, "\n") or tostring(lines)

return (#fails == 0) and ("ALL " .. n .. " CHECKS PASSED") or (#fails .. " FAILED:\n  " .. table.concat(fails, "\n  "))
""")
print("=== PRIO Cooldown Manager reads (real API.lua): %s ===" % fails)
sys.exit(0 if str(fails).startswith("ALL") else 1)
