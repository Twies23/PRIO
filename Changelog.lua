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
    { "0.3.9", {
        "The Keep It Rolling alert now shows its keybind and clearer wording: \"2+ roll detected -- extend if it's a 3 or Jackpot.\" Says what PRIO knows (a good roll) and leaves the extend call to you.",
    } },
    { "0.3.8", {
        "Roll the Bones can be tracked as either a bar OR a buff in your Cooldown Manager -- both let PRIO see a roll is active. Setup guidance corrected (it previously implied a bar was required).",
    } },
    { "0.3.7", {
        "Advisory alerts: PRIO can now show a pulsing prompt above the strip for a decision only you can make. First use is Keep It Rolling -- since only you can see if your roll is a stage 3 / Jackpot worth extending, PRIO no longer auto-presses it; when it's ready on a confirmed good roll (stage 2+) it prompts you to check and extend, and leaves the call to you.",
        "(Needs Roll the Bones tracked as a bar, like the reroll logic.)",
    } },
    { "0.3.6", {
        "Outlaw Roll the Bones -- sharper detection via Opportunity. Sinister Strike grants Opportunity on its double-strike, so PRIO reads that to know how many strikes landed and interprets the combo-point yield exactly: yield == strike count means stage 1 (reroll); more means stage 2+ (now confirmed, not just assumed).",
        "Keep It Rolling now fires on a CONFIRMED good roll (stage 2+) instead of any roll, so it never extends a stage-1 roll you're about to reroll. (Stage 3 isn't readable -- it only speeds secret cooldowns.)",
    } },
    { "0.3.5", {
        "Outlaw Roll the Bones -- infer the roll from combo points. The stage buffs aren't readable in combat, so PRIO watches Sinister Strike: stage 2 makes it generate an extra combo point, so a Sinister Strike that gives only its base 1 CP proves a stage-1 roll -> reroll. It never mistakes a good roll for a bad one, and RtB's long cooldown gives it time to settle.",
        "Keep It Rolling runs on cooldown while a roll is active (stage 3 isn't readable).",
        "Rotation Debug shows the inferred roll state (reroll / assume good).",
    } },
    { "0.3.4", {
        "Outlaw Roll the Bones -- read the stage from the bar's name. The three stage buffs share one Cooldown Manager bar and are secret by ID in combat, so PRIO now reads which name the bar is showing (One of a Kind / Double Trouble / Triple Threat) to know the real stage. Reroll and Keep It Rolling now fire correctly. Track Roll the Bones as a Bar for this to read.",
        "New /prio rtbframe dumps the Roll the Bones bar's icon + text to verify the stage read in combat.",
    } },
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
