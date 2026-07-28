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
        type = "bool-setting",
        name = "accumulate-at-max-quality",
        setting_type = "startup",
        default_value = true,
        order = "a-3a"
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
        order = "b-1"
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
    -- Hidden quality handling (for mods like Quality++ Shiny)
    {
        type = "bool-setting",
        name = "quality_control_skip_hidden_qualities",
        setting_type = "startup",
        default_value = false,
        order = "c-10"
    },
    {
        type = "bool-setting",
        name = "quality_control_hidden_qualities_sticky",
        setting_type = "startup",
        default_value = true,
        order = "c-11"
    },
    -- Custom max levels referenced by the "custom a/b/c" quality level cap values below
    {
        type = "int-setting",
        name = "custom-max-level-a",
        setting_type = "runtime-global",
        default_value = 10,
        min_value = 1,
        max_value = 255,
        order = "cz-0"
    },
    {
        type = "int-setting",
        name = "custom-max-level-b",
        setting_type = "runtime-global",
        default_value = 10,
        min_value = 1,
        max_value = 255,
        order = "cz-1"
    },
    {
        type = "int-setting",
        name = "custom-max-level-c",
        setting_type = "runtime-global",
        default_value = 10,
        min_value = 1,
        max_value = 255,
        order = "cz-2"
    }
})

-- Quality level caps (runtime-global so they can be tuned mid-game).
-- Each cap is a dropdown of quality tier names; control.lua maps the chosen
-- value to a numeric quality level. "disabled" turns off upgrades for that
-- entity type, "unlimited" applies no cap, and the "custom a/b/c" values use
-- the Custom Max Level A/B/C settings above.
local quality_cap_dropdown_values = {
    "disabled", "uncommon", "rare", "epic", "legendary", "unlimited",
    "custom-a", "custom-b", "custom-c"
}

-- Entity types (alphabetized)
local quality_cap_settings = {
    {name = "quality-level-cap-accumulators", default = "unlimited", order = "d-00"},
    {name = "quality-level-cap-agricultural-towers", default = "unlimited", order = "d-01"},
    {name = "quality-level-cap-assembly-machines", default = "unlimited", order = "d-02"},
    {name = "quality-level-cap-asteroid-collectors", default = "legendary", order = "d-03"},
    {name = "quality-level-cap-beacons", default = "unlimited", order = "d-04"},
    {name = "quality-level-cap-boilers", default = "unlimited", order = "d-05"},
    {name = "quality-level-cap-combinators-and-speakers", default = "disabled", order = "d-06"},
    {name = "quality-level-cap-defense-walls-and-gates", default = "unlimited", order = "d-07"},
    {name = "quality-level-cap-furnaces", default = "unlimited", order = "d-08"},
    {name = "quality-level-cap-generators", default = "unlimited", order = "d-09"},
    {name = "quality-level-cap-heat-pipes", default = "disabled", order = "d-10"},
    {name = "quality-level-cap-inserters", default = "unlimited", order = "d-11"},
    {name = "quality-level-cap-labs", default = "unlimited", order = "d-12"},
    {name = "quality-level-cap-lamps", default = "disabled", order = "d-13"},
    {name = "quality-level-cap-lightning-rods", default = "legendary", order = "d-14"},
    {name = "quality-level-cap-mining-drills", default = "unlimited", order = "d-15"},
    {name = "quality-level-cap-poles", default = "disabled", order = "d-16"},
    {name = "quality-level-cap-power-switches", default = "disabled", order = "d-17"},
    {name = "quality-level-cap-pumps", default = "unlimited", order = "d-18"},
    {name = "quality-level-cap-radar", default = "legendary", order = "d-19"},
    {name = "quality-level-cap-reactors", default = "unlimited", order = "d-20"},
    {name = "quality-level-cap-rocket-silos", default = "unlimited", order = "d-20a"},
    {name = "quality-level-cap-roboports", default = "unlimited", order = "d-21"},
    {name = "quality-level-cap-solar-panels", default = "unlimited", order = "d-22"},
    {name = "quality-level-cap-thrusters", default = "legendary", order = "d-23"},
    {name = "quality-level-cap-turrets", default = "unlimited", order = "d-24"}
}

for _, cap in ipairs(quality_cap_settings) do
    data:extend({
        {
            type = "string-setting",
            name = cap.name,
            setting_type = "runtime-global",
            default_value = cap.default,
            allowed_values = quality_cap_dropdown_values,
            order = cap.order
        }
    })
end

data:extend({

    -- Deprecated startup settings (hidden; kept for one release so existing saves can be migrated)
    {
        type = "bool-setting",
        name = "enable-accumulators",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-00"
    },
    {
        type = "bool-setting",
        name = "enable-agricultural-towers",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-01"
    },
    {
        type = "bool-setting",
        name = "enable-assembly-machines",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-02"
    },
    {
        type = "bool-setting",
        name = "enable-asteroid-collectors",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-03"
    },
    {
        type = "int-setting",
        name = "asteroid-collector-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        hidden = true,
        order = "d-03"
    },
    {
        type = "bool-setting",
        name = "enable-beacons",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-04"
    },
    {
        type = "bool-setting",
        name = "enable-boilers",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-05"
    },
    {
        type = "bool-setting",
        name = "enable-combinators-and-speakers",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-06"
    },
    {
        type = "bool-setting",
        name = "enable-defense-walls-and-gates",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-07"
    },
    {
        type = "bool-setting",
        name = "enable-furnaces",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-08"
    },
    {
        type = "bool-setting",
        name = "enable-generators",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-09"
    },
    {
        type = "bool-setting",
        name = "enable-heat-pipes",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-10"
    },
    {
        type = "bool-setting",
        name = "enable-inserters",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-11"
    },
    {
        type = "bool-setting",
        name = "enable-labs",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-12"
    },
    {
        type = "bool-setting",
        name = "enable-lamps",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-13"
    },
    {
        type = "bool-setting",
        name = "enable-lightning-rods",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-14"
    },
    {
        type = "int-setting",
        name = "lightning-attractor-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        hidden = true,
        order = "d-14"
    },
    {
        type = "bool-setting",
        name = "enable-mining-drills",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-15"
    },
    {
        type = "bool-setting",
        name = "enable-poles",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-16"
    },
    {
        type = "bool-setting",
        name = "enable-power-switches",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-17"
    },
    {
        type = "bool-setting",
        name = "enable-pumps",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-18"
    },
    {
        type = "bool-setting",
        name = "enable-radar",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-19"
    },
    {
        type = "int-setting",
        name = "radar-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        hidden = true,
        order = "d-19"
    },
    {
        type = "bool-setting",
        name = "enable-reactors",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-20"
    },
    {
        type = "bool-setting",
        name = "enable-rocket-silos",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-20a"
    },
    {
        type = "bool-setting",
        name = "enable-roboports",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-21"
    },
    {
        type = "bool-setting",
        name = "enable-solar-panels",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-22"
    },
    {
        type = "bool-setting",
        name = "enable-thrusters",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-23"
    },
    {
        type = "int-setting",
        name = "thruster-growth-level-limit",
        setting_type = "startup",
        default_value = 5,
        min_value = 1,
        max_value = 255,
        hidden = true,
        order = "d-23"
    },
    {
        type = "bool-setting",
        name = "enable-turrets",
        setting_type = "startup",
        default_value = false,
        hidden = true,
        order = "d-24"
    },
    {
        type = "double-setting",
        name = "turret-damage-per-manufacturing-hour",
        setting_type = "startup",
        default_value = 36000,
        min_value = 1,
        max_value = 10000000,
        order = "d-24a"
    }
})
