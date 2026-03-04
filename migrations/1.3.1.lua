--[[
Migration 1.3.1 - Remove rocket silo tracking entirely

This migration was originally added because upgrading rocket silos reset the
'send to orbit automatically' setting, and the modding API had no way to preserve it.

Rocket silo support has since been re-added now that LuaEntity.send_to_orbit_automatically
is available as a read/write property. The mod's entity rescan on configuration change will
automatically pick up rocket silos again.

This migration still runs for saves upgrading from pre-1.3.1 versions to clean up any
rocket silos that were tracked under the old (broken) behavior.
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