--[[
Migration 1.5.0 - Initialize inventory system storage tables

This migration ensures that the inventory system storage tables are properly initialized
for existing save games. These tables were previously created during on_load which
violates Factorio's API requirements.

This migration adds the missing storage tables:
- storage.network_quality_scans: Tracks network scanning data
- storage.pending_upgrades: Tracks pending entity upgrades
]]

-- Initialize inventory system storage tables if they don't exist
if not storage.network_quality_scans then
  storage.network_quality_scans = {}
end

if not storage.pending_upgrades then
  storage.pending_upgrades = {}
end

