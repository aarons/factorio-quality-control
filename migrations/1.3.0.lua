-- Migration for v1.3.0: Transition from category-based to individual entity settings
-- This migration attempts to preserve user preferences when migrating from the old
-- category system to the new individual entity type system.

-- Read the old settings if they exist
local primary_setting = settings.startup["primary-entities-selection"]
local electrical_enabled = settings.startup["enable-electrical-entities"]
local other_production_enabled = settings.startup["enable-other-production-entities"]
local defense_enabled = settings.startup["enable-defense-entities"]
local space_enabled = settings.startup["enable-space-entities"]
local other_enabled = settings.startup["enable-other-entities"]

-- Map old category settings to new individual settings if the old settings exist
if primary_setting then
  local primary_value = primary_setting.value
  if primary_value == "both" or primary_value == "assembly-machines-only" then
    settings.startup["enable-production-assembly-machines"] = {value = true}
  end
  if primary_value == "both" or primary_value == "furnaces-only" then
    settings.startup["enable-production-furnaces"] = {value = true}
  end
end

-- Apply category-based settings to individual entity types
if electrical_enabled then
  local enabled = electrical_enabled.value
  settings.startup["enable-electrical-poles"] = {value = enabled}
  settings.startup["enable-electrical-solar-panels"] = {value = enabled}
  settings.startup["enable-electrical-accumulators"] = {value = enabled}
  settings.startup["enable-electrical-generators"] = {value = enabled}
  settings.startup["enable-electrical-reactors"] = {value = enabled}
  settings.startup["enable-electrical-boilers"] = {value = enabled}
  settings.startup["enable-electrical-heat-pipes"] = {value = enabled}
  settings.startup["enable-electrical-power-switches"] = {value = enabled}
  settings.startup["enable-electrical-lightning-rods"] = {value = enabled}
end

if other_production_enabled then
  local enabled = other_production_enabled.value
  settings.startup["enable-production-rocket-silos"] = {value = enabled}
  settings.startup["enable-production-agricultural-towers"] = {value = enabled}
  settings.startup["enable-production-mining-drills"] = {value = enabled}
end

if defense_enabled then
  local enabled = defense_enabled.value
  settings.startup["enable-defense-turrets"] = {value = enabled}
  settings.startup["enable-defense-walls-and-gates"] = {value = enabled}
end

if space_enabled then
  local enabled = space_enabled.value
  settings.startup["enable-space-asteroid-collectors"] = {value = enabled}
  settings.startup["enable-space-thrusters"] = {value = enabled}
end

if other_enabled then
  local enabled = other_enabled.value
  settings.startup["enable-other-lamps"] = {value = enabled}
  settings.startup["enable-other-combinators-and-speakers"] = {value = enabled}
end

-- Map existing standalone settings to new names
local labs_enabled = settings.startup["enable-labs"]
local roboports_enabled = settings.startup["enable-roboports"]
local beacons_enabled = settings.startup["enable-beacons"]
local pumps_enabled = settings.startup["enable-pumps"]
local radar_enabled = settings.startup["enable-radar"]
local inserters_enabled = settings.startup["enable-inserters"]

if labs_enabled then
  settings.startup["enable-other-labs"] = {value = labs_enabled.value}
end
if roboports_enabled then
  settings.startup["enable-other-roboports"] = {value = roboports_enabled.value}
end
if beacons_enabled then
  settings.startup["enable-other-beacons"] = {value = beacons_enabled.value}
end
if pumps_enabled then
  settings.startup["enable-other-pumps"] = {value = pumps_enabled.value}
end
if radar_enabled then
  settings.startup["enable-other-radar"] = {value = radar_enabled.value}
end
if inserters_enabled then
  settings.startup["enable-other-inserters"] = {value = inserters_enabled.value}
end

-- Force rebuild the configuration with new settings
log("Quality Control: Migrated to individual entity settings.")