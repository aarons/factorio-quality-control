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
local debug_enabled = false -- Set to true to enable debug logging
local performance_test = true -- Used to help validate performance tweaks
local previous_qualities = {} -- lookup table for previous qualities in the chain (to make downgrades easier)
local tracked_entities -- lookup table for all the entities we might change the quality of

-- Batch processing state
local batch_state = {
  current_surface_index = 1,
  current_type_index = 1,
  is_processing_secondary = false,
  entities_processed_this_batch = 0,
  current_entities = nil, -- Current batch of entities from find_entities_filtered
  current_entity_index = 1
}

--- Helper function for debug logging
local function debug(message)
  if debug_enabled then
    log("debug: " .. message)
  end
end

--- Entity types - dynamically built from user settings
local primary_types = {}
local secondary_types = {}
local all_tracked_types = {}
local is_tracked_type = {}

--- Entity type configuration tables
local entity_type_config = {
  primary = {
    "assembling-machine",
    "furnace",
    "rocket-silo"
  },
  secondary = {
    -- Production entities (non-crafting machines)
    "agricultural-tower",
    -- Logistics and production support
    "mining-drill", "lab", "inserter", "pump", "radar", "roboport",
    -- Belt system
    "transport-belt", "underground-belt", "splitter", "loader",
    -- Power infrastructure
    "electric-pole", "solar-panel", "accumulator", "generator", "reactor", "boiler", "heat-pipe",
    -- Storage and logistics
    "container", "logistic-container", "storage-tank",
    -- Pipes and fluid handling
    "pipe", "pipe-to-ground", "offshore-pump",
    -- Defense structures
    "turret", "artillery-turret", "wall", "gate",
    -- Network and control
    "beacon", "arithmetic-combinator", "decider-combinator", "constant-combinator", "power-switch", "programmable-speaker",
    -- Other buildable entities
    "lamp",
    -- Space Age entities
    "lightning-rod", "asteroid-collector", "thruster", "cargo-landing-pad"
  }
}

--- Initialize entity types based on settings
local function initialize_entity_types()
  -- Clear existing tables
  primary_types = {}
  secondary_types = {}
  all_tracked_types = {}
  is_tracked_type = {}

  -- Process primary types
  for _, entity_type in ipairs(entity_type_config.primary) do
    local setting_name = "enable-" .. entity_type
    if settings.startup[setting_name] and settings.startup[setting_name].value then
      table.insert(primary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
      is_tracked_type[entity_type] = true
    end
  end

  -- Process secondary types
  for _, entity_type in ipairs(entity_type_config.secondary) do
    local setting_name = "enable-" .. entity_type
    if settings.startup[setting_name] and settings.startup[setting_name].value then
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
      is_tracked_type[entity_type] = true
    end
  end
end

-- Initialize entity types on startup
initialize_entity_types()

--- Setup all values defined in startup settings
local difficulty = settings.startup["difficulty"].value
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

--- Determines the next quality based on difficulty setting
local function get_next_quality(current_quality)
  if difficulty == "common" then
    -- Always upgrade
    return current_quality.next
  elseif difficulty == "uncommon" then
    -- 75% upgrade, 25% downgrade
    if math.random() <= 0.75 then
      return current_quality.next
    else
      return get_previous_quality(current_quality)
    end
  elseif difficulty == "rare" then
    -- 50/50 upgrade or downgrade
    if math.random() <= 0.5 then
      return current_quality.next
    else
      return get_previous_quality(current_quality)
    end
  elseif difficulty == "epic" then
    -- 25% upgrade, 75% downgrade
    if math.random() <= 0.25 then
      return current_quality.next
    else
      return get_previous_quality(current_quality)
    end
  elseif difficulty == "legendary" then
    -- Always downgrade
    return get_previous_quality(current_quality)
  end

  -- Fallback to upgrade (shouldn't happen)
  return current_quality.next
end

--- Initialize the entity tracking table structure
local function ensure_tracked_entity_table(force_reset)
  -- Fast path: if tracked_entities exists and no force reset, return immediately
  if tracked_entities and not force_reset then
    return
  end

  -- Handle force reset by clearing everything
  if force_reset then
    tracked_entities = nil
  end

  -- Initialize if tracked_entities is empty
  if not tracked_entities then
    if not storage.quality_control_entities then
      storage.quality_control_entities = {}
    end
    tracked_entities = storage.quality_control_entities

    -- Ensure all entity type tables exist (only for enabled types)
    for _, entity_type in ipairs(all_tracked_types) do
      if not tracked_entities[entity_type] then
        tracked_entities[entity_type] = {}
      end
    end
  end
end

--- Gets or creates entity metrics for a specific entity
local function get_entity_info(entity)
  -- debug("get_entity_info called for entity type: " .. (entity.type or "unknown"))

  local id = entity.unit_number
  local entity_type = entity.type

  -- Skip if this entity type is not enabled
  if not is_tracked_type[entity_type] then
    return nil
  end

  -- Ensure the entity type table exists in tracked_entities
  if not tracked_entities[entity_type] then
    tracked_entities[entity_type] = {}
  end

  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = entity.quality.next ~= nil
  local can_decrease = previous_quality ~= nil

  -- if the unit doesn't exist, then initialize it
  if not tracked_entities[entity_type][id] then
    tracked_entities[entity_type][id] = {
      entity = entity,
      chance_to_change = base_percentage_chance,
      attempts_to_change = 0,
      can_change_quality = can_increase or can_decrease
    }
    -- Only primary entity types track manufacturing hours
    if entity_type == "assembling-machine" or entity_type == "furnace" or
       entity_type == "rocket-silo" then
      tracked_entities[entity_type][id].manufacturing_hours = 0
    end
  end

  return tracked_entities[entity_type][id]
end


--- Cleans up data for a specific entity that was destroyed
local function remove_entity_info(entity_type, id)
  if is_tracked_type[entity_type] then
    ensure_tracked_entity_table()
    tracked_entities[entity_type][id] = nil
  end
end


--- Shows entity-specific quality change alert to the player
local function show_entity_quality_alert(entity, old_quality)
  -- debug("show_entity_quality_alert called")
  local player = game.players[1] -- In single player, this is the player
  if player and settings.get_player_settings(player)["quality-change-entity-alerts-enabled"].value then
    local action = entity.quality.level > old_quality.level and "upgraded" or "downgraded"
    local message = action .. " quality to " .. entity.quality.name

    player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = entity.quality.name}, message, true)
  end
end

--- Attempts to change the quality of a machine based on chance
local function attempt_quality_change(entity)
  -- debug("attempt_quality_change called for entity type: " .. entity.type .. ", id: " .. tostring(entity.unit_number))

  local entity_info = get_entity_info(entity)
  if not entity_info then
    return nil
  end

  local random_roll = math.random()
  entity_info.attempts_to_change = entity_info.attempts_to_change + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    -- roll failed; improve it's chance for next time and return
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * accumulation_percentage / 100)
    end
    return nil
  end

  -- Store info before creating replacement (entity becomes invalid after fast_replace)
  local old_unit_number = entity.unit_number
  local old_entity_type = entity.type
  local old_quality = entity.quality

  -- Determine target quality based on difficulty setting
  local target_quality = get_next_quality(entity.quality)

  -- Skip if target quality is nil (at boundary of quality chain)
  if not target_quality then
    return nil
  end

  local replacement_entity = entity.surface.create_entity {
    name = entity.name,
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    quality = target_quality,
    fast_replace = true,
    spill = false,
    raise_built=true,
  }

  -- debug("replacement_entity valid: " .. tostring(replacement_entity))
  if replacement_entity and replacement_entity.valid then
    remove_entity_info(old_entity_type, old_unit_number)
    show_entity_quality_alert(replacement_entity, old_quality)

    -- Return the replacement entity and quality information
    return {
      entity = replacement_entity,
      old_quality_level = old_quality.level,
      new_quality_level = replacement_entity.quality.level
    }
  end

  return nil -- we attempted to replace but it failed
end



--- Shows quality change notifications based on user settings
local function show_quality_notifications(quality_changes)
  -- debug("show_quality_notifications called")
  -- Show aggregate console alerts if enabled
  local player = game.players[1]
  if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
    local upgrade_messages = {}
    local downgrade_messages = {}

    for entity_name, changes in pairs(quality_changes) do
      if changes.upgrades > 0 then
        local plural = changes.upgrades > 1 and "s" or ""
        table.insert(upgrade_messages, changes.upgrades .. " " .. entity_name .. plural .. " upgraded")
      end
      if changes.downgrades > 0 then
        local plural = changes.downgrades > 1 and "s" or ""
        table.insert(downgrade_messages, changes.downgrades .. " " .. entity_name .. plural .. " downgraded")
      end
    end

    local all_messages = {}
    for _, msg in ipairs(upgrade_messages) do
      table.insert(all_messages, msg)
    end
    for _, msg in ipairs(downgrade_messages) do
      table.insert(all_messages, msg)
    end

    if #all_messages > 0 then
      player.print("Quality Control Updates:\n" .. table.concat(all_messages, "\n"))
    end
  end
end

--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  -- debug("reinitialize_quality_control_storage called")

  ensure_tracked_entity_table(true)

  -- Only print message if called from console command (with player context)
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control storage reinitialized.")
    end
  end
end


-- Global state for batch processing
local batch_processing_state = {
  primary_attempts = 0,
  primary_count = 0,
  quality_changes = {},
  cycle_complete = false
}

--- Gets the next batch of entities to process, limited to max_entities
local function get_next_entity_batch(max_entities)
  local surfaces = {}
  for _, surface in pairs(game.surfaces) do
    table.insert(surfaces, surface)
  end

  -- If we need fresh entities or finished current batch
  if not batch_state.current_entities or batch_state.current_entity_index > #batch_state.current_entities then
    -- Get the appropriate entity type list
    local type_list = batch_state.is_processing_secondary and secondary_types or primary_types

    -- Check if we need to move to next type or surface
    if batch_state.current_type_index > #type_list then
      -- Move to next processing phase or surface
      if not batch_state.is_processing_secondary then
        -- Switch to secondary types
        batch_state.is_processing_secondary = true
        batch_state.current_type_index = 1
        -- Don't reset surface index - continue on same surface
        type_list = secondary_types
      else
        -- Move to next surface
        batch_state.current_surface_index = batch_state.current_surface_index + 1
        batch_state.current_type_index = 1
        batch_state.is_processing_secondary = false

        -- Check if we've processed all surfaces
        if batch_state.current_surface_index > #surfaces then
          -- Complete cycle, reset state
          batch_state.current_surface_index = 1
          batch_state.current_type_index = 1
          batch_state.is_processing_secondary = false
          batch_processing_state.cycle_complete = true
          return nil -- Signal cycle completion
        end
        type_list = primary_types
      end
    end

    -- Skip if no types to process
    if #type_list == 0 then
      return nil
    end

    local current_surface = surfaces[batch_state.current_surface_index]
    local current_type = type_list[batch_state.current_type_index]

    -- Find entities of current type on current surface
    local entity_count = current_surface.count_entities_filtered{
      type = current_type,
      force = game.forces.player
    }
    debug("Found " .. entity_count .. " entities of type '" .. current_type .. "' on surface '" .. current_surface.name .. "'")

    batch_state.current_entities = current_surface.find_entities_filtered{
      type = current_type,
      force = game.forces.player
    }

    batch_state.current_entity_index = 1
    batch_state.current_type_index = batch_state.current_type_index + 1
  end

  -- Extract batch of entities up to max_entities
  local batch = {}
  local remaining = max_entities

  while remaining > 0 and batch_state.current_entities and batch_state.current_entity_index <= #batch_state.current_entities do
    table.insert(batch, batch_state.current_entities[batch_state.current_entity_index])
    batch_state.current_entity_index = batch_state.current_entity_index + 1
    remaining = remaining - 1
  end

  return batch
end

--- Process a batch of entities for quality changes
local function process_entity_batch(entities)
  ensure_tracked_entity_table()

  for _, entity in ipairs(entities) do
    if not entity or not entity.valid then
      goto continue
    end

    local entity_info = get_entity_info(entity)
    if not entity_info or not entity_info.can_change_quality then
      goto continue
    end

    local entity_type = entity.type
    local is_primary = false

    -- Check if this is a primary type
    for _, primary_type in ipairs(primary_types) do
      if entity_type == primary_type then
        is_primary = true
        break
      end
    end

    if is_primary then
      -- Process primary entity with manufacturing hours logic
      batch_processing_state.primary_count = batch_processing_state.primary_count + 1

      local current_recipe = entity.get_recipe and entity.get_recipe()
      if current_recipe then
        local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ entity.quality.level
        local recipe_time = current_recipe.prototype.energy
        local current_hours = (entity.products_finished * recipe_time) / 3600
        local previous_hours = entity_info.manufacturing_hours or 0

        local available_hours = current_hours - previous_hours
        local thresholds_passed = math.floor(available_hours / hours_needed)

        if thresholds_passed > 0 then
          batch_processing_state.primary_attempts = batch_processing_state.primary_attempts + thresholds_passed

          local successful_change = false
          for _ = 1, thresholds_passed do
            local change_result = attempt_quality_change(entity)
            if change_result then
              successful_change = true

              -- Track the change for notifications
              if not batch_processing_state.quality_changes[change_result.entity.name] then
                batch_processing_state.quality_changes[change_result.entity.name] = {upgrades = 0, downgrades = 0}
              end
              if change_result.new_quality_level > change_result.old_quality_level then
                batch_processing_state.quality_changes[change_result.entity.name].upgrades = batch_processing_state.quality_changes[change_result.entity.name].upgrades + 1
              else
                batch_processing_state.quality_changes[change_result.entity.name].downgrades = batch_processing_state.quality_changes[change_result.entity.name].downgrades + 1
              end

              break -- Stop trying after a success
            end
          end

          -- If no change was made, update the manufacturing hours floor
          if not successful_change then
            entity_info.manufacturing_hours = previous_hours + (thresholds_passed * hours_needed)
          end
        end
      end
    else
      -- Process secondary entity with ratio-based logic
      local secondary_ratio = batch_processing_state.primary_count > 0 and (batch_processing_state.primary_attempts / batch_processing_state.primary_count) or 0

      if secondary_ratio > 0 and math.random() < secondary_ratio then
        local change_result = attempt_quality_change(entity)
        if change_result then
          if not batch_processing_state.quality_changes[change_result.entity.name] then
            batch_processing_state.quality_changes[change_result.entity.name] = {upgrades = 0, downgrades = 0}
          end
          if change_result.new_quality_level > change_result.old_quality_level then
            batch_processing_state.quality_changes[change_result.entity.name].upgrades = batch_processing_state.quality_changes[change_result.entity.name].upgrades + 1
          else
            batch_processing_state.quality_changes[change_result.entity.name].downgrades = batch_processing_state.quality_changes[change_result.entity.name].downgrades + 1
          end
        end
      end
    end

    ::continue::
  end
end

--- Main batch processing function called on nth_tick
local function check_and_change_quality()
  -- debug("check_and_change_quality called")

  -- Skip if no entity types are enabled
  if #all_tracked_types == 0 then
    debug("No entity types enabled, skipping quality check")
    return
  end

  -- Reset state at start of new cycle
  if batch_processing_state.cycle_complete then
    -- Show notifications from previous cycle
    if next(batch_processing_state.quality_changes) then
      show_quality_notifications(batch_processing_state.quality_changes)
    end

    debug("Cycle complete - processed " .. batch_state.entities_processed_this_batch .. " total entities")

    -- Reset for new cycle
    batch_processing_state.primary_attempts = 0
    batch_processing_state.primary_count = 0
    batch_processing_state.quality_changes = {}
    batch_processing_state.cycle_complete = false
    batch_state.entities_processed_this_batch = 0

    debug("Starting new batch processing cycle")
  end

  -- Get and process next batch (max 1000 entities)
  local batch = get_next_entity_batch(1000)
  if batch and #batch > 0 then
    batch_state.entities_processed_this_batch = batch_state.entities_processed_this_batch + #batch
    debug("Processing batch: " .. #batch .. " entities (total: " .. batch_state.entities_processed_this_batch .. ")")

    process_entity_batch(batch)
  elseif not batch then
    debug("No more entities in batch - cycle completing")
  end
end

--- Displays quality control metrics for the selected entity
local function show_entity_quality_info(player)
  -- debug("show_entity_quality_info called")
  local selected_entity = player.selected

  if not selected_entity or not selected_entity.valid then
    player.print({"quality-control.no-entity-selected"})
    return
  end

  debug("Checking entity type: " .. selected_entity.type)
  debug("is_tracked_type lookup result: " .. tostring(is_tracked_type[selected_entity.type]))

  if not is_tracked_type[selected_entity.type] then
    player.print("selected_entity.type: " .. selected_entity.type)
    player.print("is_tracked_type table contents:")
    for key, value in pairs(is_tracked_type) do
      player.print("  " .. key .. " = " .. tostring(value))
    end
    player.print({"quality-control.entity-not-tracked", selected_entity.localised_name or selected_entity.name})
    return
  end

  local entity_info = get_entity_info(selected_entity)

  -- Check if entity info is nil (entity type is disabled)
  if not entity_info then
    player.print({"quality-control.entity-type-disabled", selected_entity.localised_name or selected_entity.name})
    return
  end
  local is_primary_type = false
  for _, entity_type in ipairs(primary_types) do
    if selected_entity.type == entity_type then
      is_primary_type = true
      break
    end
  end
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

    table.insert(info_parts, {"quality-control.manufacturing-hours", string.format("%.2f", current_hours), string.format("%.2f", hours_needed)})
    table.insert(info_parts, {"quality-control.progress-to-next", string.format("%.1f", progress_percentage)})
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

--- Event handler for quality control inspect shortcut
local function on_quality_control_inspect(event)
  -- debug("on_quality_control_inspect called")
  local player = game.get_player(event.player_index)
  if player then
    show_entity_quality_info(player)
  end
end

--- Registers the nth_tick event based on the current setting
local function register_nth_tick_event()
  -- debug("register_nth_tick_event called")
  local check_interval_ticks

  -- Override to 1 tick when performance testing
  if performance_test then
    check_interval_ticks = 1
  else
    -- Get the frequency setting in seconds and convert to ticks (60 ticks = 1 second)
    local check_interval_seconds = settings.global["upgrade-check-frequency-seconds"].value
    check_interval_ticks = math.max(60, math.floor(check_interval_seconds * 60))
  end

  -- Register the new nth_tick event (this will replace any existing handler for this specific tick interval)
  script.on_nth_tick(check_interval_ticks, check_and_change_quality)
end

--- Event handler for entity destruction - cleans up entity data
local function on_entity_destroyed(event)
  -- debug("on_entity_destroyed called")
  local entity = event.entity
  if entity and entity.valid then
    remove_entity_info(entity.type, entity.unit_number)
  end
end


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

-- Initialize quality lookup on a new game
script.on_init(function()
  debug("script.on_init called")
  ensure_tracked_entity_table()
  register_nth_tick_event()
end)

-- Rebuild quality lookup when configuration changes (mods added/removed)
script.on_configuration_changed(function(event)
  debug("script.on_configuration_changed called")
  -- Reset tracked entities data
  reinitialize_quality_control_storage()
  register_nth_tick_event()
end)

-- Handle runtime setting changes
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  debug("script.on_runtime_mod_setting_changed called for setting: " .. event.setting)
  if event.setting == "upgrade-check-frequency-seconds" then
    register_nth_tick_event()
  end
end)

script.on_load(function()
  debug("script.on_load called")
  register_nth_tick_event() -- register handler when loading a game
end)
