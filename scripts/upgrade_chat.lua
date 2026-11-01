-- Translate before coloring so rainbow letters work in each player's language.
local chat = {}

local colors = {"1,0.45,0.45", "1,0.7,0.3", "1,0.95,0.4", "0.45,1,0.55", "0.4,0.8,1", "0.8,0.55,1"}

function chat.colorize(text, seed)
  local parts, previous_color = {}, 0
  -- Use a private pseudo-random sequence, never the gameplay RNG.
  seed = seed % 2147483646 + 1
  local function append_letters(plain)
    -- Match whole UTF-8 codepoints rather than individual bytes (Lua 5.2).
    for letter in plain:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if letter:match("%s") then
        parts[#parts + 1] = letter
      else
        seed = (seed * 48271) % 2147483647
        -- Advance by at least one color so adjacent letters never match.
        local step = 1 + seed % (#colors - 1)
        local color = (previous_color - 1 + step) % #colors + 1
        previous_color = color
        parts[#parts + 1] = "[color=" .. colors[color] .. "]" .. letter .. "[/color]"
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
    -- Preserve sprites and other rich text; replace preexisting text colors.
    if not tag:match("^%[color=") and tag ~= "[/color]" then
      parts[#parts + 1] = tag
    end
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
    message = event.translated and chat.colorize(event.result, event.id + event.player_index) or entry.message
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
