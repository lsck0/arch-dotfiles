return {
    { "tpope/vim-fugitive" },

    {
        "esmuellert/vscode-diff.nvim",
        dependencies = { "MunifTanjim/nui.nvim" },
    },

    {
        "akinsho/git-conflict.nvim",
        config = true
    },

    {
        "lewis6991/gitsigns.nvim",
        lazy = false,
        event = "BufRead",
        config = function()
            require("gitsigns").setup()
        end
    },
}
