--[[
notifications.lua

Handles all notification, alert, and UI display functionality.
This includes entity-specific alerts, aggregate notifications, and quality control inspection UI.
]]

local notifications = {}

-- Aggregate notification throttling (5 minutes = 18000 ticks)
local cooldown_ticks = 18000

-- Calculate total credits spent on upgrade attempts based on current chance_to_change
-- Returns the equivalent number of credits that have been used in failed upgrade attempts
local function calculate_credits_spent_on_attempts(entity_info)
  local base_percentage_chance = storage.config.settings_data.base_percentage_chance
  local accumulation_percentage = storage.config.settings_data.accumulation_percentage

  if accumulation_percentage == 0 then
    return 0
  end

  local chance_increase = entity_info.chance_to_change - base_percentage_chance
  if chance_increase <= 0 then
    return 0
  end

  local credits_spent = (chance_increase * 100) / (base_percentage_chance * accumulation_percentage)
  return credits_spent
end

-- Format number with thousands separator
local function format_number_with_commas(number, decimal_places)
  local formatted = string.format("%." .. decimal_places .. "f", number)
  local int_part, dec_part = formatted:match("^([^.]*)(.*)$")

  -- Add commas to integer part
  local k
  while true do
    int_part, k = int_part:gsub("^(-?%d+)(%d%d%d)", '%1,%2')
    if k == 0 then break end
  end

  return int_part .. dec_part
end

function notifications.accumulate_quality_changes(quality_changes)
  for entity_name, count in pairs(quality_changes) do
    storage.aggregate_notifications.accumulated_changes[entity_name] =
      (storage.aggregate_notifications.accumulated_changes[entity_name] or 0) + count
  end
end

function notifications.try_show_accumulated_notifications()
  local current_tick = game.tick
  local time_since_last = current_tick - storage.aggregate_notifications.last_notification_tick

  if time_since_last >= cooldown_ticks and next(storage.aggregate_notifications.accumulated_changes) then
    local player = game.players[1]
    if player and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
      player.print({"quality-control.aggregate-notification-header"})

      for entity_name, count in pairs(storage.aggregate_notifications.accumulated_changes) do
        player.print(entity_name .. ": " .. count)
      end
    end

    -- Reset after showing
    storage.aggregate_notifications.accumulated_changes = {}
    storage.aggregate_notifications.last_notification_tick = current_tick
  end
end

function notifications.show_entity_quality_alert(entity, target_quality_name)
  local player = game.players[1] -- In single player, this is the player
  if player and settings.get_player_settings(player)["quality-change-entity-alerts-enabled"].value then
    local message = "upgraded quality to " .. target_quality_name

    player.add_custom_alert(entity, {type = "entity", name = entity.prototype.name, quality = target_quality_name}, message, true)
  end
end

function notifications.show_quality_notifications(quality_changes)
  if next(quality_changes) then
    notifications.accumulate_quality_changes(quality_changes)
    notifications.try_show_accumulated_notifications()
  end
end

-- TODO: cool feature idea
-- Estimated time until next attempt: 3 minutes, 12 seconds
    -- calculated by dividing total_tracked_entities / entities per tick / ticks per second - take into account batch process percentage complete / position in batch

-- Primary entity that can still upgrade notification example:
-- Assembler 1 - Uncommon Quality
-- The next credit provides a 12.35% chance of upgrade
-- Credits earned for upgrade attempts: 11.38

-- Primary entity that is at max quality notification:
-- Assembler 1 - Legendary Quality
-- This entity is at max quality.
-- Credits earned for upgrade attempts: 11.38

-- Secondary entity notification format:
-- Bulk inserter - Normal quality
-- The next credit provides a 1.35% chance of upgrade
-- Credits used on upgrade attempts so far: 0.02

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
    -- Not an entity but an error, show simple message
    table.insert(info_parts, {"quality-control.entity-not-tracked-reason", entity_info})
  else
    -- Normal entity_info table - show tracking data
    local is_primary_type = entity_info.is_primary
    local current_recipe = is_primary_type and selected_entity.get_recipe and selected_entity.get_recipe()
    local is_enabled = storage.config.can_attempt_quality_change[selected_entity.type]
    local can_change_quality = selected_entity.quality ~= storage.config.quality_limit

    -- Calculate credits earned for primary entities (based on total manufacturing hours)
    local credits_earned = 0
    if is_primary_type and current_recipe then
      local hours_needed = storage.quality_multipliers[selected_entity.quality.level]
      local recipe_time = current_recipe.prototype.energy
      local current_hours = (selected_entity.products_finished * recipe_time) / 3600
      credits_earned = current_hours / hours_needed
    end

    local credits_spent = calculate_credits_spent_on_attempts(entity_info)

    if is_enabled and can_change_quality then
      table.insert(info_parts, {"quality-control.next-chance-to-change", string.format("%.2f", math.min(100, entity_info.chance_to_change))})
      table.insert(info_parts, {"quality-control.credits-used", format_number_with_commas(credits_spent, 2)})
    elseif is_enabled then
      -- For entities that cannot change quality but are still generating credits
      table.insert(info_parts, {"quality-control.entity-at-quality-limit"})
      table.insert(info_parts, {"quality-control.credits-earned", format_number_with_commas(credits_earned, 2)})
    else
      -- entity is not enabled for quality control tracking
      table.insert(info_parts, {"quality-control.entity-type-disabled"})
    end
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

return notifications