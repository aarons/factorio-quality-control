--[[
quality_selector.lua

Handles probability-based quality selection using a bucket distribution system.
Precomputes lookup tables for efficient runtime quality selection.
]]

local quality_selector = {}

-- Constants and module state
local BUCKET_COUNT = 1000
local quality_buckets = {}
local skip_hidden_qualities = false
local sticky_hidden_qualities = true

-- Build a bucket array for a single starting quality
-- Each bucket contains a target quality name, distributed according to next_probability
local function build_bucket_array(start_quality)
  local buckets = {}
  local idx = 1
  local remaining_prob = 1.0
  local current = start_quality.next

  -- Walk chain until terminal quality or probability exhausted
  while current and current.next and remaining_prob >= 0.0001 do
    -- Skip hidden qualities if setting enabled
    -- IMPORTANT: Do NOT apply the hidden quality's probability - pretend it doesn't exist
    if skip_hidden_qualities and current.hidden then
      current = current.next
    else
      -- Clamp next_probability to valid range (protect against buggy mods)
      local continue_prob = math.max(0, math.min(1, current.next_probability or 0.1))
      local stop_prob = 1 - continue_prob

      -- Minimum 1 bucket ensures rare outcomes remain possible
      local bucket_count = math.max(1, math.floor(remaining_prob * stop_prob * BUCKET_COUNT + 0.5))

      -- Don't exceed remaining buckets
      bucket_count = math.min(bucket_count, BUCKET_COUNT - idx + 1)

      for _ = 1, bucket_count do
        buckets[idx] = current.name
        idx = idx + 1
      end

      remaining_prob = remaining_prob * continue_prob
      current = current.next
    end
  end

  -- Terminal quality gets remaining buckets
  if current then
    -- If terminal is hidden and we're skipping, find next non-hidden
    if skip_hidden_qualities and current.hidden then
      while current and current.hidden do
        current = current.next
      end
    end

    if current then
      while idx <= BUCKET_COUNT do
        buckets[idx] = current.name
        idx = idx + 1
      end
    end
  end

  return buckets
end

-- Initialize the quality selector with settings
-- Precomputes bucket lookup tables for all qualities
function quality_selector.initialize(skip_hidden, sticky_hidden)
  skip_hidden_qualities = skip_hidden
  sticky_hidden_qualities = sticky_hidden
  quality_buckets = {}

  for name, quality in pairs(prototypes.quality) do
    -- Terminal quality: no upgrade path
    if not quality.next then
      quality_buckets[name] = nil
    -- Sticky hidden: shiny entities don't upgrade
    elseif sticky_hidden_qualities and quality.hidden then
      quality_buckets[name] = nil
    else
      quality_buckets[name] = build_bucket_array(quality)
    end
  end
end

-- Get the next quality for an upgrade using probability-weighted bucket selection
-- Returns nil if no upgrade path exists (terminal quality, sticky hidden, or empty buckets)
function quality_selector.get_next_quality(current_quality_name)
  local buckets = quality_buckets[current_quality_name]
  if not buckets or buckets[1] == nil then return nil end -- Terminal, sticky hidden, or empty
  return buckets[math.random(1, BUCKET_COUNT)]
end

-- Check if a quality has any upgrade path (for tracking decisions)
function quality_selector.has_upgrade_path(quality_name)
  local buckets = quality_buckets[quality_name]
  return buckets ~= nil and buckets[1] ~= nil
end

-- Check if a quality should be skipped based on hidden quality settings
-- Returns true if skip_hidden_qualities is enabled AND the quality is hidden
function quality_selector.should_skip_quality(quality)
  return skip_hidden_qualities and quality.hidden
end

return quality_selector
