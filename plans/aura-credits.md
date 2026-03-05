# Aura Credit System for Secondary Entities

## Context

Currently, all secondary entities (inserters, beacons, poles, etc.) share a global credit pool equally, regardless of location. This means an inserter feeding a busy assembler advances at the same rate as an idle power pole across the map. The aura system directs 70% of credits from primary entities to nearby secondaries, creating natural spatial progression where support infrastructure levels up alongside the machines it serves.

## Design

When a primary entity earns credits during batch processing:
1. Find tracked secondary entities within bounding box + 3 tiles that can still upgrade
2. If any found: 70% of credits split equally among them as stored `aura_credits`, 30% to global pool
3. If none found (or all at max quality): 100% to global pool

When a secondary entity is processed, its total credits = global pool share + stored aura_credits. Aura credits reset to 0 after consumption.

This means nearby secondaries get a double benefit (aura + pool share), while distant secondaries still progress via the pool alone.

## Changes

### `scripts/core.lua` — Primary changes

1. **`core.initialize()`** — Add module-level local for `secondary_types` (from `storage.config.secondary_types`)

2. **`core.get_entity_info()`** (line 83) — Add `aura_credits = 0` to the entity_info table

3. **New function: `find_nearby_upgradeable_secondaries(entity)`** — placed before `process_primary_entity`:
   - Get entity bounding box, expand by 3 tiles in each direction
   - Call `entity.surface.find_entities_filtered{area=search_area, type=secondary_types, force=entity.force}`
   - Filter results to those in `tracked_entities` with `has_upgrade_path()` returning true
   - Return list of qualifying entity_info tables

4. **`core.process_primary_entity()`** (lines 305-323) — After calculating `credits_earned`:
   - Call `find_nearby_upgradeable_secondaries(entity)`
   - If nearby found: distribute `credits_earned * 0.70` equally as `aura_credits` on each, add remaining 30% to global pool
   - If none found: add 100% to global pool (current behavior)

5. **`core.process_secondary_entity(entity_info)`** (lines 325-337) — Accept `entity_info` parameter:
   - Consume `entity_info.aura_credits` (default to 0 if nil for migration safety)
   - Reset `aura_credits` to 0
   - Return `global_credits + aura_credits` as total `credits_earned`

6. **`batch_process_entities()`** (line 396) — Pass `entity_info` to `process_secondary_entity(entity_info)`

### `migrations/` — New migration file

Initialize `aura_credits = 0` on all existing tracked secondary entities for saves upgrading to this version. Follow existing migration naming pattern.

### `info.json`

Bump version for migration (next version after 2.0.3).

## Edge Cases

- **Processing order**: Aura credits stored on entity_info, consumed on next processing cycle. No ordering dependency within a single tick.
- **Max quality secondaries**: Excluded by `has_upgrade_path()` check in the spatial query, so they don't dilute the aura split. Once all nearby secondaries max out, 100% flows to global pool.
- **Untracked nearby entities**: Filtered out by the `tracked_entities[unit_number]` check.
- **Turrets as primaries**: `is_primary` already includes turrets (line 64), so they also generate aura credits for nearby secondaries.

## Performance

`find_entities_filtered` with type filter uses Factorio's spatial index — efficient per call. Called once per primary entity per batch cycle. No caching needed initially; can add if profiling shows issues.

## Verification

1. Run `./validate.sh` — all luacheck and pytest checks pass
2. In-game: place an assembler with inserters nearby, verify inserters advance faster than distant secondaries
3. Verify distant secondaries (no nearby primary) still progress via global pool
4. Test edge case: all nearby secondaries at max quality — credits should flow 100% to pool
