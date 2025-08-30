--[[
inventory.lua

Lightweight network inventory checker for quality upgrade availability.
Uses targeted get_item_count() calls instead of expensive get_contents() for better performance.
Scans quality levels in round-robin fashion, building knowledge over time while minimizing API overhead.
]]

local inventory = {}

local network_inventory = {}
local pending_upgrades = {}
local tracked_entities = {}
local config = {}

function inventory.initialize()
  network_inventory = storage.network_inventory
  pending_upgrades = storage.pending_upgrades
  tracked_entities = storage.quality_control_entities
  config = storage.config
end

-- Check if upgrade is available for entity, accounting for pending upgrades
function inventory.check_upgrade_available(network, entity_name, current_quality)
  if not network or not network.valid then
    return nil
  end

  -- Update scan data (makes one API call)
  local network_id = network.network_id

  -- Initialize network scan data if needed
  if not network_inventory[network_id] then
    network_inventory[network_id] = {}
  end

  if not network_inventory[network_id][entity_name] then
    network_inventory[network_id][entity_name] = {
      min_quality_level = 0,
      current_scan_level = 0,
      counts = {},
      last_update_tick = 0
    }
  end

  local scan_data = network_inventory[network_id][entity_name]

  -- Update minimum quality level based on current tracked entities
  local min_level = 9999
  local found_any = false
  for unit_number, entity_info in pairs(tracked_entities or {}) do
    if entity_info.entity and entity_info.entity.valid and entity_info.entity.name == entity_name then
      min_level = math.min(min_level, entity_info.entity.quality.level)
      found_any = true
    end
  end
  scan_data.min_quality_level = found_any and min_level or 0

  -- Make one targeted get_item_count call for current scan level
  local quality_limit = config.quality_limit
  if scan_data.current_scan_level <= quality_limit.level then
    -- Find quality prototype for current scan level
    local quality = prototypes.quality["normal"]
    while quality and quality.level < scan_data.current_scan_level do
      quality = quality.next
    end

    if quality and quality.level == scan_data.current_scan_level then
      -- Get count for this specific quality level
      local item_with_quality = {name = entity_name, quality = quality}
      scan_data.counts[scan_data.current_scan_level] = network.get_item_count(item_with_quality)
      scan_data.last_update_tick = game.tick
    end
  end

  -- Advance to next quality level (wrap around when reaching limit)
  scan_data.current_scan_level = scan_data.current_scan_level + 1
  if scan_data.current_scan_level > quality_limit.level then
    scan_data.current_scan_level = scan_data.min_quality_level
  end

  -- Find best available quality above current level
  for level = quality_limit.level, current_quality.level + 1, -1 do
    local available_count = scan_data.counts[level] or 0

    -- Subtract pending upgrades for this quality level
    local pending_count = 0
    for unit_number, upgrade_info in pairs(pending_upgrades) do
      if upgrade_info.entity_name == entity_name and
         upgrade_info.target_quality.level == level and
         upgrade_info.network_id == network.network_id then
        pending_count = pending_count + 1
      end
    end

    local effective_count = available_count - pending_count
    if effective_count > 0 then
      -- Find quality prototype for this level
      local quality = prototypes.quality["normal"]
      while quality and quality.level < level do
        quality = quality.next
      end
      return quality
    end
  end

  return nil
end

-- Track a pending upgrade to avoid double-allocation
function inventory.track_pending_upgrade(entity, target_quality, network)
  pending_upgrades[entity.unit_number] = {
    entity_name = entity.name,
    target_quality = target_quality,
    network_id = network.network_id,
    tick = game.tick,
    is_registered = true,
    original_item = entity.name,
    last_tick = game.tick
  }
end

-- Clean up completed or stale pending upgrades and invalid networks
function inventory.cleanup_pending_upgrades(full_network_cleanup)
  local current_tick = game.tick
  local stale_threshold = 60 * 60 * 10 -- 10 minutes

  -- Clean up stale pending upgrades
  for unit_number, upgrade_info in pairs(pending_upgrades) do
    local age = current_tick - upgrade_info.tick
    if age > stale_threshold then
      pending_upgrades[unit_number] = nil
    end
  end

  -- Clean up invalid networks
  if full_network_cleanup then
    -- Full cleanup - remove all invalid networks at once
    local valid_network_ids = {}
    for _, network in pairs(game.forces.player.logistic_networks) do
      valid_network_ids[network.network_id] = true
    end

    for network_id in pairs(network_inventory or {}) do
      if not valid_network_ids[network_id] then
        network_inventory[network_id] = nil
      end
    end
  else
    -- Incremental cleanup - check a few networks per call to avoid performance impact
    local networks_checked = 0
    local max_networks_per_cleanup = 3

    for network_id in pairs(network_inventory or {}) do
      if networks_checked >= max_networks_per_cleanup then
        break
      end

      -- Check if this network still exists
      local network_exists = false
      for _, network in pairs(game.forces.player.logistic_networks) do
        if network.network_id == network_id then
          network_exists = true
          break
        end
      end

      if not network_exists then
        network_inventory[network_id] = nil
      end

      networks_checked = networks_checked + 1
    end
  end
end

-- Check if entity creation matches a pending upgrade and complete it if so
function inventory.check_and_complete_upgrade(entity)
  if not entity or not entity.valid then
    return false
  end

  local old_unit_number = nil
  local matching_upgrade = nil

  for unit_number, upgrade_info in pairs(pending_upgrades or {}) do
    if upgrade_info.is_registered and
       upgrade_info.original_item == entity.name and
       upgrade_info.target_quality.name == entity.quality.name then
      -- This matches our tracked upgrade - prioritize more recent entries
      if not matching_upgrade or upgrade_info.last_tick > matching_upgrade.last_tick then
        old_unit_number = unit_number
        matching_upgrade = upgrade_info
      end
    end
  end

  if old_unit_number and matching_upgrade then
    pending_upgrades[old_unit_number] = nil
    return true
  end

  return false
end


-- Handle entity marked for upgrade event
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
    inventory.track_pending_upgrade(entity, target_quality, network)
  end
end

-- Handle upgrade cancellation event
function inventory.on_cancelled_upgrade(event)
  local entity = event.entity
  if entity.valid then
    pending_upgrades[entity.unit_number] = nil
  end
end

-- Clean up scan data for networks that no longer exist
function inventory.cleanup_invalid_networks()
  inventory.cleanup_pending_upgrades(true) -- true for full network cleanup
end


return inventory