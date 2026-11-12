local function plugin_config(name, opts)
    if hl.plugin[name] ~= nil then
        hl.config({ plugin = { [name] = opts } })
    end
end

plugin_config("dynamic_cursors", {
    enabled = true,
    mode = "none",

    shake = {
        enabled = true,
        threshold = 4,
        base = 4.0,
        speed = 4.0,
        limit = 0.0, -- no ceiling
        timeout = 500,
        -- no-op while mode is "none", explicit for a later mode switch
        effects = true,
    },
    hyprcursor = {
        enabled = true,
        nearest = true,
        resolution = -1,
        fallback = "clientside",
    },
})

local wal = require("wal_colors")
local style = require("style")

local MAXIMIZE = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']]

-- flat title bars in the tab strip's look
plugin_config("hyprbars", {
    -- off for now; the styling below stays for when it comes back
    enabled = false,
    bar_height = style.font_size + 8,
    bar_color = style.bar_bg or wal.color0,
    ["col.text"] = style.bar_text or wal.color15,
    bar_text_font = style.font,
    bar_text_size = style.font_size,
    bar_text_align = "left",
    bar_padding = 10,
    bar_button_padding = 6,
    bar_part_of_window = true,
    bar_precedence_over_border = true,
    buttons_on_hover = true,
    on_double_click = MAXIMIZE,
})

if hl.plugin.hyprbars ~= nil then
    -- a tabbed window has its title in the tab strip
    hl.window_rule({ match = { group = true }, ["hyprbars:no_bar"] = true })
    local function button(color, action)
        hl.plugin.hyprbars.add_button({ bg_color = color, fg_color = wal.color0, size = 11, icon = "", action = action })
    end
    -- rightmost first
    button(wal.color1, "$DOTFILES/configs/desktop/hyprland/window-close.nu")
    button(wal.color3, MAXIMIZE)
    button(wal.color2, [[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']])
end
