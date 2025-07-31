--[[
control.lua

This script manages the quality of crafting machines.
It periodically scans all player-owned crafting machines and applies quality changes based on their hours spent making items.
Each machine is tracked individually and only checked once per manufacturing_hours period.

IMPORTANT NOTE: Manufacturing hours do not accumulate at a constant rate. Users can place speed beacons,
productivity modules, and other modifiers that change the effective manufacturing rate. Therefore, we cannot
predict future tick times for when to check machines. Instead, we use a threshold-based approach where we
track the last manufacturing_hours threshold that was checked for each machine.
]]

--- Cache for quality chains to avoid repeated lookups
local quality_chains = {}

--- Initializes the storage for machine tracking data
local function init_machine_data()
  if not storage.machine_data then
    storage.machine_data = {}
  end
end

--- Cleans up data for machines that no longer exist
local function cleanup_machine_data()
  if not storage.machine_data then return end

  local valid_units = {}
  local player_force = game.forces.player
  if not player_force then return end

  -- Collect all valid machine unit numbers
  for _, surface in pairs(game.surfaces) do
    local machines = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace"},
      force = player_force
    }

    for _, machine in ipairs(machines) do
      if machine and machine.valid then
        valid_units[machine.unit_number] = true
      end
    end
  end

  -- Remove data for machines that no longer exist
  for unit_number, _ in pairs(storage.machine_data) do
    if not valid_units[unit_number] then
      storage.machine_data[unit_number] = nil
    end
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

  if direction == "increase" then
    return chain_data.next
  else -- direction == "decrease"
    return chain_data.previous
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

  -- Clean up stale machine data periodically (every ~100 checks)
  if not storage.cleanup_counter then storage.cleanup_counter = 0 end
  storage.cleanup_counter = storage.cleanup_counter + 1
  if storage.cleanup_counter >= 100 then
    cleanup_machine_data()
    storage.cleanup_counter = 0
  end

  -- Cache settings once per cycle instead of per machine
  local quality_direction = settings.startup["quality-change-direction"].value
  local manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  local quality_level_modifier = settings.startup["quality-level-modifier"].value
  local percentage_chance = settings.startup["percentage-chance-of-change"].value

  for _, surface in pairs(game.surfaces) do
    -- Search for both assembling machines and furnaces in a single call
    local machines = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace"},
      force = player_force
    }

    for _, machine in ipairs(machines) do
      if machine and machine.valid then
        -- Get recipe information - only process machines with valid recipes
        local current_recipe = machine.get_recipe()

        -- Only process machines that have an active recipe
        if current_recipe then
          local unit_number = machine.unit_number
          local recipe_energy = current_recipe.prototype.energy
          local next_quality = get_next_quality(machine.quality, quality_direction)

          if next_quality then
            local hours_for_this_level = manufacturing_hours_for_change +
              (manufacturing_hours_for_change * quality_level_modifier * (machine.quality.level - 1))

            -- Calculate current manufacturing hours for this machine
            local current_work_energy = machine.products_finished * recipe_energy
            local current_manufacturing_hours = current_work_energy / 3600

            -- Calculate which threshold interval we're currently in
            local current_threshold_interval = math.floor(current_manufacturing_hours / hours_for_this_level)
            local current_threshold_hours = current_threshold_interval * hours_for_this_level

            -- Initialize machine data if this is the first time we see this machine
            if not storage.machine_data[unit_number] then
              storage.machine_data[unit_number] = {
                last_checked_threshold = current_threshold_hours
              }
            end

            local machine_data = storage.machine_data[unit_number]

            -- Check if we've crossed into a new threshold interval since last check
            if current_threshold_hours > machine_data.last_checked_threshold then
              local random_roll = math.random()
              local chance_threshold = percentage_chance / 100

              if random_roll < chance_threshold then
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
                  replacement_entity.products_finished = 0
                  -- Update tracking for the new machine (quality changed, so unit_number changed)
                  storage.machine_data[replacement_entity.unit_number] = {
                    last_checked_threshold = 0  -- Reset for new quality level
                  }
                  -- Remove old machine data
                  storage.machine_data[unit_number] = nil
                end
              else
                -- Update the machine's last checked threshold even if change failed
                machine_data.last_checked_threshold = current_threshold_hours
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
  local frequency_seconds = settings.global["upgrade-check-frequency-seconds"].value
  local frequency_ticks = math.max(60, math.floor(frequency_seconds * 60))

  -- Register the new nth_tick event
  script.on_nth_tick(frequency_ticks, check_and_change_quality)
end

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

  -- Clear machine data when settings might have changed
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

-- Debug command to inspect a specific machine
commands.add_command("inspect_machine", "Inspect machine under cursor", function()
  local player = game.players[1]
  if player and player.selected and (player.selected.type == "assembling-machine" or player.selected.type == "furnace") then
    local machine = player.selected
    game.print("=== Machine Inspection ===")
    game.print("Machine: " .. machine.name .. " (" .. machine.type .. ")")
    game.print("Quality: " .. machine.quality.name .. " (level " .. machine.quality.level .. ")")
    game.print("Unit number: " .. machine.unit_number)
    game.print("Products finished: " .. machine.products_finished)

    -- Check for recipe
    local current_recipe = machine.get_recipe()
    if current_recipe then
      game.print("Recipe: " .. current_recipe.name .. " (energy: " .. current_recipe.prototype.energy .. ")")
      game.print("Crafting progress: " .. (machine.crafting_progress or 0))
      game.print("Crafting speed: " .. machine.crafting_speed)
    end

    -- Show machine tracking data
    init_machine_data()
    local unit_number = machine.unit_number
    local machine_data = storage.machine_data[unit_number]

    game.print("=== Tracking Data ===")
    if machine_data then
      game.print("Last checked threshold: " .. machine_data.last_checked_threshold .. " hours")
    else
      game.print("No tracking data yet - will be initialized on next check")
    end

    -- Calculate work threshold for quality upgrade (only if recipe is present)
    if current_recipe then
      local quality_direction = settings.startup["quality-change-direction"].value
      local manufacturing_hours = settings.startup["manufacturing-hours-for-change"].value
      local quality_modifier = settings.startup["quality-level-modifier"].value
      local hours_for_this_level = manufacturing_hours + (manufacturing_hours * quality_modifier * (machine.quality.level - 1))

      local recipe_energy = current_recipe.prototype.energy
      local current_work_energy = machine.products_finished * recipe_energy
      local current_manufacturing_hours = current_work_energy / 3600
      local current_threshold_interval = math.floor(current_manufacturing_hours / hours_for_this_level)
      local current_threshold_hours = current_threshold_interval * hours_for_this_level
      local next_threshold_hours = (current_threshold_interval + 1) * hours_for_this_level

      game.print("=== Quality Upgrade Calculation ===")
      game.print("Manufacturing hours per check: " .. hours_for_this_level)
      game.print("Current manufacturing hours: " .. string.format("%.2f", current_manufacturing_hours))
      game.print("Current threshold: " .. current_threshold_hours .. " hours")
      game.print("Next threshold: " .. next_threshold_hours .. " hours")
      game.print("Progress to next threshold: " .. string.format("%.1f", ((current_manufacturing_hours - current_threshold_hours) / hours_for_this_level) * 100) .. "%")

      if machine_data then
        if current_threshold_hours > machine_data.last_checked_threshold then
          game.print("Ready for check: YES")
        else
          game.print("Ready for check: NO")
        end
      end
    else
      game.print("Cannot calculate quality upgrade progress - no active recipe")
    end
  else
    game.print("No crafting machine selected")
  end
end)
