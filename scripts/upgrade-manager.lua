--[[
upgrade-manager.lua

Handles both the credit system and quality upgrade processing.
Combines credit generation/consumption with actual quality upgrade attempts.
]]

local notifications = require("scripts.notifications")
local upgrade_manager = {}

local tracked_entities = {}
local settings_data = {}
local quality_limit = nil
local can_attempt_quality_change = {}

function upgrade_manager.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  quality_limit = storage.config.quality_limit
  can_attempt_quality_change = storage.config.can_attempt_quality_change
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
  if not entity.valid then
    log("Quality Control - attempt quality change called with invalid entity")
    return nil
  end

  local entity_info = tracked_entities[entity.unit_number]

  if not entity_info then
    log("Quality Control - attempt quality change skipped since no entity info was available")
    return nil
  end

  local random_roll = math.random()
  entity_info.attempts_to_change = entity_info.attempts_to_change + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    if settings_data.accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (settings_data.base_percentage_chance * settings_data.accumulation_percentage / 100)
    end
    return false
  end

  local unit_number = entity.unit_number
  local entity_type = entity.type
  local entity_name = entity.name
  local entity_surface = entity.surface
  local entity_position = entity.position
  local entity_force = entity.force
  local entity_direction = entity.direction
  local entity_mirroring = entity.mirroring

  local target_quality = entity.quality.next

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

    entity_tracker.remove_entity_info(unit_number)
    update_module_quality(replacement_entity, target_quality)
    notifications.show_entity_quality_alert(replacement_entity)
    return replacement_entity
  else
    log("Quality Control - Unexpected Problem: Entity replacement failed")
    log("  - Entity unit_number: " .. unit_number)
    log("  - Entity type: " .. entity_type)
    log("  - Entity name: " .. entity_name)
    log("  - Target quality: " .. (target_quality and target_quality.name or "nil"))
    local history = prototypes.get_history(entity_type, entity_name)
    if history then
      log("  - From mod: " .. history.created)
    end
    entity_tracker.remove_entity_info(unit_number)
    return nil
  end
end

function upgrade_manager.process_quality_attempts(entity, attempts_count, quality_changes, entity_tracker)
  local successful_changes = 0
  local current_entity = entity

  for _ = 1, attempts_count do
    local change_result = attempt_quality_change(current_entity, entity_tracker)

    if change_result == nil then
      break
    end

    if change_result then
      successful_changes = successful_changes + 1
      current_entity = change_result
      quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
      if current_entity.quality == quality_limit then
        break
      end
    end
  end

  return successful_changes
end

function upgrade_manager.process_primary_entity(entity_info, entity)
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
    local secondary_count = storage.secondary_entity_count
    if secondary_count > 0 then
      local primary_count = storage.primary_entity_count
      local credit_ratio = secondary_count / math.max(primary_count, 1)
      local credits_added = thresholds_passed * credit_ratio
      storage.accumulated_upgrade_attempts = storage.accumulated_upgrade_attempts + credits_added
    end

    return {
      thresholds_passed = thresholds_passed,
      current_hours = current_hours,
      should_attempt_quality_change = can_attempt_quality_change[entity.type] and entity_info.can_change_quality
    }
  end

  return nil
end

function upgrade_manager.process_secondary_entity()
  local accumulated_attempts = storage.accumulated_upgrade_attempts
  local secondary_count = storage.secondary_entity_count

  if accumulated_attempts > 0 and secondary_count > 0 then
    local attempts_per_entity = accumulated_attempts / secondary_count
    local guaranteed_attempts = math.floor(attempts_per_entity)
    local fractional_chance = attempts_per_entity - guaranteed_attempts

    local total_attempts = guaranteed_attempts
    if fractional_chance > 0 and math.random() < fractional_chance then
      total_attempts = total_attempts + 1
    end

    if total_attempts > 0 then
      storage.accumulated_upgrade_attempts = math.max(0, accumulated_attempts - total_attempts)
      return { total_attempts = total_attempts }
    end
  end

  return nil
end

function upgrade_manager.update_manufacturing_hours(entity_info, current_hours)
  if tracked_entities[entity_info.entity.unit_number] then
    entity_info.manufacturing_hours = current_hours
  end
end

return upgrade_manager