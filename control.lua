--[[
control.lua

Main entry point for the Quality Control mod.
Handles initialization, event registration, and orchestrates the modular components.
]]

local config = require("scripts.config")
local entity_tracker = require("scripts.entity-tracker")
local upgrade_manager = require("scripts.upgrade-manager")
local notifications = require("scripts.notifications")
local inventory = require("scripts.inventory")

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
  upgrade_manager.initialize()
  entity_tracker.scan_and_populate_entities(storage.config.all_tracked_types)

  if command and command.player_index then
    local player = game.get_player(command.player_index)
    if player then
      player.print("Quality Control: Cache rebuild complete. All entities have been scanned.")
    end
  end
end

local function batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  local batch_index = storage.batch_index
  local entity_list = storage.entity_list
  local tracked_entities = storage.quality_control_entities
  local settings_data = storage.config.settings_data

  while entities_processed < batch_size do
    if batch_index > #entity_list then
      batch_index = 1
      inventory.cleanup_pending_upgrades()
      break
    end

    local unit_number = entity_list[batch_index]
    batch_index = batch_index + 1

    local entity_info = tracked_entities[unit_number]
    local should_stay_tracked = entity_info and entity_info.can_change_quality or
      (entity_info and entity_info.is_primary and settings_data.accumulate_at_max_quality)

    if not entity_info or not entity_info.entity or not entity_info.entity.valid or not should_stay_tracked then
      entity_tracker.remove_entity_info(unit_number)
      goto continue
    end

    local entity = entity_info.entity

    if entity.to_be_deconstructed() then
      goto continue
    end

    if entity.to_be_upgraded() then
      goto continue
    end

    if entity_info.is_primary then
      local credit_result = upgrade_manager.process_primary_entity(entity_info, entity)
      if credit_result then
        local successful_changes = 0
        if credit_result.should_attempt_quality_change then
          successful_changes = upgrade_manager.process_quality_attempts(entity, credit_result.thresholds_passed, quality_changes, entity_tracker)
        end

        if successful_changes == 0 then
          upgrade_manager.update_manufacturing_hours(entity_info, credit_result.current_hours)
        end
      end
    else
      local secondary_result = upgrade_manager.process_secondary_entity()
      if secondary_result then
        upgrade_manager.process_quality_attempts(entity, secondary_result.total_attempts, quality_changes, entity_tracker)
      end
    end

    entities_processed = entities_processed + 1
    ::continue::
  end

  storage.batch_index = batch_index

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes)
  end
end

--- Registers the main processing loop based on the current setting
local function register_main_loop()
  local tick_interval = storage.ticks_between_batches
  script.on_nth_tick(tick_interval, batch_process_entities)
end

local function register_event_handlers()
  -- Entity creation events (with player force filter where supported)
  script.on_event(defines.events.on_built_entity, entity_tracker.on_entity_created, {{filter = "force", force = "player"}})
  script.on_event(defines.events.on_robot_built_entity, entity_tracker.on_robot_built_entity, {{filter = "force", force = "player"}})
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

  -- Upgrade tracking events
  script.on_event(defines.events.on_marked_for_upgrade, inventory.on_marked_for_upgrade)
  script.on_event(defines.events.on_cancelled_upgrade, inventory.on_cancelled_upgrade)

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
  upgrade_manager.initialize()
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
  upgrade_manager.initialize()
  register_event_handlers()
  register_main_loop()
end)
