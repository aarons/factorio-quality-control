-- One note per audible upgrade. This module owns musical patterns and their
-- per-player save state; it has no tick handler, queue, or entity history.
local sounds = require("scripts.upgrade_sounds")
local music = {
  modes = {"fixed", "wander", "wind-chimes", "staircase", "random-scale", "random"},
  scales = {"major", "minor", "pentatonic", "chromatic"},
  ranges = {"one-octave", "two-octaves", "full"},
}

local intervals = {
  major = {0, 2, 4, 5, 7, 9, 11},
  minor = {0, 2, 3, 5, 7, 8, 10},
  pentatonic = {0, 2, 4, 7, 9},
  chromatic = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
}

-- A separate Park-Miller generator keeps cosmetic choices from consuming the
-- gameplay RNG. Products remain exact even in Lua's double-precision numbers.
local function random_index(state, count)
  state.seed = (state.seed * 48271) % 2147483647
  return 1 + math.floor((state.seed - 1) / 2147483646 * count)
end

local function make_notes(count, root, scale, range)
  -- Preserve the root's pitch class on shorter instruments by shifting octaves,
  -- rather than clamping several different roots to the same highest note.
  while root > count do root = root - 12 end
  local first, last = 1, count
  if range ~= "full" then
    local width = range == "two-octaves" and 24 or 12
    while root + width - 1 > count do root = root - 12 end
    first, last = root, root + width - 1
  end
  local allowed = {}
  for _, interval in ipairs(intervals[scale]) do allowed[interval] = true end
  local notes, start = {}, 1
  for note = first, last do
    if allowed[(note - root) % 12] then
      notes[#notes + 1] = note
      if note == root then start = #notes end
    end
  end
  return notes, start
end

local patterns = {}

function patterns.wander(state)
  if state.started then
    -- Move one or two scale steps, reflecting at the edges.
    local step = random_index(state, 4)
    local offset = ({-2, -1, 1, 2})[step]
    local position = state.position + offset
    if position < 1 then position = 2 - position end
    if position > #state.notes then position = 2 * #state.notes - position end
    state.position = position
  end
  state.started = true
  return state.notes[state.position]
end

function patterns.staircase(state)
  if state.started then
    local position = state.position + state.direction
    if position < 1 or position > #state.notes then
      state.direction = -state.direction
      position = state.position + state.direction
    end
    state.position = position
  end
  state.started = true
  return state.notes[state.position]
end

local function random_note(state)
  return state.notes[random_index(state, #state.notes)]
end

patterns["wind-chimes"] = random_note
patterns["random-scale"] = random_note
patterns.random = random_note

function music.clear_player(player_index)
  if storage.upgrade_music then storage.upgrade_music[player_index] = nil end
end

function music.on_player_removed(event)
  music.clear_player(event.player_index)
end

function music.path(player_index, preferences)
  local sound = preferences["quality-change-sound"].value
  local root = preferences["quality-change-sound-note"].value
  local mode = preferences["quality-change-sound-mode"].value
  local count = sounds.note_count(sound)
  if mode == "fixed" or not count then
    music.clear_player(player_index)
    return sounds.path(sound, root)
  end

  local scale = preferences["quality-change-sound-scale"].value
  local range = preferences["quality-change-sound-range"].value
  if mode == "wind-chimes" then scale = "pentatonic" end
  if mode == "random" then scale, range = "chromatic", "full" end
  storage.upgrade_music = storage.upgrade_music or {}
  local state = storage.upgrade_music[player_index]
  if not state or state.sound ~= sound or state.root ~= root or state.mode ~= mode
    or state.scale ~= scale or state.range ~= range then
    local notes, start = make_notes(count, root, scale, range)
    state = {
      sound = sound, root = root, mode = mode, scale = scale, range = range,
      notes = notes, position = start, direction = 1,
      seed = state and state.seed or (player_index % 2147483646 + 1),
    }
    storage.upgrade_music[player_index] = state
  end
  return sounds.path(sound, patterns[mode](state))
end

return music
