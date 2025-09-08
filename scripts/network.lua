--[[
network.lua

Construction network and inventory management for Quality Control mod.
Handles network tracking, inventory reservations, and upgrade queue processing.
]]

local network = {}

local network_inventory = {}
local upgrade_queue = {}
local tracked_entities = {}

local inventory_defines = {
  ["agricultural-tower"] = defines.inventory.crafter_modules,
  ["assembling-machine"] = defines.inventory.crafter_modules,
  ["beacon"] = defines.inventory.beacon_modules,
  ["furnace"] = defines.inventory.crafter_modules,
  ["lab"] = defines.inventory.lab_modules,
  ["mining-drill"] = defines.inventory.mining_drill_modules
}

function network.initialize()
  network_inventory = storage.network_inventory
  upgrade_queue = storage.upgrade_queue
  tracked_entities = storage.quality_control_entities
end

-- Get the item name for placing an entity
local function get_entity_item_name(entity)
  local items = entity.prototype.items_to_place_this
  if items and #items > 0 then
    return items[1].name
  end
  return nil
end

-- Helper function to update construction networks for a tracked entity
function network.update_construction_networks(entity)
  local networks = entity.surface.find_logistic_networks_by_construction_area(entity.position, entity.force)
  local network_ids = {}
  for _, logistic_network in ipairs(networks) do
    table.insert(network_ids, logistic_network.network_id)
  end

  local entity_info = tracked_entities[entity.unit_number]
  entity_info.networks = networks
  entity_info.network_ids = network_ids

  return entity_info
end

function network.update_network_inventory(networks, item_name, quality)
  for _, logistic_network in ipairs(networks) do
    local item_with_quality = {name = item_name, quality = quality}
    local available_count = logistic_network.get_item_count(item_with_quality)

    local network_id = logistic_network.network_id
    if not network_inventory[network_id] then
      network_inventory[network_id] = {}
    end
    if not network_inventory[network_id][item_name] then
      network_inventory[network_id][item_name] = {}
    end

    if network_inventory[network_id][item_name][quality.level] then
      network_inventory[network_id][item_name][quality.level].available = available_count
    else
      network_inventory[network_id][item_name][quality.level] = {
        available = available_count,
        reserved = 0
      }
    end
  end
end

function network.update_reservations(entity, network_ids, entity_name, target_quality, count)
  -- Handle reservation changes on networks
  for _, network_id in ipairs(network_ids) do
    local items = network_inventory[network_id] and
                  network_inventory[network_id][entity_name] and
                  network_inventory[network_id][entity_name][target_quality]
    if items then
      items.reserved = math.max(0, items.reserved + count)
    end
  end

  -- Add to upgrade queue if adding reservations
  if count > 0 then
    table.insert(upgrade_queue, {
      entity = entity,
      network_ids = network_ids,
      name = entity_name,
      target_quality = target_quality
    })
  end
end

function network.get_next_available_quality(networks, item_name, current_quality)
  local next_quality = current_quality.next
  -- keep this check as a user could insert max quality modules and we don't check those ahead of time
  if not next_quality then
    return nil
  end

  network.update_network_inventory(networks, item_name, next_quality)

  -- Scan for next available quality across networks the entity is covered by
  while next_quality do
    for _, logistic_network in ipairs(networks) do
      local network_id = logistic_network.network_id
      if network_inventory[network_id] and
         network_inventory[network_id][item_name] and
         network_inventory[network_id][item_name][next_quality.level] then
        local item_count = network_inventory[network_id][item_name][next_quality.level]
        if item_count.available - item_count.reserved > 0 then
          return next_quality
        end
      end
    end
    next_quality = next_quality.next
  end

  return nil
end

function network.process_upgrade_queue()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local processed = 0
  local start_index = storage.upgrade_queue_index

  while processed < batch_size and #upgrade_queue > 0 do
    if storage.upgrade_queue_index > #upgrade_queue then
      storage.upgrade_queue_index = 1

      if storage.upgrade_queue_index >= start_index then
        break
      end
    end

    local queue_item = upgrade_queue[storage.upgrade_queue_index]
    local entity = queue_item.entity
    -- if entity is no longer valid then it was replaced by an upgrade
    -- also check for upgrades that were cancelled (only if they aren't an item request proxy though)
    if not entity.valid or (entity.type ~= "item-request-proxy" and not entity.to_be_upgraded()) then
      table.remove(upgrade_queue, storage.upgrade_queue_index)
      network.update_reservations(nil, queue_item.network_ids, queue_item.name, queue_item.target_quality, -1)
    else
      storage.upgrade_queue_index = storage.upgrade_queue_index + 1
    end

    processed = processed + 1
  end

  if #upgrade_queue == 0 then
    storage.upgrade_queue_index = 1
  end
end

function network.get_upgrade_queue_size()
  return #upgrade_queue
end

function network.get_entity_item_name(entity)
  return get_entity_item_name(entity)
end

function network.get_inventory_defines()
  return inventory_defines
end

return network