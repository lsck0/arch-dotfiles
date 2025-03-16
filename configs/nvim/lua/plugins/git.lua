return {
    { "sindrets/diffview.nvim" },
    {
        "akinsho/git-conflict.nvim",
        config = true
    },
    {
        "lewis6991/gitsigns.nvim",
        lazy = true,
        event = "BufRead",
        config = function()
            require("gitsigns").setup()
        end
    },
    { "tpope/vim-fugitive" },
}
