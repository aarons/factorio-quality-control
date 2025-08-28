--[[
quality-processor.lua

Handles quality change attempts, dice rolls, and module quality updates.
Contains the core logic for attempting quality upgrades on entities.
]]

local notifications = require("scripts.notifications")
local quality_processor = {}

local tracked_entities = {}
local settings_data = {}
local quality_limit = nil

function quality_processor.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  quality_limit = storage.config.quality_limit
end

local function update_module_quality(replacement_entity, target_quality)
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
        local can_increase = current_module_quality.level < target_quality.level and current_module_quality.next

        if can_increase then
          new_module_quality = current_module_quality.next
        end
      end

      if new_module_quality then
        stack.clear()
        module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
      end
    end
  end
end

local function attempt_quality_change(entity, entity_tracker)
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
  local entity_mirroring = entity.mirroring -- wether the entity is flipped on it's axis or not

  local target_quality = entity.quality.next

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
    if entity_mirroring ~= nil then
      replacement_entity.mirroring = entity_mirroring
    end

    entity_tracker.remove_entity_info(unit_number) -- may not be needed since we already did raise_script_destroy
    update_module_quality(replacement_entity, target_quality)
    notifications.show_entity_quality_alert(replacement_entity)
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
    entity_tracker.remove_entity_info(unit_number) -- don't try to replace again
    return nil  -- signal to caller not to try again
  end
end

function quality_processor.process_quality_attempts(entity, attempts_count, quality_changes, entity_tracker)
  local successful_changes = 0
  local current_entity = entity

  for _ = 1, attempts_count do
    local change_result = attempt_quality_change(current_entity, entity_tracker)

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

return quality_processor