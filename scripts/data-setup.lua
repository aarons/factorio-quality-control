--[[
data-setup.lua

Handles all data structure initialization, settings parsing, and entity type configuration.
This separates the configuration logic from the main processing loop.
]]

local data_setup = {}

-- Entity type to setting name mappings
local entity_to_setting_map = {
  -- Production entities (includes primary entities)
  ["assembling-machine"] = "enable-assembly-machines",
  ["furnace"] = "enable-furnaces",
  ["agricultural-tower"] = "enable-agricultural-towers",
  ["mining-drill"] = "enable-mining-drills",

  -- Electrical infrastructure
  ["electric-pole"] = "enable-poles",
  ["solar-panel"] = "enable-solar-panels",
  ["accumulator"] = "enable-accumulators",
  ["generator"] = "enable-generators",
  ["reactor"] = "enable-reactors",
  ["boiler"] = "enable-boilers",
  ["heat-pipe"] = "enable-heat-pipes",
  ["power-switch"] = "enable-power-switches",
  ["lightning-rod"] = "enable-lightning-rods",

  -- Defense entities
  ["turret"] = "enable-turrets",
  ["ammo-turret"] = "enable-turrets",
  ["electric-turret"] = "enable-turrets",
  ["fluid-turret"] = "enable-turrets",
  ["artillery-turret"] = "enable-turrets",
  ["wall"] = "enable-defense-walls-and-gates",
  ["gate"] = "enable-defense-walls-and-gates",

  -- Space platform entities
  ["asteroid-collector"] = "enable-asteroid-collectors",
  ["thruster"] = "enable-thrusters",

  -- Other entities
  ["lamp"] = "enable-lamps",
  ["arithmetic-combinator"] = "enable-combinators-and-speakers",
  ["decider-combinator"] = "enable-combinators-and-speakers",
  ["constant-combinator"] = "enable-combinators-and-speakers",
  ["programmable-speaker"] = "enable-combinators-and-speakers",
  ["lab"] = "enable-labs",
  ["roboport"] = "enable-roboports",
  ["beacon"] = "enable-beacons",
  ["pump"] = "enable-pumps",
  ["offshore-pump"] = "enable-pumps",
  ["radar"] = "enable-radar",
  ["inserter"] = "enable-inserters"
}

-- Primary entity types for determining manufacturing hours logic
local primary_entity_types = {"assembling-machine", "furnace"}

function data_setup.build_entity_type_lists()
  local primary_types = {}
  local secondary_types = {}
  local all_tracked_types = {table.unpack(primary_entity_types)} -- include primary types since they are the only ones to generate qauality change events

  -- Build lists by checking individual entity type settings
  for entity_type, setting_name in pairs(entity_to_setting_map) do
    if settings.startup[setting_name].value then
      -- Check if this is a primary entity type
      local is_primary = false
      for _, primary_type in ipairs(primary_entity_types) do
        if entity_type == primary_type then
          is_primary = true
          break
        end
      end

      if is_primary then
        table.insert(primary_types, entity_type)
      else
        table.insert(secondary_types, entity_type)
      end
      table.insert(all_tracked_types, entity_type)
    end
  end

  return primary_types, secondary_types, all_tracked_types
end

function data_setup.build_and_store_config()
  if not storage.config then
    storage.config = {}
  end

  local primary_types, secondary_types, all_tracked_types = data_setup.build_entity_type_lists()
  storage.config.primary_types = primary_types
  storage.config.secondary_types = secondary_types
  storage.config.all_tracked_types = all_tracked_types

  local is_tracked_type = {}
  for _, entity_type in ipairs(all_tracked_types) do
    is_tracked_type[entity_type] = true
  end
  storage.config.is_tracked_type = is_tracked_type

  -- Store which entity types should be allowed to have quality changes attempted
  local can_attempt_quality_change = {}
  for entity_type, setting_name in pairs(entity_to_setting_map) do
    can_attempt_quality_change[entity_type] = settings.startup[setting_name].value
  end
  storage.config.can_attempt_quality_change = can_attempt_quality_change

  local settings_data = {}
  settings_data.quality_change_direction = settings.startup["quality-change-direction"].value
  settings_data.manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  settings_data.quality_increase_cost = settings.startup["quality-increase-cost"].value / 100
  settings_data.base_percentage_chance = settings.startup["percentage-chance-of-change"].value
  settings_data.accumulate_at_max_quality = settings.startup["accumulate-at-max-quality"].value

  local accumulation_rate_setting = settings.startup["quality-chance-accumulation-rate"].value
  settings_data.accumulation_percentage = 0

  if accumulation_rate_setting == "low" then
    settings_data.accumulation_percentage = 20
  elseif accumulation_rate_setting == "medium" then
    settings_data.accumulation_percentage = 50
  elseif accumulation_rate_setting == "high" then
    settings_data.accumulation_percentage = 100
  end
  storage.config.settings_data = settings_data

  local previous_qualities = {}
  for name, prototype in pairs(prototypes.quality) do
    if name ~= "quality-unknown" and prototype.next then
      previous_qualities[prototype.next.name] = prototype
    end
  end
  storage.config.previous_qualities = previous_qualities

  local quality_limit
  if settings_data.quality_change_direction == "increase" then
    local current = prototypes.quality["normal"]
    while current.next do
      current = current.next
    end
    quality_limit = current
  else
    quality_limit = prototypes.quality["normal"]
  end
  storage.config.quality_limit = quality_limit
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
end

return data_setup