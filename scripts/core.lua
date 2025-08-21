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

local tracked_entities = {}
local settings_data = {}
local is_tracked_type = {}
local previous_qualities = {}
local quality_limit = nil

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
  previous_qualities = storage.config.previous_qualities
  quality_limit = storage.config.quality_limit
end

-- Exclude entities that don't work well with fast_replace or should be excluded
local function should_exclude_entity(entity)
  if not entity.prototype.selectable_in_game then
    return true
  end

  if not entity.destructible then
    return true
  end

  -- Check if entity prototype is hidden in factoriopedia
  -- local entity_prototype = prototypes.entity[entity.name]
  -- if entity_prototype and entity_prototype.hidden_in_factoriopedia then
  --   log("[QC] Excluding entity " .. entity.name .. " - hidden in factoriopedia")
  --   return true
  -- end

  -- Entities from these mods don't fast_replace well, so for now exclude them
  local exclude_items_from_mods = {
    "Warp-Drive-Machine",
    "quality-condenser",
    "RealisticReactorsReborn",
    "railloader2-patch",
    "router",
    "fct-ControlTech", -- patch requested, may be able to remove once they are greater than version 2.0.5
    "ammo-loader",
    "miniloader-redux"
  }
  local history = prototypes.get_history(entity.type, entity.name)
  if history then
    for _, excluded_mod in ipairs(exclude_items_from_mods) do
      if history.created:find(excluded_mod, 1, true) ~= nil then
        return true
      end
    end
  end
  return false
end

-- Check for other entities at the location of the excluded entity
-- If any overlap, it's probably a complex modded entity that we shouldn't mess with
local function remove_colocated_entity_info(entity)
  local history = prototypes.get_history(entity.type, entity.name)

  local entities_at_position = entity.surface.find_entities_filtered{
    area = entity.bounding_box,
    force = entity.force
  }

  if #entities_at_position <= 1 then return end

  for _, found_entity in ipairs(entities_at_position) do
    if found_entity.unit_number ~= entity.unit_number then
      local found_history = prototypes.get_history(found_entity.type, found_entity.name)
      if found_history.created == history.created then
        core.remove_entity_info(found_entity.unit_number)
      end
    end
  end
end

function core.get_entity_info(entity)
  if should_exclude_entity(entity) then
    -- remove_colocated_entity_info(entity) -- not sure this is needed, trying without for now
    return "entity excluded from quality control"
  end

  local id = entity.unit_number
  local previous_quality = previous_qualities[entity.quality.name]
  local can_increase = settings_data.quality_change_direction == "increase" and entity.quality.next ~= nil
  local can_decrease = settings_data.quality_change_direction == "decrease" and previous_quality ~= nil
  local can_change_quality = can_increase or can_decrease
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace" or entity.type == "rocket-silo")

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
      is_primary = is_primary,
      chance_to_change = settings_data.base_percentage_chance,
      attempts_to_change = 0,
      can_change_quality = can_change_quality
    }

    if is_primary then
      storage.primary_entity_count = storage.primary_entity_count + 1
    else
      storage.secondary_entity_count = storage.secondary_entity_count + 1
    end

    -- Use ordered list for batch processing: O(1) lookup
    table.insert(storage.entity_list, id)
    storage.entity_list_index[id] = #storage.entity_list

    if is_primary then
      -- Initialize manufacturing hours based on current products_finished
      -- This ensures we don't double-count hours for already-producing entities
      local recipe_time = 0
      if entity.get_recipe() then
        recipe_time = entity.get_recipe().prototype.energy
      elseif entity.type == "furnace" and entity.previous_recipe then
        recipe_time = entity.previous_recipe.name.energy
      end

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
end

function core.remove_entity_info(id)
  if tracked_entities and tracked_entities[id] then
    local entity_info = tracked_entities[id]

    if entity_info.is_primary then
      storage.primary_entity_count = math.max(0, storage.primary_entity_count - 1)
    else
      storage.secondary_entity_count = math.max(0, storage.secondary_entity_count - 1)
    end

    tracked_entities[id] = nil

    -- O(1) removal using swap-with-last approach
    local index = storage.entity_list_index[id]
    if index then
      local entity_list = storage.entity_list
      local batch_index = storage.batch_index

      local last_index = #entity_list
      local last_unit_number = entity_list[last_index]

      entity_list[index] = last_unit_number
      storage.entity_list_index[last_unit_number] = index

      entity_list[last_index] = nil
      storage.entity_list_index[id] = nil

      if index < batch_index then
        storage.batch_index = batch_index - 1
      end
    end
  end
end

local function update_module_quality(replacement_entity, target_quality, settings_data)
  local module_setting = settings.startup["change-modules-with-entity"].value

  if module_setting == "disabled" then
    return
  end

  local module_inventory = replacement_entity.get_module_inventory()
  if not module_inventory then
    return
  end

  for i = 1, #module_inventory do
    local stack = module_inventory[i]

    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local new_module_quality = nil

      if module_setting == "extra-enabled" then
        if current_module_quality.level ~= target_quality.level then
          new_module_quality = target_quality
        end
      elseif module_setting == "enabled" then
        local is_increasing = settings_data.quality_change_direction == "increase"
        local can_increase = is_increasing and current_module_quality.level < target_quality.level and current_module_quality.next
        local can_decrease = not is_increasing and current_module_quality.level > target_quality.level

        if can_increase then
          new_module_quality = current_module_quality.next
        elseif can_decrease then
          new_module_quality = previous_qualities[current_module_quality.name]
        end
      end

      if new_module_quality then
        stack.clear()
        module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
      end
    end
  end
end

local function attempt_quality_change(entity)
  -- not sure how we can get here with an invalid entity
  if not entity.valid then
    log("Quality Control - attempt quality change called with invalid entity")
    return nil
  end

  local entity_info = tracked_entities[entity.unit_number]

  if not entity_info then
    log("Quality Control - attempt quality change skipped since no entity info was available")
    return nil  -- entity not tracked, invalid state
  end

  local random_roll = math.random()
  entity_info.attempts_to_change = entity_info.attempts_to_change + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    -- roll failed; improve it's chance for next time and return
    if settings_data.accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (settings_data.base_percentage_chance * settings_data.accumulation_percentage / 100)
    end
    return false
  end

  -- Save all entity properties before script.raise_script_destroy
  -- After the fast replace the entity is no longer available
  local unit_number = entity.unit_number
  local entity_type = entity.type
  local entity_name = entity.name
  local entity_surface = entity.surface
  local entity_position = entity.position
  local entity_force = entity.force
  local entity_direction = entity.direction

  local target_quality
  if settings_data.quality_change_direction == "increase" then
    target_quality = entity.quality.next
  else -- decrease
    target_quality = previous_qualities[entity.quality.name]
  end

  -- Need to call script_raised_destroy before the replacement attempt
  script.raise_script_destroy{entity = entity}

  local replacement_entity = entity_surface.create_entity {
    name = entity_name,
    position = entity_position,
    force = entity_force,
    direction = entity_direction,
    quality = target_quality,
    fast_replace = true,
    spill = false,
    raise_built=true,
  }

  if replacement_entity and replacement_entity.valid then
    core.remove_entity_info(unit_number) -- may not be needed since we already did raise_script_destroy
    update_module_quality(replacement_entity, target_quality, settings_data)
    notifications.show_entity_quality_alert(replacement_entity, settings_data.quality_change_direction)
    return replacement_entity
  else
    -- Unexpected failure after script_raised_destroy was called
    log("Quality Control - Unexpected Problem: Entity replacement failed")
    log("  - Entity unit_number: " .. unit_number)
    log("  - Entity type: " .. entity_type)
    log("  - Entity name: " .. entity_name)
    log("  - Target quality: " .. (target_quality and target_quality.name or "nil"))
    local history = prototypes.get_history(entity_type, entity_name)
    if history then
      log("  - From mod: " .. history.created)
    end
    core.remove_entity_info(unit_number) -- don't try to replace again
    return nil  -- signal to caller not to try again
  end
end


local function process_quality_attempts(entity, attempts_count, quality_changes)
  local successful_changes = 0
  local current_entity = entity

  for _ = 1, attempts_count do
    local change_result = attempt_quality_change(current_entity)

    if change_result == nil then
      -- entity is invalid, stop all attempts
      break
    end

    if change_result then
      successful_changes = successful_changes + 1
      current_entity = change_result
      quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
      -- check if we've hit max quality and stop attempts if so
      if current_entity.quality == quality_limit then
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

  -- Cache frequently accessed storage fields
  local primary_count = storage.primary_entity_count
  local secondary_count = storage.secondary_entity_count
  local accumulated_attempts = storage.accumulated_upgrade_attempts
  local batch_index = storage.batch_index
  local entity_list = storage.entity_list

  while entities_processed < batch_size do
    -- Check for end of list (cycle complete)
    if batch_index > #entity_list then
      batch_index = 1  -- Reset for next cycle
      break
    end

    local unit_number = entity_list[batch_index]
    batch_index = batch_index + 1

    local entity_info = tracked_entities[unit_number]
    if not entity_info or not entity_info.entity or not entity_info.entity.valid or not entity_info.can_change_quality then
      core.remove_entity_info(unit_number)
      goto continue
    end

    local entity = entity_info.entity

    if entity_info.is_primary then
        local recipe_time = 0
        if entity.get_recipe() then
          recipe_time = entity.get_recipe().prototype.energy
        elseif entity.type == "furnace" and entity.previous_recipe then
          recipe_time = entity.previous_recipe.name.energy
        end

        local hours_needed = settings_data.manufacturing_hours_for_change * (1 + settings_data.quality_increase_cost) ^ entity.quality.level
        local current_hours = (entity.products_finished * recipe_time) / 3600
        local previous_hours = entity_info.manufacturing_hours or 0
        local available_hours = current_hours - previous_hours
        local thresholds_passed = math.floor(available_hours / hours_needed)

        if thresholds_passed > 0 then
          -- Generate credits for secondary entities
          if secondary_count > 0 then
            local credit_ratio = secondary_count / math.max(primary_count, 1)
            local credits_added = thresholds_passed * credit_ratio
            accumulated_attempts = accumulated_attempts + credits_added
          end

          local successful_changes = process_quality_attempts(entity, thresholds_passed, quality_changes)
          if successful_changes == 0 and tracked_entities[unit_number] then
            entity_info.manufacturing_hours = current_hours
          end
        end
      else -- entity is a secondary entity type without hours
        if accumulated_attempts > 0 and secondary_count > 0 then
          local attempts_per_entity = accumulated_attempts / secondary_count
          local guaranteed_attempts = math.floor(attempts_per_entity)
          local fractional_chance = attempts_per_entity - guaranteed_attempts

          local total_attempts = guaranteed_attempts
          if fractional_chance > 0 and math.random() < fractional_chance then
            total_attempts = total_attempts + 1
          end

          if total_attempts > 0 then
            accumulated_attempts = math.max(0, accumulated_attempts - total_attempts)
            process_quality_attempts(entity, total_attempts, quality_changes)
          end
        end
      end

    entities_processed = entities_processed + 1
    ::continue::
  end

  -- Write back modified storage values
  storage.accumulated_upgrade_attempts = accumulated_attempts
  storage.batch_index = batch_index

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