--[[
Migration 1.3.0 - Transition from category-based to individual entity settings

This migration handles the transition from the old category-based entity selection system
to the new individual entity type toggles. All new settings default to enabled (true),
so we only need to alert users when their old preferences would have disabled entities
that are now enabled by default.

The old system had these categories:
- primary-entities-selection: "both", "assembly-machines-only", or "furnaces-only"
- enable-electrical-entities: poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods
- enable-other-production-entities: rocket silos, agricultural towers, mining drills
- enable-defense-entities: turrets, walls, gates
- enable-space-entities: asteroid collectors, thrusters
- enable-other-entities: lamps, combinators, speakers
- Plus standalone settings for: labs, roboports, beacons, pumps, radar, inserters
]]

log("[Quality Control Migration 1.3.0] Starting migration to individual entity settings")

-- Check if old category settings exist (they won't in new installs)
local primary_setting = settings.startup["primary-entities-selection"]
local electrical_enabled = settings.startup["enable-electrical-entities"]
local other_production_enabled = settings.startup["enable-other-production-entities"]
local defense_enabled = settings.startup["enable-defense-entities"]
local space_enabled = settings.startup["enable-space-entities"]
local other_enabled = settings.startup["enable-other-entities"]

-- Build list of entities that would be newly enabled compared to old preferences
local newly_enabled_entities = {}

-- Check primary entities (assembly machines and furnaces)
if primary_setting then
  local primary_value = primary_setting.value
  if primary_value == "assembly-machines-only" then
    -- Furnaces would be newly enabled
    table.insert(newly_enabled_entities, "furnaces")
  elseif primary_value == "furnaces-only" then
    -- Assembly machines would be newly enabled
    table.insert(newly_enabled_entities, "assembly machines")
  end
  -- If "both", no change needed
end

-- Check electrical entities
if electrical_enabled and not electrical_enabled.value then
  -- All electrical entities are now enabled by default but were disabled
  table.insert(newly_enabled_entities, "electrical entities (poles, solar panels, accumulators, generators, reactors, boilers, heat pipes, power switches, lightning rods)")
end

-- Check other production entities
if other_production_enabled and not other_production_enabled.value then
  -- Rocket silos, agricultural towers, mining drills now enabled
  table.insert(newly_enabled_entities, "other production entities (rocket silos, agricultural towers, mining drills)")
end

-- Check defense entities
if defense_enabled and not defense_enabled.value then
  -- Turrets, walls, gates now enabled
  table.insert(newly_enabled_entities, "defense entities (turrets, walls, gates)")
end

-- Check space entities
if space_enabled and not space_enabled.value then
  -- Asteroid collectors, thrusters now enabled
  table.insert(newly_enabled_entities, "space entities (asteroid collectors, thrusters)")
end

-- Check other entities
if other_enabled and not other_enabled.value then
  -- Lamps, combinators, speakers now enabled
  table.insert(newly_enabled_entities, "other entities (lamps, combinators, speakers)")
end

-- Check standalone entities (these persist with same names, so only notify if they existed and were disabled)
local standalone_checks = {
  {setting = "enable-labs", name = "labs"},
  {setting = "enable-roboports", name = "roboports"},
  {setting = "enable-beacons", name = "beacons"},
  {setting = "enable-pumps", name = "pumps"},
  {setting = "enable-radar", name = "radar"},
  {setting = "enable-inserters", name = "inserters"}
}

for _, check in ipairs(standalone_checks) do
  local old_setting = settings.startup[check.setting]
  if old_setting and not old_setting.value then
    table.insert(newly_enabled_entities, check.name)
  end
end

-- Only show message if there are entities that would be newly enabled
if #newly_enabled_entities > 0 then
  log("[Quality Control Migration 1.3.0] Settings changes detected - notifying user")

  -- Build user-friendly message
  local message = "Quality Control's startup settings changed to be more granular.\n"
  message = message .. "Unfortunately this change reset your previous selections.\n"
  message = message .. "These entities are now enabled for upgrades:\n"
  for _, entity_name in ipairs(newly_enabled_entities) do
    message = message .. "  - " .. entity_name .. "\n"
  end
  message = message .. "If you do not want these enabled, please exit back to menu, go to settings, and disable these entities.\n"
  message = message .. "This should be a one time change, sorry about that! >.<"

  -- Show message to all players
  game.print(message)
  log("[Quality Control Migration 1.3.0] User notification: " .. message)
else
  log("[Quality Control Migration 1.3.0] No settings changes detected - no user notification needed")
end

-- Always rebuild storage.config to ensure it has the new structure
-- This is required because the new version adds can_attempt_quality_change field
log("[Quality Control Migration 1.3.0] Rebuilding storage.config with new structure")
-- The config rebuild will happen in the on_configuration_changed event in control.lua

log("[Quality Control Migration 1.3.0] Migration completed successfully")