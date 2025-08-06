data:extend({
    -- General quality control settings
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
        default_value = true,
        order = "b-1"
    },
    {
        type = "bool-setting",
        name = "quality-change-entity-alerts-enabled",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "b-2"
    },
    -- Primary entity types
    {
        type = "bool-setting",
        name = "enable-assembling-machine",
        setting_type = "startup",
        default_value = true,
        order = "c-00"
    },
    {
        type = "bool-setting",
        name = "enable-furnace",
        setting_type = "startup",
        default_value = true,
        order = "c-01"
    },
    -- Secondary entity types
    {
        type = "bool-setting",
        name = "enable-mining-drill",
        setting_type = "startup",
        default_value = true,
        order = "c-02"
    },
    {
        type = "bool-setting",
        name = "enable-lab",
        setting_type = "startup",
        default_value = true,
        order = "c-03"
    },
    {
        type = "bool-setting",
        name = "enable-inserter",
        setting_type = "startup",
        default_value = true,
        order = "c-04"
    },
    {
        type = "bool-setting",
        name = "enable-pump",
        setting_type = "startup",
        default_value = true,
        order = "c-05"
    },
    {
        type = "bool-setting",
        name = "enable-radar",
        setting_type = "startup",
        default_value = true,
        order = "c-06"
    },
    {
        type = "bool-setting",
        name = "enable-roboport",
        setting_type = "startup",
        default_value = true,
        order = "c-07"
    },
    -- Belt system entities
    {
        type = "bool-setting",
        name = "enable-transport-belt",
        setting_type = "startup",
        default_value = false,
        order = "d-00"
    },
    {
        type = "bool-setting",
        name = "enable-underground-belt",
        setting_type = "startup",
        default_value = false,
        order = "d-01"
    },
    {
        type = "bool-setting",
        name = "enable-splitter",
        setting_type = "startup",
        default_value = false,
        order = "d-02"
    },
    {
        type = "bool-setting",
        name = "enable-loader",
        setting_type = "startup",
        default_value = false,
        order = "d-03"
    },
    -- Power infrastructure
    {
        type = "bool-setting",
        name = "enable-electric-pole",
        setting_type = "startup",
        default_value = true,
        order = "e-00"
    },
    {
        type = "bool-setting",
        name = "enable-solar-panel",
        setting_type = "startup",
        default_value = true,
        order = "e-01"
    },
    {
        type = "bool-setting",
        name = "enable-accumulator",
        setting_type = "startup",
        default_value = true,
        order = "e-02"
    },
    {
        type = "bool-setting",
        name = "enable-generator",
        setting_type = "startup",
        default_value = true,
        order = "e-03"
    },
    {
        type = "bool-setting",
        name = "enable-reactor",
        setting_type = "startup",
        default_value = true,
        order = "e-04"
    },
    {
        type = "bool-setting",
        name = "enable-boiler",
        setting_type = "startup",
        default_value = true,
        order = "e-05"
    },
    {
        type = "bool-setting",
        name = "enable-heat-pipe",
        setting_type = "startup",
        default_value = true,
        order = "e-06"
    },
    -- Storage and logistics
    {
        type = "bool-setting",
        name = "enable-container",
        setting_type = "startup",
        default_value = true,
        order = "f-00"
    },
    {
        type = "bool-setting",
        name = "enable-logistic-container",
        setting_type = "startup",
        default_value = true,
        order = "f-01"
    },
    {
        type = "bool-setting",
        name = "enable-storage-tank",
        setting_type = "startup",
        default_value = true,
        order = "f-02"
    },
    -- Pipes and fluid handling
    {
        type = "bool-setting",
        name = "enable-pipe",
        setting_type = "startup",
        default_value = false,
        order = "g-00"
    },
    {
        type = "bool-setting",
        name = "enable-pipe-to-ground",
        setting_type = "startup",
        default_value = false,
        order = "g-01"
    },
    {
        type = "bool-setting",
        name = "enable-offshore-pump",
        setting_type = "startup",
        default_value = true,
        order = "g-02"
    },
    -- Defense structures
    {
        type = "bool-setting",
        name = "enable-turret",
        setting_type = "startup",
        default_value = true,
        order = "h-00"
    },
    {
        type = "bool-setting",
        name = "enable-artillery-turret",
        setting_type = "startup",
        default_value = true,
        order = "h-01"
    },
    {
        type = "bool-setting",
        name = "enable-wall",
        setting_type = "startup",
        default_value = true,
        order = "h-02"
    },
    {
        type = "bool-setting",
        name = "enable-gate",
        setting_type = "startup",
        default_value = true,
        order = "h-03"
    },
    -- Network and control
    {
        type = "bool-setting",
        name = "enable-beacon",
        setting_type = "startup",
        default_value = true,
        order = "i-00"
    },
    {
        type = "bool-setting",
        name = "enable-arithmetic-combinator",
        setting_type = "startup",
        default_value = true,
        order = "i-01"
    },
    {
        type = "bool-setting",
        name = "enable-decider-combinator",
        setting_type = "startup",
        default_value = true,
        order = "i-02"
    },
    {
        type = "bool-setting",
        name = "enable-constant-combinator",
        setting_type = "startup",
        default_value = true,
        order = "i-03"
    },
    {
        type = "bool-setting",
        name = "enable-power-switch",
        setting_type = "startup",
        default_value = true,
        order = "i-04"
    },
    {
        type = "bool-setting",
        name = "enable-programmable-speaker",
        setting_type = "startup",
        default_value = true,
        order = "i-05"
    },
    -- Other buildable entities
    {
        type = "bool-setting",
        name = "enable-lamp",
        setting_type = "startup",
        default_value = true,
        order = "j-00"
    },
    -- Space Age entities (if DLC present)
    {
        type = "bool-setting",
        name = "enable-lightning-rod",
        setting_type = "startup",
        default_value = true,
        order = "k-00"
    },
    {
        type = "bool-setting",
        name = "enable-asteroid-collector",
        setting_type = "startup",
        default_value = true,
        order = "k-01"
    },
    {
        type = "bool-setting",
        name = "enable-thruster",
        setting_type = "startup",
        default_value = true,
        order = "k-02"
    },
    {
        type = "bool-setting",
        name = "enable-cargo-landing-pad",
        setting_type = "startup",
        default_value = true,
        order = "k-03"
    },
    {
        type = "bool-setting",
        name = "enable-agricultural-tower",
        setting_type = "startup",
        default_value = true,
        order = "k-04"
    },
    {
        type = "bool-setting",
        name = "enable-rocket-silo",
        setting_type = "startup",
        default_value = true,
        order = "k-05"
    }
})