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
