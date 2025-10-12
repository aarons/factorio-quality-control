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
local quality_multipliers = {}
local base_percentage_chance = nil
local accumulation_percentage = nil
local batch_process_queue = {}
local batch_process_queue_index = {}
local module_upgrade_setting = "disabled"

-- Entities from these mods don't fast_replace well, so for now exclude them
local excluded_mods_lookup = {
    ["ammo-loader"] = true,
    ["fct-ControlTech"] = true, -- patch requested, may be able to remove once they are greater than version 2.0.5
    ["miniloader-redux"] = true,
    ["quality-condenser"] = true,
    ["railloader2-patch"] = true,
    ["RealisticReactorsReborn"] = true,
    ["router"] = true,
    ["Warp-Drive-Machine"] = true,
  }

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
  quality_multipliers = storage.quality_multipliers
  batch_process_queue = storage.batch_process_queue
  batch_process_queue_index = storage.batch_process_queue_index
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
  module_upgrade_setting = settings_data.change_modules_with_entity
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

  -- exclude entities in a blueprint sandbox
  if string.sub(entity.surface.name, 1, 5) == "bpsb-" then
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


function core.get_entity_info(entity)
  local id = entity.unit_number
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities (they always accumulate)
  local should_track = entity.quality.next ~= nil or is_primary
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
    chance_to_change = base_percentage_chance
  }

  -- Use ordered list for O(1) lookup in batch processing
  table.insert(batch_process_queue, id)
  batch_process_queue_index[id] = #batch_process_queue

  -- Add to upgradeable set if entity can still be upgraded
  if entity.quality.next ~= nil and not storage.upgradeable_entities[id] then
    storage.upgradeable_entities[id] = true
    storage.upgradeable_count = storage.upgradeable_count + 1
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
  if tracked_entities[id] then
    tracked_entities[id] = nil

    -- Remove from upgradeable set if present
    if storage.upgradeable_entities[id] then
      storage.upgradeable_entities[id] = nil
      storage.upgradeable_count = storage.upgradeable_count - 1
    end

    -- O(1) removal using swap-with-last approach
    local index = batch_process_queue_index[id]
    if index then
      local last_index = #batch_process_queue
      local last_unit_number = batch_process_queue[last_index]

      batch_process_queue[index] = last_unit_number
      batch_process_queue_index[last_unit_number] = index

      batch_process_queue[last_index] = nil
      batch_process_queue_index[id] = nil
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
  core.remove_entity_info(event.entity.unit_number)
end


local function update_module_quality(entity)
  if module_upgrade_setting == "disabled" then
    return
  end

  local module_inventory = entity.get_module_inventory()
  if not module_inventory then
    return
  end

  local target_quality = entity.quality

  for i = 1, #module_inventory do
    local stack = module_inventory[i]

    if stack.valid_for_read and stack.is_module then
      local module_name = stack.name
      local current_module_quality = stack.quality
      local new_module_quality = nil

      if module_upgrade_setting == "extra-enabled" then
        if current_module_quality.level < target_quality.level then
          new_module_quality = target_quality
        end
      elseif module_upgrade_setting == "enabled" then
        if current_module_quality.level < target_quality.level then
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

local function attempt_upgrade_normal(entity, credits)
  local entity_info = tracked_entities[entity.unit_number]

  -- determine the chance that an upgrade will succeed
  -- if 1% base rate chance to change x 3 credits => 3% to change
  -- if 1% base rate chance to change x 0.2 credits => 0.2% chance to change
  local chance_to_change = (entity_info.chance_to_change / 100) * credits

  if math.random() >= chance_to_change then -- we failed the upgrade attempt
    entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * (accumulation_percentage / 100) * credits)
    return false
  end

  local marked_for_upgrade = entity.order_upgrade({
    target = {name = entity.name, quality = entity.quality.next},
    force = entity.force
  })

  -- whether mark for upgrade succeeds or fails, we should remove the old entity from tracking
  -- if it failed: then we shouldn't try to upgrade it again as something went wrong
  -- if it succeeded, then we are about to replace the entity with the new upgrade
  core.remove_entity_info(entity.unit_number)
  if not marked_for_upgrade then
    return false
  end

  local old_entity_energy = entity.energy

  -- apply_upgrade can return up to two entities
  -- not sure when we would get multiple entities back
  local new_entity_1, _ = entity.apply_upgrade()
  if new_entity_1 then
    new_entity_1.energy = old_entity_energy
    update_module_quality(new_entity_1)
    notifications.show_entity_quality_alert(new_entity_1, new_entity_1.quality.name)
  end

  return true
end


function core.process_upgrade_attempts(entity, credits)
  local entity_name = entity.name
  local entity_upgraded = attempt_upgrade_normal(entity, credits)

  if entity_upgraded then
    local upgrade_info = {[entity_name] = 1}
    notifications.show_quality_notifications(upgrade_info)
    return(upgrade_info)
  else
    return {}
  end
end


function core.update_credits(entity_info, entity)
  local credits_earned = 0

  -- Primary entities generate credits from manufacturing hours
  if entity_info.is_primary then
    local recipe_time = 0
    if entity.get_recipe() then
      recipe_time = entity.get_recipe().prototype.energy
    elseif entity.type == "furnace" and entity.previous_recipe then
      recipe_time = entity.previous_recipe.name.energy
    end

    local hours_needed = quality_multipliers[entity.quality.level]
    local current_hours = (entity.products_finished * recipe_time) / 3600
    local previous_hours = entity_info.manufacturing_hours or 0
    local new_hours = current_hours - previous_hours
    credits_earned = (new_hours / hours_needed)
    -- increment accumulated credits for all entities
    storage.accumulated_credits = storage.accumulated_credits + credits_earned
    entity_info.manufacturing_hours = current_hours
  end

  -- add shared credits
  credits_earned = credits_earned + storage.credits_per_entity
  return credits_earned
end
-- Main batch processing loop

function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local batch_index = storage.batch_index
  local entities_processed = 0

  while entities_processed < batch_size do
    entities_processed = entities_processed + 1
    if batch_index > #batch_process_queue then
      -- setup next batch
      batch_index = 1
      storage.credits_per_entity = storage.accumulated_credits / math.max(1, storage.upgradeable_count)
      storage.acumulated_credits = 0
      break
    end

    batch_index = batch_index + 1

    local unit_number = batch_process_queue[batch_index]
    local entity_info = tracked_entities[unit_number]
    local entity = entity_info and entity_info.entity

    if not entity or not entity.valid then
      core.remove_entity_info(unit_number)
      goto continue
    end

    -- check if radar has reached it's limit
    if entity.type == "radar" and entity.quality.level >= (settings_data.radar_growth_level_limit - 1) then
      core.remove_entity_info(unit_number)
      goto continue
    end

    -- check if lightning attractor has reached it's limit
    if entity.type == "lightning-attractor" and entity.quality.level >= (settings_data.lightning_attractor_growth_level_limit - 1) then
      core.remove_entity_info(unit_number)
      goto continue
    end

    if entity.to_be_deconstructed() or entity.to_be_upgraded() then
      goto continue
    end

    if entity.quality.next == nil then
      -- it's a primary entity that just needs to accumulate credits
      core.update_credits(entity_info, entity)
    else
      local credits_earned = core.update_credits(entity_info, entity)
      core.process_upgrade_attempts(entity, credits_earned)
    end

    ::continue::
  end

  storage.batch_index = batch_index
end

return core