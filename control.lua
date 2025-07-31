--[[
control.lua

This script manages the quality of crafting machines.
It periodically scans all player-owned crafting machines and applies quality changes based on their hours spent making items.
Each machine is tracked individually and only checked once per manufacturing_hours period.

IMPORTANT NOTE: Manufacturing hours do not accumulate at a constant rate. Users can place speed beacons,
productivity modules, and other modifiers that change the effective manufacturing rate. Therefore, we track
the last manufacturing_hours threshold that was checked for each machine.
]]

--- Cache for quality chains to avoid repeated lookups
local quality_chains = {}

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
    ["furnace"] = true,
    ["lab"] = true,
    ["mining-drill"] = true
  }

  if machine_types[entity.type] and entity.unit_number then
    storage.machine_data[entity.unit_number] = nil
  end
end

--- Builds a cache of all quality prototypes and their next/previous relationships
local function build_quality_chains()
  quality_chains = {}
  for name, quality_prototype in pairs(prototypes.quality) do
    -- Skip quality-unknown as it's not part of the normal quality chain
    if name ~= "quality-unknown" then
      quality_chains[name] = {
        prototype = quality_prototype,
        next = quality_prototype.next and quality_prototype.next.name or nil,
        previous = nil
      }
    end
  end

  -- Fill in the previous relationships
  for name, chain_data in pairs(quality_chains) do
    if chain_data.next then
      quality_chains[chain_data.next].previous = name
    end
  end

end

--- Gets the next quality in the specified direction
--- @param current_quality LuaQualityPrototype
--- @param direction string "increase" or "decrease"
--- @return LuaQualityPrototype|nil
local function get_next_quality(current_quality, direction)
  if not current_quality then return nil end

  -- Rebuild cache if it's empty (first run or after mod changes)
  if not next(quality_chains) then
    build_quality_chains()
  end

  local current_name = current_quality.name
  local chain_data = quality_chains[current_name]

  if not chain_data then return nil end

  local next_quality_name
  if direction == "increase" then
    next_quality_name = chain_data.next
  else -- direction == "decrease"
    next_quality_name = chain_data.previous
  end

  if next_quality_name and quality_chains[next_quality_name] then
    return quality_chains[next_quality_name].prototype
  end

  return nil
end

--- Attempts to change the quality of a machine based on a random roll.
--- @param machine LuaEntity The machine to potentially change.
--- @param next_quality LuaQualityPrototype The quality to change to.
--- @param percentage_chance number The chance of the quality change occurring.
--- @return boolean true if the machine was successfully replaced, false otherwise.
local function attempt_quality_change(machine, next_quality, percentage_chance)
  local random_roll = math.random()
  local chance_threshold = percentage_chance / 100

  if random_roll >= chance_threshold then
    return false -- Random roll failed, no change
  end

  -- Store the unit number before creating replacement (machine becomes invalid after fast_replace)
  local old_unit_number = machine.unit_number

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
    elseif replacement_entity.type == "lab" or replacement_entity.type == "mining-drill" then
        storage.machine_data[new_unit_number].active_cycles = 0
    end

    -- Remove old machine data using stored unit number
    storage.machine_data[old_unit_number] = nil
    return true
  end

  return false -- Replacement failed
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

  for _, surface in pairs(game.surfaces) do
    local machines = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace", "lab", "mining-drill"},
      force = player_force
    }

    for _, machine in ipairs(machines) do
      if machine and machine.valid then
        local unit_number = machine.unit_number
        local machine_type = machine.type
        local next_quality = get_next_quality(machine.quality, quality_direction)

        if next_quality then
          if not storage.machine_data[unit_number] then
            storage.machine_data[unit_number] = {}
          end
          local machine_data = storage.machine_data[unit_number]

          if machine_type == "assembling-machine" or machine_type == "furnace" then
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
                if not attempt_quality_change(machine, next_quality, percentage_chance) then
                  machine_data.last_checked_threshold = current_threshold_hours
                end
              end
            end
          elseif machine_type == "lab" or machine_type == "mining-drill" then
            local is_active = false

            if machine_type == "lab" then
              -- Lab is active if it's researching (has research target and input items)
              local force = machine.force
              if force and force.valid and force.current_research then
                -- Check if lab has input items and energy
                local inventory = machine.get_inventory(defines.inventory.lab_input)
                is_active = inventory and not inventory.is_empty() and machine.energy > 0
              end
            elseif machine_type == "mining-drill" then
              -- Mining drill is active if it has resources to mine and has energy
              local mining_target = machine.mining_target
              is_active = mining_target and mining_target.valid and machine.energy > 0 and machine.status == defines.entity_status.working
            end

            if is_active then
              machine_data.active_cycles = (machine_data.active_cycles or 0) + 1

              -- Simple threshold: labs and miners need to be active for a certain number of checks
              -- This is equivalent to the manufacturing hours concept but for non-crafting machines
              local hours_for_this_level = manufacturing_hours_for_change * math.pow(1 + quality_level_modifier, machine.quality.level)
              -- Convert hours to number of active checks needed (assuming each check represents some activity)
              -- Since check_interval_seconds represents how often we check, we can estimate cycles needed
              local cycles_per_hour = 3600 / check_interval_seconds  -- Rough estimate of checks per hour of activity
              local required_active_cycles = hours_for_this_level * cycles_per_hour

              if machine_data.active_cycles >= required_active_cycles then
                if attempt_quality_change(machine, next_quality, percentage_chance) then
                  -- Reset is handled in attempt_quality_change
                else
                  -- If change failed, reset cycles so we don't check again immediately
                  machine_data.active_cycles = 0
                end
              end
            end
          end
        end
      end
    end
  end
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

-- Initialize quality chains on first load
script.on_init(function()
  build_quality_chains()
  init_machine_data()
  register_nth_tick_event()
end)

-- Rebuild quality chains when configuration changes (mods added/removed)
script.on_configuration_changed(function(event)
  build_quality_chains()
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

