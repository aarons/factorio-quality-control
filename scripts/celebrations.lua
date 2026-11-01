-- Short-lived, player-filtered drawings. Captured positions keep effects safe
-- when the upgraded entity is replaced again or removed during the animation.
local celebrations = {}
local lifetime = 90
local badge_lifetime = lifetime * 3
local badge_start_scale = 1.5
local badge_end_scale = badge_start_scale * 2.5
local bubble_count = 18
local bubble_lifetime = 120
local white = {r = 1, g = 1, b = 1}
local rainbow = {
  {r = 1, g = 0.2, b = 0.2}, {r = 1, g = 0.7, b = 0.1},
  {r = 0.3, g = 1, b = 0.3}, {r = 0.2, g = 0.7, b = 1},
  {r = 0.7, g = 0.3, b = 1},
}

local function faded(color, opacity)
  return {r = color.r * opacity, g = color.g * opacity, b = color.b * opacity, a = opacity}
end

local function remember(object, player, entity, setting, kind, color, phase, duration)
  storage.quality_celebrations = storage.quality_celebrations or {}
  local effect = {
    object = object, player_index = player.index, force_index = entity.force.index,
    setting = setting, kind = kind, color = color, phase = phase or 0,
    position = {x = entity.position.x, y = entity.position.y}, start_tick = game.tick,
    duration = duration or lifetime,
  }
  table.insert(storage.quality_celebrations, effect)
  return effect
end

local function show_bubbles(player, entity, quality, setting)
  local bounds = entity.bounding_box
  local width = bounds.right_bottom.x - bounds.left_top.x
  local height = bounds.right_bottom.y - bounds.left_top.y
  -- Explicitly seed a separate generator so cosmetics never advance gameplay randomness.
  local seed = ((game.tick + (entity.unit_number or 0)) * 104729) % 4294967296
  local random = game.create_random_generator(seed)
  for index = 1, bubble_count do
    local delay = 12 + (index - 1) * 6
    -- Permuted lanes give a varied stream without consuming gameplay randomness.
    local lane = ((index * 7) % 19 - 9) / 9
    local position = {
      x = bounds.left_top.x + random() * width,
      y = bounds.left_top.y + random() * height,
    }
    local object = rendering.draw_sprite{
      sprite = "quality/" .. quality.name, target = position,
      surface = entity.surface, players = {player.index},
      time_to_live = delay + bubble_lifetime, color = faded(white, 0),
      x_scale = 0.25, y_scale = 0.25,
    }
    local effect = remember(object, player, entity, setting, "bubble", white, index, bubble_lifetime)
    effect.start_tick = game.tick + delay
    effect.position = position
    effect.drift = lane * 2
    effect.rise = 2.5 + (index % 4) * 0.5
  end
end

function celebrations.show(player, entity, quality, preferences)
  local color = quality.color
  for _, style in ipairs({"halo", "rainbow"}) do
    local setting = "quality-change-" .. style .. "-enabled"
    if preferences[setting].value then
      local count = style == "rainbow" and 3 or 1
      for ring = 1, count do
        local phase = (ring - 1) / count
        local ring_color = style == "rainbow" and rainbow[ring] or color
        local object = rendering.draw_circle{
          color = ring_color, radius = 0.5 + phase, width = 3, filled = false,
          target = entity.position, surface = entity.surface, players = {player.index},
          time_to_live = lifetime, draw_on_ground = true,
        }
        remember(object, player, entity, setting, style, ring_color, phase)
      end
    end
  end

  local setting = "quality-change-badge-enabled"
  if preferences[setting].value then
    local object = rendering.draw_sprite{
      sprite = "quality/" .. quality.name, target = {entity.position.x, entity.position.y - 1},
      surface = entity.surface, players = {player.index}, time_to_live = badge_lifetime,
      x_scale = badge_start_scale, y_scale = badge_start_scale,
    }
    remember(object, player, entity, setting, "badge", white, nil, badge_lifetime)
  end

  setting = "quality-change-bubbles-enabled"
  if preferences[setting].value then
    show_bubbles(player, entity, quality, setting)
  end
end

function celebrations.on_tick()
  local effects = storage.quality_celebrations
  if not effects then return end
  -- Compact in place so a burst's cleanup remains linear in its effect count.
  local remaining = 0
  for _, effect in ipairs(effects) do
    local object = effect.object
    local player = game.get_player(effect.player_index)
    local age = game.tick - effect.start_tick
    -- Effects saved by older versions have the original 90-tick duration.
    local duration = effect.duration or lifetime
    if not object.valid or age >= duration or not player or not player.valid
      or not player.connected or player.force.index ~= effect.force_index
      or not settings.get_player_settings(player)[effect.setting].value then
      if object.valid then object.destroy() end
    else
      local progress = math.max(0, age / duration)
      local opacity = 1 - progress
      if effect.kind == "badge" then
        -- Finish growing before fading, while keeping the rotation in motion throughout.
        local settle = math.min(1, progress / 0.7)
        local eased = 1 - (1 - settle) ^ 3
        local scale = badge_start_scale + (badge_end_scale - badge_start_scale) * eased
        object.target = {effect.position.x, effect.position.y - 1 - progress}
        object.orientation = progress
        object.x_scale, object.y_scale = scale, scale
        opacity = math.min(1, (1 - progress) / 0.25)
        object.color = faded(effect.color, opacity)
      elseif effect.kind == "bubble" then
        local sway = math.sin(progress * math.pi * 2 + effect.phase) - math.sin(effect.phase)
        object.target = {
          effect.position.x + effect.drift * progress + sway * 0.2,
          effect.position.y - effect.rise * progress,
        }
        local scale = 0.25 + 0.35 * math.min(1, progress / 0.3)
        object.x_scale, object.y_scale = scale, scale
        opacity = age < 0 and 0 or math.min(1, progress / 0.1, (1 - progress) / 0.4)
        object.color = faded(effect.color, opacity)
      else
        object.radius = 0.5 + effect.phase + progress * 3
        local color = effect.color
        if effect.kind == "rainbow" then
          color = rainbow[(math.floor(progress * #rainbow + effect.phase * #rainbow) % #rainbow) + 1]
        end
        object.color = faded(color, opacity)
      end
      remaining = remaining + 1
      effects[remaining] = effect
    end
  end
  for index = #effects, remaining + 1, -1 do effects[index] = nil end
  if remaining == 0 then storage.quality_celebrations = nil end
end

return celebrations
