return {
    apply = function()
        require("lazy.core.loader").load("nord.nvim", { plugin = "nord.nvim" })
        vim.cmd("colorscheme nord")
    end,
}
