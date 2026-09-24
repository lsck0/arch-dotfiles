-- Lean theorem prover.
return {
    {
        "Julian/lean.nvim",
        ft = "lean",
        dependencies = {
            { "neovim/nvim-lspconfig" },
            { "nvim-lua/plenary.nvim" },
        },
        init = function()
            vim.g.lean_config = { mappings = true }
        end,
    },
}
