# Encounter Planner (boss-timing cooldown module) — design

Status: **research / design**. No engine changes until this is approved.

## Goal

Assign specific cooldowns to **fight-relative timings or boss abilities** on a per-encounter
plan, and have the engine **take those cooldowns out of the normal priority** and instead
recommend them when their scheduled moment arrives. Authoring lives in a **new top-level
options tab** (peer of Priorities / Opener), *not* as hand-authored conditions on priority rows.

Everything the plan reads (encounter clock, boss casts, phase) is **readable in combat** — no
prediction layer needed, unlike the buff/stack signals the engine models elsewhere.

## Three pieces

1. **New options tab** — "Encounters", a peer page in the sidebar.
2. **Plan data model** — per-spec, per-encounter, per-difficulty list of `{spell, trigger, cond?}`.
3. **Engine overlay** — a precedence layer that (a) suppresses managed spells from the normal
   walk and (b) injects a managed spell as the primary when its trigger is live.

---

## 1. Options tab

Tabs are pure data in `Options.lua`:

- `NAV` (`Options.lua:1201`) — sidebar groups. Add a `RAID` group:
  ```lua
  { header = "RAID", items = { { label = "Encounters", page = "encounters" } } },
  ```
- `PAGE_META` (`Options.lua:1209`) — add an `encounters` entry (title + description).
- `Pages.encounters()` render fn (alongside `Pages.rotation`/`Pages.opener`, `Options.lua:331`/`:928`).

No framework work — the page system already dispatches `Pages[key]()` (`Options.lua:1240`).

### Page layout (v1, list editor)

- **Encounter selector** — dropdown or tab strip populated from the Encounter Journal API
  (`EJ_GetInstanceByIndex` → `EJ_GetEncounterInfoByIndex`) for the current raid tier, so we
  don't hardcode/maintain a boss table. Difficulty selector beside it (with a "copy from
  difficulty" affordance).
- **Entry list** — rows of `spell → trigger → [optional condition]`:
  - spell picker: reuses the existing ability picker (draws from `spec.spells`).
  - trigger dropdown: `At time (m:ss)`, `On boss cast (spell)`, `On phase (N)`.
    - boss-cast spell list is sourced from **BigWigs** (the abilities it actually times on this
      encounter — see Data sources), so every option is genuinely triggerable. `EJ_GetSectionInfo`
      is only an optional enrichment for names/icons.
  - optional condition: the existing generalized `Cond` editor (`Options.lua:567`) attached to
    the entry, ANDed with the trigger ("only if Avatar is actually off cooldown" etc. — though
    the live `IsReady` gate already covers the common case).
- Add / remove / reorder rows (reuse the priority-row row controls).

### Page layout (v2, graphical timeline) — deferred

Same underlying `entries`, rendered on a scrubbable horizontal timeline: drag a cooldown onto
a time, snap to boss-cast markers pulled from a reference (BigWigs schedule or a WCL-derived
default). This is the expensive custom widget; ship v1 first.

---

## 2. Data model

```lua
db.encounterPlans[specKey] = {
    [encounterID] = {
        [difficultyID] = {
            enabled = true,
            entries = {
                -- trigger is exactly one of: at / bossCast / phase
                { spell = "avatar",   at = 0,            offset = 2 },              -- pull + 2s
                { spell = "avatar",   bossCast = 12345,  offset = 0, cond = <Cond> },-- on boss cast, gated
                { spell = "recklessness", phase = 2 },                              -- phase 2 start
            },
        },
    },
}
```

- **spell** is a spec KEY (override-aware, same as priority/opener entries).
- **trigger** — one of:
  - `at` = seconds since `ENCOUNTER_START` (+ optional `offset`). Anchored to the pull clock;
    drifts if the pull runs long — prefer `bossCast`/`phase` for anything past the opening.
  - `bossCast` = boss spellID; fires within a short window after the boss's
    `SPELL_CAST_START`/`_SUCCEEDED`. Self-re-anchoring (no drift).
  - `phase` = encounter phase index (see phase detection below).
- **cond** (optional) — a standard `Cond` table, ANDed with the trigger.

Keyed per **spec** (a plan is class-specific), per **encounterID**, per **difficultyID**.

---

## 3. Engine overlay

### Activation / lifecycle

- `ENCOUNTER_START(encounterID, name, difficultyID, groupSize)` → resolve
  `activePlan = db.encounterPlans[spec.key][encounterID][difficultyID]`; record `encStart = GetTime()`.
- `ENCOUNTER_END` → clear `activePlan`.
- **When `activePlan` is nil, the overlay is completely inert** and the engine behaves exactly
  as today. This is the fail-safe: no plan, no change.
- Subscribe to boss casts via **BigWigs** callbacks (`BigWigsLoader.RegisterMessage`): a bar
  start (`BigWigs_StartBar`, args `module, key, text, time, icon`) marks the assigned ability
  firing — matched to the entry by **spellID**. Because the bar starts *before* the cast lands,
  this also yields the look-ahead for a "prepare X" pre-warning for free.
- Phase detection: BigWigs stage messages (a boss module signals its stage), so the "On phase"
  trigger is real rather than hand-marked. Fall back to manual phase markers only where a module
  doesn't expose stages.
- **Do NOT read the combat log.** Under 12.1's secret-value regime it's unreliable, and BigWigs
  already abstracts whatever detection is/isn't possible per boss. BigWigs is the single runtime
  source of truth for this module.

### State (in `BuildState`)

Add to `S`: `encTime` (seconds since pull, or nil), `bossCast[spellID] = <t of last cast>`,
`phase` (index or nil), and a resolved `S.bossManaged = { [sid]=true }` / `S.bossInject = <sid or nil>`
computed once per tick from `activePlan`.

New `Cond.types` are **not** required for the user (this is the whole point — no hand-authored
conditions), but the same primitives (`encTimeMin/Max`, `bossCast`, `phase`) back the trigger
evaluation internally.

### Precedence (in `Engine:Evaluate`)

```
1. Opener            (existing short-circuit, Engine.lua:1787)
2. Boss overlay      (NEW)
3. Standard walk     (existing, Engine.lua:1834+)
```

Two symmetric behaviors:

- **Suppression (automatic).** At the top of `tryCandidate` (`Engine.lua:1886`):
  ```lua
  if S.bossManaged and S.bossManaged[sid] then return nil end
  ```
  Any spell named in the active plan is removed from the normal walk — from **both** built-in
  and custom lists — without the user editing their priority list.

- **Injection (scheduled).** Before the pick loop, evaluate the plan entries against live `S`.
  If exactly one managed entry's trigger is active AND the spell is castable
  (`API.IsKnown` + `IsReady` + `IsUsable` — the real hard gates still apply), set it as the
  **primary**, then let the standard walk fill the remaining queue slots (managed spells still
  suppressed). If the CD has drifted onto cooldown when its window opens, nothing injects and
  the normal rotation flows through untouched.

**Inject-into-slot-1, not full takeover.** Unlike the opener (which owns the whole strip), the
overlay only claims the primary. You see the triggered cooldown up top with your normal filler
underneath — the strip never blanks.

### Open decisions

- **Simultaneous windows** — when two managed entries trigger at once, order by entry index in
  the plan (author controls it) → slot 1 gets the highest, the rest wait (they stay eligible on
  the next tick once slot 1's is cast/consumed).
- **Pre-window heads-up** — the look-ahead queue does *not* advance the encounter clock
  (`sim`, `Engine.lua:1845`), so a window opening 3 GCDs out won't pre-populate the queue. If a
  "line up X in 3s" nudge is wanted, use the existing **alerts** channel
  (`spec.alerts`, `Engine.lua:2058`), evaluated on live `S` — it's built for exactly this.
- **Opener overlap** — if a managed CD is also an opener step, the opener wins during its window
  (it short-circuits first); the plan takes over afterward. Consider a per-plan "starts after
  opener" flag.
- **Difficulty defaults** — new plans start empty; offer "copy from <difficulty>".

## Data sources & dependencies

Three data needs, three sources — and **only the runtime trigger touches BigWigs**:

| Need | Source | Dependency |
|---|---|---|
| Encounter list (tab names/icons) | Encounter Journal (`EJ_GetInstanceByIndex` → `EJ_GetEncounterInfoByIndex`) — static journal metadata, unaffected by secret-value rules | native |
| Boss-cast + phase triggers (runtime) | **BigWigs** callbacks — `BigWigs_StartBar` (match by spellID), stage messages | **BigWigs (hard)** |
| Ability dropdown + default timeline placements | **Learn-from-pull**: record the bars BigWigs fires on an attempt; the dropdown fills with exactly the abilities BigWigs times, at their real times | **BigWigs (hard)** |

Why BigWigs is a hard dependency (not the earlier "soft"):

- **The combat log is not a usable source in 12.1** (secret-value regime). BigWigs abstracts
  whatever per-boss detection is possible, so we depend on it instead of reimplementing it.
- **Learn-from-pull** guarantees every pickable ability is genuinely triggerable (EJ lists
  abilities BigWigs doesn't time, which would be dead options) and solves default placement in
  the same step — no Warcraft Logs export pipeline needed. Good enough for a personal tool.
- BigWigs' bars start *before* the cast, giving the look-ahead pre-warning for free.

**Scope the dependency to this module only.** PRIO core stays dependency-free; the Encounters
tab shows an "Install BigWigs to use encounter plans" state when BigWigs is absent. DBM support
is a possible second adapter later (BigWigs first — cleaner callback API, open source).

Do **not** reskin Blizzard's boss-banner/alert frames — render pre-warnings through PRIO's own
`alerts` channel (`Engine.lua:2058`) in the addon's visual language.

### Importing an MRT note (primary authoring path)

MRT reminder-note lines map almost 1:1 onto our trigger types, so importing a note (from lorrgs
or a guild) is the natural front door — manual entry becomes the fallback, not the default.

MRT line → PRIO entry:

| MRT syntax | Meaning | PRIO trigger |
|---|---|---|
| `{time:1:30}` | 1:30 after pull | `at` = 90 |
| `{time:0:05,SCC:54321:2}` | 5s after the **2nd** cast-succeeded of spell 54321 | `bossCast` = 54321, occurrence 2 |
| `{time:0:03,SCS:54321:1}` | 3s after the 1st cast-**start** of 54321 | `bossCast` (start variant) |
| `p2` tag | phase 2 | `phase` = 2 |
| `{spell:12345}` | the assigned cooldown | entry spell (map spellID → spec key) |
| `Player => Target` | caster (and optional target) | keep only lines where caster == `UnitName("player")` |

Import = **parse → filter-to-me → map**: keep lines whose caster is the player, extract
`(trigger, spellID)`, map spellID to a spec key (`idToKey`), drop anything that isn't a
PRIO-known managed CD. We carry an **occurrence index** (the `:N`) on `bossCast` triggers so
"on the 2nd Eradication" survives the round-trip.

Two intake paths:
1. **Paste box** — dependency-free; accepts a raw lorrgs export or any note text. Build first.
2. **Live read of MRT** — if MRT is installed, read its saved note for the current encounter
   (`VMRT.…` — exact path to verify against MRT source) and import in one click. Upgrade.

Caveats: strip class-color escapes (`|cff…|r`) around names; lines assigned by role/group rather
than character name can't be auto-filtered → flag for manual review. Import is **best-effort and
always lands in the editor for confirmation** — never silently active (notes are strat-specific).

## Build order

1. Data model + `ENCOUNTER_START/END` activation + `BuildState` fields (no UI, no override yet).
2. Engine overlay (suppression + injection) — testable via the Lua harness with a synthetic plan.
3. BigWigs adapter: subscribe to `BigWigs_StartBar`/stage messages, learn-from-pull recorder.
4. Options tab v1 (list editor) + EJ-driven encounter picker + BigWigs-derived ability dropdown.
5. MRT note import — paste box + parser (`parse → filter-to-me → map`) landing in the editor.
6. v2 graphical timeline widget (deferred). Live MRT saved-var read (deferred upgrade).
