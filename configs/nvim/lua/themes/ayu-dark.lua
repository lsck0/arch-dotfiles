return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-dark")
        -- upstream LineNr is ~1.2:1 against bg, nearly invisible
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#636A72" })
    end,
}
