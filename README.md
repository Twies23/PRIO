# PRIO

A configurable rotation priority & queue helper for World of Warcraft (Midnight, patch **12.1**). PRIO shows the ability to press **now** plus the upcoming queue, with a standalone options UI for editing the priority list.

Built to work within 12.1's "secret value" API restrictions — health/power/aura values are opaque in combat, so PRIO reads only clean signals (cooldown ready-state, nameplates, your own cast events, the Cooldown Viewer) and **predicts** the rest with a local state machine.

## Supported specs

| Class   | Spec           | Spec ID | Status |
|---------|----------------|---------|--------|
| Shaman  | Elemental      | 262     | Primary / most-tested |
| Shaman  | Enhancement    | 263     | New — needs testing |
| Hunter  | Marksmanship   | 254     | New — needs testing |
| Hunter  | Beast Mastery  | 253     | New — needs testing |
| Warrior | Arms           | 71      | New — needs testing |
| Monk    | Windwalker     | 269     | New — needs testing |
| Demon Hunter | Devourer  | 582?    | New — spec ID + spell IDs need verifying |

Each spec ships **one all-inclusive priority list per mode** (ST / Cleave / AoE) that covers every hero-talent and choice-node variation: abilities you haven't talented are filtered out automatically (`IsKnown`), and buff-gated lines go inert when that buff never appears. So the same list adapts to your build without per-talent configuration.

Hunter and Warrior spell/buff IDs are best-guess for 12.1 and may need correcting — see **Testing** below.

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
