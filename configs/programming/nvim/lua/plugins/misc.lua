return {
    {
        "chrisgrieser/nvim-early-retirement", -- auto-close idle buffers
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end,
    },
    {
        "folke/flash.nvim", -- jump/select via labels, treesitter, search
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
        "hat0uma/csvview.nvim", -- CSV column alignment
        ft = "csv",
        opts = {
            parser = { comments = { "#", "//" } },
        },
    },
    { "jbyuki/venn.nvim", cmd = { "VBox", "VBoxD", "VBoxH", "VBoxO" } }, -- ASCII diagram drawing
    {
        "mg979/vim-visual-multi", -- multiple cursors
        init = function()
            -- M-d, not M-n: herdr binds alt+n to next_agent and would swallow it
            vim.g.VM_maps = {
                ["Find Under"] = "<M-d>",
                ["Find Subword Under"] = "<M-d>",
            }
            -- it borrows autopairs' buffer <BS> map for the session and warns about it every start
            vim.g.VM_show_warnings = 0
        end,
    },
    { "mrjones2014/smart-splits.nvim", lazy = true }, -- resize/navigate splits
    {
        "nacro90/numb.nvim", -- peek line on jump
        opts = {},
    },
    {
        "nosduco/remote-sshfs.nvim", -- browse remote files via SSH
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
    { "sindrets/winshift.nvim", cmd = "WinShift" }, -- move/swap windows
    { "tpope/vim-repeat" }, -- repeat plugin actions
    { "zeioth/garbage-day.nvim" }, -- restart idle LSP clients
    {
        "ziontee113/icon-picker.nvim", -- emoji/icon picker
        cmd = { "IconPickerNormal", "IconPickerInsert", "IconPickerYank" },
        opts = { disable_legacy_commands = true },
    },
    {
        "laytan/cloak.nvim", -- mask sensitive .env values
        opts = {
            cloak_character = "#", -- default is "*"
            patterns = { { file_pattern = { "*.env*" }, cloak_pattern = "=.+" } },
        },
    },
    {
        "trixnz/sops.nvim", -- edit sops-encrypted yaml/json/toml/env in the clear
        -- not lazy: its BufReadPost decrypt must be registered before the first sops file opens
        lazy = false,
        opts = { disabled = false },
        keys = {
            { "<leader>ks", "<cmd>SopsToggle<cr>", desc = "Sops: toggle transparent en/decryption" },
        },
    },
    {
        "folke/twilight.nvim", -- dim inactive code
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
        "folke/zen-mode.nvim", -- distraction-free writing
        cmd = "ZenMode",
        opts = {},
    },

    {
        "dijeferson/gpg.nvim", -- transparent gpg for *.gpg/*.asc
        opts = {
            use_armor = true, -- .asc output, pasteable
            allow_clipboard = true,
            show_progress = "toast",
        },
    },
    {
        "icarios-dev/privymd.nvim", -- GPG-encrypted fenced blocks inside Markdown
        ft = "markdown",
        opts = {
            auto_decrypt = true,
            auto_encrypt = true,
        },
    },
    {
        "matthandzel/taskwarrior.nvim", -- edit the task db as a buffer
        main = "taskwarrior",
        -- <leader>T: its default <leader>t* collides with trouble
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
        "nvzone/showkeys", -- on-screen keypress display
        event = "VeryLazy",
        opts = {
            timeout = 1,
            maxkeys = 5,
            position = "top-right",
        },
    },
}
