return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-mirage")
        -- Same low-contrast LineNr fix as ayu-dark.lua (guide_normal ~1.3:1
        -- against bg) -- reuse the plugin's own comment tone instead.
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#6C7A8B" })
    end,
}
