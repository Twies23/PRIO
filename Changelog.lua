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
    { "0.3.3", {
        "Outlaw Roll the Bones -- correct 12.1 model: RtB grants one named buff whose identity is the stage (One of a Kind = 1, Double Trouble = 2, Triple Threat = 3); the tracked bar only reads as one stack, so PRIO now reads the stage from which named buff is up. Reroll and Keep It Rolling lines work correctly.",
        "Buff conditions now fall back to reading a buff directly when the Cooldown Manager doesn't track it -- what lets the named Roll the Bones buffs drive the rotation.",
        "Rotation Debug shows all three stage buffs plus a direct-read test for each.",
    } },
    { "0.3.2", {
        "Outlaw Rogue -- first pass (work in progress): recognised spec with a Trickster ST and AoE priority. Combo points read exactly, so combo-point gates are precise.",
        "Rotation Debug (/prio rotdebug) works for Outlaw: shows live what your Cooldown Manager reports active (Roll the Bones stage, Slice and Dice, Blade Flurry, Opportunity...), your combo points, and a direct-read test for the untracked Roll the Bones buffs.",
        "/prio myauras gained a direct-ID probe (/prio myauras <id>, or /prio rtb) that survives combat, since listing all buffs is blocked while fighting.",
        "Still to come: verified 12.1 Roll the Bones buff IDs, Fatebound tuning, Energy pooling.",
    } },
    { "0.3.1", {
        "Groundwork for Outlaw Rogue support.",
        "New /prio myauras (alias /prio buffs): lists every buff on you with its spell ID and whether PRIO can read it in combat -- used to map auras the Cooldown Manager doesn't track, like the individual Roll the Bones buffs.",
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
