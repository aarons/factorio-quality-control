-- Only the disposable media-capture copy exposes unfinished effects.
for _, style in ipairs({"halo", "rainbow"}) do
  local setting = data.raw["bool-setting"]["quality-change-" .. style .. "-enabled"]
  setting.hidden = false
  setting.forced_value = nil
end
