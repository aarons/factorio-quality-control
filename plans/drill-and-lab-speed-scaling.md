# Scale Mining Drill and Lab Credits by Speed and Productivity

Mining drills and labs stay secondary entities, but the credits they read from their
surface's progression meter are multiplied by a per-entity speed factor (base speed × speed
bonus × productivity bonus) and only granted while the entity's status is `working`. A big
mining drill full of speed modules on a high-productivity force should visibly out-progress
an inserter; an idle drill on a depleted patch should not progress at all.

## Context

### The player report that prompted this

A player compared a big mining drill mining 45+ items/sec against their fast furnaces and
found the drill had 0.07 upgrade attempts while the furnaces had 200+. They asked whether
mining speed affects upgrade attempts. Today it does not, and nothing in the mod's UI
explains why.

### How progression works today

The mod splits entities into two groups (see `CLAUDE.md` and `scripts/core.lua`):

- **Primary entities** — assembling machines, furnaces, rocket silos, turrets. Their work
  is measured directly (`products_finished × recipe_time` for crafting machines,
  `damage_dealt` for turrets) in `scripts/progression.lua`, and they *deposit* credits into a
  per-surface progression meter (`storage.surface_meters[surface_index]`), which tracks what
  the *average* depositing primary on that surface has earned.
- **Secondary entities** — everything else the mod can upgrade (inserters, poles, drills,
  labs, roboports, …). They cannot measure their own work. Each visit,
  `core.process_secondary_entity` gives them `(meter − last_seen_meter) × secondary-progression-rate`
  credits and bookmarks the meter. Their status is never checked and their own speed never
  matters — an idle inserter and a legendary big drill earn identical credits.

`plans/secondary-progression-meter.md` explains the meter design (transfer cumulative totals,
never sampled rates) and why. That plan should be read first; this plan layers on top of it
without changing the meter.

### Why not make drills and labs primaries?

The Factorio 2.0 runtime API has no lifetime production counter for drills or labs:

- `LuaEntity.products_finished` is "Can only be used if this is CraftingMachine".
- `LuaEntity.mining_progress` / `bonus_mining_progress` exist but wrap every mining cycle
  (range `[0, mining_time]`), and a fast drill completes many cycles between batch visits,
  so deltas can't be accumulated reliably.
- `LuaFlowStatistics` (production stats) is keyed by prototype name, not per entity.

The only alternative is *estimating* work as `elapsed_ticks × theoretical_rate` gated on
status, with nothing to reconcile the estimate against. Making them primaries also means they
would deposit into the surface meter, changing what every other secondary earns, and forces a
definition of "one manufacturing hour" for a drill. We decided that is not worth it: keeping
drills and labs as secondaries and scaling what they *read* from the meter gives the intuitive
"faster machines go faster" behavior with a small, local change and no feedback loop.

### Design decisions already made

1. **Multiply, don't reallocate.** Scale each drill's/lab's own credits by its own factor,
   rather than giving the drill *type* a bigger fixed share. A burner drill and a
   fully-moduled big drill should differ.
2. **Normalize so a plain vanilla machine is 1×.** Electric mining drill (`mining_speed`
   0.5) and the vanilla lab (`researching_speed` 1) earn exactly what they earn today. Burner
   drills (0.25) get 0.5×, big drills (2.5) get 5×, biolabs (2) get 2×, before bonuses.
3. **Include productivity**, matching how the mod already treats crafting machines: the
   `crafting-speed-affects-progression` tooltip explicitly says a foundry with 50%
   productivity progresses proportionally faster. Late-game mining productivity research
   makes this multiplier large; that is the same "compounding" philosophy that setting
   already documents, and it is exactly what makes a 45/s drill feel right.
4. **Respect `crafting-speed-affects-progression`.** When that startup setting is disabled
   the factor is 1 (no compounding), so the "one hour spent working = one hour of
   progression" promise holds for drills and labs too.
5. **Gate on working status: idle drills and labs earn nothing.** The user's decision:
   "idle ones shouldn't keep progressing." A drill that is output-blocked, unpowered, or on
   a depleted patch, or a lab with no packs, gets 0 credits for that interval — the meter
   bookmark still advances, so idle time is forgone, not banked. Note that
   `manufacturing-hours-for-change`'s tooltip already promises "if it sits idle, then it will
   not progress" for machines; this brings drills and labs in line with that. The gate applies
   regardless of the crafting-speed setting.
6. **No general abstraction.** Drills and labs are the complete set of secondaries this
   applies to (asteroid collectors were considered and rejected — keep them plain
   secondaries). Write two small, explicit branches; do not build a "rate-scaled secondary"
   layer, a per-type strategy table, or a new settings surface.

### Worked example

Player's big drill: `mining_speed` 2.5 → 5× base; ~45 items/s on iron (mining time 1)
means `(1 + speed_bonus) × (1 + productivity_bonus) ≈ 18`, so the factor is ≈ 90×. Their
0.07 attempts would have been ~6 — still less than a busy furnace, but no longer baffling.
The rest of the gap is the surface *average* being dragged down by idle primaries, which is
by design and out of scope here.

## Implementation Notes

### Relevant API (Factorio 2.0 runtime, verified against current docs)

- `entity.status` — compare to `defines.entity_status.working`. Drill non-working states
  include `no_minable_resources`, `waiting_for_space_in_destination`, `no_power`,
  `low_power`, `disabled_by_control_behavior`; labs report `no_research_in_progress`,
  `no_ingredients`, etc. Only exact `working` counts.
- `entity.speed_bonus`, `entity.productivity_bonus` — `double`, valid on any entity with an
  effect receiver (drills and labs both have one). They already include modules, beacons, and
  force bonuses (`LuaForce.mining_drill_productivity_bonus`,
  `LuaForce.laboratory_speed_modifier` / `laboratory_productivity_bonus`), so nothing extra
  needs to be read from the force.
- `entity.prototype.mining_speed` — base drill speed. **Quality does not change it** (there is
  no `get_mining_speed(quality)`; drill quality only widens radius and adds module slots, which
  already show up in `speed_bonus`). Safe to cache per prototype name.
- `entity.prototype.get_researching_speed(quality)` — base lab speed. **Quality does change
  lab speed**, so pass `entity.quality`; do not use the plain `researching_speed` attribute
  and do not cache by prototype name alone. Reading it each visit is fine — labs are few.
- Reference speeds for normalization: electric mining drill `0.5`, vanilla lab `1.0`. Hard-code
  these as named constants in `progression.lua` with a comment; do not look up the vanilla
  prototypes at runtime (they may be absent or modified in overhaul mods, and a fixed
  reference keeps behavior stable).

### Where things live

- `scripts/progression.lua` — leaf module (no `require`s) shared by `core.lua` and
  `notifications.lua`. `progression.initialize(settings_data)` already receives
  `crafting_speed_affects_progression`. This is the natural home for the factor function so
  the hotkey tooltip and the batch loop compute the same number.
- `scripts/core.lua`
  - `core.get_entity_info` (~line 64) — builds `tracked_entities[id]`; `is_primary` is decided
    here. Drills and labs stay `is_primary = false`.
  - `core.process_secondary_entity` (~line 373) — where secondary credits are computed. This is
    the one place credits need scaling and gating.
  - `core.batch_process_entities` (~line 406) — calls the above; skips upgrade rolls when
    `result.credits_earned` is 0, so returning 0 for an idle drill needs no changes there.
- `scripts/notifications.lua` (~line 158) — the inspection hotkey duplicates the secondary
  credit computation to show "Credits available". It must use the same factor and gate so
  what the player sees matches what the next visit grants.
- `control.lua` (~line 228) — assembles `settings_data`; nothing new is needed unless a
  constant is promoted to a setting (it should not be).
- `locale/en/locale.cfg` — setting descriptions at lines ~86 (`crafting-speed-affects-progression`)
  and ~90 (`secondary-progression-rate`). Only English is updated; other locales are handled
  by another process (see `CLAUDE.md`).

### Performance

The batch loop visits `batch-entities-per-tick` entities per tick. The new work per drill/lab
visit is one `status` read, two bonus reads, and one prototype speed read (cacheable for
drills). All are cheap property reads on an entity already in hand — no searches, no
`find_entities`, no force lookups.

## Suggested Approach

1. In `scripts/progression.lua` add one function, e.g.
   `progression.get_secondary_rate_factor(entity)`, that returns:
   - `0` if `entity.type` is `"mining-drill"` or `"lab"` and `entity.status ~= defines.entity_status.working`;
   - `1` if the type is anything else, or if `crafting_speed_affects_progression` is false;
   - drills: `(prototype.mining_speed / 0.5) × (1 + speed_bonus) × (1 + productivity_bonus)`;
   - labs: `(prototype.get_researching_speed(entity.quality) / 1.0) × (1 + speed_bonus) × (1 + productivity_bonus)`.

   Two explicit `if entity.type == …` branches with named constants for the reference speeds.
   Cache drill `mining_speed` by prototype name in a module-local table if you like; it is
   optional.
2. In `core.process_secondary_entity`, multiply `credits_earned` by that factor. Keep the
   `last_seen_meter = meter` bookmark update unconditional so idle intervals are consumed,
   not banked.
3. In `notifications.lua`, apply the same factor to `credits_available` for the tooltip.
4. Update the two English setting descriptions (see Documentation).
5. Add a changelog entry (`/new-changelog`) and bump `info.json` version.

Things to keep an eye on:

- Guard against `nil` — `mining_speed`/`get_researching_speed` are typed optional; fall back
  to factor 1 if missing (modded drills with odd prototypes).
- `entity.status` can be `nil` for some entity states; treat non-`working` (including nil) as
  idle for drills and labs.
- Do not touch `is_primary`, the meter, or `surface_primary_counts`.

## Testing

The repo's automated tests (`tests/test_*.py`, run via `./validate.sh`) are static checks —
luacheck, Lua syntax, locale key parity, `storage` usage, require placement. There is no Lua
unit-test harness, so behavior is verified in-game.

Avoid introducing boilerplate tests; we do not want excessive pointless tests as these do not
serve anyone. It's extremely important that the tests are meaningful, clear, and validate core
issues and behavior. It's important to figure out tests that validate our business case, and
that ensure healthy core architecture. They can and should help engineers understand the
intention behind the code.

For this change that means: run `./validate.sh` (must pass, ignoring expected non-English
locale failures if you add keys — you should not need new keys, only edited descriptions), and
do the in-game checks under Validation. If a check would be materially easier with a tiny
Lua-side self-check, prefer that over a Python test that re-implements the arithmetic.

## Validation

In a test save with the mod's `manufacturing-hours-for-change` set low (e.g. 0.01) so meter
movement is visible, and a few busy assemblers on the surface so the meter advances:

- [ ] `./validate.sh` passes.
- [ ] Inspection hotkey on an **unmoduled electric mining drill** that is working shows the
      same "Credits available" as an inserter next to it (factor 1×).
- [ ] Same drill with speed modules shows proportionally more; a **big mining drill** shows ≈5×
      an unmoduled electric drill; a **burner drill** shows ≈0.5×.
- [ ] Researching mining productivity raises the drill's credits (productivity folded in).
- [ ] A drill on a **depleted patch**, or with its output belt backed up, or unpowered, shows
      0 credits available and does not gain attempts over time; once it resumes working it
      earns from that point on (idle interval was not banked).
- [ ] A **lab** actively researching earns ≈1× an inserter; a **biolab** ≈2×; a lab with no
      research/packs earns 0. A higher-quality lab earns more than a normal one of the same
      type (quality affects `researching_speed`).
- [ ] With `crafting-speed-affects-progression` **disabled** (startup setting, new save or
      restart): working drills and labs earn 1× regardless of modules/productivity; idle ones
      still earn 0.
- [ ] Non-drill/lab secondaries (inserters, poles) behave exactly as before.
- [ ] Changelog and `info.json` version updated; English locale descriptions updated.

## Documentation

- `locale/en/locale.cfg`
  - `crafting-speed-affects-progression` description: mention that mining drills and labs are
    also scaled by their mining/research speed, modules, and productivity when enabled, and
    are not when disabled.
  - `secondary-progression-rate` description: note that mining drills and labs are the
    exception to "same pace as the average primary" — they only earn while working, scaled by
    their speed and productivity.
- `changelog.txt` — new entry (Balancing) describing the drill/lab behavior and the idle
  gate; bump `info.json` version to match.
- `README.md` — the "Infrastructure" line (~line 27) lists mining drills and labs among
  secondaries; add a sentence that these two are speed-scaled and only progress while working.
- `CLAUDE.md` Core Functionality — one sentence noting drills and labs are secondaries whose
  credits are scaled by speed/productivity and gated on working status.
