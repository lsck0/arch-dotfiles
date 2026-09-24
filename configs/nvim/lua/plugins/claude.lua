return {
    {
        "coder/claudecode.nvim",
        dependencies = { "folke/snacks.nvim" },
        cmd = {
            "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSend", "ClaudeCodeAdd",
            "ClaudeCodeDiffAccept", "ClaudeCodeDiffDeny",
        },
        keys = {
            { "<leader>cc", "<cmd>ClaudeCode<cr>",           desc = "Toggle Claude Code" },
            { "<leader>cf", "<cmd>ClaudeCodeFocus<cr>",      desc = "Focus Claude" },
            { "<leader>cs", "<cmd>ClaudeCodeSend<cr>",       mode = { "n", "v" },                   desc = "Send selection to Claude" },
            { "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>",      desc = "Add current buffer to context" },
            { "<leader>ca", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
            { "<leader>cd", "<cmd>ClaudeCodeDiffDeny<cr>",   desc = "Deny Claude diff" },
        },
        opts = {
            terminal = { split_side = "right", split_width_percentage = 0.35 },
        },
    },
}
