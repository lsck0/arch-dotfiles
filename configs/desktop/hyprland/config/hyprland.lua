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

-- drop-ins: another module's own binds and rules as ~/.config/hypr/dropins/<name>.lua (programming/hermes' system
-- agent), loaded after the rest and before the power-save overrides
local function dropins()
    local ok, pipe = pcall(io.popen, "ls " .. os.getenv("HOME") .. "/.config/hypr/dropins 2>/dev/null")
    if not ok or not pipe then
        return {}
    end
    local names = {}
    for file in pipe:lines() do
        local name = file:match("^([%w_]+)%.lua$")
        if name then
            table.insert(names, "dropins." .. name)
        end
    end
    pipe:close()
    table.sort(names)
    return names
end
for _, name in ipairs(dropins()) do
    table.insert(MODULES, #MODULES, name)
end

local function optional(module)
    local ok, err = pcall(require, module)
    if not ok then
        io.stderr:write("hyprland config: skipping " .. module .. ": " .. tostring(err) .. "\n")
    end
end

-- package.loaded survives a config reload, so drop everything before requiring
for _, module in ipairs({ "platform", "wal_colors", "style" }) do
    package.loaded[module] = nil
end
for _, module in ipairs(MODULES) do
    package.loaded[module] = nil
end
for _, module in ipairs(MODULES) do
    optional(module)
end

hl.config({ ecosystem = { no_update_news = true } })
