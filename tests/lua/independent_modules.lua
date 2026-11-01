-- Engine globals and randomness are replaced only in this isolated test process.
-- luacheck: globals game math
local core = require("scripts.core")
local module_upgrades = require("scripts.module_upgrades")
local notifications = require("scripts.notifications")

local tests = {}
local next_id = 0
local random_calls = 0
local roll = 0.99
local alerts = {}
local printed = {}

local function equal(actual, expected)
  assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function reset(mode)
  next_id, random_calls, roll = 0, 0, 0.99
  alerts, printed = {}, {}
  prototypes = {quality = {}, item = {["speed-module"] = {localised_name = "Speed module"}}, get_history = function() return nil end}
  local previous
  for level, name in ipairs({"normal", "uncommon", "rare", "epic", "legendary"}) do
    local quality = {name = name, level = level - 1, localised_name = name, chain_probability = 0.1, color = {r = 1, g = 1, b = 1}}
    prototypes.quality[name] = quality
    if previous then previous.next = quality end
    previous = quality
  end
  local config = {
    change_modules_with_entity = mode or "independent", base_percentage_chance = 1,
    accumulation_percentage = 100, turrets_contribute_credits = false,
    crafting_speed_affects_progression = true, turret_damage_per_manufacturing_hour = 36000,
    skip_hidden_qualities = false, sticky_hidden_qualities = true,
  }
  storage = {
    quality_control_entities = {}, entity_list = {}, entity_list_index = {}, batch_index = 1,
    surface_meters = {}, surface_primary_counts = {}, excluded_surfaces = {},
    primary_entity_count = 0, secondary_entity_count = 0,
    aggregate_notifications = {accumulated_changes = {}, last_notification_tick = 0},
    quality_multipliers = {[0] = 1, 1, 1, 1, 1},
    config = {settings_data = config, is_tracked_type = {}, can_attempt_quality_change = {}, upgrade_limit_levels = {}},
  }
  for _, kind in ipairs({"beacon", "lab", "assembling-machine", "electric-pole"}) do
    storage.config.is_tracked_type[kind] = true
    storage.config.can_attempt_quality_change[kind] = true
    storage.config.upgrade_limit_levels[kind] = 999
  end
  settings = {
    global = {["secondary-progression-rate"] = {value = 100}, ["batch-entities-per-tick"] = {value = 10}},
    get_player_settings = function()
      local preferences = {["quality-change-entity-alerts-enabled"] = {value = true}, ["quality-change-aggregate-alerts-enabled"] = {value = true}}
      for _, style in ipairs({"chat", "gps", "floating-text", "halo", "rainbow", "badge", "bubbles", "sound"}) do
        preferences["quality-change-" .. style .. "-enabled"] = {value = false}
      end
      return preferences
    end,
  }
  game = {forces = {player = {}}, players = {{
    print = function(message) printed[#printed + 1] = message end,
    add_custom_alert = function(entity, icon, message) alerts[#alerts + 1] = {entity = entity, icon = icon, message = message} end,
  }}, tick = 0}
  game.players[1].force = game.forces.player
  game.connected_players = game.players
  math.random = function(low)
    if low then return 1 end
    random_calls = random_calls + 1
    return type(roll) == "function" and roll(random_calls) or roll
  end
  core.initialize()
end

local function stack(quality, count)
  if not quality then return {valid_for_read = false} end
  local item = {
    valid_for_read = true, is_module = true, name = "speed-module", count = count or 1,
    quality = prototypes.quality[quality], health = 0.7, spoil_percent = 0.3,
    prototype = {localised_name = "Speed module", get_spoil_ticks = function() return 100 end},
  }
  item.can_set_stack = function() return not item.reject end
  item.set_stack = function(definition)
    if item.fail then return false end
    item.name, item.count, item.quality = definition.name, definition.count, prototypes.quality[definition.quality]
    item.health, item.spoil_percent = definition.health, definition.spoil_percent
    return true
  end
  item.clear = function() item.valid_for_read = false end
  return item
end

local function host(kind, quality, slots)
  next_id = next_id + 1
  local entity = {
    unit_number = next_id, valid = true, type = kind or "beacon", name = kind or "beacon",
    quality = prototypes.quality[quality or "legendary"], force = game.forces.player,
    surface_index = 1, surface = {index = 1, valid = true}, destructible = true,
    prototype = {selectable_in_game = true, items_to_place_this = {{name = "beacon"}}, name = kind or "beacon"},
    inventory = slots, products_finished = 0, energy = 0,
  }
  entity.get_module_inventory = function() return entity.inventory end
  entity.get_recipe = function() return {prototype = {energy = 3600}} end
  entity.to_be_deconstructed = function() return entity.suspended end
  entity.to_be_upgraded = function() return false end
  entity.order_upgrade = function(order) entity.target_quality = order.target.quality; return true end
  entity.apply_upgrade = function()
    -- Match synchronous engine destruction/build callbacks, with a changed slot count.
    local inventory = entity.replacement_inventory or entity.inventory
    if entity.replacement_inventory == false then inventory = nil end
    local replacement = host(entity.type, entity.target_quality, inventory)
    replacement.surface_index, replacement.surface = entity.surface_index, entity.surface
    core.on_entity_destroyed({entity = entity})
    entity.valid = false
    core.on_entity_created({entity = replacement})
    entity.replacement = replacement
    return replacement
  end
  if slots then
    slots.insert = function(definition)
      for i = 1, #slots do
        if not slots[i].valid_for_read then slots[i] = stack(definition.quality, definition.count); return definition.count end
      end
      return 0
    end
  end
  return entity
end

local function track(entity)
  local info = core.get_entity_info(entity)
  assert(type(info) == "table", tostring(info))
  return info
end

local function visit(info, meter, suspended)
  storage.surface_meters[info.surface_index] = meter
  local changes = {}
  local count = module_upgrades.process(info, info.entity.inventory, suspended, changes)
  return changes, count
end

function tests.slot_progression()
  reset()
  local entity = host(nil, nil, {stack("normal"), stack("normal", 3)})
  local info = track(entity)
  visit(info, 2)
  equal(info.module_failure_bonuses[1], 2)
  equal(info.module_failure_bonuses[2], 2)
  roll = function(call) return call == 3 and 0 or 0.99 end
  local changes = visit(info, 3)
  equal(info.module_failure_bonuses[1], 0)
  equal(info.module_failure_bonuses[2], 3)
  equal(changes["speed-module"], 1)
  equal(entity.inventory[1].quality.name, "uncommon")
  roll = 0
  visit(info, 4)
  equal(entity.inventory[2].count, 3)
  equal(entity.inventory[2].health, 0.7)
  equal(entity.inventory[2].spoil_percent, 0.3)
end

function tests.empty_and_resized_slots()
  reset()
  local entity = host(nil, nil, {stack("normal"), stack("normal"), stack("normal"), stack("normal")})
  local info = track(entity)
  info.module_failure_bonuses = {1, 2, 3, 4}
  entity.inventory = {stack(), stack("normal")}
  local _, count = visit(info, 1)
  equal(count, 2)
  equal(#info.module_failure_bonuses, 4)
  equal(info.module_failure_bonuses[1], 1)
  equal(info.module_failure_bonuses[2], 3)
  equal(info.module_failure_bonuses[4], 4)
  entity.inventory = nil
  visit(info, 10)
  entity.inventory = {stack("normal"), stack(), stack("normal"), stack("normal"), stack("normal")}
  visit(info, 11)
  equal(info.module_failure_bonuses[1], 2)
  equal(info.module_failure_bonuses[3], 4)
  equal(info.module_failure_bonuses[4], 5)
  equal(info.module_failure_bonuses[5], 1)
  entity.inventory[1] = stack("rare")
  visit(info, 12)
  equal(info.module_failure_bonuses[1], 3)
end

function tests.meter_rules()
  reset()
  storage.surface_meters[1] = 100
  local info = track(host(nil, nil, {stack("normal")}))
  visit(info, 100)
  equal(random_calls, 0)
  settings.global["secondary-progression-rate"].value = 0
  visit(info, 110)
  settings.global["secondary-progression-rate"].value = 50
  visit(info, 112)
  equal(info.module_failure_bonuses[1], 1)
  visit(info, 150, true)
  visit(info, 152)
  equal(info.module_failure_bonuses[1], 2)
  info.entity.surface_index, info.entity.surface = 2, {index = 2, valid = true}
  storage.surface_meters[2] = 1000
  core.batch_process_entities()
  equal(info.module_failure_bonuses[1], 2)
  equal(info.module_last_seen_meter, 1000)
  storage.surface_meters[2] = 1002
  core.batch_process_entities()
  equal(info.module_failure_bonuses[1], 3)
end

function tests.quality_paths()
  reset()
  prototypes.quality.uncommon.hidden = true
  storage.config.settings_data.skip_hidden_qualities = true
  core.initialize()
  local entity = host(nil, nil, {stack("normal"), stack("uncommon"), stack("legendary")})
  local info = track(entity)
  roll = 0
  visit(info, 1)
  equal(entity.inventory[1].quality.name, "rare")
  equal(entity.inventory[2].quality.name, "uncommon")
  equal(random_calls, 1)
  equal(info.module_failure_bonuses[2], 0)
  equal(info.module_failure_bonuses[3], 0)
end

function tests.technical_failure()
  reset()
  local item = stack("normal", 2)
  local info = track(host(nil, nil, {item}))
  info.module_failure_bonuses = {5}
  roll = 0
  item.reject = true
  equal(next((visit(info, 1))), nil)
  item.reject, item.fail = false, true
  equal(next((visit(info, 2))), nil)
  equal(info.module_failure_bonuses[1], 5)
  equal(item.count, 2)
  equal(item.quality.name, "normal")
  equal(#alerts, 0)
end

function tests.batch_budget()
  for _, case in ipairs({{1, 4, 1}, {10, 4, 2}, {10, 3, 3}}) do
    reset()
    settings.global["batch-entities-per-tick"].value = case[1]
    local infos = {}
    for i = 1, 5 do
      local slots = {}
      for j = 1, case[2] do slots[j] = stack(j % 2 == 0 and "legendary" or nil) end
      infos[i] = track(host(nil, nil, slots))
    end
    storage.surface_meters[1] = 1
    core.batch_process_entities()
    for i = 1, 5 do equal(infos[i].module_last_seen_meter, i <= case[3] and 1 or 0) end
  end
  reset()
  local info = track(host(nil, nil, {stack("normal")}))
  storage.surface_meters[1] = 1
  core.batch_process_entities()
  equal(random_calls, 1)
  equal(storage.batch_index, 1)
  equal(info.module_failure_bonuses[1], 1)
end

function tests.capped_and_disabled_hosts()
  reset()
  storage.config.upgrade_limit_levels.beacon = 3
  local entity = host(nil, "rare", {stack("epic")})
  track(entity)
  local empty = track(host(nil, "legendary", {stack()}))
  local unrelated = host("electric-pole", "rare")
  track(unrelated)
  storage.surface_meters[1] = 1
  roll = 0
  core.batch_process_entities()
  equal(entity.inventory[1].quality.name, "legendary")
  equal(storage.quality_control_entities[empty.entity.unit_number], empty)
  storage.config.upgrade_limit_levels["electric-pole"] = 3
  core.batch_process_entities()
  equal(storage.quality_control_entities[unrelated.unit_number], nil)
  storage.config.can_attempt_quality_change.beacon = false
  storage.config.upgrade_limit_levels.beacon = 1
  storage.surface_meters[1] = 2
  core.batch_process_entities()
  equal(storage.quality_control_entities[entity.unit_number], nil)
end

function tests.primary_secondary_credits()
  reset()
  local primary = host("assembling-machine", "legendary", {stack("normal")})
  local primary_info = track(primary)
  local secondary = track(host(nil, nil, {stack("normal")}))
  primary.products_finished = 2
  core.batch_process_entities()
  equal(primary_info.module_failure_bonuses[1], 2)
  equal(secondary.module_failure_bonuses[1], 2)
  equal(storage.surface_primary_counts[1], 1)
  equal(storage.surface_meters[1], 2)
  storage.config.can_attempt_quality_change["assembling-machine"] = false
  storage.config.upgrade_limit_levels["assembling-machine"] = 1
  primary.products_finished = 3
  core.batch_process_entities()
  equal(primary_info.module_failure_bonuses[1], 2)
  equal(storage.surface_meters[1], 3)
end

function tests.replacement()
  reset()
  local entity = host("assembling-machine", "normal", {stack("normal"), stack(), stack(), stack()})
  local info = track(entity)
  info.module_failure_bonuses = {1, 2, 3, 4}
  entity.replacement_inventory = {entity.inventory[1], stack()}
  entity.products_finished = 1
  roll = function(call) return call == 1 and 0.99 or 0 end
  core.batch_process_entities()
  local replacement = entity.replacement
  local new_info = storage.quality_control_entities[replacement.unit_number]
  equal(new_info.module_failure_bonuses[1], 2)
  equal(new_info.module_failure_bonuses[4], 4)
  equal(#replacement.inventory, 2)
  equal(new_info.module_last_seen_meter, 1)
  equal(random_calls, 2)
  equal(#storage.entity_list, 1)
  equal(storage.surface_primary_counts[1], 1)
  -- Quality grows again; returning slots resume dormant bonuses.
  replacement.inventory = {stack(), stack(), stack("normal"), stack("normal")}
  roll = 0.99
  visit(new_info, 2)
  equal(new_info.module_failure_bonuses[3], 4)
  equal(new_info.module_failure_bonuses[4], 5)

  -- A terminal replacement with no current inventory retains dormant history.
  reset()
  entity = host(nil, "epic", {stack()})
  info = track(entity)
  info.module_failure_bonuses = {4}
  entity.replacement_inventory = false
  storage.surface_meters[1] = 1
  roll = 0
  core.batch_process_entities()
  replacement = entity.replacement
  new_info = storage.quality_control_entities[replacement.unit_number]
  equal(new_info.module_failure_bonuses[1], 4)
  equal(replacement.inventory, nil)
  core.batch_process_entities()
  equal(storage.quality_control_entities[replacement.unit_number], new_info)
  replacement.inventory = {stack("normal")}
  roll = 0.99
  visit(new_info, 2)
  equal(new_info.module_failure_bonuses[1], 5)

  -- Replacements must not starve middle entries when every roll succeeds.
  reset()
  settings.global["batch-entities-per-tick"].value = 1
  local entities = {}
  for i = 1, 3 do
    entities[i] = host("assembling-machine", "normal", {stack("normal")})
    track(entities[i])
    entities[i].products_finished = 1
  end
  roll = 0
  for _ = 1, 3 do core.batch_process_entities() end
  for i = 1, 3 do assert(entities[i].replacement, "host starved by replacements") end
end

function tests.queue_removal()
  reset()
  local invalid = host(nil, nil, {stack()})
  track(invalid)
  local a = track(host(nil, nil, {stack("normal")}))
  local b = track(host(nil, nil, {stack("normal")}))
  invalid.valid = false
  storage.surface_meters[1] = 1
  core.batch_process_entities()
  equal(a.module_failure_bonuses[1], 1)
  equal(b.module_failure_bonuses[1], 1)
  equal(#storage.entity_list, 2)
  equal(random_calls, 2)
end

function tests.legacy_modes()
  for _, mode in ipairs({"disabled", "enabled", "extra-enabled"}) do
    reset(mode)
    local entity = host("assembling-machine", "rare", {stack("normal")})
    local info = track(entity)
    equal(info.module_failure_bonuses, nil)
    entity.products_finished = 1
    roll = 0
    core.batch_process_entities()
    local expected = mode == "disabled" and "normal" or mode == "enabled" and "uncommon" or "epic"
    equal(entity.replacement.inventory[1].quality.name, expected)
    equal(random_calls, 1)
    equal(storage.quality_control_entities[entity.replacement.unit_number].module_failure_bonuses, nil)
  end
end

function tests.inspection()
  reset()
  local entity = host(nil, nil, {stack("normal"), stack()})
  local info = track(entity)
  info.module_failure_bonuses = {1, 2, 3, 4}
  game.players[1].selected = entity
  notifications.show_entity_quality_info(game.players[1], core.get_entity_info)
  local slots = 0
  for _, message in ipairs(printed) do
    if message[1] == "quality-control.module-slot" or message[1] == "quality-control.module-slot-empty" then slots = slots + 1 end
  end
  equal(slots, 2)
end

function tests.lifecycle()
  reset()
  local entity = host(nil, nil, {stack("normal")})
  local info = track(entity)
  visit(info, 1)
  core.initialize() -- on_load only rebinds locals
  equal(info.module_failure_bonuses[1], 1)
  equal(info.module_last_seen_meter, 1)
  local clone = host(nil, nil, {stack("normal")})
  core.on_entity_cloned({destination = clone})
  equal(storage.quality_control_entities[clone.unit_number].module_last_seen_meter, 1)
  equal(#storage.quality_control_entities[clone.unit_number].module_failure_bonuses, 0)
  core.on_entity_destroyed({entity = entity})
  local replacement = track(host(nil, nil, {stack("normal")}))
  equal(replacement.module_last_seen_meter, 1)
  equal(#replacement.module_failure_bonuses, 0)
  core.on_surface_deleted({surface_index = 1})
  equal(storage.surface_meters[1], nil)
end

function tests.failed_host_upgrade()
  for _, phase in ipairs({"order", "apply"}) do
    reset()
    local entity = host(nil, "normal", {stack("normal")})
    local info = track(entity)
    if phase == "order" then
      entity.order_upgrade = function() return false end
    else
      entity.apply_upgrade = function() return nil end
    end
    storage.surface_meters[1] = 1
    roll = function(call) return call == 1 and 0.99 or 0 end
    core.batch_process_entities()
    local retained = storage.quality_control_entities[entity.unit_number]
    equal(retained.module_failure_bonuses[1], 1)
    equal(retained.module_failure_bonuses, info.module_failure_bonuses)
    equal(#storage.entity_list, 1)
    equal(#alerts, 0)
  end
end

function tests.notifications()
  reset()
  local info = track(host(nil, nil, {stack("normal")}))
  roll = 0
  storage.surface_meters[1] = 1
  core.batch_process_entities()
  equal(#alerts, 1)
  equal(alerts[1].entity, info.entity)
  equal(alerts[1].icon.type, "item")
  equal(alerts[1].message[1], "quality-control.module-upgraded")
  equal(next(storage.aggregate_notifications.accumulated_changes), nil)
  equal(storage.aggregate_notifications.accumulated_module_changes["speed-module"], 1)
  game.tick = 18000
  notifications.try_show_accumulated_notifications()
  equal(printed[2][1], "quality-control.module-summary")
  equal(next(storage.aggregate_notifications.accumulated_module_changes), nil)
end

assert(tests[arg[1]], "unknown scenario")()
