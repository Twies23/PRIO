# PRIO Changelog

## 0.2.33 (alpha)
- **Added Tigereye Brew (1261724) to Windwalker's buffs** — selectable in buff conditions, with a Debug row and a /prio setup tracking entry.


## 0.2.32 (alpha)
- Added a live "Blackout Kick!" row to the Debug window.


## 0.2.31 (alpha)
- **Added the "Blackout Kick!" proc (116768) to Windwalker's buffs**, so it's selectable in buff conditions. Track it via /prio setup for the condition to evaluate.


## 0.2.30 (alpha)
- **New "Energy near cap" condition** (and its inverse) — a simple boolean, true when predicted Energy is at/above the threshold (100 by default). Cleaner than a percentage for "Tiger Palm to avoid capping" lines. Debug flags NEAR CAP on the Energy row.


## 0.2.29 (alpha)
- **Energy prediction leans slightly conservative (+10%)** so it errs on the high side — you'll dump Tiger Palm a touch early rather than risk wasting regen at cap.


## 0.2.28 (alpha)
- **Energy prediction now scales with haste.** Windwalker's Energy regenerates faster with haste, so the flat 10/sec was reading a bit low; the estimate now uses 10/sec × (1 + haste) × Ascension, which tracks your real bar.


## 0.2.27 (alpha)
- **Full Energy prediction (Windwalker).** Energy is secret even as a percent, so PRIO now dead-reckons it: a fixed 10/sec regen (+10% with Ascension) integrated against your real max, re-anchored to the usable-ability checkpoints, synced to the real value whenever it's readable, and dropped the moment you cast a spender. This tracks Energy all the way to your cap — so "Energy % ≥ N" avoid-capping lines work. Debug shows the predicted value, %, and checkpoint floor.


## 0.2.26 (alpha)
- **Energy is now readable as a percentage** (via the game's secret-safe percent path — the same one EllesmereUI's bars use), so PRIO can see Energy all the way to your real cap, not just up to Tiger Palm's cost. The look-ahead now seeds from your actual Energy %, and there's a new **"Energy % ≥ / ≤"** condition for "Tiger Palm to avoid capping" lines. Debug shows live Energy %.


## 0.2.25 (alpha)
- **Energy checkpoint model (Windwalker).** Energy is unreadable, but an ability's usable flag flips on at its Energy cost — so "Crackling Jade Lightning / Paralysis usable" means Energy ≥ 20, "Tiger Palm usable" means ≥ 60 (55 with Inner Peace), etc. PRIO takes the highest such threshold as a floor on your Energy and spends it across the look-ahead, so it won't queue a Tiger Palm you can't afford. Debug shows the estimate.
- **Combo Strikes is now a hard rule for Monk** — PRIO never recommends the same ability twice in a row (it won't be relaxed to fill a slot).
- **The queue no longer papers over gaps by breaking rules.** It walks the priority list with full state carried forward (Chi/Energy spent + generated, buffs, cooldowns, last cast) so a lower line becomes the next pick — instead of ever suggesting an ability whose condition is false.


## 0.2.24 (alpha)
- **Condition editor only offers choices that work.** The target dropdown is now filtered by condition type: "Has buff / Missing buff / Buff stacks" list only buffs (not abilities), "Off/On cooldown / Usable / Just cast" list only abilities, and "Buff time left" lists only duration-tracked buffs (Zenith on Windwalker).
- **Condition types are filtered per spec.** Shaman-only types (MotE up/down, SK stacks) no longer show for Monk or other specs that don't use them.
- **Adding an ability no longer scrolls the priority list back to the top.** (The earlier fix missed the case where the list grows.)


## 0.2.23 (alpha)
- **New condition: "Buff time left ≥ / ≤ N seconds"** — for gating on a buff window winding down. Buff durations are secret in combat, so for Windwalker's Zenith it's timed from the cast (15s, +5s with Drinking Horn Cover) and counted down. This makes a real "spend before Zenith ends" rule possible instead of the old buff-presence approximation. Debug shows a live "Zenith time left".


## 0.2.22 (alpha)
- **Cleanup.** Removed the dead Energy look-ahead model (Energy is secret; the clean "insufficient power" flag does the job) and the abandoned Cooldown-Manager charge-scraping code, and dropped the redundant "Energy" Debug row. No behavior change — the Tiger Palm Energy gate and Zenith charge tracking both stay.


## 0.2.21 (alpha)
- **Tiger Palm is no longer recommended when you can't afford its Energy.** The Energy bar is secret, but the game's "insufficient power" flag reads clean in combat — PRIO now gates on that, so an Energy spender you literally can't cast is skipped in favor of one you can.
- **Debug "Zenith charges" now shows a real count while recharging** (e.g. 1 / 2) instead of "?", labeled with its source (at max / usable / predicted) and the time to the next charge.


## 0.2.20 (alpha)
- **Charges are now read EXACTLY and secret-safely, not just predicted.** Using the same technique as EllesmereUI's Cooldown Manager: the game's charge "recharge-active" flag is readable and is false only at max charges, and combining it with the spell's usable state pins the exact count (a 2-charge spell like Zenith resolves cleanly to 0 / 1 / 2). Prediction is now only a fallback for the middle counts of 3+ charge spells, and it's clamped by the real "below max" signal so it can never report full when it isn't. So "Zenith if Charges ≥ 2" is now exact. The Debug "Zenith charges" row shows the count, its source, and the time to the next charge.


## 0.2.19 (alpha)
- **Zenith charge tracking now uses prediction (the same method as Lava Burst), which actually works.** Reading the Cooldown Manager frame was unreliable (it renders the recharge timer, not a clean count). PRIO now syncs Zenith's charges to the real value out of combat and models them in combat (spend on cast, recharge on a timer), so "Zenith charges" and the Charges ≥ condition read correctly.


## 0.2.18 (alpha)
- **Zenith charge tracking fixed.** The charge reader was picking up the recharge timer instead of the count; it now only accepts a number within the real max charges, so "Zenith charges" reads correctly in the Debug window (and the Charges ≥ condition with it). Zenith must be in your Cooldown Manager.
- **Diagnostic: "Tiger Palm usable" row** added to the Debug window. Energy is a fully secret value (unreadable even out of combat), so PRIO can't gate on Energy directly — this row shows whether the game's usability flag still exposes "not enough Energy", which would give us another way in.


## 0.2.17 (alpha)
- **The priority list no longer jumps to the top when you add, move, or remove a row.** It keeps your scroll position.
- **Windwalker: Tiger Palm won't be recommended when you can't afford its Energy.** The engine now reads your Energy and predicts it across the look-ahead queue, so it stops suggesting an Energy spender you can't cast and recommends a button you can.
- **The queue no longer runs out early.** If the strict priority can't fill a slot, PRIO relaxes soft rules (Combo Strikes, then the row's condition) but still only ever suggests a castable ability — so you always get a full Now + Next set.
- **Debug window: added live Energy and Zenith charges** (the values the new gates read), and **fixed the Economy section overlapping** the rows below it.


## 0.2.16 (alpha)
- **"Charges ≥ / ≤" is now a number picker, not an ability picker.** It counts the charges of the line's own ability, so you just set the number (e.g. Zenith → Charges ≥ 2).
- **Fixed conditions that need both a spell and a number** (e.g. "Buff stacks ≥ N"): the editor now shows both the buff picker and the number stepper. Previously only the buff picker appeared and the number couldn't be set.


## 0.2.15 (alpha)
- **"Charges ≥ / ≤" now reads live charges straight from the Cooldown Manager.** Instead of predicting charges with a hardcoded recharge (the old 0.2.14 approach), PRIO now reads the real charge count Blizzard renders on the tracked cooldown frame — secret-safe and exact, for any charge ability you track. Track Zenith in the Cooldown Manager (see /prio setup) and a "Zenith if Charges ≥ 2" rule just works.


## 0.2.14 (alpha)
- **Windwalker: "Charges ≥ / ≤" now works for Zenith.** In-combat charge counts are hidden by the game, so the condition only evaluates for abilities PRIO actively predicts. Zenith is now charge-tracked (2 charges), so a rule like "Zenith if Charges ≥ 2" fires correctly. Its recharge time is learned automatically out of combat.


## 0.2.13 (alpha)
- **Windwalker: Zenith is now a castable, pickable ability.** It was missing from the ability list, so you couldn't add it to your priorities — now you can slot it in via Options → Priorities. (Uses the Zenith buff ID; if `/prio spells` shows it wrong, let me know the correct cast ID.)


## 0.2.12 (alpha)
- **Windwalker rebuilt to the current Icy Veins priorities, split by hero tree.** PRIO now keeps separate Shado-Pan and Conduit of the Celestials lists (ST + AoE) and auto-selects based on your hero talents (Celestial Conduit known = Conduit). Options → Priorities has a "Hero list to edit" switch so you can customize each independently.
- **Removed the retired Storm, Earth, and Fire.**
- **Rushing Wind Kick** now only fires when its "available" proc buff (1250554) is up.
- **Chi prediction** is now cost/generation-accurate (Zenith/Combo Breaker/Dance discounts, Energy Burst / Airborne Rhythm / Obsidian Spiral generation), so the queue looks ahead on real Chi.
- Reset your Windwalker lists to default to pick all this up. New tracked auras to add (via /prio setup): Zenith, Unbroken Rhythm, Rushing Wind Kick, Touch of Death.


## 0.2.11 (alpha)
- **Untracked buffs now fail their row instead of silently passing.** Previously a line gated on a buff you hadn't tracked (or aren't specced into) read as "open" and effectively passed — now it fails (red dot), so a Combo Breaker / Dance of Chi-Ji / Heart of Jade Serpent line won't be treated as fine when the buff can't actually be read. Track the buff (via /prio setup) to make it evaluate.
- **Windwalker Combo Strikes** is now modeled engine-wide: PRIO never queues the same ability twice in a row (the safety net still prevents a blank).
- Fixed Windwalker buff IDs: **Dance of Chi-Ji 325202** (was 325201) and **Combo Breaker 137284** (was 137384).


## 0.2.10 (alpha)
- **New condition types: Resource (>= / <= N) and Usable / Not usable.** Resource reads your discrete class power (Chi, Holy Power, Combo Points, Runes, Soul Shards, Arcane Charges, Essence) — the secret-safe ones. Usable/Not usable references another ability's `IsUsable` state.
- **Windwalker** now uses Chi thresholds on its low-Chi lines: Zenith Stomp and a Tiger Palm builder gate on Chi ≤ 2, and the high-Chi Spinning Crane Kick gates on Chi ≥ 5. (Reset your Windwalker lists to default to pick this up.)


## 0.2.9
- **New condition types: Buff stacks (>= / <= N) and Charges (>= / <= N)** — read secret-safe from the Cooldown Manager, so single-spec APLs that key off stacks now work.
- **Arms rebuilt to the Slayer priority** using them: Execute at 2 Sudden Death, Cleave at 3 Collateral Damage, pre-Bladestorm Execute under 3 Imminent Demise, Overpower at 2 charges, Heroic Strike. Colossus/talent abilities fold in automatically.
- **In-app changelog** — open it with /prio changelog.
- Arms Setup checklist now lists the stack buffs to track (Sudden Death, Collateral Damage, Imminent Demise, Executioner's Precision).


## 0.2.8 (alpha)
- Corrected Arms buff IDs from the tracked dump: **Sudden Death is 29725** (was 52437) — this also fixes the Execute-on-Sudden-Death condition. Stack probes now cover Collateral Damage, Executioner's Precision, and Imminent Demise; removed the untrackable Colossal Might.


## 0.2.7 (alpha)
- Fixed saving profiles (the name popup edit box wasn't being read on some clients).
- Added secret-safe **buff stack-count reading** (via the Cooldown Manager, like the pandemic read). Arms Debug now shows Sudden Death / Collateral Damage / Colossal Might stack counts — a test toward stack-based conditions.


## 0.2.6 (alpha)
- **Profiles reworked** to the standard dropdown style: a dropdown to load a profile (applies on select), a "Save current as…" popup for naming, and a Delete button. Fixes the name box that trapped your cursor.


## 0.2.5 (alpha)
- Applying a profile (or the recommended preset) now refreshes the open options window immediately, so the change is visible right away.


## 0.2.4
Promotes the 0.2.3 work to the main release: the editing-list/live-mode split, Elemental Flame Shock assume-on-cast and Voltaic talent handling, and the rebuilt Windwalker Monk. (Devourer remains an early scaffold pending in-game ID verification.)


## 0.2.3 (alpha)
- **Priorities page: separate "Editing list" from "Live mode"** — pick which list (ST/Cleave/AoE) you're editing without changing what's actively shown, so you can tweak any list mid-combat.
- **Elemental:** after you cast Flame Shock or Voltaic Blaze, PRIO assumes Flame Shock is up for ~4s (covers the Cooldown Manager read lag), self-correcting if the target was immune.
- **Elemental Cleave/AoE:** Flame Shock is kept up manually only on non-Voltaic builds; Voltaic builds use Voltaic Blaze on cooldown to apply it.
- **Windwalker:** rebuilt to the 12.1 Conduit + Shado-Pan priority with correct spell IDs (Zenith Stomp, Rushing Wind Kick, Slicing Winds) and buff-driven conditions.


## 0.2.2
- Promotes the recent work to the main release: **Windwalker Monk** support, the profile manager, the "defaults changed" login prompt, condition text export, and the Arms/MM review. (Devourer is included as an early scaffold that still needs in-game spec/spell ID verification.)


## 0.2.1 (alpha)
- **New spec: Windwalker Monk.** Chi is readable so spenders gate on real Chi; Combo Strikes (never repeat an ability) is modeled from your cast history. Covers Shado-Pan + Conduit of the Celestials.
- **New spec: Devourer Demon Hunter (scaffold).** Structure is in place, but as a brand-new spec its spec ID and most spell IDs need in-game verification (see below) before it works fully.


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
