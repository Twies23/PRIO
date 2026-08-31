# PRIO

A configurable rotation priority & queue helper for World of Warcraft (Midnight, patch **12.1**). PRIO shows the ability to press **now** plus the upcoming queue, with a standalone options UI for editing the priority list.

Built to work within 12.1's "secret value" API restrictions — health/power/aura values are opaque in combat, so PRIO reads only clean signals (cooldown ready-state, nameplates, your own cast events, the Cooldown Viewer) and **predicts** the rest with a local state machine.

## Supported specs

| Class   | Spec           | Spec ID | Status |
|---------|----------------|---------|--------|
| Hunter  | Beast Mastery  | 253     | **Built & tuned** — verified IDs, Pack Leader + Dark Ranger |
| Shaman  | Elemental      | 262     | Primary / most-tested |
| Rogue   | Outlaw         | 260     | Tuned (Trickster) |
| Warrior | Arms           | 71      | Tuned (Slayer) |
| Shaman  | Enhancement    | 263     | New — needs testing |
| Hunter  | Marksmanship   | 254     | Stub — best-guess IDs, needs testing |
| Monk    | Windwalker     | 269     | New — needs testing |
| Demon Hunter | Devourer  | 1480    | New — verified IDs, open questions |

Most specs ship **one all-inclusive priority list per mode** that covers every hero-talent and choice-node variation: abilities you haven't talented are filtered out automatically (`IsKnown`), and buff-gated lines go inert when that buff never appears — so the same list adapts to your build without per-talent configuration. Some specs go further with **per-hero-tree lists** (e.g. Beast Mastery's Pack Leader / Dark Ranger, Outlaw's Trickster / Fatebound) and expose only the modes that matter (Beast Mastery is ST / AoE, no separate Cleave tier).

Marksmanship still ships best-guess IDs and needs an in-game pass — see **Testing** below.

### Beast Mastery Hunter

The most complete Hunter spec. Both hero trees — **Pack Leader** (default) and **Dark Ranger** — with single-target and AoE lists; spell and buff IDs are verified against the live 12.1 client. How it works around 12.1's secret values:

- **Charges** — reads the exact 0/1/2 count for Barbed Shot / Kill Command via the charge-aware cooldown. The recharge *time* is secret in combat, so "don't overcap" gates on the readable count rather than a drifting timer.
- **Focus** — the value is secret, but spenders are gated on the game's clean insufficient-power flag: an unaffordable Kill Command / Cobra Shot / Wild Thrash is shown **dimmed** until you can afford it.
- **Howl of the Pack Leader** — read from the Kill Command button glow.
- **Cobra Fang, Nature's Ally, Beast Cleave, Hunter's Mark, Bestial Wrath** — from your Cooldown Manager (add them via `/prio setup`).
- **Frenzy** lives on the pet and can't be tracked, so it's maintained indirectly by keeping Barbed Shot off its charge cap.

It also puts a **pet check** at the top of each list (Call Pet if you have none, Revive Pet if it's dead), maintains **Hunter's Mark**, and tracks the **Bestial Wrath** cooldown. Cobra Fang lines are inert until you have the 4-set tier bonus.

## Install

1. Download this repo as a ZIP (green **Code** button → **Download ZIP**), or clone it.
2. Copy the `PRIO` folder into your AddOns directory:
   - PTR: `World of Warcraft\_ptr_\Interface\AddOns\`
   - The folder **must** be named `PRIO` (matching `PRIO.toc`) and contain the `.lua` files directly — not nested in a `PRIO-main` subfolder if you downloaded the ZIP.
3. Restart WoW or `/reload`. Enable **PRIO** in the AddOns list (untick "Load out of date" if needed).

## Usage

- `/prio` — toggle the display lock (drag to move when unlocked)
- `/prio options` — open the options window (or use the minimap button, left-click)
- `/prio debug` — open the live engine-state window (minimap right-click)
- `/prio spells` — check which of the current spec's spell IDs resolve as known
- `/prio tracked` — dump all Cooldown Viewer tracked spell/aura IDs (the source for buff IDs)

## Testing the Hunter specs

The Hunter specs ship with best-guess IDs. To verify:

1. Log in on a Marksmanship or Beast Mastery hunter.
2. Run `/prio spells` — anything reported as **not known** has a wrong ID.
3. Run `/prio tracked` and copy the output — this lists the real buff/debuff aura IDs.
4. Send the two dumps back so the constants (Precise Shots, Trick Shots, Frenzy, Beast Cleave, etc.) can be corrected.

Rotation feedback (wrong ability recommended, wrong order, missing cooldown) is very welcome — note the spec, target count, and what it suggested vs. what you'd press.

## Notes

- 12.1 / PTR only right now (`## Interface: 120100`).
- Not affiliated with Blizzard. Personal project.
