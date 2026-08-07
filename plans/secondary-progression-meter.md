# Per-Surface Progression Meter for Secondary Entities

Replace the global credit pool with a per-surface cumulative meter ("odometer") that gives
every secondary entity the average primary entity's credit earnings. Secondary entities then
advance at the same perceived pace as the machines around them, independent of how many
secondaries exist, how often the batch loop visits them, or when the mod was added to a save.

## Context

### Design goals

- Secondary entities (inserters, poles, beacons, etc. — anything that can't measure its own
  work) should advance at about the same rate as primary entities (assemblers, furnaces,
  rocket silos, turrets — entities whose work we can measure).
- Progression should feel stable and intuitive as a base grows from starter to megabase.
- Default settings should keep quality upgrades feeling like special randomized events.
- Maxed-out primaries always keep fueling the rest of the factory. This matches how most
  players already think about the quality-growth mechanic, so the
  "Continue Accumulating at Max Quality" toggle is **removed** as part of this work
  (one less configuration option; progression stays smooth with no wind-down mode).

### Current behavior and its problems

Today primaries deposit raw credits (`hours_worked / hours_needed`) into a single global pool
(`storage.accumulated_credits`), and each secondary withdraws `pool / secondary_count` on its
turn (`core.lua` — `process_primary_entity` / `process_secondary_entity`).

Problems with this model:

1. **Secondary count dilutes everyone.** Each secondary advances at roughly
   `(primary_count / secondary_count) ×` the per-primary rate. Typical factories have several
   times more secondaries than primaries, so secondaries reach max quality several times
   slower than assemblers — and placing 1000 lamps silently slows your inserters' progression.
2. **The "accumulate at max quality" off-mode is a stall trap.** When off, maxed primaries are
   dropped from tracking, pool inflow shrinks to zero as primaries max out, and secondaries
   get stranded mid-progression.
3. **Stale documentation.** The setting description in `locale/en/locale.cfg`
   (`accumulate-at-max-quality` description) still describes a ratio-upscaling system that
   was removed in v1.7.0 (commit `9921900`). That old system multiplied credits by
   `secondary_count / primary_count`, which produced the awkward "one lone uncommon assembler
   advances an entire megabase" extreme; v1.7.0 replaced it with the pool, trading away
   rate parity for predictability.

### The chosen design: a cumulative meter, read like an electricity meter

The core idea is to transfer **integrals, not derivatives** — a running total, never a
sampled rate. Rate-based designs (e.g. "apply the observed primary upgrade rate to
secondaries") were tried and are inherently cadence-poisoned and hard to tune; cumulative
counters are immune by construction.

Mechanism, three pieces:

1. **One meter per surface** `C` = total credits the *average* primary on that surface has
   earned, ever. When a primary is visited and earned `credits` since its last visit, add
   `credits / surface_primary_count` to that surface's meter.
2. **One bookmark per secondary** — `last_seen_meter`, set to the meter's *current* value
   when the entity is first tracked.
3. **On visiting a secondary**: its upgrade credits are `C − last_seen_meter`; then set
   `last_seen_meter = C`. Roll the upgrade attempt with those credits exactly as today.

The electricity-meter analogy: the utility bills on the difference between readings, so
reading the meter more often never changes the bill. Concretely — 4 assemblers each earn
0.05 credits over an hour, so the meter rises 5.00 → 5.20. An inserter visited once that
hour reads a delta of 0.20; an inserter visited four times reads 0.05 four times. Same
total. Advancing the bookmark *is* the spending — no pool balance, no spent-ledger.

Unlike the pool, the meter is **not a shared finite resource** — it's a broadcast. Every
secondary independently receives the full per-primary average. That is the definition of
the parity goal, not double-counting.

### Properties this buys (verified in design discussion)

- **Cadence invariance.** `batch-entities-per-tick` / `batch-ticks-between-processing` change
  when credits arrive, never how many. The credits→probability conversion is linear in
  credits (both the roll and the failed-attempt chance accumulation), so chunking doesn't
  matter to first order.
- **No spike when added to an existing save.** Primaries already baseline cumulative hours at
  tracking time; secondaries baseline the meter. Nothing historical is ever paid out, and
  re-running `quality-control-init` can't be farmed for credits (the pool could be).
- **Idle-neutral.** A stalled base deposits nothing; the meter freezes; progression resumes
  at full pace the moment work resumes, with no lingering "lull" (nothing is windowed or
  averaged, so there is no memory to poison).
- **No tuning parameters.** Deterministic input-rate matching; no windows, no feedback loops.

### Consciously accepted consequences

- **Idle primaries drag the average.** A mostly-idle mall lowers the per-primary average and
  slows secondary progression. This replaces the pool's stranger coupling (secondary count
  diluting everyone) and matches the old pre-1.7.0 behavior players already strategized
  around. Do NOT try to normalize by "active" primaries only — defining "active"
  reintroduces windowing/hysteresis.
- **Zero-primary surfaces freeze.** A surface with no assemblers/furnaces/silos/turrets has a
  meter that never moves, so its secondaries never advance ("nothing is manufacturing here,
  so nothing improves here"). Under the global pool they would have coasted on other
  surfaces' work. Accepted; document it.
- **Late-game catch-up softens.** Today a newly placed secondary in a maxed factory rockets
  up because the shrinking set of unmaxed secondaries splits the whole pool. Under the
  meter, a new secondary advances at the steady average-primary rate. This is a deliberate
  trade for consistency.
- **Overall secondary speedup.** Secondaries currently run at ~N/M of parity; this change is
  roughly a 3–10× speedup for typical bases. See the optional rate-multiplier setting below.
- **Extreme-cadence bound.** If a single delta pushed a roll chance past 100%, the excess is
  wasted (an entity upgrades at most once per visit). At default settings this needs
  hundreds of hours between visits — not a practical concern, just a known boundary.

### "Continue Accumulating at Max Quality" — setting removed

The toggle is removed entirely. Maxed primaries always stay tracked and always deposit into
their surface's meter — the current default behavior becomes the only behavior.

Rationale: the setting's off-mode has been a trap since v1.7.0 (its original ratio-era
character no longer exists, and its current effect is stranding secondaries mid-progression),
its in-game description is stale, and always-on matches the intuitive mental model of the
mechanic. Removing it also simplifies the code: the tracking conditions in
`get_entity_info` and `batch_process_entities` that special-case
`accumulate_at_max_quality` collapse to "primaries are always tracked."

Removal checklist: delete the `accumulate-at-max-quality` entry from `settings.lua`, its
`settings_data` wiring in `control.lua`, the `accumulate_at_max_quality` local and both
tracking conditions in `core.lua`, and its English locale entries (setting name and
description). Factorio drops removed startup settings from existing saves automatically —
no settings migration needed.

## Implementation Notes

### Source guide (for an engineer new to this repo)

- `control.lua` — entry point; builds `storage.config` (including `settings_data`), event
  registration, `quality_multipliers` table (`hours_needed = manufacturing_hours_for_change
  × (1 + quality_increase_cost)^level`).
- `scripts/core.lua` — everything relevant lives here:
  - `core.get_entity_info(entity)` — tracks a new entity, decides primary vs secondary
    (`assembling-machine`, `furnace`, `rocket-silo`, turret types = primary), baselines
    primary manufacturing hours, back-fills `chance_to_change` for pre-mod work.
  - `core.process_primary_entity` — computes credit earnings from the hours delta; currently
    deposits into `storage.accumulated_credits`. Primaries also use their own
    `credits_earned` for their own upgrade attempt — unchanged by this work.
  - `core.process_secondary_entity` — currently withdraws `pool / secondary_count`. This is
    the function the meter read replaces.
  - `core.batch_process_entities` — round-robin batch loop; gates upgrade attempts on
    `result.credits_earned > 0`; drops entities that can no longer upgrade (and, when the
    accumulate toggle is off, currently drops maxed primaries — this changes, see above).
  - `attempt_upgrade_normal` — the probability roll and failed-attempt chance accumulation.
    **Unchanged**; both are linear in the credit amount, which is what makes the design
    cadence-invariant.
- `scripts/progression.lua` — manufacturing-hours math (leaf module). Unchanged.
- `scripts/notifications.lua` — the control-shift-q inspect display computes and shows
  credits earned/spent; needs updating for meter semantics.
- `migrations/` — Factorio migration scripts run on version upgrades; follow existing
  file naming there.
- Counts: `storage.primary_entity_count` / `storage.secondary_entity_count` are global and
  maintained in `get_entity_info` / `remove_entity_info`.

### New/changed storage

- `storage.surface_meters[surface_index]` — cumulative credits-per-primary (double).
  Monotonically increasing; double precision is ample for the magnitudes involved.
- `storage.surface_primary_counts[surface_index]` — primaries per surface, maintained
  alongside the existing global counts.
- `entity_info.surface_index` — stored for **all** tracked entities. Needed both to
  decrement the right surface count when an entity is removed after becoming invalid
  (`entity.surface_index` is unreadable then) and for the surface-move guard.
- `entity_info.last_seen_meter` — secondaries only. **Must initialize to the surface
  meter's current value, never 0** — initializing to 0 hands a new secondary the entire
  historical meter as an instant spike. This is the one implementation detail that can
  silently ruin the design.
- Delete `storage.accumulated_credits`.

### Primary count baseline

Maintain per-surface counts exclusively in `get_entity_info` / `remove_entity_info`, so the
denominator always equals the set of primaries that actually deposit. The initial baseline
falls out of the existing synchronous init scan (`core.scan_and_populate_entities()`) —
increment the counts in that same pass; no separate counting mechanism.

### Guards and edge cases

- **Surface-move guard.** On each secondary visit, if `entity.surface_index ≠
  entity_info.surface_index`, re-home it: update the stored index and reset
  `last_seen_meter` to the new surface's meter (no credits from the move). Covers script
  teleports and cross-surface cloning (e.g. Factorissimo-style mods).
- **Surface deletion.** On `on_surface_deleted`, remove that surface's meter and count
  entries. Entities on the deleted surface become invalid and are already cleaned lazily by
  the batch loop.
- **Division safety.** Deposits are made by an existing tracked primary, so the surface
  primary count is ≥ 1 at deposit time. A missing meter entry initializes to 0 on first use.
- **New surfaces** need no special handling: meter starts at 0, first secondaries bookmark 0.

### New setting: `secondary-progression-rate`

A percentage multiplier applied to the meter delta when a secondary is paid.

- **Type:** `int-setting`, `setting_type = "runtime-global"` — tunable mid-game with no
  restart; the mechanism doesn't care (it scales the payout, not the meter, so changing it
  never rewrites history or causes spikes).
- **Default 100**, generous range: min 0, max 100000. At 0, secondaries stop advancing
  entirely; at 100 they match the average primary; large values let players crank
  infrastructure progression far past parity if that's their idea of fun.
- Read it at payout time in `process_secondary_entity` (or cache and refresh via
  `on_runtime_mod_setting_changed`, matching how `batch-entities-per-tick` is handled).

This is the tuning valve for the parity speedup: it adjusts secondary pacing without
touching primary pacing, preserving the "special randomized event" feel if parity proves
too fast in practice.

### Migration for existing saves

- Initialize `surface_meters` and `surface_primary_counts` (walk tracked entities; skip
  invalid ones).
- Set every tracked secondary's `last_seen_meter` to its surface's meter value (0 for
  fresh meters — equal values, so no payout spike).
- Stamp `surface_index` on all tracked entity_info records.
- Drop `storage.accumulated_credits`.
- Bump `info.json` version.

### Relationship to `plans/aura-credits.md`

That plan layers spatial credit distribution on top of the **pool** and modifies the same
functions this work replaces. It is superseded as written. If spatial differentiation is
still wanted later, it needs a redesign against the meter model (e.g. a local bonus on top
of the broadcast) — a stakeholder decision, out of scope here.

## Suggested Approach

1. Add the storage structures + per-surface count maintenance in
   `get_entity_info` / `remove_entity_info`; stamp `surface_index` on all entity_info.
2. Change `process_primary_entity` to deposit `credits_earned / surface_primary_count` into
   the surface meter; keep returning `credits_earned` for the primary's own attempt.
3. Rewrite `process_secondary_entity(entity_info, entity)` as the meter read
   (delta, bookmark advance, rate multiplier, surface-move guard).
4. Remove the `accumulate-at-max-quality` setting and its conditions in
   `get_entity_info` / `batch_process_entities` — primaries are simply always tracked.
5. Register `on_surface_deleted` cleanup in `control.lua`.
6. Add the migration script; bump version.
7. Update the inspect display in `notifications.lua` (secondaries: show credits available as
   meter − bookmark; primaries unchanged).
8. Settings + English locale: add `secondary-progression-rate` (runtime-global, default 100,
   range 0–100000) with name/description keys; remove the `accumulate-at-max-quality` keys.

## Testing

Avoid introducing boilerplate tests; we do not want excessive pointless tests as these do
not serve anyone. It's extremely important that the tests are meaningful, clear, and
validate core issues and behavior. It's important to figure out tests that validate our
business case, and that ensure healthy core architecture. They can and should help
engineers understand the intention behind the code.

Note: the existing pytest suite is static analysis (lua syntax, locale key coverage,
changelog format, storage-usage conventions) — it cannot exercise runtime Lua behavior.
The behavioral properties (cadence invariance, no-spike adoption, wind-down) are verified
in-game per the Validation checklist; don't force them into pytest.

## Validation

- [ ] `./validate.sh` passes (this is the single required check; do not run luacheck or
      pytest directly).
- [ ] Fresh game: build a few assemblers + inserters; inserters advance at roughly the
      per-assembler credit pace; building many extra secondaries does NOT slow existing ones.
- [ ] Cadence invariance: run the same save twice with very different
      `batch-entities-per-tick` / `batch-ticks-between-processing`; secondary progression
      over the same game time is equivalent.
- [ ] Mid-game adoption: add the mod (or run `quality-control-init`) on a mature save; no
      burst of secondary upgrades.
- [ ] Idle: let the base stall; no progression during the stall, full pace on resume, no
      lingering slowdown.
- [ ] Per-surface isolation: an active surface does not advance secondaries on an idle or
      zero-primary surface.
- [ ] Maxed primaries: once an assembler reaches max quality it stays tracked and keeps
      moving the meter (secondaries near-exclusively fed by maxed primaries still advance).
- [ ] `secondary-progression-rate`: changing it mid-game takes effect without restart or
      payout spikes; 0 halts secondary progression; large values accelerate it
      proportionally.
- [ ] New secondary placed late: bookmark starts at the current meter (steady rate, no
      instant historical payout).
- [ ] Inspect (control-shift-q) shows sensible credit values for both entity classes.

## Documentation

- `README.md` — rewrite the "how the upgrade system works" section for the meter model
  (electricity-meter framing + the 4-assembler worked example serve well); document the
  zero-primary-surface and idle-average behaviors.
- `locale/en/locale.cfg` — remove the `accumulate-at-max-quality` keys; add name and
  description keys for `secondary-progression-rate`. English only; non-English locale test
  failures are expected and handled by another developer.
- `changelog.txt` — new entry via the `new-changelog` skill; frame as a major balance
  change (secondaries speed up substantially; late-game catch-up behavior changes; the
  "Continue Accumulating at Max Quality" setting is removed — its behavior is now always
  on).
- `plans/aura-credits.md` — mark superseded or remove, per stakeholder decision.
