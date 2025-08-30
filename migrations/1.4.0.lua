--[[
Migration 1.4.0 - Rescan entities to capture max quality entities

This migration ensures that entities at maximum quality are properly tracked for the new
"continue accumulation at max quality" feature. This is equivalent to running the
quality-control-init command to rebuild the entity cache from scratch.

The new feature allows entities at max quality to continue accumulating manufacturing
hours for potential future downgrades, but requires a full rescan to ensure all
max quality entities are captured in the tracking system.
]]

-- Reinitialize storage and rescan all entities (same as quality-control-init command)
-- This will be handled by the on_configuration_changed event in control.lua
log("[Quality Control Migration 1.4.0] Entity rescanning will be handled by control.lua on_configuration_changed")