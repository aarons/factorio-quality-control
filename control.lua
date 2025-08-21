--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, and orchestrates the modular components.
]]

local data_setup = require("scripts.data-setup")
local core = require("scripts.core")

local all_tracked_types
local is_tracked_type
local settings_data
local previous_qualities
local quality_limit

local function initialize_module_state()
  local _, _, tracked_types = data_setup.build_entity_type_lists()
  all_tracked_types = tracked_types
  is_tracked_type = data_setup.build_is_tracked_type_lookup()
  settings_data = data_setup.parse_settings()
  previous_qualities = data_setup.build_previous_quality_lookup()
  quality_limit = data_setup.get_quality_limit(settings_data.quality_change_direction)
end

--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  data_setup.setup_data_structures(true)
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)
  core.scan_and_populate_entities(all_tracked_types)

  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Cache rebuild complete. All entities have been scanned.")
    end
  end
end

--- Registers the main processing loop based on the current setting
local function register_main_loop()
  local tick_interval = settings.global["batch-ticks-between-processing"].value

  -- save the tick interval for multiplayer consistency
  -- it may not be necessary, should look into removing
  if storage then
    storage.saved_tick_interval = tick_interval
  end

  script.on_nth_tick(tick_interval, core.batch_process_entities)
end

local function register_event_handlers()
  -- Entity creation events (with player force filter where supported)
  script.on_event(defines.events.on_built_entity, core.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_robot_built_entity, core.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_space_platform_built_entity, core.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_built, core.on_entity_created)
  script.on_event(defines.events.script_raised_revive, core.on_entity_created)
  script.on_event(defines.events.on_entity_cloned, core.on_entity_cloned)

  -- Entity destruction events (with player force filter where supported)
  script.on_event(defines.events.on_player_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_robot_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_space_platform_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_entity_died, core.on_entity_destroyed, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_destroy, core.on_entity_destroyed)

  -- Quality control inspect shortcut
  script.on_event("quality-control-inspect-entity", core.on_quality_control_inspect)

  -- Runtime setting changes
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "batch-ticks-between-processing" then
      if storage.data_structures_ready then
        register_main_loop()
      end
    end
  end)

  -- Start the main processing loop
  -- Use saved tick interval if available (for on_load), otherwise use current setting
  local tick_interval = (storage and storage.saved_tick_interval) or settings.global["batch-ticks-between-processing"].value
  script.on_nth_tick(tick_interval, core.batch_process_entities)
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
-- The mod has full access to the game object and its storage table and can change anything about the game state that it deems appropriate at this stage.
-- no events will be raised for a mod it has finished on_init() or on_load()
script.on_init(function()
  initialize_module_state()
  data_setup.setup_data_structures()
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)
  core.scan_and_populate_entities(all_tracked_types)

  -- Save the initial tick interval and mark storage as ready
  storage.saved_tick_interval = settings.global["batch-ticks-between-processing"].value
  storage.data_structures_ready = true

  register_event_handlers()
end)

-- Handle startup setting changes and mod version updates
script.on_configuration_changed(function(_)
  initialize_module_state()
  reinitialize_quality_control_storage()

  -- Save the tick interval and mark storage as ready
  storage.saved_tick_interval = settings.global["batch-ticks-between-processing"].value
  storage.data_structures_ready = true

  register_event_handlers()
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
  -- Re-initialize module state variables (not persisted between save/load)
  initialize_module_state()

  -- Initialize core module with read-only storage access
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)

  -- Re-register all event handlers immediately (required for multiplayer compatibility)
  register_event_handlers()
end)
