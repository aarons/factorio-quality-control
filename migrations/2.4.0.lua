--[[
Migration 2.4.0 - Per-surface progression meters replace the global credit pool

Secondary entities now read a per-surface cumulative meter instead of drawing from a
global credit pool. The meters, per-surface primary counts, surface indexes, and
secondary meter bookmarks are all built by the full storage rebuild that
on_configuration_changed performs after this migration runs, so the only cleanup
needed here is dropping the old pool.
]]

log("[Quality Control Migration 2.4.0] Removing the global credit pool (replaced by per-surface progression meters)")

storage.accumulated_credits = nil
