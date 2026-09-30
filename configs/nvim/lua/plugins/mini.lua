return {
    {
        "echasnovski/mini.nvim", -- small QoL modules
        event = "VeryLazy",
        config = function()
            require("mini.ai").setup()
            require("mini.align").setup()
            require("mini.move").setup()
            require("mini.splitjoin").setup()
            require("mini.surround").setup({
                mappings = {
                    add = "gsa",
                    delete = "gsd",
                    replace = "gsr",
                    find = "gsf",
                    find_left = "gsF",
                    highlight = "gsh",
                    update_n_lines = "gsn",
                }
            })
        end
    },
}
