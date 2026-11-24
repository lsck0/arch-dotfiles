local platform = require("platform")
local wal = require("wal_colors")
local style = require("style")

local wal_gradient = { colors = { wal.color1, wal.color2, wal.color3 }, angle = 45 }

local function with_alpha(c, a)
    return (c:gsub("rgb%((%x+)%)", "rgba(%1" .. a .. ")"))
end

-- the shell's motion (configs/desktop/quickshell/config/Commons/Style.qml, motion): enter curve for every enter and move, exit
-- curve for every exit; speeds are deciseconds, fast 90 = 0.9, base 160 = 1.6, exit 120 = 1.2, slow 240 = 2.4. Windows
-- travel farther than a panel and take slow. Shell layers animate themselves (no_anim in hyprland_windowrules.lua)
hl.curve("enter", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("exit", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })

local ANIMATIONS = {
    { leaf = "global", speed = 2.4, bezier = "enter" },
    { leaf = "windowsIn", speed = 2.4, bezier = "enter", style = "popin 90%" },
    { leaf = "windowsOut", speed = 1.2, bezier = "exit", style = "popin 95%" },
    { leaf = "windowsMove", speed = 2.4, bezier = "enter" },
    { leaf = "border", speed = 0.9, bezier = "enter" },
    { leaf = "fade", speed = 1.6, bezier = "enter" },
    { leaf = "fadeOut", speed = 1.2, bezier = "exit" },
    { leaf = "fadeLayersOut", speed = 1.2, bezier = "exit" },
    { leaf = "fadePopupsOut", speed = 1.2, bezier = "exit" },
    { leaf = "layers", speed = 1.6, bezier = "enter", style = "fade" },
    { leaf = "layersOut", speed = 1.2, bezier = "exit" },
    { leaf = "workspaces", speed = 2.4, bezier = "enter", style = "slidefade 15%" },
    { leaf = "specialWorkspace", speed = 2.4, bezier = "enter", style = "slidefadevert 15%" },
    { leaf = "zoomFactor", speed = 1.6, bezier = "enter" },
}
for _, animation in ipairs(ANIMATIONS) do
    animation.enabled = true
    hl.animation(animation)
end

hl.config({ animations = { enabled = platform.look.animations } })

hl.config({
    general = {
        gaps_in = platform.look.gaps_in,
        gaps_out = platform.look.gaps_out,
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
            enabled = platform.look.blur,
            size = 6,
            passes = 3,
            popups = true,
            contrast = 1.0,
            brightness = style.blur_brightness or 1.0,
            noise = 0.02,
            vibrancy = 0.3,
            vibrancy_darkness = 1.0,
        },
        shadow = {
            enabled = platform.look.shadows,
            range = 14,
            render_power = 3,
            color = "rgba(00000077)",
            color_inactive = "rgba(00000030)",
        },
    },
    group = {
        col = {
            border_active = wal_gradient,
            border_inactive = with_alpha(wal.color8, "aa"),
            border_locked_active = wal_gradient,
            border_locked_inactive = with_alpha(wal.color8, "aa"),
        },
        groupbar = {
            font_family = style.font,
            font_size = style.font_size,
            font_weight_active = "normal",
            font_weight_inactive = "normal",
            height = style.font_size + 8,
            gradients = true,
            rounding = style.rounding,
            gradient_rounding = style.rounding,
            indicator_height = 0,
            gaps_in = 1,
            gaps_out = 0,
            keep_upper_gap = false,
            text_color = style.tab_active_text or wal.color15,
            text_color_inactive = style.bar_text or wal.color15,
            col = {
                active = style.tab_active_bg or wal.color8,
                inactive = style.bar_bg or wal.color0,
                locked_active = style.tab_active_bg or wal.color8,
                locked_inactive = style.bar_bg or wal.color0,
            },
        },
    },
})
