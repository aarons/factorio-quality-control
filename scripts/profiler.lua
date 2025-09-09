--[[
profiler.lua

Performance profiling infrastructure for Quality Control mod.
Provides wrapper functions for Factorio's native profiler API and performance metrics collection.
]]

local profiler = {}

local profiling_enabled = false
local profiling_detail_level = "basic"
local profiling_report_frequency = 600 -- ticks (10 seconds)
local last_report_tick = 0

-- Performance metrics storage
local metrics = {
  batch_processing = {
    total_time = 0,
    call_count = 0,
    entities_processed = 0,
    max_time = 0
  },
  primary_processing = {
    total_time = 0,
    call_count = 0,
    max_time = 0
  },
  secondary_processing = {
    total_time = 0,
    call_count = 0,
    max_time = 0
  },
  upgrade_attempts = {
    total_time = 0,
    call_count = 0,
    max_time = 0
  },
  network_operations = {
    total_time = 0,
    call_count = 0,
    max_time = 0
  },
  entity_operations = {
    total_time = 0,
    call_count = 0,
    max_time = 0
  }
}

-- Active profiler instances
local profilers = {}

function profiler.initialize()
  if storage.profiling_settings then
    profiling_enabled = storage.profiling_settings.enabled
    profiling_detail_level = storage.profiling_settings.detail_level
    profiling_report_frequency = storage.profiling_settings.report_frequency
  end
end

function profiler.update_settings()
  if not storage.profiling_settings then
    storage.profiling_settings = {}
  end

  storage.profiling_settings.enabled = settings.global["enable-profiling"].value
  storage.profiling_settings.detail_level = settings.global["profiling-detail-level"].value
  storage.profiling_settings.report_frequency = settings.global["profiling-report-frequency"].value

  profiling_enabled = storage.profiling_settings.enabled
  profiling_detail_level = storage.profiling_settings.detail_level
  profiling_report_frequency = storage.profiling_settings.report_frequency
end

function profiler.is_enabled()
  return profiling_enabled
end

function profiler.create_profiler(name)
  if not profiling_enabled then
    return nil
  end

  local prof = game.create_profiler()
  profilers[name] = {
    profiler = prof,
    start_time = nil
  }

  return prof
end

function profiler.start(name)
  if not profiling_enabled then
    return
  end

  local prof_data = profilers[name]
  if prof_data and prof_data.profiler then
    prof_data.profiler.reset()
    prof_data.start_time = os.clock() -- Fallback timing for detailed analysis
  end
end

function profiler.stop(name, entity_count)
  if not profiling_enabled then
    return
  end

  local prof_data = profilers[name]
  if not prof_data or not prof_data.profiler then
    return
  end

  prof_data.profiler.stop()

  -- Store metrics if we're doing detailed profiling
  if profiling_detail_level == "detailed" and prof_data.start_time then
    local elapsed = os.clock() - prof_data.start_time
    local metric = metrics[name]

    if metric then
      metric.total_time = metric.total_time + elapsed
      metric.call_count = metric.call_count + 1
      metric.max_time = math.max(metric.max_time, elapsed)

      if entity_count then
        metric.entities_processed = (metric.entities_processed or 0) + entity_count
      end
    end
  end
end

function profiler.log_result(name, context)
  if not profiling_enabled then
    return
  end

  local prof_data = profilers[name]
  if prof_data and prof_data.profiler then
    local context_str = context and (" [" .. context .. "]") or ""
    log{"", "QC Profile - ", name, context_str, ": ", prof_data.profiler}
  end
end

function profiler.should_report()
  local current_tick = game.tick
  if current_tick - last_report_tick >= profiling_report_frequency then
    last_report_tick = current_tick
    return true
  end
  return false
end

function profiler.generate_report()
  if not profiling_enabled or profiling_detail_level ~= "detailed" then
    return
  end

  log("=== Quality Control Performance Report ===")
  log("Report Time: " .. game.tick .. " ticks")

  for name, metric in pairs(metrics) do
    if metric.call_count > 0 then
      local avg_time = metric.total_time / metric.call_count
      log(string.format("  %s:", name))
      log(string.format("    Calls: %d", metric.call_count))
      log(string.format("    Total Time: %.4fs", metric.total_time))
      log(string.format("    Average Time: %.4fs", avg_time))
      log(string.format("    Max Time: %.4fs", metric.max_time))

      if metric.entities_processed then
        local entities_per_call = metric.entities_processed / metric.call_count
        log(string.format("    Entities Processed: %d", metric.entities_processed))
        log(string.format("    Entities/Call: %.1f", entities_per_call))
      end
    end
  end

  log("==========================================")
end

function profiler.reset_metrics()
  for _, metric in pairs(metrics) do
    metric.total_time = 0
    metric.call_count = 0
    metric.max_time = 0
    if metric.entities_processed then
      metric.entities_processed = 0
    end
  end

  log("Quality Control: Performance metrics reset")
end

function profiler.get_metrics()
  return metrics
end

-- Convenience function for simple timing
function profiler.time_function(name, func, ...)
  if not profiling_enabled then
    return func(...)
  end

  profiler.start(name)
  local results = {func(...)}
  profiler.stop(name)

  return table.unpack(results)
end

-- Memory profiling helper
function profiler.check_memory(name)
  if not profiling_enabled or profiling_detail_level ~= "detailed" then
    return
  end

  collectgarbage("collect")
  local memory_kb = collectgarbage("count")
  log(string.format("QC Memory - %s: %.2f KB", name, memory_kb))
end

return profiler