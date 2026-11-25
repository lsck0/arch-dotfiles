return {
    {
        "stevearc/oil.nvim",
        cmd = { "Oil" },
        opts = {},
    },
    -- the sidebar file tree: a real split, so neovide draws it like the editor (a snacks explorer is a float over a
    -- split, which neovide stacks to a second, unmatched layer of glass)
    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        cmd = "Neotree",
        dependencies = { "MunifTanjim/nui.nvim" },
        opts = {
            close_if_last_window = true,
            popup_border_style = "single",
            enable_git_status = true,
            open_files_do_not_replace_types = { "terminal", "trouble", "qf" },
            window = {
                position = "left",
                width = 24,
                mapping_options = { noremap = true, nowait = true },
                mappings = {
                    ["<space>"] = "toggle_node",
                    ["S"] = "open_split",
                    ["s"] = "open_vsplit",
                    ["C"] = "close_all_subnodes",
                    ["z"] = "expand_all_nodes",
                    ["Z"] = "close_all_nodes",
                    ["a"] = "add",
                    ["A"] = "add_directory",
                    ["d"] = "delete",
                    ["r"] = "rename",
                    ["y"] = "copy_to_clipboard",
                    ["x"] = "cut_to_clipboard",
                    ["p"] = "paste_from_clipboard",
                    ["c"] = "copy",
                    ["m"] = "move",
                    ["q"] = "close_window",
                    ["R"] = "refresh",
                    ["?"] = "show_help",
                },
            },
            filesystem = {
                -- hidden and ignored entries show dimmed, H hides them
                filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false },
                follow_current_file = { enabled = true },
                -- the VimEnter autocmd opens it on a directory argument, so netrw's own listing never shows
                hijack_netrw_behavior = "disabled",
                use_libuv_file_watcher = true,
                window = {
                    mappings = {
                        ["<bs>"] = "navigate_up",
                        ["."] = "set_root",
                        ["H"] = "toggle_hidden",
                        ["/"] = "fuzzy_finder",
                    },
                },
            },
        },
    },
}
