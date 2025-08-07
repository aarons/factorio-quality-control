# factorio-quality-control

This mod changes the quality of machines after a certain amount of processing.

Use ./package.sh to package it up into a zip file, for testing changes locally. You will need to copy that zip to your local factorio mods folder.


## Performance Optimization Plan

### Target Metrics
- **Goal**: Keep script execution under 1ms per tick (out of 16.67ms total)
- **Current Issue**: Script can take up to 60ms on large bases
- **UPS Impact**: Must minimize to prevent game slowdown

### 1. Replace Entity Tracking with Factorio's Native Methods

#### Current Implementation Problems
- Maintains own `tracked_entities` table with event listeners
- Duplicates Factorio's internal entity management
- Memory overhead from storing entity references
- Event listener overhead for creation/destruction

#### Proposed Solution
- **Use `find_entities_filtered()` directly** instead of maintaining own list
- Store only metrics (manufacturing hours, attempts) keyed by unit_number
- Leverage Factorio's highly optimized C++ entity lookup
- Remove entity creation/destruction event listeners (lines 633-645)
- Benefits:
  - Reduced memory usage
  - No stale entity references
  - Leverages game's optimized entity management
  - Simpler code maintenance

### 2. Quality-Based Entity Filtering

#### Implementation Strategy
- When `difficulty = "common"` (always upgrade):
  - Only search for entities with `quality < legendary`
- When `difficulty = "legendary"` (always downgrade):
  - Only search for entities with `quality > normal`
- Use quality comparison in `find_entities_filtered()`:
  ```lua
  surface.find_entities_filtered{
    type = entity_type,
    quality = {comparison = "<", value = "legendary"}
  }
  ```
- Skip entities at quality boundaries that can't change

### 3. Incremental Entity Type Processing

#### Current Problem
- Processes all entity types in single tick
- Can cause lag spikes with many entities

#### Solution: Round-Robin Processing
- Process one entity type per tick
- Maintain state: `current_type_index`
- Track processing metrics per type:
  - Average processing time
  - Entity count
  - Priority weight
- Group small entity types together
- Process high-count types (inserters, belts) separately
- Example flow:
  ```
  Tick 1: assembling-machines (high priority)
  Tick 2: furnaces
  Tick 3: inserters (potentially thousands)
  Tick 4: small types grouped (labs + pumps + radars)
  ```

### 4. Spatial Partitioning for Large Surfaces

#### Coordinate-Based Search Strategy
- Divide surface into chunks (e.g., 256x256 tiles)
- Process one chunk per tick
- Use `area` parameter in find_entities_filtered:
  ```lua
  surface.find_entities_filtered{
    area = {{x1, y1}, {x2, y2}},
    type = entity_type
  }
  ```
- Maintain chunk processing state:
  - Current chunk coordinates
  - Chunks processed this cycle
  - Chunk entity density map (for adaptive processing)

#### Adaptive Chunk Processing
- Use `count_entities_filtered()` first to measure density
- Skip empty chunks
- Subdivide dense chunks
- Process multiple sparse chunks per tick

### 5. Lua Operation Optimizations

#### Remove Redundant Validations
- `find_entities_filtered()` returns only valid entities
- Remove `.valid` checks within same tick (line 422, 493)
- Trust Factorio's guarantees about entity validity

#### Optimize Hot Path Operations
- Cache `entity.quality.level` instead of multiple accesses
- Pre-calculate `hours_needed` formulas
- Use local variables for repeated table lookups
- Batch similar operations together

#### Memory Access Patterns
- Access entity properties once, store in locals
- Minimize table traversals
- Use numeric indices where possible
- Avoid creating temporary tables in loops

### 6. Dynamic Performance Throttling

#### Adaptive Processing
- Measure execution time using Factorio's profiler
- Dynamically adjust entities processed per tick
- Target budget: 0.5-1ms per tick
- Implementation:
  ```lua
  local start_time = game.tick_paused and 0 or game.create_profiler()
  -- process entities
  local elapsed = start_time and start_time.stop() or 0
  adjust_processing_rate(elapsed)
  ```

#### Load Balancing
- Track running average of processing time
- Increase/decrease batch size based on performance

### 7. Parallel Processing Considerations

#### Factorio Limitations
- Lua is single-threaded in Factorio
- No true parallel execution available
- Must work within tick constraints

#### Workarounds
- **Time-slice processing**: Spread work across multiple ticks
- **Predictive processing**: Calculate future states in idle ticks (see expanded section below)
- **Batch operations**: Group similar operations for cache efficiency
- **Async patterns**: Process results from previous ticks

### 7a. Predictive Processing - Smart Check Scheduling

#### Core Concept
Instead of checking every machine on every cycle, calculate when each machine will actually need its next quality check based on its production rate.

#### Implementation Strategy

##### Track Production Rate Delta
```lua
-- Store with each entity:
{
  last_products_finished = 150,
  last_check_tick = 12000,
  current_products_finished = 175,
  current_check_tick = 18000,
  products_per_tick = 0.00417,  -- (175-150)/(18000-12000)
  estimated_next_check_tick = 24000
}
```

##### Calculate Minimum Check Time
Using Factorio's crafting speed API:
```lua
function calculate_next_check_time(entity, entity_info)
  local recipe = entity.get_recipe()
  if not recipe then
    return nil  -- No recipe, check again soon
  end

  -- Get effective crafting speed with all modifiers
  local base_speed = entity.prototype.crafting_speed
  local speed_bonus = entity.speed_bonus or 0
  local effective_speed = base_speed * (1 + speed_bonus)

  -- Get productivity bonus for accurate production rate
  local effects = entity.get_module_effects()
  local productivity = effects and effects.productivity and
                      effects.productivity.bonus or 0

  -- Calculate actual items per second
  local recipe_time = recipe.energy
  local items_per_second = effective_speed / recipe_time * (1 + productivity)

  -- Manufacturing hours needed for next threshold
  local quality_level = entity.quality.level
  local hours_needed = manufacturing_hours_for_change *
                      (1 + quality_increase_cost) ^ quality_level
  local hours_remaining = hours_needed - entity_info.accumulated_hours

  -- Products needed to reach threshold
  local products_needed = (hours_remaining * 3600) / recipe_time

  -- Ticks until threshold (60 ticks = 1 second)
  local ticks_needed = products_needed / items_per_second * 60

  -- Add small buffer for timing variations
  return game.tick + math.floor(ticks_needed * 0.95)
end
```

##### Priority Queue System
```lua
-- Maintain a sorted list of when to check each entity
check_schedule = {
  {tick = 15000, entity_id = 12345, type = "assembling-machine"},
  {tick = 15600, entity_id = 67890, type = "furnace"},
  {tick = 16200, entity_id = 11111, type = "assembling-machine"},
  -- ...
}

-- On each tick, only process entities that are due
function on_tick(event)
  while check_schedule[1] and check_schedule[1].tick <= event.tick do
    local scheduled = table.remove(check_schedule, 1)
    process_entity(scheduled)
    -- Reschedule for next check
    local next_tick = calculate_next_check_time(entity, info)
    if next_tick then
      insert_sorted(check_schedule, {
        tick = next_tick,
        entity_id = scheduled.entity_id,
        type = scheduled.type
      })
    end
  end
end
```

#### Beacon Change Detection

##### Surface-Level Beacon Tracking
```lua
-- Track beacon changes per surface
surface_beacon_state = {
  [surface_index] = {
    last_change_tick = 12000,
    beacon_count = 45,
    invalidate_predictions = false
  }
}

-- On beacon add/remove events
function on_beacon_changed(event)
  local surface = event.entity.surface
  surface_beacon_state[surface.index].last_change_tick = event.tick
  surface_beacon_state[surface.index].invalidate_predictions = true
end
```

##### Invalidation Strategy
When beacons change:
1. Mark all predictions on that surface as invalid
2. Recalculate affected machines in next check
3. Use wider check radius around new/removed beacon
4. Gradually return to predictive mode

#### Benefits
- **Reduces unnecessary checks by 80-95%** on stable factories
- **Scales with factory size** - more machines don't mean more checks per tick
- **Adapts to production changes** - automatically adjusts when recipes or modules change
- **Minimal overhead** - simple arithmetic vs. full entity processing

#### Edge Cases to Handle
- Recipe changes invalidate predictions
- Module changes affect speed calculations
- Quality changes alter threshold requirements
- Machines running out of ingredients
- Power outages affecting production rate

#### Fallback Mechanism
- Maximum prediction window (e.g., 1 minute)
- Periodic full sweeps to catch edge cases
- Immediate checks on recipe/module changes
- Invalidate predictions on beacon modifications

### 8. Caching and Memoization

#### Recipe Time Cache
- Cache `recipe.prototype.energy` values
- Invalidate on recipe changes only
- Significant savings for repeated lookups

#### Quality Chain Cache
- Pre-build quality progression chains on init
- Store as simple array lookups
- Eliminate repeated quality calculations

#### Entity Type Lookups
- Build reverse lookup tables for entity types
- Cache prototype data that doesn't change
- Minimize prototype access in hot paths

### 9. Event-Driven vs Polling Trade-offs

#### Hybrid Approach
- Use events for recipe changes (important but rare)
- Poll for entity existence (avoids event overhead)
- Balance based on frequency and cost

### 10. Profiling and Metrics

#### Performance Monitoring
- Add configurable performance logging
- Track per-operation timings
- Identify bottlenecks in production
- Example metrics:
  - Entities processed per tick
  - Average processing time per entity type
  - Cache hit rates
  - Memory usage trends

#### Debug Mode Enhancements
- Add detailed timing breakdowns
- Entity count statistics
- Processing rate graphs
- Performance regression detection

### 11. Additional Optimization Strategies

#### Early Exit Conditions
- Skip surfaces with no entities of target type
- Exit immediately when time budget exceeded
- Bail out if no entities can change quality (all at max/min)
- Check global flags before processing

#### Lazy Evaluation
- Defer calculations until actually needed
- Don't calculate manufacturing hours for entities without recipes
- Skip chance calculations if at 100% probability
- Avoid quality checks for entities that can't change

#### Batch Quality Changes
- Group entities by same quality level
- Apply changes in bulk where possible
- Reduce individual entity operations
- Minimize surface.create_entity calls

#### Smart Scheduling
- Process during low-activity periods
- Skip processing when game is paused
- Reduce frequency during combat/high activity
- Adaptive scheduling based on game state

#### Memory Pool Pattern
- Pre-allocate tables for temporary data
- Reuse tables instead of creating new ones
- Clear and reuse instead of garbage collection
- Reduce allocation pressure

#### String Optimization
- Intern commonly used strings
- Avoid string concatenation in loops
- Cache localized names
- Use numeric IDs where possible

#### Network Optimization (Multiplayer)
- Minimize data sent between clients
- Batch notifications
- Use deterministic random seeds
- Reduce sync requirements

## Implementation Priority

### Phase 1: Quick Wins (1-2 hours)
1. Local variable optimizations
1. Switch to find_entities_filtered approach
  1. Add quality filtering to searches
  2. Remove redundant `.valid` checks
3. Cache recipe times (?)

### Phase 2: Core Refactor (4-6 hours)
2. Pair down entity tracking table (just metrics)
3. Implement entity type round-robin
4. Add performance metrics

### Phase 3: Advanced Optimizations (2-4 hours)
1. Spatial partitioning for large bases
2. Dynamic performance throttling
3. Adaptive batch sizing
4. Comprehensive profiling

## Testing Strategy

- Create test worlds with varying entity counts
- Measure UPS impact before/after each optimization
- Profile with Factorio's built-in tools
- Test edge cases (empty surfaces, max quality entities)
- Validate quality change behavior unchanged

