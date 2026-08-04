--[[
effects.lua

Draws a short "sparkle" visual on entities when their quality is upgraded.
The effect shows the new quality's icon over the entity, a brief glow tinted
with the quality's color, and a few small sparkle icons scattered across the
entity's footprint. Everything is derived from the entity's selection box and
the quality prototype, so it works for any entity size and any modded quality.

Effects are throttled so mod configurations that upgrade many entities in
rapid succession (even the same entity every tick) can't spam render objects:
- a per-position cooldown suppresses repeat effects on the same spot
- a global per-tick cap bounds the number of effects drawn in any single tick

All render objects are created with time_to_live, so the engine removes them
automatically and nothing needs to be tracked after creation.
]]

local effects = {}

local ICON_DURATION_TICKS = 80
local GLOW_DURATION_TICKS = 45
-- Minimum ticks between effects at the same position (the debounce). Kept
-- longer than ICON_DURATION_TICKS so effects on one entity never overlap.
local POSITION_COOLDOWN_TICKS = 120
local MAX_EFFECTS_PER_TICK = 5
-- How often expired position cooldowns are swept out of storage
local PRUNE_INTERVAL_TICKS = 600

-- Cache of quality icon sprite path validity. The prototype set is fixed for
-- the lifetime of the game session, so entries never need invalidation.
local quality_sprite_valid = {}

local function get_quality_sprite(quality_name)
  local sprite = "quality/" .. quality_name
  if quality_sprite_valid[sprite] == nil then
    quality_sprite_valid[sprite] = helpers.is_valid_sprite_path(sprite)
  end
  if quality_sprite_valid[sprite] then
    return sprite
  end
  return nil
end

-- Players who have the visual effect setting enabled. Render objects are
-- only drawn for these players.
local function get_effect_recipients()
  local recipients = {}
  for _, player in pairs(game.connected_players) do
    if settings.get_player_settings(player)["quality-change-visual-effects-enabled"].value then
      recipients[#recipients + 1] = player
    end
  end
  return recipients
end

local function draw_effect(entity, sprite, recipients)
  local box = entity.selection_box
  local width = box.right_bottom.x - box.left_top.x
  local height = box.right_bottom.y - box.left_top.y

  -- Quality icons are 64px, which rendering draws 2 tiles wide at scale 1.
  -- Scale the icon to roughly half the entity's smaller dimension.
  local icon_scale = math.min(math.max(math.min(width, height) / 4, 0.25), 2)

  rendering.draw_sprite({
    sprite = sprite,
    target = entity,
    surface = entity.surface,
    x_scale = icon_scale,
    y_scale = icon_scale,
    render_layer = "air-object",
    time_to_live = ICON_DURATION_TICKS,
    players = recipients
  })

  rendering.draw_light({
    sprite = "utility/light_medium",
    target = entity,
    surface = entity.surface,
    scale = math.max(width, height) * 0.9,
    intensity = 0.4,
    color = entity.quality.color,
    time_to_live = GLOW_DURATION_TICKS,
    players = recipients
  })

  -- Small sparkle icons scattered across the footprint, more for bigger entities
  local sparkle_count = math.min(2 + math.floor(width * height / 2), 8)
  for _ = 1, sparkle_count do
    local offset_x = (math.random() - 0.5) * width
    local offset_y = (math.random() - 0.5) * height
    rendering.draw_sprite({
      sprite = sprite,
      target = {entity = entity, offset = {offset_x, offset_y}},
      surface = entity.surface,
      x_scale = 0.15,
      y_scale = 0.15,
      render_layer = "air-object",
      time_to_live = math.random(20, ICON_DURATION_TICKS),
      players = recipients
    })
  end
end

function effects.show_upgrade_effect(entity)
  local state = storage.effect_state
  if not state then
    return
  end

  local tick = game.tick
  if tick ~= state.last_tick then
    state.last_tick = tick
    state.count_this_tick = 0

    if tick - state.last_prune_tick >= PRUNE_INTERVAL_TICKS then
      state.last_prune_tick = tick
      for key, expires_at in pairs(state.position_cooldowns) do
        if expires_at <= tick then
          state.position_cooldowns[key] = nil
        end
      end
    end
  end

  if state.count_this_tick >= MAX_EFFECTS_PER_TICK then
    return
  end

  -- Debounce by position rather than unit_number, because upgrading replaces
  -- the entity and gives it a new unit_number every time.
  local position = entity.position
  local position_key = entity.surface_index .. ":" .. position.x .. "," .. position.y
  local expires_at = state.position_cooldowns[position_key]
  if expires_at and expires_at > tick then
    return
  end

  local sprite = get_quality_sprite(entity.quality.name)
  if not sprite then
    return
  end

  local recipients = get_effect_recipients()
  if #recipients == 0 then
    return
  end

  state.count_this_tick = state.count_this_tick + 1
  state.position_cooldowns[position_key] = tick + POSITION_COOLDOWN_TICKS

  draw_effect(entity, sprite, recipients)
end

return effects
