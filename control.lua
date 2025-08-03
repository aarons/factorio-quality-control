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
local qc_entities -- lookup table for all the entities we might change the quality of

--- Setup all values defined in startup settings
local quality_change_direction = settings.startup["quality-change-direction"].value
local manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
local qaulity_increase_cost = settings.startup["qaulity-increase-cost"].value
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

local function ensure_entity_table()
  if not qc_entities then
    if not storage.quality_control_entities then
      storage.quality_control_entities = {}
    end
    qc_entities = storage.quality_control_entities
  end
end

--- Gets or creates entity metrics for a specific entity
local function get_entity_info(entity)
  ensure_entity_table()

  local id = entity.unit_number
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = quality_change_direction == "increase" and entity.quality.next
  local can_decrease = quality_change_direction == "decrease" and previous_quality

  -- if the unit doesn't exist, then initialize it
  if not qc_entities[id] then
    qc_entities[id] = {
      id = id,
      manufacturing_hours = 0,
      chance_to_change = base_percentage_chance
    }
  end

  -- calculate this fresh every time we lookup entity
  qc_entities[id].previous_quality = previous_quality
  qc_entities[id].can_change_quality = can_increase or can_decrease

  return qc_entities[id]
end

--- Cleans up data for a specific entity that was destroyed
local function remove_entity_info(entity)
  ensure_entity_table()
  qc_entities[entity.unit_number] = nil
end

--- Attempts to change the quality of a machine based on chance
local function attempt_quality_change(entity)
  local random_roll = math.random()

  local entity_info = qc_entities[entity.unit_number]

  if random_roll >= (entity_info.chance_to_change / 100) then
    -- roll failed; improve it's chance for next time and return
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * accumulation_percentage / 100)
    end
    return
  end

  -- Store info before creating replacement (entity becomes invalid after fast_replace)
  local old_unit_number = entity.unit_number

  local replacement_entity = entity.surface.create_entity {
    name = entity.name,
    position = entity.position,
    force = entity.force,
    direction = entity.direction,
    quality = entity.quality.next,
    fast_replace = true,
    spill = false
  }

  if replacement_entity and replacement_entity.valid then
    get_entity_info(replacement_entity.unit_number) -- initialize it's entry
    remove_entity_info(old_unit_number)

    -- Return change information
    return replacement_entity
  end

  return nil -- we attempted to replace but it failed for some reason
end

-- TODO: we should remove this, it's too complex and not needed
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

-- this can be simplified I suspect
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
              local entity_info = get_entity_info(unit_number)

              -- Initialize chance if not present
              if not entity_info.current_chance then
                entity_info.current_chance = base_percentage_chance
              end

              local change_result = attempt_quality_change(entity, next_quality, entity_info.current_chance)
              if change_result then
                -- Reset chance after successful change
                entity_info.current_chance = base_percentage_chance
                -- Initialize the entity type array if it doesn't exist
                if not quality_changes[entity_type] then
                  quality_changes[entity_type] = {}
                end
                table.insert(quality_changes[entity_type], change_result)
              else
                -- Increment chance after failed attempt
                entity_info.current_chance = entity_info.current_chance + (base_percentage_chance * accumulation_percentage / 100)
              end
            end
          end
        end
      end
    end
  end
end

--- Creates alerts and print statements for quality changes
local function change_notifications(quality_changes, quality_change_direction)
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

  -- we are only modifying the current players forces, so no need to look through all the players
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
                (quality_change_direction == "increase" and "upgrade" or "downgrade") ..
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
        local direction_text = quality_change_direction == "increase" and "upgraded" or "downgraded"

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

  -- Track candidates for ratio calculation
  local entities_checked = 0
  local changes_attempted = 0
  local changes_succeeded = 0

  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = {"assembling-machine", "furnace"},
      force = player_force
    }

    for _, entity in ipairs(entities) do
      -- if it's at max quality, then do nothing
      local entity_info = get_entity_info(entity)

      if entity_info.can_change_quality then
        entities_checked = entities_checked + 1
        local current_recipe = entity.get_recipe()
        if current_recipe then
          local hours_needed = manufacturing_hours_for_change * (1 + qaulity_increase_cost) ^ entity.quality.level
          local recipe_time = current_recipe.prototype.energy
          local current_hours = (entity.products_finished * recipe_time) / 3600 -- total hours machine has been working, ex. 37.5
          local previous_hours = entity_info.manufacturing_hours

          -- Check if we've crossed a new threshold (time for another attempt)
          if (previous_hours - current_hours) > hours_needed then
            changes_attempted = changes_attempted + 1
            local change_result = attempt_quality_change(entity)
            if change_result then
              changes_succeeded = changes_succeeded + 1
            else
              -- update that we attempted a change on this threshold
              -- once another 'hours_needed' is accumulated we will try again
              entity_info.manufacturing_hours = current_hours
            end
          end
        end
      end
    end
  end

  -- -- Calculate candidate ratio for additional entity types
  -- local candidate_ratio = 0
  -- if entities_checked > 0 then
  --   candidate_ratio = changes_attempted / entities_checked
  -- end

  -- -- Apply ratio-based quality changes to additional entity types
  -- if candidate_ratio > 0 then
  --   local next_quality = nil
  --   -- Get the next quality for additional entities (same direction as entitys)
  --   local normal_quality = prototypes.quality["quality-normal"]
  --   if normal_quality then
  --     next_quality = get_next_quality(normal_quality, quality_change_direction)
  --   end

  --   if next_quality then
  --     apply_ratio_based_quality_changes(candidate_ratio, quality_changes, next_quality, base_percentage_chance, accumulation_percentage, player_force)
  --   end
  -- end

  -- Handle alerts and notifications for quality changes
  -- if changes_succeeded > 0 then
    -- change_notifications(changes_succeeded)
  -- end
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
    remove_entity_info(entity)
  end
end

-- Register event handlers for entity destruction/deconstruction
script.on_event(defines.events.on_entity_died, on_entity_destroyed)
script.on_event(defines.events.on_player_mined_entity, on_entity_destroyed)
script.on_event(defines.events.on_robot_mined_entity, on_entity_destroyed)

-- Initialize quality lookup on first load
script.on_init(function()
  register_nth_tick_event()
end)

-- Rebuild quality lookup when configuration changes (mods added/removed)
script.on_configuration_changed(function(event)
  register_nth_tick_event()
end)

-- Handle runtime setting changes
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "upgrade-check-frequency-seconds" then
    register_nth_tick_event()
  end
end)

