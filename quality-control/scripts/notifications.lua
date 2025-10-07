--[[
notifications.lua

Handles all notification, alert, and UI display functionality.
This includes entity-specific alerts, aggregate notifications, and quality control inspection UI.
]]

local notifications = {}

function notifications.accumulate_quality_changes(quality_changes)
  for entity_name, count in pairs(quality_changes) do
    storage.aggregate_notifications.accumulated_changes[entity_name] =
      (storage.aggregate_notifications.accumulated_changes[entity_name] or 0) + count
  end
end

function notifications.try_show_accumulated_notifications()
  if not next(storage.aggregate_notifications.accumulated_changes) then
    return
  end

  -- Get cooldown from global settings (convert minutes to ticks: 1 minute = 3600 ticks)
  local cooldown_minutes = settings.global["aggregate-notification-cooldown-minutes"].value
  local cooldown_ticks = cooldown_minutes * 3600

  local current_tick = game.tick
  local time_since_last = current_tick - storage.aggregate_notifications.last_notification_tick

  if time_since_last >= cooldown_ticks then
    if settings.global["quality-change-aggregate-alerts-enabled"].value then
      game.print({"quality-control.aggregate-notification-header"})

      for entity_name, count in pairs(storage.aggregate_notifications.accumulated_changes) do
        game.print(entity_name .. ": " .. count)
      end
    end

    -- Reset after showing
    storage.aggregate_notifications.accumulated_changes = {}
    storage.aggregate_notifications.last_notification_tick = current_tick
  end
end

function notifications.show_entity_quality_alert(entity, target_quality_name)
  -- Check each player's individual setting
  for _, player in pairs(game.players) do
    if player.mod_settings["quality-change-entity-alerts-enabled"].value then
      local message = "upgraded quality to " .. target_quality_name
      player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = target_quality_name}, message, true)
    end
  end
end

function notifications.show_quality_notifications(quality_changes)
  if next(quality_changes) then
    notifications.accumulate_quality_changes(quality_changes)
    notifications.try_show_accumulated_notifications()
  end
end

function notifications.show_entity_quality_info(player, get_entity_info)
  local selected_entity = player.selected

  if not selected_entity or not selected_entity.valid then
    player.print({"quality-control.no-entity-selected"})
    return
  end

  if not storage.config.is_tracked_type[selected_entity.type] then
    player.print({"quality-control.entity-not-supported", selected_entity.localised_name or selected_entity.name})
    return
  end

  local entity_info = get_entity_info(selected_entity)

  -- Build info message parts
  local info_parts = {}

  -- Basic entity info
  table.insert(info_parts, {"quality-control.entity-info-header", selected_entity.localised_name or selected_entity.name, selected_entity.quality.localised_name})

  -- Check if entity_info is an error code (string) instead of a table
  if type(entity_info) == "string" then
    -- Entity can't change quality - show simple message
    table.insert(info_parts, {"quality-control.entity-not-tracked-reason", entity_info})
  else
    -- Normal entity_info table - show tracking data
    local is_primary_type = entity_info.is_primary
    local current_recipe = is_primary_type and selected_entity.get_recipe and selected_entity.get_recipe()
    local is_enabled = storage.config.can_attempt_quality_change[selected_entity.type]
    local can_change_quality = selected_entity.quality ~= storage.config.quality_limit

    -- Show eligibility status
    local eligible_text
    if not is_enabled then
      eligible_text = "No - disabled in settings"
    elseif not can_change_quality then
      eligible_text = "No - at quality limit"
    else
      eligible_text = "Yes"
    end
    table.insert(info_parts, {"quality-control.eligible-for-quality-changes", eligible_text})

    if can_change_quality then
      -- For entities that can change quality - show attempts based on entity type
      if is_primary_type then
        table.insert(info_parts, {"quality-control.credits-earned", entity_info.luck_accumulation})
      else
        table.insert(info_parts, {"quality-control.upgrade-attempts", entity_info.luck_accumulation})
      end

      -- Progress to next attempt (for primary types with manufacturing hours)
      if is_primary_type and current_recipe then
        local hours_needed = storage.quality_multipliers[selected_entity.quality.level]
        local recipe_time = current_recipe.prototype.energy
        local current_hours = (selected_entity.products_finished * recipe_time) / 3600
        local previous_hours = entity_info.manufacturing_hours or 0
        local progress_hours = current_hours - previous_hours
        local progress_percentage = math.min(100, (progress_hours / hours_needed) * 100)

        table.insert(info_parts, {"quality-control.progress-to-next-attempt", string.format("%.0f", progress_percentage)})
      end

      -- Current chance of change (capped at 100% for display)
      table.insert(info_parts, {"quality-control.chance-of-success", string.format("%.0f", math.min(100, entity_info.chance_to_change))})
    else
      -- For entities that cannot change quality but are tracked - show attempts based on entity type
      if is_primary_type then
        table.insert(info_parts, {"quality-control.credits-earned", entity_info.luck_accumulation})
      else
        table.insert(info_parts, {"quality-control.upgrade-attempts", entity_info.luck_accumulation})
      end

      -- Progress to next event generation (for primary types with manufacturing hours)
      if is_primary_type and current_recipe then
        local hours_needed = storage.quality_multipliers[selected_entity.quality.level]
        local recipe_time = current_recipe.prototype.energy
        local current_hours = (selected_entity.products_finished * recipe_time) / 3600
        local previous_hours = entity_info.manufacturing_hours or 0
        local progress_hours = current_hours - previous_hours
        local progress_percentage = math.min(100, (progress_hours / hours_needed) * 100)

        table.insert(info_parts, {"quality-control.progress-to-next-attempt", string.format("%.0f", progress_percentage)})
      end
    end
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

return notifications