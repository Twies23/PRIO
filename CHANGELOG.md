# PRIO Changelog

## 0.3.7
**Advisory alerts — and a smarter Keep It Rolling.**
- New alert banner: PRIO can now surface a pulsing prompt above the strip for a decision it can't make for you. First use: **Keep It Rolling**. Since only you can see whether your roll is a stage 3 / Jackpot worth extending, PRIO no longer auto-presses it — instead, when Keep It Rolling is ready on a confirmed good roll (stage 2+), it shows *"Keep It Rolling ready — check your roll & extend if it's strong,"* and leaves the call to you.
- (Requires Roll the Bones tracked as a bar in your Cooldown Manager — same as the reroll logic.)

## 0.3.6
**Outlaw Roll the Bones — sharper roll detection using Opportunity.**
- Sinister Strike awards a combo point per strike and, on its double-strike, grants Opportunity. PRIO now reads that Opportunity gain to know whether the strike doubled — so it interprets the combo-point yield exactly: a yield equal to the number of strikes means no Roll-the-Bones bonus (stage 1 → reroll), and more means the roll is good (stage 2+, now positively confirmed, not just assumed).
- Keep It Rolling now fires once a good roll is **confirmed** (stage 2+) rather than on any active roll, so it never wastes on a stage-1 roll you're about to reroll. (Stage 3 itself isn't readable — it only speeds up secret cooldowns — so stage 2+ is the trigger.)

## 0.3.5
**Outlaw Roll the Bones — figure out the roll from combo points.**
- The stage buffs can't be read directly in combat, so PRIO now *infers* the roll from what it does: stage 2 makes Sinister Strike generate an extra combo point, so a Sinister Strike that gives only its base 1 combo point proves you're on a stage-1 roll → reroll. Anything higher is kept. It can never mistake a good roll for a bad one (stage 2+ never gives just 1), and Roll the Bones' long cooldown gives it plenty of time to settle before a reroll is even available.
- Keep It Rolling runs on cooldown while any roll is active (the stage-3 breakpoint isn't readable).
- Rotation Debug shows the inferred roll state ("RtB stage2 (inferred)": reroll / assume good).

## 0.3.4
**Outlaw Roll the Bones — read the stage from the bar's name.**
- The three stage buffs all share one Cooldown Manager bar (so they always read as "a roll is active"), and reading them by ID is blocked in combat. PRIO now reads the **name the Roll the Bones bar is showing** ("One of a Kind" / "Double Trouble" / "Triple Threat") to know the real stage — so reroll and Keep It Rolling finally fire on the right stage. **Track Roll the Bones as a Bar in your Cooldown Manager** for this to read.
- New `/prio rtbframe` dumps the Roll the Bones bar's icon and text so the stage read can be verified in combat.

## 0.3.3
**Outlaw Roll the Bones — correct 12.1 model.**
- In 12.1 Roll the Bones grants a single named buff whose identity is the stage — **One of a Kind** (1), **Double Trouble** (2), **Triple Threat** (3) — and the tracked bar only ever reads as one stack. PRIO now reads the stage from which named buff is active, so the reroll (stage 1 or less) and Keep It Rolling (stage 3) lines work correctly.
- Buff conditions now fall back to reading a buff **directly** when the Cooldown Manager doesn't track it — this is what lets the named Roll the Bones buffs (and other untracked buffs) drive the rotation.
- Rotation Debug shows all three stage buffs and a direct-read test for each, so you can confirm the stage reads in combat.

## 0.3.2
**Outlaw Rogue — first pass (work in progress).**
- Outlaw is now a recognised spec with a Trickster single-target and AoE priority. Combo points read exactly (they're a discrete resource), so finisher and builder combo-point gates are precise.
- **Rotation Debug window** (`/prio rotdebug`) now works for Outlaw and shows, live, what your Cooldown Manager reports active for each buff (Roll the Bones stage, Slice and Dice, Blade Flurry, Opportunity, …), your combo points, and a direct read test for the Roll the Bones buffs the Cooldown Manager doesn't track.
- `/prio myauras` gained a direct-ID probe: `/prio myauras <id> <id>` (or `/prio rtb`) tests specific auras via a path that can survive combat, since listing all buffs is blocked while fighting.
- Still to come: verified 12.1 Roll the Bones buff IDs, Fatebound tuning, and Energy pooling.

## 0.3.1
Groundwork for **Outlaw Rogue** support.
- New `/prio myauras` (alias `/prio buffs`) command — lists every buff currently on you with its spell ID and whether the game lets PRIO read it in combat. This is how we map auras the Cooldown Manager doesn't track (like the individual Roll the Bones buffs) so the upcoming Outlaw rotation can read them.

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
