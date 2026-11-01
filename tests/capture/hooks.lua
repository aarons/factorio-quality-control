-- Injected only into the disposable Quality Control copy by capture_effects.py.
local notifications = require("scripts.notifications")

remote.add_interface("qc-capture", {
  show = function(player, entity, style, module_name)
    local preferences = settings.get_player_settings(player)
    for _, name in ipairs({"aggregate-alerts", "entity-alerts", "chat", "gps", "floating-text",
      "halo", "rainbow", "badge", "bubbles", "sound"}) do
      preferences["quality-change-" .. name .. "-enabled"] = {value = name == style}
    end
    if module_name then
      notifications.show_module_quality_alert(entity, module_name, entity.quality.name)
    else
      notifications.show_entity_quality_alert(entity, entity.quality.name)
    end
  end,
})
