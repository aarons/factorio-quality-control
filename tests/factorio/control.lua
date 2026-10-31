-- Real entities, inventories, replacement events, ticks, and serialization.
-- Hooks inspect bookkeeping and seed existing bonuses; all work and payouts
-- go through Quality Control's unmodified event handlers.
local loaded_checkpoint = false
local BONUS = {11, 22, 33, 44}

local function check(condition, message)
  assert(condition, "QC_TEST FAIL: " .. message)
end

local function near(actual, expected, message)
  check(math.abs(actual - expected) < 0.000001,
    message .. ": expected " .. expected .. ", got " .. actual)
end

local function snapshot(entity)
  return remote.call("qc-test", "snapshot", entity)
end

local function module_count(inventory)
  local count = 0
  for slot = 1, #inventory do
    if inventory[slot].valid_for_read then
      check(inventory[slot].name == "speed-module", "unexpected item in fixture module inventory")
      count = count + inventory[slot].count
    end
  end
  return count
end

local function pass(name)
  storage.passed[name] = true
  log("QC_TEST PASS " .. name)
end

local function create(surface, name, x, quality)
  return assert(surface.create_entity{
    name = name, position = {x, 0}, force = "player", quality = quality or "normal", raise_built = true
  })
end

local function surface(name)
  local result = game.create_surface("qc-test-" .. name, {width = 64, height = 64,
    autoplace_settings = {entity = {treat_missing_as_default = false},
      tile = {treat_missing_as_default = false}, decorative = {treat_missing_as_default = false}}})
  result.request_to_generate_chunks({0, 0}, 1)
  result.force_generate_chunk_requests()
  local tiles = {}
  for x = -24, 24 do
    for y = -12, 12 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end
  end
  result.set_tiles(tiles)
  return result
end

local function producer(where)
  local entity = create(where, "qc-test-producer", -10, "rare")
  entity.set_recipe("qc-test-work")
  return entity
end

script.on_init(function()
  storage.passed = {}
  storage.phase = "progress"

  local capped_surface = surface("capped")
  local capped = create(capped_surface, "beacon", 0, "uncommon")
  local inventory = capped.get_module_inventory()
  check(inventory.insert{name = "speed-module", count = 1} == 1, "capped_host: insert module")
  remote.call("qc-test", "seed_bonuses", capped, {10000, 0})
  storage.capped = {entity = capped, id = capped.unit_number, producer = producer(capped_surface),
    effect = capped.effects.speed, count = module_count(inventory)}

  local late_surface = surface("late")
  local late = create(late_surface, "beacon", 0, "uncommon")
  remote.call("qc-test", "seed_bonuses", late, {17, 29})
  storage.late = {entity = late, id = late.unit_number, producer = producer(late_surface), stage = "empty"}

  local resize_surface = surface("capacity")
  local resizing = create(resize_surface, "qc-test-resizing", 0)
  resizing.set_recipe("qc-test-work")
  check(#resizing.get_module_inventory() == 4, "capacity: normal host must have four real slots")
  remote.call("qc-test", "seed_bonuses", resizing, BONUS)
  remote.call("qc-test", "guarantee_host_upgrade", resizing)
  -- The sentinel immediately follows the resizing host in the production queue.
  local sentinel = create(resize_surface, "beacon", 10, "uncommon")
  storage.capacity = {entity = resizing, id = resizing.unit_number, surface = resize_surface,
    sentinel = sentinel, stage = "shrink"}
end)

script.on_load(function()
  -- Read persisted state only. The initial save is also loaded once; it must
  -- never be mistaken for the checkpoint with actual earned bonuses.
  loaded_checkpoint = storage.phase == "checkpoint"
end)

local function capped_host()
  if storage.passed.capped_host then return end
  local case = storage.capped
  local inventory = case.entity.get_module_inventory()
  if inventory[1].quality.name == "normal" then return end
  check(case.entity.unit_number == case.id and case.entity.quality.name == "uncommon",
    "capped_host: host changed despite its cap")
  check(inventory[1].name == "speed-module" and module_count(inventory) == case.count,
    "capped_host: module identity/count changed")
  check(case.entity.effects.speed > case.effect, "capped_host: engine did not recalculate the module effect")
  check(case.producer.products_finished > 0 and snapshot(case.entity).meter > 0,
    "capped_host: requires real manufacturing credits")
  near(snapshot(case.entity).bonuses[1], 0, "capped_host: successful slot bonus resets")
  case.producer.disabled_by_script = true
  pass("capped_host")
end

local function check_capacity(entity, slots)
  check(#entity.get_module_inventory() == slots, "capacity: wrong engine inventory size")
  local state = snapshot(entity)
  for slot, bonus in ipairs(BONUS) do
    near(state.bonuses[slot], bonus, "capacity: bonus moved or lost at slot " .. slot)
  end
  check(#state.inspection == slots, "capacity: inspection includes dormant slots")
  for slot, line in ipairs(state.inspection) do
    check(line[2] == slot, "capacity: inspection slot indices changed")
  end
  return state
end

local function capacity()
  if storage.passed.capacity then return end
  local case = storage.capacity
  if not case.entity.valid then
    local replacements = case.surface.find_entities_filtered{name = "qc-test-resizing", force = "player"}
    check(#replacements == 1, "capacity: expected exactly one replacement, found " .. #replacements)
    case.entity = replacements[1]
  end
  local entity = case.entity
  if case.stage == "shrink" and entity.quality.name ~= "normal" then
    check(entity.quality.name == "uncommon" and entity.unit_number ~= case.id,
      "capacity: expected Quality Control replacement at uncommon")
    entity.disabled_by_script = true
    check_capacity(entity, 2)
    remote.call("qc-test", "set_batch_size", 1)
    case.stage = "seek"
  elseif case.stage == "seek" then
    local state = check_capacity(entity, 2)
    if state.queue[state.batch_index] == entity.unit_number then
      check(state.queue[state.batch_index + 1] == case.sentinel.unit_number,
        "capacity: sentinel must immediately follow host")
      -- With two live slots the host costs three, leaving budget to visit the
      -- sentinel. Charging four remembered slots would stop before it.
      case.expected_index = state.batch_index + 2
      remote.call("qc-test", "set_batch_size", 4)
      case.stage = "budget"
    end
  elseif case.stage == "budget" then
    local state = check_capacity(entity, 2)
    check(state.batch_index == case.expected_index, "capacity: dormant slots charged to batch budget")
    remote.call("qc-test", "set_batch_size", 1000)
    remote.call("qc-test", "guarantee_host_upgrade", entity)
    case.id = entity.unit_number
    entity.disabled_by_script = false
    case.stage = "grow"
  elseif case.stage == "grow" and entity.quality.name ~= "uncommon" then
    check(entity.quality.name == "rare" and entity.unit_number ~= case.id,
      "capacity: expected Quality Control replacement at rare")
    entity.disabled_by_script = true
    check_capacity(entity, 4)
    local inventory = entity.get_module_inventory()
    check(inventory[3].set_stack{name = "speed-module", quality = "legendary", count = 1},
      "capacity: restored slot must accept a real module")
    case.stage = "restored"
    case.restored_tick = game.tick
  elseif case.stage == "restored" and game.tick > case.restored_tick + 5 then
    check_capacity(entity, 4)
    check(entity.get_module_inventory()[3].valid_for_read, "capacity: restored slot lost its module")
    pass("capacity")
  end
end

local function late_insert()
  if storage.passed.late_insert then return end
  local case = storage.late
  local state = snapshot(case.entity)
  check(case.entity.unit_number == case.id, "late_insert: tracking host was replaced")
  if case.stage == "empty" and game.tick >= 150 then
    check(state.meter > 0, "late_insert: surface did not progress while empty")
    near(state.bonuses[1], 17, "late_insert: empty slot accumulated bonus")
    case.producer.disabled_by_script = true
    case.stage = "drain"
    case.until_tick = game.tick + 20
  elseif case.stage == "drain" and game.tick >= case.until_tick then
    near(state.bookmark, state.meter, "late_insert: empty visits did not advance bookmark")
    check(case.entity.get_module_inventory()[1].set_stack{name = "speed-module", count = 1},
      "late_insert: insert into previously empty host")
    case.inserted_meter = state.meter
    case.until_tick = game.tick + 20
    case.stage = "no_history"
  elseif case.stage == "no_history" then
    near(state.meter, case.inserted_meter, "late_insert: stopped producer must not generate credits")
    near(state.bonuses[1], 17, "late_insert: historical empty intervals paid a bonus")
    check(case.entity.get_module_inventory()[1].quality.name == "normal",
      "late_insert: historical empty intervals paid an upgrade")
    if game.tick >= case.until_tick then
      case.previous = state
      case.producer.disabled_by_script = false
      case.stage = "earn"
    end
  elseif case.stage == "earn" then
    -- Observe a real failed roll rather than asserting a particular RNG sequence.
    if state.bonuses[1] > case.previous.bonuses[1] then
      near(state.bonuses[1] - case.previous.bonuses[1], state.bookmark - case.previous.bookmark,
        "late_insert: payout must match only new credits")
      check(state.bookmark > case.inserted_meter, "late_insert: no new credits earned")
      case.producer.disabled_by_script = true
      case.earned_tick = game.tick
      pass("late_insert")
    end
    case.previous = state
  end
end

local function checkpoint()
  if not (storage.passed.capped_host and storage.passed.capacity and storage.passed.late_insert) then return end
  if game.tick <= storage.late.earned_tick + 20 then return end
  local case = storage.late
  storage.earned = snapshot(case.entity)
  check(storage.earned.bonuses[1] > 0 and storage.earned.bookmark > 0,
    "earned_reload: checkpoint must contain earned bonus and bookmark")
  near(storage.earned.bookmark, storage.earned.meter, "earned_reload: checkpoint has unconsumed credits")
  storage.earned_quality = case.entity.get_module_inventory()[1].quality.name
  storage.earned_products = case.producer.products_finished
  storage.checkpoint_tick = game.tick
  storage.phase = "checkpoint"
  check(game.is_multiplayer(), "earned_reload: checkpoint needs server_save in multiplayer")
  game.server_save("qc-earned")
  log("QC_TEST CHECKPOINT earned progression at tick " .. game.tick)
end

local function earned_reload()
  local case = storage.late
  local state = snapshot(case.entity)
  local elapsed = game.tick - storage.checkpoint_tick
  check(elapsed > 0, "earned_reload: checkpoint did not advance")
  if elapsed <= 20 then
    for slot, bonus in pairs(storage.earned.bonuses) do
      near(state.bonuses[slot], bonus, "earned_reload: saved slot bonus changed while idle")
    end
    near(state.meter, storage.earned.meter, "earned_reload: replayed production history")
    near(state.bookmark, storage.earned.bookmark, "earned_reload: module bookmark changed while idle")
    near(state.host_bookmark, storage.earned.host_bookmark, "earned_reload: host bookmark changed while idle")
    check(case.producer.products_finished == storage.earned_products, "earned_reload: producer was not stopped")
    check(case.entity.get_module_inventory()[1].quality.name == storage.earned_quality,
      "earned_reload: historical credits paid an upgrade")
    if elapsed == 20 then case.producer.disabled_by_script = false end
  elseif state.bookmark > storage.earned.bookmark then
    check(case.producer.products_finished > storage.earned_products, "earned_reload: no new production")
    local stack = case.entity.get_module_inventory()[1]
    if stack.quality.name == storage.earned_quality then
      near(state.bonuses[1] - storage.earned.bonuses[1], state.bookmark - storage.earned.bookmark,
        "earned_reload: new credits paid incorrectly")
    else
      near(state.bonuses[1], 0, "earned_reload: successful upgrade did not reset bonus")
    end
    pass("earned_reload")
    storage.phase = "done"
    log("QC_TEST SUCCESS")
  end
  check(elapsed < 500, "earned_reload: progression did not resume within tick limit")
end

script.on_event(defines.events.on_tick, function()
  if storage.phase == "done" then return end
  if not storage.passed.upgrade_sounds then
    check(remote.call("qc-test", "validate_upgrade_sounds") == 385, "upgrade_sounds: incomplete sound catalog")
    pass("upgrade_sounds")
  end
  if storage.phase == "checkpoint" then
    if loaded_checkpoint then earned_reload() end
    return
  end
  check(game.tick < 6000, "progress: cases did not complete within tick limit")
  capped_host()
  capacity()
  late_insert()
  checkpoint()
end)
