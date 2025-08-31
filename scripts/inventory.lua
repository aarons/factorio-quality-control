--[[
inventory.lua

Simplified network inventory checker for quality upgrade availability.
Uses lock-based system to prevent over-allocation instead of complex pending upgrade tracking.
Keeps round-robin quality scanning for performance.
]]

local inventory = {}

local network_logistics = {}
local upgrade_locks = {}  -- [network_id][item_name][quality_level] = { count, timestamp }
local tracked_entities = {}
local config = {}
local lock_timeout = 30 * 60  -- 30 seconds in ticks

function inventory.initialize()
  network_logistics = storage.network_logistics or {}
  upgrade_locks = storage.upgrade_locks or {}
  tracked_entities = storage.quality_control_entities or {}
  config = storage.config or {}

  -- Migrate old storage if needed
  storage.network_logistics = network_logistics
  storage.upgrade_locks = upgrade_locks
end

-- Calculate how many concurrent upgrades we can allow for this item/quality
local function get_lock_limit(network, item_name, quality_level)
  local item_with_quality = {name = item_name, quality = prototypes.quality["normal"]}

  -- Find the quality prototype for this level
  local quality = prototypes.quality["normal"]
  while quality and quality.level < quality_level do
    quality = quality.next
  end

  if quality then
    item_with_quality.quality = quality
    local available_count = network.get_item_count(item_with_quality)
    -- Allow n/2+1 concurrent upgrades when n items exist, minimum of 1
    return math.max(1, math.floor(available_count / 2) + 1)
  end

  return 0
end

-- Clean up expired locks
function inventory.cleanup_locks()
  local current_tick = game.tick

  for network_id, network_locks in pairs(upgrade_locks) do
    for item_name, item_locks in pairs(network_locks) do
      for quality_level, lock_info in pairs(item_locks) do
        if current_tick - lock_info.timestamp > lock_timeout then
          upgrade_locks[network_id][item_name][quality_level] = nil
        end
      end

      -- Clean up empty entries
      if next(item_locks) == nil then
        upgrade_locks[network_id][item_name] = nil
      end
    end

    if next(network_locks) == nil then
      upgrade_locks[network_id] = nil
    end
  end
end

-- Check if upgrade is available for entity, accounting for locks
function inventory.check_upgrade_available(network, entity_name, current_quality)
  if not network or not network.valid then
    return nil
  end

  local network_id = network.network_id

  -- Initialize network logistics data if needed
  if not network_logistics[network_id] then
    network_logistics[network_id] = {}
  end

  if not network_logistics[network_id][entity_name] then
    network_logistics[network_id][entity_name] = {
      min_entity_quality = 0,
      next_quality_check = 0,
      inventory_cache = {},
      cache_timestamp = 0
    }
  end

  local item_data = network_logistics[network_id][entity_name]

  -- Update minimum quality level based on current tracked entities
  local min_level = 9999
  local found_any = false
  for unit_number, entity_info in pairs(tracked_entities or {}) do
    if entity_info.entity and entity_info.entity.valid and entity_info.entity.name == entity_name then
      min_level = math.min(min_level, entity_info.entity.quality.level)
      found_any = true
    end
  end
  item_data.min_entity_quality = found_any and min_level or 0

  -- Round-robin quality scanning - make one targeted get_item_count call
  local quality_limit = config.quality_limit
  if quality_limit and item_data.next_quality_check <= quality_limit.level then
    local quality = prototypes.quality["normal"]
    while quality and quality.level < item_data.next_quality_check do
      quality = quality.next
    end

    if quality and quality.level == item_data.next_quality_check then
      local item_with_quality = {name = entity_name, quality = quality}
      item_data.inventory_cache[item_data.next_quality_check] = network.get_item_count(item_with_quality)
      item_data.cache_timestamp = game.tick
    end
  end

  -- Advance to next quality level (wrap around when reaching limit)
  if quality_limit then
    item_data.next_quality_check = item_data.next_quality_check + 1
    if item_data.next_quality_check > quality_limit.level then
      item_data.next_quality_check = item_data.min_entity_quality
    end
  end

  -- Find best available quality above current level
  if quality_limit then
    for level = quality_limit.level, current_quality.level + 1, -1 do
      local available_count = item_data.inventory_cache[level] or 0

      if available_count > 0 then
        -- Check if we can acquire a lock for this upgrade
        local lock_limit = get_lock_limit(network, entity_name, level)
        local current_locks = 0

        if upgrade_locks[network_id] and
           upgrade_locks[network_id][entity_name] and
           upgrade_locks[network_id][entity_name][level] then
          current_locks = upgrade_locks[network_id][entity_name][level].count
        end

        if current_locks < lock_limit then
          -- Find quality prototype for this level
          local quality = prototypes.quality["normal"]
          while quality and quality.level < level do
            quality = quality.next
          end
          return quality
        end
      end
    end
  end

  return nil
end

-- Try to acquire a lock for an upgrade
function inventory.try_acquire_lock(network, entity_name, target_quality)
  if not network or not network.valid then
    return false
  end

  local network_id = network.network_id
  local quality_level = target_quality.level

  -- Initialize lock structure if needed
  if not upgrade_locks[network_id] then
    upgrade_locks[network_id] = {}
  end
  if not upgrade_locks[network_id][entity_name] then
    upgrade_locks[network_id][entity_name] = {}
  end
  if not upgrade_locks[network_id][entity_name][quality_level] then
    upgrade_locks[network_id][entity_name][quality_level] = { count = 0, timestamp = game.tick }
  end

  local lock_info = upgrade_locks[network_id][entity_name][quality_level]
  local lock_limit = get_lock_limit(network, entity_name, quality_level)

  if lock_info.count < lock_limit then
    lock_info.count = lock_info.count + 1
    lock_info.timestamp = game.tick
    return true
  end

  return false
end

-- Release a lock for an upgrade
function inventory.release_lock(network, entity_name, target_quality)
  if not network or not network.valid then
    return
  end

  local network_id = network.network_id
  local quality_level = target_quality.level

  if upgrade_locks[network_id] and
     upgrade_locks[network_id][entity_name] and
     upgrade_locks[network_id][entity_name][quality_level] then

    local lock_info = upgrade_locks[network_id][entity_name][quality_level]
    lock_info.count = math.max(0, lock_info.count - 1)

    -- Clean up empty lock
    if lock_info.count == 0 then
      upgrade_locks[network_id][entity_name][quality_level] = nil

      if next(upgrade_locks[network_id][entity_name]) == nil then
        upgrade_locks[network_id][entity_name] = nil

        if next(upgrade_locks[network_id]) == nil then
          upgrade_locks[network_id] = nil
        end
      end
    end
  end
end

-- Handle upgrade completion (when robot builds the upgraded entity)
function inventory.on_robot_built_entity(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.force ~= game.forces.player then
    return
  end

  -- Release lock for this upgrade (we assume it succeeded)
  local network = entity.logistic_network
  if network then
    inventory.release_lock(network, entity.name, entity.quality)
  end

  -- Also handle entity tracking for new entities
  local core = require("scripts.core")
  if config and config.is_tracked_type and config.is_tracked_type[entity.type] then
    core.get_entity_info(entity)
  end
end

-- Handle entity marked for upgrade
function inventory.on_marked_for_upgrade(event)
  local entity = event.entity
  if not entity.valid or entity.force ~= game.forces.player then
    return
  end

  local network = entity.logistic_network
  if not network then
    return
  end

  local target_quality = inventory.check_upgrade_available(network, entity.name, entity.quality)
  if target_quality then
    -- Try to acquire lock - if we can't, the upgrade will fail anyway
    inventory.try_acquire_lock(network, entity.name, target_quality)
  end
end

-- Handle upgrade cancellation
function inventory.on_cancelled_upgrade(event)
  local entity = event.entity
  if not entity.valid or entity.force ~= game.forces.player then
    return
  end

  local network = entity.logistic_network
  if network then
    -- We don't know what quality was being upgraded to, so we need to scan for locks
    -- This is imperfect but should be rare since cancellations are uncommon
    local network_id = network.network_id
    local entity_name = entity.name

    if upgrade_locks[network_id] and upgrade_locks[network_id][entity_name] then
      -- Release one lock from the highest quality level being upgraded
      for quality_level in pairs(upgrade_locks[network_id][entity_name]) do
        local quality = prototypes.quality["normal"]
        while quality and quality.level < quality_level do
          quality = quality.next
        end

        if quality then
          inventory.release_lock(network, entity_name, quality)
          break -- Only release one lock
        end
      end
    end
  end
end

-- Clean up invalid networks
function inventory.cleanup_invalid_networks()
  local valid_network_ids = {}
  for _, network in pairs(game.forces.player.logistic_networks) do
    valid_network_ids[network.network_id] = true
  end

  for network_id in pairs(network_logistics or {}) do
    if not valid_network_ids[network_id] then
      network_logistics[network_id] = nil
    end
  end

  for network_id in pairs(upgrade_locks or {}) do
    if not valid_network_ids[network_id] then
      upgrade_locks[network_id] = nil
    end
  end
end

return inventory