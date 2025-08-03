--[[
control.lua

This script manages the quality of crafting machines.
It periodically scans all player-owned crafting machines and applies quality changes based on their hours spent working.

Why hours spent working (manufacturing_hours)?
If we only use number of items produced then machines with fast recipes grow quickly, and slow recipes grow
slowly, despite working for the same amount of time.

We can't check "hours spent working" directly, as that's not a metric tracked by the game. But we can
calculate it by looking at how many items were created, and dividing by the recipe's duration. This
gives us an accurate look at how long the machine has spent working.

Manufacturing hours do not accumulate at a constant rate. Users can place speed beacons,
productivity modules, and other modifiers that change the effective manufacturing rate. This is fine, as a
machine with upgrades (like beacons) should be impacted by quality changes faster.
]]

--- Setup locally scoped variables
local previous_qualities = {} -- lookup table for previous qualities in the chain (to make downgrades easier)
local tracked_entities -- lookup table for all the entities we might change the quality of

--- Entity types
local primary_types = {"assembling-machine", "furnace"}
local secondary_types = {"mining-drill", "lab", "inserter", "pump", "radar", "roboport"}
local tracked_types = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["mining-drill"] = true,
  ["lab"] = true,
  ["inserter"] = true,
  ["pump"] = true,
  ["radar"] = true,
  ["roboport"] = true
}

--- Setup all values defined in startup settings
local quality_change_direction = settings.startup["quality-change-direction"].value
local manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
local quality_increase_cost = settings.startup["quality-increase-cost"].value
local base_percentage_chance = settings.startup["percentage-chance-of-change"].value
local accumulation_rate_setting = settings.startup["quality-chance-accumulation-rate"].value
local accumulation_percentage = 0

if accumulation_rate_setting == "low" then
  accumulation_percentage = 20
elseif accumulation_rate_setting == "medium" then
  accumulation_percentage = 50
elseif accumulation_rate_setting == "high" then
  accumulation_percentage = 100
end

local function get_previous_quality(quality_prototype)
  if not quality_prototype then return nil end

  -- check if we need to build the lookup table
  if not next(previous_qualities) then
    for name, prototype in pairs(prototypes.quality) do  -- renamed to avoid collision
      if name ~= "quality-unknown" and prototype.next then
        previous_qualities[prototype.next.name] = prototype
      end
    end
  end

  return previous_qualities[quality_prototype.name]
end

--- Initialize the entity tracking table structure
local function ensure_tracked_entity_table(force_reset)
  -- Handle force reset by clearing everything
  if force_reset then
    storage.quality_control_entities = {}
    tracked_entities = nil
  end

  -- Otherwise initialize if tracked_entities is empty
  if not tracked_entities then
    if not storage.quality_control_entities then
      storage.quality_control_entities = {}
    end
    tracked_entities = storage.quality_control_entities
  end
end

--- Gets or creates entity metrics for a specific entity
local function get_entity_info(entity)
  ensure_tracked_entity_table()

  local id = entity.unit_number
  local entity_type = entity.type
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = quality_change_direction == "increase" and entity.quality.next
  local can_decrease = quality_change_direction == "decrease" and previous_quality

  -- ensure the entity type table exists
  if not tracked_entities[entity_type] then
    tracked_entities[entity_type] = {}
    tracked_entities[entity_type]._keys = {} -- Array for O(1) random access
    tracked_entities[entity_type]._key_positions = {} -- Reverse mapping: key -> position in _keys array
  end

  -- if the unit doesn't exist, then initialize it
  if not tracked_entities[entity_type][id] then
    tracked_entities[entity_type][id] = {
      id = id,
      entity_type = entity_type,
      chance_to_change = base_percentage_chance,
      attempts_to_change = 0
    }
    -- Only assembling machines and furnaces track manufacturing hours
    if entity_type == "assembling-machine" or entity_type == "furnace" then
      tracked_entities[entity_type][id].manufacturing_hours = 0
    end
    -- Add to keys array for efficient random access
    local keys = tracked_entities[entity_type]._keys
    local key_positions = tracked_entities[entity_type]._key_positions
    table.insert(keys, id)
    key_positions[id] = #keys
  end

  -- calculate this fresh every time we lookup entity
  tracked_entities[entity_type][id].previous_quality = previous_quality
  tracked_entities[entity_type][id].can_change_quality = can_increase or can_decrease

  return tracked_entities[entity_type][id]
end

--- Scans all surfaces and populates entity data
local function scan_and_populate_entities()
  ensure_tracked_entity_table()
    for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace", "mining-drill", "lab", "inserter", "pump", "radar", "roboport"},
      force = game.player.force
    }

    for _, entity in ipairs(entities) do
      get_entity_info(entity) -- This will initialize the entity in tracked_entities
    end
  end
end

--- Cleans up data for a specific entity that was destroyed
local function remove_entity_info(entity_type, id)
  ensure_tracked_entity_table()
  if tracked_entities[entity_type] then
    tracked_entities[entity_type][id] = nil

    -- Remove from keys array using swap-with-last technique for O(1) removal
    local keys = tracked_entities[entity_type]._keys
    local key_positions = tracked_entities[entity_type]._key_positions
    local position = key_positions[id]

    if position then
      local last_key = keys[#keys]
      keys[position] = last_key -- Move last element to removed position
      key_positions[last_key] = position -- Update position mapping for moved element
      keys[#keys] = nil -- Remove last element
      key_positions[id] = nil -- Remove position mapping for deleted element
    end
  end
end


--- Checks if an entity should be tracked and adds it if so
local function on_entity_created(event)
  local entity = event.entity or event.created_entity
  if not entity or not entity.valid then
    return
  end

  -- Check if it's a type we track and is player owned
  if tracked_types[entity.type] and entity.force == game.forces.player then
    get_entity_info(entity) -- This will initialize the entity in tracked_entities
  end
end

--- Attempts to change the quality of a machine based on chance
local function attempt_quality_change(entity)
  local random_roll = math.random()

  local entity_info = tracked_entities[entity.type][entity.unit_number]
  entity_info.attempts_to_change = entity_info.attempts_to_change + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    -- roll failed; improve it's chance for next time and return
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * accumulation_percentage / 100)
    end
    return
  end

  -- Store info before creating replacement (entity becomes invalid after fast_replace)
  local old_unit_number = entity.unit_number

  -- Determine target quality based on direction setting
  local target_quality
  if quality_change_direction == "increase" then
    target_quality = entity.quality.next
  else -- decrease
    target_quality = get_previous_quality(entity.quality)
  end

  local replacement_entity = entity.surface.create_entity {
    name = entity.name,
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    quality = target_quality,
    fast_replace = true,
    spill = false
  }

  if replacement_entity and replacement_entity.valid then
    get_entity_info(replacement_entity) -- initialize it's entry
    -- Clean up old entity data using consistent cleanup function
    remove_entity_info(entity.type, old_unit_number)

    -- Return change information
    return replacement_entity
  end

  return nil -- we attempted to replace but it failed for some reason
end

--- Iterates through all tracked entities and checks if their quality should be changed.
local function check_and_change_quality()
  ensure_tracked_entity_table()

  -- Track candidates for ratio calculation
  local entities_checked = 0
  local changes_attempted = 0
  local changes_completed = 0

  for _, entity_type in pairs(primary_types) do
    if tracked_entities[entity_type] then
      for unit_number, entity_info in pairs(tracked_entities[entity_type]) do
        -- Skip special keys used for array management
        if unit_number == "_keys" or unit_number == "_key_positions" then
          goto continue
        end

        -- Skip if entity no longer exists
        local entity = game.get_entity_by_unit_number(unit_number)
        if not entity or not entity.valid then
          remove_entity_info(entity_type, unit_number)
          goto continue
        end

        if entity_info.can_change_quality then
          entities_checked = entities_checked + 1
          local current_recipe = entity.get_recipe()
          if current_recipe then
            local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ entity.quality.level
            local recipe_time = current_recipe.prototype.energy
            local current_hours = (entity.products_finished * recipe_time) / 3600 -- total hours machine has been working, ex. 37.5
            local previous_hours = entity_info.manufacturing_hours

            -- Calculate how many thresholds have been passed since last check
            local available_hours = current_hours - previous_hours
            local thresholds_passed = math.floor(available_hours / hours_needed)

            if thresholds_passed > 0 then
              local this_entity_changes = 0

              -- Attempt quality change for each threshold passed
              for i = 1, thresholds_passed do
                changes_attempted = changes_attempted + 1
                local change_result = attempt_quality_change(entity)
                if change_result then
                  this_entity_changes = this_entity_changes + 1
                  entity = change_result
                end

                -- Select random secondary entity to attempt a change on as well
                -- the ensures the player's entities that do work that can't be tracked easily will slowly improve as well
                local random_type = secondary_types[math.random(#secondary_types)]
                if tracked_entities[random_type] and tracked_entities[random_type]._keys and #tracked_entities[random_type]._keys > 0 then
                  local keys = tracked_entities[random_type]._keys
                  local random_id = keys[math.random(#keys)]
                  local random_entity = game.get_entity_by_unit_number(random_id)
                  if random_entity and random_entity.valid then
                    local random_result = attempt_quality_change(random_entity)
                    if random_result then
                      changes_completed = changes_completed + 1
                    end
                  end
                end
              end

              changes_completed = changes_completed + this_entity_changes

              -- If no upgrades occurred, update manufacturing hours to reflect attempted thresholds
              if this_entity_changes == 0 then
                entity_info.manufacturing_hours = previous_hours + (thresholds_passed * hours_needed)
              end
            end
          end
        end

        ::continue::
      end
    end
  end

end

--- Displays quality control metrics for the selected entity
local function show_entity_quality_info(player)
  local selected_entity = player.selected

  if not selected_entity or not selected_entity.valid then
    player.print({"quality-control.no-entity-selected"})
    return
  end

  if not tracked_types[selected_entity.type] then
    player.print({"quality-control.entity-not-tracked", selected_entity.localised_name or selected_entity.name})
    return
  end

  local entity_info = get_entity_info(selected_entity)
  local is_primary_type = selected_entity.type == "assembling-machine" or selected_entity.type == "furnace"
  local current_recipe = is_primary_type and selected_entity.get_recipe and selected_entity.get_recipe()

  -- Build info message parts
  local info_parts = {}

  -- Basic entity info
  table.insert(info_parts, {"quality-control.entity-info-header", selected_entity.localised_name or selected_entity.name, selected_entity.quality.localised_name})

  -- Attempts to change
  table.insert(info_parts, {"quality-control.attempts-to-change", entity_info.attempts_to_change})

  -- Current chance of change
  table.insert(info_parts, {"quality-control.current-chance", string.format("%.2f", entity_info.chance_to_change)})

  -- Progress to next attempt (for primary types with manufacturing hours)
  if is_primary_type and current_recipe then
    local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ selected_entity.quality.level
    local recipe_time = current_recipe.prototype.energy
    local current_hours = (selected_entity.products_finished * recipe_time) / 3600
    local previous_hours = entity_info.manufacturing_hours or 0
    local progress_hours = current_hours - previous_hours
    local progress_percentage = math.min(100, (progress_hours / hours_needed) * 100)

    table.insert(info_parts, {"quality-control.progress-to-next", string.format("%.1f", progress_percentage)})
    table.insert(info_parts, {"quality-control.manufacturing-hours", string.format("%.2f", current_hours), string.format("%.2f", hours_needed)})
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

--- Event handler for quality control inspect shortcut
local function on_quality_control_inspect(event)
  local player = game.get_player(event.player_index)
  if player then
    show_entity_quality_info(player)
  end
end

--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  local player = game.get_player(command.player_index)
  if not player then return end

  ensure_tracked_entity_table(true)
  scan_and_populate_entities()
  player.print("Quality Control storage reinitialized. All machines have been rescanned.")
end

--- Registers the nth_tick event based on the current setting
local function register_nth_tick_event()
  -- Clear any existing nth_tick registration
  script.on_nth_tick(nil)

  -- Get the frequency setting in seconds and convert to ticks (60 ticks = 1 second)
  local check_interval_seconds = settings.global["upgrade-check-frequency-seconds"].value
  local check_interval_ticks = math.max(60, math.floor(check_interval_seconds * 60))

  -- Register the new nth_tick event
  script.on_nth_tick(check_interval_ticks, check_and_change_quality)
end

--- Event handler for entity destruction - cleans up entity data
local function on_entity_destroyed(event)
  local entity = event.entity
  if entity and entity.valid then
    remove_entity_info(entity.type, entity.unit_number)
  end
end

-- Register event handlers for entity creation
script.on_event(defines.events.on_built_entity, on_entity_created)
script.on_event(defines.events.on_robot_built_entity, on_entity_created)
script.on_event(defines.events.on_space_platform_built_entity, on_entity_created)
script.on_event(defines.events.script_raised_built, on_entity_created)
script.on_event(defines.events.script_raised_revive, on_entity_created)
script.on_event(defines.events.on_entity_cloned, on_entity_created)

-- Register event handlers for entity destruction/deconstruction
script.on_event(defines.events.on_player_mined_entity, on_entity_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_entity_destroyed)
script.on_event(defines.events.on_space_platform_mined_entity, on_entity_destroyed)
script.on_event(defines.events.on_entity_died, on_entity_destroyed)
script.on_event(defines.events.script_raised_destroy, on_entity_destroyed)

-- Register event handler for quality control inspect shortcut
script.on_event("quality-control-inspect-entity", on_quality_control_inspect)

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize quality lookup on first load
script.on_init(function()
  scan_and_populate_entities()
  register_nth_tick_event()
end)

-- Rebuild quality lookup when configuration changes (mods added/removed)
script.on_configuration_changed(function(event)
  -- Reset quality lookup cache
  previous_qualities = {}

  -- Reset tracked entities data
  storage.quality_control_entities = {}

  register_nth_tick_event()
end)

-- Handle runtime setting changes
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "upgrade-check-frequency-seconds" then
    register_nth_tick_event()
  end
end)

