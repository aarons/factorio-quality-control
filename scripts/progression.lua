--[[
progression.lua

Computes manufacturing hours for primary entities and converts them into
progression hours based on the crafting-speed setting. Also provides the rate
factor that scales mining drill and lab credits. Kept as a leaf module (no
requires) so both core.lua and notifications.lua can share it.
]]

local progression = {}

local turret_damage_per_manufacturing_hour = 36000
local crafting_speed_affects_progression = true

function progression.initialize(settings_data)
  turret_damage_per_manufacturing_hour = settings_data.turret_damage_per_manufacturing_hour
  crafting_speed_affects_progression = settings_data.crafting_speed_affects_progression
end

local function get_recipe_time(entity)
  if entity.get_recipe() then
    return entity.get_recipe().prototype.energy
  elseif entity.type == "furnace" and entity.previous_recipe then
    return entity.previous_recipe.name.energy
  end
  return 0
end

-- Cumulative hours of work completed, normalized to crafting speed 1
-- (turrets: damage dealt). Always measured in these units regardless of the
-- crafting-speed setting, so stored baselines stay valid if the setting changes.
function progression.get_manufacturing_hours(entity, is_turret)
  if is_turret then
    return entity.damage_dealt / turret_damage_per_manufacturing_hour
  end
  return (entity.products_finished * get_recipe_time(entity)) / 3600
end

-- Converts a span of manufacturing hours into progression hours. When crafting
-- speed affects progression (the default) they are the same. Otherwise hours
-- are divided by the machine's current crafting speed, so progression tracks
-- time spent crafting rather than work completed. Turrets have no crafting
-- speed and are unaffected by the setting.
function progression.to_progression_hours(hours, entity, is_turret)
  if crafting_speed_affects_progression or is_turret then
    return hours
  end
  local crafting_speed = entity.crafting_speed
  if crafting_speed > 0 then
    return hours / crafting_speed
  end
  return hours
end

-- Mining drills and labs are secondary entities (nothing in the API counts what
-- they produce), but players still expect a moduled big drill to out-progress an
-- inserter. Their surface-meter credits are scaled by base speed relative to the
-- vanilla electric mining drill / lab, plus module, beacon, and force bonuses.
local electric_mining_drill_speed = 0.5
local vanilla_lab_researching_speed = 1.0

-- Multiplier applied to a secondary entity's meter credits. Mining drills and
-- labs earn nothing while idle (output blocked, no resources, no packs, no
-- power) and, when crafting speed affects progression, earn in proportion to
-- their speed and productivity. Every other secondary type earns 1x.
function progression.get_secondary_rate_factor(entity)
  local entity_type = entity.type
  if entity_type ~= "mining-drill" and entity_type ~= "lab" then
    return 1
  end
  if entity.status ~= defines.entity_status.working then
    return 0
  end
  if not crafting_speed_affects_progression then
    return 1
  end

  local base_speed_ratio = 1
  if entity_type == "mining-drill" then
    local mining_speed = entity.prototype.mining_speed
    if mining_speed then
      base_speed_ratio = mining_speed / electric_mining_drill_speed
    end
  else
    local researching_speed = entity.prototype.get_researching_speed(entity.quality)
    if researching_speed then
      base_speed_ratio = researching_speed / vanilla_lab_researching_speed
    end
  end
  return base_speed_ratio * (1 + entity.speed_bonus) * (1 + entity.productivity_bonus)
end

return progression
