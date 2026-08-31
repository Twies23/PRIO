-- harness.lua -----------------------------------------------------------------
-- Headless test harness for the PRIO engine. Mocks the WoW + PRIO API, loads the
-- real Engine.lua and Spec_Windwalker.lua, and exposes helpers to set up a game
-- state and assert on condition evaluation, hero detection, and the queue walk.
-- Run via tests/run.py (lupa / Lua 5.x). ADDON_DIR is injected by the runner.
--------------------------------------------------------------------------------

-- Lua 5.1 (WoW) compat shims for the 5.x interpreter lupa bundles.
unpack = unpack or table.unpack

local H = {}
_G.H = H

--------------------------------------------------------------------------------
-- Mutable game state the mock API reads from. reset() restores a clean baseline.
--------------------------------------------------------------------------------
local S
function H.reset()
    S = {
        specID = 269,
        now = 1000,
        enemies = 1,
        haste = 0,
        power = { [12] = 3, [3] = nil },      -- Chi readable (3), Energy secret (nil)
        powerMax = { [12] = 6, [3] = 150 },
        powerPercent = { [3] = nil },          -- Energy % secret too
        known = setmetatable({}, { __index = function() return true end }),  -- spec spells known
        knownStrict = {},                      -- talents/hero (default: not known)
        tracked = {},                          -- Cooldown Manager tracked auras
        auras = {},                            -- IsAuraActive: true/false/nil
        ready = {},                            -- IsReady: default true
        usable = {},                           -- IsUsable: default true
        usableClean = {},                      -- UsableClean: true/false/nil
        insufficientPower = {},                -- InsufficientPower: true/false/nil (default nil)
        chargeState = {},                      -- ChargeState: {max,cur,belowMax}
        talents = {},                          -- IsTalentSelected
        stacks = {},                           -- AuraStackCount
        glows = {},                            -- SpellGlowing (proc overlay)
        stealthed = false,                     -- API.Stealthed
        lastCastKey = nil,
    }
    H.S = S
end
H.reset()

local function truthy(t, id, dflt)
    local v = t[id]
    if v == nil then return dflt end
    return v and true or false
end

--------------------------------------------------------------------------------
-- Mock WoW globals used by Engine.lua at load / runtime.
--------------------------------------------------------------------------------
function GetTime() return S.now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
    local r = {}
    for k, v in pairs(t) do r[k] = type(v) == "table" and CopyTable(v) or v end
    return r
end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function InCombatLockdown() return true end
Enum = { PowerType = { Chi = 12, Energy = 3 } }
C_Spell = {
    GetOverrideSpell = function(id) return nil end,
    GetBaseSpell = function(id) return nil end,
}
C_SpellBook = {}

--------------------------------------------------------------------------------
-- Mock PRIO table + API. Engine.lua does `local API = PRIO.API` at load, so this
-- must exist first. Event handlers are captured so tests can fire a "cast".
--------------------------------------------------------------------------------
local handlers = {}
local PRIO = {}
_G.PRIO = PRIO
PRIO.specs = {}
PRIO.db = { customPriorities = {}, numQueue = 3, advanceWhileCasting = false, mode = "auto" }
function PRIO:On(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end
function PRIO:StartTicker() end
function PRIO:Tick() end
function H.fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end

local API = {}
PRIO.API = API
function API.SafeNum(v) return tonumber(v) end
function API.GetSpecID() return S.specID end
function API.EnemyCount() return S.enemies end
function API.Haste() return S.haste end
function API.Power(pt) return S.power[pt] end
function API.PowerMax(pt) return S.powerMax[pt] end
function API.PowerPercent(pt) return S.powerPercent[pt] end
function API.IsKnown(id) return truthy(S.known, id, true) end
function API.IsKnownStrict(id) return truthy(S.knownStrict, id, false) end
function API.IsTracked(id) return truthy(S.tracked, id, false) end
function API.IsReady(id) return truthy(S.ready, id, true) end
function API.IsUsable(id) return truthy(S.usable, id, true) end
function API.UsableClean(id) local v = S.usableClean[id]; if v == nil then return nil end; return v and true or false end
function API.InsufficientPower(id) local v = S.insufficientPower[id]; if v == nil then return nil end; return v and true or false end
function API.Stealthed() return S.stealthed and true or false end
function API.UsableOrNoPower(id)
    local v = S.usableNoPower and S.usableNoPower[id]
    if v ~= nil then return v and true or false end
    return truthy(S.usable, id, true)   -- default: mirror IsUsable
end
function API.IsTalentSelected(id) return truthy(S.talents, id, false) end
function API.IsTalentSelectedByName() return false end
function API.IsAuraActive(id) return S.auras[id] end   -- true/false/nil
function API.AuraStackCount(id) return S.stacks[id] end
function API.AuraStackSource(id)
    local n = S.stackSource and S.stackSource[id]
    if n ~= nil then return n, "cdm" end          -- simulate a clean CDM read
    return nil, nil
end
function API.SpellGlowing(id) local v = S.glows[id]; if v == nil then return nil end; return v and true or false end
function API.AuraRemaining(id) return nil end          -- secret in "combat"; use predicted
function API.InPandemic(id) return nil end
function API.HasPowerCost(id) return S.powerCost and S.powerCost[id] ~= nil end
function API.PowerCostAmount(id, powerType)
    local pc = S.powerCost and S.powerCost[id]     -- { type = <powerType>, cost = n }
    if not pc then return nil end
    if powerType == nil or pc.type == powerType then return pc.cost end
    return nil
end
function API.HasAura(id) return S.auras[id] == true end
function API.HasMainHandEnchant() return false end
function API.Keybind() return "" end
function API.SpellName(id) return "Spell" .. tostring(id) end
function API.SpellTexture(id) return 0 end
function API.RefreshTracked() end
function API.ChargeState(id)
    local c = S.chargeState[id]
    if not c then return nil end
    -- cleanCur lets a test model combat: ChargeFull's raw count is secret (cur=nil) while
    -- ChargeState still resolves the exact count. Falls back to cur when unset.
    local cc = c.cleanCur; if cc == nil then cc = c.cur end
    return c.max, cc, c.belowMax
end
function API.Charges(id)
    local c = S.chargeState[id]
    if not c then return nil, nil end
    return c.max, c.cur
end
function API.ChargeFull(id)
    local c = S.chargeState[id]
    if not c then return nil, nil, nil end
    return c.max, c.cur, c.recharge
end

--------------------------------------------------------------------------------
-- Load the real engine + spec.
--------------------------------------------------------------------------------
local function load(rel)
    local path = ADDON_DIR .. "\\" .. rel
    local chunk = assert(loadfile(path))
    return chunk("PRIO", PRIO)
end
load("Engine.lua")
load("Spec_Windwalker.lua")
load("Spec_Arms.lua")
load("Spec_Outlaw.lua")
load("Spec_Elemental.lua")
load("Spec_Devourer.lua")
load("Spec_BeastMastery.lua")
load("Spec_Marksmanship.lua")

PRIO.Engine:OnSpecChanged()
H.spec = PRIO.specs[269]
H.armsSpec = PRIO.specs[71]
H.outlawSpec = PRIO.specs[260]
H.eleSpec = PRIO.specs[262]
H.devourerSpec = PRIO.specs[1480]
H.bmSpec = PRIO.specs[253]
H.mmSpec = PRIO.specs[254]
H.Engine = PRIO.Engine
H.Cond = PRIO.Cond
H.API = API
H.db = PRIO.db

-- Re-bind the spec after state changes that affect idToKey/charges.
function H.rebind() PRIO.Engine:OnSpecChanged() end

return H
