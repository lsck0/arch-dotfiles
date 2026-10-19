-- lualine's auto theme with only the mode section filled, so the terminal shows through the rest
local theme = require("lualine.utils.loader").load_theme("auto")
for _, mode in pairs(theme) do
    local accent = mode.a and mode.a.bg
    for _, section in ipairs({ "b", "c" }) do
        if mode[section] then
            mode[section].bg = nil
        end
    end
    mode.z = { fg = accent, gui = "bold" }
end
return theme
