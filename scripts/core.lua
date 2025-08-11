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
local debug_enabled = false
local tracked_entities -- lookup table for all the entities we might change the quality of
local previous_qualities = {} -- lookup table for previous qualities in the chain

-- EWMA upgrade rate tracker for secondary entities
local upgrade_rate_tracker = {
  current_rate = 0.0,        -- Current estimated upgrade attempts per primary entity
  alpha = 0.001,             -- Smoothing factor: 0.01 = 230 samples to converge on the average, 0.001 = 2300 samples
  samples_count = 0          -- Number of primary entities processed
}

-- Settings (will be set by control.lua)
local settings_data = {}
local is_tracked_type = {}

function core.initialize(parsed_settings, tracked_type_lookup, quality_lookup)
  settings_data = parsed_settings
  is_tracked_type = tracked_type_lookup
  previous_qualities = quality_lookup
  tracked_entities = storage.quality_control_entities
end

local function debug(message)
  if debug_enabled then
    log("debug: " .. message)
  end
end

local function get_previous_quality(quality_prototype)
  return previous_qualities[quality_prototype.name]
end

function core.get_entity_info(entity)
  debug("get_entity_info called for entity type: " .. (entity.type or "unknown"))

  local id = entity.unit_number
  local entity_type = entity.type
  local previous_quality = get_previous_quality(entity.quality)
  local can_increase = settings_data.quality_change_direction == "increase" and entity.quality.next ~= nil
  local can_decrease = settings_data.quality_change_direction == "decrease" and previous_quality ~= nil
  local can_change_quality = can_increase or can_decrease

  -- Skip tracking entities that can't change quality
  if not can_change_quality then
    return nil
  end

  local is_primary = (entity_type == "assembling-machine" or entity_type == "furnace" or entity_type == "rocket-silo")

  if not tracked_entities[id] then
    tracked_entities[id] = {
      entity = entity,
      entity_type = entity_type,
      is_primary = is_primary,
      chance_to_change = settings_data.base_percentage_chance,
      attempts_to_change = 0,
      can_change_quality = can_change_quality
    }
    if is_primary then
      tracked_entities[id].manufacturing_hours = 0
    end
  end

  return tracked_entities[id]
end

function core.scan_and_populate_entities(all_tracked_types)
  debug("scan_and_populate_entities called")
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = all_tracked_types,
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      core.get_entity_info(entity) -- This will initialize the entity in tracked_entities
    end
  end
end

function core.remove_entity_info(id)
  if tracked_entities then
    tracked_entities[id] = nil
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
              if settings_data.quality_change_direction == "increase" then
                if current_module_quality.level < target_quality.level and current_module_quality.next then
                  new_module_quality = current_module_quality.next
                end
              else -- decrease
                if current_module_quality.level > target_quality.level then
                  new_module_quality = get_previous_quality(current_module_quality)
                end
              end
            elseif module_setting == "extra-enabled" then
              if current_module_quality.level ~= target_quality.level then
                new_module_quality = target_quality
              end
            end

            if new_module_quality then
              stack.clear()
              module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
            end
          end
        end
      end
    end

    notifications.show_entity_quality_alert(replacement_entity, settings_data.quality_change_direction)

    return replacement_entity
  end

  return nil
end

function core.batch_process_entities()
  debug("batch_process_entities called")

  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  -- Process entities using next() for natural iteration
  while entities_processed < batch_size do
    local unit_number, entity_info = next(tracked_entities, storage.last_processed_key)

    if not unit_number then
        storage.last_processed_key = nil
      break
    end

    local entity = entity_info.entity
    if not entity or not entity.valid or not entity_info.can_change_quality then
      debug("removing: " .. tostring(unit_number))
      core.remove_entity_info(unit_number)
    else
      if entity_info.is_primary then
        local thresholds_passed = 0
        local current_recipe = entity.get_recipe()
        if current_recipe then
          local hours_needed = settings_data.manufacturing_hours_for_change * (1 + settings_data.quality_increase_cost) ^ entity.quality.level
          local recipe_time = current_recipe.prototype.energy
          local current_hours = (entity.products_finished * recipe_time) / 3600
          local previous_hours = entity_info.manufacturing_hours or 0

          local available_hours = current_hours - previous_hours
          thresholds_passed = math.floor(available_hours / hours_needed)

          if thresholds_passed > 0 then
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

        upgrade_rate_tracker.current_rate = upgrade_rate_tracker.alpha * thresholds_passed + (1 - upgrade_rate_tracker.alpha) * upgrade_rate_tracker.current_rate
        upgrade_rate_tracker.samples_count = upgrade_rate_tracker.samples_count + 1
      else
        if upgrade_rate_tracker.current_rate > 0 and math.random() < upgrade_rate_tracker.current_rate then
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

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes, settings_data.quality_change_direction)
  end

  debug("Processed " .. entities_processed .. " entities this tick")
end

function core.on_entity_created(event)
  debug("on_entity_created called")
  local entity = event.entity or event.created_entity

  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_entity_destroyed(event)
  debug("on_entity_destroyed called")
  local entity = event.entity
  if entity and entity.valid then
    core.remove_entity_info(entity.unit_number)
  end
end

function core.on_quality_control_inspect(event)
  debug("on_quality_control_inspect called")
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