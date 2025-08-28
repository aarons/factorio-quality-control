--[[
credits.lua

Handles the credit system that links primary and secondary entities.
Primary entities (assemblers, furnaces) generate credits based on manufacturing hours.
Secondary entities consume credits for quality upgrade attempts.
]]

local credits = {}

local tracked_entities = {}
local settings_data = {}
local can_attempt_quality_change = {}

function credits.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  can_attempt_quality_change = storage.config.can_attempt_quality_change
end

function credits.process_primary_entity(entity_info, entity)
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
    local secondary_count = storage.secondary_entity_count
    if secondary_count > 0 then
      local primary_count = storage.primary_entity_count
      local credit_ratio = secondary_count / math.max(primary_count, 1)
      local credits_added = thresholds_passed * credit_ratio
      storage.accumulated_upgrade_attempts = storage.accumulated_upgrade_attempts + credits_added
    end

    -- Return information about what needs to happen
    return {
      thresholds_passed = thresholds_passed,
      current_hours = current_hours,
      should_attempt_quality_change = can_attempt_quality_change[entity.type] and entity_info.can_change_quality
    }
  end

  return nil
end

function credits.process_secondary_entity()
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

function credits.update_manufacturing_hours(entity_info, current_hours)
  if tracked_entities[entity_info.entity.unit_number] then
    entity_info.manufacturing_hours = current_hours
  end
end

return credits