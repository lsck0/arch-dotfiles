return {
    { "TheZoq2/neovim-auto-autoread" },       -- auto-reload changed files
    { "sitiom/nvim-numbertoggle" },           -- relative/absolute number toggle
    {
        "chrisgrieser/nvim-early-retirement", -- auto-close idle buffers
        config = function()
            require("early-retirement").setup({
                retirementAgeMins = 3,
            })
        end
    },
    {
        "https://codeberg.org/andyg/leap.nvim", -- fast cursor motion
        config = function()
            local clever_s = require("leap.user").with_traversal_keys("s", "S")
            vim.keymap.set({ "n", "x", "o" }, "s", function()
                require("leap").leap { opts = clever_s }
            end, { desc = "Leap forward" })
            vim.keymap.set({ "n", "x", "o" }, "S", function()
                require("leap").leap { opts = clever_s, backward = true }
            end, { desc = "Leap backward" })
        end
    },
    {
        "hat0uma/csvview.nvim", -- CSV column alignment
        opts = {
            parser = { comments = { "#", "//" } },
        },
    },
    { "jbyuki/venn.nvim" },       -- ASCII diagram drawing
    {
        "mg979/vim-visual-multi", -- multiple cursors
        init = function()
            vim.g.VM_maps = {
                ["Find Under"]         = "<M-n>",
                ["Find Subword Under"] = "<M-n>",
            }
        end
    },
    { "mrjones2014/smart-splits.nvim" }, -- resize/navigate splits
    {
        "nacro90/numb.nvim",             -- peek line on jump
        config = function() require("numb").setup() end
    },
    {
        "nosduco/remote-sshfs.nvim", -- browse remote files via SSH
        dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
        config = function()
            require("remote-sshfs").setup()
        end
    },
    { "sindrets/winshift.nvim" },      -- move/swap windows
    { "tpope/vim-repeat" },            -- repeat plugin actions
    { "zeioth/garbage-day.nvim" },     -- restart idle LSP clients
    {
        "ziontee113/icon-picker.nvim", -- emoji/icon picker
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
        -- Not lazy: the plugin has to own BufReadCmd/BufWriteCmd before a file
        -- is opened, otherwise the first sops file of a session shows ciphertext.
        lazy = false,
        opts = { disabled = false },
        keys = {
            { "<leader>ks", "<cmd>SopsToggle<cr>", desc = "Sops: toggle transparent en/decryption" },
        },
    },
    {
        "folke/twilight.nvim", -- dim inactive code
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
        opts = {},
    },
    { "jghauser/mkdir.nvim" }, -- auto-create parent dirs

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
        "sotte/presenting.nvim", -- turn a markdown/org/adoc file into in-editor slides
        cmd = "Presenting",      -- lazy: load only when the presentation starts
        opts = {},
        keys = {
            { "<leader>pp", "<cmd>Presenting<cr>", desc = "Present (toggle slides)" },
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
