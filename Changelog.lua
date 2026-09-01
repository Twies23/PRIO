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
    { "0.7.13", {
        "Windwalker openers are hero-split + configurable: Options -> Opener has a Shado-Pan / Conduit switch, each with its own ST and AoE sequence.",
    } },
    { "0.7.12", {
        "Zenith overcap dump now gates on Zenith's Cooldown-Manager glow (the real 20-Tigereye-stack signal) instead of predicted stacks.",
    } },
    { "0.7.11", {
        "Fixed 'dead' condition rows: nested groups (A OR (B AND C)) now show as a read-only summary instead of a blank dropdown. Conduit Zenith split into two editable rows.",
    } },
    { "0.7.10", {
        "Zenith's overcap dump now waits for 20 predicted Tigereye Brew stacks (Zenith consumes 20 for crit). Burst Zenith still fires. Debug shows predicted stacks.",
    } },
    { "0.7.9", {
        "Conduit Zenith timing matches the logs: cast right after Celestial Conduit in the burst, or at 2 charges to avoid overcap (no random mid-fight casts).",
    } },
    { "0.7.8", {
        "Conduit now recommends casting Zenith (was missing) -- placed with the burst cooldowns, gated at 2 charges so the 2nd is never wasted.",
    } },
    { "0.7.7", {
        "Conduit now recommends casting Invoke Xuen (was missing) -- gated to fire when Celestial Conduit is ready, to open its window.",
    } },
    { "0.7.6", {
        "Conduit single-target: restored Strike of the Windlord (Xuen window) and Slicing Winds -- now matches the Icy Veins guide line-for-line.",
    } },
    { "0.7.5", {
        "Conduit Windwalker ST + AoE rebuilt to match top-player logs / Icy Veins (RSK on cooldown, Rushing Wind Kick added to AoE). Reset lists to default.",
    } },
    { "0.7.4", {
        "Keybind nudge -- 'Don't remind me' now resets on each PRIO update that has changelog notes, so the nudge returns once per new version (a new version can add abilities worth binding). Per-ability Ignore still sticks.",
    } },
    { "0.7.3", {
        "Keybind nudge -- reworded the Ignore / Don't remind me confirmation prompt.",
    } },
    { "0.7.2", {
        "Keybind nudge -- Ignore and 'Don't remind me' now ask you to confirm first, so you can't silence the nudge by accident.",
    } },
    { "0.7.1", {
        "Keybind nudge. On login, if the active spec has abilities PRIO can recommend that you have no key for, a small panel lists them -- bind each on your bars and its row turns green. Open anytime with /prio binds.",
        "Honors override abilities (e.g. Moonlight Chakram shares Trueshot's key) so they're not false-flagged; skips passives and abilities you don't know.",
        "Macro users: hit Ignore on a row to silence it for that spec, or 'Don't remind me' to mute the panel per spec. Shows at most once per session, never nags.",
    } },
    { "0.7.0", {
        "Marksmanship Hunter added -- full Sentinel and Dark Ranger support (auto-selected from your hero talent), built to the same bar as the other specs.",
        "Sentinel default rotation: hold Trueshot to line up with Explosive Shot, the Explosive Shot double-cast (Unstable Trigger), Moonlight Chakram inside Trueshot, Precise Shots spending (Kill Shot / Arcane), and Aimed Shot on charges.",
        "Trueshot predicted cooldown + duration, talent-aware (Can't Miss +2s, Calling the Shots -30s). Moonlight Chakram tracked through the Trueshot-button override (once per Trueshot).",
        "Target Switch action node you can drop anywhere with your own condition; Focus-affordability dimming; Aimed Shot charge+haste model; pet check gated on Unbreakable Bond.",
        "Hunter's Mark upkeep is included but still being finalized (see Rotation Debug) -- it stays inert until the right per-target read is confirmed, so it won't misfire.",
    } },
    { "0.6.20", {
        "Marksmanship -- Hunter's Mark diagnostic. Target auras are likely secret in combat, so Rotation Debug now shows the Hunter's Mark read TWO ways -- the CDM buff frame and the target unit aura -- side by side. With a marked target, note which reads up; then swap to an unmarked target and watch which one clears. Whichever follows the swap is the per-target signal, and the upkeep line will be wired to it. Until then the line stays inert (it won't misfire).",
    } },
    { "0.6.19", {
        "Marksmanship -- Hunter's Mark now tracked per-target. It's read as the debuff on your CURRENT TARGET (UnitAuraID 257284), not the Cooldown Manager buff -- so it correctly re-prompts when you swap to an unmarked target, and never nags when you have no target or the read is unavailable. The Hunter's Mark upkeep line is back in the Sentinel and Dark Ranger defaults, and Rotation Debug shows the live 'Hunter's Mark (target)' read. Two new conditions -- 'Hunter's Mark missing (target)' and 'Hunter's Mark on target' -- are available in the editor.",
    } },
    { "0.6.18", {
        "Marksmanship -- Moonlight Chakram tracking fixed properly. Its button glow doesn't read (not a proc overlay) and its cooldown always reads ready, so PRIO now gates it on Trueshot being active plus a once-per-window flag that correctly handles the override -- a Trueshot-key press while Trueshot is active is counted as the Chakram cast. So it's suggested once during Trueshot and doesn't come back after you use it. Added a 'Chakram available' condition you can drop on any line.",
    } },
    { "0.6.17", {
        "Marksmanship -- 'Chakram glowing' is now a selectable condition. You can add it (plus the individual Chakram / Trueshot icon-glow reads) to any priority line in the condition editor, to tune the Moonlight Chakram timing yourself.",
    } },
    { "0.6.16", {
        "Marksmanship -- Moonlight Chakram now tracked by its glow, and shows the Trueshot keybind. Chakram replaces the Trueshot button, so its own cooldown read is unreliable. PRIO now reads its 'castable' state from the icon glow (which clears once you use it), so it's suggested only while actually available and only once per Trueshot. Its keybind now mirrors Trueshot's, and Rotation Debug shows the Chakram/Trueshot glow.",
    } },
    { "0.6.15", {
        "Marksmanship -- Moonlight Chakram no longer double-recommended. After you use it in Trueshot the button keeps reading 'ready', so it was suggested a second time. Both Chakram lines now also gate on a 'used this window' flag (reset when you press Trueshot), so it shows once per Trueshot. Rotation Debug shows the flag.",
    } },
    { "0.6.14", {
        "Marksmanship -- Sentinel default finalized (ST + AoE). The tuned Sentinel priority now ships for both single-target and AoE -- the Aspect of the Hydra Multi-Shot line self-gates on 2+ targets, so one list covers both -- replacing the separate AoE list.",
    } },
    { "0.6.13", {
        "Action nodes are now addable in the priority editor. The '+ Add ability' picker lists action nodes (like Marksmanship's Target Switch) alongside spells, so you can drop one anywhere in a list and set its condition like any other row. Action rows show their label + icon and open the condition editor on click.",
    } },
    { "0.6.12", {
        "New: action nodes -- 'Target Switch' for Marksmanship. A priority row can now be a spell-less instruction that shows a labeled icon whenever its condition passes (always 'off cooldown'). Marksmanship uses it for Target Switch -- the desaturated arrows icon with a 'Target Switch' label -- placed before Trueshot to prompt swapping off an already-marked target. It's a general building block any spec can use.",
    } },
    { "0.6.11", {
        "Marksmanship -- Sentinel AoE handles Trick Shots / Aspect of the Hydra. The two AoE-defining talents (the Trick Shots vs Aspect of the Hydra choice node) are now talent-gated lines in the Sentinel AoE list: Trick Shots activates the Aimed / Rapid Fire ricochet via Multi-Shot on 3+; Aspect of the Hydra spends Precise Shots on Multi-Shot at 2+. On a pure single-target build both stay inert (AoE plays like ST).",
    } },
    { "0.6.10", {
        "Marksmanship -- Sentinel / Dark Ranger variant split. Added the hero-style variant system (auto-selected from Black Arrow): your tuned Sentinel lists plus a first-pass Dark Ranger single-target priority (Black Arrow as the Precise spender + core cooldown, Wailing Arrow, Aimed-in-Trueshot). Also fixed variant auto-detection, which was always falling back to Sentinel.",
    } },
    { "0.6.9", {
        "Marksmanship -- tuned Sentinel ST/AoE as the default. Shipped the hand-tuned single-target priority: Explosive Shot / Volley on cooldown, Trueshot held until Explosive is 15s+ out (then popped right after Explosive), Moonlight Chakram inside Trueshot, Precise Shots spent on Kill / Arcane Shot, Aimed Shot on cooldown, Steady Shot filler. Without Trick Shots the AoE list is identical (a Trick Shots AoE variant is coming).",
    } },
    { "0.6.8", {
        "Marksmanship -- Moonlight Chakram no longer over-recommended. During Trueshot the button becomes Moonlight Chakram, usable once. PRIO now suggests it a single time near the end of the Trueshot window (~5s left) -- tracked so it won't re-appear every global cooldown until you press it.",
    } },
    { "0.6.7", {
        "Marksmanship -- pet lines gate on Unbreakable Bond. MM is petless (Lone Wolf) without the Unbreakable Bond talent, so the Call Pet / Revive Pet lines now only appear when you've taken it -- no stray pet suggestions on a Lone Wolf build.",
    } },
    { "0.6.6", {
        "Marksmanship -- Trueshot duration and cooldown-reduction tracking. PRIO now times Trueshot's buff (15s, +2s with Can't Miss, Won't Miss) so 'seconds left on Trueshot' gates read (e.g. Moonlight Chakram near the end), and its predicted cooldown accounts for Calling the Shots (120s -> 90s). Rotation Debug shows both the duration and cooldown left.",
    } },
    { "0.6.5", {
        "Marksmanship -- Hunter's Mark is now a first-class tracked buff, so the setup and condition editor recognise it, with a 'Hunter's Mark' row in Rotation Debug to watch the read. PRIO reads it from your Cooldown Manager's Tracked Buffs.",
    } },
    { "0.6.4", {
        "Marksmanship -- Explosive Shot cooldown tracking (Unstable Trigger aware). Added a predicted 30s cooldown for Explosive Shot. Unstable Trigger lets you fire it a second time within 3 seconds, and the 30s runs from the first press -- so the second cast no longer restarts the timer. Rotation Debug shows the Explosive Shot cooldown alongside Trueshot.",
    } },
    { "0.6.3", {
        "Marksmanship -- tracking leans on booleans + charges. Dropped predicted-cooldown tracking for everything except Trueshot (2 min, for the hold/delay logic). Short cooldowns just read the live ready flag, and the rotation gates on buffs (Precise Shots, the mark, Trick Shots, Unstable Trigger, Bullseye) and Aimed Shot charges.",
    } },
    { "0.6.2", {
        "Marksmanship -- tracked IDs corrected from the live Cooldown Viewer. Lock and Load (194595), Bullseye (204089), and the target mark is now Spotter's Mark (1219616), which becomes Sentinel's Mark once you take the Sentinel hero talent. Added Unstable Trigger (the Explosive Shot double-cast) and Bulletstorm tracking; dropped the Streamline / Lunar Storm guesses (not present without the talent/hero). While levelling, lines for abilities you haven't learned yet (Kill Shot, Black Arrow, Wailing Arrow) stay inert and light up as you get them.",
    } },
    { "0.6.1", {
        "Marksmanship Hunter -- tracking rebuilt (Sentinel). Corrected the abilities, buffs, and predicted cooldowns for 12.1 (Precise Shots, Trick Shots, Sentinel's Mark, Moonlight Chakram, the Aimed Shot charge/haste model, Trueshot / Rapid Fire / Volley cooldown tracking) and added a first-pass Sentinel rotation, the pet check, Hunter's Mark upkeep, and Focus-affordability dimming. A few buff IDs (Bullseye, Streamline, Lunar Storm) are still being verified -- work in progress.",
    } },
    { "0.6.0", {
        "Sixth stable release -- headlined by Beast Mastery Hunter, built and tuned end-to-end for 12.1 (Midnight). Everything since 0.5.0.",
        "Beast Mastery: full Pack Leader (default) and Dark Ranger single-target / AoE lists with verified IDs and the hand-tuned Pack Leader rotation as the default. Reads Howl from the Kill Command glow, Cobra Fang / Nature's Ally / Beast Cleave / Hunter's Mark / Bestial Wrath from the Cooldown Manager, and Focus affordability from the clean insufficient-power flag (the Focus number is secret).",
        "Beast Mastery: charges rebuilt -- exact 0/1/2 count via the charge-aware cooldown (fixes a 'reads 1 when it's 0' bug on every 2-charge spell) + haste-correct next-charge prediction. Pet check at the top of each list (Call Pet / Revive Pet), Hunter's Mark upkeep, Bestial Wrath cooldown tracking, cooldown-reduction modelling.",
        "All specs: unaffordable spenders are shown dimmed (desaturated) instead of hidden. New conditions -- Next charge <= / >= X sec, No pet / Pet dead, enemy target-debuff checks. Rotation Debug shows live charges + seconds and cooldown timers per ability.",
    } },
    { "0.5.17", {
        "Beast Mastery -- the pet check is now editable list lines at the top of both ST and AoE (Call Pet if you have no pet, Revive Pet if it's dead), instead of a hidden guardian. Same behavior -- shown before everything else -- but now you can see and reorder them in the condition editor. Added No pet / Pet dead as conditions you can use on any line.",
    } },
    { "0.5.16", {
        "Beast Mastery -- pet check. If your pet is dead or missing, PRIO now shows Revive Pet / Call Pet before anything else -- a guardian that runs in and out of combat and can't be edited away, since your whole rotation depends on having a pet.",
        "Empowered Kill Command now keys on the Nature's Ally buff (not the talent), with a plain Kill Command fallback beneath it so Kill Command still fires on cooldown when the buff isn't up.",
    } },
    { "0.5.15", {
        "Beast Mastery -- fixed the 'no Nature's Ally talent' Kill Command condition. It was pointing at the Nature's Ally buff ID instead of the talent node, so it showed '--' in the condition editor and didn't resolve. It now uses the correct talent (1273126) and reads as 'Nature's Ally', so the plain Kill Command line correctly applies only on builds that don't take Nature's Ally.",
    } },
    { "0.5.14", {
        "Beast Mastery -- Pack Leader default lists updated to the tuned in-game version. Single-target and AoE now ship the hand-tuned Pack Leader priority: Focus-gated spenders (shown only when affordable), the Howl / Nature's Ally Kill Command split with last-charge banking before Bestial Wrath, Wild Thrash right after Bestial Wrath and on cooldown, Bestial Wrath held for Wild Thrash / Beast Cleave, and Hunter's Mark upkeep. Reset a mode to default to pick these up if you've customized.",
    } },
    { "0.5.13", {
        "Beast Mastery -- Hunter's Mark is now maintained on your target. PRIO reapplies Hunter's Mark when the target is missing the 3% damage-taken debuff (e.g. after a target swap), reading it from your Cooldown Manager's Tracked Buffs.",
        "Fixed the Beast Cleave tracking ID (now 115939). The previous ID never matched what the game tracks, so the AoE 'keep Beast Cleave up' lines couldn't read it -- they work now. Make sure Beast Cleave is on your Cooldown Manager (it shows as a Tracked Bar) so Wild Thrash refreshes it.",
    } },
    { "0.5.12", {
        "Beast Mastery -- unaffordable spenders are shown dimmed, not hidden. When you can't yet afford Kill Command / Cobra Shot / Wild Thrash, the icon stays in place slightly desaturated (a 'press this once your Focus is up' cue) instead of vanishing. It uses the game's clean insufficient-power flag, so it's exact even though the Focus bar is secret in combat -- the dim clears the instant you have the Focus.",
    } },
    { "0.5.11", {
        "Beast Mastery -- Focus spenders are now gated on affordability. Kill Command, Cobra Shot, and Wild Thrash (plus the other Focus costs) only show when you can actually afford them. Focus is secret in combat, but the game exposes a clean 'insufficient power' flag even so -- so this is exact, with no guessing: the spender appears the instant you have the Focus and stays hidden when you don't.",
    } },
    { "0.5.10", {
        "Fixed the charge count reading 1 when it was actually 0. The count was derived from WoW's 'usable' flag, which ignores cooldown/charges and reads true even at 0 charges. It now uses the charge-aware cooldown -- the same signal that makes Lava Burst castable at 1/3 but not 0/3 -- so Barbed Shot / Kill Command show the true 0/1/2. Applies to every 2-charge spell.",
        "Beast Mastery charge maintenance now gates on the readable count, not a predicted timer. The recharge TIME is fully secret in combat (confirmed: both game reads come back blank), so 'about to cap' is simply 'at 2 charges' -- exact and drift-free. Rotation Debug shows the true count and, out of combat, the recharge; in combat it says 'recharge secret'.",
    } },
    { "0.5.9", {
        "Diagnostic build for charge-timer drift. The charge-spell rows in /prio rotdebug now show the count + its source (clean/secret) and both readable recharge candidates -- dur: (charge-duration object) and cd: (spell cooldown) -- so we can see which reads survive combat and fix the drift at the source. '--' means that read is currently secret/unavailable.",
    } },
    { "0.5.8", {
        "Rotation Debug (/prio rotdebug) now shows charges and cooldown seconds inline. The Abilities section reads e.g. 'on CD / unusable  1/2  next 3.2s (pred)' for charge spells (Barbed Shot, Kill Command) and '28s left' for tracked cooldowns (Bestial Wrath) -- tagged live/pred so you can see the recharge source and watch the 'about to cap' and Bestial Wrath timers where you're already looking.",
    } },
    { "0.5.7", {
        "Beast Mastery -- charge timer re-anchors on every charge gained. On top of the haste-correct prediction, the moment Barbed Shot / Kill Command actually gains a charge (a readable event even in combat) PRIO restarts the next-charge timer from that instant -- so any accumulated drift, including from effects it doesn't model (e.g. Pack Mentality's beast-summon reduction), is wiped clean each recharge cycle. The 'about to cap' call should now stay accurate all fight.",
    } },
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
