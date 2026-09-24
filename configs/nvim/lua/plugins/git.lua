return {
    { "tpope/vim-fugitive", cmd = { "G", "Git", "Gdiffsplit", "Gread", "Gwrite", "Gblame", "Gclog" } }, -- git commands in vim

    {
        "sindrets/diffview.nvim", -- git diff / merge / file-history views
        cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
        keys = {
            { "<leader>gd", "<cmd>DiffviewOpen<cr>",         desc = "Diffview open" },
            { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history (current file)" },
        },
    },

    {
        "akinsho/git-conflict.nvim", -- merge conflict resolution
        config = true
    },

    {
        "lewis6991/gitsigns.nvim", -- git status gutter
        event = { "BufReadPre", "BufNewFile" },
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
        "ThePrimeagen/git-worktree.nvim", -- git worktree management (bare nvim/neovide only)
        -- inside tmux/herdr, worktrees are driven by the wtree popup instead.
        cond = function() return not (vim.env.TMUX or vim.env.HERDR_SESSION) end,
        keys = { "<leader>gf", "<leader>gc" },
        dependencies = {
            "nvim-lua/plenary.nvim",         -- Lua utility library
            "nvim-telescope/telescope.nvim", -- fuzzy finder
        },
        config = function()
            require("git-worktree").setup()
            require("telescope").load_extension("git_worktree")

            local tele = require("telescope").extensions.git_worktree
            vim.keymap.set("n", "<leader>gf", tele.git_worktrees, { desc = "Git worktrees (telescope)" })
            vim.keymap.set("n", "<leader>gc", tele.create_git_worktree, { desc = "Create git worktree" })
        end,
    },

    {
        "pwntester/octo.nvim", -- github interactions
        cmd = "Octo",
        opts = {
            picker = "telescope",
            enable_builtin = true,
        },
        keys = {
            {
                "<leader>oi",
                "<CMD>Octo issue list<CR>",
                desc = "List GitHub Issues",
            },
            {
                "<leader>op",
                "<CMD>Octo pr list<CR>",
                desc = "List GitHub PullRequests",
            },
            {
                "<leader>od",
                "<CMD>Octo discussion list<CR>",
                desc = "List GitHub Discussions",
            },
            {
                "<leader>on",
                "<CMD>Octo notification list<CR>",
                desc = "List GitHub Notifications",
            },
            {
                "<leader>os",
                function()
                    require("octo.utils").create_base_search_command { include_current_repo = true }
                end,
                desc = "Search GitHub",
            },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope.nvim",
            "nvim-tree/nvim-web-devicons", -- optional if file_panel.icons is a function
        },
    },
}
