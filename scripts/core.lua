--[[
core.lua

Contains the main processing logic for quality control:
- Entity tracking and management
- Quality change attempts
- Batch processing
- Manufacturing hours calculation
]]

local notifications = require("scripts.notifications")
local core = {}

-- Module state
local debug_enabled = true

local function debug(message)
  if debug_enabled then
    log("debug: " .. message)
  end
end
local tracked_entities -- lookup table for all the entities we might change the quality of
local previous_qualities = {} -- lookup table for previous qualities in the chain
local quality_limit = nil -- the quality limit (max for increase, min for decrease)


-- Settings (will be set by control.lua)
local settings_data = {}
local is_tracked_type = {}


function core.initialize(parsed_settings, tracked_type_lookup, quality_lookup, quality_limit_setting)
  settings_data = parsed_settings
  is_tracked_type = tracked_type_lookup
  previous_qualities = quality_lookup
  quality_limit = quality_limit_setting
  tracked_entities = storage.quality_control_entities

end

local function get_previous_quality(quality_prototype)
  return previous_qualities[quality_prototype.name]
end

function core.get_entity_info(entity)
  local id = entity.unit_number
  local entity_type = entity.type
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = settings_data.quality_change_direction == "increase" and entity.quality.next ~= nil
  local can_decrease = settings_data.quality_change_direction == "decrease" and previous_quality ~= nil
  local can_change_quality = can_increase or can_decrease
  local is_primary = (entity_type == "assembling-machine" or entity_type == "furnace" or entity_type == "rocket-silo")

  -- Return error codes for entities that can't change quality
  if not can_change_quality then
    if settings_data.quality_change_direction == "increase" then
      return "at max quality"
    elseif settings_data.quality_change_direction == "decrease" then
      return "at min quality"
    else
      return "unable to change quality"
    end
  end

  if not tracked_entities[id] then
    tracked_entities[id] = {
      entity = entity,
      entity_type = entity_type,
      is_primary = is_primary,
      chance_to_change = settings_data.base_percentage_chance,
      attempts_to_change = 0,
      can_change_quality = can_change_quality
    }

    -- Update entity counts
    if is_primary then
      storage.primary_entity_count = storage.primary_entity_count + 1
    else
      storage.secondary_entity_count = storage.secondary_entity_count + 1
    end

    -- Add to ordered list for batch processing with O(1) lookup
    table.insert(storage.entity_list, id)
    storage.entity_list_index[id] = #storage.entity_list

    if is_primary then
      -- Initialize manufacturing hours based on current products_finished
      -- This ensures we don't double-count hours for already-producing entities
      local current_recipe = entity.get_recipe()
      if current_recipe then
        local recipe_time = current_recipe.prototype.energy
        local current_hours = (entity.products_finished * recipe_time) / 3600
        tracked_entities[id].manufacturing_hours = current_hours

        -- Calculate how many quality attempts would have occurred in the past
        -- and adjust the chance percentage accordingly
        if current_hours > 0 then
          local hours_needed = settings_data.manufacturing_hours_for_change * (1 + settings_data.quality_increase_cost) ^ entity.quality.level
          local past_attempts = math.floor(current_hours / hours_needed)

          -- Simulate the chance accumulation from missed attempts
          if past_attempts > 0 and settings_data.accumulation_percentage > 0 then
            local chance_increase = past_attempts * (settings_data.base_percentage_chance * settings_data.accumulation_percentage / 100)
            tracked_entities[id].chance_to_change = tracked_entities[id].chance_to_change + chance_increase
            tracked_entities[id].attempts_to_change = past_attempts
          end

          -- Not adding credits for past attempts; it's too hard to balance with secondary entities.
          -- Basically everytime you do a quality-control-init it refills the credit pool; for easy upgrade farming
        end
      else
        tracked_entities[id].manufacturing_hours = 0
      end
    end
  end
  return tracked_entities[id]
end

function core.scan_and_populate_entities(all_tracked_types)
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = all_tracked_types,
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      core.get_entity_info(entity)
    end
  end

  debug("Entity scan complete - Primary: " .. storage.primary_entity_count .. ", Secondary: " .. storage.secondary_entity_count)
end

function core.remove_entity_info(id)
  if tracked_entities and tracked_entities[id] then
    local entity_info = tracked_entities[id]

    -- Update counts before removal
    if entity_info.can_change_quality then
      if entity_info.is_primary then
        storage.primary_entity_count = math.max(0, storage.primary_entity_count - 1)
      else
        storage.secondary_entity_count = math.max(0, storage.secondary_entity_count - 1)
      end
    end

    tracked_entities[id] = nil

    -- O(1) removal using swap-with-last approach
    local index = storage.entity_list_index[id]
    if index then
      local last_index = #storage.entity_list
      local last_unit_number = storage.entity_list[last_index]

      -- Swap with last element
      storage.entity_list[index] = last_unit_number
      storage.entity_list_index[last_unit_number] = index

      -- Remove the last element
      storage.entity_list[last_index] = nil
      storage.entity_list_index[id] = nil

      -- Adjust batch_index if we swapped an element we haven't processed yet
      if index < storage.batch_index then
        storage.batch_index = storage.batch_index - 1
      end
    end
  end
end

local function update_module_quality(replacement_entity, target_quality, settings_data)
  local module_setting = settings.startup["change-modules-with-entity"].value

  -- Early return if modules should not be changed
  if module_setting == "disabled" then
    return
  end

  local module_inventory = replacement_entity.get_module_inventory()
  if not module_inventory then
    return
  end

  for i = 1, #module_inventory do
    local stack = module_inventory[i]

    -- Only process valid module stacks
    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local new_module_quality = nil

      -- Determine new quality based on module setting
      if module_setting == "extra-enabled" then
        -- Set module quality to match target quality exactly
        if current_module_quality.level ~= target_quality.level then
          new_module_quality = target_quality
        end
      elseif module_setting == "enabled" then
        -- Step module quality one level at a time
        local is_increasing = settings_data.quality_change_direction == "increase"
        local can_increase = is_increasing and current_module_quality.level < target_quality.level and current_module_quality.next
        local can_decrease = not is_increasing and current_module_quality.level > target_quality.level

        if can_increase then
          new_module_quality = current_module_quality.next
        elseif can_decrease then
          new_module_quality = get_previous_quality(current_module_quality)
        end
      end

      -- Apply the quality change if needed
      if new_module_quality then
        stack.clear()
        module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
      end
    end
  end
end

local function attempt_quality_change(entity)
  debug("attempt_quality_change called for entity type: " .. entity.type .. ", id: " .. tostring(entity.unit_number))

  local random_roll = math.random()
  local entity_info = tracked_entities[entity.unit_number]

  entity_info.attempts_to_change = entity_info.attempts_to_change + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    -- roll failed; improve it's chance for next time and return
    if settings_data.accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (settings_data.base_percentage_chance * settings_data.accumulation_percentage / 100)
    end
    return nil
  end

  -- Entity becomes invalid after fast_replace
  local old_unit_number = entity.unit_number

  local target_quality
  if settings_data.quality_change_direction == "increase" then
    target_quality = entity.quality.next
  else -- decrease
    target_quality = get_previous_quality(entity.quality)
  end

  -- Raise script_raised_destroy event for the old entity before replacement
  script.raise_script_destroy{entity = entity}

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
    core.remove_entity_info(old_unit_number)
    update_module_quality(replacement_entity, target_quality, settings_data)
    notifications.show_entity_quality_alert(replacement_entity, settings_data.quality_change_direction)
    return replacement_entity
  end

  return nil
end


local function process_quality_attempts(entity, attempts_count, quality_changes)
  local successful_changes = 0
  local current_entity = entity

  for _ = 1, attempts_count do
    local change_result = attempt_quality_change(current_entity)
    if change_result then
      successful_changes = successful_changes + 1
      current_entity = change_result
      quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1

      -- If entity reached quality limit, stop attempting further changes
      if current_entity.quality == quality_limit then
        debug("entity reached quality limit, stopping attempts: " .. tostring(current_entity.unit_number))
        break
      end
    end
  end

  return successful_changes
end


function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  while entities_processed < batch_size do
    -- Check for end of list (cycle complete)
    if storage.batch_index > #storage.entity_list then
      storage.batch_index = 1  -- Reset for next cycle
      -- Debug: total entities at end of cycle
      debug("=== CYCLE COMPLETE ===")
      debug("Total entities - Primary: " .. storage.primary_entity_count .. ", Secondary: " .. storage.secondary_entity_count .. ", Total: " .. (storage.primary_entity_count + storage.secondary_entity_count))
      debug("Accumulated upgrade attempts: " .. string.format("%.2f", storage.accumulated_upgrade_attempts))
      debug("=====================")
      break
    end

    -- Get the next entity to process
    local unit_number = storage.entity_list[storage.batch_index]
    storage.batch_index = storage.batch_index + 1

    -- Validate entity before processing
    local entity_info = tracked_entities[unit_number]
    if not entity_info or not entity_info.entity or not entity_info.entity.valid or not entity_info.can_change_quality then
      core.remove_entity_info(unit_number)
      goto continue
    end

    local entity = entity_info.entity

    if entity_info.is_primary then
        local current_recipe = entity.get_recipe()
        if current_recipe then
          local hours_needed = settings_data.manufacturing_hours_for_change * (1 + settings_data.quality_increase_cost) ^ entity.quality.level
          local recipe_time = current_recipe.prototype.energy
          local current_hours = (entity.products_finished * recipe_time) / 3600
          local previous_hours = entity_info.manufacturing_hours or 0
          local available_hours = current_hours - previous_hours
          local thresholds_passed = math.floor(available_hours / hours_needed)

          if thresholds_passed > 0 then
            -- Generate credits for secondary entities
            if storage.secondary_entity_count > 0 then
              local credit_ratio = storage.secondary_entity_count / math.max(storage.primary_entity_count, 1)
              local credits_added = thresholds_passed * credit_ratio
              storage.accumulated_upgrade_attempts = storage.accumulated_upgrade_attempts + credits_added
              debug("Primary entity " .. tostring(entity.unit_number) .. " generated " .. string.format("%.2f", credits_added) .. " credits (ratio: " .. string.format("%.2f", credit_ratio) .. ")")
              debug("Accumulated upgrade attempts now: " .. string.format("%.2f", storage.accumulated_upgrade_attempts))
            end

            -- Process primary entity attempts
            local successful_changes = process_quality_attempts(entity, thresholds_passed, quality_changes)
            if successful_changes == 0 then
              entity_info.manufacturing_hours = current_hours
            end
          end
        end
      else -- entity is a secondary entity type without hours
        if storage.accumulated_upgrade_attempts > 0 and storage.secondary_entity_count > 0 then
          -- Calculate attempts for this entity
          local attempts_per_entity = storage.accumulated_upgrade_attempts / storage.secondary_entity_count
          local guaranteed_attempts = math.floor(attempts_per_entity)
          local fractional_chance = attempts_per_entity - guaranteed_attempts

          -- Resolve fractional to integer
          local total_attempts = guaranteed_attempts
          if fractional_chance > 0 and math.random() < fractional_chance then
            total_attempts = total_attempts + 1
          end

          -- Consume exact credits
          if total_attempts > 0 then
            local credits_before = storage.accumulated_upgrade_attempts
            storage.accumulated_upgrade_attempts = math.max(0, storage.accumulated_upgrade_attempts - total_attempts)
            debug("Secondary entity " .. tostring(entity.unit_number) .. " consumed " .. total_attempts .. " credits (from " .. string.format("%.2f", credits_before) .. " to " .. string.format("%.2f", storage.accumulated_upgrade_attempts) .. ")")
            process_quality_attempts(entity, total_attempts, quality_changes)
          end
        end
      end

    entities_processed = entities_processed + 1
    ::continue::
  end

  -- Debug: batch summary
  if entities_processed > 0 then
    debug("Batch processed " .. entities_processed .. " entities, " .. (next(quality_changes) and "had quality changes" or "no quality changes"))
  end

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes, settings_data.quality_change_direction)
  end
end

function core.on_entity_created(event)
  local entity = event.entity

  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_entity_cloned(event)
  local entity = event.destination

  if not entity then
    return
  end

  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_entity_destroyed(event)
  local entity = event.entity
  if entity and entity.valid and is_tracked_type[entity.type] then
    core.remove_entity_info(entity.unit_number)
  end
end

function core.on_quality_control_inspect(event)
  local player = game.get_player(event.player_index)
  if player then
    notifications.show_entity_quality_info(
      player,
      is_tracked_type,
      core.get_entity_info,
      settings_data.manufacturing_hours_for_change,
      settings_data.quality_increase_cost
    )
  end
end

return core