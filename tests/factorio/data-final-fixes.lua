-- Eliminate quality skips without replacing the production selector or RNG.
for _, quality in pairs(data.raw.quality) do quality.chain_probability = 0 end

local function machine(name, slots)
  local entity = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-3"])
  entity.name = name
  entity.minable = {mining_time = 0.1, result = name}
  entity.next_upgrade = nil
  entity.energy_source = {type = "void"}
  entity.crafting_speed = 7.2
  entity.module_slots = slots
  entity.quality_affects_module_slots = false
  entity.crafting_categories = {"qc-test"}
  local item = table.deepcopy(data.raw.item["assembling-machine-3"])
  item.name = name
  item.place_result = name
  data:extend{entity, item}
  return entity
end

data:extend{
  {type = "recipe-category", name = "qc-test"},
  {type = "recipe", name = "qc-test-work", categories = {"qc-test"}, enabled = true,
    energy_required = 3.6, ingredients = {},
    results = {{type = "item", name = "iron-plate", amount = 1}}}
}
machine("qc-test-producer", 0)
local resizing = machine("qc-test-resizing", 2)
resizing.quality_affects_module_slots = true
resizing.module_slots_quality_bonus = {normal = 2, uncommon = 0, rare = 2, epic = 2, legendary = 2}
