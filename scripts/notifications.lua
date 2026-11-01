--[[
notifications.lua

Handles all notification, alert, and UI display functionality.
This includes entity-specific alerts, aggregate notifications, and quality control inspection UI.
]]

local progression = require("scripts.progression")
local quality_selector = require("scripts.quality_selector")
local celebrations = require("scripts.celebrations")
local upgrade_music = require("scripts.upgrade_music")
local upgrade_chat = require("scripts.upgrade_chat")

local notifications = {}

-- Aggregate notification throttling (5 minutes = 18000 ticks)
local cooldown_ticks = 18000

local turret_types = {
  ["turret"] = true, ["ammo-turret"] = true, ["electric-turret"] = true,
  ["fluid-turret"] = true, ["artillery-turret"] = true,
}

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

  local module_changes = storage.aggregate_notifications.accumulated_module_changes or {}
  if time_since_last >= cooldown_ticks and (next(storage.aggregate_notifications.accumulated_changes) or next(module_changes)) then
    -- Progression currently tracks only the player force, so its accumulated
    -- totals must not be disclosed to players on other forces.
    for _, player in pairs(game.connected_players) do
      if player.force == game.forces.player
        and settings.get_player_settings(player)["quality-change-aggregate-alerts-enabled"].value then
        player.print({"quality-control.aggregate-notification-header"})

        for entity_name, count in pairs(storage.aggregate_notifications.accumulated_changes) do
          player.print(entity_name .. ": " .. count)
        end
        for module_name, count in pairs(module_changes) do
          player.print({"quality-control.module-summary", {"item-name." .. module_name}, count})
        end
      end
    end

    -- Reset after showing
    storage.aggregate_notifications.accumulated_changes = {}
    storage.aggregate_notifications.accumulated_module_changes = {}
    storage.aggregate_notifications.last_notification_tick = current_tick
  end
end

local function deliver_upgrade(player, entity, target_quality_name, module_name)
  if not entity or not entity.valid then return end
  local quality = prototypes.quality[target_quality_name]
  local kind = module_name and "item" or "entity"
  local name = module_name or entity.name
  local localised_name = module_name and prototypes.item[module_name].localised_name or entity.localised_name
  local message_key = module_name and "quality-control.module-upgraded" or "quality-control.entity-upgraded"
  local message = {message_key, localised_name, quality.localised_name}
  local icon = {type = kind, name = name, quality = target_quality_name}

  local preferences = settings.get_player_settings(player)
  if preferences["quality-change-entity-alerts-enabled"].value then
    player.add_custom_alert(entity, icon, message, true)
  end
  -- Sprite tags display icons only, unlike entity/item/quality links, which
  -- append bracketed labels and repeat the names already in the sentence.
  local subject = {"", "[img=" .. kind .. "/" .. name .. "] ", localised_name}
  local quality_color = string.format("[color=%.3f,%.3f,%.3f]", quality.color.r, quality.color.g, quality.color.b)
  local quality_text = {"", "[img=quality/" .. target_quality_name .. "] ", quality_color, quality.localised_name, "[/color]"}
  upgrade_chat.show(player, entity, {"quality-control.entity-upgraded", subject, quality_text}, preferences)
  if preferences["quality-change-floating-text-enabled"].value then
    player.create_local_flying_text{
      text = {"quality-control.upgrade-floating", localised_name, quality.localised_name},
      position = entity.position, surface = entity.surface, color = quality.color,
      time_to_live = 90, speed = 1,
    }
  end
  -- surface follows the player's current view, including remote view.
  if preferences["quality-change-sound-enabled"].value and player.surface == entity.surface then
    player.play_sound{
      path = upgrade_music.path(player.index, preferences),
      volume_modifier = 0.6,
    }
  end
  celebrations.show(player, entity, quality, preferences)
end

local function show_upgrade(entity, target_quality_name, module_name)
  if not entity or not entity.valid then return end
  for _, player in pairs(game.connected_players) do
    if player.force == entity.force then
      deliver_upgrade(player, entity, target_quality_name, module_name)
    end
  end
end

function notifications.show_entity_quality_alert(entity, target_quality_name)
  show_upgrade(entity, target_quality_name)
end

function notifications.show_module_quality_alert(entity, module_name, target_quality_name)
  show_upgrade(entity, target_quality_name, module_name)
end

function notifications.show_quality_notifications(quality_changes, module_changes)
  if module_changes and next(module_changes) then
    local accumulated = storage.aggregate_notifications.accumulated_module_changes or {}
    storage.aggregate_notifications.accumulated_module_changes = accumulated
    for name, count in pairs(module_changes) do
      accumulated[name] = (accumulated[name] or 0) + count
    end
  end
  if next(quality_changes) or (module_changes and next(module_changes)) then
    notifications.accumulate_quality_changes(quality_changes)
    notifications.try_show_accumulated_notifications()
  end
end

-- Only current inventory slots are displayed. Stored trailing bonuses are
-- dormant history, never a claim about the host's present module capacity.
local function append_module_info(info_parts, entity, entity_info)
  if storage.config.settings_data.change_modules_with_entity ~= "independent"
    or not storage.config.can_attempt_quality_change[entity.type] then return end
  local inventory = entity.get_module_inventory()
  if not inventory then return end
  local bonuses = entity_info.module_failure_bonuses or {}
  for slot = 1, #inventory do
    local stack = inventory[slot]
    local bonus = bonuses[slot] or 0
    if stack.valid_for_read and stack.is_module then
      local chance = storage.config.settings_data.base_percentage_chance + bonus
      local status = quality_selector.has_upgrade_path(stack.quality.name)
        and {"quality-control.module-next-chance", string.format("%.2f", math.min(100, chance))}
        or {"quality-control.module-no-upgrade-path"}
      table.insert(info_parts, {"quality-control.module-slot", slot, stack.prototype.localised_name, stack.quality.localised_name,
        string.format("%.2f", bonus), status})
    else
      table.insert(info_parts, {"quality-control.module-slot-empty", slot, string.format("%.2f", bonus)})
    end
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
    local is_turret = turret_types[selected_entity.type] or false
    local is_enabled = storage.config.can_attempt_quality_change[selected_entity.type]
    local limit = storage.config.upgrade_limit_levels[selected_entity.type]
    local can_change_quality = quality_selector.has_upgrade_path(selected_entity.quality.name)
      and (not limit or selected_entity.quality.level < limit - 1)

    -- Primary entities earn credits from their total manufacturing hours; secondary
    -- entities have whatever their surface meter shows since their last reading
    local credits_earned = 0
    if is_primary_type then
      local hours_needed = storage.quality_multipliers[selected_entity.quality.level]
      local current_hours = progression.get_manufacturing_hours(selected_entity, is_turret)
      local progression_hours = progression.to_progression_hours(current_hours, selected_entity, is_turret)
      credits_earned = progression_hours / hours_needed
    end

    local credits_available = 0
    if not is_primary_type then
      local meter = storage.surface_meters[entity_info.surface_index] or 0
      local rate_multiplier = settings.global["secondary-progression-rate"].value / 100
      credits_available = (meter - entity_info.last_seen_meter) * rate_multiplier
    end

    local credits_spent = calculate_credits_spent_on_attempts(entity_info)

    if is_enabled and can_change_quality then
      table.insert(info_parts, {"quality-control.next-chance-to-change", string.format("%.2f", math.min(100, entity_info.chance_to_change))})
      if not is_primary_type then
        table.insert(info_parts, {"quality-control.credits-available", format_number_with_commas(credits_available, 2)})
      end
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

  if type(entity_info) == "table" then
    append_module_info(info_parts, selected_entity, entity_info)
  end

  -- Print all info
  for _, part in ipairs(info_parts) do
    player.print(part)
  end
end

return notifications
