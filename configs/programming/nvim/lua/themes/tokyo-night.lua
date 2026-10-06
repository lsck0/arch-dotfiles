return {
    apply = function()
        require("lazy.core.loader").load("tokyonight.nvim", { plugin = "tokyonight.nvim" })
        vim.cmd("colorscheme tokyonight-night")
    end,
}
