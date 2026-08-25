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
    { "0.2.46", {
        "Chi prediction handles Obsidian Spiral: Blackout Kick becomes a +1 Chi builder (talent-gated), castable at 0 Chi.",
    } },
    { "0.2.45", {
        "Conduit cleave + AoE default rebuilt to the tuned list (now shared); Blackout Kick! / Dance procs spent aggressively so they don't overcap. Reset lists to default.",
    } },
    { "0.2.44", {
        "Hero detection keys on Invoke Xuen via a strict talent check -- reliable Conduit/Shado-Pan signal that won't flip mid-combat.",
    } },
    { "0.2.43", {
        "Fixed Rushing Wind Kick recommended without its proc (Shado-Pan cleave/AoE); it now also requires the proc. Reset lists to default.",
    } },
    { "0.2.42", {
        "Fixed the queue going short: the look-ahead now regenerates Energy per slot, and a fallback relaxes only the soft gates (Combo Strikes, Energy guess) -- never cooldown/Chi/condition -- so it always fills 3.",
    } },
    { "0.2.41", {
        "\"Missing buff\" now passes for an untracked/unhad buff (e.g. Unbroken Rhythm without the 4pc); symmetric with \"Has buff\".",
    } },
    { "0.2.40", {
        "Conduit single-target default updated to the refined list (BoK! stacks -> boolean proc). Reset lists to default.",
    } },
    { "0.2.39", {
        "Reverted Debug \"Blackout Kick!\" to boolean -- its stack count wasn't reading reliably.",
    } },
    { "0.2.38", {
        "Debug \"Blackout Kick!\" row shows its stack count instead of up/gone.",
    } },
    { "0.2.37", {
        "Conduit single-target default built to the tuned list, with Heart of the Jade Serpent duration modeled (FoF before it falls off).",
        "A cast can now grant multiple timed buffs (Zenith grants its window + HoJS with Yu'lon's Avatar). Reset lists to default.",
    } },
    { "0.2.36", {
        "New \"Cooldown >= / <= N\" condition with Invoke Xuen cooldown prediction (120s, -30s Xuen's Bond).",
        "Drives the Conduit \"WDP / Strike of the Windlord if Xuen > 10s away\" lines; Debug shows Invoke Xuen CD.",
    } },
    { "0.2.35", {
        "Shado-Pan cleave + AoE default rebuilt to the tuned multi-target rotation. Reset Windwalker lists to default.",
    } },
    { "0.2.34", {
        "Shado-Pan single-target default rebuilt to the tuned rotation. Reset Windwalker lists to default to pick it up.",
    } },
    { "0.2.33", {
        "Added Tigereye Brew (1261724) to Windwalker buffs (condition, Debug row, setup entry).",
    } },
    { "0.2.32", {
        "Added a live \"Blackout Kick!\" row to the Debug window.",
    } },
    { "0.2.31", {
        "Added the \"Blackout Kick!\" proc (116768) to Windwalker buffs, selectable in buff conditions.",
    } },
    { "0.2.30", {
        "New \"Energy near cap\" boolean condition (threshold 100) for avoid-capping lines; Debug flags NEAR CAP.",
    } },
    { "0.2.29", {
        "Energy prediction leans +10% conservative so you dump before capping rather than after.",
    } },
    { "0.2.28", {
        "Energy prediction now scales with haste (was reading a bit low at flat 10/sec).",
    } },
    { "0.2.27", {
        "Full Energy prediction: fixed 10/sec regen (+Ascension) dead-reckoned to your real cap, anchored to checkpoints + casts.",
        "\"Energy % >=\" avoid-capping lines now work all the way to cap.",
    } },
    { "0.2.26", {
        "Energy readable as a percent (secret-safe), so PRIO sees Energy to your real cap, not just to 60.",
        "New \"Energy % >= / <=\" condition for avoid-capping lines; look-ahead seeds from real Energy %.",
    } },
    { "0.2.25", {
        "Windwalker Energy checkpoint model: usable abilities imply an Energy floor, spent across the look-ahead.",
        "Combo Strikes is a hard rule -- never recommends the same ability twice in a row.",
        "Queue walks the list with full state carried forward instead of relaxing rules to fill slots.",
    } },
    { "0.2.24", {
        "Condition target dropdown filtered by type: buffs for buff checks, abilities for cooldown/usable, Zenith-only for buff time left.",
        "Condition types filtered per spec -- Shaman-only MotE / SK stacks no longer show for Monk.",
        "Adding an ability no longer jumps the list back to the top.",
    } },
    { "0.2.23", {
        "New condition: \"Buff time left >= / <= N sec\". Zenith's window is timed from the cast (15s, +5s Drinking Horn Cover).",
        "Enables a real \"spend before Zenith ends\" rule; Debug shows live Zenith time left.",
    } },
    { "0.2.22", {
        "Cleanup: removed the dead Energy model + charge-scraping code and the redundant Energy Debug row (no behavior change).",
    } },
    { "0.2.21", {
        "Tiger Palm no longer suggested when you can't afford its Energy (clean 'insufficient power' flag).",
        "Debug: Zenith charges shows a real count while recharging (1 / 2), with source + time to next charge.",
    } },
    { "0.2.20", {
        "Charges now read EXACTLY and secret-safely (EllesmereUI's method): recharge-active flag + usable state pin 0/1/2.",
        "\"Zenith if Charges >= 2\" is now exact, not predicted. Debug shows count, source, and time to next charge.",
    } },
    { "0.2.19", {
        "Zenith charges now tracked by prediction (like Lava Burst) -- the Cooldown Manager read was unreliable.",
    } },
    { "0.2.18", {
        "Zenith charge tracking fixed (was reading the recharge timer, not the count).",
        "Debug: added a Tiger Palm usability probe -- Energy itself is a secret value, so we're checking for another readable signal.",
    } },
    { "0.2.17", {
        "Priority list keeps its scroll position when you add / move / remove a row.",
        "Windwalker: Tiger Palm isn't recommended when you can't afford its Energy (Energy now modeled).",
        "The queue never runs out early -- it always fills Now + Next with a castable ability.",
        "Debug: added live Energy + Zenith charges; fixed the Economy section overlapping.",
    } },
    { "0.2.16", {
        "\"Charges >=\" is now a number picker (counts the line's own ability), not an ability picker.",
        "Fixed conditions needing both a spell and a number (e.g. Buff stacks >=) -- both controls now show.",
    } },
    { "0.2.15", {
        "\"Charges >=\" now reads the real charge count from the Cooldown Manager (secret-safe, exact).",
        "Track Zenith in the Cooldown Manager (see /prio setup) for its Charges condition.",
    } },
    { "0.2.14", {
        "Windwalker: \"Charges >=\" now works for Zenith (charge-tracked, 2 charges).",
    } },
    { "0.2.13", {
        "Windwalker: Zenith is now a castable, pickable ability you can add to your priorities.",
    } },
    { "0.2.12", {
        "Windwalker rebuilt to Icy Veins prios, split by hero (Shado-Pan / Conduit) with auto-select.",
        "Removed retired Storm, Earth, and Fire.",
        "Rushing Wind Kick only fires when its proc buff is up.",
        "Chi prediction is now cost/generation-accurate for the look-ahead queue.",
    } },
    { "0.2.11", {
        "Untracked buffs now FAIL their row (red dot) instead of silently passing.",
        "Windwalker Combo Strikes: never queues the same ability twice in a row.",
        "Fixed Windwalker Dance of Chi-Ji / Combo Breaker buff IDs.",
    } },
    { "0.2.10", {
        "New conditions: Resource >= / <= N (Chi, Holy Power, ...), and Usable / Not usable (another ability).",
        "Windwalker uses Chi thresholds for its low-Chi lines.",
    } },
    { "0.2.9", {
        "Arms rebuilt to the Slayer priority (stack/charge-driven).",
        "New conditions: Buff stacks >= / <= N, and Charges >= / <= N.",
        "Secret-safe buff stack reading via the Cooldown Manager.",
        "Added this in-app changelog (/prio changelog).",
    } },
    { "0.2.7-0.2.8", {
        "Fixed saving profiles (name popup edit box).",
        "Profiles reworked to a dropdown + Save/Delete.",
        "Corrected Arms buff IDs from the tracked dump.",
    } },
    { "0.2.3-0.2.6", {
        "Editing list is separate from the live mode (edit any list in combat).",
        "Elemental assumes Flame Shock is up briefly after applying it.",
        "Windwalker Monk rebuilt to the 12.1 Conduit + Shado-Pan priority.",
        "Class-colored UI accent.",
    } },
    { "0.2.0-0.2.2", {
        "First stable release: Elemental, MM/BM Hunter, Arms Warrior, Windwalker.",
        "Profiles, defaults-changed prompt, condition text export.",
        "DoT pandemic-window refresh via the Cooldown Manager.",
    } },
    { "0.1.x", {
        "Priority editor with live pass/fail dots and a condition builder.",
        "Per-spec first-time Setup checklist; minimap button.",
        "Advances the primary while casting; predicts secret values.",
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
