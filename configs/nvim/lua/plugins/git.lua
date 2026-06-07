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

    {
        "nicolasgb/jj.nvim",
        version = "*",
        config = function()
            require("jj").setup({})
        end,
    },

    {
        "ThePrimeagen/git-worktree.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope.nvim",
        },
        config = function()
            require("git-worktree").setup()
            require("telescope").load_extension("git_worktree")

            local tele = require("telescope").extensions.git_worktree
            vim.keymap.set("n", "<leader>gf", tele.git_worktrees)
            vim.keymap.set("n", "<leader>gc", tele.create_git_worktree)
        end,
    },
}
