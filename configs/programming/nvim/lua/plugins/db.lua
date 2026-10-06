return {
    {
        "kristijanhusak/vim-dadbod-ui", -- database browser UI
        cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
        dependencies = {
            { "nvim-neotest/nvim-nio" },
            { "tpope/vim-dadbod" },                                                       -- database interface
            { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } }, -- SQL completion
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
