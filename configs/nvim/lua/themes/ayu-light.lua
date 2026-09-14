return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-light")
        -- Same low-contrast LineNr fix as ayu-dark.lua. Light's own `comment`
        -- tone (#ABADB1) is still under WCAG's 3:1 floor against this bg, so
        -- use `ui` (#8A9199, ~3:1) instead -- the closest of the plugin's
        -- own tones that actually clears it.
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#8A9199" })
    end,
}
