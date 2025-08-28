--[[
orchestrator.lua

Orchestrates the main processing loop for quality control.
Coordinates between entity tracking, credit system, and quality processing.
Manages batch size and performance throttling.
]]

local notifications = require("scripts.notifications")
local orchestrator = {}

local tracked_entities = {}
local settings_data = {}

function orchestrator.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
end

function orchestrator.batch_process_entities(entity_tracker, credits, quality_processor)
  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  -- Cache frequently accessed storage fields
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
    -- Check if entity should remain tracked
    local should_stay_tracked = entity_info and entity_info.can_change_quality or
      (entity_info and entity_info.is_primary and settings_data.accumulate_at_max_quality)

    if not entity_info or not entity_info.entity or not entity_info.entity.valid or not should_stay_tracked then
      entity_tracker.remove_entity_info(unit_number)
      goto continue
    end

    local entity = entity_info.entity

    -- Skip entities marked for deconstruction to avoid losing the deconstruction mark
    if entity.to_be_deconstructed() then
      goto continue
    end

    if entity_info.is_primary then
      local credit_result = credits.process_primary_entity(entity_info, entity)
      if credit_result then
        local successful_changes = 0
        if credit_result.should_attempt_quality_change then
          successful_changes = quality_processor.process_quality_attempts(entity, credit_result.thresholds_passed, quality_changes, entity_tracker)
        end

        if successful_changes == 0 then
          credits.update_manufacturing_hours(entity_info, credit_result.current_hours)
        end
      end
    else -- entity is a secondary entity type without hours
      local secondary_result = credits.process_secondary_entity()
      if secondary_result then
        quality_processor.process_quality_attempts(entity, secondary_result.total_attempts, quality_changes, entity_tracker)
      end
    end

    entities_processed = entities_processed + 1
    ::continue::
  end

  -- Write back modified storage values
  storage.batch_index = batch_index

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes)
  end
end

return orchestrator