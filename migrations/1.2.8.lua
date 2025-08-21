--[[
Migration 1.2.8 - Initialize storage.config structure
This migration ensures that players upgrading from earlier versions have the new storage.config
structure that was introduced in the refactoring to improve on_load and on_init handling.

The issue: Refactored code expects storage.config to exist with specific fields:
- storage.config.settings_data
- storage.config.is_tracked_type
- storage.config.previous_qualities
- storage.config.quality_limit
- storage.config.primary_types
- storage.config.secondary_types
- storage.config.all_tracked_types

The fix: Check if storage.config exists, and if not, initialize it by calling
data_setup.build_and_store_config() which populates all required fields.
]]

log("[Quality Control Migration 1.2.8] Starting storage.config initialization")

-- Import required module
local data_setup = require("scripts/data-setup")

-- Check if storage.config exists and has the required structure
local needs_migration = false

if not storage.config then
  log("[Quality Control Migration 1.2.8] storage.config does not exist - migration needed")
  needs_migration = true
elseif not storage.ticks_between_batches then
  log("[Quality Control Migration 1.2.8] storage.ticks_between_batches missing - migration needed")
  needs_migration = true
else
  -- Check if all required config fields exist
  local required_fields = {
    "settings_data",
    "is_tracked_type",
    "previous_qualities",
    "quality_limit",
    "primary_types",
    "secondary_types",
    "all_tracked_types"
  }

  for _, field in ipairs(required_fields) do
    if not storage.config[field] then
      log("[Quality Control Migration 1.2.8] storage.config." .. field .. " missing - migration needed")
      needs_migration = true
      break
    end
  end
end

if needs_migration then
  log("[Quality Control Migration 1.2.8] Initializing storage.config structure...")

  -- Build and store the config using the same function used in on_init
  data_setup.build_and_store_config()

  -- Also initialize ticks_between_batches if missing
  if not storage.ticks_between_batches then
    storage.ticks_between_batches = settings.global["batch-ticks-between-processing"].value
    log("[Quality Control Migration 1.2.8] storage.ticks_between_batches set to " .. storage.ticks_between_batches)
  end

  log("[Quality Control Migration 1.2.8] storage.config initialized successfully")

  -- Log what was created for debugging
  if storage.config then
    local config_keys = {}
    for key, _ in pairs(storage.config) do
      table.insert(config_keys, key)
    end
    log("[Quality Control Migration 1.2.8] Created config with keys: " .. table.concat(config_keys, ", "))
  end
else
  log("[Quality Control Migration 1.2.8] storage.config already exists with all required fields - no migration needed")
end

log("[Quality Control Migration 1.2.8] Migration completed")