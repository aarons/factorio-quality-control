-- Short-lived, player-filtered drawings. Captured positions keep effects safe
-- when the upgraded entity is replaced again or removed during the animation.
local celebrations = {}
local lifetime = 90
local rainbow = {
  {r = 1, g = 0.2, b = 0.2}, {r = 1, g = 0.7, b = 0.1},
  {r = 0.3, g = 1, b = 0.3}, {r = 0.2, g = 0.7, b = 1},
  {r = 0.7, g = 0.3, b = 1},
}

local function faded(color, opacity)
  return {r = color.r * opacity, g = color.g * opacity, b = color.b * opacity, a = opacity}
end

local function remember(object, player, entity, setting, kind, color, phase)
  storage.quality_celebrations = storage.quality_celebrations or {}
  table.insert(storage.quality_celebrations, {
    object = object, player_index = player.index, force_index = entity.force.index,
    setting = setting, kind = kind, color = color, phase = phase or 0,
    position = {x = entity.position.x, y = entity.position.y}, start_tick = game.tick,
  })
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
      surface = entity.surface, players = {player.index}, time_to_live = lifetime,
      x_scale = 1.5, y_scale = 1.5,
    }
    remember(object, player, entity, setting, "badge", {r = 1, g = 1, b = 1})
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
    if not object.valid or age >= lifetime or not player or not player.valid
      or not player.connected or player.force.index ~= effect.force_index
      or not settings.get_player_settings(player)[effect.setting].value then
      if object.valid then object.destroy() end
    else
      local progress = age / lifetime
      local opacity = 1 - progress
      if effect.kind == "badge" then
        object.target = {effect.position.x, effect.position.y - 1 - progress}
        object.orientation = progress
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
