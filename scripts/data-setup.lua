--[[
data-setup.lua

Handles all data structure initialization, settings parsing, and entity type configuration.
This separates the configuration logic from the main processing loop.
]]

local data_setup = {}

-- Entity categories configuration
local entity_categories = {
  primary = {
    ["assembling-machine"] = "assembly-machines",
    ["furnace"] = "furnaces",
    ["rocket-silo"] = "other-production"
  },
  electrical = {
    "electric-pole", "solar-panel", "accumulator", "generator", "reactor", "boiler", "heat-pipe",
    "power-switch", "lightning-rod"
  },
  other_production = {
    "agricultural-tower", "mining-drill"
  },
  defense = {
    "turret", "ammo-turret", "electric-turret", "fluid-turret", "artillery-turret", "wall", "gate"
  },
  space = {
    "asteroid-collector", "thruster", "cargo-landing-pad"
  },
  other = {
    "lamp", "arithmetic-combinator", "decider-combinator", "constant-combinator", "programmable-speaker"
  },
  standalone = {
    lab = "enable-labs",
    roboport = "enable-roboports",
    beacon = "enable-beacons",
    pump = "enable-pumps",
    ["offshore-pump"] = "enable-pumps",
    radar = "enable-radar",
    inserter = "enable-inserters"
  }
}

function data_setup.build_entity_type_lists()
  local primary_types = {}
  local secondary_types = {}
  local all_tracked_types = {}

  local primary_setting = settings.startup["primary-entities-selection"].value
  if primary_setting == "both" or primary_setting == "assembly-machines-only" then
    table.insert(primary_types, "assembling-machine")
    table.insert(all_tracked_types, "assembling-machine")
  end
  if primary_setting == "both" or primary_setting == "furnaces-only" then
    table.insert(primary_types, "furnace")
    table.insert(all_tracked_types, "furnace")
  end

  if settings.startup["enable-other-production-entities"].value then
    table.insert(primary_types, "rocket-silo")
    table.insert(all_tracked_types, "rocket-silo")
  end

  if settings.startup["enable-electrical-entities"].value then
    for _, entity_type in ipairs(entity_categories.electrical) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-other-production-entities"].value then
    for _, entity_type in ipairs(entity_categories.other_production) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-defense-entities"].value then
    for _, entity_type in ipairs(entity_categories.defense) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-space-entities"].value then
    for _, entity_type in ipairs(entity_categories.space) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  if settings.startup["enable-other-entities"].value then
    for _, entity_type in ipairs(entity_categories.other) do
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  for entity_type, setting_name in pairs(entity_categories.standalone) do
    if settings.startup[setting_name].value then
      table.insert(secondary_types, entity_type)
      table.insert(all_tracked_types, entity_type)
    end
  end

  return primary_types, secondary_types, all_tracked_types
end

function data_setup.build_is_tracked_type_lookup()
  local _, _, all_tracked_types = data_setup.build_entity_type_lists()
  local is_tracked_type = {}
  for _, entity_type in ipairs(all_tracked_types) do
    is_tracked_type[entity_type] = true
  end
  return is_tracked_type
end

function data_setup.parse_settings()
  local settings_data = {}

  settings_data.quality_change_direction = settings.startup["quality-change-direction"].value
  settings_data.manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  settings_data.quality_increase_cost = settings.startup["quality-increase-cost"].value / 100
  settings_data.base_percentage_chance = settings.startup["percentage-chance-of-change"].value

  local accumulation_rate_setting = settings.startup["quality-chance-accumulation-rate"].value
  settings_data.accumulation_percentage = 0

  if accumulation_rate_setting == "low" then
    settings_data.accumulation_percentage = 20
  elseif accumulation_rate_setting == "medium" then
    settings_data.accumulation_percentage = 50
  elseif accumulation_rate_setting == "high" then
    settings_data.accumulation_percentage = 100
  end

  return settings_data
end

function data_setup.build_previous_quality_lookup()
  local previous_qualities = {}
  for name, prototype in pairs(prototypes.quality) do
    if name ~= "quality-unknown" and prototype.next then
      previous_qualities[prototype.next.name] = prototype
    end
  end
  return previous_qualities
end

function data_setup.get_quality_limit(direction)
  if direction == "increase" then
    -- Find maximum quality by following the chain
    local current = prototypes.quality["normal"]
    while current.next do
      current = current.next
    end
    return current
  else -- decrease
    -- Minimum is always normal quality
    return prototypes.quality["normal"]
  end
end


function data_setup.setup_data_structures(force_reset)
  -- Handle force reset by clearing everything
  if force_reset then
    storage.quality_control_entities = {}
    storage.entity_list = {}
    storage.entity_list_index = {}
    storage.batch_index = 1
    storage.primary_entity_count = 0
    storage.secondary_entity_count = 0
    storage.accumulated_upgrade_attempts = 0
  end

  -- Initialize storage tables
  if not storage.quality_control_entities then
    storage.quality_control_entities = {}
  end

  if not storage.entity_list then
    storage.entity_list = {}
  end

  if not storage.entity_list_index then
    storage.entity_list_index = {}
    -- Rebuild index from existing entity_list for migration
    for i, unit_number in ipairs(storage.entity_list or {}) do
      if unit_number then
        storage.entity_list_index[unit_number] = i
      end
    end
  end

  if not storage.batch_index then
    storage.batch_index = 1
  end

  -- Initialize notification system
  if not storage.aggregate_notifications then
    storage.aggregate_notifications = {
      accumulated_changes = {},
      last_notification_tick = 0
    }
  end

  -- Initialize credit system
  if not storage.primary_entity_count then
    storage.primary_entity_count = 0
  end

  if not storage.secondary_entity_count then
    storage.secondary_entity_count = 0
  end

  if not storage.accumulated_upgrade_attempts then
    storage.accumulated_upgrade_attempts = 0
  end

  storage.data_structures_ready = true
end

return data_setup