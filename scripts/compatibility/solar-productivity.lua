--[[
solar-productivity.lua

Compatibility handler for the solar-productivity mod.
Handles entity replacements that occur without raised_built events when research is completed or reversed.
]]

local core = require("scripts.core")
local solar_productivity = {}

-- Queue for entities to be processed
local processing_queue = {}
local queue_processor_tick = 1


-- Process entities from queue in batches
local function process_entity_queue()
  local entities_per_batch = 10
  local processed = 0

  while #processing_queue > 0 and processed < entities_per_batch do
    local entity = processing_queue[#processing_queue]  -- Get last element
    processing_queue[#processing_queue] = nil            -- O(1) removal
    if entity.valid then
      core.get_entity_info(entity)
    end
    processed = processed + 1
  end

  -- If queue is empty, clean up and re-register batch_process_entities if needed
  if #processing_queue == 0 then
    script.on_nth_tick(queue_processor_tick, nil)
    -- Re-register batch_process_entities if it was using the same tick
    if storage.ticks_between_batches == queue_processor_tick then
      script.on_nth_tick(storage.ticks_between_batches, core.batch_process_entities)
    end
  end
end

-- Find and queue all solar panels and accumulators for processing
local function queue_solar_entities()
  processing_queue = {} -- Reset queue

  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{
      force = "player",
      type = {"solar-panel", "accumulator"}
    }
    for _, entity in pairs(entities) do
      table.insert(processing_queue, entity)
    end
  end

  -- Set up queue processor if we have entities to process
  if #processing_queue > 0 then
    script.on_nth_tick(queue_processor_tick, process_entity_queue)
  end
end

-- Handle solar-productivity research changes with delay
local function handle_solar_productivity_research(event)
  local research = event.research

  if research and research.name and research.name:find("^solar%-productivity%-") then
    -- Calculate delay to avoid conflicts with batch_process_entities
    -- SP processes over a period of 5 seconds by default, users can config up to an hour
    -- Waiting 60 seconds should catch most cases
    local delay = 3600 + (storage.ticks_between_batches or 300)

    -- Register delayed queue processing
    script.on_nth_tick(delay, function()
      script.on_nth_tick(delay, nil)
      queue_solar_entities()
    end)
  end
end

-- Check if solar-productivity mod is present and register events
function solar_productivity.initialize()
  if script.active_mods["solar-productivity"] then
    script.on_event(defines.events.on_research_finished, handle_solar_productivity_research)
    script.on_event(defines.events.on_research_reversed, handle_solar_productivity_research)
  end
end

return solar_productivity
