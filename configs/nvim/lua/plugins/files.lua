return {
    {
        "stevearc/oil.nvim",
        config = function()
            require("oil").setup()
        end
    },
    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        dependencies = {
            "MunifTanjim/nui.nvim",
            {
                "s1n7ax/nvim-window-picker",
                version = "2.*",
                config = function()
                    require("window-picker").setup()
                end,
            }
        },
        config = function()
            vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
            require("neo-tree").setup({
                close_if_last_window = true,
                popup_border_style = "rounded",
                enable_git_status = true,
                default_component_configs = {
                    git_status = {
                        symbols = {
                            -- Change type
                            added     = "+",
                            deleted   = "-",
                            modified  = "~",
                            renamed   = "→",
                            -- Status type
                            untracked = "?",
                            ignored   = "i",
                            unstaged  = "u",
                            staged    = "s",
                            conflict  = "!",
                        },
                    },
                },
                open_files_do_not_replace_types = { "terminal", "trouble", "qf" },
                window = {
                    position = "left",
                    width = 25,
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
                        ["<"] = "prev_source",
                        [">"] = "next_source"
                    }
                },
                nesting_rules = {},
                filesystem = {
                    filtered_items = {
                        visible = false,
                        hide_dotfiles = true,
                        hide_gitignored = true,
                        always_show = { ".gitignore", ".env" }
                    },
                    follow_current_file = { enabled = true },
                    hijack_netrw_behavior = "open_default",
                    use_libuv_file_watcher = true,
                    window = {
                        mappings = {
                            ["<bs>"] = "navigate_up",
                            ["."] = "set_root",
                            ["H"] = "toggle_hidden",
                            ["/"] = "fuzzy_finder"
                        },
                        fuzzy_finder_mappings = {
                            ["<down>"] = "move_cursor_down",
                            ["<up>"] = "move_cursor_up"
                        }
                    }
                },
                buffers = {
                    follow_current_file = { enabled = true },
                    group_empty_dirs = true,
                    show_unloaded = true,
                    window = {
                        mappings = {
                            ["d"] = "buffer_delete",
                            ["<bs>"] = "navigate_up",
                            ["."] = "set_root"
                        }
                    }
                },
                git_status = {
                    window = {
                        position = "float",
                        mappings = {
                            ["A"] = "git_add_all",
                            ["gu"] = "git_unstage_file",
                            ["ga"] = "git_add_file",
                            ["gr"] = "git_revert_file",
                            ["gc"] = "git_commit",
                            ["gp"] = "git_push",
                            ["gg"] = "git_commit_and_push"
                        }
                    }
                }
            })
        end
    },
}
