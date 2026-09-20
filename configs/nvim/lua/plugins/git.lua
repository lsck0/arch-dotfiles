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
