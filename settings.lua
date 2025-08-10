data:extend({
    {
        type = "string-setting",
        name = "quality-change-direction",
        setting_type = "startup",
        default_value = "increase",
        allowed_values = {"increase", "decrease"},
        order = "a-0"
    },
    {
        type = "double-setting",
        name = "manufacturing-hours-for-change",
        setting_type = "startup",
        default_value = 5,
        min_value = 0.001,
        max_value = 1000,
        order = "a-1"
    },
    {
        type = "double-setting",
        name = "percentage-chance-of-change",
        setting_type = "startup",
        default_value = 1,
        min_value = 0.0001,
        max_value = 100,
        order = "a-2"
    },
    {
        type = "double-setting",
        name = "quality-increase-cost",
        setting_type = "startup",
        default_value = 0.3,
        min_value = 0,
        max_value = 1000,
        order = "a-3"
    },
    {
        type = "string-setting",
        name = "quality-chance-accumulation-rate",
        setting_type = "startup",
        default_value = "none",
        allowed_values = {"none", "low", "medium", "high"},
        order = "a-4"
    },
    {
        type = "double-setting",
        name = "upgrade-check-frequency-seconds",
        setting_type = "runtime-global",
        default_value = 10,
        min_value = 1,
        max_value = 3600,
        order = "b-0"
    },
    {
        type = "bool-setting",
        name = "quality-change-aggregate-alerts-enabled",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "c-0"
    },
    {
        type = "bool-setting",
        name = "quality-change-entity-alerts-enabled",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "c-1"
    },
    -- Entity type selection settings
    {
        type = "string-setting",
        name = "primary-entities-selection",
        setting_type = "startup",
        default_value = "both",
        allowed_values = {"both", "assembly-machines-only", "furnaces-only"},
        order = "d-0"
    },
    -- Secondary entity categories
    {
        type = "bool-setting",
        name = "enable-electrical-entities",
        setting_type = "startup",
        default_value = true,
        order = "d-1"
    },
    {
        type = "bool-setting",
        name = "enable-other-production-entities",
        setting_type = "startup",
        default_value = true,
        order = "d-2"
    },
    {
        type = "bool-setting",
        name = "enable-defense-entities",
        setting_type = "startup",
        default_value = true,
        order = "d-3"
    },
    {
        type = "bool-setting",
        name = "enable-space-entities",
        setting_type = "startup",
        default_value = true,
        order = "d-4"
    },
    {
        type = "bool-setting",
        name = "enable-other-entities",
        setting_type = "startup",
        default_value = true,
        order = "d-5"
    },
    -- Standalone entity types
    {
        type = "bool-setting",
        name = "enable-labs",
        setting_type = "startup",
        default_value = true,
        order = "d-6"
    },
    {
        type = "bool-setting",
        name = "enable-roboports",
        setting_type = "startup",
        default_value = true,
        order = "d-7"
    },
    {
        type = "bool-setting",
        name = "enable-beacons",
        setting_type = "startup",
        default_value = true,
        order = "d-8"
    },
    {
        type = "bool-setting",
        name = "enable-pumps",
        setting_type = "startup",
        default_value = true,
        order = "d-9"
    },
    {
        type = "bool-setting",
        name = "enable-radar",
        setting_type = "startup",
        default_value = true,
        order = "d-10"
    },
    {
        type = "bool-setting",
        name = "enable-inserters",
        setting_type = "startup",
        default_value = true,
        order = "d-11"
    }
})