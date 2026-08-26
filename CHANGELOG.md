# PRIO Changelog

## 0.2.65 (alpha)
- **Mode buttons are now movable.** Drag them anywhere while the display is unlocked (drag any button); the position is remembered. They default to just under the strip.
- **Active button keeps white text** on the accent fill (instead of dark), so the selected mode reads clearly.


## 0.2.64 (alpha)
- **Opener "when to use" condition.** Options → Opener now has a condition chip (same editor as the priority lists) that gates whether the opener plays at the pull — on top of the built-in freshness check. Use it for things like "only open if Avatar is ready." Saved with profiles.
- **In-opener indicator.** While the opener sequence is playing, the display title shows a gold **▶ OPENER** badge, so it's obvious you're in the opener vs. the normal priority.


## 0.2.63 (alpha)
- **Clickable mode buttons under the display.** New **Behavior → Mode buttons under display** toggle adds an **Auto / ST / AoE** row beneath the strip (spec-driven — execute variants stay automatic). Click to hot-swap the live mode mid-combat; the active one is highlighted. They're plain indicator buttons, so there's nothing to taint.
- **Removed the duplicate "AoE at N+ targets" control** from the Priorities screen. The **AoE at (enemies)** slider in Behavior is now per-spec (so it actually drives Arms' 2-target default), and is the single place to set it.


## 0.2.62 (alpha)
- **Configurable openers.** New **Options → Opener** page: reorder, add, and remove the steps of the pull sequence per spec, just like the priority lists (steps that aren't known or off cooldown are still skipped automatically). Comes with a **Reset to default**, and your custom opener is saved and restored with your profiles.


## 0.2.61 (alpha)
- **New tuned Slayer default lists.** The Slayer single-target list is rebuilt, and the AoE, ST-Execute, and AoE-Execute lists now share one tuned list. Reset Arms lists to default to pick them up. (Colossus defaults are unchanged — those weren't part of this pass.)


## 0.2.60 (alpha)
- **Arms execute-phase lists, auto-swapped.** ST and AoE each now have an **Execute** variant, and PRIO switches to it automatically when the latched "in execute range" signal is on — Execute becomes the main spender (the bare Execute line self-gates on rage via usability). Out of range it swaps straight back.
- **Dropped the Cleave tier for Arms.** It's now just **ST** (1 target) and **AoE** (2+), and the AoE threshold is **configurable** — Options → *AoE at N+ targets* (default 2). Other specs (Elemental, etc.) keep their ST/Cleave/AoE unchanged.
- The priority editor's mode tabs are now per-spec, so Arms shows **ST / AoE / ST (Exec) / AoE (Exec)** — each list separately editable.
- Reset Arms lists to default to pick this up.


## 0.2.59 (alpha)
- **New "In execute range" detection (latched).** Target health is a secret value, so we can't read "< 35%" directly. Instead we infer it: Execute is only usable in execute range or on a Sudden Death proc, so **usable *without* the proc glow** means you're genuinely in range. Because rage also gates usability, the flag is **latched** — it holds through brief rage dips and only drops after a few seconds out of range (or on target change / combat end). It's exposed as an **"In execute range"** condition and shown live in Rotation Debug's *Execute range* section. Next step: auto-swap to execute-phase priority lists off this signal.


## 0.2.58 (alpha)
- **Rotation Debug: new "Execute range" probe section.** Two rows to figure out whether we can auto-detect execute phase (target below 35%): **Target health %** (shows the value, or `secret / no target` if it's a protected value) and **Execute usable (clean)** (whether Execute's usable flag reads cleanly — it should flip on in execute range). If either reads clean on the dummy, we can build an "in execute range" condition and lift Execute's priority automatically.


## 0.2.57 (alpha)
- **Renamed the debuff conditions to "Enemy has debuff" / "Enemy missing debuff"** — the debuff lives on your target, so the label now says so.


## 0.2.56 (alpha)
- **Arms conditions are now named, meaningful choices.** Instead of exposing a raw "Proc glowing" option, the condition editor offers spec-specific presets that say what they mean: **Sudden Death up**, **Imminent Demise (3)**, **Imminent Demise (<3)**, **Collateral Damage (3)**, and **Exec. Precision (2)**. Each resolves under the hood to the readable glow/predicted-stack signal, so you pick the *meaning* and never have to know that (say) "Execute glowing" stands for Sudden Death. The Arms default lists use these names too.
- **Added "Has debuff" / "Missing debuff" conditions** alongside the buff ones, so target debuffs (like Rend) read naturally in the editor.
- Reset Arms lists to default to pick up the renamed conditions.


## 0.2.55 (alpha)
- **Arms rotation rebuilt around readable proc signals.** Now that the button glows read cleanly, the rotation gates on them instead of stack counts it can't read: **Execute** fires on the **Sudden Death** glow, **Bladestorm** at **3 Imminent Demise** (its glow) during Colossus Smash, and **Cleave** at **3 Collateral Damage** (its glow) in AoE. **Executioner's Precision** has no glow, so it's tracked with a predicted counter — +1 per Execute (cap 2), reset by Mortal Strike — driving the "Mortal Strike at 2 stacks" line. New condition types under the hood: proc-glow and predicted-stacks. Reset Arms lists to default to pick this up.
- Rotation Debug gained a **Predicted stacks** section showing the Executioner's Precision counter live.
- *Note:* the separate sub-35% "execute phase" ordering isn't a distinct mode — execute range is health-gated (secret), so there's no readable trigger to switch to it; the main lists fold Execute in via the Sudden Death glow and usability.


## 0.2.54 (alpha)
- **Added a Cleave proc-glow probe** to the Rotation Debug "Proc glows" section, to test whether Cleave glows at 3 stacks of Collateral Damage — the same glow-as-stack-signal approach we're using for Bladestorm/Execute/Mortal Strike.


## 0.2.53 (alpha)
- **Rotation Debug: new "Proc glows" section.** Shows the spell-activation-overlay (button glow) state for Bladestorm, Execute, and Mortal Strike. This is a different signal than the aura stack count, so it may be readable even when stacks are secret — we're testing whether "Bladestorm is glowing" can stand in for "Imminent Demise at 3 stacks," and likewise for Sudden Death / Executioner's Precision. Each row shows GLOWING / off / secret-na.


## 0.2.52 (alpha)
- **Fixed the Rotation Debug stack-source tag never appearing.** The `appl`/`cdm`/`appl-secret`/`assumed` tag added last version was silently dropped by a Lua multiple-return gotcha (`X and f()` keeps only the first value), so active buffs showed a bare `×N` with no source. It now renders, so you can see at a glance whether a stack count read exactly (`appl`), came from the Cooldown Viewer (`cdm`), or had to be assumed.


## 0.2.51 (alpha)
- **Middle-click the minimap button to open the Rotation Debug window.** The minimap button now has three actions: left-click = options, right-click = main debug window, middle-click = rotation debug window. (Also still available via `/prio rotdebug`.)


## 0.2.50 (alpha)
- **Rotation Debug buff rows now show the stack-count source.** Each active buff shows a small tag after the count telling you where it came from: `appl` (the aura's exact applications value — clean), `cdm` (the Cooldown Viewer's rendered number), `appl-secret` (the applications value is a protected/secret value, so we fell back — shown amber), or `assumed` (active but no readable count, defaulted to 1 — amber). This makes it visible, right in the window, whether stacks like Imminent Demise read exactly or need a different source.


## 0.2.49 (alpha)
- **Fixed buff stack counts reading as x1** when they were actually higher (e.g. Imminent Demise at 3). Stack reads now try the aura's own applications value first — exact when it reads clean — and only fall back to the Cooldown Viewer's rendered number (now scanned more thoroughly) when it doesn't. Added **`/prio stackprobe`**: a diagnostic that dumps, for each tracked buff, the raw applications value (and whether it's a secret value) plus any number the Cooldown Viewer renders — run it in combat with the stacks up to see exactly what's readable.


## 0.2.48 (alpha)
- **New Arms rotation debug window** — open it with `/prio rotdebug` (or `/prio rotation`). It's a focused, second window separate from the main `/prio debug`, showing exactly the raw signals the rotation gates read: for **Cleave, Avatar, Colossus Smash, Execute, Bladestorm, Heroic Strike, Mortal Strike, Overpower, Slam** it shows cooldown-ready + usable state; for **Sudden Death, Imminent Demise, Executioner's Precision** it shows active state + stack count. If a buff shows "untracked," that's the signal to track it (or fix its ID) so the rotation reads it. Built for live rotation tuning.


## 0.2.47 (alpha)
- **Arms warrior now has a per-hero-tree priority split.** Like Windwalker's Conduit/Shado-Pan split, Arms holds two tuned lists and picks one automatically: **Slayer** (weaves Bladestorm during Colossus Smash, spends Sudden Death, uses the Heroic Strike proc) and **Colossus** (casts Demolish inside the Colossus Smash window, no Bladestorm weave). Detection keys on Demolish via a strict talent check, so it won't flip mid-combat and swaps cleanly when you change hero trees. Both lists are separately editable in Options. Reset Arms lists to default to pick this up.


## 0.2.46 (alpha)
- **Chi prediction now handles Obsidian Spiral correctly.** With that talent, Blackout Kick generates a Chi instead of costing one, so it's modeled as a +1 builder (always, not just during Zenith) and is castable at 0 Chi. Talent-gated, so it's inert unless you spec it — meaning the aggressive Blackout Kick! dumps help pool Chi for Fists of Fury once you're in Obsidian Spiral.


## 0.2.45 (alpha)
- **Conduit cleave + AoE default rebuilt to the tuned list** (they now share it — cleave was falling back to the single-target list). Because Blackout Kick! and Dance of Chi-Ji stacks aren't readable, their proc dumps sit high so they're spent aggressively and never overcap. Reset Windwalker lists to default to pick it up.


## 0.2.44 (alpha)
- **Hero-tree detection now keys on Invoke Xuen** (a Conduit-of-the-Celestials ability) via a strict talent/spellbook check. Two fixes: it's a more reliable Conduit-vs-Shado-Pan signal than Celestial Conduit, and it no longer flips to Conduit mid-combat when an ability merely becomes tracked or is temporarily summoned.


## 0.2.43 (alpha)
- **Fixed Rushing Wind Kick being recommended without its proc** in Shado-Pan cleave/AoE. That line was gated only on "no Unbroken Rhythm" (which now correctly passes when you're pre-4-piece); it now also requires the Rushing Wind Kick proc. Reset lists to default to pick it up.


## 0.2.42 (alpha)
- **Fixed the queue going short (fewer than 3 abilities).** Two causes: the look-ahead spent Energy but never regenerated it (so Tiger Palm got permanently locked out mid-queue), and the Energy prediction was a hard gate that, combined with Combo Strikes, could leave a slot blank. Now the look-ahead regenerates ~1 GCD of Energy per slot, and if the strict walk can't fill a slot it relaxes only the *predicted* gates (Combo Strikes, Energy guess) — never the real ones (cooldown, Chi, the row's condition) — so it always fills with something castable.


## 0.2.41 (alpha)
- **"Missing buff" now passes for an untracked/unhad buff** (fixing a logic hole). If a buff can't be read — e.g. Unbroken Rhythm without the 4-piece — "Has buff" fails and "Missing buff" passes, consistently treating it as not up. Previously both failed, which broke "cast X if missing Y" lines for buffs you don't have.


## 0.2.40 (alpha)
- **Conduit single-target default updated to the refined list** — Blackout Kick! stack checks replaced with the boolean proc, plus the tuned ordering. Reset your Windwalker lists to default to pick it up.


## 0.2.39 (alpha)
- Reverted the Debug "Blackout Kick!" row to boolean (up/gone) — its stack count wasn't reading reliably.


## 0.2.38 (alpha)
- Debug "Blackout Kick!" row now shows its stack count instead of just up/gone.


## 0.2.37 (alpha)
- **Conduit of the Celestials single-target default built to the tuned list.** Includes a real "Fists of Fury before Heart of the Jade Serpent falls off" line: HoJS is now duration-modeled (6s from Strike/Whirling Dragon Punch, 4s from Zenith with Yu'lon's Avatar). A cast can now grant several timed buffs. (The Bloodlust RSK line is intentionally omitted for now.) Reset your Windwalker lists to default to pick it up.


## 0.2.36 (alpha)
- **New "Cooldown ≥ / ≤ N" condition, with Invoke Xuen cooldown prediction.** Cooldown-remaining is secret in combat, so PRIO seeds a timer when Xuen is cast (120s, −30s with Xuen's Bond) and counts it down, anchored to the real off-cooldown flag. This drives the Conduit "Whirling Dragon Punch / Strike of the Windlord if Xuen is more than 10s away" lines. Debug shows Invoke Xuen CD.


## 0.2.35 (alpha)
- **Shado-Pan cleave + AoE default rebuilt to the tuned multi-target rotation** (shared list; uses the new "Energy near cap" gate on the avoid-cap Tiger Palm). Reset your Windwalker lists to default to pick it up.


## 0.2.34 (alpha)
- **Shado-Pan single-target default rebuilt to the tuned rotation** (Zenith at 2 charges, Zenith-Stomp on the closing Zenith window, Tiger Palm gated on Blackout Kick! stacks, etc.). Reset your Windwalker lists to default to pick it up.


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
