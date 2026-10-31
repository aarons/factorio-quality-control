-- luacheck: globals math
local music = require("scripts.upgrade_music")
local sounds = require("scripts.upgrade_sounds")
local reload_music = assert(loadfile("scripts/upgrade_music.lua"))
local tests = {}
local function equal(actual, expected)
  assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

storage = {}
math.random = function() error("music must not consume gameplay randomness") end

local function preferences(sound, root, mode, scale, range)
  return {
    ["quality-change-sound"] = {value = sound or "instrument-piano"},
    ["quality-change-sound-note"] = {value = root or 8},
    ["quality-change-sound-mode"] = {value = mode or "staircase"},
    ["quality-change-sound-scale"] = {value = scale or "major"},
    ["quality-change-sound-range"] = {value = range or "one-octave"},
  }
end

local function note(prefs, player)
  local path = music.path(player or 1, prefs)
  local value = tonumber(path:match("%-(%d+)$"))
  assert(value, "expected an instrument note: " .. path)
  return value
end

function tests.ranges()
  local scales = {
    major = {[0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true},
    minor = {[0] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true, [10] = true},
    pentatonic = {[0] = true, [2] = true, [4] = true, [7] = true, [9] = true},
  }
  local instruments = 0
  for _, sound in ipairs(sounds.values) do
    local count = sounds.note_count(sound)
    if count then
      instruments = instruments + 1
      for _, mode in ipairs(music.modes) do
        for _, scale in ipairs(music.scales) do
          for _, range in ipairs(music.ranges) do
            -- All roots include every pitch class and both instrument boundaries.
            for root = 1, 48 do
              local prefs = preferences(sound, root, mode, scale, range)
              local seen = {}
              for _ = 1, 16 do
                local played = note(prefs)
                assert(played >= 1 and played <= count)
                seen[played] = true
                if mode == "fixed" then
                  equal(played, math.min(root, count))
                elseif mode ~= "random" then
                  local allowed = scales[mode == "wind-chimes" and "pentatonic" or scale]
                  assert(not allowed or allowed[(played - root) % 12], "note left the chosen key")
                  if range ~= "full" then
                    local width = range == "two-octaves" and 24 or 12
                    local first = root
                    while first + width - 1 > count do first = first - 12 end
                    assert(played >= first and played < first + width, "note left the chosen range")
                  end
                end
              end
              if mode ~= "fixed" then assert(next(seen, next(seen)), "pattern never varied") end
            end
          end
        end
      end
    end
  end
  equal(instruments, 9)
end

function tests.staircase()
  local prefs = preferences()
  for _, expected in ipairs({8, 10, 12, 13, 15, 17, 19, 17, 15, 13, 12, 10, 8, 10}) do
    equal(note(prefs), expected)
  end
  prefs["quality-change-sound-note"].value = 48
  prefs["quality-change-sound"].value = "instrument-bass"
  equal(note(prefs), 24) -- Whole-octave transposition preserves E, rather than clipping the pattern.
  equal(note(prefs), 26)
  prefs["quality-change-sound-range"].value = "full"
  equal(note(prefs), 36)
  equal(note(prefs), 35) -- At the top of the full range, descend immediately.
end

function tests.wander()
  local prefs = preferences(nil, nil, "wander")
  local positions = {[8] = 1, [10] = 2, [12] = 3, [13] = 4, [15] = 5, [17] = 6, [19] = 7}
  local previous = positions[note(prefs)]
  equal(previous, 1)
  for _ = 1, 1000 do
    local current = positions[note(prefs)]
    assert(current and math.abs(current - previous) <= 2, "wander jumped more than two scale steps")
    previous = current
  end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
  return result
end

function tests.lifecycle()
  for _, mode in ipairs({"wander", "staircase", "wind-chimes", "random-scale", "random"}) do
    storage = {}
    local prefs = preferences(nil, nil, mode)
    for _ = 1, 11 do note(prefs) end
    local saved = copy(storage)
    local expected = {}
    for index = 1, 30 do expected[index] = note(prefs) end
    storage = copy(saved)
    music = reload_music()
    for index = 1, 30 do
      note(prefs, 2) -- Another player's notifications cannot advance this player's sequence.
      equal(note(prefs), expected[index])
    end
    music.on_player_removed({player_index = 1})
    equal(storage.upgrade_music[1], nil)
    assert(storage.upgrade_music[2])
  end
  local prefs = preferences()
  equal(note(prefs), 8)
  equal(note(prefs), 10)
  prefs["quality-change-sound-scale"].value = "minor"
  equal(note(prefs), 8) -- Changing pattern settings restarts at the root.
  prefs["quality-change-sound-mode"].value = "fixed"
  equal(note(prefs), 8)
  equal(storage.upgrade_music[1], nil)
  prefs["quality-change-sound-mode"].value = "staircase"
  equal(note(prefs), 8)
end

function tests.effects()
  for _, sound in ipairs(sounds.values) do
    if not sounds.note_count(sound) then
      for _, mode in ipairs(music.modes) do
        equal(music.path(1, preferences(sound, 48, mode)), sounds.path(sound, 48))
        equal(storage.upgrade_music, nil)
      end
    end
  end
  for _, sound in ipairs({"instrument-piano", "instrument-bass"}) do
    local prefs = preferences(sound, 1, "random", "minor", "one-octave")
    local seen = {}
    for _ = 1, 2000 do seen[note(prefs)] = true end
    for index = 1, sounds.note_count(sound) do assert(seen[index], "random mode missed a note") end
  end
end

assert(tests[arg[1]], "unknown scenario")()
