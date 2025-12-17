return {
    {
        "kristijanhusak/vim-dadbod-ui",
        lazy = false,
        dependencies = {
            { "nvim-neotest/nvim-nio" },
            { "tpope/vim-dadbod",                     lazy = false },
            { "kristijanhusak/vim-dadbod-completion", lazy = false, ft = { "sql", "mysql", "plsql" }, lazy = true },
        },
        cmd = {
            "DBUI",
            "DBUIToggle",
            "DBUIAddConnection",
            "DBUIFindBuffer",
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
