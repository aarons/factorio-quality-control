--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, configuration setup, and orchestrates core processing.
]]

local core = require("scripts.core")
local notifications = require("scripts.notifications")
local exclusions = require("scripts.exclusions")
local solar_productivity = require("scripts.compatibility.solar-productivity")

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
  ["lightning-attractor"] = "enable-lightning-rods",

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

local function build_entity_type_lists()
  local primary_types = {}
  local secondary_types = {}
  local all_tracked_types = {table.unpack(primary_entity_types)} -- always include primary types since they are the only ones to generate quality change events

  -- Build lists by checking individual entity type settings
  for entity_type, setting_name in pairs(entity_to_setting_map) do
    if settings.startup[setting_name].value then
      if entity_type == "assembling-machine" or entity_type == "furnace" then
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
    can_attempt_quality_change[entity_type] = settings.startup[setting_name].value
  end
  storage.config.can_attempt_quality_change = can_attempt_quality_change

  local settings_data = {}
  settings_data.manufacturing_hours_for_change = settings.startup["manufacturing-hours-for-change"].value
  settings_data.quality_increase_cost = settings.startup["quality-increase-cost"].value / 100
  settings_data.base_percentage_chance = settings.startup["percentage-chance-of-change"].value
  settings_data.accumulate_at_max_quality = settings.startup["accumulate-at-max-quality"].value
  settings_data.radar_growth_level_limit = settings.startup["radar-growth-level-limit"].value
  settings_data.lightning_attractor_growth_level_limit = settings.startup["lightning-attractor-growth-level-limit"].value
  settings_data.change_modules_with_entity = settings.startup["change-modules-with-entity"].value
  settings_data.skip_hidden_qualities = settings.startup["quality_control_skip_hidden_qualities"].value
  settings_data.sticky_hidden_qualities = settings.startup["quality_control_hidden_qualities_sticky"].value
  storage.config.mod_difficulty = settings.startup["mod-difficulty"].value

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
    storage.upgrade_queue = {}
    storage.upgrade_queue_index = 1
    storage.network_inventory = {}
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

  if not storage.network_inventory then
    storage.network_inventory = {}
  end

  if not storage.upgrade_queue then
    storage.upgrade_queue = {}
  end

  if not storage.upgrade_queue_index then
    storage.upgrade_queue_index = 1
  end

  if not storage.excluded_surfaces then
    storage.excluded_surfaces = {}
  end
end

-- Populate excluded_surfaces cache for all existing surfaces
local function populate_excluded_surfaces_cache()
  storage.excluded_surfaces = {}
  for _, surface in pairs(game.surfaces) do
    storage.excluded_surfaces[surface.index] = exclusions.evaluate_surface_exclusion(surface)
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
  local tick_interval = storage.ticks_between_batches
  script.on_nth_tick(tick_interval, core.batch_process_entities)
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

  -- Initialize compatibility modules
  solar_productivity.initialize()
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
