local platform = require("platform")

-- this is for xwayland exclusively
local xwayland_scale = platform.laptop and "1" or "2"
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", xwayland_scale)
hl.env("GDK_SCALE", xwayland_scale)

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- notebook
hl.monitor({
    output = "eDP-1",
    mode = "1920x1080",
    position = "auto",
    scale = 1,
})

-- desktop
hl.monitor({
    output = "DP-1",
    mode = "3840x2160@144",
    position = "0x0",
    scale = 1.666667,
})

hl.monitor({
    output = "DP-2",
    mode = "3840x2160@144",
    position = "auto",
    scale = 1.666667,
})

-- fallback
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})
