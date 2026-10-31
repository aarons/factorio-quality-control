-- Independent module progression belongs to inventory slots, not to the items
-- occupying them. Hosts provide discovery; only the surface meter pays credits.
local quality_selector = require("scripts.quality_selector")
local notifications = require("scripts.notifications")

local module_upgrades = {}

function module_upgrades.initialize_state(entity_info)
  if not entity_info.module_failure_bonuses then
    entity_info.module_failure_bonuses = {}
    entity_info.module_last_seen_meter = storage.surface_meters[entity_info.surface_index] or 0
  end
end

function module_upgrades.rebase(entity_info)
  if entity_info.module_failure_bonuses then
    entity_info.module_last_seen_meter = storage.surface_meters[entity_info.surface_index] or 0
  end
end

function module_upgrades.transfer(old_info, new_info)
  if old_info.module_failure_bonuses then
    new_info.module_failure_bonuses = old_info.module_failure_bonuses
    new_info.module_last_seen_meter = old_info.module_last_seen_meter
    if old_info.surface_index ~= new_info.surface_index then
      module_upgrades.rebase(new_info)
    end
  end
end

-- Returns inspected slots, including empty and terminal-quality slots. A whole
-- inventory is processed even when it takes the callback over its soft budget.
function module_upgrades.process(entity_info, inventory, suspended, changes)
  module_upgrades.initialize_state(entity_info)
  local meter = storage.surface_meters[entity_info.surface_index] or 0
  local credits = (meter - entity_info.module_last_seen_meter)
    * settings.global["secondary-progression-rate"].value / 100
  entity_info.module_last_seen_meter = meter
  if not inventory then return 0 end

  local config = storage.config.settings_data
  local bonuses = entity_info.module_failure_bonuses
  for slot = 1, #inventory do
    bonuses[slot] = bonuses[slot] or 0
    local stack = inventory[slot]
    if not suspended and credits > 0 and stack.valid_for_read and stack.is_module
      and quality_selector.has_upgrade_path(stack.quality.name) then
      local chance = math.min(1, (config.base_percentage_chance + bonuses[slot]) / 100 * credits)
      if math.random() >= chance then
        bonuses[slot] = bonuses[slot] + config.base_percentage_chance
          * config.accumulation_percentage / 100 * credits
      else
        local target = quality_selector.get_next_quality(stack.quality.name)
        local name, count = stack.name, stack.count
        -- Replace in the same slot; never clear the original item first. A slot
        -- containing multiple modules upgrades as one unit and retains its count.
        local replacement = {name = name, count = count, quality = target, health = stack.health}
        if stack.prototype.get_spoil_ticks(stack.quality) > 0 then
          replacement.spoil_percent = stack.spoil_percent
        end
        local applied = stack.can_set_stack(replacement) and stack.set_stack(replacement)
        if applied and stack.valid_for_read and stack.name == name and stack.count == count and stack.quality.name == target then
          bonuses[slot] = 0
          changes[name] = (changes[name] or 0) + count
          notifications.show_module_quality_alert(entity_info.entity, name, target)
        end
      end
    end
  end
  return #inventory
end

return module_upgrades
