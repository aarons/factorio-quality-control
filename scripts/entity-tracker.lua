--[[
entity-tracker.lua

Handles entity tracking state management, exclusion logic, and entity lifecycle events.
Maintains the tracked entities list and manages entity addition/removal from tracking.
]]

local entity_tracker = {}

local tracked_entities = {}
local settings_data = {}
local is_tracked_type = {}

function entity_tracker.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
end

-- Exclude entities that don't work well with fast_replace or should be excluded
local function should_exclude_entity(entity)
  if not entity.prototype.selectable_in_game then
    return true
  end

  if not entity.destructible then
    return true
  end

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
        entity_tracker.remove_entity_info(found_entity.unit_number)
      end
    end
  end
end

function entity_tracker.get_entity_info(entity)
  if should_exclude_entity(entity) then
    -- remove_colocated_entity_info(entity) -- not sure this is needed, trying without for now
    return "entity excluded from quality control"
  end

  local id = entity.unit_number
  local can_change_quality = entity.quality.next ~= nil
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities with accumulation enabled
  local should_track = can_change_quality or (is_primary and settings_data.accumulate_at_max_quality)
  if not should_track then
    return "at max quality"
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

    -- Use ordered list for O(1) lookup in batch processing
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

function entity_tracker.scan_and_populate_entities(all_tracked_types)
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = all_tracked_types,
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      entity_tracker.get_entity_info(entity)
    end
  end
end

function entity_tracker.remove_entity_info(id)
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

function entity_tracker.on_entity_created(event)
  local entity = event.entity
  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    entity_tracker.get_entity_info(entity)
  end
end

function entity_tracker.on_entity_cloned(event)
  local entity = event.destination
  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    entity_tracker.get_entity_info(entity)
  end
end

function entity_tracker.on_entity_destroyed(event)
  local entity = event.entity
  if entity and entity.valid and is_tracked_type[entity.type] then
    entity_tracker.remove_entity_info(entity.unit_number)
  end
end

return entity_tracker