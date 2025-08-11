--[[
notifications.lua

Handles all notification, alert, and UI display functionality.
This includes entity-specific alerts, aggregate notifications, and quality control inspection UI.
]]

local notifications = {}

function notifications.show_entity_quality_alert(entity, change_type)
  local player = game.players[1] -- In single player, this is the player
  if player and settings.get_player_settings(player)["quality-change-entity-alerts-enabled"].value then
    local action = change_type == "increase" and "upgraded" or "downgraded"
    local message = action .. " quality to " .. entity.quality.name

    player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = entity.quality.name}, message, true)
  end
end

function notifications.show_quality_notifications(quality_changes, quality_change_direction)
  -- Show aggregate console alerts if enabled
  local player = game.players[1]
  if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
    local messages = {}

    for entity_name, count in pairs(quality_changes) do
      local action = quality_change_direction == "increase" and "upgraded" or "downgraded"
      local plural = count > 1 and "s" or ""

      table.insert(messages, count .. " " .. entity_name .. plural .. " " .. action)
    end

    if #messages > 0 then
      player.print("Quality Control Updates:\n" .. table.concat(messages, "\n"))
    end
  end
end

function notifications.show_entity_quality_info(player, is_tracked_type, get_entity_info, manufacturing_hours_for_change, quality_increase_cost)
  local selected_entity = player.selected

  if not selected_entity or not selected_entity.valid then
    player.print({"quality-control.no-entity-selected"})
    return
  end

  if not is_tracked_type[selected_entity.type] then
    player.print("selected_entity.type: " .. selected_entity.type)
    player.print("is_tracked_type table contents:")
    for key, value in pairs(is_tracked_type) do
      player.print("  " .. key .. " = " .. tostring(value))
    end
    player.print({"quality-control.entity-not-tracked", selected_entity.localised_name or selected_entity.name})
    return
  end

  local entity_info = get_entity_info(selected_entity)
  local is_primary_type = entity_info.is_primary
  local current_recipe = is_primary_type and selected_entity.get_recipe and selected_entity.get_recipe()

  -- Build info message parts
  local info_parts = {}

  -- Basic entity info
  table.insert(info_parts, {"quality-control.entity-info-header", selected_entity.localised_name or selected_entity.name, selected_entity.quality.localised_name})

  -- Attempts to change
  table.insert(info_parts, {"quality-control.attempts-to-change", entity_info.attempts_to_change})

  -- Current chance of change
  table.insert(info_parts, {"quality-control.current-chance", string.format("%.2f", entity_info.chance_to_change)})

  -- Progress to next attempt (for primary types with manufacturing hours)
  if is_primary_type and current_recipe then
    local hours_needed = manufacturing_hours_for_change * (1 + quality_increase_cost) ^ selected_entity.quality.level
    local recipe_time = current_recipe.prototype.energy
    local current_hours = (selected_entity.products_finished * recipe_time) / 3600
    local previous_hours = entity_info.manufacturing_hours or 0
    local progress_hours = current_hours - previous_hours
    local progress_percentage = math.min(100, (progress_hours / hours_needed) * 100)

    table.insert(info_parts, {"quality-control.manufacturing-hours", string.format("%.2f", current_hours), string.format("%.2f", hours_needed)})
    table.insert(info_parts, {"quality-control.progress-to-next", string.format("%.1f", progress_percentage)})
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

return notifications