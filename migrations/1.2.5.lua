--[[
Migration 1.2.5 - Fix ammo-loader compatibility
This migration fixes broken ammo-loader entities that may have been upgraded by Quality Control
before the ammo-loader exclusion was added.

The issue: Quality Control was upgrading hidden inserters and range extenders from ammo-loader,
breaking the connection between containers and their hidden entities.

The fix: Destroy and recreate ammo-loader containers to let ammo-loader regenerate hidden entities.
]]

-- ammo-loader entity names
local AMMO_LOADER_CONTAINERS = {
  "ammo-loader-chest",
  "ammo-loader-chest-requester",
  "ammo-loader-chest-storage",
  "ammo-loader-chest-passive-provider"
}

-- Helper function to log with prefix
local function migration_log(message)
  log("[Quality Control Migration 1.2.5] " .. message)
end

-- Helper function to check if ammo-loader mod is active
local function is_ammo_loader_active()
  return script.active_mods["ammo-loader"] ~= nil
end

-- Helper function to get entity quality level
local function get_quality_level(entity)
  if entity and entity.valid and entity.quality then
    return entity.quality.level
  end
  return 0
end

-- Helper function to save container data before destruction
local function save_container_data(container)
  if not container or not container.valid then
    return nil
  end

  local data = {
    name = container.name,
    position = container.position,
    direction = container.direction,
    force = container.force,
    quality = container.quality,
    surface = container.surface,
    unit_number = container.unit_number,
    inventory_contents = {}
  }

  -- Save inventory contents
  local inventory = container.get_inventory(defines.inventory.chest)
  if inventory then
    local contents = inventory.get_contents()
    for i = 1, #contents do
      local item = contents[i]
      table.insert(data.inventory_contents, {
        name = item.name,
        count = item.count,
        quality = item.quality
      })
    end
  end

  migration_log("Saved container data: " .. container.name .. " at " .. serpent.line(container.position) ..
                " quality=" .. container.quality.name .. " unit_number=" .. container.unit_number)

  return data
end

-- Helper function to recreate container from saved data
local function recreate_container(container_data)
  if not container_data then
    return nil
  end

  local new_container = container_data.surface.create_entity{
    name = container_data.name,
    position = container_data.position,
    direction = container_data.direction,
    force = container_data.force,
    quality = container_data.quality,
    raise_built = true  -- Let ammo-loader know about the new container
  }

  if not new_container or not new_container.valid then
    migration_log("FAILED to recreate container: " .. container_data.name .. " at " .. serpent.line(container_data.position))
    return nil
  end

  -- Restore inventory contents
  local inventory = new_container.get_inventory(defines.inventory.chest)
  if inventory then
    for _, item_data in pairs(container_data.inventory_contents) do
      inventory.insert({
        name = item_data.name,
        count = item_data.count,
        quality = item_data.quality
      })
    end
  end

  migration_log("Recreated container: " .. new_container.name .. " at " .. serpent.line(new_container.position) ..
                " quality=" .. new_container.quality.name .. " unit_number=" .. new_container.unit_number)

  return new_container
end

-- Helper function to check if containers and hidden entities have quality mismatches
local function has_quality_mismatch(containers, hidden_entities)
  if #containers == 0 or #hidden_entities == 0 then
    return false
  end

  -- Get the quality level of the first container
  local container_quality = get_quality_level(containers[1])

  -- Check if all containers have the same quality
  for _, container in pairs(containers) do
    if get_quality_level(container) ~= container_quality then
      return true
    end
  end

  -- Check if any hidden entity has different quality than containers
  for _, hidden_entity in pairs(hidden_entities) do
    if get_quality_level(hidden_entity) ~= container_quality then
      return true
    end
  end

  return false
end

-- Helper function to check if hidden entities exist near containers
local function check_hidden_entities_exist(surface, containers_data)
  local found_inserters = 0
  local found_extenders = 0

  for _, container_data in pairs(containers_data) do
    -- Search for hidden inserters near this container position
    local nearby_inserters = surface.find_entities_filtered{
      type = "inserter",
      position = container_data.position,
      radius = 1.0
    }
    for _, inserter in pairs(nearby_inserters) do
      if inserter.name == "ammo-loader-hidden-inserter" then
        found_inserters = found_inserters + 1
      end
    end

    -- Search for range extenders near this container position
    local nearby_poles = surface.find_entities_filtered{
      type = "electric-pole",
      position = container_data.position,
      radius = 1.0
    }
    for _, pole in pairs(nearby_poles) do
      if pole.name == "ammo-loader-range-extender" then
        found_extenders = found_extenders + 1
      end
    end
  end

  migration_log("Found " .. found_inserters .. " hidden inserters and " .. found_extenders .. " range extenders after recreation")
  return found_inserters, found_extenders
end

-- Main migration function
local function fix_ammo_loader_compatibility()
  migration_log("Starting ammo-loader compatibility fix")

  if not is_ammo_loader_active() then
    migration_log("ammo-loader mod not active, skipping migration")
    return
  end

  local total_containers_fixed = 0
  local total_surfaces_processed = 0

  -- Process each surface
  for _, surface in pairs(game.surfaces) do
    migration_log("Processing surface: " .. surface.name)
    total_surfaces_processed = total_surfaces_processed + 1

    -- Find all ammo-loader containers (chests)
    local containers = {}
    local all_chests = surface.find_entities_filtered{
      type = "container"
    }
    for _, chest in pairs(all_chests) do
      for _, container_name in pairs(AMMO_LOADER_CONTAINERS) do
        if chest.name == container_name then
          table.insert(containers, chest)
          break
        end
      end
    end

    -- Find all ammo-loader hidden entities
    local hidden_entities = {}
    -- Find inserters with ammo-loader names
    local all_inserters = surface.find_entities_filtered{
      type = "inserter"
    }
    for _, inserter in pairs(all_inserters) do
      if inserter.name == "ammo-loader-hidden-inserter" then
        table.insert(hidden_entities, inserter)
      end
    end

    -- Find electric-poles with ammo-loader names
    local all_poles = surface.find_entities_filtered{
      type = "electric-pole"
    }
    for _, pole in pairs(all_poles) do
      if pole.name == "ammo-loader-range-extender" then
        table.insert(hidden_entities, pole)
      end
    end

    migration_log("Found " .. #containers .. " containers and " .. #hidden_entities .. " hidden entities")

    -- Log details about hidden entities found without containers
    if #containers == 0 and #hidden_entities > 0 then
      migration_log("Found " .. #hidden_entities .. " orphaned hidden entities without corresponding containers on surface " .. surface.name)
      goto continue_surface
    end

    -- Check if there's a quality mismatch
    if not has_quality_mismatch(containers, hidden_entities) then
      migration_log("No quality mismatch found on surface " .. surface.name)
      goto continue_surface
    end

    migration_log("Quality mismatch detected on surface " .. surface.name .. ", fixing...")

    -- Save container data before destruction
    local containers_data = {}
    for _, container in pairs(containers) do
      local data = save_container_data(container)
      if data then
        table.insert(containers_data, data)
      end
    end

    if #containers_data == 0 then
      migration_log("No valid container data to save on surface " .. surface.name)
      goto continue_surface
    end

    -- Log hidden entities before destruction for debugging
    for _, hidden_entity in pairs(hidden_entities) do
      migration_log("Hidden entity before destruction: " .. hidden_entity.name ..
                    " at " .. serpent.line(hidden_entity.position) ..
                    " quality=" .. hidden_entity.quality.name ..
                    " unit_number=" .. hidden_entity.unit_number)
    end

    -- Destroy containers (this should trigger ammo-loader to clean up hidden entities)
    for _, container in pairs(containers) do
      if container.valid then
        script.raise_script_destroy{entity = container}
        container.destroy{raise_destroy = true}
      end
    end

    migration_log("Destroyed " .. #containers .. " containers")

    -- Wait a bit and check if hidden entities were cleaned up
    local remaining_hidden = {}
    -- Find remaining inserters
    local remaining_inserters = surface.find_entities_filtered{
      type = "inserter"
    }
    for _, inserter in pairs(remaining_inserters) do
      if inserter.name == "ammo-loader-hidden-inserter" then
        table.insert(remaining_hidden, inserter)
      end
    end

    -- Find remaining electric-poles
    local remaining_poles = surface.find_entities_filtered{
      type = "electric-pole"
    }
    for _, pole in pairs(remaining_poles) do
      if pole.name == "ammo-loader-range-extender" then
        table.insert(remaining_hidden, pole)
      end
    end

    if #remaining_hidden > 0 then
      migration_log("WARNING: " .. #remaining_hidden .. " hidden entities not cleaned up by ammo-loader, manually destroying:")
      for _, hidden_entity in pairs(remaining_hidden) do
        migration_log("  Manually destroying: " .. hidden_entity.name ..
                      " at " .. serpent.line(hidden_entity.position) ..
                      " quality=" .. hidden_entity.quality.name ..
                      " unit_number=" .. hidden_entity.unit_number)
        hidden_entity.destroy{raise_destroy = false}
      end
    end

    -- Recreate containers
    local recreated_containers = {}
    for _, container_data in pairs(containers_data) do
      local new_container = recreate_container(container_data)
      if new_container then
        table.insert(recreated_containers, new_container)
      end
    end

    migration_log("Recreated " .. #recreated_containers .. " containers")
    total_containers_fixed = total_containers_fixed + #recreated_containers

    -- Validate that hidden entities were recreated
    local found_inserters, found_extenders = check_hidden_entities_exist(surface, containers_data)

    if found_inserters == 0 and found_extenders == 0 then
      migration_log("WARNING: No hidden entities found after recreation, registering delayed check")

      -- Register a delayed check in 240 ticks (4 seconds)
      script.on_nth_tick(240, function()
        local delayed_inserters, delayed_extenders = check_hidden_entities_exist(surface, containers_data)
        migration_log("Delayed check results: " .. delayed_inserters .. " inserters, " .. delayed_extenders .. " extenders")
        script.on_nth_tick(240, nil) -- Unregister the handler
      end)
    end

    ::continue_surface::
  end

  migration_log("Migration completed. Processed " .. total_surfaces_processed .. " surfaces, fixed " .. total_containers_fixed .. " containers")
end

-- Run the migration
fix_ammo_loader_compatibility()