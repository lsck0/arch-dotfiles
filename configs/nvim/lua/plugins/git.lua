return {
    { "tpope/vim-fugitive" }, -- git commands in vim

    {
        "esmuellert/vscode-diff.nvim",             -- VS Code-style diff view
        dependencies = { "MunifTanjim/nui.nvim" }, -- UI component library
    },

    {
        "akinsho/git-conflict.nvim", -- merge conflict resolution
        config = true
    },

    {
        "lewis6991/gitsigns.nvim", -- git status gutter
        lazy = false,
        config = function()
            require("gitsigns").setup()
        end
    },

    {
        "nicolasgb/jj.nvim", -- Jujutsu VCS integration
        version = "*",
        config = function()
            require("jj").setup({})
        end,
    },

    {
        "ThePrimeagen/git-worktree.nvim",    -- git worktree management
        dependencies = {
            "nvim-lua/plenary.nvim",         -- Lua utility library
            "nvim-telescope/telescope.nvim", -- fuzzy finder
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
