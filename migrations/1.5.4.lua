--[[
Migration 1.5.4 - Remove entities with quality levels above legendary

This migration removes entities with quality levels above 5 (legendary) from Quality Control
tracking. This fixes save file bloat issues caused by tracking ultra-high quality entities
from mods that add quality tiers beyond vanilla's legendary tier.

The mod now only supports vanilla quality tiers up to legendary (level 5).
]]

log("[Quality Control Migration 1.5.4] Starting migration - removing high-tier quality entities")

-- Clean up entities with quality levels above legendary (5)
if storage.quality_control_entities then
  local removed_count = 0
  local high_tier_ids = {}

  -- Collect unit numbers of entities with quality level > 5
  for unit_number, entity_info in pairs(storage.quality_control_entities) do
    if entity_info.entity and entity_info.entity.valid then
      local quality_level = entity_info.entity.quality.level
      if quality_level > 5 then
        table.insert(high_tier_ids, unit_number)
      end
    end
  end

  -- Remove high-tier quality entities
  for _, unit_number in ipairs(high_tier_ids) do
    local entity_info = storage.quality_control_entities[unit_number]

    if entity_info then
      -- Update counters
      if entity_info.is_primary then
        storage.primary_entity_count = math.max(0, storage.primary_entity_count - 1)
      else
        storage.secondary_entity_count = math.max(0, storage.secondary_entity_count - 1)
      end

      -- Remove from tracking structures
      storage.quality_control_entities[unit_number] = nil

      -- Remove from entity list if it exists
      if storage.entity_list_index and storage.entity_list_index[unit_number] then
        local index = storage.entity_list_index[unit_number]
        local last_index = #storage.entity_list
        local last_unit_number = storage.entity_list[last_index]

        storage.entity_list[index] = last_unit_number
        storage.entity_list_index[last_unit_number] = index
        storage.entity_list[last_index] = nil
        storage.entity_list_index[unit_number] = nil

        -- Adjust batch index if needed
        if storage.batch_index and index < storage.batch_index then
          storage.batch_index = storage.batch_index - 1
        end
      end

      removed_count = removed_count + 1
    end
  end

  if removed_count > 0 then
    log("[Quality Control Migration 1.5.4] Removed " .. removed_count .. " high-tier quality entities from tracking")
  else
    log("[Quality Control Migration 1.5.4] No high-tier quality entities found")
  end
end

-- Clean up quality_multipliers table to only include levels 0-5
if storage.quality_multipliers then
  local cleaned_count = 0
  for level, _ in pairs(storage.quality_multipliers) do
    if level > 5 then
      storage.quality_multipliers[level] = nil
      cleaned_count = cleaned_count + 1
    end
  end

  if cleaned_count > 0 then
    log("[Quality Control Migration 1.5.4] Cleaned " .. cleaned_count .. " high-tier quality multipliers")
  end
end

log("[Quality Control Migration 1.5.4] Migration completed successfully")