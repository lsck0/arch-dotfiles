local wal = require("wal_colors")

local walGradient = { colors = { wal.color1, wal.color2, wal.color3 }, angle = 45 }

hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("md3_standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.curve("md3_decel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("md3_accel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })
hl.curve("crazyshot", { type = "bezier", points = { { 0.1, 1.5 }, { 0.76, 0.92 } } })
hl.curve("hyprnostretch", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("menu_decel", { type = "bezier", points = { { 0.1, 1 }, { 0, 1 } } })
hl.curve("menu_accel", { type = "bezier", points = { { 0.38, 0.04 }, { 1, 0.07 } } })
hl.curve("easeInOutCirc", { type = "bezier", points = { { 0.85, 0 }, { 0.15, 1 } } })
hl.curve("easeOutCirc", { type = "bezier", points = { { 0, 0.55 }, { 0.45, 1 } } })
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("softAcDecel", { type = "bezier", points = { { 0.26, 0.26 }, { 0.15, 1 } } })
hl.curve("md2", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3.5,
    bezier = "overshot",
    style = "popin 70%",
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2.5,
    bezier = "md3_accel",
    style = "popin 70%",
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "md3_decel",
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 8,
    bezier = "default",
})
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 2.5,
    bezier = "md3_decel",
})
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 2,
    bezier = "md3_decel",
    style = "slide",
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 3,
    bezier = "menu_decel",
    style = "slide",
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 0.8,
    bezier = "menu_accel",
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 2,
    bezier = "menu_decel",
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 1.5,
    bezier = "menu_accel",
})
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 1.6,
    bezier = "softAcDecel",
    style = "slidefade 15%",
})
hl.animation({
    leaf = "specialWorkspace",
    enabled = true,
    speed = 3,
    bezier = "md3_decel",
    style = "slidefadevert 15%",
})

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border = walGradient,
            inactive_border = "rgba(2a2a2aaa)",
        },
        layout = "dwindle",
    },
    decoration = {
        screen_shader = os.getenv("HOME") .. "/.config/hypr/shaders/color-correction.frag",
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,
        rounding = 6,
        dim_inactive = false,
        dim_strength = 0.0,
        blur = {
            enabled = true,
            xray = false,
            size = 3,
            passes = 1,
            -- true flickers parts of windows against damage_tracking 2 on
            -- 0.56.1; bisected with `hyprctl eval`, damage tracking itself is
            -- fine once this is off
            new_optimizations = false,
            popups = true,
            vibrancy = 0.1796,
            vibrancy_darkness = 3.0,
        },
        shadow = {
            enabled = true,
            range = 20,
            render_power = 3,
            color = "rgba(00000055)",
        },
    },
    group = {
        col = {
            border_active = walGradient,
            border_inactive = "rgba(00000000)",
        },
        groupbar = {
            enabled = true,
            height = 3,
            render_titles = false,
            col = {
                active = wal.color2,
                inactive = "rgba(000000cc)",
            },
        },
    },
    animations = {
        enabled = true,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})
