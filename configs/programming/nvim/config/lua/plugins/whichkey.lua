return {
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
            preset = "modern",
            delay = 200,
            icons = { mappings = false, separator = "::", breadcrumb = "::" },
            -- the preset's rounded corners otherwise
            win = { border = vim.opt.winborder:get() },
            -- keys as the shell's hints: [a] [esc] [c-w]
            replace = {
                key = {
                    function(key)
                        -- the trail's root is the empty key
                        return key == "" and key or "[" .. key:gsub("<(.-)>", string.lower) .. "]"
                    end,
                },
            },
            spec = {
                { "<leader>f", group = "find" },
                { "<leader>l", group = "lsp" },
                { "<leader>d", group = "debug" },
                { "<leader>n", group = "test" },
                { "<leader>j", group = "jupyter" },
                { "<leader>p", group = "profiling" },
                { "<leader>s", group = "search/replace" },
                { "<leader>g", group = "git" },
                { "<leader>k", group = "keys/secrets" },
                { "<leader>t", group = "trouble" },
                { "<leader>T", group = "taskwarrior" },
                { "<leader>Tp", group = "project" },
                { "<leader>q", group = "session" },
                { "<leader>c", group = "claude" },
                { "<leader>C", group = "comment/doc" },
                { "<leader>o", group = "github" },
                { "<leader>m", group = "orgmode" },
                { "<leader>r", group = "rest" },
            },
        },
    },
}
