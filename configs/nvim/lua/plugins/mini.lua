return {
    "echasnovski/mini.nvim",
    config = function()
        require("mini.ai").setup()
        require("mini.align").setup()
        require("mini.move").setup()
        require("mini.jump").setup()
        require('mini.cursorword').setup()
        require("mini.pairs").setup()
        require("mini.splitjoin").setup()
        require("mini.surround").setup({
            mappings = {
                add = "ea",
                delete = "ed",
                replace = "er",
                find = "ef",
                find_left = "eF",
                highlight = "eh",
                update_n_lines = "en",
            }
        })
    end
}
