return {
    {
        "stevearc/aerial.nvim", -- symbol outline / structure panel
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        keys = {
            { "<leader>lc", "<cmd>AerialToggle<cr>", desc = "Code outline (aerial)" },
        },
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons",
        },
        opts = {
            backends = { "lsp", "treesitter", "markdown", "man" },
            layout = { default_direction = "right", min_width = 30 },
            show_guides = true,
            -- show every symbol kind, not just the default function/class subset
            -- (a file of #defines/globals/fields otherwise reports "No symbols")
            filter_kind = false,
        },
    },

    {
        "Bekaboo/dropbar.nvim", -- breadcrumbs (path + LSP/treesitter symbols)
        event = "VeryLazy",
        dependencies = { "nvim-telescope/telescope-fzf-native.nvim" },
        config = function()
            -- bar.enable=false: don't attach the top winbar.
            require("dropbar").setup({ bar = { enable = false } })
        end,
    },

    {
        "kevinhwang91/nvim-ufo",                     -- modern LSP/treesitter folding
        dependencies = { "kevinhwang91/promise-async" },
        event = { "BufReadPost", "BufNewFile" },
        keys = {
            { "zR", function() require("ufo").openAllFolds() end,  desc = "Open all folds" },
            { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
            { "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open folds except kinds" },
        },
        init = function()
            -- start unfolded; ufo drives folding from here
            vim.o.foldcolumn = "0"
            vim.o.foldlevel = 99
            vim.o.foldlevelstart = 99
            vim.o.foldenable = true
        end,
        config = function()
            require("ufo").setup({
                provider_selector = function() return { "treesitter", "indent" } end,
            })
        end,
    },

    {
        "folke/persistence.nvim", -- per-directory session save/restore
        event = "BufReadPre",
        opts = {},
        keys = {
            { "<leader>qs", function() require("persistence").load() end,             desc = "Restore session (cwd)" },
            { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
            { "<leader>qd", function() require("persistence").stop() end,             desc = "Stop saving session" },
        },
    },

    {
        "ahmedkhalf/project.nvim", -- project root detection + switcher
        event = "VeryLazy",
        config = function()
            require("project_nvim").setup({
                -- pattern-only: the "lsp" method calls the deprecated
                detection_methods = { "pattern" },
                patterns = { ".git", "Cargo.toml", "package.json", "flake.nix", "pyproject.toml", "Makefile" },
            })
        end,
        keys = {
            {
                "<leader>fp",
                function()
                    require("telescope").load_extension("projects")
                    vim.cmd("Telescope projects")
                end,
                desc = "Projects",
            },
        },
    },

    {
        "j-hui/fidget.nvim", -- LSP progress spinner
        event = "LspAttach",
        opts = {},
    },
}
