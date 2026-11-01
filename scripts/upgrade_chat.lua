-- Translate before coloring so rainbow letters work in each player's language.
local chat = {}

local colors = {{1, 0.45, 0.45}, {1, 0.7, 0.3}, {1, 0.95, 0.4}, {0.45, 1, 0.55}, {0.4, 0.8, 1}, {0.8, 0.55, 1}}
local letters_per_transition = 7

local function gradient_color(position)
  local index = math.floor(position / letters_per_transition) % #colors + 1
  local start_color, end_color = colors[index], colors[index % #colors + 1]
  local blend = (position % letters_per_transition) / letters_per_transition
  return string.format("%.3f,%.3f,%.3f",
    start_color[1] + (end_color[1] - start_color[1]) * blend,
    start_color[2] + (end_color[2] - start_color[2]) * blend,
    start_color[3] + (end_color[3] - start_color[3]) * blend)
end

function chat.colorize(text, start_position)
  local parts, color_depth = {}, 0
  -- Move smoothly from the chosen starting hue through the whole palette,
  -- including the violet-to-coral transition.
  local position_in_gradient = start_position % (#colors * letters_per_transition)
  local function append_letters(plain)
    -- Explicit colors (such as the quality name) retain their meaning, wherever
    -- the translated sentence places them.
    if color_depth > 0 then
      parts[#parts + 1] = plain
      return
    end
    -- Match whole UTF-8 codepoints rather than individual bytes (Lua 5.2).
    for letter in plain:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if letter:match("%s") then
        parts[#parts + 1] = letter
      else
        parts[#parts + 1] = "[color=" .. gradient_color(position_in_gradient) .. "]" .. letter .. "[/color]"
        position_in_gradient = position_in_gradient + 1
      end
    end
  end

  local position = 1
  while position <= #text do
    local first, last = text:find("%b[]", position)
    if not first then
      append_letters(text:sub(position))
      break
    end
    append_letters(text:sub(position, first - 1))
    local tag = text:sub(first, last)
    -- Preserve rich text and keep explicitly colored spans out of the gradient.
    if tag:match("^%[color=") then
      color_depth = color_depth + 1
    elseif tag == "[/color]" then
      color_depth = math.max(0, color_depth - 1)
    end
    parts[#parts + 1] = tag
    position = last + 1
  end
  return table.concat(parts)
end

local function print_message(player, message)
  player.print(message, {sound = defines.print_sound.never, skip = defines.print_skip.never})
end

function chat.show(player, entity, message, preferences)
  local gps = preferences["quality-change-gps-enabled"].value and entity.gps_tag or nil
  if not preferences["quality-change-chat-enabled"].value then
    if gps then print_message(player, gps) end
    return
  end

  local id = player.request_translation(message)
  storage.quality_upgrade_chat = storage.quality_upgrade_chat or {}
  local pending = storage.quality_upgrade_chat[player.index] or {}
  storage.quality_upgrade_chat[player.index] = pending
  pending[id] = {message = message, gps = gps, force_index = entity.force.index}
end

function chat.on_string_translated(event)
  local requests = storage.quality_upgrade_chat
  local pending = requests and requests[event.player_index]
  local entry = pending and pending[event.id]
  if not entry then return end
  pending[event.id] = nil
  if not next(pending) then requests[event.player_index] = nil end
  if not next(requests) then storage.quality_upgrade_chat = nil end

  local player = game.get_player(event.player_index)
  if not player or not player.valid or not player.connected or player.force.index ~= entry.force_index then return end
  local preferences = settings.get_player_settings(player)
  local message
  if preferences["quality-change-chat-enabled"].value then
    -- Failed translations still get the ordinary localized message.
    message = entry.message
    if event.translated then
      -- Seed a separate cosmetic generator so chat never affects upgrade rolls.
      local seed = ((event.id + event.player_index) * 104729) % 4294967296
      local random = game.create_random_generator(seed)
      message = chat.colorize(event.result, random() * #colors * letters_per_transition)
    end
  end
  if entry.gps and preferences["quality-change-gps-enabled"].value then
    message = message and {"", message, " ", entry.gps} or entry.gps
  end
  if message then print_message(player, message) end
end

function chat.clear_player(event)
  local requests = storage.quality_upgrade_chat
  if not requests then return end
  requests[event.player_index] = nil
  if not next(requests) then storage.quality_upgrade_chat = nil end
end

return chat
