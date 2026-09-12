return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-light")
    end,
}
