return {
    {
        "kristijanhusak/vim-dadbod-ui", -- database browser UI
        lazy = false,
        dependencies = {
            { "nvim-neotest/nvim-nio" }, -- async IO library
            { "tpope/vim-dadbod",                     lazy = false }, -- database interface
            { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } }, -- SQL completion
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
