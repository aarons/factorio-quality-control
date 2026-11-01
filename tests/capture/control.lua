-- A graphical photo stage, separate from the headless progression tests.
-- These are staged results passed to production notifications, not earned upgrades.
-- luacheck: globals game
local config = require("capture_config")
local interval = config.settle_ticks + config.last_tick + 60

script.on_init(function()
  local surface = game.create_surface("qc-photo-stage", {width = 128, height = 128,
    autoplace_settings = {entity = {treat_missing_as_default = false},
      tile = {treat_missing_as_default = false}, decorative = {treat_missing_as_default = false}}})
  surface.request_to_generate_chunks({0, 0}, 2)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities()) do entity.destroy() end
  surface.destroy_decoratives{}
  local tiles = {}
  for x = -40, 40 do
    for y = -30, 30 do
      tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}}
    end
  end
  surface.set_tiles(tiles)
  surface.daytime = 0
  surface.freeze_daytime = true
  local power = surface.create_entity{name = "electric-energy-interface", position = {0, 14}, force = "player"}
  power.electric_buffer_size = 1000000000
  power.power_production = 1000000000
  surface.create_entity{name = "substation", position = {0, 10}, force = "player"}
  game.forces.player.chart(surface, {{-40, -30}, {40, 30}})
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  local character = player.character
  player.set_controller{type = defines.controllers.god}
  if character and character.valid then character.destroy() end
  player.teleport({0, -1.5}, game.surfaces["qc-photo-stage"])
  player.zoom = config.zoom
  for _, name in ipairs({"show_controller_gui", "show_minimap", "show_research_info", "show_alert_gui",
    "show_side_menu", "show_pins_gui", "show_entity_tooltip", "show_quickbar", "show_shortcut_bar",
    "show_crafting_queue", "show_tool_bar", "show_hotkey_suggestions", "update_entity_selection"}) do
    player.game_view_settings[name] = false
  end
  player.clear_console()
  storage.player_index = player.index
  storage.start_tick = game.tick + 120
end)

local function screenshot(player, case, age, sequence)
  local directory = sequence and "sequence" or "stills"
  local frame = sequence and math.floor(age / config.frame_step) or age
  -- Center on the actual entity position (placement may snap it to the grid).
  -- At this zoom, one tile spans 32 * zoom pixels. Leave 30% below the entity.
  local subject_position = storage.subject.position
  local camera_y = subject_position.y - (config.entity_height - 0.5) * config.resolution[2] / (32 * config.zoom)
  game.take_screenshot{
    player = player, surface = player.surface, position = {subject_position.x, camera_y},
    resolution = config.resolution, zoom = config.zoom,
    path = "qc-effects/" .. case.style .. "/" .. directory .. "/" .. string.format("%04d.png", frame),
    show_gui = false, show_entity_info = true, anti_alias = true,
    hide_clouds = true, hide_fog = true, daytime = 0, force_render = true,
  }
end

script.on_event(defines.events.on_tick, function()
  if not storage.start_tick or storage.done then return end
  local elapsed = game.tick - storage.start_tick
  if elapsed < 0 then return end
  local index = math.floor(elapsed / interval) + 1
  local case = config.cases[index]
  if not case then
    game.set_wait_for_screenshots_to_finish()
    storage.done = true
    game.tick_paused = true
    log("QC_CAPTURE DONE")
    return
  end
  local player = game.get_player(storage.player_index)
  local scene_age = elapsed % interval
  if scene_age == 0 then
    if storage.subject and storage.subject.valid then storage.subject.destroy() end
    storage.subject = assert(player.surface.create_entity{
      name = case.entity, quality = case.module and case.quality or case.before_quality,
      position = {0, 0}, force = player.force,
    })
    if case.module then
      assert(storage.subject.get_module_inventory().insert{
        name = case.module, quality = case.before_quality, count = 1,
      } == 1)
    end
  end
  -- Keep placement dust outside both the stills and the recorded timeline.
  local age = scene_age - config.settle_ticks
  if age < 0 then return end
  if age == 0 then
    screenshot(player, case, 0, false)
  elseif age == config.lead_in_ticks then
    if case.module then
      -- Only the module upgrades; the beacon keeps its existing quality.
      local inventory = storage.subject.get_module_inventory()
      inventory.clear()
      assert(inventory.insert{name = case.module, quality = case.quality, count = 1} == 1)
    else
      -- Entity quality is read-only, so stage the upgrade by replacing the unit.
      local position = storage.subject.position
      storage.subject.destroy()
      storage.subject = assert(player.surface.create_entity{
        name = case.entity, quality = case.quality, position = position, force = player.force,
      })
    end
    remote.call("qc-capture", "show", player, storage.subject, case.style, case.module)
  end
  for _, tick in ipairs(case.stills) do
    if age == config.lead_in_ticks + tick then screenshot(player, case, age, false) end
  end
  if config.frame_step > 0 and age % config.frame_step == 0 and age <= config.last_tick then
    screenshot(player, case, age, true)
  end
end)
