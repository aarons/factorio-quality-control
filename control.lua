--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, and orchestrates the modular components.
]]

-- Import modules
local data_setup = require("scripts.data-setup")
local core = require("scripts.core")

-- Module state (initialized by initialize_module_state function)
local all_tracked_types
local is_tracked_type
local settings_data
local previous_qualities
local quality_limit

--- Initialize module state variables (called from on_init and on_load)
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
  -- Notify player that rebuild is starting
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  -- Full reinitialization: setup data structures and rescan entities
  data_setup.setup_data_structures(true)  -- Clear existing data
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)
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

  -- Save the tick interval in storage for multiplayer consistency
  if storage then
    storage.quality_control_saved_tick_interval = tick_interval
  end

  script.on_nth_tick(nil)
  script.on_nth_tick(tick_interval, core.batch_process_entities)
end

--- Initialize all event handlers
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
      if storage.quality_control_data_structures_ready then
        register_main_loop()
      end
    end
  end)

  -- Start the main processing loop
  -- Use saved tick interval if available (for on_load), otherwise use current setting
  local tick_interval = (storage and storage.quality_control_saved_tick_interval) or settings.global["batch-ticks-between-processing"].value
  script.on_nth_tick(tick_interval, core.batch_process_entities)
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
script.on_init(function()
  initialize_module_state()
  data_setup.setup_data_structures()
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)
  core.scan_and_populate_entities(all_tracked_types)

  -- Save the initial tick interval and mark storage as ready
  storage.quality_control_saved_tick_interval = settings.global["batch-ticks-between-processing"].value
  storage.quality_control_data_structures_ready = true

  register_event_handlers()
end)

-- Handle startup setting changes and mod version updates
script.on_configuration_changed(function(_)
  initialize_module_state()
  reinitialize_quality_control_storage()

  -- Save the tick interval and mark storage as ready
  storage.quality_control_saved_tick_interval = settings.global["batch-ticks-between-processing"].value
  storage.quality_control_data_structures_ready = true

  register_event_handlers()
end)

-- Handle save game loading
-- Must immediately re-register the same event handlers that were registered when saved
-- to prevent multiplayer desync issues
script.on_load(function()
  -- Re-initialize module state variables (not persisted between save/load)
  initialize_module_state()

  -- Initialize core module with read-only storage access
  core.initialize(settings_data, is_tracked_type, previous_qualities, quality_limit)

  -- Re-register all event handlers immediately (required for multiplayer compatibility)
  register_event_handlers()
end)
