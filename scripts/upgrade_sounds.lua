-- Vanilla sound assets shared by settings, prototype registration, and playback.
-- Keep the original utility IDs stable so existing player preferences survive.
local sounds = {values = {}, paths = {}, prototypes = {}}

local function utility(name)
  table.insert(sounds.values, name)
  sounds.paths[name] = "utility/" .. name
end

for _, name in ipairs({
  "research_completed", "achievement_unlocked", "new_objective", "console_message", "confirm",
  "crafting_finished", "scenario_message", "game_won", "game_lost", "alert_destroyed",
  "armor_insert", "armor_remove", "cannot_build", "gui_click", "list_box_click", "inventory_move",
  "console_player_joined", "console_player_left", "console_player_paused_game", "console_player_resumed_game",
  "console_player_died", "console_player_research", "console_platform_created", "console_platform_destroyed",
  "console_player_changed_logistic_group",
}) do utility(name) end

local function sample(name, filename)
  local path = "quality-control-upgrade-" .. name
  table.insert(sounds.prototypes, {
    type = "sound", name = path, category = "gui-effect", filename = filename,
  })
  return path
end

local function effect(group, name, filename)
  local value = group .. "-" .. name
  table.insert(sounds.values, value)
  sounds.paths[value] = sample(value, "__base__/sound/programmable-speaker/" .. filename .. ".ogg")
end

for _, name in ipairs({"alarm-1", "alarm-2", "buzzer-1", "buzzer-2", "buzzer-3", "ring", "siren"}) do
  effect("alarms", name, name)
end

for index, name in ipairs({
  "kick-1", "kick-2", "snare-1", "snare-2", "snare-3",
  "hat-1", "hat-2", "fx", "high-q", "perc-1",
  "perc-2", "crash", "reverse-cymbal", "clap", "shaker",
  "cowbell", "triangle",
}) do
  effect("drum-kit", name, string.format("kit-%02d", index))
end

-- Every vanilla pitched note has its own sample. The settings use the same
-- one-based note numbers as the programmable speaker.
for _, instrument in ipairs({
  {name = "piano", file = "piano1", count = 48},
  {name = "bass", file = "bass", count = 36},
  {name = "lead", file = "lead", count = 36},
  {name = "saw", file = "saw", count = 36},
  {name = "square", file = "square", count = 36},
  {name = "celesta", file = "celesta", count = 36},
  {name = "vibraphone", file = "vibraphone", count = 36},
  {name = "plucked", file = "plucked", count = 36},
  {name = "steel-drum", file = "steel-drum", count = 36},
}) do
  local value = "instrument-" .. instrument.name
  table.insert(sounds.values, value)
  local notes = {}
  for index = 1, instrument.count do
    local filename = string.format("__base__/sound/programmable-speaker/%s-%02d.ogg", instrument.file, index)
    notes[index] = sample(value .. "-" .. index, filename)
  end
  sounds.paths[value] = notes
end

function sounds.path(value, note)
  local path = sounds.paths[value]
  if type(path) == "table" then
    return path[math.min(note, #path)]
  end
  return path
end

return sounds
