return {
    {
        "chrisgrieser/nvim-early-retirement", -- auto-close idle buffers
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end
    },
    {
        "folke/flash.nvim", -- jump/select via labels, treesitter, search
        event = "VeryLazy",
        opts = {},
        keys = {
            { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end,             desc = "Flash jump" },
            { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end,       desc = "Flash treesitter" },
            { "r", mode = "o",               function() require("flash").remote() end,           desc = "Remote flash" },
            { "R", mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter search" },
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
                ["Find Under"]         = "<M-d>",
                ["Find Subword Under"] = "<M-d>",
            }
        end
    },
    { "mrjones2014/smart-splits.nvim", lazy = true }, -- resize/navigate splits
    {
        "nacro90/numb.nvim",             -- peek line on jump
        config = function() require("numb").setup() end
    },
    {
        "nosduco/remote-sshfs.nvim", -- browse remote files via SSH
        cmd = { "RemoteSSHFSConnect", "RemoteSSHFSEdit", "RemoteSSHFSDisconnect", "RemoteSSHFSFindFiles", "RemoteSSHFSLiveGrep" },
        dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
        config = function()
            require("remote-sshfs").setup()
        end
    },
    { "sindrets/winshift.nvim", cmd = "WinShift" },      -- move/swap windows
    { "tpope/vim-repeat" },            -- repeat plugin actions
    { "zeioth/garbage-day.nvim" },     -- restart idle LSP clients
    {
        "ziontee113/icon-picker.nvim", -- emoji/icon picker
        cmd = { "IconPickerNormal", "IconPickerInsert", "IconPickerYank" },
        config = function() require("icon-picker").setup({ disable_legacy_commands = true }) end
    },
    {
        "laytan/cloak.nvim", -- mask sensitive .env values
        config = function()
            require("cloak").setup({
                enabled = true,
                cloak_character = "#",
                highlight_group = "Comment",
                patterns = { { file_pattern = { "*.env*" }, cloak_pattern = "=.+" }, },
            })
        end
    },
    {
        "trixnz/sops.nvim", -- edit sops-encrypted yaml/json/toml/env in the clear
        -- Not lazy: the plugin has to own BufReadCmd/BufWriteCmd before a file is opened, otherwise the first sops file of a session shows ciphertext.
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
        }
    },
    {
        "folke/zen-mode.nvim", -- distraction-free writing
        cmd = "ZenMode",
        opts = {},
    },

    {
        "dijeferson/gpg.nvim", -- transparent GPG encryption/decryption for *.gpg/*.asc files
        opts = {
            use_armor = true,  -- .asc output, portable for pasting into chats/email
            allow_clipboard = true,
            show_progress = "toast",
        },
    },
    {
        "icarios-dev/privymd.nvim", -- GPG-encrypted fenced blocks inside Markdown
        ft = "markdown",
        config = function()
            require("privymd").setup({
                auto_decrypt = true,
                auto_encrypt = true,
            })
        end,
    },
    {
        "matthandzel/taskwarrior.nvim", -- taskwarrior integration: edit the task db as a buffer
        config = function()
            require("taskwarrior").setup()
        end,
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
