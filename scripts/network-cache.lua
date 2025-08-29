--[[
network-cache.lua

Efficient caching system for logistic network contents to support uncommon difficulty mode.
Provides O(1) quality lookups and minimizes API calls through lazy loading and expiry-based updates.
]]

local network_cache = {}

-- Cache settings
local CACHE_EXPIRY_TICKS = 360 -- 6 seconds at 60 UPS
local network_caches = {} -- indexed by network_id
local accessed_networks_this_tick = {} -- track which networks were accessed this tick

function network_cache.initialize()
  if not storage.network_caches then
    storage.network_caches = {}
  end
  network_caches = storage.network_caches

  -- Initialize upgrade tracking
  if not storage.pending_upgrades then
    storage.pending_upgrades = {} -- Maps unit_number -> {entity_name, target_quality, network_id}
  end

  -- Clear accessed networks tracker each tick
  accessed_networks_this_tick = {}
end

-- Build quality-indexed lookup table from network contents
local function build_quality_map(contents)
  local item_quality_map = {}

  for item_with_quality, count in pairs(contents) do
    -- Parse item name and quality from the key
    -- Format: "item-name#quality-name" or just "item-name" for normal quality
    local item_name, quality_name = item_with_quality:match("^(.+)#(.+)$")
    if not item_name then
      -- No quality specified, assume normal quality
      item_name = item_with_quality
      quality_name = "normal"
    end

    local quality = prototypes.quality[quality_name]
    if quality then
      if not item_quality_map[item_name] then
        item_quality_map[item_name] = {}
      end
      item_quality_map[item_name][quality.level] = count
    end
  end

  return item_quality_map
end

-- Find the best available quality for an item above the current level
local function find_best_available_quality(cache_entry, item_name, current_quality_level)
  local item_qualities = cache_entry.item_quality_map[item_name]
  if not item_qualities then
    return nil
  end

  -- Start from highest possible quality and work down
  local quality_limit = storage.config.quality_limit
  for level = quality_limit.level, current_quality_level + 1, -1 do
    local available_count = item_qualities[level] or 0

    -- Account for pending orders
    local pending_key = item_name .. "#" .. level
    local pending_count = cache_entry.pending_orders[pending_key] or 0
    local effective_count = available_count - pending_count

    if effective_count > 0 then
      -- Find the quality prototype for this level
      local quality = prototypes.quality["normal"]
      while quality and quality.level < level do
        quality = quality.next
      end
      return quality
    end
  end

  return nil
end

-- Update cache for a specific network
local function update_network_cache(network)
  if not network or not network.valid then
    return false
  end

  local network_id = network.network_id
  local current_tick = game.tick

  -- Initialize cache entry if it doesn't exist
  if not network_caches[network_id] then
    network_caches[network_id] = {
      last_update = 0,
      contents = {},
      item_quality_map = {},
      pending_orders = {}
    }
  end

  local cache_entry = network_caches[network_id]

  -- Check if cache is still fresh
  if current_tick - cache_entry.last_update < CACHE_EXPIRY_TICKS then
    return true -- Cache is fresh
  end

  -- Update cache with fresh data
  cache_entry.contents = network.get_contents()
  cache_entry.item_quality_map = build_quality_map(cache_entry.contents)
  cache_entry.last_update = current_tick

  -- Note: pending_orders are now managed by upgrade events, not cleared on cache refresh

  return true
end

-- Get or update cache for a network (lazy loading)
function network_cache.get_network_cache(network)
  if not network or not network.valid then
    return nil
  end

  local network_id = network.network_id

  -- Mark this network as accessed this tick for cleanup purposes
  accessed_networks_this_tick[network_id] = true

  -- Update cache if needed
  if not update_network_cache(network) then
    return nil
  end

  return network_caches[network_id]
end

-- Check if any upgraded quality is available for an entity
function network_cache.find_available_upgrade(network, entity_name, current_quality)
  local cache_entry = network_cache.get_network_cache(network)
  if not cache_entry then
    return nil
  end

  return find_best_available_quality(cache_entry, entity_name, current_quality.level)
end

-- Track a pending upgrade order to maintain accurate inventory counts
function network_cache.track_pending_order(network, entity, target_quality, source_quality) -- luacheck: ignore source_quality
  local cache_entry = network_cache.get_network_cache(network)
  if not cache_entry then
    return
  end

  -- Decrement the target quality count (being consumed)
  local entity_name = entity.name
  local target_key = entity_name .. "#" .. target_quality.level
  cache_entry.pending_orders[target_key] = (cache_entry.pending_orders[target_key] or 0) + 1

  -- Store upgrade info for event handling
  storage.pending_upgrades[entity.unit_number] = {
    entity_name = entity_name,
    target_quality = target_quality,
    network_id = network.network_id
  }

  -- Note: We don't increment source quality here because the entity hasn't been replaced yet
  -- This will happen when the actual upgrade completes and the old entity gets recycled
  -- source_quality parameter reserved for future use when tracking recycled entities
end

-- Clean up cache entries for networks that no longer exist
function network_cache.cleanup_invalid_networks()
  for network_id, cache_entry in pairs(network_caches) do
    -- If network wasn't accessed this tick and cache is old, it might be invalid
    if not accessed_networks_this_tick[network_id] then
      local age = game.tick - cache_entry.last_update
      if age > CACHE_EXPIRY_TICKS * 2 then -- Clean up after 2x expiry time
        network_caches[network_id] = nil
      end
    end
  end

  -- Reset accessed networks for next tick
  accessed_networks_this_tick = {}
end

-- Complete a pending order (called when upgrade is fulfilled)
function network_cache.complete_pending_order(network, entity_name, target_quality)
  local cache_entry = network_cache.get_network_cache(network)
  if not cache_entry then
    return
  end

  local target_key = entity_name .. "#" .. target_quality.level
  if cache_entry.pending_orders[target_key] and cache_entry.pending_orders[target_key] > 0 then
    cache_entry.pending_orders[target_key] = cache_entry.pending_orders[target_key] - 1
    if cache_entry.pending_orders[target_key] == 0 then
      cache_entry.pending_orders[target_key] = nil
    end
  end
end

-- Cancel a pending order (called when upgrade is cancelled)
function network_cache.cancel_pending_order(network, entity_name, target_quality)
  local cache_entry = network_cache.get_network_cache(network)
  if not cache_entry then
    return
  end

  local target_key = entity_name .. "#" .. target_quality.level
  if cache_entry.pending_orders[target_key] and cache_entry.pending_orders[target_key] > 0 then
    cache_entry.pending_orders[target_key] = cache_entry.pending_orders[target_key] - 1
    if cache_entry.pending_orders[target_key] == 0 then
      cache_entry.pending_orders[target_key] = nil
    end
  end
end

-- Handle upgrade completion event
function network_cache.on_upgrade_completed(old_unit_number, new_entity) -- luacheck: ignore new_entity
  local upgrade_info = storage.pending_upgrades[old_unit_number]
  if not upgrade_info then
    return -- Not one of our tracked upgrades
  end

  -- Find the network and complete the pending order
  for _, network in pairs(game.forces.player.logistic_networks) do
    if network.network_id == upgrade_info.network_id then
      network_cache.complete_pending_order(network, upgrade_info.entity_name, upgrade_info.target_quality)
      break
    end
  end

  -- Clean up tracking
  storage.pending_upgrades[old_unit_number] = nil
end

-- Handle upgrade cancellation event
function network_cache.on_upgrade_cancelled(entity)
  local upgrade_info = storage.pending_upgrades[entity.unit_number]
  if not upgrade_info then
    return -- Not one of our tracked upgrades
  end

  -- Find the network and cancel the pending order
  for _, network in pairs(game.forces.player.logistic_networks) do
    if network.network_id == upgrade_info.network_id then
      network_cache.cancel_pending_order(network, upgrade_info.entity_name, upgrade_info.target_quality)
      break
    end
  end

  -- Clean up tracking
  storage.pending_upgrades[entity.unit_number] = nil
end

-- Get cache statistics for debugging
function network_cache.get_statistics()
  local stats = {
    cached_networks = 0,
    total_cached_items = 0,
    total_pending_orders = 0
  }

  for _, cache_entry in pairs(network_caches) do
    stats.cached_networks = stats.cached_networks + 1

    for _ in pairs(cache_entry.item_quality_map) do
      stats.total_cached_items = stats.total_cached_items + 1
    end

    for _ in pairs(cache_entry.pending_orders) do
      stats.total_pending_orders = stats.total_pending_orders + 1
    end
  end

  return stats
end

return network_cache