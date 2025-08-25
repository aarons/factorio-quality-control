--[[
Migration 1.4.0 - Rescan entities to capture max quality entities

This migration ensures that entities at maximum quality are properly tracked for the new
"continue accumulation at max quality" feature. This is equivalent to running the
quality-control-init command to rebuild the entity cache from scratch.

The new feature allows entities at max quality to continue accumulating manufacturing
hours for potential future downgrades, but requires a full rescan to ensure all
max quality entities are captured in the tracking system.
]]

local data_setup = require("scripts.data-setup")
local core = require("scripts.core")

-- Reinitialize storage and rescan all entities (same as quality-control-init command)
data_setup.setup_data_structures(true)
data_setup.build_and_store_config()
core.initialize()
core.scan_and_populate_entities(storage.config.all_tracked_types)