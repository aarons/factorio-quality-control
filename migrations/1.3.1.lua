--[[
Migration 1.3.1 - Remove rocket silo tracking entirely

This migration removes rocket silos from Quality Control tracking entirely due to an issue
discovered by Stargateur where upgrading rocket silos resets the 'send to orbit automatically'
setting. Since we cannot preserve this setting through the modding API, rocket silos are no
longer supported by the mod.

This migration removes any existing rocket silos from tracking and informs users of the change.
]]

log("[Quality Control Migration 1.3.1] Starting migration - removing rocket silo tracking")

-- Load the core module to access remove_entity_info function
local core = require("scripts.core")

-- Remove all rocket silos from tracked entities
if storage.quality_control_entities then
  local removed_count = 0
  local rocket_silo_ids = {}

  -- Collect rocket silo unit numbers
  for unit_number, entity_info in pairs(storage.quality_control_entities) do
    if entity_info.entity and entity_info.entity.valid and entity_info.entity.type == "rocket-silo" then
      table.insert(rocket_silo_ids, unit_number)
    end
  end

  -- Remove rocket silos using the existing cleanup function
  for _, unit_number in ipairs(rocket_silo_ids) do
    core.remove_entity_info(unit_number)
    removed_count = removed_count + 1
  end

  if removed_count > 0 then
    log("[Quality Control Migration 1.3.1] Removed " .. removed_count .. " rocket silos from tracking")
  else
    log("[Quality Control Migration 1.3.1] No rocket silos found in tracking")
  end
end

log("[Quality Control Migration 1.3.1] Migration completed successfully")