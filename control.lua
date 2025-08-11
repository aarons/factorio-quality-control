--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, and orchestrates the modular components.
]]

-- Import modules
local data_setup = require("scripts.data-setup")
local core = require("scripts.core")

-- Module state
local _, _, all_tracked_types = data_setup.build_entity_type_lists()
local is_tracked_type = data_setup.build_is_tracked_type_lookup()
local settings_data = data_setup.parse_settings()
local previous_qualities = data_setup.build_previous_quality_lookup()


--- Console command to reinitialize storage
local function reinitialize_quality_control_storage(command)
  -- Notify player that rebuild is starting
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  -- Full reinitialization: setup data structures and rescan entities
  data_setup.setup_data_structures(true)  -- Clear existing data
  core.initialize(settings_data, is_tracked_type, previous_qualities)
  core.scan_and_populate_entities(all_tracked_types)

  -- Notify player that rebuild is complete
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
  script.on_nth_tick(nil)
  script.on_nth_tick(tick_interval, core.batch_process_entities)
end

--- Initialize all event handlers
local function register_event_handlers()
  -- Entity creation events
  script.on_event(defines.events.on_built_entity, core.on_entity_created)
  script.on_event(defines.events.on_robot_built_entity, core.on_entity_created)
  script.on_event(defines.events.on_space_platform_built_entity, core.on_entity_created)
  script.on_event(defines.events.script_raised_built, core.on_entity_created)
  script.on_event(defines.events.script_raised_revive, core.on_entity_created)
  script.on_event(defines.events.on_entity_cloned, core.on_entity_created)

  -- Entity destruction events
  script.on_event(defines.events.on_player_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_robot_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_space_platform_mined_entity, core.on_entity_destroyed)
  script.on_event(defines.events.on_entity_died, core.on_entity_destroyed)
  script.on_event(defines.events.script_raised_destroy, core.on_entity_destroyed)

  -- Quality control inspect shortcut
  script.on_event("quality-control-inspect-entity", core.on_quality_control_inspect)

  -- Runtime setting changes
  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "batch-ticks-between-processing" then
      if storage.batch_processing_initialized then
        register_main_loop()
      end
    end
  end)

  -- Start the main processing loop
  register_main_loop()
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
script.on_init(function()
  data_setup.setup_data_structures()
  core.initialize(settings_data, is_tracked_type, previous_qualities)
  core.scan_and_populate_entities(all_tracked_types)
  register_event_handlers()
end)

-- Handle startup setting changes and mod version updates
script.on_configuration_changed(function(event)
  reinitialize_quality_control_storage()
  storage.batch_processing_initialized = false
  register_event_handlers()
end)

-- Handle save game loading
-- Uses delayed initialization pattern because on_load has restrictions:
-- - No access to game object
-- - Storage table is read-only
-- - Can only set up metatables and event handlers
-- The one-tick delay ensures full game access when initializing
script.on_load(function()
  script.on_nth_tick(60, function()
    script.on_nth_tick(nil)  -- Unregister to run only once
    data_setup.setup_data_structures()
    core.initialize(settings_data, is_tracked_type, previous_qualities)
    register_event_handlers()
  end)
end)
