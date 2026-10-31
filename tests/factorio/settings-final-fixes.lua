local function default(kind, name, value)
  data.raw[kind .. "-setting"][name].default_value = value
end

default("string", "change-modules-with-entity", "independent")
default("double", "manufacturing-hours-for-change", 0.001)
default("double", "percentage-chance-of-change", 1)
default("double", "quality-increase-cost", 0)
default("string", "quality-chance-accumulation-rate", "high")
default("string", "upgrade-limit-assembly-machines", "rare")
default("string", "upgrade-limit-beacons", "uncommon")
default("int", "batch-entities-per-tick", 1000)
default("int", "batch-ticks-between-processing", 1)
