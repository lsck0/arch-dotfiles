local platform = require("platform")

-- no Xft.dpi: gtk under GDK_SCALE would scale its fonts twice
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
