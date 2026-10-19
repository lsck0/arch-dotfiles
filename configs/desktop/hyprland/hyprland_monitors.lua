local platform = require("platform")

hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", platform.xwayland_scale)
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
