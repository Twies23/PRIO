-- Changelog.lua ----------------------------------------------------------------
-- In-app changelog viewer (/prio changelog). Addons can't read CHANGELOG.md at
-- runtime, so the recent entries are embedded here -- keep the top few in sync.
--------------------------------------------------------------------------------

local ADDON, PRIO = ...
local UI = PRIO.UI
local C  = UI.C
local Changelog = {}
PRIO.Changelog = Changelog

-- Newest first. { version, { line, line, ... } }
local ENTRIES = {
    { "0.4.9", {
        "Outlaw -- Supercharged Combo Points (Supercharger talent): Adrenaline Rush supercharges 2, and each damaging finisher (Dispatch, Between the Eyes, Killing Spree) consumes one. New editable conditions 'Supercharged CP >= / <= / = N'. Predicted from your own casts; shown in Rotation Debug; inert unless talented.",
        "New '=' (equals) condition operator alongside >= and <= -- for Combo Points/Resource, Opportunity, Supercharged CP, Buff stacks, Charges, and Enemies.",
        "Outlaw -- Stealth added as an ability (Vanish was already there), plus a 'Stealthed / Not stealthed' condition reading the game's stealth state (Stealth / Vanish / Shadow Dance) for opener and re-stealth lines.",
    } },
    { "0.4.8", {
        "Outlaw -- finishers now fire at the combo points you set, not only at max. A finisher (Dispatch, Between the Eyes, Slice and Dice) is castable at any combo points, but the game reports its COST as the maximum -- so PRIO's affordability check withheld it below max and overrode your own condition. A 'Dispatch at >= 5 CP' line now fires at 5 (still correctly withheld at 0 CP). The real fix behind 'it should recommend Dispatch, not Sinister Strike'.",
    } },
    { "0.4.7", {
        "Fix: the Rotation Debug window showed some conditions' pass/fail inverted. A '>= N' line (e.g. Combo Pts >= 6) wrongly showed PASS whenever you were BELOW N, likewise for other >=/glowing/usable checks. Display-only -- the actual rotation always evaluated correctly -- but it made it look like a finisher should be firing before you had the combo points. The debug now reports true pass/fail.",
    } },
    { "0.4.6", {
        "Outlaw -- Fatebound hero tree added. Outlaw now has a Trickster / Fatebound hero split (auto-selected from your talents, like Arms' Slayer / Colossus). Fatebound's default lists are a clone of Trickster's for now -- a starting point to rework in-game and re-tune. Pick either tree under Options -> Priorities to view and edit its lists.",
    } },
    { "0.4.5", {
        "Elemental -- spenders now gate on 'can I actually afford it?' instead of predicted Maelstrom. Predicting a secret filling resource always drifts, so Earth Shock / Elemental Blast / Earthquake now use the game's own insufficient-power flag, which reads exactly even while the Maelstrom bar is hidden -- no prediction, no drift. They appear the moment you have the Maelstrom and stay down when you don't (a free 4-set proc reads as affordable automatically). If the game hides that flag too, it falls back to the old predicted gate so a spender can't spam. Verify with /prio usable in combat -- the noPower column should read true/false, not secret.",
    } },
    { "0.4.4", {
        "Elemental -- fixed overcapping. Predicted Maelstrom ran low because it never counted Flame Shock's passive generation (its DoT ticks generate Maelstrom continuously, and you keep it up all fight), so spenders were held back until you'd already capped. PRIO now accrues Flame Shock ticks over time (haste-scaled, ~3 per tick), and Chain Lightning generates per target (2 x targets) instead of a flat amount. The prediction now tracks real Maelstrom far better. If it spends slightly early, the Flame Shock tick value is a one-line tune.",
    } },
    { "0.4.3", {
        "Elemental 4-set (Ophidian Oracle): PRIO now understands the free spender. When the proc lights up your next Earth Shock / Elemental Blast / Earthquake on the Cooldown Manager, PRIO reads that glow and treats the spender as costing no Maelstrom -- so it isn't withheld by the affordability gate, and your predicted Maelstrom is no longer mispredicted as drained after the free cast. The glow read is latched, since the proc clears the instant you cast.",
    } },
    { "0.4.2", {
        "Fix (Elemental Shaman, long-standing): Elemental Blast / Earthquake / Earth Shock were recommended before you had enough Maelstrom. Maelstrom is secret in combat, so the affordability gate was being skipped and spenders showed at any amount. PRIO now gates Elemental's spenders on its PREDICTED Maelstrom (already tracked precisely), so a spender only appears once you can afford it -- the same result Outlaw gets from readable combo points. Fail-open specs (Arms rage) are unchanged.",
    } },
    { "0.4.1", {
        "Fix (regression from 0.4.0): the 'keep showing a spender only blocked by resource' behavior was applied to every spec, wrongly recommending Elemental Shaman Maelstrom spenders before you had enough Maelstrom. That relaxation is now Outlaw-only (Energy regens passively); built-resource specs (Maelstrom, Holy Power) again wait until you can afford the spender.",
    } },
    { "0.4.0", {
        "Third stable release -- headlined by full Outlaw Rogue (Trickster) support, plus engine improvements for every spec. Everything since 0.3.0.",
        "Outlaw: complete ST and AoE priorities and the opener. Roll the Bones is read EXACTLY from combo-point timing (a stage-2+ roll makes Sinister Strike give an extra combo point, an instant before a double-strike does), so it rerolls a stage-1 roll and never a good one.",
        "Opportunity tracked (0/3/6) by detecting Sinister Strike double-strikes; drives the Pistol Shot lines; new adjustable Opportunity >= N condition. Keep It Rolling is a movable advisory alert; the free Dispatch keys off the 4-set Fang Strike buff.",
        "Engine (all specs): the queue predicts combo-point generation so upcoming icons build toward a finisher; abilities unusable only for lack of a filling resource (Energy) keep showing instead of collapsing to the cheapest filler; fixed a cost check that compared Energy to combo points; the alert banner is draggable.",
    } },
    { "0.3.0", {
        "Second stable release -- full Arms Warrior and Windwalker Monk support, plus a much deeper engine.",
        "Arms rebuilt: auto hero-tree split (Slayer/Colossus); separate ST and AoE lists, each auto-swapping to an execute variant in execute range; the Cleave tier is dropped for a configurable AoE-at-N threshold; tuned Slayer defaults and ST/AoE openers.",
        "Windwalker rebuilt: Shado-Pan / Conduit hero split, accurate Chi + Energy prediction, Combo Strikes.",
        "Reads the game under the secret-value API: proc-glows stand in for hidden stacks, predicted counters where there is no signal, latched execute-range detection, secret-safe charges / cooldowns / buff timers, and it keeps predicting during channels like Bladestorm.",
        "New condition types (buff stacks, charges, resource, usable, buff time left, cooldown, energy, enemy has/missing debuff) and named presets that hide the raw mechanics.",
        "Configurable openers, split into ST and AoE, shown before the pull, with an \"all cooldowns ready\" gate and a gold OPENER badge.",
        "Clickable / movable mode buttons, a Rotation Debug window (minimap middle-click or /prio rotdebug), per-spec mode tabs, reworked Profiles, corrected Setup checklists, and an auto-opening changelog.",
        "Fixes: the queue never goes short or suggests an unusable ability, cooldown abilities no longer stack as fillers, untracked buffs fail their row.",
    } },
    { "0.2.0", {
        "First stable release: configurable priority & queue helper for 12.1. Specs: Elemental Shaman, Marksmanship, Beast Mastery, Arms Warrior. Priority editor, pandemic refresh, Setup, Profiles, and secret-value prediction.",
    } },
}

local win
function Changelog:Build()
    if win then return end
    win = UI.Window("PRIOChangelog", 470, 520, "PRIO  Changelog", "What's changed")
    win:SetFrameStrata("DIALOG")
    local scroll = CreateFrame("ScrollFrame", "PRIOChangelogScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -64); scroll:SetPoint("BOTTOMRIGHT", -34, 18)
    local body = CreateFrame("Frame", nil, scroll); body:SetSize(410, 10)
    scroll:SetScrollChild(body)

    local acc = UI.accentHex or "0cd29f"
    local parts = {}
    for _, entry in ipairs(ENTRIES) do
        parts[#parts + 1] = "|cff" .. acc .. entry[1] .. "|r"
        for _, line in ipairs(entry[2]) do
            parts[#parts + 1] = "  \226\128\162 " .. line
        end
        parts[#parts + 1] = " "
    end

    local fs = UI.Font(body, 12.5, C.text)
    fs:SetPoint("TOPLEFT", 4, -4); fs:SetPoint("RIGHT", body, "RIGHT", -4, 0)
    fs:SetJustifyH("LEFT"); fs:SetSpacing(4)
    fs:SetText(table.concat(parts, "\n"))
    body:SetHeight(math.max(fs:GetStringHeight() + 16, 10))
end

function Changelog:Toggle()
    self:Build()
    if win:IsShown() then win:Hide() else win:Show() end
end

function Changelog:Open()
    self:Build()
    win:Show()
end

-- The newest version we have notes for.
function Changelog:CurrentVersion()
    return ENTRIES[1] and ENTRIES[1][1]
end

-- Pop the changelog once when the addon's version changes from what was last seen.
function Changelog:MaybeAutoOpen()
    local db = PRIO.db
    if not db then return end
    local cur = self:CurrentVersion()
    if not cur then return end
    local seen = db.changelogSeenVersion
    db.changelogSeenVersion = cur
    if seen ~= cur then self:Open() end
end
