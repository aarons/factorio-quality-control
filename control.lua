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
local debug = true -- Set to true to enable debug logging
local previous_qualities = {} -- lookup table for previous qualities in the chain (to make downgrades easier)
local tracked_entities -- lookup table for all the entities we might change the quality of

--- Helper function for debug logging
local function debug(message)
  if debug then
    log("debug: " .. message)
  end
end

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
  debug("get_previous_quality called")
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
  debug("ensure_tracked_entity_table called with force_reset=" .. tostring(force_reset))
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
  debug("get_entity_info called for entity type: " .. (entity.type or "unknown"))

  local id = entity.unit_number
  local entity_type = entity.type
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = quality_change_direction == "increase" and entity.quality.next ~= nil
  local can_decrease = quality_change_direction == "decrease" and previous_quality ~= nil

  -- ensure the entity type table exists
  if not tracked_entities[entity_type] then
    tracked_entities[entity_type] = {}
    tracked_entities[entity_type]._keys = {} -- Array for O(1) random access
    tracked_entities[entity_type]._key_positions = {} -- Reverse mapping: key -> position in _keys array
  end

  -- if the unit doesn't exist, then initialize it
  if not tracked_entities[entity_type][id] then
    tracked_entities[entity_type][id] = {
      entity = entity,
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
  else
    -- Update the entity reference in case it changed due to quality upgrade
    tracked_entities[entity_type][id].entity = entity
  end

  -- calculate this fresh every time we lookup entity via get_entity_info
  tracked_entities[entity_type][id].previous_quality = previous_quality
  tracked_entities[entity_type][id].can_change_quality = can_increase or can_decrease


  return tracked_entities[entity_type][id]
end

--- Scans all surfaces and populates entity data
local function scan_and_populate_entities()
  debug("scan_and_populate_entities called")
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace", "mining-drill", "lab", "inserter", "pump", "radar", "roboport"},
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      get_entity_info(entity) -- This will initialize the entity in tracked_entities
    end
  end
end

--- Cleans up data for a specific entity that was destroyed
local function remove_entity_info(entity_type, id)
  -- debug("remove_entity_info called for entity_type: " .. entity_type .. ", id: " .. tostring(id))
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
  debug("on_entity_created called")
  local entity = event.entity or event.created_entity

  -- Check if it's a type we track and is player owned
  if tracked_types[entity.type] and entity.force == game.forces.player then
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
  local entity_info = tracked_entities[entity.type] and tracked_entities[entity.type][entity.unit_number]

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
    -- don't need to get_entity_info with the new one as the on_creation trigger should handle it
    -- may need to hook the script on create, but I don't think so
    remove_entity_info(old_entity_type, old_unit_number)

    -- Show entity-specific alert if successful
    show_entity_quality_alert(replacement_entity, quality_change_direction)

    -- Return change information including whether it was upgraded or downgraded
    return {
      entity = replacement_entity,
      change_type = quality_change_direction,
      entity_type = old_entity_type
    }
  end

  return nil -- we attempted to replace but it failed
end



--- Shows quality change notifications based on user settings
local function show_quality_notifications(changes_by_type)
  debug("show_quality_notifications called")
  -- Show aggregate console alerts if enabled
  local player = game.players[1]
  if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
    local messages = {}

    for key, count in pairs(changes_by_type) do
      local entity_type, change_type = key:match("([^_]+)_(.+)")
      local entity_name = entity_type:gsub("-", " ")
      local action = change_type == "increase" and "upgraded" or "downgraded"
      local plural = count > 1 and "s" or ""

      table.insert(messages, count .. " " .. entity_name .. plural .. " " .. action)
    end

    if #messages > 0 then
      player.print(table.concat(messages, "\n"))
    end
  end
end

--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  debug("reinitialize_quality_control_storage called")

  ensure_tracked_entity_table(true)
  scan_and_populate_entities()

  -- Only print message if called from console command (with player context)
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control storage reinitialized. All machines have been rescanned.")
    end
  end
end


--- Iterates through all tracked entities and checks if their quality should be changed.
local function check_and_change_quality()
  debug("check_and_change_quality called")

  local total_secondary_attempts = 0
  local total_invalid_entites = 0

  -- Track changes for notifications
  local changes_by_type = {} -- For aggregate alerts

  -- Primary entities loop
  for _, entity_type in pairs(primary_types) do
    if tracked_entities[entity_type] then

      for unit_number, entity_info in pairs(tracked_entities[entity_type]) do
        if unit_number == "_keys" or unit_number == "_key_positions" then goto continue end
        local entity = entity_info.entity
        if not entity or not entity.valid then
          debug("entity invalid or unit number changed: valid=" .. tostring(entity and entity.valid) .. ", unit_numbers: " .. tostring(entity and entity.unit_number) .. " vs " .. tostring(unit_number))
          remove_entity_info(entity_type, unit_number)
          total_invalid_entites = total_invalid_entites + 1
          goto continue
        end

        if entity_info.can_change_quality then
          local current_recipe = entity.get_recipe()
          if current_recipe then
            local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ entity.quality.level
            local recipe_time = current_recipe.prototype.energy
            local current_hours = (entity.products_finished * recipe_time) / 3600
            local previous_hours = entity_info.manufacturing_hours or 0

            local available_hours = current_hours - previous_hours
            local thresholds_passed = math.floor(available_hours / hours_needed)

            if thresholds_passed > 0 then
              total_secondary_attempts = total_secondary_attempts + thresholds_passed
              local successful_change = false

              for i = 1, thresholds_passed do
                local change_result = attempt_quality_change(entity)
                if change_result then
                  successful_change = true

                  -- Track the change for notifications
                  local key = change_result.entity_type .. "_" .. change_result.change_type
                  changes_by_type[key] = (changes_by_type[key] or 0) + 1

                  break -- Stop trying after a success
                end
              end

              -- If no change was made, update the manufacturing hours floor
              if not successful_change then
                entity_info.manufacturing_hours = previous_hours + (thresholds_passed * hours_needed)
              end
            end
          end
        end
        ::continue::
      end
    end
  end

  -- Secondary entities loop
  if total_secondary_attempts > 0 then
    for i = 1, total_secondary_attempts do
      local random_type = secondary_types[math.random(#secondary_types)]
      if tracked_entities[random_type] and tracked_entities[random_type]._keys and #tracked_entities[random_type]._keys > 0 then
        local keys = tracked_entities[random_type]._keys
        local random_id = keys[math.random(#keys)]
        local entity_info = tracked_entities[random_type][random_id]

        if entity_info then
          local random_entity = entity_info.entity
          if random_entity and random_entity.valid and random_entity.unit_number == random_id then
            -- Update the entity_info to ensure fresh calculations
            entity_info = get_entity_info(random_entity)
            if entity_info.can_change_quality then
              local random_result = attempt_quality_change(random_entity)
              if random_result then
                -- Track the change for notifications
                local key = random_result.entity_type .. "_" .. random_result.change_type
                changes_by_type[key] = (changes_by_type[key] or 0) + 1
              end
            end
          else
            -- Clean up invalid entity
            remove_entity_info(random_type, random_id)
          end
        end
      end
    end
  end

  -- Show notifications if any changes occurred
  if next(changes_by_type) then
    show_quality_notifications(changes_by_type)
  end

  -- See if we should re-initilize storage.
  -- If error rate is high then something has gone wonky with tracked_entities; likely a mod change or migration from older version
  if (total_secondary_attempts == 0 and total_invalid_entites > 3) or
     (storage.tracked_entities and #storage.tracked_entities < #storage.tracked_types * 3) then
    debug("Total invalid entities was high: " .. total_invalid_entites)
    debug("Maybe there was a migration from an old version, re-initialize storage")
    reinitialize_quality_control_storage()
  end
end

--- Displays quality control metrics for the selected entity
local function show_entity_quality_info(player)
  debug("show_entity_quality_info called")
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
  debug("on_quality_control_inspect called")
  local player = game.get_player(event.player_index)
  if player then
    show_entity_quality_info(player)
  end
end

--- Registers the nth_tick event based on the current setting
local function register_nth_tick_event()
  debug("register_nth_tick_event called")
  -- Get the frequency setting in seconds and convert to ticks (60 ticks = 1 second)
  local check_interval_seconds = settings.global["upgrade-check-frequency-seconds"].value
  local check_interval_ticks = math.max(60, math.floor(check_interval_seconds * 60))

  -- Register the new nth_tick event (this will replace any existing handler for this specific tick interval)
  script.on_nth_tick(check_interval_ticks, check_and_change_quality)
end

--- Event handler for entity destruction - cleans up entity data
local function on_entity_destroyed(event)
  debug("on_entity_destroyed called")
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

-- Initialize quality lookup on a new game
script.on_init(function()
  debug("script.on_init called")
  ensure_tracked_entity_table()
  scan_and_populate_entities()
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
  ensure_tracked_entity_table() -- this should be present but just in case
end)
