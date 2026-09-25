return {
    {
        "kristijanhusak/vim-dadbod-ui", -- database browser UI
        cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" }, -- load on first DBUI command
        dependencies = {
            { "nvim-neotest/nvim-nio" },                                                  -- async IO library
            { "tpope/vim-dadbod" },                                                       -- database interface (loads with UI)
            { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } }, -- SQL completion
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
    },
}
