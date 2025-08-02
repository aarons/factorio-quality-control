--[[
control.lua

This script manages the quality of crafting machines.
It periodically scans all player-owned crafting machines and applies quality changes based on their hours spent making items.
Each machine is tracked individually and only checked once per manufacturing_hours period.

IMPORTANT NOTE: Manufacturing hours do not accumulate at a constant rate. Users can place speed beacons,
productivity modules, and other modifiers that change the effective manufacturing rate. Therefore, we track
the last manufacturing_hours threshold that was checked for each machine.
]]

--- Cache for quality information to avoid repeated lookups
local qualities = {}

--- Initializes the storage for machine tracking data
local function init_machine_data()
  if not storage.machine_data then
    storage.machine_data = {}
  end
end

--- Gets or creates entity tracking data for the given unit number
--- @param unit_number uint The unit number of the entity
--- @return table The entity data table
local function get_entity_info(unit_number)
  if not storage.machine_data then
    storage.machine_data = {}
  end
  
  if not storage.machine_data[unit_number] then
    storage.machine_data[unit_number] = {}
  end
  
  return storage.machine_data[unit_number]
end

--- Cleans up data for a specific machine that was destroyed
--- @param entity LuaEntity The entity that was destroyed
local function cleanup_single_machine_data(entity)
  if storage.machine_data and entity.unit_number then
    storage.machine_data[entity.unit_number] = nil
  end
end

--- Builds a cache of all quality prototypes and their next/previous relationships
local function build_quality_lookup()
  qualities = {}
  for name, quality_prototype in pairs(prototypes.quality) do
    -- Skip quality-unknown as it's not part of the normal quality chain
    if name ~= "quality-unknown" then
      qualities[name] = {
        prototype = quality_prototype,
        next = quality_prototype.next and quality_prototype.next.name or nil,
        previous = nil
      }
    end
  end

  -- Fill in the previous relationships
  for name, quality_info in pairs(qualities) do
    if quality_info.next then
      qualities[quality_info.next].previous = name
    end
  end

end

--- Gets the next quality in the specified direction
--- @param current_quality LuaQualityPrototype
--- @param direction string "increase" or "decrease"
--- @return LuaQualityPrototype|nil
local function get_next_quality(current_quality, direction)
  if not current_quality then return nil end

  local current_name = current_quality.name
  local quality_info = qualities[current_name]

  if not quality_info then return nil end

  local next_quality_name
  if direction == "increase" then
    next_quality_name = quality_info.next
  else -- direction == "decrease"
    next_quality_name = quality_info.previous
  end

  if next_quality_name and qualities[next_quality_name] then
    return qualities[next_quality_name].prototype
  end

  return nil
end

--- Attempts to change the quality of a machine based on a random roll.
--- @param machine LuaEntity The machine to potentially change.
--- @param next_quality LuaQualityPrototype The quality to change to.
--- @param percentage_chance number The chance of the quality change occurring.
--- @return table|nil Returns table with change info if successful: {entity=LuaEntity, old_quality=string, new_quality=string, entity_type=string}, nil otherwise.
local function attempt_quality_change(machine, next_quality, percentage_chance)
  local random_roll = math.random()
  local chance_threshold = percentage_chance / 100

  if random_roll >= chance_threshold then
    return false -- Random roll failed, no change
  end

  -- Store info before creating replacement (machine becomes invalid after fast_replace)
  local old_unit_number = machine.unit_number
  local old_quality_name = machine.quality.name
  local entity_type = machine.type

  local replacement_entity = machine.surface.create_entity {
    name = machine.name,
    position = machine.position,
    force = machine.force,
    direction = machine.direction,
    quality = next_quality,
    fast_replace = true,
    spill = false
  }

  if replacement_entity and replacement_entity.valid then
    local new_unit_number = replacement_entity.unit_number
    local machine_data = get_entity_info(new_unit_number)

    if replacement_entity.type == "assembling-machine" or replacement_entity.type == "furnace" then
        replacement_entity.products_finished = 0
        machine_data.last_checked_threshold = 0
    end

    -- Remove old machine data using stored unit number
    storage.machine_data[old_unit_number] = nil

    -- Return change information
    return {
      entity = replacement_entity,
      old_quality = old_quality_name,
      new_quality = next_quality.name,
      entity_type = entity_type
    }
  end

  return nil -- Replacement failed
end

--- Randomly selects a specified number of entities from a list using Fisher-Yates shuffle
--- @param entities table List of entities to select from
--- @param count number Number of entities to select
--- @return table Selected entities
local function randomly_select_entities(entities, count)
  if count <= 0 then
    return {}
  end

  if count >= #entities then
    return entities
  end

  local selected = {}
  local remaining = {}

  -- Create a copy of the entities list
  for i, entity in ipairs(entities) do
    remaining[i] = entity
  end

  -- Fisher-Yates shuffle for first 'count' elements
  for i = 1, count do
    local j = math.random(i, #remaining)
    remaining[i], remaining[j] = remaining[j], remaining[i]
    table.insert(selected, remaining[i])
  end

  return selected
end

--- Applies ratio-based quality changes to additional entity types (labs, miners, inserters, etc.)
--- @param candidate_ratio number The ratio of machines that became candidates (0.0 to 1.0)
--- @param quality_changes table Existing quality changes table to add to
--- @param next_quality LuaQualityPrototype The quality to change to
--- @param percentage_chance number The chance of quality change occurring
--- @param player_force LuaForce The player's force
local function apply_ratio_based_quality_changes(candidate_ratio, quality_changes, next_quality, base_percentage_chance, accumulation_percentage, player_force)
  if candidate_ratio <= 0 then
    return -- No candidates, nothing to do
  end

  local additional_entity_types = {"mining-drill", "lab", "inserter", "pump", "radar", "roboport"}

  for _, entity_type in ipairs(additional_entity_types) do
    for _, surface in pairs(game.surfaces) do
      local entities = surface.find_entities_filtered{
        type = entity_type,
        force = player_force
      }

      if #entities > 0 then
        local target_count = math.floor(#entities * candidate_ratio)

        -- Handle edge case: ratio results in < 1 entity but entities exist
        if target_count == 0 and candidate_ratio > 0 then
          if math.random() < candidate_ratio then
            target_count = 1
          end
        end

        if target_count > 0 then
          local selected_entities = randomly_select_entities(entities, target_count)

          for _, entity in ipairs(selected_entities) do
            if entity and entity.valid then
              local unit_number = entity.unit_number
              local machine_data = get_entity_info(unit_number)
              
              -- Initialize chance if not present
              if not machine_data.current_chance then
                machine_data.current_chance = base_percentage_chance
              end
              
              local change_result = attempt_quality_change(entity, next_quality, machine_data.current_chance)
              if change_result then
                -- Reset chance after successful change
                machine_data.current_chance = base_percentage_chance
                -- Initialize the entity type array if it doesn't exist
                if not quality_changes[entity_type] then
                  quality_changes[entity_type] = {}
                end
                table.insert(quality_changes[entity_type], change_result)
              else
                -- Increment chance after failed attempt
                machine_data.current_chance = machine_data.current_chance + (base_percentage_chance * accumulation_percentage / 100)
              end
            end
          end
        end
      end
    end
  end
end

--- Creates alerts and print statements for quality changes
--- @param quality_changes table Changes grouped by entity type
--- @param quality_direction string "increase" or "decrease"
local function handle_quality_change_notifications(quality_changes, quality_direction)
  -- Count total changes by entity type
  local total_changes = 0
  local entity_type_counts = {}

  -- Count changes for all entity types
  for entity_type, changes in pairs(quality_changes) do
    local count = #changes
    if count > 0 then
      entity_type_counts[entity_type] = count
      total_changes = total_changes + count
    end
  end

  if total_changes == 0 then
    return -- No changes to report
  end

  -- Handle alerts and console messages independently for each player
  for _, player in pairs(game.players) do
    if player.valid then
      local player_settings = settings.get_player_settings(player)
      local alerts_enabled = player_settings["quality-change-alerts-enabled"].value
      local console_messages_enabled = player_settings["quality-change-console-messages-enabled"].value

      -- Create individual alerts for each changed entity (if enabled)
      if alerts_enabled then
        for entity_type, changes in pairs(quality_changes) do
          for _, change in ipairs(changes) do
            if change.entity and change.entity.valid then
              -- Determine alert message key
              local message_key = "alert-message.quality-" ..
                (quality_direction == "increase" and "upgrade" or "downgrade") ..
                "-" .. entity_type

              -- Use the entity itself as the icon (SignalID format)
              local icon = {type = "item", name = change.entity.name, quality = change.new_quality}

              -- Create the alert
              player.add_custom_alert(change.entity, icon, {message_key}, true)
            end
          end
        end
      end

      -- Print console messages (if enabled)
      if console_messages_enabled then
        local direction_text = quality_direction == "increase" and "upgraded" or "downgraded"

        -- Define user-friendly names for entity types
        local entity_type_names = {
          ["assembling-machine"] = "assembly machine",
          ["furnace"] = "furnace",
          ["mining-drill"] = "mining drill",
          ["lab"] = "lab",
          ["inserter"] = "inserter",
          ["pump"] = "pump",
          ["radar"] = "radar",
          ["roboport"] = "roboport"
        }

        -- Print message for each entity type that had changes
        for entity_type, count in pairs(entity_type_counts) do
          local friendly_name = entity_type_names[entity_type] or entity_type
          local plural_suffix = count == 1 and "" or "s"
          player.print(string.format("[Quality Control] %d %s%s quality %s",
            count, friendly_name, plural_suffix, direction_text),
            {sound_path="utility/console_message", volume_modifier=0.3})
        end
      end
    end
  end
end

--- Iterates through all player-owned crafting machines on all surfaces and checks if their quality should be changed.
local function check_and_change_quality()
  local player_force = game.forces.player
  if not player_force then
    return
  end

  -- Initialize machine data if needed
  init_machine_data()

  -- Cache settings once per cycle instead of per machine
  local quality_direction = settings.startup["quality-change-direction"].value
  local manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  local quality_level_modifier = settings.startup["quality-level-modifier"].value
  local base_percentage_chance = settings.startup["percentage-chance-of-change"].value
  local accumulation_rate_setting = settings.startup["quality-chance-accumulation-rate"].value
  local check_interval_seconds = settings.global["upgrade-check-frequency-seconds"].value
  local check_interval_ticks = math.max(60, math.floor(check_interval_seconds * 60))
  
  -- Convert accumulation rate setting to percentage multiplier
  local accumulation_percentage = 0
  if accumulation_rate_setting == "low" then
    accumulation_percentage = 20
  elseif accumulation_rate_setting == "medium" then
    accumulation_percentage = 50
  elseif accumulation_rate_setting == "high" then
    accumulation_percentage = 100
  end

  -- Track quality changes by entity type for summary reporting
  local quality_changes = {
    ["assembling-machine"] = {},
    ["furnace"] = {}
  }

  -- Track candidates for ratio calculation
  local total_machines_tracked = 0
  local candidates_attempted = 0

  for _, surface in pairs(game.surfaces) do
    local machines = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace"},
      force = player_force
    }

    for _, machine in ipairs(machines) do
      if machine and machine.valid then
        local unit_number = machine.unit_number
        local next_quality = get_next_quality(machine.quality, quality_direction)

        if next_quality then
          local machine_data = get_entity_info(unit_number)

          local current_recipe = machine.get_recipe()
          if current_recipe then
            total_machines_tracked = total_machines_tracked + 1

            local hours_for_this_level = manufacturing_hours_for_change * math.pow(1 + quality_level_modifier, machine.quality.level)
            local recipe_energy = current_recipe.prototype.energy
            local current_work_energy = machine.products_finished * recipe_energy
            local current_manufacturing_hours = current_work_energy / 3600
            local current_threshold_interval = math.floor(current_manufacturing_hours / hours_for_this_level)
            local current_threshold_hours = current_threshold_interval * hours_for_this_level

            -- Initialize machine data if not present
            if not machine_data.last_checked_threshold then
              machine_data.last_checked_threshold = current_threshold_hours
              -- Initialize chance based on past attempts (for existing machines when mod updates)
              local past_attempts = current_threshold_interval
              machine_data.current_chance = base_percentage_chance + (past_attempts * base_percentage_chance * accumulation_percentage / 100)
            end

            -- Check if we've crossed a new threshold (time for another attempt)
            if current_threshold_hours > machine_data.last_checked_threshold then
              candidates_attempted = candidates_attempted + 1
              local change_result = attempt_quality_change(machine, next_quality, machine_data.current_chance)
              if change_result then
                -- Reset chance after successful change
                machine_data.current_chance = base_percentage_chance
                machine_data.last_checked_threshold = 0 -- Reset for new quality level
                -- Track the change for alerts/reporting
                table.insert(quality_changes[change_result.entity_type], change_result)
              else
                -- Increment chance after failed attempt
                machine_data.current_chance = machine_data.current_chance + (base_percentage_chance * accumulation_percentage / 100)
                machine_data.last_checked_threshold = current_threshold_hours
              end
            end
          end
        end
      end
    end
  end

  -- Calculate candidate ratio for additional entity types
  local candidate_ratio = 0
  if total_machines_tracked > 0 then
    candidate_ratio = candidates_attempted / total_machines_tracked
  end

  -- Apply ratio-based quality changes to additional entity types
  if candidate_ratio > 0 then
    local next_quality = nil
    -- Get the next quality for additional entities (same direction as machines)
    local normal_quality = prototypes.quality["quality-normal"]
    if normal_quality then
      next_quality = get_next_quality(normal_quality, quality_direction)
    end

    if next_quality then
      apply_ratio_based_quality_changes(candidate_ratio, quality_changes, next_quality, base_percentage_chance, accumulation_percentage, player_force)
    end
  end

  -- Handle alerts and notifications for quality changes
  handle_quality_change_notifications(quality_changes, quality_direction)
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

--- Event handler for entity destruction - cleans up machine data
local function on_entity_destroyed(event)
  local entity = event.entity
  if entity and entity.valid then
    cleanup_single_machine_data(entity)
  end
end

-- Register event handlers for entity destruction/deconstruction
script.on_event(defines.events.on_entity_died, on_entity_destroyed)
script.on_event(defines.events.on_player_mined_entity, on_entity_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_entity_destroyed)

-- Initialize quality lookup on first load
script.on_init(function()
  build_quality_lookup()
  init_machine_data()
  register_nth_tick_event()
end)

-- Rebuild quality lookup when configuration changes (mods added/removed)
script.on_configuration_changed(function(event)
  build_quality_lookup()
  init_machine_data()
  register_nth_tick_event()
  if storage.machine_data then
    storage.machine_data = {}
  end
end)

-- Handle runtime setting changes
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "upgrade-check-frequency-seconds" then
    register_nth_tick_event()
  end
end)

