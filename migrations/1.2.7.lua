--[[
Migration 1.2.7 - Fix miniloader-redux compatibility
This migration deletes broken miniloader entities that may have been upgraded by Quality Control
before proper miniloader-redux exclusion was implemented.

The issue: Quality Control was upgrading hidden loaders and inserters from miniloader-redux,
breaking the connection between main entities and their hidden components.

The fix: Find hidden entities that are destructible (indicating they were incorrectly upgraded),
locate their parent miniloader, and delete both the parent and all associated hidden entities.

Entity Types:
  Main entities (visible): hps__ml-.*miniloader$ (without -l or -i suffix)
    - Entity type: inserter
    - These are the user-visible miniloader entities

  Hidden loaders: hps__ml-.*miniloader-l$
    - Entity type: loader-1x1
    - Properties: destructible = false, operable = true, selectable_in_game = false

  Hidden inserters: hps__ml-.*miniloader-i$
    - Entity type: inserter
    - Properties: destructible = false, operable = false, selectable_in_game = false

Detection:
  - Hidden entities that have destructible = true are broken and need deletion
  - Parent child entities that have mismatched qualities are probably broken
]]

log("[Quality Control Migration 1.2.7] Starting miniloader-redux compatibility fix")

if not script.active_mods["miniloader-redux"] then
  log("[Quality Control Migration 1.2.7] miniloader-redux mod not active, skipping migration")
  return
end


-- Find the parent miniloader entity for a broken hidden entity
local function find_parent_miniloader(surface, hidden_entity)
  if not hidden_entity or not hidden_entity.valid then
    return nil
  end

  -- Search for a main miniloader at the same position
  local nearby_entities = surface.find_entities_filtered{
    position = hidden_entity.position,
    radius = 0.1  -- Very close to the same position
  }

  for _, entity in pairs(nearby_entities) do
    if entity.valid and entity.name:match("^hps__ml%-.*miniloader$") then
      return entity
    end
  end

  return nil
end

-- Find broken hidden entities that need fixing
local function find_broken_hidden_entities(surface)
  local broken_entities = {}

  -- Check hidden inserters (type: inserter)
  local all_inserters = surface.find_entities_filtered{type = "inserter"}
  for _, entity in pairs(all_inserters) do
    if entity.valid and entity.name:match("^hps__ml%-.*miniloader%-i$") and entity.destructible then
      table.insert(broken_entities, entity)
    end
  end

  -- Check hidden loaders (type: loader-1x1)
  local all_loaders = surface.find_entities_filtered{type = "loader-1x1"}
  for _, entity in pairs(all_loaders) do
    if entity.valid and entity.name:match("^hps__ml%-.*miniloader%-l$") and entity.destructible then
      table.insert(broken_entities, entity)
    end
  end

  log("[Quality Control Migration 1.2.7] Found " .. #broken_entities .. " broken hidden entities on surface " .. surface.name)
  return broken_entities
end

-- Delete all miniloader entities at a broken entity's location
local function delete_broken_entity(broken_entity)
  if not broken_entity.valid then
    return false
  end

  local entity_surface = broken_entity.surface
  local entity_position = broken_entity.position

  log("[Quality Control Migration 1.2.7] Processing broken entity " .. broken_entity.name .. " at " .. serpent.line(entity_position))

  -- Find ALL entities at this location that need to be deleted
  local entities_to_delete = entity_surface.find_entities_filtered{
    position = entity_position,
    radius = 0.1
  }

  local entities_deleted = 0

  -- Delete all miniloader-related entities at this location
  for _, entity in pairs(entities_to_delete) do
    if entity.valid then
      entity.destroy{raise_destroy = true}
      entities_deleted = entities_deleted + 1
    end
  end

  if entities_deleted > 0 then
    return true
  else
    return false
  end
end

-- Main function to process a surface
local function delete_miniloader_entities_on_surface(surface)
  log("[Quality Control Migration 1.2.7] Processing surface: " .. surface.name)

  -- Find broken hidden entities (those that are destructible when they shouldn't be)
  local broken_entities = find_broken_hidden_entities(surface)

  -- Skip if no broken entities found
  if #broken_entities == 0 then
    log("[Quality Control Migration 1.2.7] No broken hidden entities found on surface " .. surface.name)
    return {
      broken_entities = 0,
      deletions_attempted = 0,
      deletions_succeeded = 0
    }
  end

  log("[Quality Control Migration 1.2.7] Found " .. #broken_entities .. " broken hidden entities, attempting deletions...")

  -- Group broken entities by parent to avoid deleting the same parent multiple times
  local processed_parents = {}
  local deletions_attempted = 0
  local deletions_succeeded = 0

  for _, broken_entity in pairs(broken_entities) do
    if broken_entity.valid then
      local parent = find_parent_miniloader(surface, broken_entity)
      local parent_key = parent and (parent.name .. "@" .. serpent.line(parent.position)) or "orphan"

      if not processed_parents[parent_key] then
        processed_parents[parent_key] = true
        deletions_attempted = deletions_attempted + 1

        if delete_broken_entity(broken_entity) then
          deletions_succeeded = deletions_succeeded + 1
        end
      end
    end
  end

  return {
    broken_entities = #broken_entities,
    deletions_attempted = deletions_attempted,
    deletions_succeeded = deletions_succeeded
  }
end

-- Main migration function
local function delete_miniloader_compatibility()
  log("[Quality Control Migration 1.2.7] Starting miniloader-redux compatibility cleanup")

  local total_broken_entities = 0
  local total_deletions_attempted = 0
  local total_deletions_succeeded = 0
  local total_surfaces_processed = 0

  -- Process each surface
  for _, surface in pairs(game.surfaces) do
    local stats = delete_miniloader_entities_on_surface(surface)

    total_surfaces_processed = total_surfaces_processed + 1
    total_broken_entities = total_broken_entities + stats.broken_entities
    total_deletions_attempted = total_deletions_attempted + stats.deletions_attempted
    total_deletions_succeeded = total_deletions_succeeded + stats.deletions_succeeded

    if stats.broken_entities > 0 then
      log(string.format(
        "[Quality Control Migration 1.2.7] Surface '%s': Found %d broken entities, attempted %d deletions, %d succeeded.",
        surface.name, stats.broken_entities, stats.deletions_attempted, stats.deletions_succeeded
      ))
    end
  end

  log(string.format(
    "[Quality Control Migration 1.2.7] Migration completed. Processed %d surfaces, found %d broken entities, deleted %d/%d",
    total_surfaces_processed, total_broken_entities, total_deletions_succeeded, total_deletions_attempted
  ))
end

-- Run the migration
delete_miniloader_compatibility()