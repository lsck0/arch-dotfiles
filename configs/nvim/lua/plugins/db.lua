return {
    {
        "kristijanhusak/vim-dadbod-ui",
        lazy = false,
        dependencies = {
            { "nvim-neotest/nvim-nio" },
            { "tpope/vim-dadbod",                     lazy = false },
            { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
