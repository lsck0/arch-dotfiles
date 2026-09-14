return {
    apply = function()
        require("lazy.core.loader").load("neovim-ayu", { plugin = "neovim-ayu" })
        vim.cmd("colorscheme ayu-dark")
        -- neovim-ayu's LineNr uses colors.guide_normal (#1E222A), meant for
        -- indent guides, against bg #0B0E14 -- contrast ratio ~1.2:1, far
        -- below WCAG's 3:1 floor for UI text, so line numbers were nearly
        -- invisible. colors.comment (#636A72, ~3.6:1) is the plugin's own
        -- "muted but legible" tone; reuse it here instead of patching the
        -- plugin's checkout, which lazy.nvim would just overwrite on update.
        vim.api.nvim_set_hl(0, "LineNr", { fg = "#636A72" })
    end,
}
