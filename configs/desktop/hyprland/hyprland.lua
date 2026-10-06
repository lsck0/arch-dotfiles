local MODULES = {
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
    -- last, overrides the rest
    "hyprland_powersave",
}

local function optional(module)
    local ok, err = pcall(require, module)
    if not ok then
        io.stderr:write("hyprland config: skipping " .. module .. ": " .. tostring(err) .. "\n")
    end
end

-- package.loaded survives a config reload, so drop everything before requiring
package.loaded["platform"] = nil
package.loaded["wal_colors"] = nil
for _, module in ipairs(MODULES) do
    package.loaded[module] = nil
end
for _, module in ipairs(MODULES) do
    optional(module)
end

hl.config({
    ecosystem = {
        no_update_news = true,
    },
})
