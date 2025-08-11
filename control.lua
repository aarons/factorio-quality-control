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
local debug_enabled = false
local previous_qualities = {} -- lookup table for previous qualities in the chain (to make downgrades easier)
local tracked_entities -- lookup table for all the entities we might change the quality of

--- Batch processing state (simple rolling window for secondary entity ratios)
local rolling_ratio = {
  attempts = 0,
  entities = 0,
  window_size = 10000 -- reset counters after this many primary entities processed
}

--- Helper function for debug logging
local function debug(message)
  if debug_enabled then
    log("debug: " .. message)
  end
end

local entity_categories = {
  primary = {
    ["assembling-machine"] = "assembly-machines",
    ["furnace"] = "furnaces",
    ["rocket-silo"] = "other-production"
  },
  electrical = {
    "electric-pole", "solar-panel", "accumulator", "generator", "reactor", "boiler", "heat-pipe",
    "power-switch", "lightning-rod"
  },
  other_production = {
    "agricultural-tower", "mining-drill"
  },
  defense = {
    "turret", "artillery-turret", "wall", "gate"
  },
  space = {
    "asteroid-collector", "thruster", "cargo-landing-pad"
  },
  other = {
    "lamp", "arithmetic-combinator", "decider-combinator", "constant-combinator", "programmable-speaker"
  },
  standalone = {
    lab = "enable-labs",
    roboport = "enable-roboports",
    beacon = "enable-beacons",
    pump = "enable-pumps",
    ["offshore-pump"] = "enable-pumps",
    radar = "enable-radar",
    inserter = "enable-inserters"
  }
}

local function build_entity_type_lists()
  local primary_types = {}
  local secondary_types = {}
  local all_tracked_types = {}

  local primary_setting = settings.startup["primary-entities-selection"].value
  if primary_setting == "both" or primary_setting == "assembly-machines-only" then
    table.insert(primary_types, "assembling-machine")
    table.insert(all_tracked_types, "assembling-machine")
  end
  if primary_setting == "both" or primary_setting == "furnaces-only" then
    table.insert(primary_types, "furnace")
    table.insert(all_tracked_types, "furnace")
  end

  if settings.startup["enable-other-production-entities"].value then
    table.insert(secondary_types, "rocket-silo")
    table.insert(all_tracked_types, "rocket-silo")
  end

  if settings.startup["enable-electrical-entities"].value then
    for _, entity_type in ipairs(entity_categories.electrical) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-other-production-entities"].value then
    for _, entity_type in ipairs(entity_categories.other_production) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-defense-entities"].value then
    for _, entity_type in ipairs(entity_categories.defense) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-space-entities"].value then
    for _, entity_type in ipairs(entity_categories.space) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-other-entities"].value then
    for _, entity_type in ipairs(entity_categories.other) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  for entity_type, setting_name in pairs(entity_categories.standalone) do
    if settings.startup[setting_name].value then
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  return primary_types, secondary_types, all_tracked_types
end

local _, _, all_tracked_types = build_entity_type_lists()

local is_tracked_type = {}
for _, entity_type in ipairs(all_tracked_types) do
  is_tracked_type[entity_type] = true
end

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

--- Build the previous quality lookup table (called once during init)
local function build_previous_quality_lookup()
  for name, prototype in pairs(prototypes.quality) do
    if name ~= "quality-unknown" and prototype.next then
      previous_qualities[prototype.next.name] = prototype
    end
  end
end

local function get_previous_quality(quality_prototype)
  return previous_qualities[quality_prototype.name]
end


--- Gets or creates entity metrics for a specific entity
local function get_entity_info(entity)
  debug("get_entity_info called for entity type: " .. (entity.type or "unknown"))

  local id = entity.unit_number
  local entity_type = entity.type
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = quality_change_direction == "increase" and entity.quality.next ~= nil
  local can_decrease = quality_change_direction == "decrease" and previous_quality ~= nil

  -- Check if entity type is primary (assembling-machine or furnace)
  local is_primary = (entity_type == "assembling-machine" or entity_type == "furnace")

  -- if the unit doesn't exist, then initialize it
  if not tracked_entities[id] then
    tracked_entities[id] = {
      entity = entity,
      entity_type = entity_type,
      is_primary = is_primary,
      chance_to_change = base_percentage_chance,
      attempts_to_change = 0,
      can_change_quality = can_increase or can_decrease
    }
    -- Only primary entities track manufacturing hours
    if is_primary then
      tracked_entities[id].manufacturing_hours = 0
    end
  end

  return tracked_entities[id]
end

--- Scans all surfaces and populates entity data
local function scan_and_populate_entities()
  debug("scan_and_populate_entities called")
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = all_tracked_types,
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      get_entity_info(entity) -- This will initialize the entity in tracked_entities
    end
  end
end

--- Cleans up data for a specific entity that was destroyed
local function remove_entity_info(id)
  if tracked_entities then
    tracked_entities[id] = nil
  end
end

--- Checks if an entity should be tracked and adds it if so
local function on_entity_created(event)
  debug("on_entity_created called")
  local entity = event.entity or event.created_entity

  -- Check if it's a type we track and is player owned
  if is_tracked_type[entity.type] and entity.force == game.forces.player then
    get_entity_info(entity)
  end
end

--- Shows entity-specific quality change alert to the player
local function show_entity_quality_alert(entity, change_type)
  debug("show_entity_quality_alert called")
  local player = game.players[1] -- In single player, this is the player
  if player and settings.get_player_settings(player)["quality-change-entity-alerts-enabled"].value then
    local action = change_type == "increase" and "upgraded" or "downgraded"
    local message = action .. " quality to " .. entity.quality.name

    player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = entity.quality.name}, message, true)
  end
end

--- Attempts to change the quality of a machine based on chance
local function attempt_quality_change(entity)
  debug("attempt_quality_change called for entity type: " .. entity.type .. ", id: " .. tostring(entity.unit_number))

  local random_roll = math.random()
  local entity_info = tracked_entities[entity.unit_number]

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
    spill = false,
    raise_built=true,
  }

  debug("replacement_entity valid: " .. tostring(replacement_entity))
  if replacement_entity and replacement_entity.valid then
    remove_entity_info(old_unit_number)

    -- Update module quality when entity quality changes
    local module_setting = settings.startup["change-modules-with-entity"].value
    if module_setting ~= "disabled" then
      local module_inventory = replacement_entity.get_module_inventory()
      if module_inventory then
        for i = 1, #module_inventory do
          local stack = module_inventory[i]
          if stack.valid_for_read and stack.is_module then
            local module_name = stack.name
            local current_module_quality = stack.quality
            local new_module_quality = nil

            if module_setting == "enabled" then
              -- Original behavior: modules change by one tier in same direction as entity
              if quality_change_direction == "increase" then
                -- For upgrades: only bump modules that are lower tier than the new machine quality
                if current_module_quality.level < target_quality.level and current_module_quality.next then
                  new_module_quality = current_module_quality.next
                end
              else -- decrease
                -- For downgrades: only bump down modules that are higher tier than the new machine quality
                if current_module_quality.level > target_quality.level then
                  new_module_quality = get_previous_quality(current_module_quality)
                end
              end
            elseif module_setting == "extra-enabled" then
              -- New behavior: modules match the entity's quality level exactly
              if current_module_quality.level ~= target_quality.level then
                new_module_quality = target_quality
              end
            end

            -- Apply the quality change if we determined a new quality
            if new_module_quality then
              stack.clear()
              module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
            end
          end
        end
      end
    end

    show_entity_quality_alert(replacement_entity, quality_change_direction)

    -- Return the replacement entity
    return replacement_entity
  end

  return nil -- we attempted to replace but it failed
end



--- Shows quality change notifications based on user settings
local function show_quality_notifications(quality_changes)
  debug("show_quality_notifications called")
  -- Show aggregate console alerts if enabled
  local player = game.players[1]
  if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
    local messages = {}

    for entity_name, count in pairs(quality_changes) do
      local action = quality_change_direction == "increase" and "upgraded" or "downgraded"
      local plural = count > 1 and "s" or ""

      table.insert(messages, count .. " " .. entity_name .. plural .. " " .. action)
    end

    if #messages > 0 then
      player.print("Quality Control Updates:\n" .. table.concat(messages, "\n"))
    end
  end
end

--- Setup all data structures needed for the mod
local function setup_data_structures(force_reset)
  -- Handle force reset by clearing everything
  if force_reset then
    storage.quality_control_entities = {}
  end

  -- Initialize storage tables
  if not storage.quality_control_entities then
    storage.quality_control_entities = {}
  end
  tracked_entities = storage.quality_control_entities

  build_previous_quality_lookup()

  if not storage.last_processed_key then
    storage.last_processed_key = nil
  end

  if not storage.rolling_ratio then
    storage.rolling_ratio = {attempts = 0, entities = 0}
  end

  storage.batch_processing_initialized = true
end

--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  debug("reinitialize_quality_control_storage called")

  -- Notify player that rebuild is starting
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  -- Full reinitialization: setup data structures and rescan entities
  setup_data_structures(true)  -- Clear existing data
  scan_and_populate_entities()

  -- Notify player that rebuild is complete
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Cache rebuild complete. All entities have been scanned.")
    end
  end
end

--- Process entities in batches to avoid performance spikes
local function batch_process_entities()
  debug("batch_process_entities called")

  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}
  local ratio = storage.rolling_ratio

  -- Process entities using next() for natural iteration
  while entities_processed < batch_size do
    local unit_number, entity_info = next(tracked_entities, storage.last_processed_key)

    if not unit_number then
      -- Finished the table, reset for next cycle
      storage.last_processed_key = nil

      -- Reset rolling ratio counters periodically
      if ratio.entities > rolling_ratio.window_size then
        ratio.attempts = math.floor(ratio.attempts / 2)
        ratio.entities = math.floor(ratio.entities / 2)
      end
      break
    end

    local entity = entity_info.entity
    if not entity or not entity.valid then
      debug("entity invalid: " .. tostring(unit_number))
      remove_entity_info(unit_number)
    else
      -- Process entity based on whether it's primary or secondary
      if entity_info.is_primary and entity_info.can_change_quality then
        -- Primary entity logic (manufacturing hours)
        local current_recipe = entity.get_recipe()
        if current_recipe then
          local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ entity.quality.level
          local recipe_time = current_recipe.prototype.energy
          local current_hours = (entity.products_finished * recipe_time) / 3600
          local previous_hours = entity_info.manufacturing_hours or 0

          local available_hours = current_hours - previous_hours
          local thresholds_passed = math.floor(available_hours / hours_needed)

          if thresholds_passed > 0 then
            ratio.attempts = ratio.attempts + thresholds_passed
            ratio.entities = ratio.entities + 1

            local successful_change = false
            for _ = 1, thresholds_passed do
              local change_result = attempt_quality_change(entity)
              if change_result then
                successful_change = true
                quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
                break
              end
            end

            if not successful_change then
              entity_info.manufacturing_hours = previous_hours + (thresholds_passed * hours_needed)
            end
          end
        end
      elseif not entity_info.is_primary and entity_info.can_change_quality then
        -- Secondary entity logic (uses ratio from primary entities)
        local current_ratio = ratio.entities > 0 and (ratio.attempts / ratio.entities) or 0
        if current_ratio > 0 and math.random() < current_ratio then
          local change_result = attempt_quality_change(entity)
          if change_result then
            quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
          end
        end
      end
    end

    storage.last_processed_key = unit_number
    entities_processed = entities_processed + 1
  end

  -- Show notifications if any changes occurred
  if next(quality_changes) then
    show_quality_notifications(quality_changes)
  end

  debug("Processed " .. entities_processed .. " entities this tick")
end

--- Displays quality control metrics for the selected entity
local function show_entity_quality_info(player)
  debug("show_entity_quality_info called")
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
  local is_primary_type = entity_info.is_primary
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
  debug("on_quality_control_inspect called")
  local player = game.get_player(event.player_index)
  if player then
    show_entity_quality_info(player)
  end
end

--- Event handler for entity destruction - cleans up entity data
local function on_entity_destroyed(event)
  debug("on_entity_destroyed called")
  local entity = event.entity
  if entity and entity.valid then
    remove_entity_info(entity.unit_number)
  end
end


--- Registers the main processing loop based on the current setting
local function register_main_loop()
  local tick_interval = settings.global["batch-ticks-between-processing"].value
  script.on_nth_tick(nil)
  script.on_nth_tick(tick_interval, batch_process_entities)
end

--- Initialize all event handlers
local function register_event_handlers()
  -- Entity creation events
  script.on_event(defines.events.on_built_entity, on_entity_created)
  script.on_event(defines.events.on_robot_built_entity, on_entity_created)
  script.on_event(defines.events.on_space_platform_built_entity, on_entity_created)
  script.on_event(defines.events.script_raised_built, on_entity_created)
  script.on_event(defines.events.script_raised_revive, on_entity_created)
  script.on_event(defines.events.on_entity_cloned, on_entity_created)

  -- Entity destruction events
  script.on_event(defines.events.on_player_mined_entity, on_entity_destroyed)
  script.on_event(defines.events.on_robot_mined_entity, on_entity_destroyed)
  script.on_event(defines.events.on_space_platform_mined_entity, on_entity_destroyed)
  script.on_event(defines.events.on_entity_died, on_entity_destroyed)
  script.on_event(defines.events.script_raised_destroy, on_entity_destroyed)

  -- Quality control inspect shortcut
  script.on_event("quality-control-inspect-entity", on_quality_control_inspect)

  -- Runtime setting changes
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "batch-ticks-between-processing" then
      if storage.batch_processing_initialized then
        register_main_loop()
      end
    end
  end)

  -- Start the main processing loop
  register_main_loop()
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
script.on_init(function()
  setup_data_structures()
  scan_and_populate_entities()
  register_event_handlers()
end)

-- Handle startup setting changes and mod version updates
script.on_configuration_changed(function(event)
  reinitialize_quality_control_storage()
  storage.batch_processing_initialized = false
  register_event_handlers()
end)

-- Handle save game loading
-- Uses delayed initialization pattern because on_load has restrictions:
-- - No access to game object
-- - Storage table is read-only
-- - Can only set up metatables and event handlers
-- The one-tick delay ensures full game access when initializing
script.on_load(function()
  script.on_nth_tick(60, function()
    script.on_nth_tick(nil)  -- Unregister to run only once
    setup_data_structures()
    register_event_handlers()
  end)
end)
