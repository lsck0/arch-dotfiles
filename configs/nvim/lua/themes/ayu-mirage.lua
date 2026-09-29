return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-mirage")
        -- same LineNr contrast fix as ayu-dark
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#6C7A8B" })
    end,
}
