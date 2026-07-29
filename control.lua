--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, configuration setup, and orchestrates core processing.
]]

local core = require("scripts.core")
local notifications = require("scripts.notifications")
local exclusions = require("scripts.exclusions")

-- Entity type to upgrade limit setting name mappings.
-- Each limit is a runtime-global dropdown of quality tier names, resolved to a
-- numeric quality level by get_upgrade_limit_level below.
local entity_to_setting_map = {
  -- Production entities (includes primary entities)
  ["assembling-machine"] = "upgrade-limit-assembly-machines",
  ["furnace"] = "upgrade-limit-furnaces",
  ["rocket-silo"] = "upgrade-limit-rocket-silos",
  ["agricultural-tower"] = "upgrade-limit-agricultural-towers",
  ["mining-drill"] = "upgrade-limit-mining-drills",

  -- Electrical infrastructure
  ["electric-pole"] = "upgrade-limit-poles",
  ["solar-panel"] = "upgrade-limit-solar-panels",
  ["accumulator"] = "upgrade-limit-accumulators",
  ["generator"] = "upgrade-limit-generators",
  ["reactor"] = "upgrade-limit-reactors",
  ["fusion-reactor"] = "upgrade-limit-reactors",
  ["fusion-generator"] = "upgrade-limit-generators",
  ["boiler"] = "upgrade-limit-boilers",
  ["heat-pipe"] = "upgrade-limit-heat-pipes",
  ["power-switch"] = "upgrade-limit-power-switches",
  ["lightning-attractor"] = "upgrade-limit-lightning-rods",

  -- Defense entities
  ["turret"] = "upgrade-limit-turrets",
  ["ammo-turret"] = "upgrade-limit-turrets",
  ["electric-turret"] = "upgrade-limit-turrets",
  ["fluid-turret"] = "upgrade-limit-turrets",
  ["artillery-turret"] = "upgrade-limit-turrets",
  ["wall"] = "upgrade-limit-defense-walls-and-gates",
  ["gate"] = "upgrade-limit-defense-walls-and-gates",

  -- Space platform entities
  ["asteroid-collector"] = "upgrade-limit-asteroid-collectors",
  ["thruster"] = "upgrade-limit-thrusters",

  -- Other entities
  ["lamp"] = "upgrade-limit-lamps",
  ["arithmetic-combinator"] = "upgrade-limit-combinators-and-speakers",
  ["decider-combinator"] = "upgrade-limit-combinators-and-speakers",
  ["constant-combinator"] = "upgrade-limit-combinators-and-speakers",
  ["programmable-speaker"] = "upgrade-limit-combinators-and-speakers",
  ["lab"] = "upgrade-limit-labs",
  ["roboport"] = "upgrade-limit-roboports",
  ["beacon"] = "upgrade-limit-beacons",
  ["pump"] = "upgrade-limit-pumps",
  ["offshore-pump"] = "upgrade-limit-pumps",
  ["radar"] = "upgrade-limit-radar",
  ["inserter"] = "upgrade-limit-inserters"
}

-- Numeric quality level for each limit dropdown value. Levels are 1-based tier
-- counts (normal = 1 ... legendary = 5); 255 is the engine maximum and acts
-- as "unlimited". A limit of 1 ("common") disables upgrades for that entity
-- type, since entities cannot upgrade past the first tier.
local limit_value_to_level = {
  ["common"] = 1,
  ["uncommon"] = 2,
  ["rare"] = 3,
  ["epic"] = 4,
  ["legendary"] = 5,
  ["unlimited"] = 255
}

-- The "custom a/b/c" dropdown values read their level from these settings.
local custom_level_setting_for_value = {
  ["custom-a"] = "custom-upgrade-limit-a",
  ["custom-b"] = "custom-upgrade-limit-b",
  ["custom-c"] = "custom-upgrade-limit-c"
}

local custom_upgrade_limit_settings = {}
for _, setting_name in pairs(custom_level_setting_for_value) do
  custom_upgrade_limit_settings[setting_name] = true
end

--- Resolves an upgrade limit setting to its numeric quality level.
local function get_upgrade_limit_level(limit_setting_name)
  local value = settings.global[limit_setting_name].value
  local custom_setting = custom_level_setting_for_value[value]
  if custom_setting then
    return settings.global[custom_setting].value
  end
  return limit_value_to_level[value]
end

-- Lookup from setting name to entity group for the deprecated startup settings.
-- Used only for the one-time migration of old saves to the new runtime-global upgrade limits.
local limit_setting_migration_map = {
  ["upgrade-limit-accumulators"] = {old_bool = "enable-accumulators"},
  ["upgrade-limit-agricultural-towers"] = {old_bool = "enable-agricultural-towers"},
  ["upgrade-limit-assembly-machines"] = {old_bool = "enable-assembly-machines"},
  ["upgrade-limit-asteroid-collectors"] = {old_bool = "enable-asteroid-collectors", old_limit = "asteroid-collector-growth-level-limit"},
  ["upgrade-limit-beacons"] = {old_bool = "enable-beacons"},
  ["upgrade-limit-boilers"] = {old_bool = "enable-boilers"},
  ["upgrade-limit-combinators-and-speakers"] = {old_bool = "enable-combinators-and-speakers"},
  ["upgrade-limit-defense-walls-and-gates"] = {old_bool = "enable-defense-walls-and-gates"},
  ["upgrade-limit-furnaces"] = {old_bool = "enable-furnaces"},
  ["upgrade-limit-generators"] = {old_bool = "enable-generators"},
  ["upgrade-limit-heat-pipes"] = {old_bool = "enable-heat-pipes"},
  ["upgrade-limit-inserters"] = {old_bool = "enable-inserters"},
  ["upgrade-limit-labs"] = {old_bool = "enable-labs"},
  ["upgrade-limit-lamps"] = {old_bool = "enable-lamps"},
  ["upgrade-limit-lightning-rods"] = {old_bool = "enable-lightning-rods", old_limit = "lightning-attractor-growth-level-limit"},
  ["upgrade-limit-mining-drills"] = {old_bool = "enable-mining-drills"},
  ["upgrade-limit-poles"] = {old_bool = "enable-poles"},
  ["upgrade-limit-power-switches"] = {old_bool = "enable-power-switches"},
  ["upgrade-limit-pumps"] = {old_bool = "enable-pumps"},
  ["upgrade-limit-radar"] = {old_bool = "enable-radar", old_limit = "radar-growth-level-limit"},
  ["upgrade-limit-reactors"] = {old_bool = "enable-reactors"},
  ["upgrade-limit-rocket-silos"] = {old_bool = "enable-rocket-silos"},
  ["upgrade-limit-roboports"] = {old_bool = "enable-roboports"},
  ["upgrade-limit-solar-panels"] = {old_bool = "enable-solar-panels"},
  ["upgrade-limit-thrusters"] = {old_bool = "enable-thrusters", old_limit = "thruster-growth-level-limit"},
  ["upgrade-limit-turrets"] = {old_bool = "enable-turrets"}
}

--- One-time migration from the old startup bool/limit settings to the new
--- runtime-global upgrade limits. Guarded by a storage flag so it runs
--- exactly once and can't overwrite later changes on subsequent updates.
local function migrate_upgrade_limits_to_runtime_settings()
  if storage.upgrade_limits_migrated then
    return
  end
  storage.upgrade_limits_migrated = true

  local level_to_limit_value = {"common", "uncommon", "rare", "epic", "legendary"}
  -- Old numeric limits above legendary have no named tier, so they are
  -- preserved by assigning them to the custom a/b/c slots. There are four old
  -- limit settings and three slots; any value that doesn't fit falls back to
  -- unlimited.
  local free_custom_values = {"custom-a", "custom-b", "custom-c"}
  local custom_value_for_level = {}

  for limit_setting, old in pairs(limit_setting_migration_map) do
    local value
    if not settings.startup[old.old_bool].value then
      -- Old bool off means the entity type was disabled; a "common" limit
      -- preserves that by blocking upgrades past the first tier
      value = "common"
    elseif old.old_limit then
      local level = settings.startup[old.old_limit].value
      value = level_to_limit_value[level] or custom_value_for_level[level]
      if not value then
        value = table.remove(free_custom_values, 1) or "unlimited"
        if value ~= "unlimited" then
          custom_value_for_level[level] = value
          settings.global[custom_level_setting_for_value[value]] = {value = level}
        end
      end
    else
      value = "unlimited"
    end
    settings.global[limit_setting] = {value = value}
  end
end

-- Primary entity types for determining manufacturing hours logic
local primary_entity_types = {
  "assembling-machine", "furnace", "rocket-silo",
  "turret", "ammo-turret", "electric-turret", "fluid-turret", "artillery-turret"
}

local function build_entity_type_lists()
  local primary_types = {}
  local secondary_types = {}
  local all_tracked_types = {table.unpack(primary_entity_types)} -- always include primary types since they are the only ones to generate quality change events

  -- Build lists by checking individual entity type settings
  for entity_type, setting_name in pairs(entity_to_setting_map) do
    if get_upgrade_limit_level(setting_name) > 1 then
      if entity_type == "assembling-machine" or entity_type == "furnace" or entity_type == "rocket-silo"
        or entity_type == "turret" or entity_type == "ammo-turret" or entity_type == "electric-turret"
        or entity_type == "fluid-turret" or entity_type == "artillery-turret" then
        table.insert(primary_types, entity_type)
      else
        table.insert(secondary_types, entity_type)
      end
      table.insert(all_tracked_types, entity_type)
    end
  end

  return primary_types, secondary_types, all_tracked_types
end

local function build_and_store_config()
  if not storage.config then
    storage.config = {}
  end

  local primary_types, secondary_types, all_tracked_types = build_entity_type_lists()
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
    can_attempt_quality_change[entity_type] = get_upgrade_limit_level(setting_name) > 1
  end
  storage.config.can_attempt_quality_change = can_attempt_quality_change

  -- Max quality level each entity type will be raised to (limit of 1 = no upgrades)
  local upgrade_limit_levels = {}
  for entity_type, setting_name in pairs(entity_to_setting_map) do
    upgrade_limit_levels[entity_type] = get_upgrade_limit_level(setting_name)
  end
  storage.config.upgrade_limit_levels = upgrade_limit_levels

  local settings_data = {}
  settings_data.manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  settings_data.quality_increase_cost = settings.startup["quality-increase-cost"].value / 100
  settings_data.base_percentage_chance = settings.startup["percentage-chance-of-change"].value
  settings_data.accumulate_at_max_quality = settings.startup["accumulate-at-max-quality"].value
  settings_data.change_modules_with_entity = settings.startup["change-modules-with-entity"].value
  settings_data.turret_damage_per_manufacturing_hour = settings.startup["turret-damage-per-manufacturing-hour"].value
  settings_data.skip_hidden_qualities = settings.startup["quality_control_skip_hidden_qualities"].value
  settings_data.sticky_hidden_qualities = settings.startup["quality_control_hidden_qualities_sticky"].value

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

  local quality_limit = prototypes.quality["normal"]
  while quality_limit.next do
    quality_limit = quality_limit.next
  end
  storage.config.quality_limit = quality_limit

  storage.quality_multipliers = {}
  local current_quality = prototypes.quality["normal"]
  while current_quality do
    storage.quality_multipliers[current_quality.level] =
      settings_data.manufacturing_hours_for_change *
      (1 + settings_data.quality_increase_cost) ^ current_quality.level
    current_quality = current_quality.next
  end
end

local function setup_data_structures(force_reset)
  -- Handle force reset by clearing everything
  if force_reset then
    storage.quality_control_entities = {}
    storage.entity_list = {}
    storage.entity_list_index = {}
    storage.batch_index = 1
    storage.primary_entity_count = 0
    storage.secondary_entity_count = 0
    storage.accumulated_credits = 0
    storage.excluded_surfaces = {}
  end

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

  if not storage.aggregate_notifications then
    storage.aggregate_notifications = {
      accumulated_changes = {},
      last_notification_tick = 0
    }
  end

  if not storage.primary_entity_count then
    storage.primary_entity_count = 0
  end

  if not storage.secondary_entity_count then
    storage.secondary_entity_count = 0
  end

  if not storage.accumulated_credits then
    storage.accumulated_credits = 0
  end

  if not storage.quality_multipliers then
    storage.quality_multipliers = {}
  end

  if not storage.excluded_surfaces then
    storage.excluded_surfaces = {}
  end
end

-- Populate excluded_surfaces cache for all existing surfaces
local function populate_excluded_surfaces_cache()
  storage.excluded_surfaces = {}
  for _, surface in pairs(game.surfaces) do
    storage.excluded_surfaces[surface.index] = exclusions.should_exclude_surface(surface)
  end
end

local function reinitialize_quality_control_storage(command)
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  setup_data_structures(true)
  build_and_store_config()
  populate_excluded_surfaces_cache()
  core.initialize()
  core.scan_and_populate_entities()

  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Cache rebuild complete. All entities have been scanned.")
    end
  end
end


--- Registers the main processing loop based on the current setting
local function register_main_loop()
  -- on_nth_tick registrations are keyed by interval, so clear any existing
  -- registration first or the loop would run at both the old and new cadence
  script.on_nth_tick(nil)
  script.on_nth_tick(storage.ticks_between_batches, core.batch_process_entities)
end

local function register_event_handlers()
  -- Entity creation events (with player force filters for the events that support it)
  script.on_event(defines.events.on_built_entity, core.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_robot_built_entity, core.on_robot_built_entity, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_space_platform_built_entity, core.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_built, core.on_entity_created)
  script.on_event(defines.events.script_raised_revive, core.on_entity_created)
  script.on_event(defines.events.on_entity_cloned, core.on_entity_cloned)

  -- Entity destruction events (with player force filters for the events that support it)
  script.on_event(defines.events.on_player_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_robot_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_space_platform_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_entity_died, core.on_entity_destroyed, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_destroy, core.on_entity_destroyed)

  -- Quality control inspect shortcut
  script.on_event("quality-control-inspect-entity", function(event)
    local player = game.get_player(event.player_index)
    if player then
      notifications.show_entity_quality_info(
        player,
        core.get_entity_info
      )
    end
  end)

  -- Surface lifecycle events for exclusion cache
  script.on_event(defines.events.on_surface_created, exclusions.on_surface_created)
  script.on_event(defines.events.on_surface_deleted, exclusions.on_surface_deleted)
  script.on_event(defines.events.on_surface_renamed, exclusions.on_surface_renamed)
  script.on_event(defines.events.on_surface_imported, exclusions.on_surface_imported)

  -- Re-register the main loop when its tick interval is changed mid-game
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "batch-ticks-between-processing" then
      storage.ticks_between_batches = settings.global["batch-ticks-between-processing"].value
      register_main_loop()
    elseif limit_setting_migration_map[event.setting] or custom_upgrade_limit_settings[event.setting] then
      -- An upgrade limit (or a custom upgrade limit it may reference) changed;
      -- rebuild tracked entities and config
      reinitialize_quality_control_storage()
    end
  end)
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
-- The mod has full access to the game object and its storage table and can change anything about the game state that it deems appropriate at this stage.
-- no events will be raised for a mod it has finished on_init() or on_load()
script.on_init(function()
  setup_data_structures()
  build_and_store_config()
  populate_excluded_surfaces_cache()
  core.initialize()
  core.scan_and_populate_entities()
  storage.ticks_between_batches = settings.global["batch-ticks-between-processing"].value
  register_event_handlers()
  register_main_loop()
end)

-- Ran when settings change or mod version updates
script.on_configuration_changed(function(_)
  setup_data_structures()
  migrate_upgrade_limits_to_runtime_settings()
  reinitialize_quality_control_storage()
  storage.ticks_between_batches = settings.global["batch-ticks-between-processing"].value
  register_event_handlers()
  register_main_loop()
end)


-- Handle save game loading (on_load())
-- It gives the mod the opportunity to rectify potential differences in local state introduced by the save/load cycle.
-- Access to the game object is not available.
-- The storage table can be accessed and is safe to read from, but not write to, as doing so will lead to an error.
-- The only legitimate uses of this step are these:
-- - Re-setup metatables not registered with LuaBootstrap::register_metatable, as they are not persisted through the save/load cycle.
-- - Re-setup conditional event handlers, meaning subscribing to an event only when some condition is met to save processing time.
-- - Create local references to data stored in the storage table.
-- For all other purposes, LuaBootstrap::on_init, LuaBootstrap::on_configuration_changed, or migrations should be used instead.
-- no events will be raised for a mod it has finished on_init() or on_load()
-- storage is persisted between loaded games, but local variables that hook into storage need to be setup here
script.on_load(function()
  core.initialize()
  register_event_handlers()
  register_main_loop()
end)
