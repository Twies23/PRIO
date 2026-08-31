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
    { "0.5.6", {
        "Beast Mastery -- Barbed Shot / Kill Command 'about to cap' is now haste-correct. The game's own charge-recharge read turns out to be secret in combat, so PRIO predicts the next-charge time from the recharge base and your LIVE haste (base / (1 + haste%)) rather than a fixed duration -- the timer no longer drifts as your haste changes.",
        "Barbed Scales and the other cast-triggered reductions are already folded in; Pack Mentality's occasional beast-summon -4s is the only remaining unmodeled nudge.",
    } },
    { "0.5.5", {
        "Beast Mastery -- fixed Barbed Shot / Kill Command charge-timer drift. 'Next charge in Xs' (and the 'about to cap' Barbed Shot check) now reads the game's own recharge -- which is correctly hasted -- instead of a fixed-duration prediction that drifted with haste and unmodeled cooldown reductions. The cast-based prediction stays only as a fallback.",
        "Rotation Debug tags each charge row (live) or (predicted) so you can see whether that readable recharge value stays available in combat or goes secret.",
    } },
    { "0.5.4", {
        "Beast Mastery -- cooldown-reduction modeling. The predicted Kill Command / Barbed Shot recharge (and so the 'Next charge <= X sec' gates and the Rotation Debug seconds) now account for the cast-triggered reductions: Cobra Shot -1s Kill Command, War Orders -3s Kill Command (on Barbed Shot), Barbed Scales -2s Barbed Shot (on Cobra Shot), and Killer Cobra's Kill Command reset during Bestial Wrath.",
        "'Next charge in Xs' now reflects how fast they actually come back. Pack Mentality's beast-summon and Master Handler's per-tick reductions are periodic, so they stay handled by the live charge read.",
    } },
    { "0.5.3", {
        "Beast Mastery -- quantified, tunable timing. New condition 'Next charge <= / >= X sec' for charge spells (Barbed Shot, Kill Command): the seconds until the next charge lands, which the plain Cooldown condition can't show (it reads 0 while a charge is banked).",
        "Bestial Wrath's cooldown now reads in combat, so 'Cooldown <= X sec' on Bestial Wrath is your editable 'Bestial Wrath in less than X seconds' gate. Barbed Shot now fires at 2 charges OR when the next charge is within ~1.5s (about to cap).",
        "Rotation Debug shows Kill Command / Barbed Shot as charges + seconds-to-next, and Bestial Wrath as cooldown seconds left. Cobra Fang is the 4-set tier bonus -- its tracking is now optional, so Setup won't flag it red without the set.",
    } },
    { "0.5.2", {
        "Beast Mastery: simplified to ST and AoE only. Dropped the separate Cleave tier -- the AoE list now covers 2+ targets, so there are just two mode tabs to tune.",
    } },
    { "0.5.1", {
        "Beast Mastery Hunter -- full rotation rebuild for 12.1 (Midnight). Replaces the placeholder lists with a complete, tuned build for both hero trees: Pack Leader (default) and Dark Ranger, each with its own single-target / cleave / AoE lists you can customize.",
        "Reads your real proc signals: Howl of the Pack Leader from the Kill Command glow (empowered KC suggested the instant it lights up), Cobra Shot at 4 stacks of Cobra Fang, and Nature's Ally empowered Kill Command.",
        "Bestial Wrath cooldown is tracked (30s with The Beast Within) so Barbed Shot refreshes right before it -- keeping Frenzy up through the burst without needing to see the pet buff. AoE builds/holds Beast Cleave via Wild Thrash (replaces Multi-Shot); Dark Ranger opens it with Black Arrow and uses the Withering Fire / Wailing Arrow window.",
    } },
    { "0.5.0", {
        "Fifth stable release -- headlined by a redesigned Setup and the finalized Outlaw Trickster lists. Everything since 0.4.11.",
        "Setup rebuilt: general checks up top (Cooldown Manager active, nameplates), then two columns -- Ability cooldowns (left, validation for your own display; PRIO reads cooldowns directly) and Auras to add (right, REQUIRED -- PRIO reads buffs only from the Cooldown Manager).",
        "Setup auto-derives the required auras from your real rotation (default AND custom conditions), so it can't miss one and doesn't list buffs the rotation never reads. Glow-driving abilities (e.g. Pistol Shot for Opportunity) are flagged required. Status updates live as you edit the CDM; re-opens after each update; rows no longer overlap; build-specific (4-set) auras show optional.",
        "Outlaw: finalized Trickster default lists; corrected two tracked-aura IDs (Loaded Dice, Flawless Form).",
    } },
    { "0.4.16", {
        "Setup: glow-driving abilities are now flagged as required. Some reads use an ability's proc glow (e.g. Outlaw reads Opportunity from Pistol Shot's glow), which only lights up when that spell is present -- so those show in the Abilities column tagged (glow) and turn red until added. Columns reframed: left 'ability cooldowns -- validation' (for your own cooldown display), right 'auras to add to your Cooldown Manager' (required).",
        "Setup dots update live as you edit the Cooldown Manager, and on an update the setup opens after you close the changelog instead of stacking on top of it.",
    } },
    { "0.4.14", {
        "Setup polish: intro text no longer overlaps the first row, and a build-specific aura like Fang Strike (4-set) shows amber 'optional' instead of red 'required' when you don't have the set.",
    } },
    { "0.4.13", {
        "Setup redesigned. /prio setup now shows general checks up top, then two columns: Abilities (left -- add to the Cooldown Manager's Essential/Utility, recommended) and Auras (right -- add to Tracked Buffs, REQUIRED, PRIO reads these). Rows grow to fit their text (no overlap), misleading entries dropped (e.g. the bogus 'Between the Eyes debuff window'), and it re-opens after each update so you re-verify (an update can add a newly-required aura).",
        "'Apply recommended settings' now enables the opener and the primary glow.",
    } },
    { "0.4.12", {
        "Setup (/prio setup) is now robust -- it can't miss a required aura. Added a 'Cooldown Manager active' check at the top (PRIO reads all buffs/debuffs from Blizzard's Cooldown Manager -- without it, it's blind in combat), and the checklist now AUTO-DERIVES every aura your rotation actually gates on from the priority lists and lists any that were missing (e.g. Outlaw's Adrenaline Rush, Elemental's Stormkeeper / Purging Flames). Nothing removed -- only missing items added.",
    } },
    { "0.4.11", {
        "Outlaw -- finalized Trickster default lists. Killing Spree during Adrenaline Rush now also requires AR on cooldown (fires inside the AR window); single-target Stealth only shows when you're NOT already stealthed (AoE keeps it always). Reset to default (per mode) to pick up if you've customized. Also fixed two tracked-aura IDs (Loaded Dice 256171, Flawless Form 441326 -- the buffs, not the talents).",
    } },
    { "0.4.10", {
        "Fourth stable release -- full Outlaw Fatebound support and a big round of Elemental & Outlaw fixes. Everything since 0.4.0.",
        "Outlaw: Fatebound hero tree (Trickster / Fatebound split, auto-selected from talents; both share tuned ST/AoE defaults, each customizable per hero). New tuned default lists -- Stealth opener, supercharge-aware finishers, Killing Spree during Adrenaline Rush, 4-set free Dispatch, and a self-gating Fatebound Deal Fate line.",
        "Outlaw: Supercharged Combo Points (Supercharger talent) tracked, with new 'Supercharged CP >= / <= / = N' conditions. Finishers now fire at the combo points you set, not only at max (the game reports a finisher's cost as its maximum, which was overriding your condition). Stealth added as an ability; new Stealthed / Not stealthed condition.",
        "Elemental: spenders gate on the game's readable insufficient-power flag instead of predicted Maelstrom (exact, no drift) -- fixes both showing too early and being held back while overcapping. Flame Shock's passive per-tick Maelstrom is now counted and Chain Lightning scales per target. The 4-set free spender is read from the CDM glow -- not withheld, not mispredicted as drained.",
        "Engine & editor: new '=' (equals) operator for count conditions (Combo Points, Opportunity, Supercharged CP, Buff stacks, Charges, Enemies); fixed the Rotation Debug window showing some '>=' / glowing / usable conditions' pass/fail inverted (display-only -- the rotation itself was always correct).",
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
