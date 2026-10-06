local ignore_filetypes_list = {
    "%.xlsx", "%.jpg", "%.png", "%.webp", "%.pdf", "%.odt", "%.ico", "vendor"
}

return {
    {
        "ThePrimeagen/harpoon", -- quick file bookmarks
        branch = "harpoon2",
        keys = { "<leader>a", "<leader>h", "<leader>1", "<leader>2", "<leader>3", "<leader>4", "<leader>5" },
        config = function()
            -- real maps set on load, `keys` above only triggers the lazy load
            local harpoon = require("harpoon")
            harpoon:setup()

            vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end, { desc = "Harpoon: add file" })
            vim.keymap.set("n", "<leader>h", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Harpoon: quick menu" })
            vim.keymap.set("n", "<leader>1", function() harpoon:list():select(1) end, { desc = "Harpoon: file 1" })
            vim.keymap.set("n", "<leader>2", function() harpoon:list():select(2) end, { desc = "Harpoon: file 2" })
            vim.keymap.set("n", "<leader>3", function() harpoon:list():select(3) end, { desc = "Harpoon: file 3" })
            vim.keymap.set("n", "<leader>4", function() harpoon:list():select(4) end, { desc = "Harpoon: file 4" })
            vim.keymap.set("n", "<leader>5", function() harpoon:list():select(5) end, { desc = "Harpoon: file 5" })
        end
    },
    {
        "nvim-telescope/telescope.nvim", -- fuzzy finder
        cmd = "Telescope",
        dependencies = {
            {
                "nvim-telescope/telescope-fzf-native.nvim", -- fzf sorting backend
                build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release"
            }
        },
        config = function()
            local actions = require("telescope.actions")
            require("telescope").setup({
                defaults = {
                    file_ignore_patterns = ignore_filetypes_list,
                    layout_strategy = "bottom_pane",
                    layout_config = { height = 25 },
                    sorting_strategy = "ascending",
                    border = true,
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                            -- not C-q: tmux/herdr prefix
                            ["<C-a>"] = function(prompt_bufnr)
                                actions.smart_send_to_qflist(prompt_bufnr)
                                actions.open_qflist(prompt_bufnr)
                            end
                        },
                    },
                },
                pickers = {},
                extensions = {
                    fzf = {},
                }
            })

            require("telescope").load_extension("fzf")
        end
    },
}
