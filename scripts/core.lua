--[[
core.lua

Core processing engine for Quality Control mod.
Handles entity quality management, credit system, and main processing loop.
Combines upgrade processing, entity tracking, and batch processing functionality.
]]

local notifications = require("scripts.notifications")
local quality_selector = require("scripts.quality_selector")
local exclusions = require("scripts.exclusions")
local core = {}

local tracked_entities = {}
local settings_data = {}
local is_tracked_type = {}
local quality_multipliers = {}
local accumulate_at_max_quality = nil
local base_percentage_chance = nil
local accumulation_percentage = nil
local entity_list = {}
local entity_list_index = {}
local module_upgrade_setting = "disabled"

local function get_recipe_time(entity)
  if entity.get_recipe() then
    return entity.get_recipe().prototype.energy
  elseif entity.type == "furnace" and entity.previous_recipe then
    return entity.previous_recipe.name.energy
  end
  return 0
end

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
  quality_multipliers = storage.quality_multipliers
  entity_list = storage.entity_list
  entity_list_index = storage.entity_list_index
  accumulate_at_max_quality = settings_data.accumulate_at_max_quality
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
  module_upgrade_setting = settings_data.change_modules_with_entity

  -- Initialize quality selector with settings
  quality_selector.initialize(
    settings_data.skip_hidden_qualities,
    settings_data.sticky_hidden_qualities
  )
end


function core.get_entity_info(entity)
  local id = entity.unit_number
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities with accumulation enabled
  local can_upgrade = quality_selector.has_upgrade_path(entity.quality.name)
  local should_track = can_upgrade or (is_primary and accumulate_at_max_quality)
  if not should_track then
    return "at max quality"
  end

  if tracked_entities[id] then
    return tracked_entities[id]
  end

  -- entity is not tracked; so we're adding a new entity
  -- first check if it's something we should track:
  if exclusions.should_exclude_entity(entity) then
    return "entity excluded from quality control"
  end

  tracked_entities[id] = {
    entity = entity,
    is_primary = is_primary,
    chance_to_change = base_percentage_chance
  }

  if is_primary then
    storage.primary_entity_count = storage.primary_entity_count + 1
  else
    storage.secondary_entity_count = storage.secondary_entity_count + 1
  end

  -- Use ordered list for O(1) lookup in batch processing
  table.insert(entity_list, id)
  entity_list_index[id] = #entity_list

  if not is_primary then
    -- all done with secondary entity processing, ok to return
    return tracked_entities[id]
  end

  -- Initialize manufacturing hours based on current products_finished
  -- This ensures we don't double-count hours for already-producing entities
  local current_hours = (entity.products_finished * get_recipe_time(entity)) / 3600
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
      local last_index = #entity_list
      local last_unit_number = entity_list[last_index]

      entity_list[index] = last_unit_number
      entity_list_index[last_unit_number] = index

      entity_list[last_index] = nil
      entity_list_index[id] = nil
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

local function attempt_upgrade_normal(entity, upgrade_credit)
  -- Capture entity info upfront before any API calls that might invalidate the entity
  local unit_number = entity.unit_number
  local entity_name = entity.name
  local entity_type = entity.type
  local entity_quality = entity.quality.name
  local entity_force = entity.force.name
  local entity_surface = entity.surface.name
  local entity_info = tracked_entities[unit_number]

  -- Select target quality using probability-weighted bucket system
  local target_quality = quality_selector.get_next_quality(entity_quality)
  if not target_quality then return false end -- No upgrade path (terminal or sticky hidden)

  -- determine the chance that an upgrade will succeed
  -- if 1% base rate chance to change x 3 credits => 3% to change
  -- if 1% base rate chance to change x 0.2 credits => 0.2% chance to change
  local chance_to_change = (entity_info.chance_to_change / 100) * upgrade_credit

  if math.random() >= chance_to_change then -- we failed the upgrade attempt
    entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * (accumulation_percentage / 100) * upgrade_credit)
    return false
  end

  local marked_for_upgrade = entity.order_upgrade({
    target = {name = entity_name, quality = target_quality},
    force = entity.force
  })

  -- whether mark for upgrade succeeds or fails, we should remove the old entity from tracking
  -- if it failed: then we shouldn't try to upgrade it again as something went wrong
  -- if it succeeded, then we are about to replace the entity with the new upgrade
  core.remove_entity_info(unit_number)
  if not marked_for_upgrade then
    return false
  end

  -- TEMPORARY DIAGNOSTIC: Log if entity became invalid after order_upgrade
  -- This helps identify what causes the "LuaEntity was invalid" error
  if not entity.valid then
    log("[Quality Control] Entity became invalid after order_upgrade! " ..
        "unit_number=" .. tostring(unit_number) ..
        ", name=" .. tostring(entity_name) ..
        ", type=" .. tostring(entity_type) ..
        ", quality=" .. tostring(entity_quality) ..
        ", target_quality=" .. tostring(target_quality) ..
        ", force=" .. tostring(entity_force) ..
        ", surface=" .. tostring(entity_surface) ..
        ", is_primary=" .. tostring(entity_info.is_primary) ..
        ", marked_for_upgrade=" .. tostring(marked_for_upgrade))
    return true  -- Entity was removed, tracking already cleaned up
  end

  local old_entity_energy = entity.energy
  local old_always_on = nil
  if entity.type == "lamp" then
    old_always_on = entity.always_on
  end

  -- apply_upgrade can return up to two entities
  -- not sure when we would get multiple entities back, but in this case we just need to
  -- handle modules and stored energy
  local new_entity_1, _ = entity.apply_upgrade()
  if new_entity_1 then
    -- successfully upgraded into at least 1 entity
    new_entity_1.energy = old_entity_energy
    if old_always_on ~= nil then
      new_entity_1.always_on = old_always_on
    end
    update_module_quality(new_entity_1)
  end

  return true
end


function core.process_primary_entity(entity_info, entity)
  local hours_needed = quality_multipliers[entity.quality.level]
  local current_hours = (entity.products_finished * get_recipe_time(entity)) / 3600
  local previous_hours = entity_info.manufacturing_hours or 0
  local hours_worked = current_hours - previous_hours
  local credits_earned = hours_worked / hours_needed

  storage.accumulated_credits = storage.accumulated_credits + credits_earned

  return {
    credits_earned = credits_earned,
    current_hours = current_hours
  }
end

function core.process_secondary_entity()
  local accumulated_credits = storage.accumulated_credits
  local secondary_count = storage.secondary_entity_count

  secondary_count = math.max(secondary_count, 1) -- this shouldn't be necessary but gaurantee's the division is always safe
  local credits_earned = accumulated_credits / secondary_count
  storage.accumulated_credits = math.max(0, accumulated_credits - credits_earned)

  return {
    credits_earned = credits_earned,
    current_hours = nil
  }
end

-- Main batch processing loop

function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local batch_index = storage.batch_index
  local entities_processed = 0
  local entities_upgraded = {}

  while entities_processed < batch_size do
    entities_processed = entities_processed + 1
    if batch_index > #entity_list then
      batch_index = 1
      break
    end

    local unit_number = entity_list[batch_index]
    local entity_info = tracked_entities[unit_number]
    local entity = entity_info.entity

    if not entity or not entity.valid then
      core.remove_entity_info(unit_number)
      goto continue
    end

    local can_still_upgrade = quality_selector.has_upgrade_path(entity.quality.name)

    -- check if radar has reached it's limit
    if entity.type == "radar" and can_still_upgrade then
      if entity.quality.level >= (settings_data.radar_growth_level_limit - 1) then
        can_still_upgrade = false
      end
    end

    -- check if lightning attractor has reached it's limit
    if entity.type == "lightning-attractor" and can_still_upgrade then
      if entity.quality.level >= (settings_data.lightning_attractor_growth_level_limit - 1) then
        can_still_upgrade = false
      end
    end

    -- if the entity is primary and accumulate a max quality is on, then we should keep tracking
    local should_stay_tracked = can_still_upgrade or (entity_info.is_primary and accumulate_at_max_quality)
    if not should_stay_tracked then
      core.remove_entity_info(unit_number)
      goto continue
    end

    batch_index = batch_index + 1

    if entity.to_be_deconstructed() or entity.to_be_upgraded() then
      goto continue
    end

    local result
    if entity_info.is_primary then
      result = core.process_primary_entity(entity_info, entity)
    else
      result = core.process_secondary_entity()
    end

    if can_still_upgrade and result.credits_earned > 0 then
      local entity_name = entity.name
      local entity_upgraded = attempt_upgrade_normal(entity, result.credits_earned)

      if entity_upgraded then
        entities_upgraded[entity_name] = (entities_upgraded[entity_name] or 0) + 1
      elseif entity_info.is_primary then
        -- it wasn't upgraded and is a primary entity
        -- update hours so that we don't add more credits for the same hours next time
        entity_info.manufacturing_hours = result.current_hours
      end
    end

    ::continue::
  end

  storage.batch_index = batch_index

  if next(entities_upgraded) then
    notifications.show_quality_notifications(entities_upgraded)
  end
end

return core