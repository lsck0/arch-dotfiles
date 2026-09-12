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

local function optional(module)
    local ok, err = pcall(require, module)
    if not ok then
        io.stderr:write("hyprland config: skipping " .. module .. ": " .. tostring(err) .. "\n")
    end
end

optional("hyprland_autostart")
optional("hyprland_cursor")
optional("hyprland_input")
optional("hyprland_keybindings")
optional("hyprland_layout")
optional("hyprland_misc")
optional("hyprland_monitors")
optional("hyprland_plugins")
optional("hyprland_windowrules")
optional("hyprland_windows")

hl.config({
    ecosystem = {
        no_update_news = true,
    },
})
