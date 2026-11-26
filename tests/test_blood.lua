-- test_blood.lua --------------------------------------------------------------
-- Blood Death Knight (250). San'layn = the user's tuned list (ST and AoE share it); the
-- shared machinery (confirmed Bone Shield rows, read-only RP gate, rune cap / pooling, rune
-- look-ahead) is exercised on the DEATHBRINGER list, which still carries those rows.
--------------------------------------------------------------------------------

local HS, VS, MR, BB, DND, DRW, DS, DC = 206930, 433895, 195182, 50842, 43265, 49028, 49998, 195292
local CONSUMPTION, REAPERSMARK, VB = 1263824, 439843, 55233
local BONESHIELD, DND_BUFF, DRW_BUFF, CRIMSON = 195181, 188290, 81256, 81141
local RP = 6
local OSSUARY = 219788

-- Steady state mid-fight (San'layn): Bone Shield + Ossuary up, standing in DnD, DRW / VB /
-- DnD / Blood Boil all on cooldown, no procs, Death Strike unaffordable. Expected primary:
-- Heart Strike.
local function blood()
    H.reset()
    H.S.specID = 250
    H.S.enemies = 1
    H.S.power[RP] = nil                     -- Runic Power: secret in combat
    H.S.powerMax[RP] = 125
    H.S.known[CONSUMPTION] = false          -- not in the user's build
    H.S.tracked[BONESHIELD] = true; H.S.auras[BONESHIELD] = true; H.S.stacks[BONESHIELD] = 8
    H.S.tracked[OSSUARY] = true;    H.S.auras[OSSUARY] = true    -- 5+ Bone Shield
    H.S.tracked[DND_BUFF] = true;   H.S.auras[DND_BUFF] = true
    H.S.tracked[DRW_BUFF] = true;   H.S.auras[DRW_BUFF] = false
    H.S.tracked[CRIMSON] = true;    H.S.auras[CRIMSON] = false
    H.S.ready[DRW] = false
    H.S.ready[VB] = false
    H.S.tracked[VB] = true;         H.S.auras[VB] = false
    H.S.chargeState[BB] = { max = 2, cur = 0, belowMax = true }; H.S.ready[BB] = false
    H.S.ready[DND] = false
    H.S.insufficientPower[DS] = true
    -- Vampiric Strike (433895) only exists while the proc / Gift is up: in-game it reads
    -- "on CD / unusable" otherwise, which is what gates the user's Ossuary-only VS row.
    H.S.ready[VS] = false; H.S.usable[VS] = false
    H.rebind()
    H.Engine.openerActive = false
    H.Engine.P.maelstrom = 0
    H.db.numQueue = 2
end

-- Same steady state on the DEATHBRINGER list (Reaper's Mark known, on cooldown).
local function dbr()
    blood()
    H.S.knownStrict[REAPERSMARK] = true
    H.S.ready[REAPERSMARK] = false
    H.rebind()
    H.Engine.openerActive = false
    H.Engine.P.maelstrom = 0
end

local function primary() local r = H.Engine:Evaluate(); return r.primary and r.primary.id end

test("Blood spec registered under 250, San'layn by default", function()
    truthy(H.bloodSpec, "Blood spec should be registered")
    eq(H.bloodSpec.className, "Death Knight")
    eq(H.bloodSpec.resource, RP, "resource is Runic Power (6)")
    H.reset(); H.S.specID = 250; H.rebind()
    eq(H.bloodSpec.activeHero(), "sanlayn", "no Reaper's Mark -> San'layn")
    truthy(H.bloodSpec.priority.st[1], "ST list resolves")
end)

test("every Blood priority row names a spell in spec.spells (both heroes)", function()
    for hero, lists in pairs(H.bloodSpec.priorityByVariant) do
        for mode, list in pairs(lists) do
            for i, row in ipairs(list) do
                truthy(H.bloodSpec.spells[row.spell],
                    ("%s.%s[%d]: '%s' must be a spec spell"):format(hero, mode, i, tostring(row.spell)))
            end
        end
    end
end)

test("steady state: Heart Strike is the filler", function()
    blood()
    eq(primary(), HS, "nothing urgent -> Heart Strike")
end)

test("San'layn: Bone Shield gone (Ossuary gone with it) -> Marrowrend", function()
    blood()
    H.S.auras[BONESHIELD] = false; H.S.auras[OSSUARY] = false
    eq(primary(), MR, "rebuild Bone Shield first")
end)

test("San'layn: one tuned list serves both ST and AoE", function()
    local s = H.bloodSpec.priorityByVariant.sanlayn
    truthy(s.st == s.aoe, "same list")
    eq(#s.st, 14, "the user's 14 rows")
    eq(H.bloodSpec.defaultsRevision, 2, "Blood defaults revision bumped for the new list")
end)

test("San'layn: Death Strike whenever affordable (above the fillers)", function()
    blood()
    H.S.insufficientPower[DS] = false
    eq(primary(), DS, "row 9: spend RP as soon as the game says it's affordable")
end)

test("San'layn: DRW + Crimson Scourge + Ossuary -> free Death and Decay", function()
    blood()
    H.S.auras[DRW_BUFF] = true; H.S.auras[CRIMSON] = true; H.S.ready[DND] = true
    eq(primary(), DND, "row 4")
    H.S.auras[OSSUARY] = false
    eq(primary(), MR, "below 5 Bone Shield: Marrowrend (row 3) comes first")
end)

test("REGRESSION (over-recommend): a fake stack count of 1 with Ossuary up -> no Marrowrend", function()
    blood()
    H.S.stacks[BONESHIELD] = 1              -- in-game: "x1 assumed", not a real count
    eq(primary(), HS, "the stack number must not drive Marrowrend; Ossuary says 5+")
end)

test("REGRESSION (over-recommend): Bone Shield bar UNREADABLE -> no Marrowrend (Deathbringer rows)", function()
    dbr()
    H.S.auras[BONESHIELD] = nil             -- tracked bar briefly reads nothing
    eq(primary(), HS, "only a clean 'absent' rebuilds Bone Shield")
end)

test("Bone Shield untracked -> the confirmed-missing line never fires (Deathbringer rows)", function()
    dbr()
    H.S.tracked[BONESHIELD] = false; H.S.auras[BONESHIELD] = nil
    eq(primary(), HS, "strict: can't confirm absence -> no Marrowrend")
end)

test("Bone Shield up but stack count UNREADABLE -> no Marrowrend spam", function()
    blood()
    H.S.stacks[BONESHIELD] = nil            -- secret count: reads as nothing
    eq(primary(), HS, "unreadable count must not satisfy the <= 4 line")
end)

test("Ossuary drops (Bone Shield < 5), count unreadable -> Marrowrend", function()
    blood()
    H.S.stacks[BONESHIELD] = nil            -- the number itself is secret...
    H.S.auras[OSSUARY] = false              -- ...but Ossuary going away says "below 5"
    eq(primary(), MR, "Ossuary is the clean below-5 signal")
end)

test("Ossuary UNREADABLE + count unreadable -> no Marrowrend spam (Deathbringer rows)", function()
    dbr()
    H.S.stacks[BONESHIELD] = nil
    H.S.tracked[OSSUARY] = false; H.S.auras[OSSUARY] = nil
    eq(primary(), HS, "strict missing: an untracked Ossuary never fires")
end)

test("predicted Bone Shield about to expire -> Marrowrend refresh (Deathbringer rows)", function()
    dbr()
    H.Engine.P.auraExpire = { [BONESHIELD] = H.S.now + 4 }
    eq(primary(), MR, "refresh with <= 5s left on the cast-seeded timer")
end)

test("RP READ via percent >= 75 -> Death Strike before anything else (Deathbringer rows)", function()
    dbr()
    H.S.auras[BONESHIELD] = false           -- even over a missing Bone Shield
    H.S.powerPercent[RP] = 64               -- 64% of 125 = 80 RP, a real read
    H.S.insufficientPower[DS] = false       -- ...so Death Strike is affordable
    eq(primary(), DS, "anti-cap Death Strike is row 1")
    eq(H.Engine.P.maelstrom, 80, "percent x max is the engine's RP")
    eq(H.Engine.P.resourceSource, "percent")
end)

test("RP NOT readable: an estimated 80 never fires the anti-cap (fails closed, Deathbringer rows)", function()
    dbr()
    H.S.powerPercent[RP] = nil              -- secret
    H.Engine.P.maelstrom = 80               -- cast-based estimate only
    eq(primary(), HS, "no Death Strike on a guess")
end)

test("RP anchors: Death Strike unaffordable clamps the estimate below its cost", function()
    blood()
    H.Engine.P.maelstrom = 90
    H.S.insufficientPower[DS] = true        -- clean flag: can't afford 40
    H.Engine:Evaluate()
    eq(H.Engine.P.maelstrom, 39, "estimate pulled under the cost")
    eq(H.Engine.P.resourceSource, "anchored")
end)

test("RP anchors: Death Strike affordable lifts the estimate to at least its cost", function()
    blood()
    H.Engine.P.maelstrom = 10
    H.S.insufficientPower[DS] = false
    H.Engine:Evaluate()
    eq(H.Engine.P.maelstrom, 40, "estimate raised to the cost")
end)

test("Vampiric Strike (Heart Strike overridden) beats Heart Strike", function()
    blood()
    H.S.overrides = { [HS] = VS }; H.S.ready[VS] = true; H.S.usable[VS] = true
    eq(primary(), VS, "Vampiric Strike when the proc is up")
end)

test("Crimson Scourge glow -> free Death and Decay (Deathbringer rows)", function()
    dbr()
    H.S.ready[DND] = true
    H.S.glows[DND] = true
    eq(primary(), DND, "free DnD proc")
end)

test("left Death and Decay -> recast it (maintenance buff, Deathbringer rows)", function()
    dbr()
    H.S.ready[DND] = true
    H.S.auras[DND_BUFF] = false
    eq(primary(), DND, "stand back in DnD")
end)

test("San'layn: any Blood Boil charge goes before Heart Strike", function()
    blood()
    H.S.chargeState[BB] = { max = 2, cur = 1, belowMax = true }; H.S.ready[BB] = true
    eq(primary(), BB, "row 13 above row 14")
end)

test("Dancing Rune Weapon fires when ready", function()
    blood()
    H.S.ready[DRW] = true
    eq(primary(), DRW, "DRW on cooldown")
end)

test("San'layn: Vampiric Blood fires on cooldown (Gift of the San'layn window)", function()
    blood()
    H.S.ready[VB] = true
    eq(primary(), VB, "VB is a damage cooldown on San'layn")
end)

test("San'layn: Vampiric Blood not re-suggested while it's running", function()
    blood()
    H.S.ready[VB] = true; H.S.auras[VB] = true
    truthy(primary() ~= VB, "no VB while the buff is up")
end)

test("San'layn: Vampiric Blood sits below the Bone Shield rebuild", function()
    blood()
    H.S.ready[VB] = true; H.S.auras[OSSUARY] = false
    eq(primary(), MR, "Bone Shield first, then VB")
end)

test("Deathbringer: Vampiric Blood stays the player's (not in the list)", function()
    blood()
    H.S.knownStrict[REAPERSMARK] = true
    H.S.ready[REAPERSMARK] = false
    H.S.ready[VB] = true
    H.rebind(); H.Engine.openerActive = false; H.Engine.P.maelstrom = 0
    local r = H.Engine:Evaluate()
    truthy(r.primary and r.primary.id ~= VB, "no VB primary on Deathbringer")
    for _, e in ipairs(r.queue or {}) do truthy(e.id ~= VB, "no VB queued on Deathbringer") end
end)

test("rune-starved with no Blood Boil -> Death Strike dump", function()
    blood()
    H.S.usable[HS] = false; H.S.usable[MR] = false; H.S.usable[DND] = false
    H.S.chargeState[BB] = { max = 2, cur = 0, belowMax = true }
    H.S.ready[BB] = false
    H.S.insufficientPower[DS] = false       -- the game says Death Strike is affordable
    eq(primary(), DS, "nothing else castable -> Death Strike")
end)

test("Death Strike withheld when the game says it's unaffordable", function()
    blood()
    H.S.usable[HS] = false; H.S.usable[MR] = false; H.S.usable[DND] = false
    H.S.chargeState[BB] = { max = 2, cur = 0, belowMax = true }
    H.S.ready[BB] = false
    H.S.insufficientPower[DS] = true
    -- Nothing qualifies, so the never-blank safety net shows the first known row as a
    -- PLACEHOLDER -- which must carry the dim flag, never read as a castable "press now".
    local r = H.Engine:Evaluate()
    if r.primary and r.primary.id == DS then
        truthy(r.primary.noResource, "an unaffordable Death Strike may only appear dimmed")
    end
end)

test("RP model: Heart Strike +10, Marrowrend +20, Death Strike -40", function()
    blood()
    H.S.known[221536] = false; H.S.talents[221536] = false   -- no Heartbreaker
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, HS)
    eq(H.Engine.P.maelstrom, 10, "Heart Strike +10")
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, MR)
    eq(H.Engine.P.maelstrom, 30, "Marrowrend +20")
    H.Engine.P.maelstrom = 60
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, DS)
    eq(H.Engine.P.maelstrom, 20, "Death Strike -40")
end)

test("RP model: Heartbreaker adds 2 RP per target hit by Heart Strike (cap 5)", function()
    blood()
    H.S.known[221536] = true
    H.S.enemies = 3
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, HS)
    eq(H.Engine.P.maelstrom, 16, "10 + 2x3")
    H.Engine.P.maelstrom = 0
    H.S.enemies = 8
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, HS)
    eq(H.Engine.P.maelstrom, 20, "10 + 2x5 (capped)")
end)

test("runes condition reads the count and fails closed when secret", function()
    blood()
    H.S.runes = 3; H.rebind()
    truthy(evalClause({ type = "runesMin", v = 2 }), "3 runes >= 2")
    falsy(evalClause({ type = "runesMax", v = 2 }), "3 runes not <= 2")
    -- Raw secret: the spell probes still answer (both spenders ready -> at least 2).
    H.S.runes = nil
    truthy(evalClause({ type = "runesMin", v = 2 }), "probes: Marrowrend ready -> 2+")
    falsy(evalClause({ type = "runesMin", v = 3 }), "probes alone can't claim 3")
end)

test("rune probes: 0 / 1 / 2+ from Heart Strike + Marrowrend readiness", function()
    blood(); H.S.runes = nil
    H.S.ready[HS] = false; H.S.ready[MR] = false
    eq(H.Engine:RuneCount(), 0, "neither spender ready -> 0")
    H.S.ready[HS] = true
    eq(H.Engine:RuneCount(), 1, "1-rune spender only -> exactly 1")
    H.S.ready[MR] = true
    eq(H.Engine:RuneCount(), 2, "2-rune spender ready -> 2 (at least)")
end)

test("runes: a direct read that said 6 at 0 runes is caught and dropped", function()
    blood()
    H.S.runes = 6                           -- UnitPower: 6/6...
    H.S.ready[HS] = false; H.S.ready[MR] = false   -- ...with every spender down
    eq(H.Engine:RuneCount(), 0, "probes win: 0 runes")
    H.S.now = H.S.now + 0.6                 -- disagreement persists past the grace
    eq(H.Engine:RuneCount(), 0)
    truthy(H.Engine.P.runeLied.power, "power read flagged as lying")
    H.S.ready[HS] = true; H.S.ready[MR] = true
    local n, src = H.Engine:RuneCount()
    eq(n, 2, "lying read stays dropped -> probe floor 2")
    eq(src, "probes")
end)

test("runes: per-rune cooldown read is used when UnitPower lies", function()
    blood()
    H.S.runes = 6; H.S.runesCd = 0
    H.S.ready[HS] = false; H.S.ready[MR] = false
    local n, src = H.Engine:RuneCount()
    eq(n, 0); eq(src, "cooldowns", "the honest per-rune read answers")
    falsy(H.Engine.P.runeLied.cooldowns, "cooldowns read not flagged")
    H.S.ready[HS] = true; H.S.ready[MR] = true; H.S.runesCd = 5
    n, src = H.Engine:RuneCount()
    eq(n, 5, "exact count from the direct read"); eq(src, "cooldowns")
end)

test("runes: a one-frame blip (rune lands, spell CD catches up) is NOT a lie", function()
    blood()
    H.S.runesCd = 1
    H.S.ready[HS] = false; H.S.ready[MR] = false   -- spell CD still says 0 for a moment
    H.Engine:RuneCount()
    H.S.now = H.S.now + 0.2
    H.S.ready[HS] = true                    -- caught up: 1 = 1
    local n, src = H.Engine:RuneCount()
    eq(n, 1); eq(src, "cooldowns", "honest read kept")
    falsy(H.Engine.P.runeLied.cooldowns, "blip under the grace isn't flagged")
end)

test("runes: a flagged read is trusted again after 3s of agreeing", function()
    blood()
    H.S.runesCd = 3
    H.S.ready[HS] = false; H.S.ready[MR] = false
    H.Engine:RuneCount(); H.S.now = H.S.now + 0.6; H.Engine:RuneCount()
    truthy(H.Engine.P.runeLied.cooldowns, "flagged")
    H.S.ready[HS] = true; H.S.ready[MR] = true   -- now agrees (3 >= 2+)
    H.Engine:RuneCount()
    H.S.now = H.S.now + 3
    local n, src = H.Engine:RuneCount()
    eq(n, 3); eq(src, "cooldowns", "forgiven after 3s of agreement")
end)

test("look-ahead uses real recharge timers: a rune landing in 1s funds the next Heart Strike", function()
    dbr()
    H.db.numQueue = 2
    H.S.auras[OSSUARY] = false              -- Marrowrend first (spends both runes)
    H.S.runesCd = 2
    H.S.runeRecharge = { 1.0, 7.0 }         -- one rune back within the next GCD
    H.Engine.P.maelstrom = 30
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, MR)
    eq(r.queue[1] and r.queue[1].id, HS, "the rune landing at 1.0s pays for Heart Strike")
end)

test("look-ahead with real timers: nothing landing -> no Heart Strike next", function()
    dbr()
    H.db.numQueue = 2
    H.S.auras[OSSUARY] = false
    H.S.runesCd = 2
    H.S.runeRecharge = { 4.0, 7.0 }         -- nothing back within the GCD
    H.Engine.P.maelstrom = 30
    local r = H.Engine:Evaluate()
    eq(r.queue[1] and r.queue[1].id, DS, "out of runes -> Death Strike")
end)

test("runes: an honest direct read is the count, exactly like combo points", function()
    blood(); H.S.runes = 4
    local n, src = H.Engine:RuneCount()
    eq(n, 4); eq(src, "power")
    H.S.ready[HS] = true; H.S.ready[MR] = false; H.S.runes = 1
    n, src = H.Engine:RuneCount()
    eq(n, 1, "agrees with the probes at 1 -> still trusted"); eq(src, "power")
end)

test("0 runes in combat: no rune spender is the primary", function()
    blood()
    H.S.runes = 6
    for _, id in ipairs({ HS, MR, DND, DC, VS }) do H.S.ready[id] = false; H.S.usable[id] = false end
    H.S.insufficientPower[DS] = false
    local p = primary()
    truthy(p ~= HS and p ~= MR and p ~= DND, "rune-starved -> no rune spender up front")
end)

test("look-ahead spends runes: Marrowrend on 2 runes isn't followed by a Heart Strike", function()
    dbr()
    H.db.numQueue = 2
    H.S.auras[OSSUARY] = false              -- Marrowrend is the primary
    H.S.runes = 2
    H.Engine.P.maelstrom = 30               -- Marrowrend +20 -> 50: Death Strike affordable next
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, MR, "Marrowrend now")
    eq(r.queue[1] and r.queue[1].id, DS, "out of runes after it -> Death Strike, not Heart Strike")
end)

test("look-ahead with runes to spare keeps Heart Strike next", function()
    dbr()
    H.db.numQueue = 2
    H.S.auras[OSSUARY] = false
    H.S.runes = 5
    H.Engine.P.maelstrom = 30
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, MR)
    eq(r.queue[1] and r.queue[1].id, HS, "3 runes left -> Heart Strike")
end)

test("cooldowns: DRW 90s, Reaper's Mark 45s / 30s with Reaper's Onslaught", function()
    blood(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, DRW)
    eq(H.Engine.P.cdExpire[DRW], 1090, "DRW 90s")
    blood(); H.S.known[469870] = false; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, REAPERSMARK)
    eq(H.Engine.P.cdExpire[REAPERSMARK], 1045, "Reaper's Mark 45s")
    blood(); H.S.known[469870] = true; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, REAPERSMARK)
    eq(H.Engine.P.cdExpire[REAPERSMARK], 1030, "Reaper's Onslaught -15s")
end)

test("Red Thirst: each Death Strike takes 8s off the predicted Vampiric Blood timer", function()
    blood(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, VB)
    eq(H.Engine.P.cdExpire[VB], 1090, "VB 90s base")
    H.Engine.P.maelstrom = 100
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, DS)
    eq(H.Engine.P.cdExpire[VB], 1082, "40 RP spent -> -8s")
    -- Without Red Thirst nothing moves.
    blood(); H.S.known[205723] = false; H.S.talents[205723] = false; H.rebind(); H.S.now = 1000
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, VB)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, DS)
    eq(H.Engine.P.cdExpire[VB], 1090, "no Red Thirst -> unchanged")
end)

test("Marrowrend seeds the predicted 30s Bone Shield timer", function()
    blood()
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, MR)
    eq(H.Engine.P.auraExpire[BONESHIELD], H.S.now + 30, "Bone Shield 30s from Marrowrend")
end)

test("Deathbringer: Reaper's Mark known -> Deathbringer list, Reaper's Mark on cooldown", function()
    blood()
    H.S.knownStrict[REAPERSMARK] = true
    H.rebind(); H.Engine.openerActive = false; H.Engine.P.maelstrom = 0
    eq(H.bloodSpec.activeHero(), "deathbringer")
    eq(primary(), REAPERSMARK, "Reaper's Mark when ready")
end)

test("rune probe reads through the override: Gift up, 1 rune -> per-rune read not branded a liar", function()
    blood()
    H.S.overrides = { [HS] = VS }           -- Heart Strike button is Vampiric Strike
    H.S.ready[HS] = false                   -- base Heart Strike reads "on cooldown"...
    H.S.ready[VS] = true                    -- ...but the active Vampiric Strike is castable
    H.S.ready[MR] = false
    H.S.runesCd = 1
    H.Engine:RuneCount(); H.S.now = H.S.now + 1
    local n, src = H.Engine:RuneCount()
    eq(n, 1); eq(src, "cooldowns", "honest per-rune read kept during Gift")
    falsy(H.Engine.P.runeLied.cooldowns, "not flagged")
end)

--------------------------------------------------------------------------------
-- List refactor: ST + AoE only (DRW rows gated inside San'layn), rune rows, pruned rows.
--------------------------------------------------------------------------------
test("just ST and AoE: no DRW phase lists or tabs", function()
    eq(#H.bloodSpec.modes, 2, "two editor tabs")
    falsy(H.bloodSpec.phaseMode, "no DRW phase swap")
    for hero, lists in pairs(H.bloodSpec.priorityByVariant) do
        local n = 0
        for _ in pairs(lists) do n = n + 1 end
        eq(n, 2, hero .. ": st + aoe only")
    end
end)

test("DRW-gated rows exist only on San'layn", function()
    local function drwRows(lst)
        local n = 0
        for _, row in ipairs(lst) do
            local found = false
            local function walk(x) if type(x) ~= "table" then return end
                if x.spell == DRW_BUFF then found = true end
                for _, v in ipairs(x.clauses or {}) do walk(v) end end
            walk(row.cond)
            if found then n = n + 1 end
        end
        return n
    end
    truthy(drwRows(H.bloodSpec.priorityByVariant.sanlayn.st) > 0, "San'layn ST has DRW rows")
    eq(drwRows(H.bloodSpec.priorityByVariant.deathbringer.st), 0, "Deathbringer has none")
end)

test("San'layn defaults are pruned: no Consumption / Blood Debt rows", function()
    for mode, lst in pairs(H.bloodSpec.priorityByVariant.sanlayn) do
        for i, row in ipairs(lst) do
            truthy(row.spell ~= "Consumption", ("%s[%d] is Consumption"):format(mode, i))
            local c = row.cond
            local ids = {}
            local function walk(x) if type(x) ~= "table" then return end
                if x.spell then ids[x.spell] = true end
                for _, v in ipairs(x.clauses or {}) do walk(v) end end
            walk(c)
            falsy(ids[1310372], ("%s[%d] gates on Blood Debt"):format(mode, i))
        end
    end
end)

test("DRW up, just pressed: one Blood Boil on entry (same ST list)", function()
    blood()
    H.S.chargeState[BB] = { max = 2, cur = 2, belowMax = false }; H.S.ready[BB] = true
    H.S.auras[DRW_BUFF] = true
    H.Engine.P.lastCast = DRW; H.Engine.P.lastCastKey = "DancingRuneWeapon"
    local r = H.Engine:Evaluate()
    eq(r.debug.mode, "st", "no phase swap")
    eq(r.primary and r.primary.id, BB, "one Blood Boil on DRW entry")
end)

test("inside DRW, Blood Boil is the filler ahead of Heart Strike", function()
    blood()
    H.S.chargeState[BB] = { max = 2, cur = 1, belowMax = true }; H.S.ready[BB] = true
    H.S.auras[DRW_BUFF] = true             -- 1 charge, not just-cast DRW
    eq(primary(), BB, "Blood Boil filler in DRW")
end)

test("San'layn: Vampiric Strike / DnD / Heart Strike all wait for Ossuary", function()
    blood()
    H.S.overrides = { [HS] = VS }; H.S.ready[VS] = true; H.S.usable[VS] = true
    H.S.ready[DND] = true
    H.S.auras[OSSUARY] = false
    H.S.usable[MR] = false                  -- can't pay Marrowrend yet
    local p = primary()
    truthy(p ~= VS and p ~= DND and p ~= HS, "runes are saved for Bone Shield")
end)

test("rune cap (Deathbringer rows): 5+ runes -> Heart Strike ahead of the Blood Boil filler", function()
    dbr()
    H.S.chargeState[BB] = { max = 2, cur = 1, belowMax = true }; H.S.ready[BB] = true
    H.S.runesCd = 5
    eq(primary(), HS, "idle rune regen is the bigger waste")
    H.S.runesCd = 3
    eq(primary(), BB, "under the rune cap, Blood Boil filler first")
end)

test("Heart Strike pools for Marrowrend: Bone Shield below 5 on 1 rune -> no Heart Strike", function()
    blood()
    H.S.auras[OSSUARY] = false             -- below 5
    H.S.runesCd = 1
    H.S.ready[MR] = false; H.S.usable[MR] = false   -- Marrowrend can't be paid yet
    local p = primary()
    truthy(p ~= HS, "the last rune is saved for Marrowrend")
end)

test("look-ahead: after Marrowrend, Ossuary is assumed back (no second Marrowrend queued)", function()
    blood()
    H.db.numQueue = 3
    H.S.auras[OSSUARY] = false
    H.S.runesCd = 6
    local r = H.Engine:Evaluate()
    eq(r.primary and r.primary.id, MR)
    for _, e in ipairs(r.queue) do truthy(e.id ~= MR, "no repeat Marrowrend in the queue") end
end)

--------------------------------------------------------------------------------
-- Reset prompt is scoped per spec (it used to wipe every spec's custom lists).
--------------------------------------------------------------------------------
test("defaults prompt: only the spec whose revision rose (and is customized) is offered", function()
    -- Load Core.lua into its OWN sandboxed addon table (stub frames / slash / popups), so its
    -- event wiring never touches the harness engine.
    -- Core.lua also publishes `_G.PRIO = PRIO`, so the real global is saved and restored BY
    -- NAME (a pairs() loop would skip globals that were nil and leave the stubs behind).
    local noop = setmetatable({}, { __index = function() return function() end end })
    local NAMES = { "PRIO", "CreateFrame", "UIParent", "SlashCmdList", "StaticPopupDialogs" }
    local saved = {}
    for _, n in ipairs(NAMES) do saved[n] = _G[n] end
    CreateFrame = function() return noop end
    UIParent = noop; SlashCmdList = {}; StaticPopupDialogs = {}
    local P = { specs = {} }
    local okLoad, loadErr = pcall(function() assert(loadfile(ADDON_DIR .. "/Core.lua"))("PRIO", P) end)
    local popup = StaticPopupDialogs.PRIO_DEFAULTS_CHANGED
    for _, n in ipairs(NAMES) do _G[n] = saved[n] end
    if not okLoad then error("Core.lua failed to load in the sandbox: " .. tostring(loadErr), 0) end
    local ok, err = pcall(function()
        P.db = { customPriorities = {
            DEATHKNIGHT_BLOOD = { st = { { spell = "HeartStrike" } } },
            WARRIOR_ARMS      = { st = { { spell = "MortalStrike" } } },
        }, defaultsSeenBySpec = { DEATHKNIGHT_BLOOD = 1, WARRIOR_ARMS = 0 } }
        P.specs = {
            [250] = { key = "DEATHKNIGHT_BLOOD", label = "Blood", className = "Death Knight", defaultsRevision = 2 },
            [71]  = { key = "WARRIOR_ARMS",      label = "Arms",  className = "Warrior",      defaultsRevision = 0 },
            [70]  = { key = "PALADIN_RETRIBUTION", label = "Retribution", defaultsRevision = 5 },   -- first sighting
        }
        local keys, names = P:ChangedDefaultSpecs()
        eq(#keys, 1, "one spec changed")
        eq(keys[1], "DEATHKNIGHT_BLOOD")
        eq(names[1], "Blood Death Knight")
        eq(P.db.defaultsSeenBySpec.PALADIN_RETRIBUTION, 5, "first sighting recorded silently")
        -- Accepting resets ONLY Blood; Arms keeps its custom list.
        popup.OnAccept(nil, keys)
        falsy(P.db.customPriorities.DEATHKNIGHT_BLOOD, "Blood reset")
        truthy(P.db.customPriorities.WARRIOR_ARMS, "Arms untouched")
        local again = P:ChangedDefaultSpecs()
        eq(#again, 0, "no re-prompt once seen")
    end)
    if not ok then error(err, 0) end
end)

test("REGRESSION (in-game): Bone Shield gone with its CDM bar hidden -> Marrowrend (Deathbringer rows)", function()
    dbr()
    H.S.tracked[BONESHIELD] = false         -- bar set to hide while inactive: no frame now
    H.S.auras[BONESHIELD] = false           -- ...but the game's aura lookup says cleanly absent
    eq(primary(), MR, "a confirmed-absent Bone Shield must rebuild, frame or not")
end)

test("confirmed missing: unreadable stays silent even with the frame present (Deathbringer rows)", function()
    dbr()
    H.S.tracked[BONESHIELD] = true; H.S.auras[BONESHIELD] = nil
    eq(primary(), HS, "nil is not 'absent'")
end)

--------------------------------------------------------------------------------
-- San'layn list v2 (user's second export).
--------------------------------------------------------------------------------
test("San'layn: Blood Boil at 2 charges goes right after Vampiric Blood, outside DRW too", function()
    blood()
    H.S.chargeState[BB] = { max = 2, cur = 2, belowMax = false }; H.S.ready[BB] = true
    H.S.insufficientPower[DS] = false       -- even ahead of an affordable Death Strike (row 9)
    eq(primary(), BB, "row 7: don't cap Blood Boil")
end)

test("San'layn: free Crimson Scourge DnD outside DRW even below 5 Bone Shield", function()
    blood()
    H.S.ready[DND] = true; H.S.glows[DND] = true    -- Crimson Scourge (glow fallback)
    H.S.auras[OSSUARY] = false; H.S.usable[MR] = false   -- below 5, Marrowrend not payable
    eq(primary(), DND, "row 10: a free DnD doesn't wait for Ossuary")
end)

test("San'layn: Vampiric Strike needs the proc, not just Ossuary", function()
    blood()
    H.S.ready[VS] = true; H.S.usable[VS] = true     -- castable, but no proc / override
    eq(primary(), HS, "row 12 holds without the proc -> Heart Strike")
    H.S.overrides = { [HS] = VS }
    eq(primary(), VS, "proc up -> Vampiric Strike")
end)
