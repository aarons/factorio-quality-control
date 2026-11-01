-- luacheck: globals game math defines rendering package
local notifications = require("scripts.notifications")
local celebrations = require("scripts.celebrations")
local tests = {}
local styles = {"entity-alerts", "chat", "gps", "floating-text", "halo", "rainbow", "badge", "bubbles", "sound", "aggregate-alerts"}
local objects = {}
local players = {}
local force = {index = 1}
local other_force = {index = 2}
local entity

local function key(style) return "quality-change-" .. style .. "-enabled" end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local function enable(player, style, value) player.preferences[key(style)].value = value ~= false end

local function reset()
  objects, players = {}, {}
  storage = {aggregate_notifications = {accumulated_changes = {}, last_notification_tick = 0}}
  defines = {print_sound = {never = 0}, print_skip = {never = 0}}
  prototypes = {
    quality = {custom = {name = "custom", color = {r = 0.2, g = 0.8, b = 0.7}, localised_name = {"quality-name.custom"}}},
    item = {module = {localised_name = {"item-name.module"}}},
  }
  entity = {valid = true, name = "beacon", localised_name = {"entity-name.beacon"},
    force = force, surface = {index = 2, name = "other-surface"}, position = {x = 3, y = 7},
    gps_tag = "[gps=3,7,other-surface]"}
  for index = 1, 3 do
    local player = {index = index, valid = true, connected = true, force = index == 3 and other_force or force,
      surface = entity.surface, physical_surface = entity.surface,
      preferences = {}, messages = {}, alerts = {}, texts = {}, sounds = {}}
    for _, style in ipairs(styles) do player.preferences[key(style)] = {value = false} end
    player.preferences["quality-change-sound"] = {value = "instrument-piano"}
    player.preferences["quality-change-sound-note"] = {value = 23}
    player.preferences["quality-change-sound-mode"] = {value = "fixed"}
    player.preferences["quality-change-sound-scale"] = {value = "major"}
    player.preferences["quality-change-sound-range"] = {value = "one-octave"}
    player.print = function(message, options) table.insert(player.messages, {message = message, options = options}) end
    player.add_custom_alert = function(target, icon, message)
      table.insert(player.alerts, {entity = target, icon = icon, message = message})
    end
    player.create_local_flying_text = function(spec) table.insert(player.texts, spec) end
    player.play_sound = function(spec) table.insert(player.sounds, spec) end
    players[index] = player
  end
  game = {tick = 0, connected_players = players, forces = {player = force}, get_player = function(index) return players[index] end}
  settings = {get_player_settings = function(player) return player.preferences end}
  local function draw(spec)
    equal(#spec.players, 1)
    assert(spec.time_to_live > 0 and spec.time_to_live <= 270)
    local object = {valid = true, spec = spec, radius = spec.radius}
    object.destroy = function() object.valid = false end
    table.insert(objects, object)
    return object
  end
  rendering = {draw_circle = draw, draw_sprite = draw}
  math.random = function() error("cosmetics must not consume gameplay randomness") end
end

function tests.independent()
  for _, style in ipairs(styles) do
    if style ~= "aggregate-alerts" then
      reset()
      enable(players[2], style)
      notifications.show_entity_quality_alert(entity, "custom")
      local player = players[2]
      equal(#player.alerts, style == "entity-alerts" and 1 or 0)
      equal(#player.messages, (style == "chat" or style == "gps") and 1 or 0)
      equal(#player.texts, style == "floating-text" and 1 or 0)
      equal(#player.sounds, style == "sound" and 1 or 0)
      equal(#objects, style == "rainbow" and 3 or (style == "bubbles" and 18 or ((style == "halo" or style == "badge") and 1 or 0)))
      equal(#players[1].alerts + #players[1].messages + #players[1].sounds + #players[1].texts, 0)
      for _, object in ipairs(objects) do equal(object.spec.players[1], 2) end
      if style == "gps" then equal(player.messages[1].message, entity.gps_tag) end
      if style == "floating-text" then equal(player.texts[1].surface, entity.surface) end
    end
  end
end

function tests.chat_and_gps()
  for _, module_name in ipairs({false, "module"}) do
    for _, chat in ipairs({false, true}) do
      for _, gps in ipairs({false, true}) do
        reset()
        local player = players[1]
        enable(player, "chat", chat)
        enable(player, "gps", gps)
        if module_name then
          notifications.show_module_quality_alert(entity, module_name, "custom")
        else
          notifications.show_entity_quality_alert(entity, "custom")
        end
        equal(#player.messages, (chat or gps) and 1 or 0)
        if chat or gps then
          local printed = player.messages[1]
          equal(printed.options.sound, defines.print_sound.never)
          equal(printed.options.skip, defines.print_skip.never)
          if chat then
            local message = printed.message
            if gps then
              equal(message[4], entity.gps_tag)
              message = message[2]
            end
            equal(message[1], module_name and "quality-control.module-upgraded" or "quality-control.entity-upgraded")
            equal(message[2][2], "[" .. (module_name and "item=module" or "entity=beacon") .. ",quality=custom] ")
          else
            equal(printed.message, entity.gps_tag)
          end
        end
      end
    end
  end
end

function tests.sound_surface()
  for _, module_name in ipairs({false, "module"}) do
    reset()
    local other_surface = {index = 1, name = "nauvis"}
    local player = players[1]
    local function upgrade()
      if module_name then
        notifications.show_module_quality_alert(entity, module_name, "custom")
      else
        notifications.show_entity_quality_alert(entity, "custom")
      end
    end
    enable(player, "sound")
    -- Each player chooses their own sound independently of other styles.
    enable(players[2], "sound")
    players[2].preferences["quality-change-sound"].value = "confirm"
    for _, sound in ipairs({"research_completed", "achievement_unlocked", "new_objective", "console_message", "confirm"}) do
      player.preferences["quality-change-sound"].value = sound
      player.sounds, players[2].sounds = {}, {}
      upgrade()
      equal(#player.sounds, 1)
      equal(player.sounds[1].path, "utility/" .. sound)
      equal(players[2].sounds[1].path, "utility/confirm")
      equal(#player.messages + #player.alerts + #player.texts, 0)
    end
    player.sounds = {}
    player.surface = other_surface -- Remote view away from the character's surface.
    upgrade()
    equal(#player.sounds, 0)
    player.physical_surface = other_surface -- Physically away as well.
    upgrade()
    equal(#player.sounds, 0)
    player.surface = entity.surface -- Remote view back to the upgrade surface.
    upgrade()
    equal(#player.sounds, 1)
    player.sounds = {}
    enable(player, "sound", false)
    upgrade()
    equal(#player.sounds, 0)
  end
end

function tests.speaker_sounds()
  reset()
  local player = players[1]
  enable(player, "sound")
  for _, case in ipairs({
    {"alarms-ring", 20, "quality-control-upgrade-alarms-ring"},
    {"drum-kit-cowbell", 48, "quality-control-upgrade-drum-kit-cowbell"},
    {"instrument-piano", 1, "quality-control-upgrade-instrument-piano-1"},
    {"instrument-piano", 48, "quality-control-upgrade-instrument-piano-48"},
    {"instrument-steel-drum", 20, "quality-control-upgrade-instrument-steel-drum-20"},
    {"instrument-bass", 48, "quality-control-upgrade-instrument-bass-36"},
    {"confirm", 48, "utility/confirm"},
  }) do
    player.preferences["quality-change-sound"].value = case[1]
    player.preferences["quality-change-sound-note"].value = case[2]
    player.sounds = {}
    notifications.show_module_quality_alert(entity, "module", "custom")
    equal(#player.sounds, 1)
    equal(player.sounds[1].path, case[3])
    equal(#players[2].sounds, 0)
  end
  player.sounds = {}
  player.preferences["quality-change-sound"].value = "instrument-piano"
  player.surface = {index = 1}
  notifications.show_entity_quality_alert(entity, "custom")
  equal(#player.sounds, 0)
end

function tests.music_surface()
  reset()
  local player = players[1]
  player.preferences["quality-change-sound-mode"].value = "staircase"
  player.preferences["quality-change-sound-note"].value = 8
  enable(player, "sound")
  notifications.show_entity_quality_alert(entity, "custom")
  equal(player.sounds[1].path, "quality-control-upgrade-instrument-piano-8")
  player.surface = {index = 1}
  notifications.show_module_quality_alert(entity, "module", "custom")
  player.surface = entity.surface
  enable(player, "sound", false)
  notifications.show_entity_quality_alert(entity, "custom")
  enable(player, "sound")
  player.force = other_force
  notifications.show_entity_quality_alert(entity, "custom")
  player.force = force
  equal(#player.sounds, 1)
  notifications.show_module_quality_alert(entity, "module", "custom")
  equal(#player.sounds, 2)
  equal(player.sounds[2].path, "quality-control-upgrade-instrument-piano-10")
  equal(storage.upgrade_music[2], nil)
end

function tests.recipients()
  reset()
  for _, player in ipairs(players) do for _, style in ipairs(styles) do enable(player, style) end end
  notifications.show_module_quality_alert(entity, "module", "custom")
  equal(#objects, 46)
  for index = 1, 2 do
    local player = players[index]
    equal(#player.messages, 1)
    equal(#player.sounds, 1)
    equal(#player.texts, 1)
    equal(player.alerts[1].icon.type, "item")
    equal(player.alerts[1].icon.quality, "custom")
    equal(player.alerts[1].message[1], "quality-control.module-upgraded")
  end
  equal(#players[3].messages + #players[3].sounds + #players[3].texts + #players[3].alerts, 0)
  game.tick = 18000
  notifications.show_quality_notifications({beacon = 2}, {module = 3})
  equal(#players[1].messages, 4)
  equal(#players[2].messages, 4)
  equal(#players[3].messages, 0)
  game.connected_players = {}
  notifications.show_entity_quality_alert(entity, "custom")
  equal(#objects, 46)
end

function tests.lifecycle()
  reset()
  for _, style in ipairs({"halo", "rainbow", "badge", "bubbles"}) do enable(players[1], style) end
  notifications.show_entity_quality_alert(entity, "custom")
  entity.valid = false
  entity.position.x = 100 -- Rendering stays at the captured upgrade location.
  game.tick = 30
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 23)
  equal(objects[5].target[1], 3)
  assert(objects[1].radius > 0.5 and objects[1].color.a < 1)
  -- Reload the module while retaining serialized storage, as Factorio does.
  package.loaded["scripts.celebrations"] = nil
  celebrations = require("scripts.celebrations")
  enable(players[1], "rainbow", false)
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 20)
  objects[1].valid = false -- e.g. the surface was deleted by the engine.
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 19)
  players[1].connected = false
  celebrations.on_tick()
  equal(storage.quality_celebrations, nil)
  equal(objects[5].valid, false)

  reset()
  enable(players[1], "halo")
  notifications.show_entity_quality_alert(entity, "custom")
  players[1].force = other_force
  celebrations.on_tick()
  equal(storage.quality_celebrations, nil)
end

function tests.badge_animation()
  reset()
  enable(players[1], "badge")
  enable(players[1], "bubbles")
  notifications.show_entity_quality_alert(entity, "custom")
  local badge = objects[1]
  equal(badge.spec.time_to_live, 270)
  for _, object in ipairs(objects) do equal(object.spec.sprite, "quality/custom") end
  celebrations.on_tick()
  equal(badge.color.a, 1)
  for index = 2, #objects do equal(objects[index].color.a, 0) end

  game.tick = 24
  celebrations.on_tick()
  assert(objects[2].color.a > 0)
  equal(objects[#objects].color.a, 0) -- Later bubbles have not been released yet.
  local first_bubble_y = objects[2].target[2]
  game.tick = 60
  celebrations.on_tick()
  assert(objects[2].target[2] < first_bubble_y)
  assert(objects[2].target[1] ~= objects[3].target[1])
  assert(objects[2].x_scale < badge.x_scale)

  game.tick = 189 -- The full-size badge remains fully visible before fading.
  celebrations.on_tick()
  equal(badge.x_scale, badge.spec.x_scale * 2.5)
  equal(badge.y_scale, badge.x_scale)
  local orientation_before_fade = badge.orientation
  equal(badge.color.a, 1)
  game.tick = 240
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 1)
  assert(badge.color.a > 0 and badge.color.a < 1)
  assert(badge.orientation > orientation_before_fade)
  local orientation_during_fade = badge.orientation
  game.tick = 269
  celebrations.on_tick()
  assert(badge.orientation > orientation_during_fade)
  assert(badge.color.a > 0)
  game.tick = 270
  celebrations.on_tick()
  equal(storage.quality_celebrations, nil)
  for _, object in ipairs(objects) do equal(object.valid, false) end

  for _, disabled_style in ipairs({"badge", "bubbles"}) do
    reset()
    enable(players[1], "badge")
    enable(players[1], "bubbles")
    notifications.show_entity_quality_alert(entity, "custom")
    enable(players[1], disabled_style, false)
    celebrations.on_tick() -- Each toggle removes only its own effects, including delayed bubbles.
    equal(#storage.quality_celebrations, disabled_style == "badge" and 18 or 1)
    equal(objects[1].valid, disabled_style ~= "badge")
    for index = 2, #objects do equal(objects[index].valid, disabled_style ~= "bubbles") end
    enable(players[1], "badge", false)
    enable(players[1], "bubbles", false)
    celebrations.on_tick()
    equal(storage.quality_celebrations, nil)
  end
end

function tests.legacy_effect()
  reset()
  enable(players[1], "badge")
  notifications.show_entity_quality_alert(entity, "custom")
  local effect = storage.quality_celebrations[1]
  effect.duration = nil -- A badge already in flight in a save from the previous version.
  storage.quality_celebrations = {effect}
  game.tick = 89
  celebrations.on_tick()
  equal(effect.object.valid, true)
  game.tick = 90
  celebrations.on_tick()
  equal(effect.object.valid, false)
  equal(storage.quality_celebrations, nil)
end

function tests.burst()
  reset()
  for _, style in ipairs(styles) do enable(players[1], style) end
  for _ = 1, 100 do notifications.show_entity_quality_alert(entity, "custom") end
  equal(#objects, 2300)
  equal(#players[1].sounds, 100)
  equal(#players[1].messages, 100)
  game.tick = 89
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 2300)
  game.tick = 90
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 1900)
  game.tick = 269
  celebrations.on_tick()
  equal(#storage.quality_celebrations, 100)
  game.tick = 270
  celebrations.on_tick()
  equal(storage.quality_celebrations, nil)
  for _, object in ipairs(objects) do equal(object.valid, false) end
end

assert(tests[arg[1]], "unknown scenario")()
