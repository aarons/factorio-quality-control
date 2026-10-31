local upgrade_sounds = require("scripts.upgrade_sounds")

-- Reuse the vanilla speaker samples as private notification sounds.
data:extend(upgrade_sounds.prototypes)

-- Custom input for quality control entity inspection
data:extend({
  {
    type = "custom-input",
    name = "quality-control-inspect-entity",
    key_sequence = "CONTROL + SHIFT + Q",
    consuming = "none"
  }
})
