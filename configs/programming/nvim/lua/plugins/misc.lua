return {
    {
        "chrisgrieser/nvim-early-retirement",
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end,
    },
    {
        "folke/flash.nvim",
        event = "VeryLazy",
        opts = {},
        keys = {
            {
                "s",
                mode = { "n", "x", "o" },
                function()
                    require("flash").jump()
                end,
                desc = "Flash jump",
            },
            {
                "S",
                mode = { "n", "x", "o" },
                function()
                    require("flash").treesitter()
                end,
                desc = "Flash treesitter",
            },
            {
                "r",
                mode = "o",
                function()
                    require("flash").remote()
                end,
                desc = "Remote flash",
            },
            {
                "R",
                mode = { "o", "x" },
                function()
                    require("flash").treesitter_search()
                end,
                desc = "Treesitter search",
            },
        },
    },
    {
        "hat0uma/csvview.nvim",
        ft = "csv",
        opts = {
            parser = { comments = { "#", "//" } },
        },
    },
    { "jbyuki/venn.nvim", cmd = { "VBox", "VBoxD", "VBoxH", "VBoxO" } },
    {
        "mg979/vim-visual-multi",
        init = function()
            -- M-d, not M-n: herdr binds alt+n to next_agent and would swallow it
            vim.g.VM_maps = {
                ["Find Under"] = "<M-d>",
                ["Find Subword Under"] = "<M-d>",
            }
            vim.g.VM_show_warnings = 0
        end,
    },
    { "smart-splits-nvim/smart-splits.nvim", lazy = true },
    {
        "nacro90/numb.nvim",
        opts = {},
    },
    {
        "nosduco/remote-sshfs.nvim",
        cmd = {
            "RemoteSSHFSConnect",
            "RemoteSSHFSEdit",
            "RemoteSSHFSDisconnect",
            "RemoteSSHFSFindFiles",
            "RemoteSSHFSLiveGrep",
        },
        dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
        opts = {},
    },
    { "sindrets/winshift.nvim", cmd = "WinShift" },
    { "tpope/vim-repeat" },
    { "zeioth/garbage-day.nvim" },
    {
        "ziontee113/icon-picker.nvim",
        cmd = { "IconPickerNormal", "IconPickerInsert", "IconPickerYank" },
        opts = { disable_legacy_commands = true },
    },
    {
        "laytan/cloak.nvim",
        opts = {
            cloak_character = "#",
            patterns = { { file_pattern = { "*.env*" }, cloak_pattern = "=.+" } },
        },
    },
    {
        "trixnz/sops.nvim",
        -- not lazy: its BufReadPost decrypt must be registered before the first sops file opens
        lazy = false,
        opts = { disabled = false },
        keys = {
            { "<leader>ks", "<cmd>SopsToggle<cr>", desc = "Sops: toggle transparent en/decryption" },
        },
    },
    {
        "folke/twilight.nvim",
        cmd = "Twilight",
        opts = {
            treesitter = true,
            expand = {
                "enum_specifier",
                "for_statement",
                "function_definition",
                "if_statement",
                "preproc_function_def",
                "preproc_if",
                "struct_specifier",
                "type_definition",
                "while_statement",
            },
        },
    },
    {
        "folke/zen-mode.nvim",
        cmd = "ZenMode",
        opts = {},
    },

    {
        "dijeferson/gpg.nvim",
        opts = {
            use_armor = true, -- .asc output, pasteable
            allow_clipboard = true,
            show_progress = "toast",
        },
    },
    {
        "icarios-dev/privymd.nvim",
        ft = "markdown",
        opts = {
            auto_decrypt = true,
            auto_encrypt = true,
        },
    },
    {
        "matthandzel/taskwarrior.nvim",
        main = "taskwarrior",
        opts = {
            capture_key = "<leader>Ta",
            open_key = "<leader>Tt",
            filter_key = "<leader>Tf",
            sort_key = "<leader>Ts",
            group_key = "<leader>Tg",
            project_add_key = "<leader>Tpa",
            context_key = "<leader>Tc",
            view_key = "<leader>Tv",
            report_key = "<leader>Tr",
            -- the error hint hardcodes <leader>tF
            feedback = { feedback_key = "<leader>TF", hint_on_error = false },
        },
    },

    {
        "nvzone/showkeys",
        event = "VeryLazy",
        opts = {
            timeout = 1,
            maxkeys = 5,
            position = "top-right",
        },
    },
}
