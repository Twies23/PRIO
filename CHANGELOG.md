# PRIO Changelog

## 0.5.6
- **Beast Mastery — Barbed Shot / Kill Command "about to cap" is now haste-correct.** The game's own charge-recharge read turns out to be secret in combat, so PRIO predicts the next-charge time from the recharge base and your **live haste** (base ÷ (1 + haste%)) rather than a fixed duration — the timer no longer drifts as your haste changes. (Barbed Scales and the other cast-triggered reductions are already folded in; Pack Mentality's occasional beast-summon −4s is the only remaining unmodeled nudge.)

## 0.5.5
- **Beast Mastery — fixed Barbed Shot / Kill Command charge-timer drift.** The "next charge in Xs" (and the "about to cap" Barbed Shot check) now reads the game's own recharge — which is correctly hasted — instead of a fixed-duration prediction that drifted with haste and unmodeled cooldown reductions. The cast-based prediction stays only as a fallback.
- Rotation Debug tags each charge row **(live)** or **(predicted)** so you can see whether that readable recharge value stays available in combat or goes secret.

## 0.5.4
- **Beast Mastery — cooldown-reduction modeling.** The predicted Kill Command / Barbed Shot recharge — and so the "Next charge ≤ X sec" gates and the Rotation Debug seconds — now account for the cast-triggered cooldown reductions: Cobra Shot −1s Kill Command, War Orders −3s Kill Command (on Barbed Shot), Barbed Scales −2s Barbed Shot (on Cobra Shot), and Killer Cobra's Kill Command reset during Bestial Wrath. "Next charge in Xs" now reflects how fast they actually come back. (Pack Mentality's beast-summon and Master Handler's per-tick reductions are periodic, so they stay handled by the live charge read.)

## 0.5.3
- **Beast Mastery — quantified, tunable timing.**
  - New condition **"Next charge ≤ / ≥ X sec"** for charge spells (Barbed Shot, Kill Command) — the seconds until the next charge lands. The plain "Cooldown" condition can't show this (it reads 0 while you still have a charge banked).
  - Bestial Wrath's cooldown now reads in combat, so **"Cooldown ≤ X sec"** on Bestial Wrath is your editable *"Bestial Wrath in less than X seconds"* gate.
  - Barbed Shot now fires at 2 charges **or when the next charge is within ~1.5s** (about to cap), not only at the hard cap.
  - Rotation Debug shows Kill Command / Barbed Shot as **charges + seconds to next**, and Bestial Wrath as **cooldown seconds left**.
- **Cobra Fang is the 4-set tier bonus** — its tracking is now optional, so Setup won't flag it red without the set (those lines stay inert until you have it).

## 0.5.2
- **Beast Mastery: simplified to ST and AoE only.** Dropped the separate Cleave tier — the AoE list now covers 2+ targets, so there are just two mode tabs to tune.

## 0.5.1
**Beast Mastery Hunter — full rotation rebuild (12.1 Midnight).** The placeholder Beast Mastery lists are replaced with a complete, tuned build for both hero trees — **Pack Leader** (default) and **Dark Ranger** — each with its own single-target, cleave, and AoE lists you can customize.
- **Reads your real proc signals:** Howl of the Pack Leader is detected from the **Kill Command glow** (so the empowered Kill Command is suggested the instant it lights up), Cobra Shot is prioritized at **4 stacks of Cobra Fang**, and Nature's Ally empowers Kill Command.
- **Bestial Wrath cooldown is tracked** (30s with The Beast Within), so Barbed Shot is refreshed right before it — keeping Frenzy up across the burst window without needing to see the pet buff.
- **AoE** builds and holds Beast Cleave with Wild Thrash (which replaced Multi-Shot); Dark Ranger opens Beast Cleave with Black Arrow and uses the Withering Fire / Wailing Arrow window.

## 0.5.0
Fifth stable release — headlined by a **redesigned Setup** and the finalized **Outlaw Trickster** lists. Everything since 0.4.11.

**Setup (`/prio setup`) rebuilt**
- General checks up top (**Cooldown Manager active**, nameplates), then a **two-column** layout: **Ability cooldowns** (left, validation — for your own cooldown display; PRIO reads cooldowns directly) and **Auras to add** (right, *required* — PRIO reads buffs only from the Cooldown Manager).
- **Auto-derived from your real rotation** — the required auras come straight from the priority conditions (default *and* custom), so it can't miss one and doesn't list buffs the rotation never reads. **Glow-driving abilities** (e.g. Pistol Shot for Opportunity) are flagged required.
- Status updates **live** as you edit the Cooldown Manager; **re-opens after each update** to re-verify; rows no longer overlap; build-specific auras (4-set) show as optional.

**Outlaw**
- Finalized Trickster default ST/AoE lists; corrected two tracked-aura IDs (Loaded Dice, Flawless Form).

## 0.4.16
- **Setup: glow-driving abilities are now flagged as required.** Some reads use an ability's proc *glow* (e.g. Outlaw reads Opportunity from Pistol Shot's glow), which only lights up when that spell is present — so those show in the Abilities column tagged **(glow)** and turn red until added, instead of being merely recommended. Columns reframed: left is **"ability cooldowns — validation"** (confirm your cooldowns are tracked for your own display), right is **"auras to add to your Cooldown Manager"** (required — PRIO reads these).
- Dots update **live** as you add/remove spells in the Cooldown Manager, and on an update the Setup no longer stacks on top of the changelog (it opens after you close it).

## 0.4.14
- **Setup polish:** the intro text no longer overlaps the first row (rows start below it now), and a build-specific aura like **Fang Strike (4-set)** shows amber "optional" instead of red "required" when you don't have the set — so non-tier-set players aren't told to track something they don't need.

## 0.4.13
- **Setup redesigned into a cleaner, clearer checklist.** `/prio setup` now shows general checks up top (Cooldown Manager active, nameplates), then a two-column layout: **Abilities** on the left (add to your Cooldown Manager's Essential/Utility — recommended, so your cooldowns show) and **Auras** on the right (add to Tracked Buffs — *required*, PRIO reads these). Rows grow to fit their text (no more overlap), and it drops the misleading entries that weren't actually needed (e.g. the "Between the Eyes debuff window"). It also **re-opens after each update** so you can re-verify — handy since an update can add a newly-required aura.
- **"Apply recommended settings" now enables the opener and the primary glow.**

## 0.4.12
- **Setup (`/prio setup`) is now robust — it can't miss a required aura.** Two additions: a **"Cooldown Manager active"** check at the top (PRIO reads all your buffs/debuffs from Blizzard's Cooldown Manager — without it, it's blind in combat, and now you're told so directly), and the checklist now **auto-derives every aura your rotation actually gates on** from the priority lists themselves and lists any that were missing. This closes gaps like Outlaw's Adrenaline Rush, and Elemental's Stormkeeper / Purging Flames, that the hand-written lists had omitted. Nothing existing was removed — only missing items added.

## 0.4.11
- **Outlaw — finalized Trickster default lists.** Two tuning tweaks: Killing Spree during Adrenaline Rush now also requires AR to be on cooldown (fires inside the AR window), and single-target **Stealth** only shows when you're **not already stealthed** (AoE keeps it on always). Reset to default (per mode) to pick these up if you've customized. Also corrected two tracked-aura IDs (Loaded Dice → 256171, Flawless Form → 441326, the buff auras rather than the talents).

## 0.4.10
Fourth stable release — full **Outlaw Fatebound** support and a big round of Elemental & Outlaw fixes. Everything since 0.4.0.

**Outlaw Rogue**
- **Fatebound hero tree** — a Trickster / Fatebound split, auto-selected from your talents (like Arms' Slayer / Colossus). Both share tuned ST/AoE defaults, each still customizable per hero.
- **New tuned default lists** — a Stealth opener, supercharge-aware finishers, Killing Spree during Adrenaline Rush, the 4-set free Dispatch, and a Fatebound **Deal Fate** line that self-activates only on that talent.
- **Supercharged Combo Points** (Supercharger talent) tracked, with new "Supercharged CP ≥ / ≤ / = N" conditions.
- **Finishers fire at the combo points you set**, not only at max — the game reports a finisher's cost as its maximum, which was overriding your own condition (0 CP still correctly blocks).
- **Stealth** added as an ability; new **Stealthed / Not stealthed** condition (covers Stealth, Vanish, Shadow Dance).

**Elemental Shaman**
- **Spenders gate on the game's readable insufficient-power flag** instead of predicted Maelstrom — exact, no drift; fixes both showing too early and being held back while you overcap.
- **Flame Shock's passive (per-tick) Maelstrom** is now counted and **Chain Lightning scales per target**, so the prediction tracks your real Maelstrom far better.
- **4-set (Ophidian Oracle) free spender** read from the Cooldown Manager glow — not withheld, and not mispredicted as draining Maelstrom.

**Engine & editor**
- **New "=" (equals) operator** for count conditions — Combo Points/Resource, Opportunity, Supercharged CP, Buff stacks, Charges, and Enemies.
- **Fixed the Rotation Debug window** showing some "≥" / glowing / usable conditions' pass/fail inverted (display-only; the rotation itself was always correct).

## 0.4.0
Third stable release — headlined by full **Outlaw Rogue** support, plus engine improvements that help every spec. Everything since 0.3.0.

**Outlaw Rogue (Trickster)**
- Complete single-target and AoE priorities and the opener.
- **Roll the Bones read exactly.** PRIO figures out your roll's stage from combo-point *timing* — a stage-2+ roll makes Sinister Strike generate an extra combo point, landing an instant beat before a double-strike does — so it rerolls a stage-1 roll and never a good one.
- **Opportunity tracked (0/3/6)** by detecting Sinister Strike double-strikes from that same timing, driving the Pistol Shot lines. New adjustable "Opportunity ≥ N" condition.
- **Keep It Rolling** is a movable advisory alert (only you can tell if a roll's a 3/Jackpot worth extending); the free **Dispatch** keys off the 4-set **Fang Strike** buff.

**Engine (all specs)**
- The queue now predicts combo-point generation, so the upcoming icons build toward a finisher and back down.
- Abilities unusable *only* because you're low on a filling resource (Energy, etc.) keep showing — you'll press them the instant it regenerates — instead of collapsing to the cheapest filler.
- Fixed a resource-cost check that compared an ability's Energy cost against a different resource (combo points), and a couple of default conditions that opened blank in the editor.
- The advisory alert banner can be dragged to its own spot (unlock the display).

## 0.3.0
Second stable release — everything since 0.2.0, headlined by full **Arms Warrior** and **Windwalker Monk** support and a much deeper secret-value engine.

**Specs**
- **Arms Warrior — rebuilt end to end.** Auto-detected **hero-tree split** (Slayer / Colossus); separate **ST** and **AoE** priority lists, each with an **execute-phase variant that swaps in automatically** in execute range; the Cleave tier is dropped in favour of a configurable **AoE-at-N** threshold. Tuned Slayer defaults, ST/AoE openers.
- **Windwalker Monk — full 12.1 rebuild.** Auto-selected **Shado-Pan / Conduit of the Celestials** hero split (ST + AoE), accurate Chi cost/generation, **Combo Strikes** (never repeat an ability), and tuned lists.

**Reading the game under the secret-value API**
- **Proc-glow reads** stand in for stack counts the game hides (Arms: Sudden Death = Execute glow, Imminent Demise 3 = Bladestorm glow, Collateral Damage 3 = Cleave glow).
- **Predicted stack counters** for stacks with no readable signal (Executioner's Precision: +1 per Execute, reset by Mortal Strike).
- **Execute-range detection** — target health is secret, so it's inferred from Execute being usable without a proc, **latched** to ride rage dips, and drives the auto-swap to Arms' execute lists.
- **Energy prediction (Windwalker)** dead-reckoned to your real cap (haste-scaled, checkpoint-anchored) so avoid-capping lines work; **charges, cooldowns, buff durations and pandemic windows** read exactly where the game exposes them and predicted secret-safely where it doesn't.
- **Keeps predicting during channels** (e.g. Bladestorm) instead of collapsing to a filler.

**Condition editor**
- New types: **Buff stacks**, **Charges**, **Resource ≥/≤**, **Usable**, **Buff time left**, **Cooldown ≥/≤**, **Energy % / near cap**, **Enemy has/missing debuff**, and spec-specific **named presets** (e.g. "Sudden Death up") that hide the raw glow/stack mechanics. Type/target lists are filtered so you only see choices that work.

**Openers**
- **Configurable**, split into **ST and AoE** (picked by pull size), edited on their own page. They now **show before the pull** and flow into the fight, with an **"only when all cooldowns are ready"** gate and a gold **▶ OPENER** badge while playing.

**UI & tooling**
- **Clickable, movable mode buttons** (Auto / ST / AoE) to hot-swap in combat; **Rotation Debug** window (minimap middle-click or `/prio rotdebug`) exposing the raw signals the rotation reads; per-spec **mode tabs**; reworked **Profiles**; corrected per-spec **Setup** checklists; and the **changelog auto-opens** on a new version.

**Fixes & robustness**
- The queue never goes short and never suggests an ability whose condition is false; cooldown abilities (Cleave) no longer stack as fake fillers; untracked buffs fail their row instead of silently passing; the priority list keeps its scroll position while editing.

Also includes an early **Devourer Demon Hunter** scaffold (pending in-game ID verification).


## 0.2.0
First stable release. Configurable rotation priority & queue helper for WoW 12.1, working within the secret-value API.
- Specs: **Elemental Shaman**, **Marksmanship Hunter**, **Beast Mastery Hunter**, **Arms Warrior**.
- Priority editor with live pass/fail dots, condition builder, and text export.
- DoT **pandemic-window** refresh (Elemental Flame Shock, Arms Rend) via the Cooldown Manager.
- Per-spec first-time **Setup** checklist, **Profiles**, class-colored UI, and a text-export tool.
- Predicts secret values (Maelstrom/Focus/Rage, charges, procs) and advances the primary while casting.


## 0.1.25
- Fixed the Profiles page buttons rendering as solid blocks with no visible text.
- **Arms:** removed the redundant Warbreaker line — the Colossus Smash button smart-swaps to Warbreaker when talented.
- **Marksmanship:** Black Arrow moved to a low-priority Precise Shots spender, matching the guide.

## 0.1.24
- **Profiles** (Options → Profiles): save your settings and priority lists as named profiles, then apply or delete them. The recommended preset lives here too.
- When a future release changes the default priorities, PRIO now prompts you on login (only if you have customized lists) to reset to the new defaults.

## 0.1.23
- Elemental: Voltaic Blaze in Cleave/AoE now only appears when the **Voltaic Blaze talent is selected**. It was showing even without it because Voltaic Blaze shares an override with Flame Shock (so "is known" read true). Reset Cleave/AoE to default to pick this up.

## 0.1.22
- Fixed conditions showing "?" — old custom lists made before a fix could collapse a nested condition into an empty clause. Condition copy is now recursive, and the pandemic clause reads "in pandemic".
- Priority dots (and the text export) now show a grey **not talented** state for abilities you don't have, instead of a misleading green.
- Elemental tuning: ST drops the separate Voltaic Blaze line (Flame Shock smart-swaps to it); AoE drops Elemental Blast (unused there) and a redundant Chain Lightning; Cleave drops a redundant Chain Lightning. Reset your Elemental lists to default to pick these up.

## 0.1.21
- **Export a priority list as text** — the Priorities page has an Export button (or /prio export). It opens a selectable box you can copy (Ctrl+A, Ctrl+C) with each ability, its condition, and live pass/fail — handy for sharing or annotating.
- Fixed: switching **talent loadouts** is now detected automatically out of combat (previously the talent-based logic only updated when you changed an individual talent).

## 0.1.20
- The condition editor now lists each spec's full set of relevant buffs/debuffs, so you can build lists referencing anything the spec uses even when you aren't talented into it.
- **Arms:** Rend now refreshes in its pandemic window (like Elemental Flame Shock), with a setup checklist and optional Rend pandemic alert.
- **Marksmanship & Beast Mastery:** added first-time setup checklists and their relevant-buff lists.

## 0.1.19
- Fixed the condition editor showing a blank ("—") spell for build-specific buffs (like Purging Flames or Lava Surge) when you aren't talented into them. The dropdown now always lists every aura referenced by the spec's conditions, across all specs.

## 0.1.18
- Fixed the Elemental Flame Shock / Voltaic Blaze default conditions (they used a nested condition group that showed blank in the editor and evaluated incorrectly). They now correctly refresh when Flame Shock is missing or in its pandemic window. If you customized your Elemental list, use "Reset to default".

## 0.1.17
- Elemental: Voltaic Blaze now refreshes Flame Shock in its pandemic window in **single target** (matching Flame Shock), but is cast **on cooldown** in Cleave/AoE, matching the guide. If you've customized your Elemental list, use "Reset to default" to pick this up.

## 0.1.16
- The priority list now shows a **live pass/fail dot** next to each ability, so you can see at a glance whether its condition is currently met (green = passing, red = failing, amber = unreadable).
- Elemental: Flame Shock now always refreshes if it drops off, and only does the early pandemic-window refresh when you're not mid Master-of-the-Elements spend.

## 0.1.15
- Fixed the **close (×) button** on PRIO windows not responding (it was being covered by window content), and gave it a cleaner look that highlights red on hover.

## 0.1.14
- The UI accent is now **class-colored** by default (toggle "Class-colored accent" in Behavior to go back to PRIO green).
- The Setup checklist now has **Apply recommended settings** (a tuned layout preset) and **Customize** (opens the options) buttons.

## 0.1.13
- Added a per-spec **first-time Setup checklist** that auto-opens once per spec: it shows what to configure (tracked auras, enemy nameplates, optional pandemic alerts) with a live status that turns green as you set each one up. Reopen anytime with /prio setup.

## 0.1.12
- Added a one-time tip on login explaining how to enable pandemic-window tracking in the Cooldown Manager (only for specs that use it). Dismiss with "Got it", or re-open anytime with /prio pandemic.

## 0.1.11
- **Flame Shock now refreshes in its pandemic window** (the last ~30%, refresh without clipping) using Blizzard's own pandemic state. New "In pandemic (refreshable)" condition is available in the priority editor for any tracked DoT. Needs the spell's "Pandemic Time" alert enabled in the Cooldown Manager; without it, Flame Shock still refreshes when it drops off.

## 0.1.10
- Re-added a Flame Shock pandemic readout to the Debug window using Blizzard's own pandemic state (secret-safe). Requires enabling the "Pandemic Time" alert for Flame Shock in the Cooldown Manager.

## 0.1.9
- Fixed Lava Surge tracking (was pointing at the passive spell 77756 instead of the buff aura 77762) — the instant-Lava-Burst lines, proc flash, and Lava Burst charge reset now read it correctly.

## 0.1.8
- Removed the experimental Flame Shock pandemic rows from the Debug window — testing confirmed aura durations are hidden in combat, so a true pandemic/refresh window isn't readable. Flame Shock refresh timing continues to use PRIO's own prediction.

## 0.1.7
- **Fixed a flood of Lua errors** when the Debug window was open — the pandemic/aura probes were touching secret values. They're now fully guarded, and the Debug panel can't error out even if a probe fails.

## 0.1.6
- Added `/prio power` — a diagnostic that shows which of your class resources read cleanly in combat, used to validate spec support.

## 0.1.5
- Added the groundwork for **pandemic / refresh windows** — PRIO can now read Blizzard's Cooldown Manager pandemic state for DoTs like Flame Shock.
- Debug window shows live pandemic and aura-timing info to validate what's readable in combat.

## 0.1.4
- **New spec: Enhancement Shaman** (Stormbringer + Totemic).
- Debug window now shows live Maelstrom Weapon / aura details for tuning.

## 0.1.3
- Packaging setup for CurseForge.

## 0.1.2
- **Fixed target counting** so Cleave/AoE actually kicks in: PRIO now enables enemy nameplates for you (it needs them to see the pack). New option to turn that off.
- Debug window shows nameplate status.

## 0.1.1
- **Elemental:** now correctly spends Master of the Elements instead of double-casting Lava Burst.
- **Primary advances while casting** — as you hard-cast, the shown ability moves to your next button.
- **Fixed mode getting stuck in Single Target** in real content.
- **Arms:** Rend no longer locks the priority; Mortal Strike leads single target.
- Debug window is now per-spec.

## 0.1.0
- First release.
- Specs: **Elemental Shaman**, **Marksmanship Hunter**, **Beast Mastery Hunter**, **Arms Warrior**.
- Shows your current ability plus the upcoming queue, with cast/GCD swipes and proc flashes.
- Standalone options UI with a priority editor, a spec-aware Debug window, and a minimap button.
- Priority lists adapt to your talents and hero tree automatically.
