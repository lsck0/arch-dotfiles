return {
    {
        "tpope/vim-fugitive",
        -- every command it defines, so none is missing until another one loaded it
        cmd = {
            "G",
            "Git",
            "GBrowse",
            "Gcd",
            "Glcd",
            "Gclog",
            "Gllog",
            "GcLog",
            "GlLog",
            "Ggrep",
            "Glgrep",
            "Gedit",
            "Ge",
            "Gsplit",
            "Gvsplit",
            "Gtabedit",
            "Gpedit",
            "Gdrop",
            "Gdiffsplit",
            "Gvdiffsplit",
            "Ghdiffsplit",
            "Gread",
            "Gr",
            "Gwrite",
            "Gw",
            "Gwq",
            "GMove",
            "GRename",
            "GDelete",
            "GRemove",
            "GUnlink",
        },
    },

    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
        keys = {
            { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview open" },
            { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history (current file)" },
        },
    },

    {
        "akinsho/git-conflict.nvim",
        config = true,
    },

    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {},
    },

    {
        "nicolasgb/jj.nvim",
        version = "*",
        opts = {},
    },

    {
        "pwntester/octo.nvim",
        cmd = "Octo",
        opts = {
            picker = "telescope",
            enable_builtin = true,
            default_to_projects_v2 = true,
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
                    require("octo.utils").create_base_search_command({ include_current_repo = true })
                end,
                desc = "Search GitHub",
            },
            -- org via the private per-repo identity, never hardcoded
            {
                "<leader>oR",
                function()
                    require("config.octo").org_cmd("Octo repo list %s")
                end,
                desc = "List org repos",
            },
            {
                "<leader>oI",
                function()
                    require("config.octo").org_search("is:issue is:open sort:updated-desc")
                end,
                desc = "List org issues",
            },
            {
                "<leader>oP",
                function()
                    require("config.octo").org_search("is:pr is:open sort:updated-desc")
                end,
                desc = "List org PRs",
            },
            {
                "<leader>oO",
                function()
                    require("config.octo").org_search("")
                end,
                desc = "Search org repos",
            },
            {
                "<leader>oc",
                "<CMD>Octo card set<CR>",
                desc = "Set project card (kanban)",
            },
            {
                "<leader>oC",
                "<CMD>Octo card remove<CR>",
                desc = "Remove project card",
            },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope.nvim",
            "nvim-tree/nvim-web-devicons",
        },
    },
}
