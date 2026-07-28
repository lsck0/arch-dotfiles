for _, module in ipairs({
    "platform",
    "wal_colors",
    "hyprland_autostart",
    "hyprland_cursor",
    "hyprland_input",
    "hyprland_keybindings",
    "hyprland_layout",
    "hyprland_misc",
    "hyprland_monitors",
    "hyprland_plugins",
    "hyprland_windowrules",
    "hyprland_windows",
}) do
    package.loaded[module] = nil
end

require("hyprland_autostart")
require("hyprland_cursor")
require("hyprland_input")
require("hyprland_keybindings")
require("hyprland_layout")
require("hyprland_misc")
require("hyprland_monitors")
require("hyprland_plugins")
require("hyprland_windowrules")
require("hyprland_windows")

hl.config({
    ecosystem = {
        no_update_news = true,
    },
})
