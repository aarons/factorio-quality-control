# Code Review — June 2026

Full read-through of the runtime code (`control.lua`, `scripts/*.lua`, `settings.lua`, migrations, packaging).
Baseline: `43f8034`, `./validate.sh` green. Factorio API behaviors below were verified against the official
runtime docs (v2.0.77) rather than assumed; regressions were confirmed via git history. No changes made —
this is a tracking list, ordered by severity.

---

## P0 — Bugs

### 1. [x] Disabling assemblers/furnaces/turrets/rocket silos does not stop their upgrades

The eight "primary" types are always tracked regardless of their `enable-*` startup settings
(`control.lua:71`) — intentional, so they keep generating credits. But nothing in the upgrade path
ever checks `storage.config.can_attempt_quality_change`; its only reader is the inspect UI
(`notifications.lua:144`). So with e.g. `enable-furnaces = false`, furnaces still receive quality
upgrades, while the inspect tool tells the player "This entity type is disabled from quality control
in settings."

The locale promises "Enable quality changes for furnaces" etc., so this is a broken setting for all
four groups (assembly machines, furnaces, rocket silos, turrets). Secondary types are unaffected —
disabling them removes them from tracking entirely.

**History:** this is a regression. The gate existed when individual toggles were introduced
(`18a9ea8`, `core.lua:416: if can_attempt_quality_change[entity.type] then`) and was dropped in
`31c71e1` ("refactor: streamline upgrade processing by removing unused quality change tracking" —
it wasn't unused).

**Fix sketch:** load `can_attempt_quality_change` as a module local in `core.initialize()`, and in
`batch_process_entities` fold it into the upgrade decision the same way the level-limit checks work:
a disabled primary stays tracked and keeps generating credits (matching the design comment for the
always-track list), but never attempts an upgrade. One design question to settle: should a disabled
primary keep contributing credits (the always-track list implies yes), or be fully ignored?

### 2. [x] Rocket silo was only half re-enabled: always-tracked "primary" in control.lua, but a credit-consuming secondary in core.lua

Before silo support was removed, `is_primary` included rocket-silo (`604e652^`, core.lua:102).
The re-enable (`4a287c9` / 2.1.0) restored the setting, the always-track list entry, and
`send_to_orbit_automatically` preservation — but never restored rocket-silo in core.lua's
`is_primary` (`core.lua:64`). The turret commit later extended both places for turrets, leaving the
silo behind again.

Consequences today:
- Silos generate no credits from their crafting (`products_finished` unused); they draw from the
  shared pool like an inserter, and inflate `secondary_entity_count`, diluting every real
  secondary's share.
- Combined with bug 1: with `enable-rocket-silos = false`, silos are still tracked, still upgraded,
  and still drain the pool.

**Fix sketch:** add `entity.type == "rocket-silo"` back into `is_primary` (one line) plus the gate
from bug 1. If silo-as-secondary is actually preferred now, instead remove `"rocket-silo"` from
`primary_entity_types` in control.lua so the enable setting controls tracking — either way the two
files must agree.

### 3. [x] "Ticks Between Processing" changes mid-game do nothing (and can double-register the loop)

`batch-ticks-between-processing` is runtime-global (`settings.lua:63`), but
`storage.ticks_between_batches` is only written in `on_init` / `on_configuration_changed`
(`control.lua:302,310`) and there is no `on_runtime_mod_setting_changed` handler. Changing the
setting in-game has no effect until some unrelated config change (e.g. any mod update) happens.

Second-order issue: when the value finally does change via `on_configuration_changed`, the old
registration stays live for the rest of the session — `on_load` runs first in that same session and
registers the old interval, and `on_nth_tick` registrations are keyed per interval (verified in the
API docs). Result: the batch loop runs at both cadences (~2× speed) until the next save/load.

`batch-entities-per-tick` is fine — it's read fresh each cycle (`core.lua:349`).

**Fix sketch:** add an `on_runtime_mod_setting_changed` handler: on this setting, do
`script.on_nth_tick(storage.ticks_between_batches, nil)`, update storage, register the new interval.
Have `register_main_loop` (config-changed path) unregister the old interval the same way, or call
`script.on_nth_tick(nil)` once before registering.

---

## P1 — Algorithm

### 4. [ ] Recipe changes re-value a machine's entire crafting history (credit windfalls / pool wipes)

Manufacturing hours are computed as `products_finished × current_recipe_energy / 3600`
(`core.lua:111` and `core.lua:318`). `products_finished` is a lifetime counter, so the *current*
recipe's energy re-values all past crafts every time it's read:

- Switch a machine from a short to a long recipe → `hours_worked` spikes → large free credit
  windfall into the pool.
- Switch long → short → `hours_worked` goes negative → the pool is drained (it goes negative and is
  then zeroed by the `math.max(0, …)` at `core.lua:338` the next time a secondary processes — so
  whatever pool existed is silently wiped).
- Clear an assembler's recipe entirely → `get_recipe_time` returns 0 → the machine's whole history is
  dumped as negative hours; re-selecting the recipe re-adds the whole history as fresh positive
  credits. Because the negative excursion clamps at zero but the positive lands in full, this is
  repeatable credit farming — and ordinary recipe switching causes the same imbalance unintentionally.

Turrets are unaffected (`damage_dealt` is monotonic).

**Fix sketch (small, clean):** store the last-seen `products_finished` on `entity_info` instead of
(or alongside) `manufacturing_hours`, and compute
`hours_worked = (products_now − products_prev) × current_recipe_energy / 3600` each cycle, then
update `products_prev`. Past crafts are never re-valued; a recipe change only mis-prices the crafts
inside one batch window. Clamp `hours_worked` at ≥ 0 as a backstop.

---

## P2 — Moderate improvements

### 5. [ ] Every mod-configuration change wipes accrued progress

`on_configuration_changed` always calls `reinitialize_quality_control_storage()` →
`setup_data_structures(true)`, a full wipe + rescan. Primaries get `chance_to_change` re-derived
from lifetime hours (approximately preserved), but **secondaries lose all accumulated chance** and
`accumulated_credits` resets to 0. This fires for *any* mod added/removed/updated in the save, so
modpack players lose secondary progress constantly.

**Improvement:** make the config-changed path a soft resync — rebuild `storage.config`, keep
`tracked_entities` entries whose entity is still valid and whose type is still tracked, sweep out
no-longer-tracked types, rescan to add new entities. Keep the force reset for the
`/quality-control-init` command. Moderate effort (needs care when settings that feed
`quality_multipliers` change), but a real player-facing payoff.

### 6. [ ] Multiplayer: only `game.players[1]` ever sees notifications

Both notification paths print to `game.players[1]` and gate on *that* player's per-user settings
(`notifications.lua:64` and `notifications.lua:80`). Everyone else in a multiplayer game gets
nothing, and if player 1 disabled alerts, nobody gets them — despite the settings being
runtime-per-user precisely so each player can choose. Fix: iterate `game.connected_players` and
apply each player's own setting (`add_custom_alert` is already per-player).

### 7. [ ] Inspect tool (Ctrl+Shift+Q) reports wrong status in several cases

- `can_change_quality = selected_entity.quality ~= storage.config.quality_limit`
  (`notifications.lua:145`) is wrong for sticky hidden qualities (a shiny entity shows an upgrade
  chance it will never roll), ignores the radar/lightning/thruster/collector level limits, and is
  wrong for off-chain modded qualities. Use `quality_selector.has_upgrade_path()` plus the same
  level-limit logic as the batch loop — which also lets `storage.config.quality_limit` be deleted.
- The credits calculation re-implements core's hours formula but omits the furnace
  `previous_recipe` fallback, so a furnace inspected between smelts shows 0 credits.

Both fall out of item 8.

### 8. [ ] Manufacturing-hours formula is duplicated three times

`core.get_entity_info` (107–113), `core.process_primary_entity` (314–319), and
`notifications.show_entity_quality_info` (149–162). The third copy has already drifted (missing
furnace fallback, see item 7). Extract one `core.get_current_manufacturing_hours(entity, is_turret)`
and use it in all three places; also fixes `get_recipe_time` calling `get_recipe()` twice.

### 9. [ ] `plans/` ships in the released mod zip

Confirmed in the published artifact: `quality-control_2.1.2.zip` contains `plans/aura-credits.md`.
`package.sh`'s `PACKAGE_EXCLUSIONS` (lines 83–97) lacks a `plans*` entry — note that **this review
document will ship in the next release** unless that's added. One-line fix.

---

## P3 — Minor

### 10. [ ] Four copy-pasted level-limit blocks in the batch loop

`core.lua:372–398` repeats the same check for radar, lightning-attractor, thruster, and
asteroid-collector. Build a `level_limits = { radar = …, ["lightning-attractor"] = …, … }` lookup at
init; the loop body becomes one check. The pattern is growing (four types so far), so this pays for
itself the next time a type is added.

### 11. [ ] `build_entity_type_lists` duplicates the primary-type list

The if-chain at `control.lua:76–78` restates `primary_entity_types` member-by-member; build a set
from the array instead. Also, `all_tracked_types` contains every primary type twice when enabled
(unpack + loop insert) — harmless to `find_entities_filtered`, but untidy.

### 12. [ ] Dead / unused artifacts

- `storage.config.primary_types` is written but never read. (`secondary_types` is also unread today
  but is reserved by `plans/aura-credits.md` — keep or note.)
- Locale keys `chance-of-success` and `entity-not-tracked` are unused.
- Migration `1.2.8` still checks `storage.config.previous_qualities`, a field current code never
  creates (its "needs migration" branch only logs, so it's harmless, just stale).

### 13. [ ] Migration `1.3.1` is a silent no-op

It `require`s `scripts.core` and calls `core.remove_entity_info()` (`migrations/1.3.1.lua:34`), but
migrations run before `on_load`, so `core.initialize()` has never run and the module locals
(`tracked_entities`, `entity_list`, …) are still the empty file-scope tables — every call no-ops,
while the migration logs "Removed N rocket silos." It's harmless only because
`on_configuration_changed` force-rebuilds everything immediately after. Worth removing or
commenting; the require-core-from-a-migration pattern is a footgun for any future migration that
isn't followed by a full reset.

### 14. [ ] Localization gaps in notifications

`show_entity_quality_alert` builds a raw English string (`"upgraded quality to " ..`,
`notifications.lua:82`) — every other user-facing string is a locale key. The aggregate notification
prints internal prototype names ("assembling-machine-2: 3") instead of localised names.

### 15. [ ] `update_module_quality` edge cases (`core.lua:216–239`)

- "enabled" mode steps modules to `current_quality.next`, which can be a hidden (shiny) quality even
  when `skip_hidden_qualities` is on — route the step through `quality_selector` instead.
- `stack.clear()` followed by `module_inventory.insert(...)` can drop the module if the insert fails
  (result is unchecked); `stack.set_stack{...}` swaps the same slot atomically.

### 16. [ ] `quality_multipliers` assumes every quality is on normal's chain

`control.lua:145–152` builds multipliers by walking `prototypes.quality["normal"].next`, keyed by
level. An entity holding a quality not on that chain (possible with exotic quality mods — the mod
declares optional deps on 15 of them) makes `quality_multipliers[entity.quality.level]` nil →
arithmetic-on-nil crash in `get_entity_info` / `process_primary_entity`. Building from
`pairs(prototypes.quality)` keyed by quality *name* removes the assumption at identical lookup cost.

### 17. [ ] Doc nits

- `batch-ticks-between-processing`: max 6000 ticks is described as "~2.5 minutes" in the locale and
  "about 15 minutes" in settings.lua — it's 100 seconds.
- The `accumulate-at-max-quality` description mentions only assemblers/furnaces; turrets are
  primaries now too.

---

## Verified non-issues (checked deliberately, no action needed)

- `{{filter = "force", force = "player"}}` is a valid filter for all four events it's used on
  (confirmed against `runtime-api.json` 2.0.77).
- `apply_upgrade()` raises `script_raised_built` for the new entity, so upgraded entities are
  re-tracked by `core.on_entity_created`; removing the old entity from tracking *before*
  `apply_upgrade()` also makes the simultaneous `script_raised_destroy` re-entry a clean no-op.
- The batch loop's swap-with-last removal plus don't-advance-cursor-on-removal is correct, including
  last-element and wraparound edges; `goto continue` placement is legal (label at end of block).
- The bucket-array probability math reproduces vanilla's 900/90/9/1 distribution and handles
  skip-hidden / sticky-hidden correctly, including all-hidden chains.
- Space-platform surfaces (`planet == nil`) are correctly *included* by
  `should_exclude_surface`'s fall-through.
