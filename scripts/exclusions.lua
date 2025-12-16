--[[
exclusions.lua

Handles entity and surface exclusion logic for Quality Control mod.
Determines which entities and surfaces should be excluded from quality tracking.
Includes Factorissimo compatibility for nested factory detection.
]]

local exclusions = {}

-- Mods with fast_replace issues that should be excluded
local excluded_mods_lookup = {
  ["ammo-loader"] = true,
  ["fct-ControlTech"] = true, -- patch requested, may be able to remove once they are greater than version 2.0.5
  ["miniloader-redux"] = true,
  ["quality-condenser"] = true,
  ["railloader2-patch"] = true,
  ["RealisticReactorsReborn"] = true,
  ["router"] = true,
  ["Warp-Drive-Machine"] = true,
}

-- Get the item name for placing an entity
function exclusions.get_entity_item_name(entity)
  local items = entity.prototype.items_to_place_this
  if items and #items > 0 then
    return items[1].name
  end
  return nil
end

-- Check if Factorissimo remote interface is available
local function factorissimo_available()
  return remote.interfaces["factorissimo"] ~= nil
end

-- Find the factory that has the given surface as its inside_surface
-- Returns nil if not found (surface is not a factory interior)
local function find_factory_by_inside_surface(surface_index)
  if not factorissimo_available() then return nil end
  local factories = remote.call("factorissimo", "get_global", {"factories"})
  if not factories then return nil end
  for _, factory in pairs(factories) do
    if factory.inside_surface and factory.inside_surface.valid
       and factory.inside_surface.index == surface_index then
      return factory
    end
  end
  return nil
end

-- Find the root (outermost non-factory) surface for a factory floor
-- Traverses up through nested factories until reaching a non-factory surface
local function get_root_surface(surface, depth)
  depth = depth or 0
  if depth > 100 then return nil end  -- Prevent infinite recursion (factories can contain themselves)

  local factory = find_factory_by_inside_surface(surface.index)
  if not factory then return surface end  -- Not a factory interior, this is the root

  local outside = factory.outside_surface
  if not outside or not outside.valid then return nil end

  -- If outside surface is also a factory floor, recurse
  if remote.call("factorissimo", "is_factorissimo_surface", outside) then
    return get_root_surface(outside, depth + 1)
  end

  return outside
end

-- Evaluate whether a surface should be excluded from entity tracking
-- Called once per surface when created, result cached in storage.excluded_surfaces
function exclusions.evaluate_surface_exclusion(surface)
  local name = surface.name

  -- Direct blueprint-sandbox surfaces: bpsb-lab-* or bpsb-sb-*
  if string.sub(name, 1, 5) == "bpsb-" then
    return true
  end

  -- Surface has a planet - it's a real game surface
  if surface.planet then
    return false
  end

  -- Check for Factorissimo factory floor (requires Factorissimo mod)
  if factorissimo_available() and remote.call("factorissimo", "is_factorissimo_surface", surface) then
    local root = get_root_surface(surface, 0)
    if root then
      -- If root is a sandbox, exclude; otherwise include
      return string.sub(root.name, 1, 5) == "bpsb-"
    end
    -- Couldn't determine root - exclude to be safe
    return true
  end

  -- Unknown surface without planet - include by default
  return false
end

-- Handler for surface creation - evaluate and cache exclusion status
function exclusions.on_surface_created(event)
  local surface = event.surface
  storage.excluded_surfaces = storage.excluded_surfaces or {}
  storage.excluded_surfaces[surface.index] = exclusions.evaluate_surface_exclusion(surface)
end

-- Handler for surface deletion - clean up cache
function exclusions.on_surface_deleted(event)
  if storage.excluded_surfaces then
    storage.excluded_surfaces[event.surface_index] = nil
  end
end

-- Check if an entity should be excluded from quality tracking
function exclusions.should_exclude_entity(entity)
  if not entity.prototype.selectable_in_game then
    return true
  end

  if not entity.destructible then
    return true
  end

  -- exclude entities on sandbox surfaces or factories inside sandboxes
  if storage.excluded_surfaces and storage.excluded_surfaces[entity.surface.index] then
    return true
  end

  -- check if entity has no placeable items
  if exclusions.get_entity_item_name(entity) == nil then
    return true
  end

  -- Check if entity is from an excluded mod
  local history = prototypes.get_history(entity.type, entity.name)
  if history and excluded_mods_lookup[history.created] then
    return true
  end

  return false
end

return exclusions
