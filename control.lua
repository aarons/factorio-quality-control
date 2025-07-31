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

--- Cleans up data for a specific machine that was destroyed
--- @param entity LuaEntity The entity that was destroyed
local function cleanup_single_machine_data(entity)
  if not storage.machine_data then return end

  -- Check if this is a machine type we track
  local machine_types = {
    ["assembling-machine"] = true,
    ["furnace"] = true
  }

  if machine_types[entity.type] and entity.unit_number then
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
    storage.machine_data[new_unit_number] = {}

    if replacement_entity.type == "assembling-machine" or replacement_entity.type == "furnace" then
        replacement_entity.products_finished = 0
        storage.machine_data[new_unit_number].last_checked_threshold = 0
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

--- Creates alerts and print statements for quality changes
--- @param quality_changes table Changes grouped by entity type
--- @param quality_direction string "increase" or "decrease"
local function handle_quality_change_notifications(quality_changes, quality_direction)
  -- Count total changes by entity type
  local assembling_count = #quality_changes["assembling-machine"]
  local furnace_count = #quality_changes["furnace"]
  local total_changes = assembling_count + furnace_count

  if total_changes == 0 then
    return -- No changes to report
  end

  -- Create individual alerts for each player (if enabled) and fallback print statements
  for _, player in pairs(game.players) do
    if player.valid then
      local alerts_enabled = settings.get_player_settings(player)["quality-change-alerts-enabled"].value

      if alerts_enabled then
        -- Create individual alerts for each changed machine
        for entity_type, changes in pairs(quality_changes) do
          for _, change in ipairs(changes) do
            if change.entity and change.entity.valid then
              -- Determine alert message key
              local message_key = "alert-message.quality-" ..
                (quality_direction == "increase" and "upgrade" or "downgrade") ..
                "-" .. entity_type

              -- Use the machine itself as the icon (SignalID format)
              local icon = {type = "item", name = change.entity.name, quality = change.new_quality}

              -- Create the alert
              player.add_custom_alert(change.entity, icon, {message_key}, true)
            end
          end
        end

        if assembling_count > 0 then
          local direction_text = quality_direction == "increase" and "upgraded" or "downgraded"
          player.print(string.format("[Quality Control] %d assembly machine%s quality %s",
            assembling_count, assembling_count == 1 and "" or "s", direction_text))
        end

        if furnace_count > 0 then
          local direction_text = quality_direction == "increase" and "upgraded" or "downgraded"
          player.print(string.format("[Quality Control] %d furnace%s quality %s",
            furnace_count, furnace_count == 1 and "" or "s", direction_text))
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
  local percentage_chance = settings.startup["percentage-chance-of-change"].value
  local check_interval_seconds = settings.global["upgrade-check-frequency-seconds"].value
  local check_interval_ticks = math.max(60, math.floor(check_interval_seconds * 60))

  -- Track quality changes by entity type for summary reporting
  local quality_changes = {
    ["assembling-machine"] = {},
    ["furnace"] = {}
  }

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
          if not storage.machine_data[unit_number] then
            storage.machine_data[unit_number] = {}
          end
          local machine_data = storage.machine_data[unit_number]

          local current_recipe = machine.get_recipe()
          if current_recipe then
            local hours_for_this_level = manufacturing_hours_for_change * math.pow(1 + quality_level_modifier, machine.quality.level)
            local recipe_energy = current_recipe.prototype.energy
            local current_work_energy = machine.products_finished * recipe_energy
            local current_manufacturing_hours = current_work_energy / 3600
            local current_threshold_interval = math.floor(current_manufacturing_hours / hours_for_this_level)
            local current_threshold_hours = current_threshold_interval * hours_for_this_level

            if not machine_data.last_checked_threshold then
              machine_data.last_checked_threshold = current_threshold_hours
            end

            if current_threshold_hours > machine_data.last_checked_threshold then
              local change_result = attempt_quality_change(machine, next_quality, percentage_chance)
              if change_result then
                -- Track the change for alerts/reporting
                table.insert(quality_changes[change_result.entity_type], change_result)
              else
                machine_data.last_checked_threshold = current_threshold_hours
              end
            end
          end
        end
      end
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

