local platform = require("platform")

-- X11 apps under force_zero_scaling: gtk scales by GDK_SCALE; no Xft.dpi, gtk would scale its fonts by it a second
-- time; native wayland apps take the compositor's fractional scale
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
