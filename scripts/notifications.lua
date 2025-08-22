--[[
notifications.lua

Handles all notification, alert, and UI display functionality.
This includes entity-specific alerts, aggregate notifications, and quality control inspection UI.
]]

local notifications = {}

-- Aggregate notification throttling (5 minutes = 18000 ticks)
local cooldown_ticks = 18000

function notifications.accumulate_quality_changes(quality_changes)
  for entity_name, count in pairs(quality_changes) do
    storage.aggregate_notifications.accumulated_changes[entity_name] =
      (storage.aggregate_notifications.accumulated_changes[entity_name] or 0) + count
  end
end

function notifications.try_show_accumulated_notifications(quality_change_direction)
  local current_tick = game.tick
  local time_since_last = current_tick - storage.aggregate_notifications.last_notification_tick

  if time_since_last >= cooldown_ticks and
     next(storage.aggregate_notifications.accumulated_changes) then

    local player = game.players[1]
    if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
      local messages = {}

      for entity_name, count in pairs(storage.aggregate_notifications.accumulated_changes) do
        local action = quality_change_direction == "increase" and "upgraded" or "downgraded"
        local plural = count > 1 and "s" or ""

        table.insert(messages, count .. " " .. entity_name .. plural .. " " .. action)
      end

      if #messages > 0 then
        player.print("Quality Control Updates:\n" .. table.concat(messages, "\n"))
      end
    end

    -- Reset after showing
    storage.aggregate_notifications.accumulated_changes = {}
    storage.aggregate_notifications.last_notification_tick = current_tick
  end
end

function notifications.show_entity_quality_alert(entity, change_type)
  local player = game.players[1] -- In single player, this is the player
  if player and settings.get_player_settings(player)["quality-change-entity-alerts-enabled"].value then
    local action = change_type == "increase" and "upgraded" or "downgraded"
    local message = action .. " quality to " .. entity.quality.name

    player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = entity.quality.name}, message, true)
  end
end

function notifications.show_quality_notifications(quality_changes, quality_change_direction)
  if next(quality_changes) then
    notifications.accumulate_quality_changes(quality_changes)
    notifications.try_show_accumulated_notifications(quality_change_direction)
  end
end

function notifications.show_entity_quality_info(player, is_tracked_type, get_entity_info, manufacturing_hours_for_change, quality_increase_cost, can_attempt_quality_change)
  local selected_entity = player.selected

  if not selected_entity or not selected_entity.valid then
    player.print({"quality-control.no-entity-selected"})
    return
  end

  if not is_tracked_type[selected_entity.type] then
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
    local is_enabled = can_attempt_quality_change[selected_entity.type]

    -- Show enabled/disabled status
    local enabled_text = is_enabled and "Yes" or "No"
    table.insert(info_parts, {"quality-control.enabled-for-quality-changes", enabled_text})

    if is_enabled then
      -- For enabled entities - show actual attempts and success chance
      table.insert(info_parts, {"quality-control.upgrades-attempted", entity_info.attempts_to_change})

      -- Progress to next attempt (for primary types with manufacturing hours)
      if is_primary_type and current_recipe then
        local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ selected_entity.quality.level
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
      -- For disabled entities - show virtual attempts that would have been generated
      if is_primary_type and current_recipe then
        local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ selected_entity.quality.level
        local recipe_time = current_recipe.prototype.energy
        local current_hours = (selected_entity.products_finished * recipe_time) / 3600
        local previous_hours = entity_info.manufacturing_hours or 0
        local progress_hours = current_hours - previous_hours
        local virtual_attempts = math.floor(current_hours / hours_needed)
        local progress_percentage = math.min(100, (progress_hours / hours_needed - virtual_attempts) * 100)

        table.insert(info_parts, {"quality-control.upgrade-attempts-generated", virtual_attempts})
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