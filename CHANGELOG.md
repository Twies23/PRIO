# PRIO Changelog

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
