return {
    apply = function()
        require("lazy.core.loader").load("catppuccin", { plugin = "catppuccin" })
        vim.cmd("colorscheme catppuccin-macchiato")
    end,
}
