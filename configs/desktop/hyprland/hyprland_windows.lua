local wal = require("wal_colors")
local style = require("style")

local wal_gradient = { colors = { wal.color1, wal.color2, wal.color3 }, angle = 45 }

local function with_alpha(c, a)
    return (c:gsub("rgb%((%x+)%)", "rgba(%1" .. a .. ")"))
end

local CURVES = {
    md3_decel = { { 0.05, 0.7 }, { 0.1, 1 } },
    md3_accel = { { 0.3, 0 }, { 0.8, 0.15 } },
    overshot = { { 0.05, 0.9 }, { 0.1, 1.1 } },
    menu_decel = { { 0.1, 1 }, { 0, 1 } },
    menu_accel = { { 0.38, 0.04 }, { 1, 0.07 } },
    softAcDecel = { { 0.26, 0.26 }, { 0.15, 1 } },
}
for name, points in pairs(CURVES) do
    hl.curve(name, { type = "bezier", points = points })
end

local ANIMATIONS = {
    { leaf = "windowsIn", speed = 5, bezier = "overshot", style = "popin 70%" },
    { leaf = "windowsOut", speed = 4, bezier = "md3_accel", style = "popin 70%" },
    { leaf = "windowsMove", speed = 4.5, bezier = "md3_decel" },
    { leaf = "border", speed = 10, bezier = "default" },
    { leaf = "fade", speed = 2.5, bezier = "md3_decel" },
    { leaf = "layers", speed = 2, bezier = "md3_decel", style = "slide" },
    { leaf = "layersIn", speed = 3, bezier = "menu_decel" },
    { leaf = "layersOut", speed = 0.8, bezier = "menu_accel" },
    { leaf = "fadeLayersIn", speed = 2, bezier = "menu_decel" },
    { leaf = "fadeLayersOut", speed = 1.5, bezier = "menu_accel" },
    { leaf = "workspaces", speed = 2.2, bezier = "softAcDecel", style = "slidefade 15%" },
    { leaf = "specialWorkspace", speed = 3, bezier = "md3_decel", style = "slidefadevert 15%" },
}
for _, animation in ipairs(ANIMATIONS) do
    animation.enabled = true
    hl.animation(animation)
end

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = style.border,
        col = {
            active_border = wal_gradient,
            inactive_border = with_alpha(wal.color8, "aa"),
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = style.rounding,
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
            popups = true,
            vibrancy = 0.1796,
            vibrancy_darkness = 1.0,
        },
        shadow = {
            enabled = true,
            range = 12,
            render_power = 3,
            color = with_alpha(wal.color4, "18"),
            color_inactive = "rgba(00000066)",
        },
    },
    group = {
        col = {
            border_active = wal_gradient,
            border_inactive = "rgba(00000000)",
        },
        groupbar = {
            font_family = style.font,
            font_size = style.font_size,
            font_weight_active = "normal",
            font_weight_inactive = "normal",
            height = style.font_size + 8,
            gradients = true,
            rounding = 0,
            gradient_rounding = 0,
            indicator_height = 0,
            gaps_in = 1,
            gaps_out = 0,
            keep_upper_gap = false,
            text_color = style.tab_active_text or wal.color15,
            text_color_inactive = style.bar_text or wal.color15,
            col = {
                active = style.tab_active_bg or wal.color8,
                inactive = style.bar_bg or wal.color0,
            },
        },
    },
})
