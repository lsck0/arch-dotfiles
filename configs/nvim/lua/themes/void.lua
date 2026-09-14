-- void theme (themes/void.json at repo root) has no dedicated nvim
-- colorscheme of its own -- its palette is a tokyonight-night derivative,
-- so reuse that plugin rather than inventing a new one. Matches the
-- lua/themes/<name>.lua dispatch convention: theme.lua does
-- `require("themes." .. name).apply()` keyed off the marker file's name.
return {
    apply = function()
        require("lazy.core.loader").load("tokyonight.nvim", { plugin = "tokyonight.nvim" })
        vim.cmd("colorscheme tokyonight-night")
    end,
}
