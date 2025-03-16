local ignore_filetypes_list = {
    "%.xlsx", "%.jpg", "%.png", "%.webp", "%.pdf", "%.odt", "%.ico",
}

return {
    {
        "ThePrimeagen/harpoon",
        lazy = true,
        event = "BufRead",
        branch = "harpoon2",
        config = function()
            require("harpoon"):setup()

            local harpoon = require("harpoon")
            vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
            vim.keymap.set("n", "<leader>h", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)
            vim.keymap.set("n", "<leader>1", function() harpoon:list():select(1) end)
            vim.keymap.set("n", "<leader>2", function() harpoon:list():select(2) end)
            vim.keymap.set("n", "<leader>3", function() harpoon:list():select(3) end)
            vim.keymap.set("n", "<leader>4", function() harpoon:list():select(4) end)
            vim.keymap.set("n", "<leader>5", function() harpoon:list():select(5) end)
        end
    },
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            {
                "nvim-telescope/telescope-fzf-native.nvim",
                build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release"
            }
        },
        config = function()
            local actions = require("telescope.actions")
            require("telescope").setup({
                defaults = {
                    file_ignore_patterns = ignore_filetypes_list,
                    mappings = {
                        i = {
                            ["<C-k>"] = "move_selection_next",
                            ["<C-j>"] = "move_selection_previous",
                            ["<M-q>"] = function(prompt_bufnr)
                                actions.smart_send_to_qflist(prompt_bufnr)
                                actions.open_qflist(prompt_bufnr)
                            end
                        },
                    },
                },
                pickers = {
                    find_files = { theme = "ivy" },
                    live_grep = { theme = "ivy" },
                    grep_string = { theme = "ivy" },
                },
                extensions = {
                    fzf = {},
                }
            })

            require("telescope").load_extension("fzf")
        end
    },
}
