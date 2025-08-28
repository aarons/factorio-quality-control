--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, and orchestrates the modular components.
]]

local config = require("scripts.config")
local entity_tracker = require("scripts.entity-tracker")
local quality_processor = require("scripts.quality-processor")
local credits = require("scripts.credits")
local orchestrator = require("scripts.orchestrator")
local notifications = require("scripts.notifications")

local function reinitialize_quality_control_storage(command)
  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Rebuilding cache, scanning entities...")
    end
  end

  config.setup_data_structures(true)
  config.build_and_store_config()
  entity_tracker.initialize()
  quality_processor.initialize()
  credits.initialize()
  orchestrator.initialize()
  entity_tracker.scan_and_populate_entities(storage.config.all_tracked_types)

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
  script.on_nth_tick(tick_interval, function()
    orchestrator.batch_process_entities(entity_tracker, credits, quality_processor)
  end)
end

local function register_event_handlers()
  -- Entity creation events (with player force filter where supported)
  script.on_event(defines.events.on_built_entity, entity_tracker.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_robot_built_entity, entity_tracker.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_space_platform_built_entity, entity_tracker.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_built, entity_tracker.on_entity_created)
  script.on_event(defines.events.script_raised_revive, entity_tracker.on_entity_created)
  script.on_event(defines.events.on_entity_cloned, entity_tracker.on_entity_cloned)

  -- Entity destruction events (with player force filter where supported)
  script.on_event(defines.events.on_player_mined_entity, entity_tracker.on_entity_destroyed)
  script.on_event(defines.events.on_robot_mined_entity, entity_tracker.on_entity_destroyed)
  script.on_event(defines.events.on_space_platform_mined_entity, entity_tracker.on_entity_destroyed)
  script.on_event(defines.events.on_entity_died, entity_tracker.on_entity_destroyed, {{filter = "force", force = "player"}})
  script.on_event(defines.events.script_raised_destroy, entity_tracker.on_entity_destroyed)

  -- Quality control inspect shortcut
  script.on_event("quality-control-inspect-entity", function(event)
    local player = game.get_player(event.player_index)
    if player then
      notifications.show_entity_quality_info(
        player,
        storage.config.is_tracked_type,
        entity_tracker.get_entity_info,
        storage.config.settings_data.manufacturing_hours_for_change,
        storage.config.settings_data.quality_increase_cost,
        storage.config.can_attempt_quality_change
      )
    end
  end)
end

-- Register console command
commands.add_command("quality-control-init", "Reinitialize Quality Control storage and rescan all machines", reinitialize_quality_control_storage)

-- Initialize on new game
-- The mod has full access to the game object and its storage table and can change anything about the game state that it deems appropriate at this stage.
-- no events will be raised for a mod it has finished on_init() or on_load()
script.on_init(function()
  config.setup_data_structures()
  config.build_and_store_config()
  entity_tracker.initialize()
  quality_processor.initialize()
  credits.initialize()
  orchestrator.initialize()
  entity_tracker.scan_and_populate_entities(storage.config.all_tracked_types)
  storage.ticks_between_batches = settings.global["batch-ticks-between-processing"].value
  register_event_handlers()
  register_main_loop()
end)

-- Handle startup setting changes and mod version updates
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
  entity_tracker.initialize()
  quality_processor.initialize()
  credits.initialize()
  orchestrator.initialize()
  register_event_handlers()
  register_main_loop()
end)
