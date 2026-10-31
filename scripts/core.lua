--[[
core.lua

Core processing engine for Quality Control mod.
Handles entity quality management, credit system, and main processing loop.
Combines upgrade processing, entity tracking, and batch processing functionality.
]]

local notifications = require("scripts.notifications")
local progression = require("scripts.progression")
local quality_selector = require("scripts.quality_selector")
local exclusions = require("scripts.exclusions")
local module_upgrades = require("scripts.module_upgrades")
local core = {}

local tracked_entities = {}
local settings_data = {}
local is_tracked_type = {}
local can_attempt_quality_change = {}
local upgrade_limit_levels = {}
local quality_multipliers = {}
local turrets_contribute_credits = nil
local base_percentage_chance = nil
local accumulation_percentage = nil
local entity_list = {}
local entity_list_index = {}
local module_upgrade_setting = "disabled"

local turret_types = {
  ["turret"] = true, ["ammo-turret"] = true, ["electric-turret"] = true,
  ["fluid-turret"] = true, ["artillery-turret"] = true,
}

-- A primary deposits credits into its surface meter unless it is an isolated
-- turret (Turrets Contribute Credits disabled). The meter's divisor counts only
-- depositing primaries, so isolated turrets never dilute secondary progression.
local function feeds_surface_meter(is_primary, is_turret)
  return is_primary and (not is_turret or turrets_contribute_credits)
end

function core.initialize()
  tracked_entities = storage.quality_control_entities
  settings_data = storage.config.settings_data
  is_tracked_type = storage.config.is_tracked_type
  can_attempt_quality_change = storage.config.can_attempt_quality_change
  upgrade_limit_levels = storage.config.upgrade_limit_levels
  quality_multipliers = storage.quality_multipliers
  entity_list = storage.entity_list
  entity_list_index = storage.entity_list_index
  turrets_contribute_credits = settings_data.turrets_contribute_credits
  base_percentage_chance = settings_data.base_percentage_chance
  accumulation_percentage = settings_data.accumulation_percentage
  module_upgrade_setting = settings_data.change_modules_with_entity

  progression.initialize(settings_data)

  -- Initialize quality selector with settings
  quality_selector.initialize(
    settings_data.skip_hidden_qualities,
    settings_data.sticky_hidden_qualities
  )
end


-- A retained array also keeps dormant slots alive through our own replacements
-- with a prototype that currently has no module inventory.
local function independent_module_inventory(entity)
  if module_upgrade_setting == "independent" and can_attempt_quality_change[entity.type] then
    return entity.get_module_inventory()
  end
  return nil
end

local function can_upgrade_entity(entity)
  local limit = upgrade_limit_levels[entity.type]
  return can_attempt_quality_change[entity.type]
    and quality_selector.has_upgrade_path(entity.quality.name)
    and (not limit or entity.quality.level < limit - 1)
end

function core.get_entity_info(entity, previous_info)
  local id = entity.unit_number
  if tracked_entities[id] then
    if previous_info then module_upgrades.transfer(previous_info, tracked_entities[id]) end
    return tracked_entities[id]
  end
  local is_turret = turret_types[entity.type] or false
  local is_primary = (entity.type == "assembling-machine" or entity.type == "furnace"
    or entity.type == "rocket-silo" or is_turret)

  -- Track entities that can change quality. Depositing primaries are always
  -- tracked, even at max quality, so they keep feeding their surface's
  -- progression meter. Isolated turrets don't feed the meter, so there is no
  -- reason to keep tracking them once they can no longer upgrade themselves.
  local can_upgrade = can_upgrade_entity(entity)
  local module_inventory = independent_module_inventory(entity)
  local inherited_module_state = previous_info and previous_info.module_failure_bonuses
  local should_track = can_upgrade or feeds_surface_meter(is_primary, is_turret) or module_inventory or inherited_module_state
  if not should_track then
    return "at max quality"
  end

  -- entity is not tracked; so we're adding a new entity
  -- first check if it's something we should track:
  if exclusions.should_exclude_entity(entity) then
    return "entity excluded from quality control"
  end

  local surface_index = entity.surface_index
  tracked_entities[id] = {
    entity = entity,
    is_primary = is_primary,
    is_turret = is_turret,
    surface_index = surface_index,
    chance_to_change = base_percentage_chance
  }

  if is_primary then
    storage.primary_entity_count = storage.primary_entity_count + 1
    if feeds_surface_meter(is_primary, is_turret) then
      storage.surface_primary_counts[surface_index] = (storage.surface_primary_counts[surface_index] or 0) + 1
    end
  else
    storage.secondary_entity_count = storage.secondary_entity_count + 1
  end

  -- Use ordered list for O(1) lookup in batch processing
  table.insert(entity_list, id)
  entity_list_index[id] = #entity_list

  if module_inventory then
    module_upgrades.initialize_state(tracked_entities[id])
  end
  if previous_info then module_upgrades.transfer(previous_info, tracked_entities[id]) end

  if not is_primary then
    -- Bookmark the surface meter at its current value so the entity only earns
    -- credits generated after tracking begins, never the meter's history
    tracked_entities[id].last_seen_meter = storage.surface_meters[surface_index] or 0
    return tracked_entities[id]
  end

  -- Initialize manufacturing hours based on current activity
  -- This ensures we don't double-count hours for already-active entities
  local current_hours = progression.get_manufacturing_hours(entity, is_turret)
  tracked_entities[id].manufacturing_hours = current_hours

  -- Calculate how many upgrade attempts would have occurred in the past
  -- and adjust the chance percentage accordingly
  if current_hours > 0 then
    local hours_needed = quality_multipliers[entity.quality.level]
    local progression_hours = progression.to_progression_hours(current_hours, entity, is_turret)
    local past_attempts = math.floor(progression_hours / hours_needed)

    -- Simulate the chance accumulation from missed upgrade attempts
    if past_attempts > 0 and accumulation_percentage > 0 then
      local chance_increase = past_attempts * (base_percentage_chance * accumulation_percentage / 100)
      tracked_entities[id].chance_to_change = tracked_entities[id].chance_to_change + chance_increase
    end
    -- Past hours only pre-charge the failure accumulation; they never deposit into the
    -- surface meter, so re-running quality-control-init can't be farmed for credits
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
      -- The stored surface_index is used because the entity itself may already be
      -- invalid here; the count entry may be gone if the surface was deleted
      if feeds_surface_meter(entity_info.is_primary, entity_info.is_turret) then
        local surface_count = storage.surface_primary_counts[entity_info.surface_index]
        if surface_count then
          storage.surface_primary_counts[entity_info.surface_index] = math.max(0, surface_count - 1)
        end
      end
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
  if module_upgrade_setting == "disabled" or module_upgrade_setting == "independent" then
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
  local unit_number = entity.unit_number
  local entity_name = entity.name
  local entity_quality = entity.quality.name
  local entity_info = tracked_entities[unit_number]
  local queue_index = entity_list_index[unit_number]

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

  -- capture lamp settings and accumulator energy, to transfer to the new entity
  local old_entity_energy = entity.energy
  local old_always_on = nil
  if entity.type == "lamp" then
    old_always_on = entity.always_on
  end

  local marked_for_upgrade = entity.order_upgrade({
    target = {name = entity_name, quality = target_quality},
    force = entity.force
  })

  -- A failed host upgrade must not stop discovery of its independent modules.
  if not marked_for_upgrade and entity_info.module_failure_bonuses then
    return false
  end

  -- whether mark for upgrade succeeds or fails, we should remove the old entity from tracking
  -- if it failed: then we shouldn't try to upgrade it again as something went wrong
  -- if it succeeded, then we are about to replace the entity with the new upgrade
  core.remove_entity_info(unit_number)
  if not marked_for_upgrade then
    return false
  end

  -- another mod's event handler may have destroyed/replaced the entity
  if not entity.valid then
    return false
  end
  local old_send_to_orbit_automatically = nil
  if entity.type == "rocket-silo" then
    old_send_to_orbit_automatically = entity.send_to_orbit_automatically
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
    if old_send_to_orbit_automatically ~= nil then
      new_entity_1.send_to_orbit_automatically = old_send_to_orbit_automatically
    end
    core.get_entity_info(new_entity_1, entity_info)
    -- Build callbacks append the replacement. Put it back in the old host's
    -- position so frequent upgrades cannot keep revisiting the queue's tail
    -- while starving the hosts in between.
    local replacement_index = entity_list_index[new_entity_1.unit_number]
    if replacement_index and queue_index <= #entity_list then
      local displaced_id = entity_list[queue_index]
      entity_list[queue_index] = new_entity_1.unit_number
      entity_list[replacement_index] = displaced_id
      entity_list_index[new_entity_1.unit_number] = queue_index
      entity_list_index[displaced_id] = replacement_index
    end
    update_module_quality(new_entity_1)
    notifications.show_entity_quality_alert(new_entity_1, target_quality)
  elseif entity.valid and entity_info.module_failure_bonuses then
    core.get_entity_info(entity, entity_info)
  end

  return new_entity_1 ~= nil, new_entity_1
end


-- Re-attaches an entity that a script moved to another surface. True clones
-- register separately with fresh state; moves rebase the existing bookmarks.
local function rehome_moved_entity(entity_info, surface_index)
  if feeds_surface_meter(entity_info.is_primary, entity_info.is_turret) then
    local old_count = storage.surface_primary_counts[entity_info.surface_index]
    if old_count then
      storage.surface_primary_counts[entity_info.surface_index] = math.max(0, old_count - 1)
    end
    storage.surface_primary_counts[surface_index] = (storage.surface_primary_counts[surface_index] or 0) + 1
  elseif not entity_info.is_primary then
    entity_info.last_seen_meter = storage.surface_meters[surface_index] or 0
  end
  entity_info.surface_index = surface_index
  module_upgrades.rebase(entity_info)
end

function core.process_primary_entity(entity_info, entity)
  local hours_needed = quality_multipliers[entity.quality.level]
  local current_hours = progression.get_manufacturing_hours(entity, entity_info.is_turret)
  local previous_hours = entity_info.manufacturing_hours or 0
  local hours_worked = progression.to_progression_hours(current_hours - previous_hours, entity, entity_info.is_turret)
  local credits_earned = hours_worked / hours_needed

  local surface_index = entity.surface_index
  if surface_index ~= entity_info.surface_index then
    rehome_moved_entity(entity_info, surface_index)
  end

  -- The surface meter tracks the total credits the average depositing primary
  -- on the surface has earned, so each one deposits its own share of that
  -- average. Isolated turrets keep their credits for their own upgrade attempts
  -- instead of feeding the meter that secondary entities read.
  if feeds_surface_meter(entity_info.is_primary, entity_info.is_turret) then
    local primary_count = math.max(storage.surface_primary_counts[surface_index] or 1, 1)
    storage.surface_meters[surface_index] = (storage.surface_meters[surface_index] or 0)
      + credits_earned / primary_count
  end

  return {
    credits_earned = credits_earned,
    current_hours = current_hours
  }
end

function core.process_secondary_entity(entity_info, entity)
  local surface_index = entity.surface_index
  if surface_index ~= entity_info.surface_index then
    rehome_moved_entity(entity_info, surface_index)
  end

  -- Read the surface meter like an electricity meter: credits earned are whatever
  -- the average primary earned since this entity's last reading. Visiting more or
  -- less often changes when credits arrive, never how many.
  local meter = storage.surface_meters[surface_index] or 0
  local rate_multiplier = settings.global["secondary-progression-rate"].value / 100
  local credits_earned = (meter - entity_info.last_seen_meter) * rate_multiplier
  entity_info.last_seen_meter = meter

  return {
    credits_earned = credits_earned,
    current_hours = nil
  }
end

-- Surface deletion drops the meter and count entries; entities on the deleted
-- surface become invalid and are cleaned up lazily by the batch loop
function core.on_surface_deleted(event)
  if storage.surface_meters then
    storage.surface_meters[event.surface_index] = nil
  end
  if storage.surface_primary_counts then
    storage.surface_primary_counts[event.surface_index] = nil
  end
end

-- Main batch processing loop

function core.batch_process_entities()
  local batch_size = settings.global["batch-entities-per-tick"].value
  local batch_index = storage.batch_index
  local checked = 0
  local entities_upgraded = {}
  local modules_upgraded = {}
  local visited = {}

  while checked < batch_size do
    if batch_index > #entity_list then
      batch_index = 1
      break
    end

    local unit_number = entity_list[batch_index]
    -- A replacement may be appended during an event callback. It has already
    -- received this visit's module processing and must wait for the next pass.
    if visited[unit_number] then
      batch_index = batch_index + 1
      goto continue
    end
    visited[unit_number] = true
    checked = checked + 1
    local entity_info = tracked_entities[unit_number]
    local entity = entity_info.entity

    if not entity or not entity.valid then
      core.remove_entity_info(unit_number)
      goto continue
    end

    if entity.force ~= game.forces.player or storage.excluded_surfaces[entity.surface_index] then
      core.remove_entity_info(unit_number)
      goto continue
    end

    if entity.surface_index ~= entity_info.surface_index then
      rehome_moved_entity(entity_info, entity.surface_index)
    end

    local can_still_upgrade = can_upgrade_entity(entity)

    local inventory = independent_module_inventory(entity)
    local has_module_state = module_upgrade_setting == "independent"
      and can_attempt_quality_change[entity.type] and entity_info.module_failure_bonuses ~= nil
    local should_stay_tracked = can_still_upgrade
      or feeds_surface_meter(entity_info.is_primary, entity_info.is_turret)
      or inventory or has_module_state
    if not should_stay_tracked then
      core.remove_entity_info(unit_number)
      goto continue
    end

    local suspended = entity.to_be_deconstructed() or entity.to_be_upgraded()
    local result
    if not suspended then
      if entity_info.is_primary then
        result = core.process_primary_entity(entity_info, entity)
        entity_info.manufacturing_hours = result.current_hours
      else
        result = core.process_secondary_entity(entity_info, entity)
      end
    end

    if inventory or has_module_state then
      checked = checked + module_upgrades.process(entity_info, inventory, suspended, modules_upgraded)
    end

    if not suspended and can_still_upgrade and result.credits_earned > 0 then
      local entity_name = entity.name
      local entity_upgraded, replacement = attempt_upgrade_normal(entity, result.credits_earned)
      if entity_upgraded then
        entities_upgraded[entity_name] = (entities_upgraded[entity_name] or 0) + 1
        visited[replacement.unit_number] = true
      end
    end

    -- Removal swaps the last entry into this position. Visit that entry next;
    -- otherwise advance normally. This also handles synchronous upgrade events.
    if entity_list[batch_index] == unit_number or visited[entity_list[batch_index]] then
      batch_index = batch_index + 1
    end
    ::continue::
  end

  storage.batch_index = batch_index
  notifications.show_quality_notifications(entities_upgraded, modules_upgraded)
end

return core
