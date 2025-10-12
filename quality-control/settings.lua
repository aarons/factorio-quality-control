data:extend({
    {
        type = "double-setting",
        name = "manufacturing-hours-for-change",
        setting_type = "startup",
        default_value = 3,
        min_value = 0.001,
        max_value = 1000,
        order = "a-0"
    },
    {
        type = "double-setting",
        name = "percentage-chance-of-change",
        setting_type = "startup",
        default_value = 1,
        min_value = 0.0001,
        max_value = 100,
        order = "a-1"
    },
    {
        type = "double-setting",
        name = "quality-increase-cost",
        setting_type = "startup",
        default_value = 50,
        min_value = 0,
        max_value = 100000,
        order = "a-2"
    },
    {
        type = "string-setting",
        name = "quality-chance-accumulation-rate",
        setting_type = "startup",
        default_value = "low",
        allowed_values = {"none", "low", "medium", "high"},
        order = "a-3"
    },
    {
        type = "string-setting",
        name = "change-modules-with-entity",
        setting_type = "startup",
        default_value = "disabled",
        allowed_values = {"disabled", "enabled", "extra-enabled"},
        order = "a-4"
    },
    {
        type = "int-setting",
        name = "batch-entities-per-tick",
        setting_type = "runtime-global",
        default_value = 10,
        min_value = 1,
        max_value = 1000,
        order = "b-0"
    },
    {
        type = "int-setting",
        name = "batch-ticks-between-processing",
        setting_type = "runtime-global",
        default_value = 1,
        min_value = 1,
        max_value = 6000, -- about 15 minutes
        order = "b-01"
    },
    {
        type = "bool-setting",
        name = "quality-change-aggregate-alerts-enabled",
        setting_type = "runtime-global",
        default_value = false,
        order = "b-02"
    },
    {
        type = "int-setting",
        name = "aggregate-notification-cooldown-minutes",
        setting_type = "runtime-global",
        default_value = 5,
        min_value = 1,
        max_value = 720,
        order = "b-03"
    },
    {
        type = "bool-setting",
        name = "quality-change-entity-alerts-enabled",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "c-01"
    },
    -- Entity types (alphabetized)
    {
        type = "bool-setting",
        name = "enable-accumulators",
        setting_type = "startup",
        default_value = true,
        order = "d-00"
    },
    {
        type = "bool-setting",
        name = "enable-agricultural-towers",
        setting_type = "startup",
        default_value = true,
        order = "d-01"
    },
    {
        type = "bool-setting",
        name = "enable-assembly-machines",
        setting_type = "startup",
        default_value = true,
        order = "d-02"
    },
    {
        type = "bool-setting",
        name = "enable-asteroid-collectors",
        setting_type = "startup",
        default_value = true,
        order = "d-03"
    },
    {
        type = "bool-setting",
        name = "enable-beacons",
        setting_type = "startup",
        default_value = true,
        order = "d-04"
    },
    {
        type = "bool-setting",
        name = "enable-boilers",
        setting_type = "startup",
        default_value = true,
        order = "d-05"
    },
    {
        type = "bool-setting",
        name = "enable-combinators-and-speakers",
        setting_type = "startup",
        default_value = true,
        order = "d-06"
    },
    {
        type = "bool-setting",
        name = "enable-defense-walls-and-gates",
        setting_type = "startup",
        default_value = true,
        order = "d-07"
    },
    {
        type = "bool-setting",
        name = "enable-furnaces",
        setting_type = "startup",
        default_value = true,
        order = "d-08"
    },
    {
        type = "bool-setting",
        name = "enable-generators",
        setting_type = "startup",
        default_value = true,
        order = "d-09"
    },
    {
        type = "bool-setting",
        name = "enable-heat-pipes",
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
    },
    {
        type = "bool-setting",
        name = "enable-labs",
        setting_type = "startup",
        default_value = true,
        order = "d-12"
    },
    {
        type = "bool-setting",
        name = "enable-lamps",
        setting_type = "startup",
        default_value = true,
        order = "d-13"
    },
    {
        type = "bool-setting",
        name = "enable-lightning-rods",
        setting_type = "startup",
        default_value = true,
        order = "d-14"
    },
    {
        type = "bool-setting",
        name = "enable-mining-drills",
        setting_type = "startup",
        default_value = true,
        order = "d-15"
    },
    {
        type = "bool-setting",
        name = "enable-poles",
        setting_type = "startup",
        default_value = true,
        order = "d-16"
    },
    {
        type = "bool-setting",
        name = "enable-power-switches",
        setting_type = "startup",
        default_value = true,
        order = "d-17"
    },
    {
        type = "bool-setting",
        name = "enable-pumps",
        setting_type = "startup",
        default_value = true,
        order = "d-18"
    },
    {
        type = "bool-setting",
        name = "enable-radar",
        setting_type = "startup",
        default_value = true,
        order = "d-19"
    },
    {
        type = "int-setting",
        name = "radar-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        order = "d-19a"
    },
    {
        type = "int-setting",
        name = "lightning-attractor-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        order = "d-14a"
    },
    {
        type = "bool-setting",
        name = "enable-reactors",
        setting_type = "startup",
        default_value = true,
        order = "d-20"
    },
    {
        type = "bool-setting",
        name = "enable-roboports",
        setting_type = "startup",
        default_value = true,
        order = "d-21"
    },
    {
        type = "bool-setting",
        name = "enable-solar-panels",
        setting_type = "startup",
        default_value = true,
        order = "d-22"
    },
    {
        type = "bool-setting",
        name = "enable-thrusters",
        setting_type = "startup",
        default_value = true,
        order = "d-23"
    },
    {
        type = "bool-setting",
        name = "enable-turrets",
        setting_type = "startup",
        default_value = true,
        order = "d-24"
    }
})