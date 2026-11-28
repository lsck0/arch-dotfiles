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
                -- the rest are neo-tree's defaults; <space> stays its toggle_node without nowait, so the leader works
                mappings = {
                    ["C"] = "close_all_subnodes",
                    ["z"] = "expand_all_nodes",
                    ["Z"] = "close_all_nodes",
                },
            },
            filesystem = {
                -- hidden and ignored entries show dimmed, H hides them
                filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false },
                follow_current_file = { enabled = true },
                -- the VimEnter autocmd opens it on a directory argument, so netrw's own listing never shows
                hijack_netrw_behavior = "disabled",
                use_libuv_file_watcher = true,
                components = {
                    -- the root as its directory name, ~ for home: a full path does not fit the narrow window
                    name = function(config, node, state)
                        local name = require("neo-tree.sources.common.components").name(config, node, state)
                        local tail = vim.fn.fnamemodify(node.path or "", ":~:t")
                        if node:get_depth() == 1 and node.type == "directory" and tail ~= "" then
                            name.text = tail .. name.text:sub(#node.name + 1)
                        end
                        return name
                    end,
                },
            },
        },
    },
}
