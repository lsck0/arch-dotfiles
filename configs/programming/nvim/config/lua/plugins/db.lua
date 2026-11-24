return {
    {
        "kristijanhusak/vim-dadbod-ui",
        cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
        dependencies = {
            { "nvim-neotest/nvim-nio" },
            { "tpope/vim-dadbod" },
            { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
