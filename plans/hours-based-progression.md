# Quality Control 3.0: Active-Hours Progression

Replace the crafting-speed/productivity-scaled "manufacturing hours" and the "upgrade credits"
vocabulary with a single, simpler unit: **active hours** — wall-clock time an entity spends
working. Every entity, primary or secondary, earns active hours and needs a fixed number of
them (per quality tier) for each upgrade attempt. Turrets stop sharing progress with the rest
of the factory. This ships as a single major release, version 3.0.0.

Explicitly out of scope for this plan (scoped to separate efforts):
- **Attempt only at full hours** — upgrade rolls happen only when a full threshold of hours has
  been earned, instead of the current proportional partial attempts each visit. This plan keeps
  the existing attempt logic untouched but lays the groundwork (durable per-entity
  `active_hours`) so that follow-up is small.
- **In-game notice about the model change** — the author will decide on player-facing
  messaging independently of the implementation. Do not add one.

## Context

### Why

After a long time playing with the mod the author concluded the current model is
overcomplicated. Progression today depends on recipe duration, crafting speed, productivity
bonuses, module/beacon effects, and a per-surface "credit" meter, and the language players see
mixes "manufacturing hours", "progression hours", and "credits". The desired identity for the
mod is simple to state and simple to reason about:

> A machine that works for N hours gets an upgrade attempt.

The player experience the mod is going for is unchanged — a machine that works hard climbs in
quality, and cranking the settings still gives a near-instant "cheat" feel — but the knobs
that get you there are fewer and easier to explain.

### Why a major bump is acceptable now

- ~1000 active players are on Factorio 2.0 and stay on Quality Control 2.1.3 (the last
  2.0-compatible release). ~150 are on Factorio 2.1 and receive current releases. Players
  generally update mods between playthroughs, so most will meet 3.0 as a fresh start.
- Quality Control adds no entity prototypes (only hotkeys and settings). Downgrading, removing,
  or swapping the mod never breaks a save — nothing on the map disappears. Any player who
  dislikes 3.0 can pin 2.5.x with no consequences.
- 2.4.0 already removed a setting (Continue Accumulating at Max Quality) without complaint.

If a vocal group later wants the old compounding behavior, the fallback is to publish 2.5.x
under a separate mod name ("Quality Control Classic"). That is reactive and outside this plan.

### What changes for the player

| Today | 3.0 | Kind of change |
|---|---|---|
| Work per attempt measured in "manufacturing hours" (products × recipe time, optionally ÷ crafting speed) | Active hours: wall-clock time spent working | Behavior change |
| `crafting-speed-affects-progression` (startup, default on) | Removed. Progression is always time-based. | **The one real removal.** Players on the default lose the compounding effect where each quality upgrade speeds up the next. A faster feel is achieved by lowering hours-per-attempt instead. |
| Mining drills and labs: meter credits × (base speed ratio × speed bonus × productivity bonus), only while working | Earn hours at 1× while `status == working`, 0× otherwise | Simplification; the working-only rule stays |
| `turrets-contribute-credits` (startup, default off) | Removed. Turrets only ever upgrade themselves. | Removal, but the default already matched the new behavior |
| "Credits" in the hotkey readout, setting descriptions, README | "Hours" / "active hours" everywhere | Terminology |
| `manufacturing-hours-for-change` (startup) | Same stored key, presented as "Active hours per upgrade attempt"; **recommended:** value moves to a runtime-global setting (Map tab) so pace is tunable mid-game | See D4 |
| `percentage-chance-of-change`, `quality-increase-cost`, `quality-chance-accumulation-rate`, `secondary-progression-rate`, upgrade limits, module upgrades, notifications, batch settings | Unchanged | — |

`quality-chance-accumulation-rate` is explicitly kept as-is: it only raises the success chance
of each subsequent roll after a failure, which is orthogonal to how hours are earned.

## Implementation Notes

### Source guide (read in this order)

- `CLAUDE.md`, `README.md` (Technical Details section), `mod-description.md` — the current
  model as documented; all three need rewriting (see Documentation).
- `plans/secondary-progression-meter.md` — why the per-surface meter transfers cumulative
  totals rather than sampled rates. The meter design stays; only its unit changes.
- `plans/drill-and-lab-speed-scaling.md` — the speed factor this plan removes.
- `scripts/progression.lua` (93 lines) — leaf module (no requires) shared by core and
  notifications. `get_manufacturing_hours` (products × recipe time / 3600, or turret
  damage / `turret-damage-per-manufacturing-hour`), `to_progression_hours` (÷ crafting speed
  when the setting is off), `get_secondary_rate_factor` (drill/lab speed factor and working
  gate). Most of this file goes away or shrinks.
- `scripts/core.lua` (481 lines) — entity tracking and the batch loop.
  - `feeds_surface_meter(is_primary, is_turret)` encodes the turrets-contribute rule; becomes
    simply `is_primary and not is_turret`.
  - `core.get_entity_info` creates the tracked record (`manufacturing_hours` baseline,
    `chance_to_change`, `last_seen_meter` bookmark for secondaries) and pre-charges
    `chance_to_change` for past attempts derived from the entity's cumulative API counters.
  - `core.process_primary_entity` computes `credits_earned = hours_worked / hours_needed` and
    deposits `credits_earned / surface_primary_count` into `storage.surface_meters[surface]`.
  - `core.process_secondary_entity` reads the meter delta × `secondary-progression-rate` ×
    drill/lab rate factor.
  - `attempt_upgrade_normal(entity, upgrade_credit)` rolls with `chance × upgrade_credit`; on
    failure it bumps `chance_to_change` by `base × accumulation% × upgrade_credit`. This
    partial-attempt logic is **unchanged** in 3.0 (see out-of-scope note above); only the
    argument's unit changes with D2.
- `scripts/notifications.lua` — hotkey readout. `calculate_credits_spent_on_attempts`
  back-derives attempts from `chance_to_change`; `show_entity_quality_info` prints the
  `credits-earned` / `credits-available` / `credits-used` / `next-chance-to-change` strings.
- `control.lua`
  - `build_and_store_config` (~line 195–265) reads every startup setting into
    `storage.config.settings_data` and builds `storage.quality_multipliers[quality_level]` =
    hours-per-attempt × (1 + cost)^level.
  - `migrate_upgrade_limits_to_runtime_settings` (~line 100–160) is the in-repo precedent for
    moving a startup setting to runtime-global in a single release: the old startup prototypes
    stay in `settings.lua` with `hidden = true` so their values remain readable, and a storage
    flag makes the one-time copy idempotent.
  - `reinitialize_quality_control_storage` (~line 343) is called from `on_init`,
    `on_configuration_changed`, and the `/quality-control-init` command. It calls
    `setup_data_structures(true)`, which **wipes all tracked entities, meters, and bookmarks**,
    then rescans. Today that is harmless because progress is re-derivable from the entities'
    cumulative API counters. Under 3.0 it is not — see D3.
- `settings.lua` — the settings named above, plus the hidden deprecated `enable-*` startup
  settings from the 2.2.0 limits migration (leave those alone; they are still needed to
  migrate stragglers coming from ≤2.1.x).
- `locale/en/locale.cfg` — setting names/descriptions (~lines 8–14, 85–90, 51, 126–128) and
  the hotkey strings (`credits-earned`, `credits-available`, `credits-used`,
  `next-chance-to-change`, ~lines 413–417). Only edit English; other locales are handled
  separately and their test failures for new/renamed keys are expected.
- `migrations/` — Lua migration scripts keyed by version; `2.4.0.lua` is a minimal example.

### Factorio API facts that shape the design

- No entity has a lifetime "time spent working" counter. `products_finished` (crafting
  machines) and `damage_dealt` (turrets) are cumulative and survive save/load;
  `entity.status` (`defines.entity_status.working`, `full_output`, `no_power`, `low_power`,
  `item_ingredient_shortage`, …) is a point-in-time sample. Mining drills and labs have
  `status` but no production counter.
- Startup settings can be read but never written from control-stage code. Runtime-global
  settings can be written (`settings.global[name] = {value = v}`), and changes fire
  `on_runtime_mod_setting_changed`.
- A removed setting prototype cannot be read at all, which is why prototypes whose stored
  values must survive are kept with `hidden = true` rather than deleted.
- The batch loop visits every tracked entity in round-robin at `batch-entities-per-tick` per
  `batch-ticks-between-processing` ticks (defaults: 10 per tick), so a 10,000-entity factory
  is fully visited about every 17 seconds. The bounded visit interval is what makes "elapsed
  time since last visit" a usable measure.
- 216,000 ticks = 1 hour at 60 UPS.

### Design decisions

**D1. How a primary earns active hours.** Store `last_visit_tick` per entity. On each visit,
`elapsed_hours = (game.tick - last_visit_tick) / 216000`; the entity earns `elapsed_hours` if
it was working during the interval, else 0, and `last_visit_tick` advances either way.
Recommended working test: `entity.status == defines.entity_status.working` at the visit
**or** `products_finished` advanced since the last visit. Status sampling is an unbiased
duty-cycle estimator over many visits and covers long recipes that don't finish between
visits; the products check catches statuses like `low_power` where the machine still crafts
slowly. This is deliberately generous (a machine that finishes one item per visit window and
idles otherwise gets full credit for the window). If that proves too generous in playtesting,
the strict alternative is `status == working` alone. Turrets keep their damage-based measure
(`damage_dealt / turret-damage-per-manufacturing-hour`) — there is no meaningful "time
working" for a turret — but the resulting value is now called active hours. Recipe time and
crafting speed are no longer read anywhere.

**D2. Unit of the surface meter: hours, not attempts.** Today the meter accumulates
*attempts* (hours ÷ hours-needed at the depositing primary's tier), so a secondary inherits
its neighbours' tier cost rather than paying its own. Recommended: the meter accumulates the
average primary's **active hours**, and each secondary compares the hours it draws against its
own tier's threshold (`storage.quality_multipliers[its quality level]`). One unit everywhere
makes the hotkey readout coherent ("4.2 of 6.8 hours") for every entity type. Behavior
consequence to call out in the changelog: a high-tier secondary among low-tier primaries now
progresses slower than before, and vice versa. (If the author prefers the old inheritance,
the meter can stay in attempt units and just be renamed — but "hours" would then be slightly
dishonest for secondaries. Confirm before implementing if unsure.)

**D3. Durable per-entity hours.** Add `active_hours` (lifetime accumulated) and
`last_visit_tick` to each tracked record. `active_hours` feeds the hotkey readout now and is
the foundation for the later "attempt only at full hours" effort. Because these values are
accumulated rather than derived from API counters, `reinitialize_quality_control_storage`
must stop discarding them: carry `{unit_number → {active_hours, chance_to_change}}` across
the rebuild and reattach when the rescan meets the same unit number. Reset `last_visit_tick`
to the current tick on rebuild so downtime is not credited. This also fixes an existing quirk
where every mod update reset accumulated `chance_to_change`. The `/quality-control-init`
command keeps its "rescan" meaning but no longer zeroes progress.

**D4. Settings.** Keep stored setting **keys** unchanged wherever a setting survives —
renaming a prototype silently loses the player's configured value; only locale strings change.
Delete `crafting-speed-affects-progression` and `turrets-contribute-credits` outright:
neither has a value worth preserving (the compounding effect has no static equivalent, and
turrets-contribute's default already matches the new behavior). Recommended: move
hours-per-attempt to runtime-global in this same release using the 2.2.0 pattern —
add a new runtime-global setting (e.g. `active-hours-per-attempt`), mark the old
`manufacturing-hours-for-change` startup prototype `hidden = true` (do not delete it), copy
the value once in `on_configuration_changed` behind a storage flag, and recompute
`storage.quality_multipliers` in `on_runtime_mod_setting_changed`. This lets players who find
the time-based pace slower fix it from the Map tab without a restart — the most likely 3.0
complaint. Keep the hidden prototype indefinitely (like the 2.2.0 `enable-*` ones) so players
jumping many versions still migrate. Leave `quality-increase-cost` as startup; changing it
mid-game would re-price every tier and isn't needed for the pace complaint.

**D5. Turrets isolated.** `feeds_surface_meter` → `is_primary and not is_turret`. Turrets are
tracked only while they can still upgrade themselves (the existing isolated-turret logic in
`get_entity_info` / `batch_process_entities` becomes the only path);
`storage.surface_primary_counts` counts only crafting primaries. Remove the setting, its
`settings_data` entry, and its locale strings.

**D6. Drills and labs.** `get_secondary_rate_factor` reduces to: `mining-drill` and `lab`
earn `status == working and 1 or 0`, every other secondary earns 1. The base-speed constants
and the speed/productivity bonus math go away.

### Storage migration

`migrations/3.0.0.lua` has little to do because `on_configuration_changed` rebuilds storage
after migrations run. It should log the model change and remove stale
`storage.config.settings_data` fields (`crafting_speed_affects_progression`,
`turrets_contribute_credits`) so no dead keys linger.

Old per-entity `manufacturing_hours` baselines, meter readings, and bookmarks are dropped by
the rebuild; fresh records start with `active_hours = 0` and `last_visit_tick = game.tick`.
Do **not** try to convert old credit balances — 2.x meters were in attempt units of a
different model. The `past_attempts` pre-charge in `get_entity_info` (deriving historic
attempts from cumulative counters) cannot be computed under a time model; remove it — new
records start at the base chance. One-time consequence to note in the changelog: accumulated
failure-chance bonuses reset when a save first loads under 3.0. (D3's carry-across then
prevents any *future* resets.)

## Suggested Approach

Order of work, each step leaving `./validate.sh` green:

1. **Turrets isolated** (D5) — smallest and independent: remove `turrets-contribute-credits`,
   simplify `feeds_surface_meter` and the tracked-at-max-quality logic, update locale and docs
   text.
2. **Progression rewrite** (D1, D2, D6): replace `progression.lua`'s functions with an
   active-hours earner and the reduced drill/lab working gate; convert
   `process_primary_entity` / `process_secondary_entity` and the surface meter to the hours
   unit; remove `crafting-speed-affects-progression` and its `settings_data` field.
3. **Durable progress** (D3): add `active_hours` / `last_visit_tick`, carry them across
   `setup_data_structures(true)` rebuilds, adjust `/quality-control-init` messaging.
4. **Settings move** (D4): hidden-prototype pattern plus `on_runtime_mod_setting_changed`
   recompute of `quality_multipliers`.
5. **Vocabulary and readout**: rename the `credits-*` locale keys and strings to hours terms;
   the hotkey shows lifetime active hours, hours available since last reading (secondaries),
   hours needed at the current tier, and next-roll chance. Rename
   `calculate_credits_spent_on_attempts` and other credit-named identifiers.
6. **Migration + docs + changelog + `info.json` 3.0.0.**

Naming: spell words out per the repo convention — `active_hours`, `last_visit_tick`,
`hours_needed`; no abbreviations. Comments describe current behavior only; the old model
belongs in the changelog, not in comments.

## Testing

Avoid introducing boilerplate tests; we do not want excessive pointless tests as these do not
serve anyone. It's extremely important that the tests are meaningful, clear, and validate core
issues and behavior. It's important to figure out tests that validate our business case, and
that ensure healthy core architecture. They can and should help engineers understand the
intention behind the code.

The repo's tests are Python static checks (`tests/test_*.py`) run by `./validate.sh`; there is
no Lua unit harness, so in-game verification (Validation below) is the real behavioral test.
Static checks worth updating or adding:

- `test_locale.py` will flag removed/renamed keys — ensure the English file matches the Lua
  code exactly and no `{"quality-control.<key>"}` reference points at a deleted key.
- `test_info_json.py` / `test_changelog.py` cover the 3.0.0 bump.
- Consider a static check asserting `crafting_speed`, `speed_bonus`, `productivity_bonus`,
  and recipe-time reads (`get_recipe`, `previous_recipe`, `.energy`) no longer appear in
  `scripts/` — it guards the core design intent ("no speed scaling") against regressions in a
  way no other automated check here can.

## Validation

- `./validate.sh` passes (non-English locale failures for new/renamed keys are expected).
- Load a 2.5.x save under 3.0.0: no error on load; the player's configured hours-per-attempt
  value appears in the new Map-tab setting; the hotkey readout speaks in hours, not credits.
- An assembler working continuously for 3 in-game hours (accelerate with `/c game.speed = 60`)
  reaches its first attempt threshold regardless of crafting speed; an identical assembler
  with four speed modules earns hours at the same rate; an output-blocked assembler earns none.
- Max-quality assemblers still feed the surface meter (secondaries nearby keep progressing).
- Turrets: killing biters no longer moves the surface meter; turrets still upgrade themselves;
  a max-quality turret is untracked.
- A mining drill on a depleted patch earns nothing; the same drill on ore earns hours at the
  same rate as an inserter beside it (with `secondary-progression-rate` at 100%).
- Changing the runtime hours-per-attempt setting mid-game updates the hotkey's "hours needed"
  without a restart.
- Running `/quality-control-init` (or updating the mod) does not reset a machine's
  `active_hours` or accumulated `chance_to_change`.
- Author reviews the changelog wording before release.

## Documentation

- `changelog.txt` — 3.0.0 entry: the new model, the two removed settings, the meter unit
  change (D2), the one-time reset of failure-chance accumulation, the hours setting moving to
  the Map tab.
- `info.json` — version 3.0.0.
- `README.md` — Core Functionality, the manufacturing-hours formula, Technical Details (meter
  now in hours, drill/lab section), settings list.
- `mod-description.md` (portal description) — the lines about crafting speed, speed modules,
  and the credit pool are all obsolete.
- `CLAUDE.md` — the Core Functionality section (manufacturing hours, credits,
  `progression.get_secondary_rate_factor`).
- `locale/en/locale.cfg` — setting names/descriptions and hotkey strings (English only).
- `plans/drill-and-lab-speed-scaling.md` and `plans/secondary-progression-meter.md` — add a
  one-line note at the top that 3.0 superseded the speed factor / changed the meter unit, so
  future readers aren't misled.
