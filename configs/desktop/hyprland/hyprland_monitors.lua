local platform = require("platform")

-- X11 apps under force_zero_scaling: gtk reads GDK_SCALE, qt's xcb and most others Xft.dpi (hyprland_autostart.lua);
-- native wayland apps take the compositor's fractional scale and ignore both
hl.env("GDK_SCALE", platform.xwayland_scale)

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

for _, monitor in ipairs(platform.monitors) do
    hl.monitor(monitor)
end

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto",
})
