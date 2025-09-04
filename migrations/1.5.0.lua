--[[
Migration 1.5.0 - Initialize item count cache for logistics network optimization

This migration initializes the new storage.item_count_cache for the logistics network
scanning optimization introduced in version 1.5.0.
]]

-- Initialize the new cache structure
storage.item_count_cache = {}

log("[Quality Control Migration 1.5.0] Migration completed - item count cache initialized")