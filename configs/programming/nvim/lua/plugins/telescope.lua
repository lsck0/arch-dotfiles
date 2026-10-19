local ignore_filetypes_list = {
    "%.xlsx",
    "%.jpg",
    "%.png",
    "%.webp",
    "%.pdf",
    "%.odt",
    "%.ico",
    "^vendor/",
    "/vendor/",
}

return {
    {
        "ThePrimeagen/harpoon",
        branch = "harpoon2",
        -- full specs so which-key labels them before harpoon loads
        keys = function()
            local keys = {
                {
                    "<leader>a",
                    function()
                        require("harpoon"):list():add()
                    end,
                    desc = "Harpoon: add file",
                },
                {
                    "<leader>h",
                    function()
                        local harpoon = require("harpoon")
                        harpoon.ui:toggle_quick_menu(harpoon:list())
                    end,
                    desc = "Harpoon: quick menu",
                },
            }
            for i = 1, 5 do
                table.insert(keys, {
                    "<leader>" .. i,
                    function()
                        require("harpoon"):list():select(i)
                    end,
                    desc = "Harpoon: file " .. i,
                })
            end
            return keys
        end,
        config = function()
            require("harpoon"):setup()
        end,
    },
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        dependencies = {
            {
                "nvim-telescope/telescope-fzf-native.nvim",
                build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
            },
        },
        config = function()
            local actions = require("telescope.actions")
            require("telescope").setup({
                defaults = {
                    file_ignore_patterns = ignore_filetypes_list,
                    layout_strategy = "bottom_pane",
                    layout_config = { height = 25 },
                    sorting_strategy = "ascending",
                    mappings = {
                        i = {
                            ["<C-j>"] = "move_selection_next",
                            ["<C-k>"] = "move_selection_previous",
                            ["<C-a>"] = function(prompt_bufnr)
                                actions.smart_send_to_qflist(prompt_bufnr)
                                actions.open_qflist(prompt_bufnr)
                            end,
                        },
                    },
                },
                extensions = {
                    fzf = {},
                },
            })

            require("telescope").load_extension("fzf")
        end,
    },
}
