-- Loaded ONLY into the runner's temporary Quality Control copy. Reads existing
-- tracking state without registering entities or calling production processing.
-- luacheck: globals helpers
local notifications = require("scripts.notifications")
local upgrade_sounds = require("scripts.upgrade_sounds")

local function info(entity)
  return assert(storage.quality_control_entities[entity.unit_number], "QC_TEST FAIL: host not tracked")
end

remote.add_interface("qc-test", {
  validate_upgrade_sounds = function()
    local paths = {}
    local count = 0
    for _, value in ipairs(upgrade_sounds.values) do
      for note = 1, 48 do
        local path = upgrade_sounds.path(value, note)
        assert(helpers.is_valid_sound_path(path), "QC_TEST FAIL: invalid upgrade sound " .. tostring(path))
        if not paths[path] then
          paths[path] = true
          count = count + 1
        end
      end
    end
    return count
  end,
  snapshot = function(entity)
    local state = info(entity)
    local lines = {}
    notifications.test_append_module_info(lines, entity, state)
    return {
      bonuses = state.module_failure_bonuses,
      bookmark = state.module_last_seen_meter,
      host_bookmark = state.last_seen_meter,
      meter = storage.surface_meters[entity.surface_index] or 0,
      inspection = lines,
      batch_index = storage.batch_index,
      queue = storage.entity_list,
    }
  end,
  seed_bonuses = function(entity, bonuses)
    info(entity).module_failure_bonuses = bonuses
  end,
  guarantee_host_upgrade = function(entity)
    info(entity).chance_to_change = 1000000
  end,
  set_batch_size = function(size)
    -- Runtime settings may only be changed by their owning mod.
    settings.global["batch-entities-per-tick"] = {value = size}
  end,
})
