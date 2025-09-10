--[[
core.lua

Core processing engine for Quality Control mod.
Handles entity quality management, credit system, and main processing loop.
Combines upgrade processing, entity tracking, and batch processing functionality.
]]

local notifications = require("scripts.notifications")
local core = {}

local tracked_entities = {}
local settings_data = {}
local is_tracked_type = {}
local mod_difficulty = nil
local quality_multipliers = {}
local accumulate_at_max_quality = nil
local base_percentage_chance = nil
local accumulation_percentage = nil
local network_inventory = {}
local entity_list = {}
local entity_list_index = {}
local upgrade_queue = {}

local inventory_defines = {
  ["agricultural-tower"] = defines.inventory.crafter_modules,
  ["assembling-machine"] = defines.inventory.crafter_modules,
  ["beacon"] = defines.inventory.beacon_modules,
  ["furnace"] = defines.inventory.crafter_modules,
  ["lab"] = defines.inventory.lab_modules,
  ["mining-drill"] = defines.inventory.mining_drill_modules
}

-- Testing mode - mod exclusions removed for file size testing
local excluded_mods_lookup = {}

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
  mod_difficulty = storage.config.mod_difficulty
  quality_multipliers = storage.quality_multipliers
  network_inventory = storage.network_inventory
  entity_list = storage.entity_list
  entity_list_index = storage.entity_list_index
  upgrade_queue = storage.upgrade_queue
  accumulate_at_max_quality = settings_data.accumulate_at_max_quality
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
end

-- Get the item name for placing an entity
local function get_entity_item_name(entity)
  local items = entity.prototype.items_to_place_this
  if items and #items > 0 then
    return items[1].name
  end
  return nil
end

-- Exclude entities that shouldn't be upgraded
local function should_exclude_entity(entity)
  if not entity.prototype.selectable_in_game then
    return true
  end

  if not entity.destructible then
    return true
  end

  -- check if entity has no placeable items
  if get_entity_item_name(entity) == nil then
    return true
  end

  -- Check if entity is from an excluded mod
  local history = prototypes.get_history(entity.type, entity.name)
  if history and excluded_mods_lookup[history.created] then
    return true
  end

  return false
end


-- Helper function to update construction networks for a tracked entity
local function update_construction_networks(entity)
  local networks = entity.surface.find_logistic_networks_by_construction_area(entity.position, entity.force)
  local network_ids = {}
  for _, network in ipairs(networks) do
    table.insert(network_ids, network.network_id)
  end

  local entity_info = tracked_entities[entity.unit_number]
  entity_info.networks = networks
  entity_info.network_ids = network_ids

  return entity_info
end

local function update_network_inventory(networks, item_name, quality)
  for _, network in ipairs(networks) do
    local item_with_quality = {name = item_name, quality = quality}
    local available_count = network.get_item_count(item_with_quality)

    local network_id = network.network_id
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

local function update_reservations(entity, network_ids, entity_name, target_quality, count)
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


local function get_next_available_quality(networks, item_name, current_quality)
  local next_quality = current_quality.next
  -- keep this check as a user could insert max quality modules and we don't check those ahead of time
  if not next_quality then
    return nil
  end

  update_network_inventory(networks, item_name, next_quality)

  -- Scan for next available quality across networks the entity is covered by
  while next_quality do
    for _, network in ipairs(networks) do
      local network_id = network.network_id
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


function core.get_entity_info(entity)
  local id = entity.unit_number
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities with accumulation enabled
  local should_track = entity.quality.next ~= nil or (is_primary and accumulate_at_max_quality)
  if not should_track then
    return "at max quality"
  end

  if tracked_entities[id] then
    return tracked_entities[id]
  end

  -- entity is not tracked; so we're adding a new entity
  -- first check if it's something we should track:
  if should_exclude_entity(entity) then
    return "entity excluded from quality control"
  end

  tracked_entities[id] = {
    entity = entity,
    is_primary = is_primary,
    chance_to_change = base_percentage_chance,
    upgrade_attempts = 0,
  }

  if is_primary then
    storage.primary_entity_count = storage.primary_entity_count + 1
  else
    storage.secondary_entity_count = storage.secondary_entity_count + 1
  end

  -- Use ordered list for O(1) lookup in batch processing
  table.insert(entity_list, id)
  entity_list_index[id] = #entity_list

  if mod_difficulty == "Uncommon" then
    local entity_info = update_construction_networks(entity)
    if entity.to_be_upgraded() and #entity_info.networks > 0 then
      local _, target_quality = entity.get_upgrade_target()
      update_network_inventory(entity_info.networks, get_entity_item_name(entity), target_quality)
      update_reservations(entity, entity_info.network_ids, get_entity_item_name(entity), target_quality.level, 1)
    end
  end

  if not is_primary then
    -- all done with secondary entity processing, ok to return
    return tracked_entities[id]
  end

  -- Initialize manufacturing hours based on current products_finished
  -- This ensures we don't double-count hours for already-producing entities
  local recipe_time = 0
  if entity.get_recipe() then
    recipe_time = entity.get_recipe().prototype.energy
  elseif entity.type == "furnace" and entity.previous_recipe then
    recipe_time = entity.previous_recipe.name.energy
  end

  local current_hours = (entity.products_finished * recipe_time) / 3600
  tracked_entities[id].manufacturing_hours = current_hours

  -- Calculate how many upgrade attempts would have occurred in the past
  -- and adjust the chance percentage accordingly
  if current_hours > 0 then
    local hours_needed = quality_multipliers[entity.quality.level]
    local past_attempts = math.floor(current_hours / hours_needed)

    -- Simulate the chance accumulation from missed upgrade attempts
    if past_attempts > 0 and accumulation_percentage > 0 then
      local chance_increase = past_attempts * (base_percentage_chance * accumulation_percentage / 100)
      tracked_entities[id].chance_to_change = tracked_entities[id].chance_to_change + chance_increase
      tracked_entities[id].upgrade_attempts = past_attempts
    end
    -- Not adding credits for past upgrade attempts; it's too hard to balance with secondary entities.
    -- Basically every time you do a quality-control-init it refills the credit pool; for easy upgrade farming
  end
  return tracked_entities[id]
end


function core.scan_and_populate_entities()
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      type = storage.config.all_tracked_types,
      force = game.forces.player
    }

    for _, entity in ipairs(entities) do
      core.get_entity_info(entity)
    end
  end
end

function core.remove_entity_info(id)
  if tracked_entities and tracked_entities[id] then
    local entity_info = tracked_entities[id]

    if entity_info.is_primary then
      storage.primary_entity_count = math.max(0, storage.primary_entity_count - 1)
    else
      storage.secondary_entity_count = math.max(0, storage.secondary_entity_count - 1)
    end

    tracked_entities[id] = nil

    -- O(1) removal using swap-with-last approach
    local index = entity_list_index[id]
    if index then
      local batch_index = storage.batch_index

      local last_index = #entity_list
      local last_unit_number = entity_list[last_index]

      entity_list[index] = last_unit_number
      entity_list_index[last_unit_number] = index

      entity_list[last_index] = nil
      entity_list_index[id] = nil

      if index < batch_index then
        storage.batch_index = batch_index - 1
      end
    end
  end
end

-- Event handlers for entity lifecycle

function core.on_entity_created(event)
  local entity = event.entity
  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_robot_built_entity(event)
  local entity = event.entity
  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_entity_cloned(event)
  local entity = event.destination
  if entity.valid and is_tracked_type[entity.type] and entity.force == game.forces.player then
    core.get_entity_info(entity)
  end
end

function core.on_entity_destroyed(event)
  local entity = event.entity
  if entity and entity.valid and is_tracked_type[entity.type] then
    core.remove_entity_info(entity.unit_number)
  end
end

-- Quality upgrade processing

local function update_module_quality(replacement_entity, target_quality)
  local module_setting = settings.startup["change-modules-with-entity"].value

  if module_setting == "disabled" then
    return
  end

  local module_inventory = replacement_entity.get_module_inventory()
  if not module_inventory then
    return
  end

  for i = 1, #module_inventory do
    local stack = module_inventory[i]

    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local new_module_quality = nil

      if module_setting == "extra-enabled" then
        if current_module_quality.level ~= target_quality.level then
          new_module_quality = target_quality
        end
      elseif module_setting == "enabled" then
        local can_increase = current_module_quality.level < target_quality.level and current_module_quality.next

        if can_increase then
          new_module_quality = current_module_quality.next
        end
      end

      if new_module_quality then
        stack.clear()
        module_inventory.insert({name = module_name, count = 1, quality = new_module_quality.name})
      end
    end
  end
end

local function attempt_upgrade_normal(entity)
  if not entity.valid then
    log("Quality Control ERROR - attempt quality change called with invalid entity. Entity info: " .. (entity and serpent.line(entity) or "nil"))
    return nil
  end

  local entity_info = tracked_entities[entity.unit_number]

  if not entity_info then
    log("Quality Control ERROR - attempt quality change skipped since no entity info was available. Entity: " .. (entity and entity.name or "nil") .. ", unit_number: " .. (entity and entity.unit_number or "nil"))
    return nil
  end

  local random_roll = math.random()
  entity_info.upgrade_attempts = entity_info.upgrade_attempts + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * accumulation_percentage / 100)
    end
    return false
  end

  local unit_number = entity.unit_number
  local entity_type = entity.type
  local entity_name = entity.name
  local entity_surface = entity.surface
  local entity_position = entity.position
  local entity_force = entity.force
  local entity_direction = entity.direction
  local entity_mirroring = entity.mirroring
  local target_quality = entity.quality.next

  script.raise_script_destroy{entity = entity}

  local replacement_entity = entity_surface.create_entity {
    name = entity_name,
    position = entity_position,
    force = entity_force,
    direction = entity_direction,
    quality = target_quality,
    fast_replace = true,
    spill = false,
    raise_built=true,
  }

  if replacement_entity and replacement_entity.valid then
    if entity_mirroring ~= nil then
      replacement_entity.mirroring = entity_mirroring
    end

    core.remove_entity_info(unit_number)
    update_module_quality(replacement_entity, target_quality)
    notifications.show_entity_quality_alert(replacement_entity, target_quality.name)
    return replacement_entity
  else
    log("Quality Control - Unexpected Problem: Entity replacement failed")
    log("  - Entity unit_number: " .. unit_number)
    log("  - Entity type: " .. entity_type)
    log("  - Entity name: " .. entity_name)
    log("  - Target quality: " .. (target_quality and target_quality.name or "nil"))
    local history = prototypes.get_history(entity_type, entity_name)
    if history then
      log("  - From mod: " .. history.created)
    end
    core.remove_entity_info(unit_number)
    return nil
  end
end

local function attempt_upgrade_uncommon(entity)
  if entity.to_be_upgraded() then
    return false
  end

  -- Refresh networks before attempting upgrades to ensure current construction coverage
  local entity_info = update_construction_networks(entity)
  if #entity_info.networks == 0 then
    return false
  end

  -- Find the next available quality across all networks
  local target_quality = get_next_available_quality(entity_info.networks, get_entity_item_name(entity), entity.quality)
  if not target_quality then
    return false
  end

  local random_roll = math.random()
  entity_info.upgrade_attempts = entity_info.upgrade_attempts + 1

  if random_roll >= (entity_info.chance_to_change / 100) then
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * accumulation_percentage / 100)
    end
    return false
  end

  entity.order_upgrade({
    target = {name = entity.name, quality = target_quality},
    force = entity.force
  })

  update_reservations(entity, entity_info.network_ids, get_entity_item_name(entity), target_quality.level, 1)

  -- Handle module upgrades if enabled
  local module_setting = settings.startup["change-modules-with-entity"].value
  if module_setting == "disabled" then
    notifications.show_entity_quality_alert(entity, target_quality.name)
    return true
  end

  local module_inventory = entity.get_module_inventory()
  if not module_inventory then
    notifications.show_entity_quality_alert(entity, target_quality.name)
    return true
  end

  for i = 1, #module_inventory do
    local stack = module_inventory[i]
    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local module_target_quality = get_next_available_quality(entity_info.networks, module_name, current_module_quality)

      if module_target_quality then
        local module_inventory_define = inventory_defines[entity.type]
        local proxy = entity.surface.create_entity({
          name = "item-request-proxy",
          position = entity.position,
          force = entity.force,
          target = entity,
          modules = {{
            id = {name = module_name, quality = module_target_quality.name},
            items = {in_inventory = {{inventory = module_inventory_define, stack = i - 1, count = 1}}}
          }},
          removal_plan = {{
            id = {name = module_name, quality = current_module_quality.name},
            items = {in_inventory = {{inventory = module_inventory_define, stack = i - 1, count = 1}}}
          }}
        })
        update_reservations(proxy, entity_info.network_ids, module_name, module_target_quality.level, 1)
      end
    end
  end

  notifications.show_entity_quality_alert(entity, target_quality.name)
  return true
end


function core.process_upgrade_attempts(entity, attempts_count)
  local quality_changes = {}
  local current_entity = entity

  for _ = 1, attempts_count do
    if current_entity.quality.next == nil then
      break
    end

    local change_result
    if mod_difficulty == "Uncommon" then
      change_result = attempt_upgrade_uncommon(current_entity)
    else
      change_result = attempt_upgrade_normal(current_entity)
    end

    -- Handle errors
    if change_result == nil then
      break
    end

    -- Handle successful upgrades
    if change_result then
      if mod_difficulty == "Uncommon" then
        -- Uncommon mode returns true on success, use current entity
        quality_changes[current_entity.name] = (quality_changes[current_entity.name] or 0) + 1
        break -- Uncommon mode only allows one upgrade per batch
      else
        -- Normal mode returns the new entity on success
        quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
        current_entity = change_result
      end
    end
  end

  return quality_changes
end

function core.process_primary_entity(entity_info, entity)
  local recipe_time = 0
  if entity.get_recipe() then
    recipe_time = entity.get_recipe().prototype.energy
  elseif entity.type == "furnace" and entity.previous_recipe then
    recipe_time = entity.previous_recipe.name.energy
  end

  local hours_needed = quality_multipliers[entity.quality.level]
  local current_hours = (entity.products_finished * recipe_time) / 3600
  local previous_hours = entity_info.manufacturing_hours or 0
  local available_hours = current_hours - previous_hours
  local credits_earned = math.floor(available_hours / hours_needed)

  if credits_earned > 0 then
    local secondary_count = storage.secondary_entity_count
    if secondary_count > 0 then
      local primary_count = storage.primary_entity_count
      local credit_ratio = secondary_count / math.max(primary_count, 1)
      local credits_added = credits_earned * credit_ratio
      storage.accumulated_credits = storage.accumulated_credits + credits_added
    end

    return {
      credits_earned = credits_earned,
      current_hours = current_hours
    }
  end

  return nil
end

function core.process_secondary_entity()
  local accumulated_credits = storage.accumulated_credits
  local secondary_count = storage.secondary_entity_count

  if accumulated_credits > 0 and secondary_count > 0 then
    local credits_per_entity = accumulated_credits / secondary_count
    local credits_earned = math.floor(credits_per_entity)
    local fractional_chance = credits_per_entity - credits_earned

    if fractional_chance > 0 and math.random() < fractional_chance then
      credits_earned = credits_earned + 1
    end

    if credits_earned > 0 then
      storage.accumulated_credits = math.max(0, accumulated_credits - credits_earned)
      return {
        credits_earned = credits_earned,
        current_hours = nil
      }
    end
  end

  return nil
end

function core.update_manufacturing_hours(entity_info, current_hours)
  if tracked_entities[entity_info.entity.unit_number] then
    entity_info.manufacturing_hours = current_hours
  end
end

local function process_upgrade_queue()
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
      update_reservations(nil, queue_item.network_ids, queue_item.name, queue_item.target_quality, -1)
    else
      storage.upgrade_queue_index = storage.upgrade_queue_index + 1
    end

    processed = processed + 1
  end

  if #upgrade_queue == 0 then
    storage.upgrade_queue_index = 1
  end
end

-- Main batch processing loop

function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  local batch_index = storage.batch_index

  while entities_processed < batch_size do
    if batch_index > #entity_list then
      batch_index = 1
      break
    end

    local unit_number = entity_list[batch_index]
    local entity_info = tracked_entities[unit_number]

    if not entity_info or not entity_info.entity or not entity_info.entity.valid then
      core.remove_entity_info(unit_number)
      goto continue
    end

    -- if the entity can change quality still, or
    -- if the entity is primary and accumulate a max quality is on, then we should keep tracking
    local should_stay_tracked = entity_info.entity.quality.next ~= nil or (entity_info.is_primary and accumulate_at_max_quality)
    if not should_stay_tracked then
      core.remove_entity_info(unit_number)
      goto continue
    end

    batch_index = batch_index + 1

    local entity = entity_info.entity

    if entity.to_be_deconstructed() or entity.to_be_upgraded() then
      goto continue
    end

    local result
    if entity_info.is_primary then
      result = core.process_primary_entity(entity_info, entity)
    else
      result = core.process_secondary_entity()
    end

    if result and result.credits_earned > 0 then
      local upgrades = core.process_upgrade_attempts(entity, result.credits_earned)

      local entity_name, count = next(upgrades)
      if entity_name then
        quality_changes[entity_name] = (quality_changes[entity_name] or 0) + count
      elseif entity_info.is_primary then
        -- update hours so that we don't add more credits for the same hours next time
        core.update_manufacturing_hours(entity_info, result.current_hours)
      end
    end

    entities_processed = entities_processed + 1
    ::continue::
  end

  storage.batch_index = batch_index

  if #upgrade_queue > 0 then
    process_upgrade_queue()
  end

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes)
  end
end

-- Quality testing functions for file size experiments

function core.set_all_entities_quality_level(target_level)
  local target_quality = prototypes.quality["normal"]
  while target_quality and target_quality.level < target_level do
    target_quality = target_quality.next
  end

  if not target_quality then
    return false, "Quality level " .. target_level .. " not found"
  end

  local changed_count = 0

  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{force = game.forces.player}

    for _, entity in ipairs(entities) do
      if entity.valid and entity.quality.level ~= target_level and not should_exclude_entity(entity) and is_tracked_type[entity.type] then
        local entity_name = entity.name
        local entity_surface = entity.surface
        local entity_position = entity.position
        local entity_force = entity.force
        local entity_direction = entity.direction
        local entity_mirroring = entity.mirroring

        local replacement_entity = entity_surface.create_entity {
          name = entity_name,
          position = entity_position,
          force = entity_force,
          direction = entity_direction,
          quality = target_quality,
          fast_replace = true,
          spill = false,
        }

        if replacement_entity and replacement_entity.valid then
          if entity_mirroring ~= nil then
            replacement_entity.mirroring = entity_mirroring
          end
          changed_count = changed_count + 1
        end
      end
    end
  end

  return true, "Changed " .. changed_count .. " entities to quality level " .. target_level .. " (" .. target_quality.name .. ")"
end

function core.set_all_entities_quality(target_quality_name)
  local target_quality = prototypes.quality[target_quality_name]
  storage.quality_control_current_test_quality = target_quality_name
  return core.set_all_entities_quality_level(target_quality.level)
end

function core.get_current_test_quality()
  return storage.quality_control_current_test_quality or "normal"
end

function core.increment_test_quality()
  local current_quality_name = core.get_current_test_quality()
  local current_quality = prototypes.quality[current_quality_name]

  if current_quality and current_quality.next then
    local next_quality = current_quality.next
    storage.quality_control_current_test_quality = next_quality.name
    return core.set_all_entities_quality(next_quality.name)
  else
    return false, "Already at maximum quality: " .. current_quality_name
  end
end

return core