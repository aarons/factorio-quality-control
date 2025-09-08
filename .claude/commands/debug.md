We are working on debugging a problem. Please add some temporary logging statements to help us investigate and understand the issue better. If you notice any obvious logical issues please also point them out.

Context:
$ARGUMENTS

Do not worry about ./validate.sh flagging errors related to line length of cyclomatic complexity, as we can temporarily take on extra complexity to identify issues.

Here are some helpful debugging patterns we've put together in the past:

**Info dump about entities**

```lua
local debug_msg = "QC Debug: registered new tracked entity - " ..
    "id=" .. tostring(id) ..
    ", name=" .. (entity.name or "nil") ..
    ", type=" .. (entity.type or "nil") ..
    ", quality=" .. (entity.quality.name or "nil") ..
    ", surface=" .. (entity.surface.name or "nil") ..
    ", position={" .. (entity.position.x or 0) .. "," .. (entity.position.y or 0) .. "}" ..
    ", is_primary=" .. tostring(is_primary) ..
    ", force=" .. (entity.force.name or "nil") ..
    ", unit_number=" .. (entity.unit_number or "nil")
log(debug_msg)
```

**Storing problematic entities in a lookup table to check for later**
```lua

-- Temporary debug tracking for registered entities
local debug_registered_entities = {}

function core.get_entity_info(entity)
    if entity.quality.name == "normal" then
        debug_registered_entities[id] = true
    end
 -- rest of the function
end

function core.remove_entity_info(id)
  -- Debug logging for tracked entity removals
  if debug_registered_entities[id] then
    log("QC Debug: removing tracked entity - id=" .. tostring(id))
    debug_registered_entities[id] = nil
  end
  -- rest of the function..
end
```

**Search the previous entities location for info about what replaced it**
```lua
      if debug_registered_entities[unit_number] then
        log("QC Debug: Entity became invalid - unit_number=" .. tostring(unit_number))

        if entity_info then
          log("  Original info: name=" .. (entity_info.original_name or "nil") ..
              ", position={" .. (entity_info.original_position and entity_info.original_position.x or "nil") ..
              "," .. (entity_info.original_position and entity_info.original_position.y or "nil") .. "}")

          -- Try to find what's at the original position now
          if entity_info.original_surface and entity_info.original_surface.valid and entity_info.original_position then
            local found_entities = entity_info.original_surface.find_entities_filtered{
              position = entity_info.original_position,
              radius = 0.5
            }

            if #found_entities > 0 then
              log("  Entities found at original position:")
              for _, found_entity in pairs(found_entities) do
                local item_name = "nil"
                if found_entity.prototype and found_entity.prototype.items_to_place_this then
                  local items = found_entity.prototype.items_to_place_this
                  if items and #items > 0 then
                    item_name = items[1].name
                  end
                end

                log("    - name=" .. (found_entity.name or "nil") ..
                    ", type=" .. (found_entity.type or "nil") ..
                    ", quality=" .. (found_entity.quality and found_entity.quality.name or "nil") ..
                    ", surface=" .. (found_entity.surface and found_entity.surface.name or "nil") ..
                    ", position={" .. (found_entity.position.x or 0) .. "," .. (found_entity.position.y or 0) .. "}" ..
                    ", force=" .. (found_entity.force and found_entity.force.name or "nil") ..
                    ", unit_number=" .. (found_entity.unit_number or "nil") ..
                    ", item_name=" .. item_name)
              end
            else
              log("  No entities found at original position")
            end
          end
        end

        -- Remove from debug list after logging
        debug_registered_entities[unit_number] = nil
      end
```


