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
local quality_limit = nil
local is_tracked_type = {}
local mod_difficulty = nil
local quality_multipliers = {}
local accumulate_at_max_quality = nil
local base_percentage_chance = nil
local accumulation_percentage = nil
local item_count_cache = {}

-- Entities from these mods don't fast_replace well, so for now exclude them
local excluded_mods_lookup = {
    ["Warp-Drive-Machine"] = true,
    ["quality-condenser"] = true,
    ["RealisticReactorsReborn"] = true,
    ["railloader2-patch"] = true,
    ["router"] = true,
    ["fct-ControlTech"] = true, -- patch requested, may be able to remove once they are greater than version 2.0.5
    ["ammo-loader"] = true,
    ["miniloader-redux"] = true
  }

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  quality_limit = storage.config.quality_limit
  is_tracked_type = storage.config.is_tracked_type
  mod_difficulty = storage.config.mod_difficulty
  quality_multipliers = storage.quality_multipliers
  item_count_cache = storage.item_count_cache
  accumulate_at_max_quality = settings_data.accumulate_at_max_quality
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
end

-- Exclude entities that don't work well with fast_replace or should be excluded
local function should_exclude_entity(entity)
  if not entity.prototype.selectable_in_game then
    return true
  end

  if not entity.destructible then
    return true
  end

  -- Check if entity is from an excluded mod
  local history = prototypes.get_history(entity.type, entity.name)
  if history and excluded_mods_lookup[history.created] then
    return true
  end

  return false
end

local function update_item_cache(network, item_name, quality)
  local item_with_quality = {name = item_name, quality = quality}
  local available_count = network.get_item_count(item_with_quality)

  -- update the cache with the current count
  local network_id = network.network_id
  if not item_count_cache[network_id] then
    item_count_cache[network_id] = {}
  end
  if not item_count_cache[network_id][item_name] then
    item_count_cache[network_id][item_name] = {}
  end

  local item_count = item_count_cache[network_id][item_name][quality.level]

  if item_count then
    item_count.available = available_count
  else
    item_count_cache[network_id][item_name][quality.level] = {
      available = available_count,
      reserved = 0
    }
  end

  return item_count
end

local function get_next_available_quality(network, item_name, current_quality)
  local next_quality = current_quality.next
  -- keep this check as a user could insert max quality modules and we don't check those ahead of time
  if not next_quality then
    return nil
  end

  local item_count = update_item_cache(network, item_name, next_quality)
  if item_count and (item_count.available - item_count.reserved) > 0 then
    return next_quality
  end

  -- scan the cache for any available quality
  next_quality = next_quality.next
  while next_quality do
    item_count = item_count_cache[network.network_id][item_name][next_quality.level]
    if item_count and (item_count.available - item_count.reserved) > 0 then
      return next_quality
    end
    next_quality = next_quality.next
  end

  return nil
end

function core.get_entity_info(entity)
  local id = entity.unit_number

  local can_change_quality = entity.quality.next ~= nil
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities with accumulation enabled
  local should_track = can_change_quality or (is_primary and accumulate_at_max_quality)
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
    upgrade_attempts = 0
  }

  -- Check if entity is being upgraded and add to upgrade tracking queue
  if mod_difficulty == "Uncommon" and entity.to_be_upgraded() and entity.logistic_network then
    local target = entity.get_upgrade_target()
    local network = entity.logistic_network
    local network_id = network.network_id

    -- Update cache and add reservation
    local items = update_item_cache(network, entity.name, target.quality)
    items.reserved = items.reserved + 1

    -- Add to queue
    table.insert(storage.upgrade_queue, {
      entity = entity,
      entity_network_id = network_id,
      entity_name = entity.name,
      entity_target_quality_level = target.quality.level
    })
  end

  if is_primary then
    storage.primary_entity_count = storage.primary_entity_count + 1
  else
    storage.secondary_entity_count = storage.secondary_entity_count + 1
  end

  -- Use ordered list for O(1) lookup in batch processing
  table.insert(storage.entity_list, id)
  storage.entity_list_index[id] = #storage.entity_list

  if is_primary then
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
      local entity_info = core.get_entity_info(entity)

      -- Populate item count cache for entities with logistic networks (only when not in Normal difficulty)
      -- Only do this for entities that are actually being tracked (entity_info has .entity field)
      if mod_difficulty ~= "Normal" and entity_info.entity and entity.logistic_network then
        local network = entity.logistic_network
        local network_id = network.network_id

        if entity.quality.next then
          local next_quality = entity.quality.next
          -- Only update cache if we haven't already checked this network/item/quality combo
          if not (item_count_cache[network_id] and
                  item_count_cache[network_id][entity.name] and
                  item_count_cache[network_id][entity.name][next_quality.level] ~= nil) then
            update_item_cache(network, entity.name, next_quality)
          end
        end

        -- Also populate cache for modules if entity has module inventory
        local module_inventory = entity.get_module_inventory()
        if module_inventory then
          for i = 1, #module_inventory do
            local stack = module_inventory[i]
            if stack.valid_for_read and stack.is_module and stack.quality.next then
              local next_quality = stack.quality.next
              -- Only update cache if we haven't already checked this network/item/quality combo
              if not (item_count_cache[network_id] and
                      item_count_cache[network_id][stack.name] and
                      item_count_cache[network_id][stack.name][next_quality.level] ~= nil) then
                update_item_cache(network, stack.name, next_quality)
              end
            end
          end
        end
      end
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
    local index = storage.entity_list_index[id]
    if index then
      local entity_list = storage.entity_list
      local batch_index = storage.batch_index

      local last_index = #entity_list
      local last_unit_number = entity_list[last_index]

      entity_list[index] = last_unit_number
      storage.entity_list_index[last_unit_number] = index

      entity_list[last_index] = nil
      storage.entity_list_index[id] = nil

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
    notifications.show_entity_quality_alert(replacement_entity)
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
  if entity.to_be_upgraded() or not entity.logistic_network then
    return false
  end

  local network = entity.logistic_network
  local entity_info = tracked_entities[entity.unit_number]

  -- Find the next available quality in the network
  local target_quality = get_next_available_quality(network, entity.name, entity.quality)
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

  -- update reservations
  local items = item_count_cache[network.network_id][entity.name][target_quality.level]
  items.reserved = items.reserved + 1

  entity.order_upgrade({
    target = {name = entity.name, quality = target_quality},
    force = entity.force
  })

  -- add to reservation queue
  table.insert(storage.upgrade_queue, {
    entity = entity,
    entity_network_id = network.network_id,
    entity_name = entity.name,
    entity_target_quality_level = target_quality.level
  })

  -- Handle module upgrades if enabled
  local module_setting = settings.startup["change-modules-with-entity"].value
  if module_setting == "disabled" then
    notifications.show_entity_quality_alert(entity)
    return true
  end

  local module_inventory = entity.get_module_inventory()
  if not module_inventory then
    notifications.show_entity_quality_alert(entity)
    return true
  end

  for i = 1, #module_inventory do
    local stack = module_inventory[i]
    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local module_target_quality = get_next_available_quality(network, module_name, current_module_quality)

      if module_target_quality then
        entity.order_upgrade({
          force = entity.force,
          target = {name = module_name, quality = module_target_quality}
        })
      end
    end
  end

  notifications.show_entity_quality_alert(entity)
  return true
end


function core.process_upgrade_attempts(entity, attempts_count)
  local quality_changes = {}
  local current_entity = entity

  for _ = 1, attempts_count do
    local change_result
    if mod_difficulty == "Uncommon" then
      change_result = attempt_upgrade_uncommon(current_entity)
    else
      change_result = attempt_upgrade_normal(current_entity)
    end

    if change_result == nil then
      -- we ran into an error, just return instead of continuing
      break
    end

    if change_result and mod_difficulty == "Normal" then
      current_entity = change_result
      quality_changes[change_result.name] = (quality_changes[change_result.name] or 0) + 1
      if current_entity.quality == quality_limit then
        break
      end
    elseif change_result and mod_difficulty == "Uncommon" then
      quality_changes[current_entity.name] = (quality_changes[current_entity.name] or 0) + 1
      break
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
  local queue = storage.upgrade_queue
  local batch_size = settings.global["batch-entities-per-tick"].value
  local processed = 0
  local start_index = storage.upgrade_queue_index

  while processed < batch_size and #queue > 0 do
    if storage.upgrade_queue_index > #queue then
      storage.upgrade_queue_index = 1

      if storage.upgrade_queue_index >= start_index then
        break
      end
    end

    local queue_item = queue[storage.upgrade_queue_index]
    local entity = queue_item.entity

    if not entity.valid or not entity.to_be_upgraded() then
      table.remove(queue, storage.upgrade_queue_index)

      local items = item_count_cache[queue_item.entity_network_id] and
                   item_count_cache[queue_item.entity_network_id][queue_item.entity_name] and
                   item_count_cache[queue_item.entity_network_id][queue_item.entity_name][queue_item.entity_target_quality_level]
      if items then
        items.reserved = math.max(0, items.reserved - 1)
      end
    else
      storage.upgrade_queue_index = storage.upgrade_queue_index + 1
    end

    processed = processed + 1
  end

  if #queue == 0 then
    storage.upgrade_queue_index = 1
  end
end

-- Main batch processing loop

function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local entities_processed = 0
  local quality_changes = {}

  local batch_index = storage.batch_index
  local entity_list = storage.entity_list

  while entities_processed < batch_size do
    if batch_index > #entity_list then
      batch_index = 1
      break
    end

    local unit_number = entity_list[batch_index]
    batch_index = batch_index + 1

    local entity_info = tracked_entities[unit_number]
    -- if the entity is primary and accumulate a max quality is on, then we should keep tracking
    -- or if the entity can change quality still
    local should_stay_tracked = entity_info and
      (entity_info.entity.quality.next ~= nil or
      (entity_info.is_primary and accumulate_at_max_quality))

    if not entity_info or not entity_info.entity or not entity_info.entity.valid or not should_stay_tracked then
      core.remove_entity_info(unit_number)
      goto continue
    end

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

  if #storage.upgrade_queue > 0 then
    process_upgrade_queue()
  end

  if next(quality_changes) then
    notifications.show_quality_notifications(quality_changes)
  end
end

return core