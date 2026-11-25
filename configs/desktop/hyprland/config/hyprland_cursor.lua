local platform = require("platform")

hl.env("HYPRCURSOR_SIZE", tostring(platform.cursor.size))
hl.env("HYPRCURSOR_THEME", "rose-pine-hyprcursor")
hl.env("XCURSOR_SIZE", tostring(platform.cursor.size))
hl.env("XCURSOR_THEME", "BreezeX-RosePine-Linux")

-- hyprland 0.56.2 asserted in CHyprOpenGLImpl::beginSimple on hardware cursors when a client churns cursor shapes.
-- RETEST(hyprland 0.57.2): not tried since the upgrade; software cursors block direct scanout (hyprland_misc.lua), so
-- run the churn with 2 (auto) and dynamic-cursors loaded, then drop this line or move the tag to the tested version
hl.config({ cursor = { no_hardware_cursors = 1, inactive_timeout = platform.input.cursor_hide_s } })
