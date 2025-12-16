--[[
core.lua

Core processing engine for Quality Control mod.
Handles entity quality management, credit system, and main processing loop.
Combines upgrade processing, entity tracking, and batch processing functionality.
]]

local notifications = require("scripts.notifications")
local core = {}

-- Quality bucket system for probability-based quality selection
local BUCKET_COUNT = 1000
local quality_buckets = {}
local skip_hidden_qualities = false
local sticky_hidden_qualities = true

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
local module_upgrade_setting = "disabled"

-- Build a bucket array for a single starting quality
-- Each bucket contains a target quality name, distributed according to next_probability
local function build_bucket_array(start_quality)
  local buckets = {}
  local idx = 1
  local remaining_prob = 1.0
  local current = start_quality.next

  -- Walk chain until terminal quality or probability exhausted
  while current and current.next and remaining_prob >= 0.0001 do
    -- Skip hidden qualities if setting enabled
    -- IMPORTANT: Do NOT apply the hidden quality's probability - pretend it doesn't exist
    if skip_hidden_qualities and current.hidden then
      current = current.next
    else
      -- Clamp next_probability to valid range (protect against buggy mods)
      local continue_prob = math.max(0, math.min(1, current.next_probability or 0.1))
      local stop_prob = 1 - continue_prob

      -- Minimum 1 bucket ensures rare outcomes remain possible
      local bucket_count = math.max(1, math.floor(remaining_prob * stop_prob * BUCKET_COUNT + 0.5))

      -- Don't exceed remaining buckets
      bucket_count = math.min(bucket_count, BUCKET_COUNT - idx + 1)

      for _ = 1, bucket_count do
        buckets[idx] = current.name
        idx = idx + 1
      end

      remaining_prob = remaining_prob * continue_prob
      current = current.next
    end
  end

  -- Terminal quality gets remaining buckets
  if current then
    -- If terminal is hidden and we're skipping, find next non-hidden
    if skip_hidden_qualities and current.hidden then
      while current and current.hidden do
        current = current.next
      end
    end

    if current then
      while idx <= BUCKET_COUNT do
        buckets[idx] = current.name
        idx = idx + 1
      end
    end
  end

  return buckets
end

-- Precompute quality bucket lookup tables for all qualities
-- Called at init and on configuration change
function core.precompute_quality_buckets()
  quality_buckets = {}

  for name, quality in pairs(prototypes.quality) do
    -- Terminal quality: no upgrade path
    if not quality.next then
      quality_buckets[name] = nil
    -- Sticky hidden: shiny entities don't upgrade
    elseif sticky_hidden_qualities and quality.hidden then
      quality_buckets[name] = nil
    else
      quality_buckets[name] = build_bucket_array(quality)
    end
  end
end

-- Get the next quality for an upgrade using probability-weighted bucket selection
-- Returns nil if no upgrade path exists (terminal quality, sticky hidden, or empty buckets)
local function next_quality(current_quality_name)
  local buckets = quality_buckets[current_quality_name]
  if not buckets or buckets[1] == nil then return nil end -- Terminal, sticky hidden, or empty
  return buckets[math.random(1, BUCKET_COUNT)]
end

-- Check if a quality has any upgrade path (for tracking decisions)
local function has_upgrade_path(quality_name)
  local buckets = quality_buckets[quality_name]
  return buckets ~= nil and buckets[1] ~= nil
end

local module_identifiers = {
  ["agricultural-tower"] = defines.inventory.crafter_modules,
  ["assembling-machine"] = defines.inventory.crafter_modules,
  ["beacon"] = defines.inventory.beacon_modules,
  ["furnace"] = defines.inventory.crafter_modules,
  ["lab"] = defines.inventory.lab_modules,
  ["mining-drill"] = defines.inventory.mining_drill_modules
}

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
  mod_difficulty = storage.config.mod_difficulty
  quality_multipliers = storage.quality_multipliers
  network_inventory = storage.network_inventory
  entity_list = storage.entity_list
  entity_list_index = storage.entity_list_index
  upgrade_queue = storage.upgrade_queue
  accumulate_at_max_quality = settings_data.accumulate_at_max_quality
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
  module_upgrade_setting = settings_data.change_modules_with_entity
  skip_hidden_qualities = settings_data.skip_hidden_qualities
  sticky_hidden_qualities = settings_data.sticky_hidden_qualities

  -- Precompute quality buckets for probability-based upgrades
  core.precompute_quality_buckets()
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
  local next_qual = current_quality.next
  -- keep this check as a user could insert max quality modules and we don't check those ahead of time
  if not next_qual then
    return nil
  end

  update_network_inventory(networks, item_name, next_qual)

  -- Scan for next available quality across networks the entity is covered by
  while next_qual do
    -- Skip hidden qualities if setting enabled
    if not (skip_hidden_qualities and next_qual.hidden) then
      for _, network in ipairs(networks) do
        local network_id = network.network_id
        if network_inventory[network_id] and
           network_inventory[network_id][item_name] and
           network_inventory[network_id][item_name][next_qual.level] then
          local item_count = network_inventory[network_id][item_name][next_qual.level]
          if item_count.available - item_count.reserved > 0 then
            return next_qual
          end
        end
      end
    end
    next_qual = next_qual.next
  end

  return nil
end


function core.get_entity_info(entity)
  local id = entity.unit_number
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace")

  -- Only track entities that can change quality OR are primary entities with accumulation enabled
  -- Use has_upgrade_path to respect hidden quality settings
  local can_upgrade = has_upgrade_path(entity.quality.name)
  local should_track = can_upgrade or (is_primary and accumulate_at_max_quality)
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
  local target_quality = next_quality(entity_quality)
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

local function attempt_upgrade_uncommon(entity, upgrade_credit)
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

  local chance_to_change = (entity_info.chance_to_change / 100) * upgrade_credit

  if math.random() >= chance_to_change then
    if accumulation_percentage > 0 then
      entity_info.chance_to_change = entity_info.chance_to_change + (base_percentage_chance * (accumulation_percentage / 100) * upgrade_credit)
    end
    return false
  end

  local marked_for_upgrade = entity.order_upgrade({
    target = {name = entity.name, quality = target_quality},
    force = entity.force
  })

  if not marked_for_upgrade then
    -- there was an issue with upgrading this entity, stop tracking it to prevent future issues
    core.remove_entity_info(entity.unit_number)
    return false
  end

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
        local module_inventory_define = module_identifiers[entity.type]
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
  local entity_name = entity.name
  local entity_upgraded

  if mod_difficulty == "Uncommon" then
    entity_upgraded = attempt_upgrade_uncommon(entity, attempts_count)
  else
    entity_upgraded = attempt_upgrade_normal(entity, attempts_count)
  end

  if entity_upgraded then
    return {[entity_name] = 1}
  end

  return {}
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

    if not entity_info or not entity or not entity.valid then
      core.remove_entity_info(unit_number)
      goto continue
    end

    -- Use has_upgrade_path to respect hidden quality settings
    local can_still_upgrade = has_upgrade_path(entity.quality.name)

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

    if result and can_still_upgrade and result.credits_earned > 0 then
      local upgrades = core.process_upgrade_attempts(entity, result.credits_earned)

      local entity_name, count = next(upgrades)
      if entity_name then
        entities_upgraded[entity_name] = (entities_upgraded[entity_name] or 0) + count
      elseif entity_info.is_primary then
        -- it wasn't upgraded and is a primary entity
        -- update hours so that we don't add more credits for the same hours next time
        entity_info.manufacturing_hours = result.current_hours
      end
    end

    ::continue::
  end

  storage.batch_index = batch_index

  if #upgrade_queue > 0 then
    process_upgrade_queue()
  end

  if next(entities_upgraded) then
    notifications.show_quality_notifications(entities_upgraded)
  end
end

return core